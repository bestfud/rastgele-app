import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/browser_geolocation.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import '../widgets/social_post_card.dart';
import 'post_detail_screen.dart';
import 'post_location_preview_screen.dart';
import 'profile_screen.dart';
import 'spot_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.repository,
    required this.selectedIndex,
    required this.refreshSeed,
    required this.onSelectTab,
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
    required this.onOpenSearch,
    required this.onOpenLocation,
    required this.onOpenMessages,
    required this.onOpenNotifications,
    required this.unreadMessageCount,
    required this.unreadNotificationCount,
    required this.onLogout,
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
  final int unreadMessageCount;
  final int unreadNotificationCount;
  final VoidCallback onLogout;
  final String? shellAvatarUrl;
  final String? shellAvatarLabel;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  static const int _initialPageSize = 10;
  static const int _nextPageSize = 10;

  BrowserCoordinates? _userCoordinates;
  String? _locationMessage;
  late final TabController _tabController;
  final Map<_ExploreFeedFilter, _ExploreFeedState> _feedStates = {
    _ExploreFeedFilter.all: const _ExploreFeedState(),
    _ExploreFeedFilter.following: const _ExploreFeedState(),
  };
  bool _didLogInitialLoad = false;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  final Map<_ExploreFeedFilter, int> _loadGenerations = {
    _ExploreFeedFilter.all: 0,
    _ExploreFeedFilter.following: 0,
  };

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Explore open start');
    perfLogFrame('Explore', _openStopwatch);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleViewChanged);
    _loadInitialPosts(filter: _ExploreFeedFilter.all);
    _loadUserCoordinates();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleViewChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed) {
      _reload();
    }
  }

  _ExploreFeedState _stateFor(_ExploreFeedFilter filter) =>
      _feedStates[filter] ?? const _ExploreFeedState();

  void _updateFeedState(
    _ExploreFeedFilter filter,
    _ExploreFeedState Function(_ExploreFeedState current) update,
  ) {
    setState(() {
      _feedStates[filter] = update(_stateFor(filter));
    });
  }

  _ExploreView get _selectedView => _viewForIndex(_tabController.index);

  _ExploreView _viewForIndex(int index) {
    switch (index) {
      case 1:
        return _ExploreView.following;
      case 2:
        return _ExploreView.nearby;
      case 0:
      default:
        return _ExploreView.all;
    }
  }

  _ExploreFeedFilter _filterForView(_ExploreView view) {
    return view == _ExploreView.following
        ? _ExploreFeedFilter.following
        : _ExploreFeedFilter.all;
  }

  void _handleViewChanged() {
    if (!mounted || _tabController.indexIsChanging) {
      return;
    }

    final view = _selectedView;
    final filter = _filterForView(view);
    final state = _stateFor(filter);
    if (!state.hasLoadedOnce && !state.isInitialLoading) {
      unawaited(_loadInitialPosts(filter: filter));
    }
    setState(() {});
  }

  Future<void> _loadInitialPosts({
    required _ExploreFeedFilter filter,
  }) async {
    final generation = (_loadGenerations[filter] ?? 0) + 1;
    _loadGenerations[filter] = generation;
    final stopwatch = Stopwatch()..start();
    _updateFeedState(
      filter,
      (current) => current.copyWith(
        isInitialLoading: true,
        errorMessage: null,
      ),
    );

    try {
      final posts = await _fetchFeedPage(
        filter: filter,
        offset: 0,
        limit: _initialPageSize,
        includeImages: false,
      );
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }

      _updateFeedState(
        filter,
        (current) => current.copyWith(
          posts: posts,
          hasMore: posts.length >= _initialPageSize,
          isInitialLoading: false,
          hasLoadedOnce: true,
          errorMessage: null,
        ),
      );
      perfLog(
          'Explore total data load complete in ${_openStopwatch.elapsedMilliseconds}ms posts=${posts.length}');

      _scheduleImageHydration(filter, generation);
    } catch (error) {
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }

      _updateFeedState(
        filter,
        (current) => current.copyWith(
          isInitialLoading: false,
          hasLoadedOnce: true,
          errorMessage: 'Paylaşımlar yüklenemedi: $error',
        ),
      );
    } finally {
      stopwatch.stop();
      if (!_didLogInitialLoad) {
        _didLogInitialLoad = true;
        perfLog('initial Explore load took ${stopwatch.elapsedMilliseconds}ms');
      }
    }
  }

  Future<List<SocialPost>> _fetchFeedPage({
    required _ExploreFeedFilter filter,
    required int offset,
    required int limit,
    required bool includeImages,
  }) {
    switch (filter) {
      case _ExploreFeedFilter.following:
        return widget.repository.fetchPostsForFollowingFeed(
          offset: offset,
          limit: limit,
          includeImages: includeImages,
        );
      case _ExploreFeedFilter.all:
        return widget.repository.fetchRecentPosts(
          offset: offset,
          limit: limit,
          includeImages: includeImages,
        );
    }
  }

  void _scheduleImageHydration(_ExploreFeedFilter filter, int generation) {
    final sourcePosts = List<SocialPost>.from(_stateFor(filter).posts);
    if (sourcePosts.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }
      final hydrationStopwatch = Stopwatch()..start();
      final hydrated = await widget.repository.hydratePostImages(sourcePosts);
      hydrationStopwatch.stop();
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }

      final hydratedById = {
        for (final post in hydrated) post.id: post,
      };
      _updateFeedState(
        filter,
        (current) => current.copyWith(
          posts: current.posts
              .map(
                (post) => post.copyWith(
                  imageUrl: hydratedById[post.id]?.imageUrl ?? post.imageUrl,
                  imageStoragePath: hydratedById[post.id]?.imageStoragePath ??
                      post.imageStoragePath,
                ),
              )
              .toList(growable: false),
        ),
      );
      perfLog(
        'Explore deferred hydration complete in ${hydrationStopwatch.elapsedMilliseconds}ms posts=${hydrated.length} filter=$filter',
      );
    });
  }

  Future<void> _loadMore(_ExploreFeedFilter filter) async {
    final current = _stateFor(filter);
    if (current.isLoadingMore || !current.hasMore) {
      return;
    }

    final generation = _loadGenerations[filter] ?? 0;
    _updateFeedState(
      filter,
      (state) => state.copyWith(isLoadingMore: true),
    );

    try {
      final nextPosts = await _fetchFeedPage(
        filter: filter,
        offset: current.posts.length,
        limit: _nextPageSize,
        includeImages: false,
      );
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }

      _updateFeedState(
        filter,
        (state) => state.copyWith(
          posts: [...state.posts, ...nextPosts],
          hasMore: nextPosts.length >= _nextPageSize,
          isLoadingMore: false,
        ),
      );

      _scheduleImageHydration(filter, generation);
    } catch (error) {
      if (!mounted || generation != _loadGenerations[filter]) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daha fazla paylaşım yüklenemedi: $error')),
      );
    } finally {
      if (mounted && generation == _loadGenerations[filter]) {
        _updateFeedState(
          filter,
          (state) => state.copyWith(isLoadingMore: false),
        );
      }
    }
  }

  Future<void> _reload() async {
    final filter = _filterForView(_selectedView);
    perfLog('Explore reload start filter=$filter view=$_selectedView');
    await _loadInitialPosts(filter: filter);
  }

  Future<void> _loadUserCoordinates() async {
    final stopwatch = Stopwatch()..start();
    final coordinates = await getBrowserCoordinates();
    stopwatch.stop();
    perfLog(
      'Explore coordinates load took ${stopwatch.elapsedMilliseconds}ms hit=${coordinates != null}',
    );
    if (!mounted) {
      return;
    }

    if (coordinates == null) {
      setState(() {
        _locationMessage = 'Konum izni verilmedi, normal akış gösteriliyor.';
      });
      return;
    }

    setState(() {
      _userCoordinates = coordinates;
      _locationMessage = null;
    });
  }

  Future<void> _toggleLike(String postId) async {
    final currentFilter = _filterForView(_selectedView);
    final originalPosts = List<SocialPost>.from(_stateFor(currentFilter).posts);
    final index = originalPosts.indexWhere((post) => post.id == postId);
    if (index == -1) {
      return;
    }

    final post = originalPosts[index];
    final updatedPost = post.copyWith(
      isLiked: !post.isLiked,
      likeCount: post.isLiked
          ? (post.likeCount > 0 ? post.likeCount - 1 : 0)
          : post.likeCount + 1,
    );
    final updatedPosts = List<SocialPost>.from(originalPosts);
    updatedPosts[index] = updatedPost;

    void applyToAllStates(List<SocialPost> replacement) {
      setState(() {
        for (final filter in _feedStates.keys) {
          final posts = _stateFor(filter).posts;
          final targetIndex = posts.indexWhere((post) => post.id == postId);
          if (targetIndex == -1) {
            continue;
          }
          final nextPosts = List<SocialPost>.from(posts);
          nextPosts[targetIndex] = replacement[index];
          _feedStates[filter] = _stateFor(filter).copyWith(posts: nextPosts);
        }
      });
    }

    applyToAllStates(updatedPosts);

    try {
      await widget.repository.toggleLike(post.id);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        for (final filter in _feedStates.keys) {
          final posts = _stateFor(filter).posts;
          final targetIndex = posts.indexWhere((item) => item.id == postId);
          if (targetIndex == -1) {
            continue;
          }
          final nextPosts = List<SocialPost>.from(posts);
          nextPosts[targetIndex] = originalPosts[index];
          _feedStates[filter] = _stateFor(filter).copyWith(posts: nextPosts);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beğeni durumu güncellenemedi: $error')),
      );
    }
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

    _replacePost(updatedPost);
  }

  Future<void> _openAuthorProfile(SocialPost post) async {
    final profileId = post.authorProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bilgisi yüklenemedi')),
      );
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
          profileId: profileId,
          showShellChrome: false,
        ),
      ),
    );
  }

  Future<void> _openPostLocation(SocialPost post) async {
    if (post.hasExactSpotAction && (post.linkedSpotId ?? '').isNotEmpty) {
      debugPrint(
        '[SPOT_NAV] tap source=explore postId=${post.id} passedSpotId=${post.linkedSpotId!} linkedSpotId=${post.linkedSpotId ?? 'null'} linkedFishingSpotId=${post.linkedFishingSpotId ?? 'null'} itemSpotId=null visibility=${post.visibilityValue}',
      );
      try {
        await widget.repository.fetchSpotDetail(post.linkedSpotId!);
        if (!mounted) {
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SpotDetailScreen(
              repository: widget.repository,
              spotId: post.linkedSpotId!,
            ),
          ),
        );
      } catch (error) {
        debugPrint(
          '[SPOT_NAV] failure source=explore postId=${post.id} passedSpotId=${post.linkedSpotId!} error=$error',
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
      return;
    }

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

  void _replacePost(SocialPost updatedPost) {
    setState(() {
      for (final filter in _feedStates.keys) {
        final posts = _stateFor(filter).posts;
        final index = posts.indexWhere((post) => post.id == updatedPost.id);
        if (index == -1) {
          continue;
        }
        final updatedPosts = List<SocialPost>.from(posts);
        updatedPosts[index] = updatedPost;
        _feedStates[filter] = _stateFor(filter).copyWith(posts: updatedPosts);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activePosts = _postsForView(
      _stateFor(_filterForView(_selectedView)).posts,
      view: _selectedView,
    );
    final activeState = _stateFor(_filterForView(_selectedView));
    if (!_didLogMeaningfulPaint &&
        (activeState.isInitialLoading ||
            activePosts.isNotEmpty ||
            activeState.errorMessage != null)) {
      _didLogMeaningfulPaint = true;
      perfLog(
          'Explore structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
    }

    return ShellScaffold(
      title: 'Keşfet',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _FeedViewToggle(
              value: _selectedView,
              onChanged: (view) {
                final index = switch (view) {
                  _ExploreView.all => 0,
                  _ExploreView.following => 1,
                  _ExploreView.nearby => 2,
                };
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
                _buildFeed(_ExploreView.all),
                _buildFeed(_ExploreView.following),
                _buildFeed(_ExploreView.nearby),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed(_ExploreView view) {
    final filter = _filterForView(view);
    final state = _stateFor(filter);
    final posts = _postsForView(state.posts, view: view);

    if (state.isInitialLoading && posts.isEmpty) {
      return _buildLoadingFeed();
    }

    if (state.errorMessage != null && posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(state.errorMessage!),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _reload,
          child: _buildFeedList(view, posts),
        ),
        if (state.isInitialLoading)
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

  Widget _buildLoadingFeed() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: const [
            AppSkeletonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonBox(height: 46, radius: 999),
                ],
              ),
            ),
            SizedBox(height: 16),
            _ExplorePostSkeleton(),
            SizedBox(height: 16),
            _ExplorePostSkeleton(),
            SizedBox(height: 16),
            _ExplorePostSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedList(_ExploreView view, List<SocialPost> posts) {
    final filter = _filterForView(view);
    final state = _stateFor(filter);
    if (posts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (_locationMessage != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _locationMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 72),
          AppEmptyState(
            iconWidget: AppIcon(
              view == _ExploreView.following ? AppGlyph.user : AppGlyph.wave,
              size: 24,
              color: AppColors.textSecondary,
            ),
            message: view == _ExploreView.following
                ? 'Takip ettiğin hesaplar paylaşım yaptığında burada göreceksin.'
                : view == _ExploreView.nearby
                    ? 'Yakınınızda gösterilecek paylaşım bulunmuyor.'
                    : 'Henüz gösterilecek paylaşım yok.',
          ),
        ],
      );
    }

    final hasLocationHeader = _locationMessage != null;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: posts.length + (hasLocationHeader ? 2 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (hasLocationHeader && index == 0) {
          return Text(
            _locationMessage!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }

        final loadMoreIndex = posts.length + (hasLocationHeader ? 1 : 0);
        if (index == loadMoreIndex) {
          if (!state.hasMore && !state.isLoadingMore) {
            return const SizedBox.shrink();
          }

          return Center(
            child: state.isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(),
                  )
                : TextButton(
                    onPressed: () => _loadMore(filter),
                    child: const Text('Daha fazla'),
                  ),
          );
        }

        final postIndex = hasLocationHeader ? index - 1 : index;
        final post = posts[postIndex];
        return SocialPostCard(
          post: post,
          onLike: () => _toggleLike(post.id),
          onTap: () => _openPost(post),
          onOpenAuthor: () => _openAuthorProfile(post),
          onOpenComments: () => _openPost(post),
          onOpenSpot:
              post.hasExactSpotAction ? () => _openPostLocation(post) : null,
          onOpenMap: post.hasApproxLocationAction
              ? () => _openPostLocation(post)
              : null,
          onOpenLocation:
              post.hasLocationAction ? () => _openPostLocation(post) : null,
        );
      },
    );
  }

  List<SocialPost> _postsForView(
    List<SocialPost> posts, {
    required _ExploreView view,
  }) {
    final enriched = posts.map(_withDistance).toList();
    if (view != _ExploreView.nearby || _userCoordinates == null) {
      return enriched;
    }

    enriched.sort((a, b) {
      final left = a.distanceKm;
      final right = b.distanceKm;
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return left.compareTo(right);
    });

    return enriched;
  }

  SocialPost _withDistance(SocialPost post) {
    final user = _userCoordinates;
    if (user == null || post.latitude == null || post.longitude == null) {
      return post.copyWith(distanceKm: null);
    }

    return post.copyWith(
      distanceKm: _distanceInKm(
        user.latitude,
        user.longitude,
        post.latitude!,
        post.longitude!,
      ),
    );
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

class _ExplorePostSkeleton extends StatelessWidget {
  const _ExplorePostSkeleton();

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
                    AppSkeletonBox(height: 12, width: 160, radius: 10),
                  ],
                ),
              ),
              AppSkeletonBox(height: 30, width: 72, radius: 999),
            ],
          ),
          SizedBox(height: 18),
          AppSkeletonBox(height: 14, radius: 10),
          SizedBox(height: 8),
          AppSkeletonBox(height: 14, width: 210, radius: 10),
          SizedBox(height: 18),
          AppSkeletonBox(height: 180, radius: 22),
          SizedBox(height: 16),
          AppSkeletonBox(height: 44, radius: 14),
        ],
      ),
    );
  }
}

