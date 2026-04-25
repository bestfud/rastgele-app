import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/browser_geolocation.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import 'create_post_screen.dart';

class AddSpotScreen extends StatefulWidget {
  const AddSpotScreen({
    super.key,
    required this.repository,
    this.initialLatitude,
    this.initialLongitude,
  });

  final SpotRepository repository;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen> {
  static const LatLng _fallbackCenter = LatLng(40.375, 28.883);

  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  final _nameController = TextEditingController();
  final _regionController = TextEditingController();
  final _waterTypeController = TextEditingController();

  bool _isSubmitting = false;
  bool _isResolvingCurrentLocation = false;
  bool _isResolvingLocationLabel = false;
  bool _animateSelectedMarker = false;
  String _visibility = 'private';
  String? _errorMessage;
  String? _selectedLocationLabel;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  int _locationLabelRequestId = 0;

  LatLng? _currentLocation;
  LatLng? _selectedLatLng;
  late LatLng _mapCenter;
  final double _mapZoom = 13.4;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Add Spot open start');
    perfLogFrame('Add Spot', _openStopwatch);

    final initialSelection = _initialSelectionFromWidget();
    _selectedLatLng = initialSelection;
    _currentLocation = initialSelection;
    _mapCenter = initialSelection ?? _fallbackCenter;

    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    _waterTypeController.dispose();
    super.dispose();
  }

