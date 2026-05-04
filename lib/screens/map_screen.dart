import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../services/browser_geolocation.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import 'add_spot_screen.dart';
import 'post_detail_screen.dart';
import 'spot_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
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
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  static const LatLng _mudanyaCenter = LatLng(40.375, 28.883);
  static const double _defaultMapZoom = 12.8;
  static const _MapFreezeIsolationMode _finalIsolationMode =
      _MapFreezeIsolationMode.selectedStateWithPopup;

  final MapController _mapController = MapController();
  late final AnimationController _cameraAnimationController;
  List<SpotFeedItem>? _spotItems;
  List<SocialPost>? _postItems;
  Object? _spotLoadError;
  Object? _postLoadError;
  bool _isSpotLayerLoading = false;
  bool _isSpotLayerEnriching = false;
  bool _isPostLayerLoading = false;
  String? _selectedSpotId;
  String? _selectedPostId;
  SpotFeedItem? _activeSpotPreviewItem;
  _PendingSpotMarker? _pendingSpotMarker;
  _MapLayerFilter _filter = _MapLayerFilter.all;
  bool _didLogInitialMapLoad = false;
  int _reloadGeneration = 0;
  final Stopwatch _openStopwatch = Stopwatch();
  bool _didLogMeaningfulPaint = false;
  String? _lastMarkerSummary;
  LatLng? _currentLocation;
  bool _didCenterOnCurrentLocation = false;
  bool _isMapReady = false;
  bool _pendingAnimateToUser = false;
  bool _showMapSurface = false;
  late LatLng _cameraCenter;
  double _cameraZoom = _defaultMapZoom;
  LatLngBounds? _visibleBounds;
  bool _ignoreMapTapOnce = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[map-freeze][final] mode=${_finalIsolationMode.label}');
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _cameraCenter = _mudanyaCenter;
    _openStopwatch.start();
    perfLog('Map open start');
    perfLogFrame('Map', _openStopwatch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showMapSurface = true;
      });
      unawaited(_loadCurrentLocation());
      unawaited(_reload(forceRefresh: true, includePosts: false));
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _postItems != null || _filter == _MapLayerFilter.spots) {
          return;
        }
        unawaited(_reload(forceRefresh: false, includeSpots: false));
      });
    });
  }

  @override
  void dispose() {
    _cameraAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed) {
      _reload(forceRefresh: true);
    }
  }

  Future<void> _reload({
    bool forceRefresh = true,
    bool includeSpots = true,
    bool includePosts = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final generation = ++_reloadGeneration;
    final shouldLoadSpots = includeSpots &&
        _filter != _MapLayerFilter.posts &&
        (forceRefresh || _spotItems == null);
    final shouldLoadPosts = includePosts &&
        _filter != _MapLayerFilter.spots &&
        (forceRefresh || _postItems == null);

    setState(() {
      if (shouldLoadSpots) {
        _isSpotLayerLoading = true;
        _isSpotLayerEnriching = false;
        _spotLoadError = null;
      }
      if (shouldLoadPosts) {
        _isPostLayerLoading = true;
        _postLoadError = null;
      }
    });

    final tasks = <Future<void>>[];

    if (shouldLoadSpots) {
      tasks.add(_reloadSpotLayer(generation));
    }

    if (shouldLoadPosts) {
      tasks.add(_reloadPostLayer(generation));
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    {
      stopwatch.stop();
      final label =
          _didLogInitialMapLoad ? 'map data loading' : 'initial Map load';
      _didLogInitialMapLoad = true;
      perfLog('$label took ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<void> _loadCurrentLocation() async {
    final coordinates = await getBrowserCoordinates();
    if (!mounted) {
      return;
    }
    if (coordinates == null) {
      debugPrint('[MAP_LOC] getCurrentPosition failure error=null_position');
      return;
    }

    final currentLocation = LatLng(
      coordinates.latitude,
      coordinates.longitude,
    );
    setState(() {
      _currentLocation = currentLocation;
    });

    if (_didCenterOnCurrentLocation) {
      return;
    }

    _didCenterOnCurrentLocation = true;
    _animateToUserIfPossible(
      reason: 'initial_location_fetch',
      targetZoom: _defaultMapZoom,
    );
  }

  Future<void> _moveToCurrentLocation() async {
    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      _animateToUserIfPossible(
        reason: 'locate_button_existing_position',
        targetZoom: _defaultMapZoom + 0.4,
      );
      return;
    }

    await _loadCurrentLocation();
    if (!mounted || _currentLocation == null) {
      debugPrint('[MAP_LOC] animateToUser skipped reason=position_null');
      return;
    }

    _animateToUserIfPossible(
      reason: 'locate_button_after_fetch',
      targetZoom: _defaultMapZoom + 0.4,
    );
  }

  void _animateToUserIfPossible({
    required String reason,
    required double targetZoom,
  }) {
    if (!_isMapReady) {
      _pendingAnimateToUser = true;
      debugPrint(
        '[MAP_LOC] animateToUser skipped reason=controller_not_ready',
      );
      return;
    }
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      debugPrint('[MAP_LOC] animateToUser skipped reason=position_null');
      return;
    }

    _pendingAnimateToUser = false;
    _animateMapTo(currentLocation, targetZoom);
  }

  void _animateMapTo(LatLng target, double targetZoom) {
    final startCenter = _cameraCenter;
    final startZoom = _cameraZoom;
    final latTween = Tween<double>(
      begin: startCenter.latitude,
      end: target.latitude,
    );
    final lngTween = Tween<double>(
      begin: startCenter.longitude,
      end: target.longitude,
    );
    final zoomTween = Tween<double>(
      begin: startZoom,
      end: targetZoom,
    );
    final animation = CurvedAnimation(
      parent: _cameraAnimationController,
      curve: Curves.easeOutCubic,
    );

    void listener() {
      final nextCenter = LatLng(
        latTween.evaluate(animation),
        lngTween.evaluate(animation),
      );
      final nextZoom = zoomTween.evaluate(animation);
      _mapController.move(nextCenter, nextZoom);
    }

    _cameraAnimationController
      ..stop()
      ..reset()
      ..removeListener(listener)
      ..addListener(listener);

    _cameraAnimationController.forward().whenCompleteOrCancel(() {
      _cameraAnimationController.removeListener(listener);
      _cameraCenter = target;
      _cameraZoom = targetZoom;
    });
  }

  bool _updateCameraState(MapCamera camera) {
    final nextCenter = camera.center;
    final nextZoom = camera.zoom;
    final nextBounds = camera.visibleBounds;

    final centerChanged =
        (_cameraCenter.latitude - nextCenter.latitude).abs() > 0.00001 ||
            (_cameraCenter.longitude - nextCenter.longitude).abs() > 0.00001;
    final zoomChanged = (_cameraZoom - nextZoom).abs() > 0.01;
    final boundsChanged = _visibleBounds == null ||
        (_visibleBounds!.north - nextBounds.north).abs() > 0.00001 ||
        (_visibleBounds!.south - nextBounds.south).abs() > 0.00001 ||
        (_visibleBounds!.east - nextBounds.east).abs() > 0.00001 ||
        (_visibleBounds!.west - nextBounds.west).abs() > 0.00001;

    _cameraCenter = nextCenter;
    _cameraZoom = nextZoom;
    _visibleBounds = nextBounds;

    return centerChanged || zoomChanged || boundsChanged;
  }

  Future<List<SpotFeedItem>> _loadSpotLayerForFilter(
      _MapLayerFilter filter) async {
    switch (filter) {
      case _MapLayerFilter.posts:
        return _spotItems ?? const <SpotFeedItem>[];
      case _MapLayerFilter.spots:
      case _MapLayerFilter.all:
        return widget.repository.fetchGlobalVisibleSpots(
          includeScores: false,
          includeWeather: false,
          limit: 32,
        );
    }
  }

  Future<List<SocialPost>> _loadPostLayerForFilter(
      _MapLayerFilter filter) async {
    switch (filter) {
      case _MapLayerFilter.spots:
        return _postItems ?? const <SocialPost>[];
      case _MapLayerFilter.posts:
      case _MapLayerFilter.all:
        final posts = await widget.repository.fetchRecentPosts(
          limit: 8,
          includeImages: false,
        );
        return posts
            .where((post) => post.latitude != null && post.longitude != null)
            .toList(growable: false);
    }
  }

  void _onFilterChanged(_MapLayerFilter filter) {
    if (_filter == filter) {
      return;
    }

    setState(() {
      _filter = filter;
      _activeSpotPreviewItem = null;
      _selectedSpotId = null;
    });

    final needsSpots = filter != _MapLayerFilter.posts && _spotItems == null;
    final needsPosts = filter != _MapLayerFilter.spots && _postItems == null;
    if (needsSpots || needsPosts) {
      _reload(forceRefresh: false);
    }
  }

  Future<void> _reloadSpotLayer(int generation) async {
    try {
      final items = await _loadSpotLayerForFilter(_filter);
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _spotItems = items;
        _pendingSpotMarker = null;
        _isSpotLayerLoading = false;
        if (_activeSpotPreviewItem != null) {
          _activeSpotPreviewItem = items
              .where((item) => item.spot.id == _activeSpotPreviewItem!.spot.id)
              .cast<SpotFeedItem?>()
              .firstWhere((item) => item != null, orElse: () => null);
          if (_activeSpotPreviewItem == null) {
            _selectedSpotId = null;
          }
        }
      });
      perfLog(
          'Map spot layer ready in ${_openStopwatch.elapsedMilliseconds}ms items=${items.length}');

      if (items.isEmpty) {
        return;
      }

      setState(() {
        _isSpotLayerEnriching = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _enrichSpotLayer(items, generation);
      });
    } catch (error) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _spotLoadError = error;
        _isSpotLayerLoading = false;
        _isSpotLayerEnriching = false;
      });
    }
  }

  Future<void> _enrichSpotLayer(
      List<SpotFeedItem> items, int generation) async {
    final stopwatch = Stopwatch()..start();
    try {
      final enrichedItems = await widget.repository.enrichSpotFeedItems(
        items.take(5).toList(growable: false),
        includeScores: true,
        includeWeather: true,
      );
      stopwatch.stop();
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _spotItems = enrichedItems;
        _isSpotLayerEnriching = false;
      });
      perfLog(
        'Map deferred spot layer enrichment complete in ${stopwatch.elapsedMilliseconds}ms items=${enrichedItems.length}',
      );
    } catch (error) {
      stopwatch.stop();
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _isSpotLayerEnriching = false;
      });
      perfLog(
        'Map deferred spot layer enrichment failed in ${stopwatch.elapsedMilliseconds}ms: $error',
      );
    }
  }

  Future<void> _reloadPostLayer(int generation) async {
    try {
      final posts = await _loadPostLayerForFilter(_filter);
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _postItems = posts
            .where((post) => post.latitude != null && post.longitude != null)
            .toList(growable: false);
        _isPostLayerLoading = false;
      });
      perfLog(
        'Map post layer ready in ${_openStopwatch.elapsedMilliseconds}ms items=${_postItems?.length ?? 0}',
      );
    } catch (error) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }

      setState(() {
        _postLoadError = error;
        _isPostLayerLoading = false;
      });
    }
  }

  void _handleSpotTap(SpotFeedItem item) {
    _markMarkerInteraction();
    debugPrint('[map-freeze][final] marker tapped spot=${item.spot.id}');
    switch (_finalIsolationMode) {
      case _MapFreezeIsolationMode.markerTapOnly:
        return;
      case _MapFreezeIsolationMode.selectedStateOnly:
        setState(() {
          _selectedSpotId = item.spot.id;
          _selectedPostId = null;
          _activeSpotPreviewItem = null;
        });
        debugPrint(
          '[map-freeze][final] selectedSpot updated id=${item.spot.id}',
        );
        return;
      case _MapFreezeIsolationMode.selectedStateWithPopup:
        setState(() {
          _activeSpotPreviewItem = item;
          _selectedSpotId = item.spot.id;
          _selectedPostId = null;
        });
        debugPrint(
          '[map-freeze][final] selectedSpot updated id=${item.spot.id}',
        );
        return;
    }
  }

  void _closeSpotPreview() {
    if (_activeSpotPreviewItem == null &&
        _selectedSpotId == null &&
        _selectedPostId == null) {
      return;
    }

    setState(() {
      _activeSpotPreviewItem = null;
      _selectedSpotId = null;
      _selectedPostId = null;
    });
    debugPrint('[map-freeze][fix] popup closed');
  }

  void _markMarkerInteraction() {
    _ignoreMapTapOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ignoreMapTapOnce = false;
    });
  }

  void _handleMapTap() {
    if (_ignoreMapTapOnce) {
      return;
    }

    _closeSpotPreview();
  }

  Future<void> _handlePostTap(SocialPost post) async {
    _markMarkerInteraction();
    debugPrint('[map-rebuild][truth] marker tapped post=${post.id}');
    setState(() {
      _selectedPostId = post.id;
      _selectedSpotId = null;
      _activeSpotPreviewItem = null;
    });

    final updatedPost = await Navigator.of(context).push<SocialPost>(
      MaterialPageRoute<SocialPost>(
        builder: (_) => PostDetailScreen(
          repository: widget.repository,
          post: post,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      if (updatedPost != null && _postItems != null) {
        _postItems = _postItems!
            .map((item) => item.id == updatedPost.id ? updatedPost : item)
            .toList(growable: false);
      }
      _selectedPostId = null;
    });
  }

  Future<void> _openSpotDetail(SpotFeedItem item) async {
    debugPrint(
      '[SPOT_NAV] tap source=map postId=${item.sourcePostId ?? 'null'} passedSpotId=${item.spot.id} linkedSpotId=null linkedFishingSpotId=null itemSpotId=${item.spot.id}',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpotDetailScreen(
          repository: widget.repository,
          spotId: item.spot.id,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  bool _shouldRenderSpotPopup() {
    final shouldRender =
        _finalIsolationMode == _MapFreezeIsolationMode.selectedStateWithPopup &&
            _activeSpotPreviewItem != null;
    if (shouldRender) {
      debugPrint(
        '[map-freeze][fix] popup render started id=${_activeSpotPreviewItem!.spot.id}',
      );
    }
    return shouldRender;
  }

  Future<void> _startAddSpotFlow(LatLng position) async {
    setState(() {
      _pendingSpotMarker = _PendingSpotMarker(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    });

    final createdSpot = await Navigator.of(context).push<FishingSpot>(
      MaterialPageRoute<FishingSpot>(
        builder: (_) => AddSpotScreen(
          repository: widget.repository,
          initialLatitude: position.latitude,
          initialLongitude: position.longitude,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (createdSpot == null) {
      setState(() {
        _pendingSpotMarker = null;
      });
      return;
    }

    setState(() {
      _pendingSpotMarker = null;
    });

    try {
      await _reload();

      if (!mounted) {
        return;
      }

      setState(() {
        final existingItems = _spotItems ?? const <SpotFeedItem>[];
        final alreadyPresent =
            existingItems.any((item) => item.spot.id == createdSpot.id);
        if (!alreadyPresent && _filter != _MapLayerFilter.posts) {
          _spotItems = [
            SpotFeedItem(spot: createdSpot),
            ...existingItems,
          ];
        }
        _selectedSpotId = createdSpot.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingSpotMarker = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mera kaydedilemedi. Lütfen tekrar deneyin.'),
        ),
      );
    }
  }

  _MapView _initialMapView() {
    return _MapView(
      center: _currentLocation ?? _mudanyaCenter,
      zoom: _defaultMapZoom,
    );
  }

  List<SpotFeedItem> _spotsInView(List<SpotFeedItem> items) {
    final bounds = _visibleBounds;
    if (bounds == null) {
      return items;
    }

    return items.where((item) {
      final latitude = item.spot.latitude;
      final longitude = item.spot.longitude;
      return latitude <= bounds.north &&
          latitude >= bounds.south &&
          longitude >= bounds.west &&
          longitude <= bounds.east;
    }).toList(growable: false);
  }

  List<_SpotNode> _buildSpotNodes(List<SpotFeedItem> items) {
    if (items.isEmpty) {
      return const <_SpotNode>[];
    }

    if (_cameraZoom >= 14.2) {
      return items
          .map(
            (item) => _SpotNode.single(
              key: item.spot.id,
              item: item,
            ),
          )
          .toList(growable: false);
    }

    final bucketMeters = _clusterBucketMeters(_cameraZoom);
    final latitudeBucket = bucketMeters / 111320;
    final longitudeBucket = bucketMeters /
        (111320 *
            math.max(
              0.24,
              math.cos(_cameraCenter.latitude * math.pi / 180),
            ));

    final buckets = <String, List<SpotFeedItem>>{};
    for (final item in items) {
      final latKey = (item.spot.latitude / latitudeBucket).floor();
      final lngKey = (item.spot.longitude / longitudeBucket).floor();
      buckets.putIfAbsent('$latKey:$lngKey', () => <SpotFeedItem>[]).add(item);
    }

    return buckets.entries.map((entry) {
      final bucketItems = entry.value;
      if (bucketItems.length == 1) {
        return _SpotNode.single(
          key: bucketItems.first.spot.id,
          item: bucketItems.first,
        );
      }

      final centerLatitude = bucketItems
              .map((item) => item.spot.latitude)
              .reduce((a, b) => a + b) /
          bucketItems.length;
      final centerLongitude = bucketItems
              .map((item) => item.spot.longitude)
              .reduce((a, b) => a + b) /
          bucketItems.length;
      final scoredItems = bucketItems
          .where((item) => item.score != null)
          .toList(growable: false);
      final averageScore = scoredItems.isEmpty
          ? null
          : scoredItems
                  .map((item) => item.score!.scoreValue)
                  .reduce((a, b) => a + b) /
              scoredItems.length;

      return _SpotNode.cluster(
        key: entry.key,
        items: bucketItems,
        center: LatLng(centerLatitude, centerLongitude),
        averageScore: averageScore,
      );
    }).toList(growable: false);
  }

  double _clusterBucketMeters(double zoom) {
    if (zoom <= 8.5) {
      return 5200;
    }
    if (zoom <= 10) {
      return 3200;
    }
    if (zoom <= 11.5) {
      return 1800;
    }
    if (zoom <= 13) {
      return 950;
    }
    return 500;
  }

  _BestSpotContext? _bestSpotContext(List<SpotFeedItem> items) {
    final eligibleItems = items
        .where((item) => item.score?.scoreValue != null)
        .toList(growable: false);
    if (eligibleItems.isEmpty) {
      return null;
    }

    eligibleItems.sort((a, b) {
      final scoreCompare = (b.score!.scoreValue).compareTo(a.score!.scoreValue);
      if (scoreCompare != 0) {
        return scoreCompare;
      }

      final distanceCompare =
          _distanceToCurrent(a).compareTo(_distanceToCurrent(b));
      if (distanceCompare != 0) {
        return distanceCompare;
      }

      final aTime = a.score?.scoreTime ?? a.spot.createdAt ?? DateTime(1970);
      final bTime = b.score?.scoreTime ?? b.spot.createdAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return _BestSpotContext(item: eligibleItems.first);
  }

  double _distanceToCurrent(SpotFeedItem item) {
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      return double.infinity;
    }

    return const Distance().as(
      LengthUnit.Kilometer,
      currentLocation,
      LatLng(item.spot.latitude, item.spot.longitude),
    );
  }

  Future<void> _handleBestSpotTap(_BestSpotContext bestSpot) async {
    _markMarkerInteraction();
    debugPrint(
      '[map-freeze][final] marker tapped best-spot=${bestSpot.item.spot.id}',
    );
    final focusPoint = LatLng(
      bestSpot.item.spot.latitude,
      bestSpot.item.spot.longitude,
    );
    switch (_finalIsolationMode) {
      case _MapFreezeIsolationMode.markerTapOnly:
        break;
      case _MapFreezeIsolationMode.selectedStateOnly:
        setState(() {
          _selectedSpotId = bestSpot.item.spot.id;
          _selectedPostId = null;
          _activeSpotPreviewItem = null;
        });
        debugPrint(
          '[map-freeze][final] selectedSpot updated id=${bestSpot.item.spot.id}',
        );
        break;
      case _MapFreezeIsolationMode.selectedStateWithPopup:
        setState(() {
          _activeSpotPreviewItem = bestSpot.item;
          _selectedSpotId = bestSpot.item.spot.id;
          _selectedPostId = null;
        });
        debugPrint(
          '[map-freeze][final] selectedSpot updated id=${bestSpot.item.spot.id}',
        );
        break;
    }
    _animateMapTo(focusPoint, math.max(_cameraZoom, 14.6));
  }

  void _handleClusterTap(_SpotNode cluster) {
    if (!cluster.isCluster) {
      return;
    }

    _markMarkerInteraction();
    debugPrint('[map-freeze][audit] marker tapped cluster=${cluster.key}');
    _closeSpotPreview();
    _animateMapTo(
      cluster.center!,
      math.min(_cameraZoom + 1.7, 15.2),
    );
  }

  List<Marker> _markers({
    required List<SocialPost> posts,
    required List<_SpotNode> spotNodes,
    required String? bestSpotId,
  }) {
    final markers = <Marker>[];

    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 28,
          height: 28,
          child: const IgnorePointer(
            child: _MapMarkerBadge(
              color: AppColors.primary,
              label: '',
              size: 20,
              textStyle: null,
            ),
          ),
        ),
      );
    }

    if (_filter != _MapLayerFilter.posts) {
      markers.addAll(
        spotNodes.map((node) {
          if (node.isCluster) {
            return Marker(
              point: node.center!,
              width: 42,
              height: 42,
              child: GestureDetector(
                onTap: () => _handleClusterTap(node),
                child: _MapMarkerBadge(
                  color: _scoreBandFill(_scoreBand(node.averageScore?.round())),
                  label: '${node.count}',
                  size: 34,
                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                ),
              ),
            );
          }

          final item = node.item!;
          final isBestSpot = item.spot.id == bestSpotId;
          final isSelected = item.spot.id == _selectedSpotId;

          return Marker(
            point: LatLng(item.spot.latitude, item.spot.longitude),
            width: 46,
            height: 46,
            child: GestureDetector(
              onTap: () => _handleSpotTap(item),
              child: _MapSpotMarker(
                score: item.score?.scoreValue,
                isSelected: isSelected,
                isBestSpot: isBestSpot,
              ),
            ),
          );
        }),
      );
    }

    if (_filter != _MapLayerFilter.spots) {
      markers.addAll(
        posts
            .where((post) => post.latitude != null && post.longitude != null)
            .map(
          (post) {
            final isSelected = post.id == _selectedPostId;
            return Marker(
              point: LatLng(post.latitude!, post.longitude!),
              width: 44,
              height: 52,
              child: GestureDetector(
                onTap: () => _handlePostTap(post),
                child: _MapPostMarker(
                  isSelected: isSelected,
                  commentCount: post.commentCount,
                ),
              ),
            );
          },
        ),
      );
    }

    final pendingSpotMarker = _pendingSpotMarker;
    if (pendingSpotMarker != null && _filter != _MapLayerFilter.posts) {
      markers.add(
        Marker(
          point:
              LatLng(pendingSpotMarker.latitude, pendingSpotMarker.longitude),
          width: 34,
          height: 34,
          child: const _MapMarkerBadge(
            color: AppColors.primary,
            label: '',
            size: 24,
            textStyle: null,
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final items = _spotItems ?? const <SpotFeedItem>[];
    final posts = _postItems ?? const <SocialPost>[];
    final visibleItems =
        _filter == _MapLayerFilter.posts ? const <SpotFeedItem>[] : items;
    final visiblePosts =
        _filter == _MapLayerFilter.spots ? const <SocialPost>[] : posts;
    final isCurrentFilterLoading = switch (_filter) {
      _MapLayerFilter.spots => _isSpotLayerLoading || _isSpotLayerEnriching,
      _MapLayerFilter.posts => _isPostLayerLoading,
      _MapLayerFilter.all =>
        _isSpotLayerLoading || _isSpotLayerEnriching || _isPostLayerLoading,
    };
    final loadError = switch (_filter) {
      _MapLayerFilter.spots => _spotLoadError,
      _MapLayerFilter.posts => _postLoadError,
      _MapLayerFilter.all => _spotLoadError ?? _postLoadError,
    };
    final hasVisibleMarkers = switch (_filter) {
      _MapLayerFilter.spots => visibleItems.isNotEmpty,
      _MapLayerFilter.posts => visiblePosts.isNotEmpty,
      _MapLayerFilter.all => visibleItems.isNotEmpty || visiblePosts.isNotEmpty,
    };
    final initialMapView = _initialMapView();
    final inViewSpotItems = _spotsInView(visibleItems);
    final spotNodes = _buildSpotNodes(inViewSpotItems);
    final bestSpot = _bestSpotContext(inViewSpotItems);
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog('Map structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
    }
    final markerSummary =
        'spots=${visibleItems.length} posts=${visiblePosts.length} filter=$_filter';
    if (_lastMarkerSummary != markerSummary) {
      _lastMarkerSummary = markerSummary;
      perfLog('Map marker data ready $markerSummary');
    }

    return ShellScaffold(
      title: 'Harita',
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
      body: !_showMapSurface
          ? const _MapLoadingSkeleton()
          : Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialMapView.center,
              initialZoom: initialMapView.zoom,
              onMapReady: () {
                _isMapReady = true;
                if (_pendingAnimateToUser && _currentLocation != null) {
                  _animateToUserIfPossible(
                    reason: 'on_map_ready_pending_user_location',
                    targetZoom: _defaultMapZoom + 0.4,
                  );
                }
              },
              onTap: (_, __) => _handleMapTap(),
              onLongPress: (_, point) => _startAddSpotFlow(point),
              onPositionChanged: (camera, hasGesture) {
                if (_updateCameraState(camera)) {
                  setState(() {});
                }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'fishing_app',
              ),
              MarkerLayer(
                markers: _markers(
                  posts: visiblePosts,
                  spotNodes: spotNodes,
                  bestSpotId: bestSpot?.item.spot.id,
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: _MapFilterBar(
                  value: _filter,
                  onChanged: _onFilterChanged,
                ),
              ),
            ),
          ),
          if (loadError != null &&
              !hasVisibleMarkers &&
              !isCurrentFilterLoading)
            const Center(
              child: SizedBox(
                width: 320,
                child: AppEmptyState(
                  iconWidget: AppIcon(
                    AppGlyph.compass,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                  message: 'Harita verisi yüklenemedi.',
                ),
              ),
            ),
          if (loadError == null &&
              !hasVisibleMarkers &&
              !isCurrentFilterLoading)
            Positioned(
              left: 16,
              right: 16,
              top: bestSpot != null ? 88 : 60,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: _MapNoticeChip(
                    message: _filter == _MapLayerFilter.posts
                        ? 'Gösterilecek paylaşım yok'
                        : 'İşaretçi görünmüyor',
                  ),
                ),
              ),
            ),
          if (_filter != _MapLayerFilter.posts &&
              (_isSpotLayerLoading || _isSpotLayerEnriching))
            Positioned(
              top: bestSpot != null ? 88 : 60,
              right: 16,
              child: _MapLayerLoadingChip(
                label: _isSpotLayerLoading
                    ? 'Meralar yükleniyor'
                    : 'Mera detayları güncelleniyor',
              ),
            ),
          if (_filter != _MapLayerFilter.spots && _isPostLayerLoading)
            Positioned(
              top: (_filter != _MapLayerFilter.posts &&
                      (_isSpotLayerLoading || _isSpotLayerEnriching))
                  ? (bestSpot != null ? 132 : 104)
                  : (bestSpot != null ? 88 : 60),
              right: 16,
              child: const _MapLayerLoadingChip(
                label: 'Paylaşımlar yükleniyor',
              ),
            ),
          if (bestSpot != null)
            Positioned(
              left: 16,
              right: 16,
              top: 54,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _BestSpotChip(
                    item: bestSpot.item,
                    onTap: () => _handleBestSpotTap(bestSpot),
                  ),
                ),
              ),
            ),
          if (_shouldRenderSpotPopup())
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 80,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _SpotPreviewCard(
                    item: _activeSpotPreviewItem!,
                    distanceKm:
                        _distanceToCurrent(_activeSpotPreviewItem!).isFinite
                            ? _distanceToCurrent(_activeSpotPreviewItem!)
                            : null,
                    onClose: _closeSpotPreview,
                    onOpenDetail: () =>
                        _openSpotDetail(_activeSpotPreviewItem!),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 20,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: appSoftShadow(Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: _moveToCurrentLocation,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Konumum',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
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

class _MapLoadingSkeleton extends StatelessWidget {
  const _MapLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          AppSkeletonCard(
            child: SizedBox(height: 44),
          ),
          SizedBox(height: 12),
          Expanded(
            child: AppSkeletonCard(
              child: SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MapLayerFilter { spots, posts, all }

enum _MapFreezeIsolationMode {
  markerTapOnly('A'),
  selectedStateOnly('B'),
  selectedStateWithPopup('C');

  const _MapFreezeIsolationMode(this.label);

  final String label;
}

class _MapView {
  const _MapView({
    required this.center,
    required this.zoom,
  });

  final LatLng center;
  final double zoom;
}

class _SpotNode {
  const _SpotNode.single({
    required this.key,
    required this.item,
  })  : center = null,
        items = null,
        averageScore = null;

  const _SpotNode.cluster({
    required this.key,
    required this.items,
    required this.center,
    required this.averageScore,
  }) : item = null;

  final String key;
  final SpotFeedItem? item;
  final List<SpotFeedItem>? items;
  final LatLng? center;
  final double? averageScore;

  bool get isCluster => items != null;
  int get count => items?.length ?? 1;
}

class _BestSpotContext {
  const _BestSpotContext({
    required this.item,
  });

  final SpotFeedItem item;
}

enum _ScoreBand { great, medium, weak, neutral }

_ScoreBand _scoreBand(int? value) {
  if (value == null) {
    return _ScoreBand.neutral;
  }
  if (value >= 80) {
    return _ScoreBand.great;
  }
  if (value >= 50) {
    return _ScoreBand.medium;
  }
  return _ScoreBand.weak;
}

Color _scoreBandFill(_ScoreBand band) {
  switch (band) {
    case _ScoreBand.great:
      return AppColors.success;
    case _ScoreBand.medium:
      return AppColors.warning;
    case _ScoreBand.weak:
      return AppColors.danger;
    case _ScoreBand.neutral:
      return AppColors.textSecondary;
  }
}

Color _scoreBandSoft(_ScoreBand band) {
  switch (band) {
    case _ScoreBand.great:
      return AppColors.successSoft;
    case _ScoreBand.medium:
      return AppColors.warningSoft;
    case _ScoreBand.weak:
      return AppColors.dangerSoft;
    case _ScoreBand.neutral:
      return AppColors.background;
  }
}

class _MapLayerLoadingChip extends StatelessWidget {
  const _MapLayerLoadingChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: appSoftShadow(Theme.of(context).colorScheme.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BestSpotChip extends StatelessWidget {
  const _BestSpotChip({
    required this.item,
    required this.onTap,
  });

  final SpotFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = item.score?.scoreValue;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.975),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${item.spot.name} • ${score?.toString() ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    height: 1.1,
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

class _MapFilterBar extends StatelessWidget {
  const _MapFilterBar({
    required this.value,
    required this.onChanged,
  });

  final _MapLayerFilter value;
  final ValueChanged<_MapLayerFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: appSoftShadow(theme.colorScheme.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in const [
            (_MapLayerFilter.spots, 'Meralar'),
            (_MapLayerFilter.posts, 'Paylaşımlar'),
            (_MapLayerFilter.all, 'Tümü'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _MapFilterButton(
                label: option.$2,
                selected: value == option.$1,
                onTap: () => onChanged(option.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapFilterButton extends StatelessWidget {
  const _MapFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapNoticeChip extends StatelessWidget {
  const _MapNoticeChip({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
        boxShadow: appSoftShadow(theme.colorScheme.primary),
      ),
      child: Text(
        message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _MapMarkerBadge extends StatelessWidget {
  const _MapMarkerBadge({
    required this.color,
    required this.label,
    required this.size,
    required this.textStyle,
  });

  final Color color;
  final String label;
  final double size;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.92),
            width: 2,
          ),
          boxShadow: appSoftShadow(color),
        ),
        alignment: Alignment.center,
        child: label.isEmpty
            ? null
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: textStyle,
              ),
      ),
    );
  }
}

class _MapSpotMarker extends StatelessWidget {
  const _MapSpotMarker({
    required this.score,
    required this.isSelected,
    required this.isBestSpot,
  });

  final int? score;
  final bool isSelected;
  final bool isBestSpot;

  @override
  Widget build(BuildContext context) {
    final band = _scoreBand(score);
    final fill = isSelected ? AppColors.primary : _scoreBandFill(band);
    final soft = _scoreBandSoft(band);

    return Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (isBestSpot)
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: soft.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(19),
              ),
            ),
          _MapMarkerBadge(
            color: fill,
            label: score?.toString() ?? '',
            size: 28,
            textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
          ),
          if (isBestSpot)
            Positioned(
              top: -2,
              right: -1,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.star_rounded,
                  size: 10,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPostMarker extends StatelessWidget {
  const _MapPostMarker({
    required this.isSelected,
    required this.commentCount,
  });

  final bool isSelected;
  final int commentCount;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected ? AppColors.primary : const Color(0xFF0F766E);
    final soft = isSelected ? AppColors.primarySoft : const Color(0xFFE6FFFB);

    return Center(
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 28,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.96),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.96),
                width: 2,
              ),
              boxShadow: appSoftShadow(fill),
            ),
            child: Icon(
              Icons.forum_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.96),
            ),
          ),
          if (commentCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.96),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  commentCount > 9 ? '9+' : '$commentCount',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpotPreviewCard extends StatelessWidget {
  const _SpotPreviewCard({
    required this.item,
    required this.distanceKm,
    required this.onClose,
    required this.onOpenDetail,
  });

  final SpotFeedItem item;
  final double? distanceKm;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    debugPrint('[map-freeze][fix] popup mounted id=${item.spot.id}');
    final theme = Theme.of(context);
    final meta = <String>[
      if ((item.spot.waterType ?? '').isNotEmpty)
        localizedWaterTypeLabel(item.spot.waterType),
      if (distanceKm != null) '${distanceKm!.toStringAsFixed(1)} km',
      if ((item.spot.region ?? '').isNotEmpty) item.spot.region!,
    ];
    final decisionTitle = _decisionTitle(item);
    final decisionSummary = _decisionSummary(item);
    final chips = _decisionChips(item);

    return Material(
      elevation: 10,
      color: AppColors.card.withValues(alpha: 0.98),
      borderRadius: BorderRadius.circular(24),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        const SizedBox(height: 6),
                        Text(
                          meta.isEmpty ? 'Detay bilgisi yok' : meta.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _scoreBandFill(_scoreBand(item.score?.scoreValue)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${item.score?.scoreValue ?? '-'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Kapat',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  decisionTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                decisionSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in chips.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          chip,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: onOpenDetail,
                      child: const Text('Detayı aç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: onClose,
                    child: const Text('Kapat'),
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

String _decisionTitle(SpotFeedItem item) {
  final score = item.score?.scoreValue;
  if (score == null) {
    return 'Kontrol etmeye değer';
  }
  if (score >= 80) {
    return 'Gitmeye değer';
  }
  if (score >= 50) {
    return 'Takibe değer';
  }
  return 'Şartlar zayıf';
}

String _decisionSummary(SpotFeedItem item) {
  final weather = item.weatherSnapshot;
  return [
    'Basınç ${_pressureLabel(weather?.pressure)}',
    'rüzgar ${_windLabel(weather?.windSpeed)}',
    'yağış ${_rainLabel(weather?.precipitation)}',
  ].join(', ');
}

List<String> _decisionChips(SpotFeedItem item) {
  final weather = item.weatherSnapshot;
  return [
    'Basınç ${_pressureChip(weather?.pressure)}',
    'Rüzgar ${_windChip(weather?.windSpeed)}',
    'Yağış ${_rainChip(weather?.precipitation)}',
  ];
}

String _pressureLabel(double? pressure) {
  if (pressure == null) {
    return 'iyi';
  }
  if (pressure >= 1018) {
    return 'iyi';
  }
  if (pressure >= 1011) {
    return 'orta';
  }
  return 'zayıf';
}

String _windLabel(double? windSpeed) {
  if (windSpeed == null) {
    return 'orta';
  }
  if (windSpeed <= 10) {
    return 'hafif';
  }
  if (windSpeed <= 22) {
    return 'orta';
  }
  return 'sert';
}

String _rainLabel(double? precipitation) {
  if (precipitation == null) {
    return 'düşük';
  }
  if (precipitation <= 0.5) {
    return 'düşük';
  }
  if (precipitation <= 2) {
    return 'orta';
  }
  return 'yüksek';
}

String _pressureChip(double? pressure) {
  if (pressure == null) {
    return 'Normal';
  }
  return '${pressure.toStringAsFixed(0)} hPa';
}

String _windChip(double? windSpeed) {
  if (windSpeed == null) {
    return 'Orta';
  }
  return '${windSpeed.toStringAsFixed(0)} m/s';
}

String _rainChip(double? precipitation) {
  if (precipitation == null) {
    return 'Düşük';
  }
  return '${precipitation.toStringAsFixed(1)} mm';
}

class _PendingSpotMarker {
  const _PendingSpotMarker({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}
