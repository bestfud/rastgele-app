import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import '../widgets/social_post_card.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart';
import 'post_detail_screen.dart';
import 'post_location_preview_screen.dart';
import 'spot_detail_screen.dart';

void _noopProfileCallback() {}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.repository,
    required this.selectedIndex,
    required this.refreshSeed,
    required this.onSelectTab,
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
    required this.onOpenSearch,
    required this.onOpenLocation,
    this.onOpenMessages = _noopProfileCallback,
    this.onOpenNotifications = _noopProfileCallback,
    this.onDirectMessageStateChanged = _noopProfileCallback,
    this.unreadMessageCount = 0,
    this.unreadNotificationCount = 0,
    required this.onLogout,
    this.profileId,
    this.showShellChrome = true,
    this.shellAvatarUrl,
    this.shellAvatarLabel,
  });

  final SpotRepository repository;
  final int selectedIndex;
  final int refreshSeed;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocation;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenNotifications;
  final VoidCallback onDirectMessageStateChanged;
  final int unreadMessageCount;
  final int unreadNotificationCount;
  final VoidCallback onLogout;
  final String? profileId;
  final bool showShellChrome;
  final String? shellAvatarUrl;
  final String? shellAvatarLabel;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileScreenData? _profileData;
  Object? _profileLoadError;
  bool _isInitialLoading = true;
  String? _viewerProfileId;
  int _loadGeneration = 0;
  bool _didLogInitialProfileLoad = false;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  bool _didLogHydration = false;
  bool _isOpeningChat = false;
  int _profileImageVersion = 0;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Profile open start profileId=${widget.profileId ?? 'self'}');
    perfLogFrame('Profile', _openStopwatch);
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed ||
        oldWidget.profileId != widget.profileId) {
      _reload(
        preserveData: oldWidget.profileId == widget.profileId &&
            oldWidget.refreshSeed != widget.refreshSeed,
      );
    }
  }

  void _updateProfileData(
      ProfileScreenData Function(ProfileScreenData current) update) {
    final current = _profileData;
    if (current == null) {
      return;
    }

    setState(() {
      _profileData = update(current);
    });
  }

  Future<void> _loadProfile({bool preserveData = false}) async {
    final loadGeneration = ++_loadGeneration;
    final stopwatch = Stopwatch()..start();
    if (!preserveData || _profileData == null) {
      setState(() {
        _isInitialLoading = true;
        _profileLoadError = null;
        _profileData = preserveData ? _profileData : null;
        _viewerProfileId = preserveData ? _viewerProfileId : null;
      });
    } else {
      setState(() {
        _profileLoadError = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        widget.repository.fetchProfileScreenPhaseOneData(
          profileId: widget.profileId,
          includePostImages: false,
        ),
        widget.repository.fetchCurrentProfile(),
      ]);
      final phaseOne = results[0] as ProfileScreenPhaseOneData;
      final viewerProfile = results[1] as AppProfile;
      stopwatch.stop();
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }

      setState(() {
        _profileData = phaseOne.data;
        _profileLoadError = null;
        _isInitialLoading = false;
        _viewerProfileId = viewerProfile.id;
      });

      perfLog(
        'Profile phase 1 data load complete in ${_openStopwatch.elapsedMilliseconds}ms posts=${phaseOne.data.posts.length}',
      );
      if (!_didLogInitialProfileLoad) {
        _didLogInitialProfileLoad = true;
        perfLog(
            'initial Profile phase 1 load took ${stopwatch.elapsedMilliseconds}ms');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hydratePostImages(phaseOne.data, loadGeneration);
        _loadDeferredPublicSpots(
          phaseOne.data,
          phaseOne.postIds,
          loadGeneration,
        );
      });
    } catch (error) {
      stopwatch.stop();
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }

      setState(() {
        _profileLoadError = error;
        _isInitialLoading = false;
        _viewerProfileId = null;
        if (!preserveData) {
          _profileData = null;
        }
      });
    }
  }

  Future<void> _reload({bool preserveData = true}) async {
    perfLog('Profile reload start profileId=${widget.profileId ?? 'self'}');
    _didLogHydration = false;
    await _loadProfile(preserveData: preserveData);
  }

  Future<void> _loadDeferredPublicSpots(
    ProfileScreenData data,
    List<String> knownPostIds,
    int loadGeneration,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final publicSpots = await widget.repository.fetchProfileSpotsForProfile(
        data.profile,
        isOwnProfile: data.isOwnProfile,
        knownPostIds: knownPostIds,
      );
      stopwatch.stop();
      if (!mounted ||
          loadGeneration != _loadGeneration ||
          _profileData == null) {
        return;
      }

      setState(() {
        _profileData = _profileData!.copyWith(
          publicSpots: publicSpots,
          stats: _profileData!.stats.copyWith(
            totalFishingSpots: publicSpots.length,
          ),
        );
      });
      perfLog(
        'Profile deferred spots load complete in ${stopwatch.elapsedMilliseconds}ms publicSpots=${publicSpots.length}',
      );
      perfLog(
        'Profile total data load complete in ${_openStopwatch.elapsedMilliseconds}ms posts=${_profileData!.posts.length} publicSpots=${publicSpots.length}',
      );
    } catch (error) {
      stopwatch.stop();
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }

      setState(() {});
      perfLog(
          'Profile deferred spots load failed in ${stopwatch.elapsedMilliseconds}ms: $error');
    }
  }

  Future<void> _hydratePostImages(
      ProfileScreenData data, int loadGeneration) async {
    if (data.posts.isEmpty ||
        data.posts.every((post) => (post.imageStoragePath ?? '').isEmpty)) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    final hydratedPosts = await widget.repository.hydratePostImages(data.posts);
    stopwatch.stop();
    if (!mounted || loadGeneration != _loadGeneration || _profileData == null) {
      return;
    }

    final hydratedById = {
      for (final post in hydratedPosts) post.id: post,
    };
    final current = _profileData!;
    final mergedPosts = current.posts
        .map(
          (post) => post.copyWith(
            imageUrl: hydratedById[post.id]?.imageUrl ?? post.imageUrl,
            imageStoragePath: hydratedById[post.id]?.imageStoragePath ??
                post.imageStoragePath,
          ),
        )
        .toList(growable: false);

    setState(() {
      _profileData = current.copyWith(posts: mergedPosts);
    });
    if (!_didLogHydration) {
      _didLogHydration = true;
      perfLog(
        'Profile deferred hydration complete in ${stopwatch.elapsedMilliseconds}ms posts=${hydratedPosts.length}',
      );
    }
  }

  Future<void> _openEditProfile(AppProfile profile) async {
    final updated = await Navigator.of(context).push<AppProfile>(
      MaterialPageRoute<AppProfile>(
        builder: (_) => EditProfileScreen(
          repository: widget.repository,
          profile: profile,
        ),
      ),
    );

    if (updated != null && mounted) {
      _updateProfileData(
        (current) => current.copyWith(profile: updated),
      );
      setState(() {
        _profileImageVersion++;
      });
      await _reload();
    }
  }

  Future<void> _shareProfile(AppProfile profile) async {
    final username = (profile.username ?? '').trim();
    final shareText = username.isNotEmpty
        ? '@$username profilini incele'
        : '${profile.displayName} profilini incele';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil paylaşım metni panoya kopyalandı')),
    );
  }

  Future<void> _toggleFollow(ProfileScreenData data) async {
    if (data.isOwnProfile) {
      return;
    }

    final nextIsFollowing = !data.isFollowing;
    final updatedData = data.copyWith(
      isFollowing: nextIsFollowing,
      stats: data.stats.copyWith(
        followerCount: nextIsFollowing
            ? data.stats.followerCount + 1
            : (data.stats.followerCount > 0 ? data.stats.followerCount - 1 : 0),
      ),
    );

    _updateProfileData((_) => updatedData);

    try {
      if (nextIsFollowing) {
        await widget.repository.followUser(data.profile.id);
      } else {
        await widget.repository.unfollowUser(data.profile.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _updateProfileData((_) => data);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Takip durumu güncellenemedi: $error')),
      );
    }
  }

  Future<void> _openDirectMessage(ProfileScreenData data) async {
    if (data.isOwnProfile || _isOpeningChat) {
      return;
    }

    setState(() {
      _isOpeningChat = true;
    });

    try {
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            repository: widget.repository,
            otherProfile: data.profile,
            currentProfileId: _viewerProfileId,
            pendingConversationId: () async {
              final viewerProfileId = _viewerProfileId?.trim() ?? '';
              if (viewerProfileId.isNotEmpty) {
                return widget.repository.createOrGetConversation(
                  viewerProfileId,
                  data.profile.id,
                  currentProfileId: viewerProfileId,
                );
              }

              final currentProfile =
                  await widget.repository.fetchCurrentProfile();
              return widget.repository.createOrGetConversation(
                currentProfile.id,
                data.profile.id,
                currentProfileId: currentProfile.id,
              );
            }(),
          ),
        ),
      );
      widget.onDirectMessageStateChanged();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj başlatılamadı: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningChat = false;
        });
      }
    }
  }

  Future<void> _toggleLike(ProfileScreenData data, int index) async {
    final originalPosts = List<SocialPost>.from(data.posts);
    final post = originalPosts[index];
    final updatedPost = post.copyWith(
      isLiked: !post.isLiked,
      likeCount: post.isLiked
          ? (post.likeCount > 0 ? post.likeCount - 1 : 0)
          : post.likeCount + 1,
    );
    final updatedPosts = List<SocialPost>.from(originalPosts);
    updatedPosts[index] = updatedPost;

    _updateProfileData((current) => current.copyWith(posts: updatedPosts));

    try {
      await widget.repository.toggleLike(post.id);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _updateProfileData((current) => current.copyWith(posts: originalPosts));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beğeni durumu güncellenemedi: $error')),
      );
    }
  }

  Future<void> _openLinkedSpot(SocialPost post) async {
    if (!post.hasExactSpotAction || (post.linkedFishingSpotId ?? '').isEmpty) {
      return;
    }

    debugPrint(
      '[SPOT_NAV] tap source=profile postId=${post.id} passedSpotId=${post.linkedFishingSpotId!} linkedSpotId=${post.linkedSpotId ?? 'null'} linkedFishingSpotId=${post.linkedFishingSpotId ?? 'null'} itemSpotId=null visibility=${post.visibilityValue}',
    );
    try {
      await widget.repository.fetchSpotDetail(post.linkedFishingSpotId!);
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SpotDetailScreen(
            repository: widget.repository,
            spotId: post.linkedFishingSpotId!,
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        '[SPOT_NAV] failure source=profile postId=${post.id} passedSpotId=${post.linkedFishingSpotId!} error=$error',
      );
      if (!mounted) {
        return;
      }

      if (post.latitude != null && post.longitude != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PostLocationPreviewScreen(post: post),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu mera detayına erişilemiyor')),
      );
    }
  }

  Future<void> _openFollowers(ProfileScreenData data) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileConnectionsScreen(
          title: 'Takipçiler',
          emptyMessage: 'Henüz takipçi yok',
          profilesFuture:
              widget.repository.fetchFollowersForProfile(data.profile.id),
          onOpenProfile: _openProfile,
        ),
      ),
    );
  }

  Future<void> _openFollowing(ProfileScreenData data) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileConnectionsScreen(
          title: 'Takip edilenler',
          emptyMessage: 'Henüz takip edilen kullanıcı yok',
          profilesFuture:
              widget.repository.fetchFollowingForProfile(data.profile.id),
          onOpenProfile: _openProfile,
        ),
      ),
    );
  }

  Future<void> _openProfile(AppProfile profile) async {
    if (!mounted || profile.id.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          repository: widget.repository,
          selectedIndex: widget.selectedIndex,
          refreshSeed: widget.refreshSeed,
          onSelectTab: widget.onSelectTab,
          onOpenAddSpot: widget.onOpenAddSpot,
          onOpenCreatePost: widget.onOpenCreatePost,
          onOpenSearch: widget.onOpenSearch,
          onOpenLocation: widget.onOpenLocation,
          onLogout: widget.onLogout,
          profileId: profile.id,
          showShellChrome: false,
        ),
      ),
    );
  }

  Future<void> _openPost(SocialPost post) async {
    final updatedPost = await Navigator.of(context).push<SocialPost>(
      MaterialPageRoute<SocialPost>(
        builder: (_) => PostDetailScreen(
          repository: widget.repository,
          post: post,
        ),
      ),
    );

    if (updatedPost == null || !mounted) {
      return;
    }

    _updateProfileData((data) {
      final updatedPosts = List<SocialPost>.from(data.posts);
      final index =
          updatedPosts.indexWhere((item) => item.id == updatedPost.id);
      if (index == -1) {
        return data;
      }

      updatedPosts[index] = updatedPost;
      return data.copyWith(posts: updatedPosts);
    });
  }

  Future<void> _openPostMap(SocialPost post) async {
    if (post.hasApproxLocationAction &&
        post.latitude != null &&
        post.longitude != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostLocationPreviewScreen(post: post),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    if (post.hasApproxLocationAction && (post.region ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(post.region!)),
      );
    }
  }

  List<Widget> _actionsFor(ProfileScreenData? data) {
    if (data == null || !data.isOwnProfile) {
      return const [];
    }

    return [
      IconButton(
        onPressed: () => _shareProfile(data.profile),
        icon: const Icon(Icons.ios_share_outlined),
        tooltip: 'Profili paylaş',
      ),
      IconButton(
        onPressed: () => _openEditProfile(data.profile),
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Profili düzenle',
      ),
    ];
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_isInitialLoading && _profileData == null) {
      if (!_didLogMeaningfulPaint) {
        _didLogMeaningfulPaint = true;
        perfLog(
            'Profile structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
      }
      return const _ProfileLoadingView();
    }

    if (_profileLoadError != null && _profileData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Profil yüklenemedi: $_profileLoadError'),
        ),
      );
    }

    final data = _profileData;
    if (data == null) {
      return const Center(child: Text('Profil bulunamadı.'));
    }
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
          'Profile structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
    }

    final profile = data.profile;
    final hasCoverImage = (profile.coverUrl ?? '').trim().isNotEmpty;
    final bannerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.primary.withValues(alpha: 0.9),
        const Color(0xFF7AA6F8),
        AppColors.primarySoft,
      ],
    );
    final username = (profile.username ?? '').trim();
    final bio = (profile.bio ?? '').trim();
    final heroTopInset =
        widget.showShellChrome ? 20.0 : MediaQuery.paddingOf(context).top + 12;
    final metaItems = <_ProfileMetaItem>[
      if ((profile.city ?? '').trim().isNotEmpty)
        _ProfileMetaItem(
          icon: Icons.place_outlined,
          label: profile.city!.trim(),
        ),
      if ((profile.homeRegion ?? '').trim().isNotEmpty)
        _ProfileMetaItem(
          icon: Icons.waves_outlined,
          label: profile.homeRegion!.trim(),
        ),
    ];
    final statItems = [
      (
        label: 'Paylaşımlar',
        value: data.stats.totalPosts.toString(),
        onTap: null,
      ),
      (
        label: 'Meralar',
        value: data.stats.totalFishingSpots.toString(),
        onTap: null,
      ),
      (
        label: 'Takip',
        value: data.stats.followingCount.toString(),
        onTap: () => _openFollowing(data),
      ),
      (
        label: 'Takipçi',
        value: data.stats.followerCount.toString(),
        onTap: () => _openFollowers(data),
      ),
    ];

    return RefreshIndicator(
      onRefresh: _reload,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              widget.showShellChrome ? 16 : 0,
              16,
              24,
            ),
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: widget.showShellChrome ? 168 : 196,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: appSoftShadow(theme.colorScheme.primary),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasCoverImage
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                _cacheBustedImageUrl(profile.coverUrl)!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.08),
                                      Colors.black.withValues(alpha: 0.24),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: bannerGradient,
                            ),
                          ),
                  ),
                  Positioned(
                    left: 20,
                    top: heroTopInset,
                    child: AnimatedOpacity(
                      opacity: widget.showShellChrome ? 0 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: IgnorePointer(
                        ignoring: widget.showShellChrome,
                        child: _ProfileHeroIconButton(
                          icon: Icons.arrow_back_rounded,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: heroTopInset,
                    right: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (data.isOwnProfile)
                          _ProfileHeroIconButton(
                            icon: Icons.ios_share_outlined,
                            onPressed: () => _shareProfile(profile),
                          ),
                        if (data.isOwnProfile) const SizedBox(width: 8),
                        if (data.isOwnProfile)
                          _ProfileHeroIconButton(
                            icon: Icons.edit_outlined,
                            onPressed: () => _openEditProfile(profile),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: -34,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 37,
                          backgroundColor: AppColors.background,
                          backgroundImage: (profile.avatarUrl ?? '').isNotEmpty
                              ? NetworkImage(
                                  _cacheBustedImageUrl(profile.avatarUrl)!,
                                )
                              : null,
                          child: (profile.avatarUrl ?? '').isEmpty
                              ? Text(
                                  profile.initials,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                profile.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.84),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  bio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.28,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ],
              if (metaItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in metaItems)
                      _ProfileMetaChip(
                        icon: item.icon,
                        label: item.label,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              _ProfileActionRow(
                isOwnProfile: data.isOwnProfile,
                isFollowing: data.isFollowing,
                isMessageLoading: _isOpeningChat,
                onEdit: () => _openEditProfile(profile),
                onShare: () => _shareProfile(profile),
                onToggleFollow: () => _toggleFollow(data),
                onMessage: () => _openDirectMessage(data),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.32),
                  ),
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < statItems.length; index++) ...[
                      Expanded(
                        child: _InlineStatItem(
                          label: statItems[index].label,
                          value: statItems[index].value,
                          onTap: statItems[index].onTap,
                        ),
                      ),
                      if (index != statItems.length - 1)
                        Container(
                          width: 1,
                          height: 28,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.24),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _SectionLabel(
                title: data.isOwnProfile ? 'Paylaşımlarım' : 'Paylaşımlar',
                subtitle: 'Sosyal akış ve son paylaşımlar',
              ),
              const SizedBox(height: 10),
              if (data.posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: AppEmptyState(
                    icon: Icons.photo_library_outlined,
                    message: 'Henüz paylaşım yok.',
                  ),
                )
              else
                ...data.posts.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SocialPostCard(
                          post: entry.value,
                          profileSurface: true,
                          onLike: () => _toggleLike(data, entry.key),
                          onTap: () => _openPost(entry.value),
                          onOpenComments: () => _openPost(entry.value),
                          onOpenSpot: entry.value.hasExactSpotAction
                              ? () => _openLinkedSpot(entry.value)
                              : null,
                          onOpenMap: entry.value.hasApproxLocationAction
                              ? () => _openPostMap(entry.value)
                              : null,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _profileData?.isOwnProfile == false
        ? _profileData?.profile.displayName ?? 'Profil'
        : 'Profil';
    final body = _buildBody(context);
    final actions = _actionsFor(_profileData);

    if (!widget.showShellChrome) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 0,
          actions: actions,
        ),
        body: body,
      );
    }

    return ShellScaffold(
      title: title,
      selectedIndex: widget.selectedIndex,
      onSelectIndex: widget.onSelectTab,
      onOpenAddSpot: widget.onOpenAddSpot,
      onOpenCreatePost: widget.onOpenCreatePost,
      onOpenSearch: widget.onOpenSearch,
      onOpenLocation: widget.onOpenLocation,
      onOpenMessages: widget.onOpenMessages,
      onOpenNotifications: widget.onOpenNotifications,
      unreadMessageCount: widget.unreadMessageCount,
      unreadNotificationCount: widget.unreadNotificationCount,
      headerAvatarUrl: widget.shellAvatarUrl,
      headerAvatarLabel: widget.shellAvatarLabel,
      onLogout: widget.onLogout,
      actions: actions,
      body: body,
    );
  }

  String? _cacheBustedImageUrl(String? rawUrl) {
    final trimmed = rawUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final separator = trimmed.contains('?') ? '&' : '?';
    return '$trimmed${separator}v=$_profileImageVersion';
  }
}

