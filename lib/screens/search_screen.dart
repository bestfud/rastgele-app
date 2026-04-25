import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import 'profile_screen.dart';
import 'spot_detail_screen.dart';

void _noopSearchCallback() {}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    this.showShellChrome = false,
    this.selectedIndex = 1,
    this.onSelectTab,
    this.onOpenAddSpot = _noopSearchCallback,
    this.onOpenCreatePost = _noopSearchCallback,
    this.onOpenSearch = _noopSearchCallback,
    this.onOpenLocation = _noopSearchCallback,
    this.onOpenNotifications = _noopSearchCallback,
    this.onLogout = _noopSearchCallback,
    this.unreadNotificationCount = 0,
    this.shellAvatarUrl,
    this.shellAvatarLabel,
  });

  final SpotRepository repository;
  final bool showShellChrome;
  final int selectedIndex;
  final ValueChanged<int>? onSelectTab;
  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocation;
  final VoidCallback onOpenNotifications;
  final VoidCallback onLogout;
  final int unreadNotificationCount;
  final String? shellAvatarUrl;
  final String? shellAvatarLabel;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _searchDebounceDuration = Duration(milliseconds: 280);

  late final TextEditingController _controller;
  late final TabController _tabController;
  Timer? _searchDebounce;

  List<SpotFeedItem> _discoverableSpots = const [];
  List<AppProfile> _discoverableProfiles = const [];
  List<SpotFeedItem> _spotResults = const [];
  List<AppProfile> _profileResults = const [];
  bool _isDiscoveryLoading = true;
  bool _isSearching = false;
  String _query = '';
  int _requestToken = 0;
  int _discoveryRequestToken = 0;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;

  bool get _hasQuery => _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Search open start');
    perfLogFrame('Search', _openStopwatch);
    _controller = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    unawaited(_loadDiscovery());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.removeListener(_handleTabChanged);
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) {
      return;
    }
    setState(() {});
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();

    setState(() {
      _query = query;
      if (query.isEmpty) {
        _spotResults = const [];
        _profileResults = const [];
        _isSearching = false;
      } else {
        _spotResults = const [];
        _profileResults = const [];
        _isSearching = true;
      }
    });

    if (query.isEmpty) {
      _requestToken++;
      perfLog('Search query cleared');
      return;
    }

    _searchDebounce = Timer(_searchDebounceDuration, () {
      unawaited(_performSearch(query));
    });
  }

  Future<void> _loadDiscovery() async {
    final token = ++_discoveryRequestToken;
    try {
      final results = await Future.wait<dynamic>([
        widget.repository.fetchDiscoverableSpots(),
        widget.repository.fetchDiscoverableProfiles(),
      ]);
      if (!mounted || token != _discoveryRequestToken) {
        return;
      }

      setState(() {
        _discoverableSpots = results[0] as List<SpotFeedItem>;
        _discoverableProfiles = results[1] as List<AppProfile>;
        _isDiscoveryLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _discoveryRequestToken) {
        return;
      }

      setState(() {
        _discoverableSpots = const [];
        _discoverableProfiles = const [];
        _isDiscoveryLoading = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final token = ++_requestToken;
    final stopwatch = Stopwatch()..start();

    try {
      final results = await Future.wait<dynamic>([
        widget.repository.searchAccessibleSpots(query),
        widget.repository.searchProfiles(query),
      ]);
      stopwatch.stop();

      if (!mounted || token != _requestToken || query != _query) {
        perfLog(
          'Search stale response ignored for "$query" in ${stopwatch.elapsedMilliseconds}ms',
        );
        return;
      }

      setState(() {
        _spotResults = results[0] as List<SpotFeedItem>;
        _profileResults = results[1] as List<AppProfile>;
        _isSearching = false;
      });
      perfLog(
        'Search query "$query" complete in ${stopwatch.elapsedMilliseconds}ms spots=${_spotResults.length} profiles=${_profileResults.length}',
      );
    } catch (_) {
      stopwatch.stop();
      if (!mounted || token != _requestToken || query != _query) {
        return;
      }

      setState(() {
        _spotResults = const [];
        _profileResults = const [];
        _isSearching = false;
      });
    }
  }

  Future<void> _openSpot(SpotFeedItem item) async {
    debugPrint(
      '[SPOT_NAV] tap source=search postId=${item.sourcePostId ?? 'null'} passedSpotId=${item.spot.id} linkedSpotId=null linkedFishingSpotId=null itemSpotId=${item.spot.id}',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpotDetailScreen(
          repository: widget.repository,
          spotId: item.spot.id,
        ),
      ),
    );
  }

  Future<void> _openProfile(AppProfile profile) async {
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
          profileId: profile.id,
          showShellChrome: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
        'Search structure ready at ${_openStopwatch.elapsedMilliseconds}ms',
      );
    }

    final body = SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Mera veya kullanıcı ara',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(14),
                  child: AppIcon(
                    AppGlyph.wave,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppSurfaceSegmentedControl<int>(
              value: _tabController.index,
              options: const [
                AppSurfaceSegmentOption<int>(value: 0, label: 'Meralar'),
                AppSurfaceSegmentOption<int>(value: 1, label: 'Kullanıcılar'),
              ],
              onChanged: (index) {
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
                _SearchListSection<SpotFeedItem>(
                  mode: _hasQuery
                      ? _SearchContentMode.results
                      : _SearchContentMode.discovery,
                  isLoading: _hasQuery ? _isSearching : _isDiscoveryLoading,
                  title: _hasQuery ? 'Mera sonuçları' : 'Keşfe açık meralar',
                  description: _hasQuery
                      ? 'Aramana uyan meraları gösteriyoruz.'
                      : 'Takip etmediğin kullanıcılardan öne çıkan açık meralar.',
                  items: _hasQuery ? _spotResults : _discoverableSpots,
                  emptyMessage: _hasQuery
                      ? 'Bu aramaya uygun mera bulunamadı.'
                      : 'Şu an keşfedilecek açık mera görünmüyor.',
                  emptyIcon: const AppIcon(
                    AppGlyph.spot,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                  skeletonBuilder: (_, __) => const _SpotSearchRowSkeleton(),
                  itemBuilder: (context, item) => _SpotSearchRow(
                    item: item,
                    onTap: () => _openSpot(item),
                  ),
                ),
                _SearchListSection<AppProfile>(
                  mode: _hasQuery
                      ? _SearchContentMode.results
                      : _SearchContentMode.discovery,
                  isLoading: _hasQuery ? _isSearching : _isDiscoveryLoading,
                  title: _hasQuery
                      ? 'Kullanıcı sonuçları'
                      : 'Keşfedilecek kullanıcılar',
                  description: _hasQuery
                      ? 'Aramana uyan kullanıcı profilleri.'
                      : 'Açık içerik üreten ve göz atmaya değer kullanıcılar.',
                  items: _hasQuery ? _profileResults : _discoverableProfiles,
                  emptyMessage: _hasQuery
                      ? 'Bu aramaya uygun kullanıcı bulunamadı.'
                      : 'Şu an önerilecek kullanıcı görünmüyor.',
                  emptyIcon: const AppIcon(
                    AppGlyph.user,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                  skeletonBuilder: (_, __) => const _ProfileSearchRowSkeleton(),
                  itemBuilder: (context, profile) => _ProfileSearchRow(
                    profile: profile,
                    onTap: () => _openProfile(profile),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.showShellChrome) {
      return ShellScaffold(
        title: 'Arama',
        selectedIndex: widget.selectedIndex,
        onSelectIndex: widget.onSelectTab ?? (_) {},
        onOpenAddSpot: widget.onOpenAddSpot,
        onOpenCreatePost: widget.onOpenCreatePost,
        onOpenSearch: widget.onOpenSearch,
        onOpenLocation: widget.onOpenLocation,
        onOpenNotifications: widget.onOpenNotifications,
        unreadNotificationCount: widget.unreadNotificationCount,
        onLogout: widget.onLogout,
        headerAvatarUrl: widget.shellAvatarUrl,
        headerAvatarLabel: widget.shellAvatarLabel,
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ara'),
      ),
      body: body,
    );
  }
}

enum _SearchContentMode { discovery, results }

class _SearchListSection<T> extends StatelessWidget {
  const _SearchListSection({
    required this.mode,
    required this.isLoading,
    required this.title,
    required this.description,
    required this.items,
    required this.emptyMessage,
    required this.skeletonBuilder,
    required this.itemBuilder,
    required this.emptyIcon,
  });

  final _SearchContentMode mode;
  final bool isLoading;
  final String title;
  final String description;
  final List<T> items;
  final String emptyMessage;
  final IndexedWidgetBuilder skeletonBuilder;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: skeletonBuilder,
      );
    }

    if (items.isEmpty) {
      return AppEmptyState(
        message: emptyMessage,
        iconWidget: emptyIcon,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      itemCount: items.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchSectionHeader(
            title: title,
            description: description,
            mode: mode,
          );
        }

        return itemBuilder(context, items[index - 1]);
      },
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({
    required this.title,
    required this.description,
    required this.mode,
  });

  final String title;
  final String description;
  final _SearchContentMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mode == _SearchContentMode.discovery
            ? AppColors.card
            : AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: mode == _SearchContentMode.discovery
              ? AppColors.border
              : AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotSearchRow extends StatelessWidget {
  const _SpotSearchRow({
    required this.item,
    required this.onTap,
  });

  final SpotFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaParts = <String>[
      if ((item.spot.region ?? '').trim().isNotEmpty) item.spot.region!.trim(),
      if ((item.spot.waterType ?? '').trim().isNotEmpty)
        localizedWaterTypeLabel(item.spot.waterType),
    ];
    final decisionText = _decisionText(item.score?.scoreValue);

    return Container(
      decoration: BoxDecoration(
        boxShadow: appSoftShadow(theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.background,
                  child: AppIcon(
                    AppGlyph.spot,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (decisionText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          decisionText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          metaParts.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SearchScoreBadge(scoreValue: item.score?.scoreValue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _decisionText(int? scoreValue) {
    if (scoreValue == null) {
      return null;
    }
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
}

class _SearchScoreBadge extends StatelessWidget {
  const _SearchScoreBadge({
    required this.scoreValue,
  });

  final int? scoreValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _styleFor(scoreValue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.$2),
      ),
      child: Text(
        scoreValue?.toString() ?? '...',
        style: theme.textTheme.labelMedium?.copyWith(
          color: style.$3,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  (Color, Color, Color) _styleFor(int? scoreValue) {
    if (scoreValue == null) {
      return (
        const Color(0xFFF1F4F7),
        const Color(0xFFDCE4EA),
        const Color(0xFF52606D),
      );
    }
    if (scoreValue >= 80) {
      return (
        const Color(0xFFE8F4EC),
        const Color(0xFFCFE5D7),
        const Color(0xFF236145),
      );
    }
    if (scoreValue >= 60) {
      return (
        const Color(0xFFFFF4DE),
        const Color(0xFFF0E1B8),
        const Color(0xFF8B6724),
      );
    }
    return (
      const Color(0xFFF8E8E6),
      const Color(0xFFEACBC6),
      const Color(0xFF97493F),
    );
  }
}

class _SpotSearchRowSkeleton extends StatelessWidget {
  const _SpotSearchRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonCard(
      child: Row(
        children: [
          AppSkeletonBox(height: 40, width: 40, radius: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(height: 16, width: 150, radius: 10),
                SizedBox(height: 6),
                AppSkeletonBox(height: 13, width: 110, radius: 10),
                SizedBox(height: 6),
                AppSkeletonBox(height: 12, width: 130, radius: 10),
              ],
            ),
          ),
          SizedBox(width: 10),
          AppSkeletonBox(height: 28, width: 44, radius: 14),
        ],
      ),
    );
  }
}

class _ProfileSearchRowSkeleton extends StatelessWidget {
  const _ProfileSearchRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonCard(
      child: Row(
        children: [
          AppSkeletonBox(height: 44, width: 44, radius: 22),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(height: 16, width: 140, radius: 10),
                SizedBox(height: 8),
                AppSkeletonBox(height: 12, width: 100, radius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSearchRow extends StatelessWidget {
  const _ProfileSearchRow({
    required this.profile,
    required this.onTap,
  });

  final AppProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        boxShadow: appSoftShadow(theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Card(
        child: ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: AppColors.background,
            backgroundImage: (profile.avatarUrl ?? '').isNotEmpty
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: (profile.avatarUrl ?? '').isEmpty
                ? Text(
                    profile.initials,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          title: Text(
            profile.displayName,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: (profile.username ?? '').isEmpty
              ? null
              : Text(
                  '@${profile.username}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
        ),
      ),
    );
  }
}
