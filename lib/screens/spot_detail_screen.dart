import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/social_post_card.dart';
import 'create_post_screen.dart';
import 'profile_screen.dart';

class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({
    super.key,
    required this.repository,
    required this.spotId,
    this.sharedBy,
  });

  final SpotRepository repository;
  final String spotId;
  final SpotSharerIdentity? sharedBy;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  late final StreamSubscription<dynamic> _authStateSubscription;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  bool _didLogDataLoaded = false;
  String? _lastAuthUid;
  SpotSharerIdentity? _incomingSharerIdentity;
  SpotDetailData? _detail;
  AppProfile? _currentProfile;
  List<AppProfile> _sharedProfiles = const [];
  List<SocialPost> _spotPosts = const [];
  Object? _loadError;
  bool _isLoading = true;
  bool _isEmbeddedMapInteracting = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Spot Detail open start spotId=${widget.spotId}');
    perfLogFrame('Spot Detail', _openStopwatch);
    _incomingSharerIdentity = _normalizedSharerIdentity(widget.sharedBy);
    _logIncomingSharerIdentity(
      sharer: _incomingSharerIdentity,
      source: 'init',
    );
    _lastAuthUid = widget.repository.currentAuthUidForDebug;
    unawaited(_loadViewState(reason: 'init'));
    _authStateSubscription = widget.repository.authStateChanges.listen((_) {
      final nextAuthUid = widget.repository.currentAuthUidForDebug;
      if (_lastAuthUid == nextAuthUid || !mounted) {
        return;
      }

      _lastAuthUid = nextAuthUid;
      unawaited(_loadViewState(reason: 'auth_change'));
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpotDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSharerIdentity = _normalizedSharerIdentity(widget.sharedBy);
    if (_sameSharerIdentity(_incomingSharerIdentity, nextSharerIdentity) ==
        false) {
      _incomingSharerIdentity = nextSharerIdentity;
      _logIncomingSharerIdentity(
        sharer: _incomingSharerIdentity,
        source: 'did_update_widget',
      );
    }
    if (oldWidget.spotId == widget.spotId) {
      return;
    }

    unawaited(_loadViewState(reason: 'spot_id_change'));
  }

  Future<void> _refresh() async {
    perfLog('Spot Detail refresh start spotId=${widget.spotId}');
    await _loadViewState(reason: 'refresh');
    perfLog('Spot Detail refresh complete spotId=${widget.spotId}');
  }

  Future<void> _loadViewState({required String reason}) async {
    final loadGeneration = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _detail = null;
        _currentProfile = null;
        _sharedProfiles = const [];
        _spotPosts = const [];
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        widget.repository.fetchSpotDetail(widget.spotId),
        widget.repository.fetchCurrentProfile(),
        widget.repository.isSpotFavorited(widget.spotId),
      ]);

      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }

      setState(() {
        _detail = results[0] as SpotDetailData;
        _currentProfile = results[1] as AppProfile;
        _spotPosts = const [];
        _isLoading = false;
        _loadError = null;
      });

      try {
        final spotPosts =
            await widget.repository.fetchPostsForSpot(widget.spotId);
        if (!mounted || loadGeneration != _loadGeneration) {
          return;
        }
        setState(() {
          _spotPosts = spotPosts;
        });
      } catch (error) {
        debugPrint(
          '[SPOT_DETAIL] postsLoadFailure spotId=${widget.spotId} error=$error',
        );
        if (!mounted || loadGeneration != _loadGeneration) {
          return;
        }
        setState(() {
          _spotPosts = const [];
        });
      }

      final detail = results[0] as SpotDetailData;
      final currentProfile = results[1] as AppProfile;
      if (_isOwner(detail: detail, currentProfile: currentProfile)) {
        final sharedProfiles =
            await widget.repository.fetchSpotSharedProfiles(widget.spotId);
        if (!mounted || loadGeneration != _loadGeneration) {
          return;
        }
        setState(() {
          _sharedProfiles = sharedProfiles;
        });
      }
    } catch (error) {
      debugPrint(
        '[SPOT_DETAIL] loadFailure spotId=${widget.spotId} error=$error',
      );
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }

      setState(() {
        _detail = null;
        _currentProfile = null;
        _sharedProfiles = const [];
        _spotPosts = const [];
        _isLoading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _openContributeFlow(FishingSpot spot) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreatePostScreen(
          repository: widget.repository,
          initialSpotId: spot.id,
        ),
      ),
    );

    if (created == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _openPostMap(SocialPost post) async {
    if (post.hasExactSpotAction &&
        (post.linkedFishingSpotId ?? '').trim().isNotEmpty &&
        post.linkedFishingSpotId != widget.spotId) {
      await _openLinkedSpot(post);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu katkı zaten bu mera akışına bağlı.'),
      ),
    );
  }

  Future<void> _openLinkedSpot(SocialPost post) async {
    final linkedSpotId = post.linkedFishingSpotId?.trim() ?? '';
    if (linkedSpotId.isEmpty) {
      return;
    }

    if (linkedSpotId == widget.spotId) {
      await _openPostMap(post);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpotDetailScreen(
          repository: widget.repository,
          spotId: linkedSpotId,
        ),
      ),
    );
  }

  Future<void> _openExpandedMap(FishingSpot spot) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ExpandedSpotMapScreen(spot: spot),
      ),
    );
  }

  void _setEmbeddedMapInteracting(bool value) {
    if (_isEmbeddedMapInteracting == value || !mounted) {
      return;
    }

    setState(() {
      _isEmbeddedMapInteracting = value;
    });
  }

  Future<void> _openSharerProfile(SpotSharerIdentity sharer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          repository: widget.repository,
          selectedIndex: 4,
          refreshSeed: 0,
          onSelectTab: (_) {},
          onOpenAddSpot: () {},
          onOpenCreatePost: () {},
          onOpenSearch: () {},
          onOpenLocation: () {},
          onLogout: () {},
          profileId: sharer.profileId,
          showShellChrome: false,
        ),
      ),
    );
  }

  SpotSharerIdentity? _normalizedSharerIdentity(SpotSharerIdentity? sharer) {
    final profileId = sharer?.profileId.trim();
    if (profileId == null || profileId.isEmpty) {
      return null;
    }

    final displayName = sharer?.displayName?.trim();
    final username = sharer?.username?.trim();
    final avatarUrl = sharer?.avatarUrl?.trim();
    final sourcePostId = sharer?.sourcePostId?.trim();
    final sourceUserId = sharer?.sourceUserId?.trim();

    return SpotSharerIdentity(
      profileId: profileId,
      displayName:
          displayName != null && displayName.isNotEmpty ? displayName : null,
      username: username != null && username.isNotEmpty ? username : null,
      avatarUrl: avatarUrl != null && avatarUrl.isNotEmpty ? avatarUrl : null,
      sourcePostId:
          sourcePostId != null && sourcePostId.isNotEmpty ? sourcePostId : null,
      sourceUserId:
          sourceUserId != null && sourceUserId.isNotEmpty ? sourceUserId : null,
    );
  }

  bool _sameSharerIdentity(
    SpotSharerIdentity? a,
    SpotSharerIdentity? b,
  ) {
    return a?.profileId == b?.profileId &&
        a?.displayName == b?.displayName &&
        a?.username == b?.username &&
        a?.avatarUrl == b?.avatarUrl &&
        a?.sourcePostId == b?.sourcePostId &&
        a?.sourceUserId == b?.sourceUserId;
  }

  void _logIncomingSharerIdentity({
    required SpotSharerIdentity? sharer,
    required String source,
  }) {}

  bool _isOwner({
    required SpotDetailData detail,
    required AppProfile currentProfile,
  }) {
    final currentProfileId = currentProfile.id.trim();
    final ownerProfileId = detail.spot.ownerProfileId.trim();
    return currentProfileId.isNotEmpty && ownerProfileId == currentProfileId;
  }

  bool _isSharedViaWhitelist({
    required SpotDetailData detail,
    required AppProfile currentProfile,
  }) {
    return !_isOwner(detail: detail, currentProfile: currentProfile) &&
        detail.spot.visibility.trim().toLowerCase() == 'private';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
          'Spot Detail structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mera',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.82),
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (_loadError != null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Bu mera detayına erişilemiyor'),
              ),
            );
          }

          if (_isLoading || _detail == null || _currentProfile == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = _detail!;
          final currentProfile = _currentProfile!;

          final weather = detail.weatherSnapshot;
          if (!_didLogDataLoaded) {
            _didLogDataLoaded = true;
            perfLog(
              'Spot Detail data load complete in ${_openStopwatch.elapsedMilliseconds}ms hasWeather=${weather != null} hasScore=${detail.score != null}',
            );
          }
          final score = detail.score;
          final bestTimeWindow = _buildBestTimeWindow(score);
          final weatherLine = _buildCompactWeatherLine(weather);
          final whyReasons = _buildWhyReasons(
            score: score,
            weather: weather,
          );
          final recentStatus = _buildRecentStatus(_spotPosts);
          final tacticSummary = _buildTacticSummary(
            posts: _spotPosts,
            bestTimeWindow: bestTimeWindow,
            score: score,
          );
          final currentProfileId = currentProfile.id;
          final isOwner = _isOwner(
            detail: detail,
            currentProfile: currentProfile,
          );
          final isSharedViaWhitelist = _isSharedViaWhitelist(
            detail: detail,
            currentProfile: currentProfile,
          );
          final sharerIdentity = _incomingSharerIdentity;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  physics: _isEmbeddedMapInteracting
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detail.spot.name,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.35,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _decisionLabelForScore(score),
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.92),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _SpotCommunityScoreBadge(score: score),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoPill(
                                  icon: Icons.water_outlined,
                                  label: localizedWaterTypeLabel(
                                    detail.spot.waterType,
                                  ).trim().isEmpty
                                      ? 'Su tipi yok'
                                      : localizedWaterTypeLabel(
                                          detail.spot.waterType,
                                        ),
                                ),
                                _InfoPill(
                                  icon: Icons.visibility_outlined,
                                  label: localizedVisibilityLabel(
                                    detail.spot.visibility,
                                  ),
                                ),
                                if (bestTimeWindow != null)
                                  _InfoPill(
                                    icon: Icons.schedule_outlined,
                                    label: bestTimeWindow.label,
                                  ),
                                if (isSharedViaWhitelist)
                                  const _InfoPill(
                                    icon: Icons.lock_outline_rounded,
                                    label: 'Seninle paylaşıldı',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _buildSystemDecisionLine(score),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.9),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bugünün durumu',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Son 24 saatte bu meradan gelen katkı özeti.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatusMetricCard(
                                    label: 'Katkı',
                                    value: '${recentStatus.recentCount}',
                                    tone: AppColors.primary,
                                    soft: AppColors.primarySoft,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatusMetricCard(
                                    label: 'Başarılı',
                                    value: '${recentStatus.successCount}',
                                    tone: AppColors.success,
                                    soft: AppColors.successSoft,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatusMetricCard(
                                    label: 'Boş geçti',
                                    value: '${recentStatus.emptyCount}',
                                    tone: AppColors.danger,
                                    soft: AppColors.dangerSoft,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              recentStatus.summary,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.88),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: SizedBox(
                                height: 188,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Listener(
                                        onPointerDown: (_) =>
                                            _setEmbeddedMapInteracting(true),
                                        onPointerUp: (_) =>
                                            _setEmbeddedMapInteracting(false),
                                        onPointerCancel: (_) =>
                                            _setEmbeddedMapInteracting(false),
                                        child: _SpotLocationMap(
                                          latitude: detail.spot.latitude,
                                          longitude: detail.spot.longitude,
                                          interactive: true,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 12,
                                      bottom: 12,
                                      child: IgnorePointer(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.42),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                detail.spot.name,
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _buildActivityBadgeText(score),
                                                style: theme
                                                    .textTheme.labelMedium
                                                    ?.copyWith(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.84),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Material(
                                        color: theme.colorScheme.surface
                                            .withValues(alpha: 0.92),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: InkWell(
                                          onTap: () =>
                                              _openExpandedMap(detail.spot),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 9,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.open_in_full_rounded,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Tam ekran',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Taktik özeti',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Bu merada öne çıkan yöntemler ve zaman pencereleri.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _TagSummaryGroup(
                              title: 'Teknikler',
                              tags: tacticSummary.techniques,
                            ),
                            const SizedBox(height: 12),
                            _TagSummaryGroup(
                              title: 'Yem / Sahte',
                              tags: tacticSummary.baits,
                            ),
                            const SizedBox(height: 12),
                            _TagSummaryGroup(
                              title: 'Zaman',
                              tags: tacticSummary.times,
                            ),
                            if (weatherLine != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                weatherLine,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                            if (whyReasons.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Neden',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...whyReasons.map(
                                (reason) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '•',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          reason,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.9),
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (sharerIdentity != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _DetailSharerRow(
                            sharer: sharerIdentity,
                            currentProfileId: currentProfileId,
                            onTap: () => _openSharerProfile(sharerIdentity),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isOwner) ...[
                              Text(
                                'Paylaşılan kişiler',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_sharedProfiles.isEmpty)
                                Text(
                                  'Henüz seçili kişi yok.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.9),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _sharedProfiles
                                      .map(
                                        (profile) => _ProfileChip(
                                          avatar: CircleAvatar(
                                            backgroundImage:
                                                (profile.avatarUrl ?? '')
                                                        .isNotEmpty
                                                    ? NetworkImage(
                                                        profile.avatarUrl!,
                                                      )
                                                    : null,
                                            child: (profile.avatarUrl ?? '')
                                                    .isEmpty
                                                ? Text(profile.initials)
                                                : null,
                                          ),
                                          label: (profile.username ?? '')
                                                  .isNotEmpty
                                              ? '${profile.displayName} (@${profile.username})'
                                              : profile.displayName,
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                            ] else
                              Text(
                                'Bu merayı hızlıca kaydedebilir veya kaydını kaldırabilirsin.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _SectionHeader(
                      title: 'Mera katkıları',
                      subtitle:
                          'Bu lokasyona bağlı tüm katkılar burada akar. Aynı yere yeni mera açmak yerine katkı ekle.',
                    ),
                    const SizedBox(height: 10),
                    if (_spotPosts.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: AppEmptyState(
                            icon: Icons.forum_outlined,
                            message:
                                'Henüz bu meraya katkı yok.\nİlk katkıyı sen ekleyebilirsin.',
                          ),
                        ),
                      )
                    else
                      ..._spotPosts.map(
                        (post) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SocialPostCard(
                            post: post,
                            profileSurface: true,
                            onLike: () async {
                              await widget.repository.toggleLike(post.id);
                              await _refresh();
                            },
                            onTap: () => _openPostMap(post),
                            onOpenComments: () => _openPostMap(post),
                            onOpenSpot: post.hasExactSpotAction
                                ? () => _openLinkedSpot(post)
                                : null,
                            onOpenMap: post.hasApproxLocationAction
                                ? () => _openPostMap(post)
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 92),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: _detail == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openContributeFlow(_detail!.spot),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Bu meraya katkı yap'),
            ),
    );
  }

  String? _buildCompactWeatherLine(WeatherSnapshot? weather) {
    if (weather == null) {
      return null;
    }

    final windText = weather.windSpeed == null
        ? 'Rüzgar yok'
        : '${_windSpeedLabel(weather.windSpeed!)} rüzgar';
    final tempText = weather.airTemperature == null
        ? 'Sıcaklık yok'
        : '${weather.airTemperature!.round()}°';
    final rainText = (weather.precipitation ?? 0) <= 0.1
        ? 'Yağış yok'
        : 'Yağış ${weather.precipitation!.toStringAsFixed(1)} mm';

    return '🌬 $windText • 🌡 $tempText • ☁ $rainText';
  }

  String _fallbackDecisionHeadline(FishingScore? score) {
    switch ((score?.scoreLabel ?? '').trim().toLowerCase()) {
      case 'good':
      case 'great':
      case 'excellent':
        return '🎯 Kaçırılmayacak bir zaman';
      case 'medium':
      case 'fair':
      case 'ok':
      case 'average':
      case 'neutral':
        return 'Denemeye değer';
      case 'weak':
      case 'poor':
      case 'bad':
      case 'low':
        return '⚠️ Şartlar şu an zayıf';
      default:
        return '🎯 Durum dikkatle değerlendirilmeli';
    }
  }

  String? _buildDecisionHeadlineText(FishingScore? score) {
    final catchProbability =
        _normalizeInsightValue(score?.catchProbabilityLabel);
    final activityLevel = _normalizeInsightValue(score?.activityLevelLabel);
    final shoreOpportunity =
        _normalizeInsightValue(score?.shoreOpportunityLabel);
    final fishingStyleFit = _normalizeInsightValue(score?.fishingStyleFit);

    final headline = _buildDecisionHeadline(
      catchProbability: catchProbability,
      activityLevel: activityLevel,
      shoreOpportunity: shoreOpportunity,
      fishingStyleFit: fishingStyleFit,
    );

    final resolvedHeadline = headline ?? _fallbackDecisionHeadline(score);
    if (resolvedHeadline.isEmpty) {
      return null;
    }

    return resolvedHeadline;
  }

  String _buildActivityBadgeText(FishingScore? score) {
    final scoreValue = score?.scoreValue;
    if (scoreValue == null) {
      return 'Skor yok';
    }
    if (scoreValue >= 80) {
      return 'Yüksek aktivite';
    }
    if (scoreValue >= 65) {
      return 'İyi aktivite';
    }
    if (scoreValue >= 50) {
      return 'Orta aktivite';
    }
    return 'Düşük aktivite';
  }

  String _buildSystemDecisionLine(FishingScore? score) {
    final scoreValue = score?.scoreValue;
    final scoreText = scoreValue == null ? 'Skor yok' : '$scoreValue Skor';
    final headline = (_buildDecisionHeadlineText(score) ?? 'Değerlendir')
        .replaceAll(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '')
        .trim();
    return '$scoreText • $headline';
  }

  String _decisionLabelForScore(FishingScore? score) {
    final scoreValue = score?.scoreValue ?? 0;
    if (scoreValue >= 80) {
      return 'Gitmeye değer';
    }
    if (scoreValue >= 60) {
      return 'Denemeye değer';
    }
    if (scoreValue >= 40) {
      return 'Zorlanabilir';
    }
    return 'Önerilmez';
  }

  _RecentSpotStatus _buildRecentStatus(List<SocialPost> posts) {
    final now = DateTime.now();
    final recentPosts = posts
        .where(
          (post) =>
              post.createdAt != null &&
              now.difference(post.createdAt!.toLocal()).inHours <= 24,
        )
        .toList(growable: false);

    int successCount = 0;
    int emptyCount = 0;
    for (final post in recentPosts) {
      final cue = _resultCueForText(post.caption);
      if (cue == _ContributionResult.success) {
        successCount++;
      } else if (cue == _ContributionResult.empty) {
        emptyCount++;
      }
    }

    final summary = recentPosts.isEmpty
        ? 'Son 24 saate ait katkı yok. Yapı hazır; yeni katkılar burada birikecek.'
        : successCount == 0 && emptyCount == 0
            ? 'Son 24 saatte ${recentPosts.length} katkı geldi, ama açık başarı/boş geçti etiketi henüz yok.'
            : 'Son 24 saatte ${recentPosts.length} katkıdan $successCount başarılı, $emptyCount boş geçti sinyali çıktı.';

    return _RecentSpotStatus(
      recentCount: recentPosts.length,
      successCount: successCount,
      emptyCount: emptyCount,
      summary: summary,
    );
  }

  _SpotTacticSummary _buildTacticSummary({
    required List<SocialPost> posts,
    required _BestTimeWindowContent? bestTimeWindow,
    required FishingScore? score,
  }) {
    final techniques = <String>{};
    final baits = <String>{};
    final times = <String>{};

    for (final post in posts) {
      final text = '${post.caption ?? ''} ${post.linkedFishingSpotName ?? ''}'
          .toLowerCase();
      for (final entry in _techniqueKeywords.entries) {
        if (entry.value.any(text.contains)) {
          techniques.add(entry.key);
        }
      }
      for (final entry in _baitKeywords.entries) {
        if (entry.value.any(text.contains)) {
          baits.add(entry.key);
        }
      }
      for (final entry in _timeKeywords.entries) {
        if (entry.value.any(text.contains)) {
          times.add(entry.key);
        }
      }
    }

    if (bestTimeWindow != null) {
      times.add(bestTimeWindow.label);
    } else {
      final activityText = _buildActivityBadgeText(score).toLowerCase();
      if (activityText.contains('yüksek')) {
        times.add('Aktif pencere');
      }
    }

    return _SpotTacticSummary(
      techniques:
          techniques.isEmpty ? const ['Henüz veri yok'] : techniques.toList(),
      baits: baits.isEmpty ? const ['Henüz veri yok'] : baits.toList(),
      times: times.isEmpty ? const ['Henüz veri yok'] : times.toList(),
    );
  }

  _ContributionResult? _resultCueForText(String? text) {
    final normalized = (text ?? '').toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (const [
      'iş yaptı',
      'vurdu',
      'aldım',
      'çıktı',
      'güzel geçti',
      'bereketli'
    ].any(normalized.contains)) {
      return _ContributionResult.success;
    }
    if (const ['boş geçti', 'boş döndük', 'yoktu', 'çıkmadı', 'alamadık']
        .any(normalized.contains)) {
      return _ContributionResult.empty;
    }
    return null;
  }

  List<String> _buildWhyReasons({
    required FishingScore? score,
    required WeatherSnapshot? weather,
  }) {
    final reasons = <String>[];
    final factors = score?.scoreFactors;
    final pressure = _factorStateLabel(
      factors,
      const ['pressure', 'basinc', 'basınç'],
    );
    final wind = _factorStateLabel(
      factors,
      const ['wind', 'wind_speed', 'ruzgar', 'rüzgar'],
    );
    final rain = _factorStateLabel(
      factors,
      const ['precipitation', 'rain', 'yagis', 'yağış'],
    );

    if (pressure != null) {
      reasons.add('Basınç ${_reasonTone(pressure)}');
    } else if (weather?.pressure != null) {
      reasons.add('Basınç ${weather!.pressure!.toStringAsFixed(0)} hPa');
    }
    if (wind != null) {
      reasons.add('Rüzgar ${_reasonTone(wind)}');
    } else if (weather?.windSpeed != null) {
      reasons.add('Rüzgar ${_windSpeedLabel(weather!.windSpeed!)}');
    }
    if (rain != null) {
      reasons.add('Yağış ${_reasonTone(rain)}');
    } else if ((weather?.precipitation ?? 0) <= 0.1) {
      reasons.add('Yağış yok');
    }

    final summary = score?.scoreSummary?.trim();
    if (summary != null && summary.isNotEmpty && reasons.length < 3) {
      reasons.add(summary);
    }

    return reasons.take(3).toList(growable: false);
  }

  String? _factorStateLabel(
    Map<String, dynamic>? factors,
    List<String> candidateKeys,
  ) {
    if (factors == null || factors.isEmpty) {
      return null;
    }

    for (final entry in factors.entries) {
      final normalizedKey = entry.key.trim().toLowerCase();
      if (!candidateKeys.contains(normalizedKey)) {
        continue;
      }

      final normalizedValue = _normalizeFactorValue(entry.value);
      if (normalizedValue != null) {
        return normalizedValue;
      }
    }

    return null;
  }

  String? _normalizeFactorValue(dynamic value) {
    if (value is String) {
      return _localizedFactorState(value);
    }
    if (value is Map) {
      for (final key in const ['state', 'rating', 'label', 'status']) {
        final candidate = value[key];
        if (candidate is String) {
          return _localizedFactorState(candidate);
        }
      }
    }
    return null;
  }

  String? _localizedFactorState(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'good':
      case 'great':
      case 'excellent':
        return 'iyi';
      case 'medium':
      case 'fair':
      case 'ok':
      case 'average':
      case 'neutral':
        return 'orta';
      case 'weak':
      case 'poor':
      case 'bad':
      case 'low':
        return 'zayıf';
      default:
        return null;
    }
  }

  String _reasonTone(String value) {
    switch (value) {
      case 'iyi':
        return 'stabil';
      case 'orta':
        return 'orta';
      case 'zayıf':
        return 'zayıf';
      default:
        return value;
    }
  }

  String _windSpeedLabel(double value) {
    if (value < 8) {
      return 'hafif';
    }
    if (value < 18) {
      return 'orta';
    }
    return 'kuvvetli';
  }

  _BestTimeWindowContent? _buildBestTimeWindow(FishingScore? score) {
    final start = score?.forecastWindowStart?.toLocal();
    final end = score?.forecastWindowEnd?.toLocal();
    if (start == null || end == null) {
      return null;
    }

    final now = DateTime.now();
    final label =
        '${DateFormat.Hm().format(start)} – ${DateFormat.Hm().format(end)}';

    if (now.isAfter(start) && now.isBefore(end)) {
      final hoursLeft = _roundHours(end.difference(now));
      return _BestTimeWindowContent(
        label: label,
        description: 'Şu an aktif. Yaklaşık $hoursLeft saat daha iyi kalır.',
      );
    }

    if (now.isBefore(start)) {
      final hoursUntil = _roundHours(start.difference(now));
      return _BestTimeWindowContent(
        label: label,
        description: 'Henüz başlamadı. $hoursUntil saat sonra başlayacak.',
      );
    }

    return _BestTimeWindowContent(
      label: label,
      description: 'Bu pencere geçti.',
    );
  }

  int _roundHours(Duration duration) {
    final rounded = (duration.inMinutes / 60).round();
    return rounded < 1 ? 1 : rounded;
  }

  String? _buildDecisionHeadline({
    required String? catchProbability,
    required String? activityLevel,
    required String? shoreOpportunity,
    required String? fishingStyleFit,
  }) {
    switch (_normalizeDecisionKey(catchProbability)) {
      case 'yuksek':
        return _normalizeDecisionKey(activityLevel) == 'yuksek'
            ? '🎯 Şu an çık, balık alma ihtimali çok yüksek'
            : '🎯 Kaçırılmayacak bir zaman';
      case 'orta':
        return 'Denemeye değer';
      case 'dusuk':
        return '⚠️ Çok verimli görünmüyor';
    }

    if (activityLevel != null) {
      return '👍 Hareket var, değerlendirmeye değer';
    }
    if (shoreOpportunity != null) {
      return '👍 Kıyıdan denemeye açık bir an';
    }
    if (fishingStyleFit != null) {
      return '👍 Doğru stille şans var';
    }

    return null;
  }

  String? _normalizeInsightValue(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final withoutPunctuation = normalized.replaceFirst(RegExp(r'[.!?]+$'), '');
    if (withoutPunctuation.isEmpty) {
      return null;
    }

    return withoutPunctuation[0].toLowerCase() +
        withoutPunctuation.substring(1);
  }

  String _normalizeDecisionKey(String? value) {
    if (value == null) {
      return '';
    }

    return value
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .trim();
  }
}

class _BestTimeWindowContent {
  const _BestTimeWindowContent({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

enum _ContributionResult { success, empty }

class _RecentSpotStatus {
  const _RecentSpotStatus({
    required this.recentCount,
    required this.successCount,
    required this.emptyCount,
    required this.summary,
  });

  final int recentCount;
  final int successCount;
  final int emptyCount;
  final String summary;
}

class _SpotTacticSummary {
  const _SpotTacticSummary({
    required this.techniques,
    required this.baits,
    required this.times,
  });

  final List<String> techniques;
  final List<String> baits;
  final List<String> times;
}

const Map<String, List<String>> _techniqueKeywords = {
  'Spin': ['spin', 'spinning'],
  'LRF': ['lrf'],
  'Surf casting': ['surf', 'surfcasting', 'surf casting'],
  'Tekne': ['tekne', 'boat'],
  'Yemli': ['yemli'],
};

const Map<String, List<String>> _baitKeywords = {
  'Silikon': ['silikon', 'shad'],
  'Karides': ['karides', 'shrimp'],
  'Yemli': ['yemli', 'canli yem', 'canlı yem'],
  'Kaşık': ['kaşık', 'kasik', 'spinner'],
  'Minnow': ['minnow'],
};

const Map<String, List<String>> _timeKeywords = {
  'Sabah': ['sabah', 'gün doğumu', 'gun dogumu'],
  'Öğlen': ['öğlen', 'oglen'],
  'Akşam': ['akşam', 'aksam', 'gün batımı', 'gun batimi'],
  'Gece': ['gece'],
};

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
          ),
        ),
      ],
    );
  }
}

class _StatusMetricCard extends StatelessWidget {
  const _StatusMetricCard({
    required this.label,
    required this.value,
    required this.tone,
    required this.soft,
  });

  final String label;
  final String value;
  final Color tone;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagSummaryGroup extends StatelessWidget {
  const _TagSummaryGroup({
    required this.title,
    required this.tags,
  });

  final String title;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags
              .map(
                (tag) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow
                        .withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _SpotCommunityScoreBadge extends StatelessWidget {
  const _SpotCommunityScoreBadge({required this.score});

  final FishingScore? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreValue = score?.scoreValue;
    final label = scoreValue == null ? 'Skor yok' : '$scoreValue';
    final background = scoreValue == null
        ? AppColors.background
        : scoreValue >= 80
            ? AppColors.successSoft
            : scoreValue >= 60
                ? AppColors.warningSoft
                : AppColors.dangerSoft;
    final foreground = scoreValue == null
        ? AppColors.textSecondary
        : scoreValue >= 80
            ? AppColors.success
            : scoreValue >= 60
                ? AppColors.warning
                : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
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
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSharerRow extends StatelessWidget {
  const _DetailSharerRow({
    required this.sharer,
    required this.currentProfileId,
    required this.onTap,
  });

  final SpotSharerIdentity sharer;
  final String currentProfileId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final secondaryLabel =
        sharer.secondaryLabel(currentProfileId: currentProfileId);
    final primaryLabel =
        sharer.primaryLabel(currentProfileId: currentProfileId);

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primarySoft,
                  backgroundImage: (sharer.avatarUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(sharer.avatarUrl!.trim())
                      : null,
                  child: (sharer.avatarUrl ?? '').trim().isEmpty
                      ? Text(
                          _initialsFromLabel(primaryLabel),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paylaşan',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (secondaryLabel != null)
                        Text(
                          secondaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.82),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _initialsFromLabel(String source) {
  final normalized = source.replaceFirst('@', '').trim();
  if (normalized.isEmpty) {
    return '?';
  }

  final parts = normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return normalized.substring(0, 1).toUpperCase();
  }
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }

  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

class _ExpandedSpotMapScreen extends StatelessWidget {
  const _ExpandedSpotMapScreen({required this.spot});

  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(spot.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _SpotLocationMap(
              latitude: spot.latitude,
              longitude: spot.longitude,
              interactive: true,
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spot.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${spot.latitude.toStringAsFixed(5)}, ${spot.longitude.toStringAsFixed(5)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotLocationMap extends StatelessWidget {
  const _SpotLocationMap({
    required this.latitude,
    required this.longitude,
    required this.interactive,
  });

  final double latitude;
  final double longitude;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = LatLng(latitude, longitude);

    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: interactive ? 14.4 : 13.8,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.fishing_app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: theme.colorScheme.onPrimary,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.avatar,
    required this.label,
  });

  final Widget avatar;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: avatar,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