class _ProfileMetaItem {
  const _ProfileMetaItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class _ProfileLoadingView extends StatelessWidget {
  const _ProfileLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            AppSkeletonCard(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonBox(height: 80, width: 80, radius: 40),
                      SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppSkeletonBox(height: 24, width: 160, radius: 12),
                            SizedBox(height: 10),
                            AppSkeletonBox(height: 14, width: 110, radius: 10),
                            SizedBox(height: 10),
                            AppSkeletonBox(height: 14, width: 90, radius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: AppSkeletonBox(height: 76, radius: 18)),
                      SizedBox(width: 14),
                      Expanded(child: AppSkeletonBox(height: 76, radius: 18)),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: AppSkeletonBox(height: 76, radius: 18)),
                      SizedBox(width: 14),
                      Expanded(child: AppSkeletonBox(height: 76, radius: 18)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),
            AppSkeletonBox(height: 24, width: 110, radius: 12),
            SizedBox(height: 12),
            AppSkeletonCard(
              child: SizedBox(height: 108),
            ),
            SizedBox(height: 18),
            AppSkeletonBox(height: 24, width: 130, radius: 12),
            SizedBox(height: 12),
            _ProfilePostSkeleton(),
            SizedBox(height: 16),
            _ProfilePostSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _ProfilePostSkeleton extends StatelessWidget {
  const _ProfilePostSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSkeletonBox(height: 46, width: 46, radius: 23),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(height: 16, width: 120, radius: 10),
                    SizedBox(height: 8),
                    AppSkeletonBox(height: 12, width: 150, radius: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          AppSkeletonBox(height: 14, radius: 10),
          SizedBox(height: 8),
          AppSkeletonBox(height: 14, width: 220, radius: 10),
          SizedBox(height: 18),
          AppSkeletonBox(height: 160, radius: 22),
        ],
      ),
    );
  }
}

