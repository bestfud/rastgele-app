import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/browser_geolocation.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import '../widgets/spot_card.dart';
import 'profile_screen.dart';
import 'spot_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.authService,
    required this.repository,
    required this.selectedIndex,
    required this.refreshSeed,
    required this.sessionSeed,
    required this.onSelectTab,
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
    required this.onOpenSearch,
    required this.onOpenLocation,
    required this.onOpenMessages,
    required this.onOpenNotifications,
    required this.onLogout,
    required this.unreadMessageCount,
    required this.unreadNotificationCount,
    this.shellAvatarUrl,
    this.shellAvatarLabel,
  });

  final AuthService authService;
  final SpotRepository repository;
  final int selectedIndex;
  final int refreshSeed;
  final int sessionSeed;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocation;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenNotifications;
  final Future<void> Function() onLogout;
  final int unreadMessageCount;
  final int unreadNotificationCount;
  final String? shellAvatarUrl;
  final String? shellAvatarLabel;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  HomeScreenData? _homeData;
  Object? _loadError;
  bool _isFeedLoading = true;
  bool _isDeferredLoading = false;
  BrowserCoordinates? _userCoordinates;
  int _loadGeneration = 0;
  List<SpotFeedItem> _savedItems = const [];
  List<SpotFeedItem> _sharedItems = const [];
  bool _isSupplementalLoading = false;
  bool _didRequestSavedItems = false;
  bool _didRequestSharedItems = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelectionChanged);
    _loadHome(reason: 'init');
    _loadUserCoordinates();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelectionChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed ||
        oldWidget.sessionSeed != widget.sessionSeed) {
      _loadHome(
        reason: oldWidget.sessionSeed != widget.sessionSeed
            ? 'session_seed_changed'
            : 'refresh_seed_changed',
        preserveData: oldWidget.sessionSeed == widget.sessionSeed,
      );
    }
  }

  Future<void> _reload() async {
    await _loadHome(reason: 'pull_to_refresh', preserveData: true);
  }

  Future<void> _loadHome({
    required String reason,
    bool preserveData = false,
  }) async {
    final generation = ++_loadGeneration;
    final cachedHomeData =
        preserveData ? _homeData : widget.repository.getCachedHomeFeedData();
    if (mounted) {
      setState(() {
        _isFeedLoading = cachedHomeData == null;
        _isDeferredLoading = false;
        _loadError = null;
        _homeData = cachedHomeData;
      });
    }

    try {
      final homeData = await widget.repository.fetchHomeFeedCards();
      final currentAuthUid = widget.authService.currentUser?.id;
      final isStaleGeneration = generation != _loadGeneration;
      final isStaleAuth = homeData.authUid != currentAuthUid;
      if (!mounted || isStaleGeneration || isStaleAuth) {
        return;
      }

      setState(() {
        _homeData = homeData;
        if (!preserveData) {
          _savedItems = const [];
          _sharedItems = const [];
          _didRequestSavedItems = false;
          _didRequestSharedItems = false;
        }
        _isFeedLoading = false;
        _isDeferredLoading = false;
        _isSupplementalLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('enrich skipped reason=lightweight_home');
        debugPrint('shared load skipped reason=not_visible');
        _maybeLoadVisibleSupplemental(generation);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loadError = error;
        _isFeedLoading = false;
        _isDeferredLoading = false;
        if (!preserveData) {
          _homeData = null;
        }
      });
    }
  }

  void _handleTabSelectionChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    _maybeLoadVisibleSupplemental(_loadGeneration);
  }

  void _maybeLoadVisibleSupplemental(int generation) {
    final filter = _selectedFilter;
    if (filter == _HomeSpotFilter.shared && !_didRequestSharedItems) {
      unawaited(_loadSharedItemsIfNeeded(generation));
    }
    if (filter == _HomeSpotFilter.saved && !_didRequestSavedItems) {
      unawaited(_loadSavedItemsIfNeeded(generation));
    }
  }

  Future<void> _loadSavedItemsIfNeeded(int generation) async {
    if (_didRequestSavedItems) {
      return;
    }
    _didRequestSavedItems = true;
    if (mounted) {
      setState(() {
        _isSupplementalLoading = true;
      });
    }
    final stopwatch = Stopwatch()..start();
    try {
      final savedItems = await widget.repository
          .fetchFavoriteSpots()
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _savedItems = savedItems;
        _isDeferredLoading = false;
        _isSupplementalLoading = false;
      });
    } catch (_) {
      _didRequestSavedItems = false;
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _isSupplementalLoading = false;
      });
    }
  }

  Future<void> _loadSharedItemsIfNeeded(int generation) async {
    if (_didRequestSharedItems) {
      return;
    }
    _didRequestSharedItems = true;
    if (mounted) {
      setState(() {
        _isSupplementalLoading = true;
      });
    }
    try {
      final sharedItems = await widget.repository
          .fetchSharedWithMeSpots()
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _sharedItems = sharedItems;
        _isSupplementalLoading = false;
      });
    } catch (_) {
      _didRequestSharedItems = false;
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _isSupplementalLoading = false;
      });
    }
  }

  Future<void> _loadUserCoordinates() async {
    final coordinates = await getBrowserCoordinates();
    if (!mounted || coordinates == null) {
      return;
    }

    setState(() {
      _userCoordinates = coordinates;
    });
  }

  Future<void> _openSpot(SpotFeedItem item) async {
    debugPrint(
      '[SPOT_NAV] tap source=home postId=${item.sourcePostId ?? 'null'} passedSpotId=${item.spot.id} linkedSpotId=null linkedFishingSpotId=null itemSpotId=${item.spot.id}',
    );
    final sharerIdentity = item.sharerIdentity;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpotDetailScreen(
          repository: widget.repository,
          spotId: item.spot.id,
          sharedBy: sharerIdentity,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openSharerProfile(SpotFeedItem item) async {
    final sharerIdentity = item.sharerIdentity;
    if (sharerIdentity == null) {
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
          onOpenMessages: widget.onOpenMessages,
          onOpenNotifications: widget.onOpenNotifications,
          unreadMessageCount: widget.unreadMessageCount,
          unreadNotificationCount: widget.unreadNotificationCount,
          onLogout: widget.onLogout,
          profileId: sharerIdentity.profileId,
          showShellChrome: false,
        ),
      ),
    );
  }

  Future<void> _toggleSavedSpot(SpotFeedItem item) async {
    final homeData = _homeData;
    if (homeData == null) {
      return;
    }

    final nextSaved = !item.isSaved;
    final previousSavedItems = _savedItems;
    final previousSharedItems = _sharedItems;
    final updatedFollowed = _updateSavedState(
      homeData.followedPublicSpots,
      spotId: item.spot.id,
      isSaved: nextSaved,
    );
    final updatedShared = _updateSavedState(
      _sharedItems,
      spotId: item.spot.id,
      isSaved: nextSaved,
    );
    final updatedSaved = nextSaved
        ? _prependIfMissing(
            _savedItems,
            _updatedSavedItem(item, isSaved: true),
          )
        : _savedItems
            .where((entry) => entry.spot.id != item.spot.id)
            .toList(growable: false);

    setState(() {
      _homeData = homeData.copyWith(followedPublicSpots: updatedFollowed);
      _sharedItems = updatedShared;
      _savedItems = updatedSaved;
    });

    try {
      await widget.repository.toggleFavorite(
        spotId: item.spot.id,
        shouldFavorite: nextSaved,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _homeData = homeData;
        _savedItems = previousSavedItems;
        _sharedItems = previousSharedItems;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextSaved
                ? 'Mera kaydedilemedi: $error'
                : 'Kayıt kaldırılamadı: $error',
          ),
        ),
      );
    }
  }

  List<SpotFeedItem> _updateSavedState(
    List<SpotFeedItem> items, {
    required String spotId,
    required bool isSaved,
  }) {
    return items
        .map(
          (entry) => entry.spot.id == spotId
              ? entry.copyWith(isSaved: isSaved)
              : entry,
        )
        .toList(growable: false);
  }

  SpotFeedItem _updatedSavedItem(
    SpotFeedItem item, {
    required bool isSaved,
  }) {
    return item.copyWith(isSaved: isSaved);
  }

  List<SpotFeedItem> _prependIfMissing(
    List<SpotFeedItem> items,
    SpotFeedItem item,
  ) {
    final withoutExisting = items
        .where((entry) => entry.spot.id != item.spot.id)
        .toList(growable: false);
    return [item, ...withoutExisting];
  }

  _HomeSpotFilter get _selectedFilter =>
      _HomeSpotFilter.values[_tabController.index];

  List<SpotFeedItem> _itemsForFilter(_HomeSpotFilter filter) {
    final followed = _homeData?.followedPublicSpots ?? const <SpotFeedItem>[];
    switch (filter) {
      case _HomeSpotFilter.following:
        return followed;
      case _HomeSpotFilter.shared:
        return _sharedItems;
      case _HomeSpotFilter.saved:
        return _savedItems;
      case _HomeSpotFilter.all:
        final merged = <SpotFeedItem>[
          ...followed,
          ..._sharedItems,
          ..._savedItems,
        ];
        final bySpotId = <String, SpotFeedItem>{};
        for (final item in merged) {
          bySpotId[item.spot.id] = item;
        }
        return bySpotId.values.toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      title: 'Ana Sayfa',
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
      onLogout: () => unawaited(widget.onLogout()),
      body: Builder(
        builder: (context) {
          final isCompactMobile = MediaQuery.of(context).size.width < 720;
          if (_loadError != null && _homeData == null) {
            return const Center(child: Text('Meralar yüklenemedi.'));
          }
          final homeData = _homeData;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  if (_isSupplementalLoading || _isDeferredLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _HomeFeedToggle(
                      value: _selectedFilter,
                      onChanged: (filter) {
                        final index = _HomeSpotFilter.values.indexOf(filter);
                        if (_tabController.index == index) {
                          return;
                        }
                        _tabController.animateTo(index);
                      },
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        for (final filter in _HomeSpotFilter.values)
                          _buildFeedPage(
                            filter,
                            homeData: homeData,
                            compact: isCompactMobile,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedPage(
    _HomeSpotFilter filter, {
    required HomeScreenData? homeData,
    required bool compact,
  }) {
    final items = _itemsForFilter(filter);
    final bestSpotId = items
        .where((item) => item.score?.scoreValue != null)
        .fold<SpotFeedItem?>(null, (best, item) {
          if (best == null) {
            return item;
          }

          return item.score!.scoreValue > best.score!.scoreValue ? item : best;
        })
        ?.spot
        .id;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            key: PageStorageKey<String>('home-feed-${filter.name}'),
            padding: EdgeInsets.fromLTRB(16, 8, 16, compact ? 124 : 24),
            children: [
              if (!compact) ...[
                _HomeFeedHeader(
                  title: _titleForFilter(filter),
                  subtitle: _subtitleForFilter(filter),
                ),
                const SizedBox(height: 14),
              ],
              if (_isFeedLoading && homeData == null) ...const [
                _HomeSpotSkeleton(),
                SizedBox(height: 12),
                _HomeSpotSkeleton(),
                SizedBox(height: 12),
                _HomeSpotSkeleton(),
              ] else if (items.isEmpty) ...[
                const SizedBox(height: 116),
                AppEmptyState(
                  iconWidget: const AppIcon(
                    AppGlyph.spot,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                  message: _emptyMessageForFilter(filter),
                ),
              ] else ...[
                if (compact) ...[
                  Text(
                    _titleForFilter(filter),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final item in items) ...[
                  SpotCard(
                    item: item,
                    currentProfileId: homeData?.profile.id,
                    distanceLabel: _distanceLabelFor(item),
                    isBestSpot: item.spot.id == bestSpotId,
                    compact: compact,
                    onTap: () => _openSpot(item),
                    onSharerTap: () => _openSharerProfile(item),
                    onToggleSaved: () => _toggleSavedSpot(item),
                  ),
                  SizedBox(height: compact ? 12 : 16),
                ],
              ],
            ],
          ),
        ),
        if ((_isFeedLoading && homeData != null) || _isDeferredLoading)
          const Positioned(
            top: 12,
            right: 16,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ),
      ],
    );
  }

  String _titleForFilter(_HomeSpotFilter filter) {
    switch (filter) {
      case _HomeSpotFilter.all:
        return 'Tüm spot akışı';
      case _HomeSpotFilter.following:
        return 'Takip ettiklerim';
      case _HomeSpotFilter.shared:
        return 'Benimle paylaşılanlar';
      case _HomeSpotFilter.saved:
        return 'Kaydettiklerim';
    }
  }

  String _subtitleForFilter(_HomeSpotFilter filter) {
    switch (filter) {
      case _HomeSpotFilter.all:
        return 'Tüm spot akışını tek yerde gör';
      case _HomeSpotFilter.following:
        return 'Takip ettiğin hesapların ve ağının spotları';
      case _HomeSpotFilter.shared:
        return 'Sana özel açılan spotlar';
      case _HomeSpotFilter.saved:
        return 'Daha sonra dönmek için işaretlediklerin';
    }
  }

  String _emptyMessageForFilter(_HomeSpotFilter filter) {
    switch (filter) {
      case _HomeSpotFilter.all:
        return 'Henüz gösterilecek spot akışı yok.';
      case _HomeSpotFilter.following:
        return 'Takip ettiğin hesapların spotları burada görünecek.';
      case _HomeSpotFilter.shared:
        return 'Seninle paylaşılan spotlar burada görünecek.';
      case _HomeSpotFilter.saved:
        return 'Kaydettiğin spotlar burada görünecek.';
    }
  }

  String? _distanceLabelFor(SpotFeedItem item) {
    final coordinates = _userCoordinates;
    if (coordinates == null) {
      return null;
    }

    final distanceKm = _distanceInKm(
      coordinates.latitude,
      coordinates.longitude,
      item.spot.latitude,
      item.spot.longitude,
    );

    return '📍 ${distanceKm.toStringAsFixed(1)} km uzaklıkta';
  }

  double _distanceInKm(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const earthRadiusKm = 6371.0;
    final latDistance = _degreesToRadians(toLatitude - fromLatitude);
    final lonDistance = _degreesToRadians(toLongitude - fromLongitude);
    final startLat = _degreesToRadians(fromLatitude);
    final endLat = _degreesToRadians(toLatitude);
    final haversine = (sin(latDistance / 2) * sin(latDistance / 2)) +
        cos(startLat) *
            cos(endLat) *
            sin(lonDistance / 2) *
            sin(lonDistance / 2);

    return 2 * earthRadiusKm * asin(sqrt(haversine));
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
}

enum _HomeSpotFilter {
  all('Tümü'),
  following('Takip ettiklerim'),
  shared('Benimle paylaşılanlar'),
  saved('Kaydettiklerim');

  const _HomeSpotFilter(this.label);

  final String label;
}

class _HomeFeedToggle extends StatelessWidget {
  const _HomeFeedToggle({
    required this.value,
    required this.onChanged,
  });

  final _HomeSpotFilter value;
  final ValueChanged<_HomeSpotFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceSegmentedControl<_HomeSpotFilter>(
      value: value,
      options: const [
        AppSurfaceSegmentOption<_HomeSpotFilter>(
          value: _HomeSpotFilter.all,
          label: 'Tümü',
        ),
        AppSurfaceSegmentOption<_HomeSpotFilter>(
          value: _HomeSpotFilter.following,
          label: 'Takip ettiklerim',
        ),
        AppSurfaceSegmentOption<_HomeSpotFilter>(
          value: _HomeSpotFilter.shared,
          label: 'Benimle paylaşılanlar',
        ),
        AppSurfaceSegmentOption<_HomeSpotFilter>(
          value: _HomeSpotFilter.saved,
          label: 'Kaydettiklerim',
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _HomeFeedHeader extends StatelessWidget {
  const _HomeFeedHeader({
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
        const SizedBox(height: 4),
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

class _HomeSpotSkeleton extends StatelessWidget {
  const _HomeSpotSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonBox(height: 24, width: 180, radius: 12),
          SizedBox(height: 10),
          AppSkeletonBox(height: 16, width: 120, radius: 10),
          SizedBox(height: 18),
          AppSkeletonBox(height: 110, radius: 20),
          SizedBox(height: 16),
          AppSkeletonBox(height: 44, radius: 18),
        ],
      ),
    );
  }
}