  LatLng? _initialSelectionFromWidget() {
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _isResolvingCurrentLocation = true;
    });

    try {
      final coordinates = await getBrowserCoordinates();
      if (!mounted || coordinates == null) {
        return;
      }

      final currentLocation = LatLng(
        coordinates.latitude,
        coordinates.longitude,
      );
      setState(() {
        _currentLocation = currentLocation;
        _selectedLatLng ??= currentLocation;
        _mapCenter = _selectedLatLng ?? currentLocation;
        _errorMessage = null;
      });
      _moveMap(_mapCenter);
      if (_selectedLatLng != null) {
        _resolveSelectedLocationLabel(_selectedLatLng!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingCurrentLocation = false;
        });
      }
    }
  }

  void _moveMap(LatLng target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _mapController.move(target, _mapZoom);
    });
  }

  void _selectPoint(LatLng point) {
    setState(() {
      _selectedLatLng = point;
      _errorMessage = null;
      _mapCenter = point;
      _animateSelectedMarker = true;
    });
    _resolveSelectedLocationLabel(point);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _animateSelectedMarker = false;
      });
    });
  }

  void _selectCurrentLocation() {
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      setState(() {
        _errorMessage =
            'Bulunduğun konum alınamadı. Haritadan bir nokta seçebilirsin.';
      });
      return;
    }

    _selectPoint(currentLocation);
    _moveMap(currentLocation);
  }

  Future<void> _resolveSelectedLocationLabel(LatLng point) async {
    final requestId = ++_locationLabelRequestId;
    setState(() {
      _isResolvingLocationLabel = true;
      _selectedLocationLabel = _fallbackLocationLabel(point);
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '14',
        'accept-language': 'tr',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'fishing_app/0.1 (spot-picker)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return;
      }

      final label = _bestReverseGeocodeLabel(payload);
      if (!mounted || requestId != _locationLabelRequestId) {
        return;
      }

      setState(() {
        _selectedLocationLabel = label ?? _fallbackLocationLabel(point);
      });
    } catch (_) {
      if (!mounted || requestId != _locationLabelRequestId) {
        return;
      }

      setState(() {
        _selectedLocationLabel = _fallbackLocationLabel(point);
      });
    } finally {
      if (mounted && requestId == _locationLabelRequestId) {
        setState(() {
          _isResolvingLocationLabel = false;
        });
      }
    }
  }

  String? _bestReverseGeocodeLabel(Map<String, dynamic> payload) {
    final address = payload['address'];
    if (address is Map<String, dynamic>) {
      final locality = _firstNonEmpty(<String?>[
        address['suburb']?.toString(),
        address['neighbourhood']?.toString(),
        address['quarter']?.toString(),
        address['village']?.toString(),
        address['town']?.toString(),
        address['city_district']?.toString(),
      ]);
      final region = _firstNonEmpty(<String?>[
        address['city']?.toString(),
        address['town']?.toString(),
        address['municipality']?.toString(),
        address['state_district']?.toString(),
        address['state']?.toString(),
      ]);
      final country = _firstNonEmpty(<String?>[
        address['country']?.toString(),
      ]);

      final parts = [
        if (locality != null) locality,
        if (region != null && region != locality) region,
        if (country != null) country,
      ];
      if (parts.isNotEmpty) {
        return parts.join(', ');
      }
    }

    final displayName = payload['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName.split(',').take(3).join(', ').trim();
    }

    return null;
  }

  String _fallbackLocationLabel(LatLng point) {
    final region = _regionController.text.trim();
    if (region.isNotEmpty) {
      return region;
    }

    return '${point.latitude.toStringAsFixed(4)}, '
        '${point.longitude.toStringAsFixed(4)}';
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedLatLng = _selectedLatLng;
    if (selectedLatLng == null) {
      setState(() {
        _errorMessage = 'Lütfen haritadan bir konum seç';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final nearbyMatches = await widget.repository.findNearbySpotMatches(
        latitude: selectedLatLng.latitude,
        longitude: selectedLatLng.longitude,
      );
      if (!mounted) {
        return;
      }

      if (nearbyMatches.isNotEmpty) {
        setState(() {
          _isSubmitting = false;
        });
        final resolution = await _showDuplicateSpotPrompt(nearbyMatches);
        if (!mounted) {
          return;
        }
        if (resolution?.action == _DuplicateSpotResolution.contribute) {
          final selectedMatch = nearbyMatches.firstWhere(
            (item) => item.spot.id == resolution!.selectedSpotId,
            orElse: () => nearbyMatches.first,
          );
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => CreatePostScreen(
                repository: widget.repository,
                initialSpotId: selectedMatch.spot.id,
              ),
            ),
          );
          if (!mounted) {
            return;
          }
          if (created == true) {
            Navigator.of(context).pop(selectedMatch.spot);
          }
          return;
        }
        if (resolution?.action != _DuplicateSpotResolution.forceCreate) {
          return;
        }

        setState(() {
          _isSubmitting = true;
        });
      }

      final spot = await widget.repository.addFishingSpot(
        name: _nameController.text.trim(),
        latitude: selectedLatLng.latitude,
        longitude: selectedLatLng.longitude,
        region: _regionController.text.trim(),
        waterType: _waterTypeController.text.trim(),
        visibility: _visibility,
      );

      if (!mounted) {
        return;
      }

      stopwatch.stop();
      perfLog('Add Spot submit complete in ${stopwatch.elapsedMilliseconds}ms');
      Navigator.of(context).pop(spot);
    } catch (error) {
      stopwatch.stop();
      setState(() {
        _errorMessage = _friendlySaveError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<_DuplicateSpotChoice?> _showDuplicateSpotPrompt(
    List<NearbySpotMatch> matches,
  ) {
    var selectedSpotId = matches.first.spot.id;
    return showModalBottomSheet<_DuplicateSpotChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bu bölgede zaten bir mera var',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aynı yere yeni pin açmak yerine mevcut mera sayfasına katkı eklemek varsayılan akış. Yakın eşleşmeler:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final match = matches[index];
                          final isSelected =
                              selectedSpotId == match.spot.id.trim();
                          return _NearbySpotMatchCard(
                            match: match,
                            selected: isSelected,
                            onTap: () {
                              setModalState(() {
                                selectedSpotId = match.spot.id;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(
                        _DuplicateSpotChoice(
                          action: _DuplicateSpotResolution.contribute,
                          selectedSpotId: selectedSpotId,
                        ),
                      ),
                      child: const Text('Bu meraya katkı yap'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(
                        _DuplicateSpotChoice(
                          action: _DuplicateSpotResolution.forceCreate,
                          selectedSpotId: selectedSpotId,
                        ),
                      ),
                      child: const Text('Yine de yeni mera oluştur'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _friendlySaveError(Object error) {
    if (error is PostgrestException) {
      return 'Mera kaydedilemedi. İzinler veya profil bilgisi kontrol edilmeli.';
    }

    final message = error.toString();
    if (message.contains('Oturum açmış kullanıcı bulunamadı')) {
      return 'Mera kaydedilemedi. Lütfen tekrar giriş yapın.';
    }
    if (message.contains('profil')) {
      return 'Mera kaydedilemedi. Profil bilgisi doğrulanamadı.';
    }

    return 'Mera kaydedilemedi. Lütfen tekrar deneyin.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
        'Add Spot structure ready at ${_openStopwatch.elapsedMilliseconds}ms',
      );
    }

    final selectedLatLng = _selectedLatLng;
    final currentLocation = _currentLocation;
    final hasSelection = selectedLatLng != null;
    final mapHelperText = _isResolvingCurrentLocation
        ? 'Konumun bulunuyor...'
        : hasSelection
            ? '📍 Konum seçildi • Haritada değiştirilebilir'
            : 'Haritaya dokunarak mera noktasını seç';
    final saveButtonOpacity = hasSelection && !_isSubmitting ? 1.0 : 0.56;

    return Scaffold(
      appBar: AppBar(title: const Text('Mera Ekle')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
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
                            'Mera detayları',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Haritadan bir konum seç, sonra mera bilgilerini tamamla.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow
                                  .withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              mapHelperText,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.86),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              height: 280,
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _mapCenter,
                                  initialZoom: _mapZoom,
                                  onTap: (tapPosition, point) {
                                    _selectPoint(point);
                                  },
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.all &
                                        ~InteractiveFlag.rotate,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.fishing.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      if (currentLocation != null)
                                        Marker(
                                          point: currentLocation,
                                          width: 24,
                                          height: 24,
                                          child: IgnorePointer(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: AppColors.primary,
                                                  width: 2.2,
                                                ),
                                                boxShadow: appSoftShadow(
                                                  AppColors.primary,
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration:
                                                      const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (selectedLatLng != null)
                                        Marker(
                                          point: selectedLatLng,
                                          width: 54,
                                          height: 54,
                                          child: IgnorePointer(
                                            child: AnimatedScale(
                                              scale: _animateSelectedMarker
                                                  ? 0.9
                                                  : 1.0,
                                              duration: const Duration(
                                                milliseconds: 150,
                                              ),
                                              curve: Curves.easeOut,
                                              child: const Icon(
                                                Icons.place_rounded,
                                                size: 38,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _isResolvingCurrentLocation
                                  ? null
                                  : _selectCurrentLocation,
                              icon: const Text('📍'),
                              label: const Text('Bulunduğum yeri seç'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _nameController,
                            decoration:
                                const InputDecoration(labelText: 'Mera adı'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Bir mera adı gir.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _regionController,
                            decoration: const InputDecoration(
                              labelText: 'Bölge (isteğe bağlı)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _waterTypeController,
                            decoration: const InputDecoration(
                              labelText: 'Su türü (isteğe bağlı)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _visibility,
                            decoration:
                                const InputDecoration(labelText: 'Görünürlük'),
                            items: const [
                              DropdownMenuItem(
                                value: 'private',
                                child: Text('Gizli'),
                              ),
                              DropdownMenuItem(
                                value: 'public',
                                child: Text('Açık'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _visibility = value;
                                });
                              }
                            },
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
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
                          const SizedBox(height: 16),
                          if (hasSelection) ...[
                            Row(
                              children: [
                                Text(
                                  '📍',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _isResolvingLocationLabel
                                        ? 'Konum adı yükleniyor...'
                                        : (_selectedLocationLabel ??
                                            _fallbackLocationLabel(
                                              selectedLatLng,
                                            )),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.88),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            hasSelection
                                ? 'Seçilen konum hazır'
                                : 'Konum seçilmedi',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: hasSelection
                                  ? AppColors.primary
                                  : colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.82),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: saveButtonOpacity,
                            child: FilledButton(
                              onPressed: _isSubmitting || !hasSelection
                                  ? null
                                  : _submit,
                              child: Text(
                                _isSubmitting
                                    ? 'Kaydediliyor...'
                                    : 'Merayı kaydet',
                              ),
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
        ),
      ),
    );
  }
}

enum _DuplicateSpotResolution { contribute, forceCreate }

class _DuplicateSpotChoice {
  const _DuplicateSpotChoice({
    required this.action,
    required this.selectedSpotId,
  });

  final _DuplicateSpotResolution action;
  final String selectedSpotId;
}

class _NearbySpotMatchCard extends StatelessWidget {
  const _NearbySpotMatchCard({
    required this.match,
    required this.selected,
    required this.onTap,
  });

  final NearbySpotMatch match;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.8)
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
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
                      match.spot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${match.distanceLabel} • ${match.contributionCount} katkı',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (match.scoreValue != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${match.scoreValue}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
