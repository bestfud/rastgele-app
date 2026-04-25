import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.repository,
    required this.profile,
  });

  final SpotRepository repository;
  final AppProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  late final TextEditingController _instagramController;
  late final TextEditingController _xController;
  late final TextEditingController _youtubeController;
  late final TextEditingController _tiktokController;

  bool _isSaving = false;
  bool _isPickingAvatar = false;
  bool _isPickingCover = false;
  String? _errorMessage;
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;
  String? _avatarExtension;
  String? _coverExtension;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.profile.displayName);
    _usernameController =
        TextEditingController(text: widget.profile.username ?? '');
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _locationController =
        TextEditingController(text: widget.profile.city ?? '');
    _websiteController =
        TextEditingController(text: widget.profile.websiteUrl ?? '');
    _instagramController =
        TextEditingController(text: widget.profile.instagram ?? '');
    _xController = TextEditingController(text: widget.profile.xHandle ?? '');
    _youtubeController =
        TextEditingController(text: widget.profile.youtube ?? '');
    _tiktokController =
        TextEditingController(text: widget.profile.tiktok ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    _instagramController.dispose();
    _xController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({
    required bool isCover,
  }) async {
    setState(() {
      if (isCover) {
        _isPickingCover = true;
      } else {
        _isPickingAvatar = true;
      }
      _errorMessage = null;
    });

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (file == null) {
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }

      setState(() {
        if (isCover) {
          _coverBytes = bytes;
          _coverExtension = _extensionFromName(file.name);
        } else {
          _avatarBytes = bytes;
          _avatarExtension = _extensionFromName(file.name);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Görsel seçilemedi: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isCover) {
            _isPickingCover = false;
          } else {
            _isPickingAvatar = false;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      String? avatarUrl = widget.profile.avatarUrl;
      String? coverUrl = widget.profile.coverUrl;
      if (_avatarBytes != null) {
        avatarUrl = await widget.repository.uploadProfileImage(
          bytes: _avatarBytes!,
          kind: 'avatar',
          extension: _avatarExtension,
        );
      }
      if (_coverBytes != null) {
        coverUrl = await widget.repository.uploadProfileImage(
          bytes: _coverBytes!,
          kind: 'cover',
          extension: _coverExtension,
        );
      }

      final updated = await widget.repository.updateProfile(
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        city: _locationController.text.trim(),
        websiteUrl: _websiteController.text.trim(),
        instagram: _instagramController.text.trim(),
        xHandle: _xController.text.trim(),
        youtube: _youtubeController.text.trim(),
        tiktok: _tiktokController.text.trim(),
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
      );
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil güncellendi')),
      );
      Navigator.of(context).pop(updated);
    } on StorageException catch (error) {
      perfLog('[profile-save] storage upload error=$error');
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Fotoğraf yüklenemedi. Lütfen tekrar dene.';
      });
    } catch (error) {
      perfLog('[profile-save] edit screen caught error=$error');
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Profil kaydedilemedi. Lütfen tekrar dene.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 80,
        leading: TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).maybePop(),
          child: const Text('İptal'),
        ),
        title: Text(
          'Profili düzenle',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '...' : 'Kaydet'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
                children: [
                  _PhotoSection(
                    avatarUrl: widget.profile.avatarUrl,
                    avatarBytes: _avatarBytes,
                    coverUrl: widget.profile.coverUrl,
                    coverBytes: _coverBytes,
                    isPickingAvatar: _isPickingAvatar,
                    isPickingCover: _isPickingCover,
                    onPickAvatar: () => _pickImage(isCover: false),
                    onPickCover: () => _pickImage(isCover: true),
                  ),
                  const SizedBox(height: 20),
                  _FormSection(
                    title: 'Profil bilgileri',
                    children: [
                      TextFormField(
                        controller: _displayNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'İsim',
                          hintText: 'Görünen adın',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'İsim zorunludur.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı adı',
                          hintText: '@kullaniciadi',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _bioController,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 280,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'Kendinden kısaca bahset',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _locationController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Konum',
                          hintText: 'Şehir veya bölge',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _websiteController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Website',
                          hintText: 'site.com veya tam bağlantı',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _FormSection(
                    title: 'Sosyal bağlantılar',
                    children: [
                      TextFormField(
                        controller: _instagramController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Instagram',
                          hintText: '@kullanici veya tam bağlantı',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _xController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'X',
                          hintText: '@kullanici veya tam bağlantı',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _youtubeController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'YouTube',
                          hintText: 'Kanal adı veya tam bağlantı',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _tiktokController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'TikTok',
                          hintText: '@kullanici veya tam bağlantı',
                        ),
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _extensionFromName(String? name) {
    final value = name?.trim() ?? '';
    if (value.isEmpty || !value.contains('.')) {
      return null;
    }

    return value.split('.').last;
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.avatarUrl,
    required this.avatarBytes,
    required this.coverUrl,
    required this.coverBytes,
    required this.isPickingAvatar,
    required this.isPickingCover,
    required this.onPickAvatar,
    required this.onPickCover,
  });

  final String? avatarUrl;
  final Uint8List? avatarBytes;
  final String? coverUrl;
  final Uint8List? coverBytes;
  final bool isPickingAvatar;
  final bool isPickingCover;
  final VoidCallback onPickAvatar;
  final VoidCallback onPickCover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fotoğraflar',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: isPickingCover ? null : onPickCover,
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                height: 148,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: theme.colorScheme.surfaceContainerHigh,
                  image: _buildImage(
                    bytes: coverBytes,
                    url: coverUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.06),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Kapak fotoğrafını değiştir',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isPickingCover)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  onTap: isPickingAvatar ? null : onPickAvatar,
                  borderRadius: BorderRadius.circular(999),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    backgroundImage: _buildProvider(
                      bytes: avatarBytes,
                      url: avatarUrl,
                    ),
                    child:
                        avatarBytes == null && (avatarUrl ?? '').trim().isEmpty
                            ? Icon(
                                Icons.person_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 28,
                              )
                            : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profil fotoğrafı',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dokunup galeriden seç',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPickingAvatar)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DecorationImage? _buildImage({
    required Uint8List? bytes,
    required String? url,
    required BoxFit fit,
  }) {
    final provider = _buildProvider(bytes: bytes, url: url);
    if (provider == null) {
      return null;
    }

    return DecorationImage(
      image: provider,
      fit: fit,
    );
  }

  ImageProvider<Object>? _buildProvider({
    required Uint8List? bytes,
    required String? url,
  }) {
    if (bytes != null) {
      return MemoryImage(bytes);
    }

    final trimmedUrl = url?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      return NetworkImage(trimmedUrl);
    }

    return null;
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
