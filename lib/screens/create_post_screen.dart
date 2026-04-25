import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import 'add_spot_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    required this.repository,
    this.initialSpotId,
  });

  final SpotRepository repository;
  final String? initialSpotId;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxUploadDimension = 1280;
  static const int _jpegUploadQuality = 68;
  static const int _jpegSecondPassQuality = 60;
  static const int _skipCompressionMaxBytes = 1200 * 1024;
  static const int _targetMaxCompressedBytes = 1000 * 1024;

  final _captionController = TextEditingController();
  final _picker = ImagePicker();
  final MapController _spotPreviewMapController = MapController();

  late Future<List<SpotFeedItem>> _spotsFuture;

  bool _isSubmitting = false;
  String _visibility = 'exact';
  SpotFeedItem? _selectedSpotItem;
  String? _errorMessage;
  String? _resultStatus;
  String? _submitStatus;
  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoExtension;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  Timer? _uploadStatusTimer;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Create Post open start');
    perfLogFrame('Create Post', _openStopwatch);
    _spotsFuture = _loadSpots();
  }

  @override
  void dispose() {
    _uploadStatusTimer?.cancel();
    _captionController.dispose();
    super.dispose();
  }

  void _setSubmitStatus(String? value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _submitStatus = value;
    });
  }

  Future<List<SpotFeedItem>> _loadSpots() async {
    final stopwatch = Stopwatch()..start();
    final items = await widget.repository.fetchVisibleSpots(
      includeScores: true,
      includeWeather: false,
    );
    stopwatch.stop();
    perfLog(
      'Create Post preparation spots ready in ${stopwatch.elapsedMilliseconds}ms count=${items.length}',
    );
    final initialSpotId = widget.initialSpotId?.trim();
    if (initialSpotId != null &&
        initialSpotId.isNotEmpty &&
        _selectedSpotItem == null) {
      SpotFeedItem? matchedSpot;
      for (final item in items) {
        if (item.spot.id == initialSpotId) {
          matchedSpot = item;
          break;
        }
      }
      if (matchedSpot != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _selectedSpotItem = matchedSpot;
          });
          _focusSelectedSpotPreview();
        });
      }
    }
    return items;
  }

  Future<void> _pickPhoto() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (file == null) {
        return;
      }

      final preparedImage = await _prepareImageForUpload(file);
      if (!mounted) {
        return;
      }

      setState(() {
        _photoBytes = preparedImage.bytes;
        _photoName = file.name;
        _photoExtension = preparedImage.extension;
        _errorMessage = null;
      });
      stopwatch.stop();
      perfLog(
        'Create Post image pick complete in ${stopwatch.elapsedMilliseconds}ms bytes=${preparedImage.bytes.length}',
      );
    } catch (error) {
      stopwatch.stop();
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Görsel seçilemedi: $error';
      });
    }
  }

  void _removePhoto() {
    setState(() {
      _photoBytes = null;
      _photoName = null;
      _photoExtension = null;
    });
  }

  Future<_PreparedUploadImage> _prepareImageForUpload(XFile file) async {
    final originalBytes = await file.readAsBytes();
    verboseDebugLog(
      '[CREATE_POST_FLOW] image original bytes=${originalBytes.length}',
    );
    final originalExtension = _extensionFromName(file.name) ?? 'jpg';
    final decodedSize = await _decodeImageSize(originalBytes);
    final originalWidth = decodedSize?.$1 ?? 0;
    final originalHeight = decodedSize?.$2 ?? 0;
    final needsResize = originalWidth > _maxUploadDimension ||
        originalHeight > _maxUploadDimension;
    final isJpeg = originalExtension == 'jpg' || originalExtension == 'jpeg';
    final shouldCompress =
        originalBytes.length > _skipCompressionMaxBytes || needsResize || !isJpeg;

    if (!shouldCompress) {
      verboseDebugLog(
        '[CREATE_POST_FLOW] image compressed bytes=${originalBytes.length}',
      );
      verboseDebugLog('[CREATE_POST_FLOW] image compression duration=0ms');
      return _PreparedUploadImage(
        bytes: originalBytes,
        extension: originalExtension,
      );
    }

    final compressionStopwatch = Stopwatch()..start();
    Uint8List candidateBytes = Uint8List.fromList(
      await FlutterImageCompress.compressWithList(
      originalBytes,
      minWidth: _maxUploadDimension,
      minHeight: _maxUploadDimension,
      quality: _jpegUploadQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
      ),
    );

    if (candidateBytes.length > _targetMaxCompressedBytes) {
      final secondPassBytes = await FlutterImageCompress.compressWithList(
        candidateBytes,
        minWidth: _maxUploadDimension,
        minHeight: _maxUploadDimension,
        quality: _jpegSecondPassQuality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (secondPassBytes.isNotEmpty &&
          secondPassBytes.length < candidateBytes.length) {
        candidateBytes = Uint8List.fromList(secondPassBytes);
      }
    }
    compressionStopwatch.stop();

    final effectiveBytes = candidateBytes.isNotEmpty &&
            candidateBytes.length < originalBytes.length
        ? candidateBytes
        : originalBytes;
    final effectiveExtension =
        identical(effectiveBytes, originalBytes) ? originalExtension : 'jpg';

    verboseDebugLog(
      '[CREATE_POST_FLOW] image compressed bytes=${effectiveBytes.length}',
    );
    verboseDebugLog(
      '[CREATE_POST_FLOW] image compression duration=${compressionStopwatch.elapsedMilliseconds}ms',
    );

    return _PreparedUploadImage(
      bytes: effectiveBytes,
      extension: effectiveExtension,
    );
  }

  Future<(int, int)?> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      image.dispose();
      return (width, height);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAddSpot() async {
    final createdSpot = await Navigator.of(context).push<FishingSpot>(
      MaterialPageRoute<FishingSpot>(
        builder: (_) => AddSpotScreen(repository: widget.repository),
      ),
    );

    if (!mounted || createdSpot == null) {
      return;
    }

    final refreshedSpots = await _loadSpots();
    if (!mounted) {
      return;
    }

    setState(() {
      _spotsFuture = Future<List<SpotFeedItem>>.value(refreshedSpots);
      _selectedSpotItem = refreshedSpots
          .where((item) => item.spot.id == createdSpot.id)
          .cast<SpotFeedItem?>()
          .firstWhere(
            (item) => item != null,
            orElse: () => null,
          );
      _errorMessage = null;
    });
    _focusSelectedSpotPreview();
  }

  void _focusSelectedSpotPreview() {
    final selectedSpot = _selectedSpotItem?.spot;
    if (selectedSpot == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _spotPreviewMapController.move(
        LatLng(selectedSpot.latitude, selectedSpot.longitude),
        14.6,
      );
    });
  }

  Future<void> _submit() async {
    final selectedSpotItem = _selectedSpotItem;
    if (selectedSpotItem == null) {
      setState(() {
        _errorMessage = 'Bir mera seç.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _submitStatus = 'Post hazırlanıyor...';
    });

    final stopwatch = Stopwatch()..start();
    verboseDebugLog('[CREATE_POST_FLOW] submit start');
    try {
      _uploadStatusTimer?.cancel();
      if ((_photoBytes?.isNotEmpty ?? false)) {
        _uploadStatusTimer = Timer(const Duration(milliseconds: 700), () {
          if (!mounted || !_isSubmitting) {
            return;
          }
          _setSubmitStatus('Fotoğraf yükleniyor...');
        });
      }
      verboseDebugLog('[CREATE_POST_FLOW] repository createPost start');
      final repositoryStopwatch = Stopwatch()..start();
      final postId = await widget.repository.createPost(
        caption: _captionController.text.trim(),
        visibility: _visibility,
        spot: selectedSpotItem.spot,
        photoBytes: _photoBytes,
        photoExtension: _photoExtension,
      );
      repositoryStopwatch.stop();
      verboseDebugLog(
        '[CREATE_POST_FLOW] repository createPost end duration=${repositoryStopwatch.elapsedMilliseconds}ms',
      );
      verboseDebugLog('[CREATE_POST_FLOW] post insert success postId=$postId');

      if (!mounted) {
        return;
      }

      stopwatch.stop();
      perfLog(
        'Create Post submit complete in ${stopwatch.elapsedMilliseconds}ms',
      );
      verboseDebugLog('[CREATE_POST_FLOW] post-create refresh/navigation start');
      _uploadStatusTimer?.cancel();
      _setSubmitStatus('Paylaşım tamamlanıyor...');
      if (_isSubmitting) {
        setState(() {
          _isSubmitting = false;
        });
      }
      verboseDebugLog('[CREATE_POST_FLOW] navigator pop attempted');
      Navigator.of(context).pop(true);
      verboseDebugLog('[CREATE_POST_FLOW] navigator pop success');
      verboseDebugLog(
        '[CREATE_POST_FLOW] post-create refresh/navigation end totalSubmitDuration=${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (error, st) {
      stopwatch.stop();
      if (!mounted) {
        return;
      }
      _uploadStatusTimer?.cancel();
      debugPrint('[CREATE_POST] submit failure error=$error');
      debugPrint('[CREATE_POST] submit stack=$st');

      setState(() {
        _errorMessage =
            'Post paylaşılırken bir hata oluştu. Lütfen tekrar deneyin.';
        _submitStatus = null;
      });
    } finally {
      verboseDebugLog('[CREATE_POST_FLOW] submit finally start');
      _uploadStatusTimer?.cancel();
      if (mounted) {
        if (_isSubmitting) {
          setState(() {
            _isSubmitting = false;
          });
        }
        if (_submitStatus != null) {
          setState(() {
            _submitStatus = null;
          });
        }
        verboseDebugLog('[CREATE_POST_FLOW] submit finally isSubmitting=false');
      } else {
        verboseDebugLog(
          '[CREATE_POST_FLOW] submit finally skipped isSubmitting reset because mounted=false',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
        'Create Post structure ready at ${_openStopwatch.elapsedMilliseconds}ms',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Post paylaş')),
      body: FutureBuilder<List<SpotFeedItem>>(
        future: _spotsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Meralar yüklenemedi: ${snapshot.error}'),
              ),
            );
          }

          final spots = snapshot.data ?? const <SpotFeedItem>[];
          final hasSpotSelection = _selectedSpotItem != null;
          final selectedSpot = _selectedSpotItem?.spot;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mera katkısı',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mevcut meraya not, sonuç ve yöntem ekle. Aynı yere yeni pin açmak yerine katkı bırak.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _ComposerPhotoCard(
                              photoBytes: _photoBytes,
                              photoName: _photoName,
                              isSubmitting: _isSubmitting,
                              onPickPhoto: _pickPhoto,
                              onRemovePhoto: _removePhoto,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Mera',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Paylaşımı ilişkilendirmek için bir mera seç.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (spots.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer
                                      .withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  'Paylaşım oluşturmadan önce en az bir mera ekleyin.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 248),
                                child: ScrollConfiguration(
                                  behavior: const MaterialScrollBehavior()
                                      .copyWith(scrollbars: false),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: spots.length,
                                    itemBuilder: (context, index) {
                                      final item = spots[index];
                                      return _SpotSelectionCard(
                                        item: item,
                                        selected: item.spot.id ==
                                            _selectedSpotItem?.spot.id,
                                        onTap: _isSubmitting
                                            ? null
                                            : () {
                                                setState(() {
                                                  _selectedSpotItem = item;
                                                  _errorMessage = null;
                                                });
                                                _focusSelectedSpotPreview();
                                              },
                                      );
                                    },
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            Text(
                              'Harita önizleme',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SpotPreviewMap(
                              mapController: _spotPreviewMapController,
                              selectedSpot: selectedSpot,
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow
                                    .withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mera listede yok mu?',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Önce yeni merayı ekleyip sonra paylaşımını ilişkilendirebilirsin.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                    onPressed:
                                        _isSubmitting ? null : _openAddSpot,
                                    child: const Text('+ Yeni mera ekle'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Sonuç',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _SelectionChip(
                                  label: 'İş yaptı',
                                  selected: _resultStatus == 'success',
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(() {
                                            _resultStatus =
                                                _resultStatus == 'success'
                                                    ? null
                                                    : 'success';
                                          }),
                                ),
                                _SelectionChip(
                                  label: 'Boş geçti',
                                  selected: _resultStatus == 'empty',
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(() {
                                            _resultStatus =
                                                _resultStatus == 'empty'
                                                    ? null
                                                    : 'empty';
                                          }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _captionController,
                              minLines: 4,
                              maxLines: 6,
                              maxLength: 280,
                              decoration: const InputDecoration(
                                hintText:
                                    'Ne denedin, ne işe yaradı, kısa not bırak. (isteğe bağlı)',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Kimler görebilir?',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _VisibilityChip(
                                  label: 'Herkese açık',
                                  selected: _visibility == 'exact',
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(() {
                                            _visibility = 'exact';
                                          }),
                                ),
                                _VisibilityChip(
                                  label: 'Takipçiler',
                                  selected: _visibility == 'approx',
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(() {
                                            _visibility = 'approx';
                                          }),
                                ),
                                _VisibilityChip(
                                  label: 'Gizli',
                                  selected: _visibility == 'private',
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(() {
                                            _visibility = 'private';
                                          }),
                                ),
                              ],
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _isSubmitting ||
                                      spots.isEmpty ||
                                      !hasSpotSelection
                                  ? null
                                  : _submit,
                              child: Text(
                                _isSubmitting
                                    ? (_submitStatus ?? 'Paylaşılıyor...')
                                    : 'Paylaş',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _extensionFromName(String? name) {
    if (name == null || !name.contains('.')) {
      return null;
    }

    return name.split('.').last.toLowerCase();
  }
}

class _SpotPreviewMap extends StatelessWidget {
  const _SpotPreviewMap({
    required this.mapController,
    required this.selectedSpot,
  });

  final MapController mapController;
  final FishingSpot? selectedSpot;

  @override
  Widget build(BuildContext context) {
    final center = selectedSpot == null
        ? const LatLng(40.375, 28.883)
        : LatLng(selectedSpot!.latitude, selectedSpot!.longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 196,
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: selectedSpot == null ? 10.8 : 14.6,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'fishing_app',
            ),
            if (selectedSpot != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 54,
                    height: 54,
                    child: const IgnorePointer(
                      child: Icon(
                        Icons.place_rounded,
                        size: 38,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerPhotoCard extends StatelessWidget {
  const _ComposerPhotoCard({
    required this.photoBytes,
    required this.photoName,
    required this.isSubmitting,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final Uint8List? photoBytes;
  final String? photoName;
  final bool isSubmitting;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: isSubmitting ? null : onPickPhoto,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.all(16),
          child: photoBytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '+ Fotoğraf ekle',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(
                        photoBytes!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            photoName ?? 'Seçilen fotoğraf',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: isSubmitting ? null : onRemovePhoto,
                          child: const Text('Kaldır'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.tonal(
                          onPressed: isSubmitting ? null : onPickPhoto,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Değiştir'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PreparedUploadImage {
  const _PreparedUploadImage({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}

class _SpotSelectionCard extends StatelessWidget {
  const _SpotSelectionCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SpotFeedItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = item.score?.scoreValue;
    final region = item.spot.region?.trim();

    return Material(
      color: selected
          ? AppColors.primarySoft.withValues(alpha: 0.92)
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.spot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (region != null && region.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        region,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (score != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _scoreSoftColor(score),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Skor $score',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _scoreColor(score),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppColors.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 80) {
      return AppColors.success;
    }
    if (score >= 50) {
      return AppColors.warning;
    }
    return AppColors.danger;
  }

  Color _scoreSoftColor(int score) {
    if (score >= 80) {
      return AppColors.successSoft;
    }
    if (score >= 50) {
      return AppColors.warningSoft;
    }
    return AppColors.dangerSoft;
  }
}

class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = selected ? AppColors.primarySoft : AppColors.card;
    final foregroundColor =
        selected ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _VisibilityChip(
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
}