class _ProfileHeroIconButton extends StatelessWidget {
  const _ProfileHeroIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ProfileMetaChip extends StatelessWidget {
  const _ProfileMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStatItem extends StatelessWidget {
  const _InlineStatItem({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.82),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  const _ProfileActionRow({
    required this.isOwnProfile,
    required this.isFollowing,
    required this.isMessageLoading,
    required this.onEdit,
    required this.onShare,
    required this.onToggleFollow,
    required this.onMessage,
  });

  final bool isOwnProfile;
  final bool isFollowing;
  final bool isMessageLoading;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final followButton = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: isFollowing
          ? OutlinedButton(
              key: const ValueKey('following'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(37),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onToggleFollow,
              child: const Text('Takip ediliyor'),
            )
          : FilledButton(
              key: const ValueKey('follow'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(37),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onToggleFollow,
              child: const Text('Takip et'),
            ),
    );

    final leftButton = isOwnProfile
        ? OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(37),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Profili düzenle'),
          )
        : followButton;

    final rightButton = isOwnProfile
        ? FilledButton(
            onPressed: onShare,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(37),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Profili paylaş'),
          )
        : OutlinedButton(
            onPressed: isMessageLoading ? null : onMessage,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(37),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isMessageLoading ? 'Açılıyor...' : 'Mesaj gönder'),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              leftButton,
              const SizedBox(height: 8),
              rightButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: leftButton),
            const SizedBox(width: 10),
            Expanded(child: rightButton),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}

class _ProfileConnectionsScreen extends StatefulWidget {
  const _ProfileConnectionsScreen({
    required this.title,
    required this.emptyMessage,
    required this.profilesFuture,
    required this.onOpenProfile,
  });

  final String title;
  final String emptyMessage;
  final Future<List<AppProfile>> profilesFuture;
  final Future<void> Function(AppProfile profile) onOpenProfile;

  @override
  State<_ProfileConnectionsScreen> createState() =>
      _ProfileConnectionsScreenState();
}

class _ProfileConnectionsScreenState extends State<_ProfileConnectionsScreen> {
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('${widget.title} open start');
    perfLogFrame(widget.title, _openStopwatch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<AppProfile>>(
        future: widget.profilesFuture,
        builder: (context, snapshot) {
          if (!_didLogMeaningfulPaint) {
            _didLogMeaningfulPaint = true;
            perfLog(
                '${widget.title} structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${widget.title} yüklenemedi: ${snapshot.error}'),
              ),
            );
          }

          final profiles = snapshot.data ?? const [];
          perfLog(
            '${widget.title} data load complete in ${_openStopwatch.elapsedMilliseconds}ms items=${profiles.length}',
          );

          if (profiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.emptyMessage),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: profiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  return Card(
                    child: ListTile(
                      onTap: () => widget.onOpenProfile(profile),
                      leading: CircleAvatar(
                        backgroundImage: (profile.avatarUrl ?? '').isNotEmpty
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: (profile.avatarUrl ?? '').isEmpty
                            ? Text(profile.initials)
                            : null,
                      ),
                      title: Text(profile.displayName),
                      subtitle: (profile.username ?? '').isNotEmpty
                          ? Text('@${profile.username}')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