enum _ExploreFeedFilter { all, following }

enum _ExploreView { all, following, nearby }

class _FeedViewToggle extends StatelessWidget {
  const _FeedViewToggle({
    required this.value,
    required this.onChanged,
  });

  final _ExploreView value;
  final ValueChanged<_ExploreView> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = _FeedViewToggleOption.values;

    void moveSelection(int direction) {
      final currentIndex = options.indexWhere((option) => option.view == value);
      if (currentIndex == -1) {
        return;
      }
      final nextIndex = (currentIndex + direction).clamp(0, options.length - 1);
      if (nextIndex == currentIndex) {
        return;
      }
      onChanged(options[nextIndex].view);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 180) {
          return;
        }
        moveSelection(velocity < 0 ? 1 : -1);
      },
      child: AppSurfaceSegmentedControl<_ExploreView>(
        value: value,
        options: const [
          AppSurfaceSegmentOption<_ExploreView>(
            value: _ExploreView.all,
            label: 'Tümü',
          ),
          AppSurfaceSegmentOption<_ExploreView>(
            value: _ExploreView.following,
            label: 'Takip ettiklerim',
          ),
          AppSurfaceSegmentOption<_ExploreView>(
            value: _ExploreView.nearby,
            label: 'Yakındakiler',
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

enum _FeedViewToggleOption {
  all(_ExploreView.all, 'Tümü'),
  following(_ExploreView.following, 'Takip ettiklerim'),
  nearby(_ExploreView.nearby, 'Yakındakiler');

  const _FeedViewToggleOption(this.view, this.label);

  final _ExploreView view;
  final String label;
}

class _ExploreFeedState {
  static const Object _sentinel = Object();

  const _ExploreFeedState({
    this.posts = const [],
    this.isInitialLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.hasLoadedOnce = false,
    this.errorMessage,
  });

  final List<SocialPost> posts;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool hasLoadedOnce;
  final String? errorMessage;

  _ExploreFeedState copyWith({
    List<SocialPost>? posts,
    bool? isInitialLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? hasLoadedOnce,
    Object? errorMessage = _sentinel,
  }) {
    return _ExploreFeedState(
      posts: posts ?? this.posts,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
