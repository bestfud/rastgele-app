import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import 'auth_service.dart';
import 'perf_logger.dart';

class SpotRepository {
  static const int _defaultFeedPageSize = 12;
  static const int _defaultDeferredImageResolveCount = 4;
  static const int _defaultMapSpotLimit = 32;
  static const Duration _signedUrlTtl = Duration(days: 6);
  static const double _duplicateSpotRadiusMeters = 50;
  static const String _profileAvatarBucket = 'avatars';
  static const String _profileCoverBucket = 'covers';
  static const String _spotBaseSelect =
      'id, owner_profile_id, name, latitude, longitude, visibility, status, region, water_type, created_at';
  static const String _profileBaseSelect =
      'id, auth_user_id, display_name, username, bio, city, avatar_url, cover_url, home_region, website_url, instagram, x_handle, youtube, tiktok';
  static const String _notificationBaseSelect =
      'id, type, recipient_profile_id, actor_profile_id, fishing_spot_id, conversation_id, message_preview, is_read, created_at, actor_profile:profiles!notifications_actor_profile_id_fkey(id, display_name, username)';

  SpotRepository({
    required SupabaseClient client,
    required AuthService authService,
  })  : _client = client,
        _authService = authService;

  final SupabaseClient _client;
  final AuthService _authService;
  final Map<String, _CachedSignedUrl> _signedUrlCache = {};
  final Map<String, Future<String?>> _pendingSignedUrlRequests = {};
  AppProfile? _cachedCurrentProfile;
  String? _cachedCurrentProfileAuthUid;
  Future<AppProfile>? _pendingCurrentProfileResolution;
  HomeScreenData? _cachedHomeFeedData;
  String? _cachedHomeFeedAuthUid;
  final Map<String, ProfileScreenData> _cachedProfileSummaries = {};

  String? get currentAuthUidForDebug => _authService.currentUser?.id;
  String? get currentProfileIdHint => _cachedCurrentProfile?.id;
  Stream<AuthState> get authStateChanges => _authService.authStateChanges;
  HomeScreenData? getCachedHomeFeedData() {
    final currentAuthUid = _authService.currentUser?.id;
    if (_cachedHomeFeedAuthUid != currentAuthUid) {
      return null;
    }
    return _cachedHomeFeedData;
  }

  ProfileScreenData? cachedProfileSummary(String? profileId) {
    final key = _profileCacheKey(profileId);
    return _cachedProfileSummaries[key];
  }

  String _profileCacheKey(String? profileId) {
    final normalized = profileId?.trim() ?? '';
    return normalized.isEmpty ? 'self' : normalized;
  }

  String _normalizeWeatherSpotId(String value) {
    return value.trim().toLowerCase();
  }

  void clearSessionState({
    String? previousAuthUid,
    String? nextAuthUid,
    required String reason,
  }) {
    _signedUrlCache.clear();
    _pendingSignedUrlRequests.clear();
    _cachedCurrentProfile = null;
    _cachedCurrentProfileAuthUid = null;
    _pendingCurrentProfileResolution = null;
    _cachedHomeFeedData = null;
    _cachedHomeFeedAuthUid = null;
    _cachedProfileSummaries.clear();
    perfLog(
      '[auth] repository clearSessionState reason=$reason previousAuthUid=${previousAuthUid ?? 'null'} nextAuthUid=${nextAuthUid ?? 'null'}',
    );
    _homeLog(
      'clearSessionState reason=$reason previousAuthUid=${previousAuthUid ?? 'null'} nextAuthUid=${nextAuthUid ?? 'null'} clearedSignedUrlCaches=true staleCachedDataReused=false',
    );
  }

  Future<AppProfile> _profile() => _resolveCanonicalCurrentProfile(
        scope: 'ensureProfile',
      );

  Future<AppProfile> fetchCurrentProfile() => _resolveCanonicalCurrentProfile(
        scope: 'fetchCurrentProfile',
      );

  Future<HomeScreenData> fetchHomeScreenData() async {
    return _runTimed('fetchHomeScreenData', () async {
      final homeData = await fetchHomeFeedCards();

      return homeData;
    });
  }

  Future<HomeScreenData> fetchHomeFeedCards({
    int limit = 12,
  }) async {
    return _runTimed('fetchHomeFeedCards', () async {
      try {
        final profile = _cachedCurrentProfile ??
            AppProfile(
              id: currentProfileIdHint ?? '',
              displayName: 'Balıkçı',
            );
        final rows = await _client.rpc(
          'home_feed_cards',
          params: {'p_limit': limit},
        );
        final rowList = (rows as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        debugPrint('[PERF_ROWS] home_feed_cards rows=${rowList.length}');
        final items = rowList
            .map(_homeFeedCardItemFromMap)
            .where((item) => item.spot.id.isNotEmpty)
            .toList(growable: false);
        final data = HomeScreenData(
          authUid: _authService.currentUser?.id,
          profile: profile,
          followedPublicSpots: items,
          reusedStaleCache: false,
          repositoryMethod: 'home_feed_cards',
          followedCount: items.length,
          ownPublicSpotCount: 0,
          candidatePostIds: items
              .map((item) => item.sourcePostId ?? '')
              .where((id) => id.isNotEmpty)
              .toList(growable: false),
          finalResultIds: items
              .map((item) => item.spot.id)
              .where((id) => id.isNotEmpty)
              .toList(growable: false),
          earlyEmptyReturn: items.isEmpty,
        );
        _cachedHomeFeedData = data;
        _cachedHomeFeedAuthUid = _authService.currentUser?.id;
        return data;
      } on PostgrestException {
        return fetchFollowedPublicHomeSpots(includeSpotEnrichment: false);
      }
    });
  }

  Future<HomeScreenData> fetchFollowedPublicHomeSpots({
    AppProfile? currentProfile,
    bool includeSpotEnrichment = true,
  }) async {
    return _runTimed('fetchFollowedPublicHomeSpots', () async {
      final baseData = await _fetchFollowedPublicHomeSpotsBaseData();
      final baseItems = baseData.followedPublicSpots;

      if (!includeSpotEnrichment || baseItems.isEmpty) {
        return baseData.copyWith(
          repositoryMethod: includeSpotEnrichment
              ? 'fetchFollowedPublicHomeSpots'
              : 'fetchFollowedPublicHomeSpots.phase1',
        );
      }

      final enrichedItems = await enrichSpotFeedItems(
        baseItems,
        includeScores: true,
        includeWeather: true,
      );
      return baseData.copyWith(
        followedPublicSpots: enrichedItems,
        repositoryMethod: 'fetchFollowedPublicHomeSpots',
      );
    });
  }

  Future<HomeScreenData> fetchHomeScreenPhaseOneData() async {
    return _runTimed('fetchHomeScreenPhaseOneData', () async {
      return fetchHomeFeedCards();
    });
  }

  Future<List<SpotFeedItem>> fetchMapSpotCards({
    int limit = _defaultMapSpotLimit,
  }) async {
    return _runTimed('fetchMapSpotCards', () async {
      try {
        final rows = await _client.rpc(
          'map_spot_cards',
          params: {'p_limit': limit},
        );
        final rowList = (rows as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        debugPrint('[PERF_ROWS] map_spot_cards rows=${rowList.length}');
        return rowList
            .map(_mapSpotCardItemFromMap)
            .where((item) => item.spot.id.isNotEmpty)
            .toList(growable: false);
      } on PostgrestException {
        return fetchGlobalVisibleSpots(
          includeScores: false,
          includeWeather: false,
          limit: limit,
        );
      }
    });
  }

  Future<List<SpotFeedItem>> enrichSpotFeedItems(
    List<SpotFeedItem> items, {
    bool includeScores = true,
    bool includeWeather = true,
  }) async {
    return _runTimed('enrichSpotFeedItems', () async {
      if (items.isEmpty) {
        return items;
      }

      final spots = items.map((item) => item.spot).toList(growable: false);
      final spotIds = spots
          .map((spot) => spot.id)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (spotIds.isEmpty) {
        return items;
      }

      final duplicateSpotIds = <String>{};
      final seenSpotIds = <String>{};
      for (final item in items) {
        final spotId = item.spot.id.trim();
        if (spotId.isEmpty) {
          continue;
        }
        if (!seenSpotIds.add(spotId)) {
          duplicateSpotIds.add(spotId);
        }
      }
      final results = await Future.wait<dynamic>([
        includeScores
            ? _fetchLatestScores(spotIds)
            : Future.value(const <String, FishingScore>{}),
        includeScores || includeWeather
            ? _fetchLatestWeatherSnapshotPairs(spotIds)
            : Future.value(const <String, _WeatherSnapshotPair>{}),
        _fetchFavoriteSpotIds(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final favoriteSpotIds = results[2] as Set<String>;

      return items.map((item) {
        final spot = item.spot;
        final weatherPair = weatherBySpot[_normalizeWeatherSpotId(spot.id)];
        final currentWeather = weatherPair?.current;

        return item.copyWith(
          score: _resolveSpotScore(
            spotId: spot.id,
            storedScore: scoresBySpot[spot.id],
            currentWeather: currentWeather,
            previousWeather: weatherPair?.previous,
          ),
          weatherSnapshot: includeWeather ? currentWeather : null,
          isSaved: favoriteSpotIds.contains(spot.id),
        );
      }).toList(growable: false);
    });
  }

  Future<HomeScreenData> _fetchFollowedPublicHomeSpotsBaseData() async {
    return _runTimed('getFollowedPublicHomeSpotsBaseRpc', () async {
      final currentProfile = await _resolveCanonicalCurrentProfile(
        scope: 'fetchFollowedPublicHomeSpotsBaseData',
      );
      final response =
          await _client.rpc('get_followed_public_home_spots_base_v1');
      final map = _asMap(response);
      final rawSpotRows = _asList(map['spots'])
          .map((row) => _asMap(row))
          .toList(growable: false);
      final candidatePostIds = _asStringList(map['candidate_post_ids']);
      final finalResultIds = _asStringList(map['final_result_ids']);
      final followedProfileIds = await _fetchFollowingProfileIds(
        currentProfile.id,
      );
      _auditHomeFeedRows(
        rows: rawSpotRows,
        currentProfileId: currentProfile.id,
        followedProfileIds: followedProfileIds,
        candidatePostIds: candidatePostIds,
        finalResultIds: finalResultIds,
      );
      final followedPublicSpots = rawSpotRows
          .map((row) => _spotFeedItemFromMap(_asMap(row)))
          .where((item) => item.spot.id.isNotEmpty)
          .toList(growable: false);

      final data = HomeScreenData(
        authUid: map['auth_uid']?.toString(),
        profile: currentProfile,
        followedPublicSpots: followedPublicSpots,
        reusedStaleCache: false,
        repositoryMethod: 'get_followed_public_home_spots_base_v1',
        followedCount: _asInt(map['followed_count']),
        ownPublicSpotCount: _asInt(map['own_public_spot_count']),
        candidatePostIds: candidatePostIds,
        finalResultIds: finalResultIds,
        earlyEmptyReturn: map['early_empty_return'] == true,
      );
      return data;
    });
  }

  Future<Set<String>> _fetchFollowingProfileIds(String profileId) async {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) {
      return const <String>{};
    }

    final rows = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', normalizedProfileId);
    return (rows as List)
        .map(
          (row) =>
              (row as Map<String, dynamic>)['following_id']
                  ?.toString()
                  .trim() ??
              '',
        )
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  void _auditHomeFeedRows({
    required List<Map<String, dynamic>> rows,
    required String currentProfileId,
    required Set<String> followedProfileIds,
    required List<String> candidatePostIds,
    required List<String> finalResultIds,
  }) {}

  Future<List<SpotFeedItem>> fetchGlobalVisibleSpots({
    bool includeScores = true,
    bool includeWeather = true,
    int limit = _defaultMapSpotLimit,
  }) async {
    return _runTimed('fetchGlobalVisibleSpots', () async {
      final authUid = _authService.currentUser?.id;
      final profile = await _profile();
      _homeLog(
        'authUid=${authUid ?? 'null'} resolvedProfileId=${profile.id} method=fetchGlobalVisibleSpots scope=global visibility=exact reusedStaleCache=false',
      );

      final spotsResponse = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .eq('visibility', 'exact')
          .order('created_at', ascending: false)
          .limit(limit);

      final spots = (spotsResponse as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .toList(growable: false);
      debugPrint('[PERF_ROWS] fetchGlobalVisibleSpots rows=${spots.length}');

      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final results = await Future.wait<dynamic>([
        includeScores
            ? _fetchLatestScores(spotIds)
            : Future.value(const <String, FishingScore>{}),
        includeScores || includeWeather
            ? _fetchLatestWeatherSnapshotPairs(spotIds)
            : Future.value(const <String, _WeatherSnapshotPair>{}),
        _fetchFavoriteSpotIds(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final favoriteSpotIds = results[2] as Set<String>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: includeWeather,
        favoriteSpotIds: favoriteSpotIds,
      );
    });
  }

  Future<List<SpotFeedItem>> fetchVisibleSpots({
    bool includeScores = true,
    bool includeWeather = true,
  }) async {
    return _runTimed('fetchVisibleSpots', () async {
      final spotsResponse = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .order('created_at', ascending: false);

      final spots = (spotsResponse as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .toList();

      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final results = await Future.wait<dynamic>([
        includeScores
            ? _fetchLatestScores(spotIds)
            : Future.value(const <String, FishingScore>{}),
        includeScores || includeWeather
            ? _fetchLatestWeatherSnapshotPairs(spotIds)
            : Future.value(const <String, _WeatherSnapshotPair>{}),
        _fetchFavoriteSpotIds(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final favoriteSpotIds = results[2] as Set<String>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: includeWeather,
        favoriteSpotIds: favoriteSpotIds,
      );
    });
  }

  void _homeLog(String message) {
    perfLog('[home] $message');
  }

  Future<List<SpotFeedItem>> fetchFavoriteSpots() async {
    return _runTimed('fetchFavoriteSpots', () async {
      final profile = await _profile();
      final favoriteRows = await _client
          .from('favorites')
          .select('fishing_spot_id')
          .eq('profile_id', profile.id);

      final favoriteIds = (favoriteRows as List)
          .map((item) =>
              (item as Map<String, dynamic>)['fishing_spot_id'] as String)
          .toList();

      if (favoriteIds.isEmpty) {
        return [];
      }

      final favoriteIdSet = favoriteIds.toSet();
      final spotRows = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .inFilter('id', favoriteIds)
          .order('created_at', ascending: false);

      final spots = (spotRows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where((spot) => spot.id.isNotEmpty)
          .toList(growable: false);

      if (spots.isEmpty) {
        return [];
      }

      final accessibleSpotIds =
          spots.map((spot) => spot.id).toList(growable: false);
      final ownerProfilesById = await _fetchProfilesById(
        spots
            .map((spot) => spot.ownerProfileId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList(growable: false),
      );
      final existingItemsBySpot = <String, SpotFeedItem>{
        for (final spot in spots)
          spot.id: SpotFeedItem(
            spot: spot,
            isSaved: true,
            sharedByProfileId: ownerProfilesById[spot.ownerProfileId]?.id,
            sharedByDisplayName:
                ownerProfilesById[spot.ownerProfileId]?.displayName,
            sharedByUsername: ownerProfilesById[spot.ownerProfileId]?.username,
            sharedByAvatarUrl:
                ownerProfilesById[spot.ownerProfileId]?.avatarUrl,
          ),
      };

      final results = await Future.wait<dynamic>([
        _fetchLatestScores(accessibleSpotIds),
        _fetchLatestWeatherSnapshotPairs(accessibleSpotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: true,
        favoriteSpotIds: favoriteIdSet,
        existingItemsBySpot: existingItemsBySpot,
      );
    });
  }

  Future<List<SpotFeedItem>> fetchSharedWithMeSpots() async {
    return _runTimed('fetchSharedWithMeSpots', () async {
      final profile = await _profile();
      final accessRows = await _client
          .from('spot_access')
          .select('fishing_spot_id')
          .eq('profile_id', profile.id);

      final sharedSpotIds = (accessRows as List)
          .map(
            (row) =>
                (row as Map<String, dynamic>)['fishing_spot_id']?.toString(),
          )
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (sharedSpotIds.isEmpty) {
        return const [];
      }

      final favoriteSpotIds = await _fetchFavoriteSpotIds(sharedSpotIds);
      final spotRows = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .inFilter('id', sharedSpotIds)
          .eq('visibility', 'private')
          .neq('owner_profile_id', profile.id)
          .order('created_at', ascending: false);

      final spots = (spotRows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where(
            (spot) =>
                spot.id.isNotEmpty &&
                !favoriteSpotIds.contains(spot.id) &&
                spot.ownerProfileId.trim().isNotEmpty,
          )
          .toList(growable: false);

      if (spots.isEmpty) {
        return const [];
      }

      final ownerProfilesById = await _fetchProfilesById(
        spots
            .map((spot) => spot.ownerProfileId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList(growable: false),
      );
      final visibleSpots = spots
          .where((spot) => ownerProfilesById[spot.ownerProfileId] != null)
          .toList(growable: false);

      if (visibleSpots.isEmpty) {
        return const [];
      }

      final visibleSpotIds =
          visibleSpots.map((spot) => spot.id).toList(growable: false);
      final existingItemsBySpot = <String, SpotFeedItem>{
        for (final spot in visibleSpots)
          spot.id: SpotFeedItem(
            spot: spot,
            sharedByProfileId: ownerProfilesById[spot.ownerProfileId]?.id,
            sharedByDisplayName:
                ownerProfilesById[spot.ownerProfileId]?.displayName,
            sharedByUsername: ownerProfilesById[spot.ownerProfileId]?.username,
            sharedByAvatarUrl:
                ownerProfilesById[spot.ownerProfileId]?.avatarUrl,
          ),
      };

      final results = await Future.wait<dynamic>([
        _fetchLatestScores(visibleSpotIds),
        _fetchLatestWeatherSnapshotPairs(visibleSpotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;

      return _buildSpotFeedItems(
        visibleSpots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: true,
        favoriteSpotIds: const <String>{},
        existingItemsBySpot: existingItemsBySpot,
      );
    });
  }

  Future<List<SpotFeedItem>> searchAccessibleSpots(
    String query, {
    int limit = 20,
  }) async {
    return _runTimed('searchAccessibleSpots', () async {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) {
        return const [];
      }

      final rows = await _client.rpc(
        'search_accessible_spots_v1',
        params: {
          'p_query': normalizedQuery,
          'p_limit': limit,
        },
      );

      final spots = (rows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where((spot) => spot.id.isNotEmpty)
          .toList(growable: false);

      if (spots.isEmpty) {
        return const [];
      }

      final ownerProfilesById = await _fetchProfilesById(
        spots
            .map((spot) => spot.ownerProfileId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList(growable: false),
      );
      final existingItemsBySpot = <String, SpotFeedItem>{
        for (final spot in spots)
          spot.id: SpotFeedItem(
            spot: spot,
            sharedByProfileId: ownerProfilesById[spot.ownerProfileId]?.id,
            sharedByDisplayName:
                ownerProfilesById[spot.ownerProfileId]?.displayName,
            sharedByUsername: ownerProfilesById[spot.ownerProfileId]?.username,
            sharedByAvatarUrl:
                ownerProfilesById[spot.ownerProfileId]?.avatarUrl,
          ),
      };
      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final favoriteSpotIds = await _fetchFavoriteSpotIds(
        spotIds,
      );
      final results = await Future.wait<dynamic>([
        _fetchLatestScores(spotIds),
        _fetchLatestWeatherSnapshotPairs(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: true,
        favoriteSpotIds: favoriteSpotIds,
        existingItemsBySpot: existingItemsBySpot,
      );
    });
  }

  Future<List<SpotFeedItem>> fetchDiscoverableSpots({
    int limit = 10,
  }) async {
    return _runTimed('fetchDiscoverableSpots', () async {
      final profile = await _profile();
      final rows = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .eq('visibility', 'exact')
          .neq('owner_profile_id', profile.id)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(limit);

      final spots = (rows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where((spot) => spot.id.isNotEmpty)
          .toList(growable: false);
      debugPrint('[PERF_ROWS] fetchDiscoverableSpots rows=${spots.length}');

      if (spots.isEmpty) {
        return const [];
      }

      final ownerProfilesById = await _fetchProfilesById(
        spots
            .map((spot) => spot.ownerProfileId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList(growable: false),
      );
      final visibleSpots = spots
          .where((spot) => ownerProfilesById[spot.ownerProfileId] != null)
          .toList(growable: false);
      if (visibleSpots.isEmpty) {
        return const [];
      }

      final existingItemsBySpot = <String, SpotFeedItem>{
        for (final spot in visibleSpots)
          spot.id: SpotFeedItem(
            spot: spot,
            sharedByProfileId: ownerProfilesById[spot.ownerProfileId]?.id,
            sharedByDisplayName:
                ownerProfilesById[spot.ownerProfileId]?.displayName,
            sharedByUsername: ownerProfilesById[spot.ownerProfileId]?.username,
            sharedByAvatarUrl:
                ownerProfilesById[spot.ownerProfileId]?.avatarUrl,
          ),
      };
      final spotIds =
          visibleSpots.map((spot) => spot.id).toList(growable: false);
      final favoriteSpotIds = await _fetchFavoriteSpotIds(spotIds);
      final items = _buildSpotFeedItems(
        visibleSpots,
        storedScoresBySpot: const <String, FishingScore>{},
        weatherBySpot: const <String, _WeatherSnapshotPair>{},
        exposeWeatherSnapshots: false,
        favoriteSpotIds: favoriteSpotIds,
        existingItemsBySpot: existingItemsBySpot,
      );
      return items.take(limit).toList(growable: false);
    });
  }

  Future<List<AppProfile>> searchProfiles(
    String query, {
    int limit = 20,
  }) async {
    return _runTimed('searchProfiles', () async {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) {
        return const [];
      }

      final rows = await _client.rpc(
        'search_profiles_v1',
        params: {
          'p_query': normalizedQuery,
          'p_limit': limit,
        },
      );

      final profiles = (rows as List)
          .map((item) => AppProfile.fromMap(item as Map<String, dynamic>))
          .where((profile) => profile.id.isNotEmpty)
          .toList(growable: false);

      return profiles;
    });
  }

  Future<List<AppProfile>> fetchDiscoverableProfiles({
    int limit = 18,
  }) async {
    return _runTimed('fetchDiscoverableProfiles', () async {
      final currentProfile = await _profile();
      final spots = await fetchDiscoverableSpots(limit: limit);
      if (spots.isEmpty) {
        return const [];
      }

      final profileIds = <String>[];
      final seenProfileIds = <String>{};
      for (final item in spots) {
        final ownerProfileId = item.spot.ownerProfileId.trim();
        if (ownerProfileId.isEmpty ||
            ownerProfileId == currentProfile.id ||
            !seenProfileIds.add(ownerProfileId)) {
          continue;
        }
        profileIds.add(ownerProfileId);
      }

      if (profileIds.isEmpty) {
        return const [];
      }

      final profiles = await _resolveProfilesInOrder(profileIds);
      return profiles.take(limit).toList(growable: false);
    });
  }

  Future<List<SocialPost>> fetchRecentPosts({
    int limit = _defaultFeedPageSize,
    int offset = 0,
    bool includeImages = true,
  }) async {
    return _runTimed('fetchRecentPosts', () async {
      return _fetchFeedPostsFromServer(
        scope: 'recent',
        limit: limit,
        offset: offset,
        includeImages: includeImages,
      );
    });
  }

  Future<List<SocialPost>> fetchPostsForFollowingFeed({
    int limit = _defaultFeedPageSize,
    int offset = 0,
    bool includeImages = true,
  }) async {
    return _runTimed('fetchPostsForFollowingFeed', () async {
      return _fetchFeedPostsFromServer(
        scope: 'following',
        limit: limit,
        offset: offset,
        includeImages: includeImages,
      );
    });
  }

  Future<ProfileScreenData> fetchMyProfileScreenData() async {
    return fetchProfileScreenData();
  }

  Future<ProfileScreenPhaseOneData> fetchProfileScreenPhaseOneData({
    String? profileId,
    bool includePostImages = true,
  }) async {
    return _runTimed('fetchProfileScreenPhaseOneData', () async {
      final summaryData = await fetchProfileSummaryCard(profileId: profileId);
      return ProfileScreenPhaseOneData(
        data: summaryData,
        postIds: const [],
      );
    });
  }

  Future<ProfileScreenData> fetchProfileSummaryCard({
    String? profileId,
  }) async {
    return _runTimed('fetchProfileSummaryCard', () async {
      final normalizedProfileId = profileId?.trim();
      final cacheKey = _profileCacheKey(normalizedProfileId);
      try {
        final rows = await _client.rpc(
          'profile_summary',
          params: {
            'p_profile_id': normalizedProfileId?.isEmpty ?? true
                ? null
                : normalizedProfileId,
          },
        );
        final rowList = rows as List;
        if (rowList.isEmpty) {
          throw Exception('Profil bulunamadı.');
        }
        final row = Map<String, dynamic>.from(rowList.first as Map);
        debugPrint('[PERF_ROWS] profile_summary rows=${rowList.length}');
        final profile = AppProfile.fromMap({
          'id': row['profile_id'],
          'display_name': row['display_name'],
          'username': row['username'],
          'avatar_url': row['avatar_url'],
          'cover_url': row['cover_url'],
          'bio': row['bio'],
          'city': row['city'],
          'home_region': row['home_region'],
          'website_url': row['website_url'],
          'instagram': row['instagram'],
          'x_handle': row['x_handle'],
          'youtube': row['youtube'],
          'tiktok': row['tiktok'],
        });
        final data = ProfileScreenData(
          profile: profile,
          stats: ProfileStats(
            totalPosts: _asInt(row['post_count']),
            totalFishingSpots: _asInt(row['spot_count']),
            followerCount: _asInt(row['follower_count']),
            followingCount: _asInt(row['following_count']),
          ),
          posts: const [],
          publicSpots: const [],
          savedSpots: const [],
          sharedWithMeSpots: const [],
          isOwnProfile: row['is_own'] == true,
          isFollowing: row['is_following'] == true,
        );
        _cachedProfileSummaries[cacheKey] = data;
        return data;
      } on PostgrestException {
        final summary = await _fetchProfileSummary(profileId);
        final data = ProfileScreenData(
          profile: summary.profile,
          stats: ProfileStats(
            totalPosts: summary.totalPosts,
            totalFishingSpots: summary.totalFishingSpots,
            followerCount: summary.followerCount,
            followingCount: summary.followingCount,
          ),
          posts: const [],
          publicSpots: const [],
          savedSpots: const [],
          sharedWithMeSpots: const [],
          isOwnProfile: summary.isOwnProfile,
          isFollowing: summary.isFollowing,
        );
        _cachedProfileSummaries[cacheKey] = data;
        return data;
      }
    });
  }

  Future<List<SocialPost>> fetchProfilePostCards(
    String profileId, {
    int limit = 10,
    int offset = 0,
  }) async {
    return _runTimed('fetchProfilePostCards', () async {
      final normalizedProfileId = profileId.trim();
      if (normalizedProfileId.isEmpty) {
        return const <SocialPost>[];
      }

      try {
        final rows = await _client.rpc(
          'profile_post_cards',
          params: {
            'p_profile_id': normalizedProfileId,
            'p_limit': limit,
            'p_offset': offset,
          },
        );
        final rowList = (rows as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        debugPrint('[PERF_ROWS] profile_post_cards rows=${rowList.length}');
        return rowList
            .map(_profilePostCardFromMap)
            .where((post) => post.id.isNotEmpty)
            .toList(growable: false);
      } on PostgrestException {
        final summary = await fetchProfileSummaryCard(profileId: normalizedProfileId);
        return fetchPostsByUser(
          summary.profile.postUserId,
          limit: limit,
          offset: offset,
          includeImages: false,
        );
      }
    });
  }

  Future<List<SpotFeedItem>> fetchPublicSharedSpotsForProfileId(
    String? profileId, {
    bool includeAllForOwner = false,
  }) async {
    final summary = await _fetchProfileSummary(profileId);

    return _fetchPublicSharedSpotsForProfile(
      summary.profile,
      includeAllVisibilities: includeAllForOwner && summary.isOwnProfile,
    );
  }

  Future<List<SpotFeedItem>> fetchProfileSpotsForProfileId(
    String? profileId,
  ) async {
    final summary = await _fetchProfileSummary(profileId);
    return fetchProfileSpotsForProfile(
      summary.profile,
      isOwnProfile: summary.isOwnProfile,
    );
  }

  Future<List<SpotFeedItem>> fetchPublicSharedSpotsForProfile(
    AppProfile profile, {
    required bool includeAllVisibilities,
    List<String>? knownPostIds,
  }) async {
    return _fetchPublicSharedSpotsForProfile(
      profile,
      includeAllVisibilities: includeAllVisibilities,
      knownPostIds: knownPostIds,
    );
  }

  Future<List<SpotFeedItem>> fetchProfileSpotsForProfile(
    AppProfile profile, {
    required bool isOwnProfile,
    List<String>? knownPostIds,
  }) async {
    if (isOwnProfile) {
      return _fetchOwnedSpotsForProfile(profile);
    }

    return _fetchPublicSharedSpotsForProfile(
      profile,
      includeAllVisibilities: false,
      knownPostIds: knownPostIds,
    );
  }

  Future<ProfileScreenData> fetchProfileScreenData({
    String? profileId,
    bool includePostImages = true,
  }) async {
    return _runTimed('fetchProfileScreenData', () async {
      final phaseOne = await fetchProfileScreenPhaseOneData(
        profileId: profileId,
        includePostImages: includePostImages,
      );
      final publicSpots = await fetchProfileSpotsForProfile(
        phaseOne.data.profile,
        isOwnProfile: phaseOne.data.isOwnProfile,
        knownPostIds: phaseOne.postIds,
      );
      final savedSpots = phaseOne.data.isOwnProfile
          ? await fetchFavoriteSpots()
          : const <SpotFeedItem>[];
      final sharedWithMeSpots = phaseOne.data.isOwnProfile
          ? await fetchSharedWithMeSpots()
          : const <SpotFeedItem>[];

      return phaseOne.data.copyWith(
        publicSpots: publicSpots,
        savedSpots: savedSpots,
        sharedWithMeSpots: sharedWithMeSpots,
        stats: phaseOne.data.stats.copyWith(
          totalFishingSpots: publicSpots.length,
        ),
      );
    });
  }

  Future<SpotDetailData> fetchSpotDetailPhaseOne(String spotId) async {
    return _runTimed('fetchSpotDetailPhaseOne', () async {
      final normalizedSpotId = spotId.trim();
      final spotRow = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .eq('id', normalizedSpotId)
          .single();
      return SpotDetailData(
        spot: FishingSpot.fromMap(spotRow),
      );
    }).catchError((error) {
      debugPrint(
        '[SPOT_REPO] phaseOne result spotId=$spotId found=false error=$error',
      );
      throw error;
    });
  }

  Future<_ProfileSummaryData> _fetchProfileSummary(String? profileId) async {
    return _runTimed('getProfileSummaryRpc', () async {
      final rows = await _client.rpc(
        'get_profile_summary_v1',
        params: {
          'p_profile_lookup': profileId,
        },
      );
      final rowList = rows as List;
      if (rowList.isEmpty) {
        throw Exception('Profil bulunamadı.');
      }

      final row = Map<String, dynamic>.from(rowList.first as Map);
      return _ProfileSummaryData(
        profile: AppProfile.fromMap(row),
        totalPosts: _asInt(row['total_posts']),
        totalFishingSpots: _asInt(row['total_fishing_spots']),
        followerCount: _asInt(row['follower_count']),
        followingCount: _asInt(row['following_count']),
        isOwnProfile: row['is_own'] == true,
        isFollowing: row['is_following'] == true,
      );
    });
  }

  Future<List<SocialPost>> fetchPostsByUser(
    String userId, {
    int limit = 10,
    int offset = 0,
    bool includeImages = true,
  }) async {
    return _runTimed('fetchPostsByUser', () async {
      return _fetchFeedPostsFromServer(
        scope: 'profile',
        targetUserId: userId,
        limit: limit,
        offset: offset,
        includeImages: includeImages,
      );
    });
  }

  Future<List<SocialPost>> fetchPostsForSpot(
    String spotId, {
    int limit = 12,
    bool includeImages = true,
  }) async {
    return _runTimed('fetchPostsForSpot', () async {
      final normalizedSpotId = spotId.trim();
      if (normalizedSpotId.isEmpty) {
        return const <SocialPost>[];
      }

      final rows = await _client
          .from('posts')
          .select(
            'id, user_id, caption, visibility, created_at, '
            'post_spots!inner(fishing_spot_id, visibility_override, region, latitude, longitude), '
            'post_photos(storage_path)',
          )
          .eq('post_spots.fishing_spot_id', normalizedSpotId)
          .order('created_at', ascending: false)
          .limit(limit);

      final basePosts = (rows as List)
          .map((item) => SocialPost.fromMap(item as Map<String, dynamic>))
          .where((post) => post.id.isNotEmpty)
          .toList(growable: false);
      debugPrint('[PERF_ROWS] fetchPostsForSpot rows=${basePosts.length}');
      if (basePosts.isEmpty) {
        return basePosts;
      }

      final profilesById = await _fetchProfilesById(
        basePosts
            .map((post) => post.userId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList(growable: false),
      );
      final likeMap = await fetchLikesForPosts(
        basePosts.map((post) => post.id).toList(growable: false),
      );
      final commentMap = await fetchCommentCountsForPosts(
        basePosts.map((post) => post.id).toList(growable: false),
      );

      final enrichedPosts = basePosts.map((post) {
        final profile = profilesById[post.userId];
        final likeData = likeMap[post.id];
        return post.copyWith(
          authorProfileId: profile?.id ?? post.authorProfileId,
          displayName: profile?.displayName ?? post.displayName,
          username: profile?.username ?? post.username,
          avatarUrl: profile?.avatarUrl ?? post.avatarUrl,
          likeCount: likeData?.likeCount ?? post.likeCount,
          isLiked: likeData?.isLiked ?? post.isLiked,
          commentCount: commentMap[post.id] ?? post.commentCount,
        );
      }).toList(growable: false);

      if (!includeImages) {
        return enrichedPosts;
      }

      return hydratePostImages(
        enrichedPosts,
        maxResolveCount: _defaultDeferredImageResolveCount,
      );
    });
  }

  Future<SpotTrustSummary> fetchSpotTrustSummary(String spotId) async {
    return _runTimed('fetchSpotTrustSummary', () async {
      final posts = await fetchPostsForSpot(
        spotId,
        limit: 80,
        includeImages: false,
      );
      if (posts.isEmpty) {
        return const SpotTrustSummary(
          contributionCount: 0,
          recentContributionCount: 0,
          successCount: 0,
          emptyCount: 0,
          totalLikeCount: 0,
          trustScore: 0,
        );
      }

      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
      var recentContributionCount = 0;
      var successCount = 0;
      var emptyCount = 0;
      var totalLikeCount = 0;
      for (final post in posts) {
        if ((post.createdAt?.toUtc().isAfter(cutoff) ?? false)) {
          recentContributionCount += 1;
        }
        final normalizedCaption = (post.caption ?? '').toLowerCase();
        if (const [
          'iş yaptı',
          'vurdu',
          'aldım',
          'çıktı',
          'güzel geçti',
          'bereketli'
        ].any(normalizedCaption.contains)) {
          successCount += 1;
        } else if (const [
          'boş geçti',
          'boş döndük',
          'yoktu',
          'çıkmadı',
          'alamadık'
        ].any(normalizedCaption.contains)) {
          emptyCount += 1;
        }
        totalLikeCount += post.likeCount;
      }

      final rawTrust = (posts.length * 8) +
          (recentContributionCount * 6) +
          (successCount * 5) -
          (emptyCount * 2) +
          totalLikeCount;

      return SpotTrustSummary(
        contributionCount: posts.length,
        recentContributionCount: recentContributionCount,
        successCount: successCount,
        emptyCount: emptyCount,
        totalLikeCount: totalLikeCount,
        trustScore: rawTrust.clamp(0, 100),
      );
    });
  }

  Future<List<SocialPost>> _fetchFeedPostsFromServer({
    required String scope,
    String? targetUserId,
    required int limit,
    required int offset,
    required bool includeImages,
  }) async {
    return _runTimed('_fetchFeedPostsFromServer[$scope]', () async {
      final rpcStopwatch = Stopwatch()..start();
      final response = await _client.rpc(
        'get_feed_posts_v1',
        params: {
          'p_scope': scope,
          'p_target_user_id': targetUserId,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      rpcStopwatch.stop();

      final rowList = (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      debugPrint('[PERF_ROWS] $scope rows=${rowList.length}');
      perfLog(
        '_fetchFeedPostsFromServer[$scope] rpc returned rows=${rowList.length} in ${rpcStopwatch.elapsedMilliseconds}ms',
      );

      final posts = rowList
          .map(SocialPost.fromMap)
          .where((post) => post.id.isNotEmpty)
          .toList(growable: false);
      if (!includeImages) {
        return posts;
      }

      final hydrationStopwatch = Stopwatch()..start();
      final hydratedPosts = await hydratePostImages(
        posts,
        maxResolveCount: _defaultDeferredImageResolveCount,
      );
      hydrationStopwatch.stop();
      perfLog(
        '_fetchFeedPostsFromServer[$scope] image hydration posts=${hydratedPosts.length} took ${hydrationStopwatch.elapsedMilliseconds}ms',
      );
      return hydratedPosts;
    });
  }

  Future<void> toggleLike(String postId) async {
    final profile = await _profile();
    final existing = await _client
        .from('post_likes')
        .select('post_id')
        .eq('post_id', postId)
        .eq('profile_id', profile.id)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('profile_id', profile.id);
      return;
    }

    await _client.from('post_likes').insert({
      'post_id': postId,
      'profile_id': profile.id,
    });
  }

  Future<AppProfile> fetchProfileById(String profileId) async {
    return _runTimed('fetchProfileById', () async {
      final row = await _findProfileByAuthUserId(profileId) ??
          await _findLegacyProfileById(profileId);

      if (row == null) {
        throw Exception('Profil bulunamadı.');
      }

      return AppProfile.fromMap(row);
    });
  }

  Future<void> followUser(String profileId) async {
    final profile = await _profile();
    if (profile.id == profileId) {
      return;
    }

    await _client.from('follows').upsert({
      'follower_id': profile.id,
      'following_id': profileId,
    }, onConflict: 'follower_id,following_id');
  }

  Future<void> unfollowUser(String profileId) async {
    final profile = await _profile();
    if (profile.id == profileId) {
      return;
    }

    await _client
        .from('follows')
        .delete()
        .eq('follower_id', profile.id)
        .eq('following_id', profileId);
  }

  Future<bool> isFollowing(String profileId) async {
    final profile = await _profile();
    if (profile.id == profileId) {
      return false;
    }

    final row = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', profile.id)
        .eq('following_id', profileId)
        .maybeSingle();

    return row != null;
  }

  Future<String> createOrGetConversation(
    String userA,
    String userB, {
    String? currentProfileId,
  }) async {
    return _runTimed('createOrGetConversation', () async {
      final currentUserProfileId = await _resolveCurrentProfileId(
        currentProfileId: currentProfileId,
        scope: 'createOrGetConversation',
      );
      final normalizedUserA = userA.trim();
      final normalizedUserB = userB.trim();
      if (normalizedUserA.isEmpty || normalizedUserB.isEmpty) {
        throw Exception('Geçerli kullanıcı bulunamadı.');
      }
      if (normalizedUserA == normalizedUserB) {
        throw Exception('Kendine mesaj gönderemezsin.');
      }
      if (currentUserProfileId != normalizedUserA &&
          currentUserProfileId != normalizedUserB) {
        throw Exception('Bu konuşmayı başlatma iznin yok.');
      }

      final targetProfileId = normalizedUserA == currentUserProfileId
          ? normalizedUserB
          : normalizedUserA;
      final response = await _client.rpc(
        'create_or_get_dm_conversation',
        params: {
          'target_profile_id': targetProfileId,
        },
      );
      final conversationId = response?.toString().trim() ?? '';
      if (conversationId.isEmpty) {
        throw Exception('Konuşma oluşturulamadı.');
      }

      return conversationId;
    });
  }

  Future<DirectMessage> sendMessage(String conversationId, String text) async {
    return _runTimed('sendMessage', () async {
      final totalStopwatch = Stopwatch()..start();
      final profile = await _profile();
      final normalizedConversationId = conversationId.trim();
      final normalizedText = _nullableText(text);
      if (normalizedConversationId.isEmpty) {
        throw Exception('Geçerli konuşma bulunamadı.');
      }
      if (normalizedText == null) {
        throw Exception('Boş mesaj gönderilemez.');
      }

      await _ensureConversationParticipant(
        conversationId: normalizedConversationId,
        profileId: profile.id,
      );

      final participantRows = await _client
          .from('conversation_participants')
          .select('profile_id')
          .eq('conversation_id', normalizedConversationId);
      final participantIds = (participantRows as List)
          .map(
            (row) =>
                (row as Map<String, dynamic>)['profile_id']
                    ?.toString()
                    .trim() ??
                '',
          )
          .where((id) => id.isNotEmpty)
          .toSet();
      final otherProfileId =
          participantIds.firstWhere((id) => id != profile.id, orElse: () => '');
      if (otherProfileId.isNotEmpty) {
        await _assertDirectMessagePermission(profile.id, otherProfileId);
      }

      final insertStopwatch = Stopwatch()..start();
      final insertedRows = await _client
          .from('messages')
          .insert({
            'conversation_id': normalizedConversationId,
            'sender_id': profile.id,
            'text': normalizedText,
          })
          .select('id, conversation_id, sender_id, text, created_at, read_at')
          .limit(1);
      insertStopwatch.stop();
      perfLog(
          '[perf] sendMessage insert ${insertStopwatch.elapsedMilliseconds}ms');

      final insertedRowList = insertedRows as List;
      if (insertedRowList.isEmpty) {
        throw Exception('Mesaj kaydedilemedi.');
      }
      final insertedMessage = DirectMessage.fromMap(
        insertedRowList.first as Map<String, dynamic>,
      );

      if (otherProfileId.isNotEmpty) {
        unawaited(
          _createDirectMessageNotification(
            recipientProfileId: otherProfileId,
            conversationId: normalizedConversationId,
            messagePreview: normalizedText,
          ).catchError((error) {
            debugPrint(
              '[SPOT_REPO] dm notification create failed conversation=$normalizedConversationId recipient=$otherProfileId error=$error',
            );
          }),
        );
      }

      totalStopwatch.stop();
      perfLog(
          '[perf] sendMessage total ${totalStopwatch.elapsedMilliseconds}ms');
      return insertedMessage;
    });
  }

  Future<List<DirectMessage>> fetchMessages(
    String conversationId, {
    String? currentProfileId,
  }) async {
    return _runTimed('fetchMessages', () async {
      final currentUserProfileId = await _resolveCurrentProfileId(
        currentProfileId: currentProfileId,
        scope: 'fetchMessages',
      );
      final normalizedConversationId = conversationId.trim();
      if (normalizedConversationId.isEmpty) {
        return const [];
      }

      await _ensureConversationParticipant(
        conversationId: normalizedConversationId,
        profileId: currentUserProfileId,
      );

      final rows = await _client
          .from('messages')
          .select('id, conversation_id, sender_id, text, created_at, read_at')
          .eq('conversation_id', normalizedConversationId)
          .order('created_at', ascending: true);

      return (rows as List)
          .map((row) => DirectMessage.fromMap(row as Map<String, dynamic>))
          .where((item) => item.id.trim().isNotEmpty)
          .toList(growable: false);
    });
  }

  Future<int> getUnreadMessageCount({
    String? currentProfileId,
  }) async {
    return _runTimed('getUnreadMessageCount', () async {
      final myProfileId = (await _resolveCurrentProfileId(
        currentProfileId: currentProfileId,
        scope: 'getUnreadMessageCount',
      ))
          .trim();
      if (myProfileId.isEmpty) {
        _dmAuditLog('unread total count=0 reason=missing_profile');
        return 0;
      }

      final myParticipantRows = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('profile_id', myProfileId);
      final conversationIds = (myParticipantRows as List)
          .map(
            (row) =>
                (row as Map<String, dynamic>)['conversation_id']
                    ?.toString()
                    .trim() ??
                '',
          )
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (conversationIds.isEmpty) {
        _dmAuditLog('unread total count=0 conversations=0');
        return 0;
      }

      final unreadRows = await _client
          .from('messages')
          .select('conversation_id')
          .inFilter('conversation_id', conversationIds)
          .neq('sender_id', myProfileId)
          .isFilter('read_at', null);
      final count = (unreadRows as List).length;
      _dmAuditLog(
        'unread total count=$count conversations=${conversationIds.length}',
      );
      return count;
    });
  }

  Future<List<UserConversation>> fetchUserConversations() async {
    return fetchUserConversationsWithMeta();
  }

  Future<List<UserConversation>> fetchUserConversationsWithMeta({
    String? currentProfileId,
  }) async {
    return _runTimed('fetchUserConversationsWithMeta', () async {
      final myProfileId = (await _resolveCurrentProfileId(
        currentProfileId: currentProfileId,
        scope: 'fetchUserConversationsWithMeta',
      ))
          .trim();
      if (myProfileId.isEmpty) {
        return const [];
      }

      final myParticipantRows = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('profile_id', myProfileId);
      final conversationIds = (myParticipantRows as List)
          .map(
            (row) =>
                (row as Map<String, dynamic>)['conversation_id']
                    ?.toString()
                    .trim() ??
                '',
          )
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (conversationIds.isEmpty) {
        return const [];
      }

      final resultSets = await Future.wait<dynamic>([
        _client
            .from('conversations')
            .select('id, created_at')
            .inFilter('id', conversationIds),
        _client
            .from('conversation_participants')
            .select('conversation_id, profile_id')
            .inFilter('conversation_id', conversationIds),
        _client
            .from('messages')
            .select(
              'id, conversation_id, sender_id, text, created_at, read_at',
            )
            .inFilter('conversation_id', conversationIds)
            .order('created_at', ascending: false),
        _client
            .from('messages')
            .select('conversation_id')
            .inFilter('conversation_id', conversationIds)
            .neq('sender_id', myProfileId)
            .isFilter('read_at', null),
      ]);

      final conversationRows = resultSets[0] as List;
      final createdAtByConversationId = <String, DateTime?>{};
      for (final row in conversationRows) {
        final map = row as Map<String, dynamic>;
        final conversationId = map['id']?.toString().trim() ?? '';
        if (conversationId.isEmpty) {
          continue;
        }
        createdAtByConversationId[conversationId] =
            DateTime.tryParse(map['created_at']?.toString() ?? '');
      }

      final participantRows = resultSets[1] as List;
      final otherProfileIdByConversationId = <String, String>{};
      final otherProfileIds = <String>{};
      for (final row in participantRows) {
        final map = row as Map<String, dynamic>;
        final conversationId = map['conversation_id']?.toString().trim() ?? '';
        final participantId = map['profile_id']?.toString().trim() ?? '';
        if (conversationId.isEmpty ||
            participantId.isEmpty ||
            participantId == myProfileId) {
          continue;
        }
        otherProfileIdByConversationId[conversationId] = participantId;
        otherProfileIds.add(participantId);
      }
      if (otherProfileIds.isEmpty) {
        return const [];
      }

      final profilesById = await _fetchProfilesById(otherProfileIds.toList());
      final messageRows = resultSets[2] as List;
      final lastMessageByConversationId = <String, DirectMessage>{};
      for (final row in messageRows) {
        final message = DirectMessage.fromMap(row as Map<String, dynamic>);
        if (message.conversationId.isEmpty || message.id.isEmpty) {
          continue;
        }
        lastMessageByConversationId.putIfAbsent(
          message.conversationId,
          () => message,
        );
      }

      final unreadCountByConversationId = <String, int>{};
      final unreadRows = resultSets[3] as List;
      for (final row in unreadRows) {
        final conversationId = (row as Map<String, dynamic>)['conversation_id']
                ?.toString()
                .trim() ??
            '';
        if (conversationId.isEmpty) {
          continue;
        }
        unreadCountByConversationId[conversationId] =
            (unreadCountByConversationId[conversationId] ?? 0) + 1;
      }

      final conversations = <UserConversation>[];
      for (final conversationId in conversationIds) {
        final otherProfileId = otherProfileIdByConversationId[conversationId];
        if (otherProfileId == null) {
          continue;
        }
        final otherProfile = profilesById[otherProfileId];
        if (otherProfile == null) {
          continue;
        }
        final lastMessage = lastMessageByConversationId[conversationId];
        conversations.add(
          UserConversation(
            id: conversationId,
            otherProfile: otherProfile,
            lastMessageText: lastMessage?.text,
            lastMessageAt: lastMessage?.createdAt ??
                createdAtByConversationId[conversationId],
            unreadCount: unreadCountByConversationId[conversationId] ?? 0,
          ),
        );
      }

      conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      for (final conversation in conversations) {
        _dmAuditLog(
          'conversation unread count id=${conversation.id} count=${conversation.unreadCount}',
        );
      }

      return conversations;
    });
  }

  Future<void> markConversationAsRead(
    String conversationId, {
    String? currentProfileId,
  }) async {
    await _runTimed('markConversationAsRead', () async {
      final currentUserProfileId = await _resolveCurrentProfileId(
        currentProfileId: currentProfileId,
        scope: 'markConversationAsRead',
      );
      final normalizedConversationId = conversationId.trim();
      if (normalizedConversationId.isEmpty) {
        return;
      }

      await _ensureConversationParticipant(
        conversationId: normalizedConversationId,
        profileId: currentUserProfileId,
      );

      await _client
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', normalizedConversationId)
          .neq('sender_id', currentUserProfileId)
          .isFilter('read_at', null);
    });
  }

  Future<int> fetchFollowerCount(String profileId) async {
    return _runTimed('fetchFollowerCount', () async {
      final rows = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', profileId);

      return (rows as List).length;
    });
  }

  Future<int> fetchFollowingCount(String profileId) async {
    return _runTimed('fetchFollowingCount', () async {
      final rows = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', profileId);

      return (rows as List).length;
    });
  }

  Future<List<AppProfile>> fetchFollowersForProfile(String profileId) async {
    return _runTimed('fetchFollowersForProfile', () async {
      final rows = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', profileId);

      final followerIds = (rows as List)
          .map((row) =>
              (row as Map<String, dynamic>)['follower_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      return _resolveProfilesInOrder(followerIds);
    });
  }

  Future<List<AppProfile>> fetchFollowingForProfile(String profileId) async {
    return _runTimed('fetchFollowingForProfile', () async {
      final rows = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', profileId);

      final followingIds = (rows as List)
          .map((row) =>
              (row as Map<String, dynamic>)['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      return _resolveProfilesInOrder(followingIds);
    });
  }

  Future<Map<String, PostLikeData>> fetchLikesForPosts(
      List<String> postIds) async {
    if (postIds.isEmpty) {
      return {};
    }

    return _runTimed('fetchLikesForPosts', () async {
      final profile = await _profile();
      final rows = await _client
          .from('post_likes')
          .select('post_id, profile_id')
          .inFilter('post_id', postIds);
      final rowList = rows as List;

      final likeCounts = <String, int>{};
      final likedPostIds = <String>{};

      for (final row in rowList) {
        final map = row as Map<String, dynamic>;
        final postId = map['post_id']?.toString();
        final profileId = map['profile_id']?.toString();
        if (postId == null || postId.isEmpty) {
          continue;
        }

        likeCounts[postId] = (likeCounts[postId] ?? 0) + 1;
        if (profileId == profile.id) {
          likedPostIds.add(postId);
        }
      }

      final results = <String, PostLikeData>{};
      for (final postId in postIds) {
        results[postId] = PostLikeData(
          likeCount: likeCounts[postId] ?? 0,
          isLiked: likedPostIds.contains(postId),
        );
      }

      perfLog(
          'fetchLikesForPosts aggregated posts=${postIds.length} rows=${rowList.length}');
      return results;
    });
  }

  Future<Map<String, int>> fetchCommentCountsForPosts(
      List<String> postIds) async {
    if (postIds.isEmpty) {
      return {};
    }

    return _runTimed('fetchCommentCountsForPosts', () async {
      final rows = await _client
          .from('post_comments')
          .select('post_id')
          .inFilter('post_id', postIds);
      final rowList = rows as List;

      final counts = <String, int>{};
      for (final row in rowList) {
        final postId = (row as Map<String, dynamic>)['post_id']?.toString();
        if (postId == null || postId.isEmpty) {
          continue;
        }

        counts[postId] = (counts[postId] ?? 0) + 1;
      }

      perfLog(
        'fetchCommentCountsForPosts aggregated posts=${postIds.length} rows=${rowList.length}',
      );
      return counts;
    });
  }

  Future<List<PostComment>> fetchCommentsForPost(String postId) async {
    return _runTimed('fetchCommentsForPost', () async {
      final rows = await _client
          .from('post_comments')
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      final comments = (rows as List)
          .map((item) => PostComment.fromMap(item as Map<String, dynamic>))
          .toList();

      final profilesById = await _fetchProfilesById(
        comments
            .map((comment) => comment.profileId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(),
      );

      return comments.map(
        (comment) {
          final profile = profilesById[comment.profileId];
          if (profile == null) {
            return comment;
          }

          return PostComment(
            id: comment.id,
            postId: comment.postId,
            profileId: comment.profileId,
            body: comment.body,
            createdAt: comment.createdAt,
            displayName: profile.displayName,
            username: profile.username,
            avatarUrl: profile.avatarUrl,
          );
        },
      ).toList();
    });
  }

  Future<PostComment> createComment({
    required String postId,
    required String body,
  }) async {
    return _runTimed('createComment', () async {
      final profile = await _profile();

      final row = await _client
          .from('post_comments')
          .insert({
            'post_id': postId,
            'profile_id': profile.id,
            'body': _nullableText(body),
          })
          .select()
          .single();

      final comment = PostComment.fromMap(row);
      return PostComment(
        id: comment.id,
        postId: comment.postId,
        profileId: comment.profileId,
        body: comment.body,
        createdAt: comment.createdAt,
        displayName: profile.displayName,
        username: profile.username,
        avatarUrl: profile.avatarUrl,
      );
    });
  }

  Future<AppProfile> updateProfile({
    required String displayName,
    required String username,
    required String bio,
    required String city,
    String? websiteUrl,
    String? instagram,
    String? xHandle,
    String? youtube,
    String? tiktok,
    String? avatarUrl,
    String? coverUrl,
  }) async {
    final profile = await _profile();
    final payload = <String, dynamic>{};

    void setIfChanged(String key, String? nextValue, String? currentValue) {
      final normalizedNext = _nullableText(nextValue);
      final normalizedCurrent = _nullableText(currentValue);
      if (normalizedNext == normalizedCurrent) {
        return;
      }
      payload[key] = normalizedNext;
    }

    final normalizedDisplayName = _nullableText(displayName);
    if (normalizedDisplayName != null &&
        normalizedDisplayName != profile.displayName.trim()) {
      payload['display_name'] = normalizedDisplayName;
    }

    setIfChanged('username', username, profile.username);
    setIfChanged('bio', bio, profile.bio);
    setIfChanged('city', city, profile.city);
    setIfChanged('website_url', websiteUrl, profile.websiteUrl);
    setIfChanged('instagram', instagram, profile.instagram);
    setIfChanged('x_handle', xHandle, profile.xHandle);
    setIfChanged('youtube', youtube, profile.youtube);
    setIfChanged('tiktok', tiktok, profile.tiktok);
    setIfChanged('avatar_url', avatarUrl, profile.avatarUrl);
    setIfChanged('cover_url', coverUrl, profile.coverUrl);

    if (payload.isEmpty) {
      perfLog('[profile-save] payload empty profileId=${profile.id}');
      return profile;
    }

    perfLog('[profile-save] profileId=${profile.id} payload=$payload');

    try {
      final updated = await _client
          .from('profiles')
          .update(payload)
          .eq('id', profile.id)
          .select()
          .single();
      final updatedProfile = AppProfile.fromMap(updated);
      _cachedCurrentProfile = updatedProfile;
      _cachedCurrentProfileAuthUid = _authService.currentUser?.id;
      perfLog('[profile-save] success profileId=${profile.id}');
      return updatedProfile;
    } on PostgrestException catch (error) {
      perfLog(
        '[profile-save] postgrest error profileId=${profile.id} code=${error.code ?? 'null'} message=${error.message} details=${error.details ?? 'null'} hint=${error.hint ?? 'null'} payload=$payload',
      );
      rethrow;
    } catch (error) {
      perfLog(
        '[profile-save] unexpected error profileId=${profile.id} error=$error payload=$payload',
      );
      rethrow;
    }
  }

  Future<String> uploadProfileImage({
    required Uint8List bytes,
    required String kind,
    String? extension,
  }) async {
    final profile = await _profile();
    final normalizedKind =
        kind.trim().toLowerCase() == 'cover' ? 'cover' : 'avatar';
    final bucket =
        normalizedKind == 'cover' ? _profileCoverBucket : _profileAvatarBucket;
    final normalizedExtension = _normalizedPhotoExtension(extension);
    final storagePath =
        '${profile.id}_${DateTime.now().millisecondsSinceEpoch}.$normalizedExtension';

    perfLog(
      '[profile-upload] profileId=${profile.id} kind=$normalizedKind bucket=$bucket path=$storagePath',
    );

    try {
      await _client.storage.from(bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeForExtension(normalizedExtension),
              upsert: true,
            ),
          );

      return _client.storage.from(bucket).getPublicUrl(storagePath);
    } on StorageException catch (error) {
      perfLog(
        '[profile-upload] storage error profileId=${profile.id} kind=$normalizedKind bucket=$bucket statusCode=${error.statusCode} message=${error.message} error=${error.error}',
      );
      rethrow;
    }
  }

  Future<SpotDetailData> fetchSpotDetail(String spotId) async {
    return _runTimed('fetchSpotDetail', () async {
      final normalizedSpotId = spotId.trim();
      if (normalizedSpotId.isEmpty) {
        debugPrint('[SPOT_REPO] result spotId=$normalizedSpotId found=false');
      }
      final results = await Future.wait<dynamic>([
        _client
            .from('fishing_spots')
            .select(_spotBaseSelect)
            .eq('id', normalizedSpotId)
            .single(),
        _fetchLatestScores(<String>[normalizedSpotId]),
        _fetchLatestWeatherSnapshotPairs(<String>[normalizedSpotId]),
      ]);

      final spotRow = results[0];
      final scoresBySpot = results[1] as Map<String, FishingScore>;
      final weatherBySpot = results[2] as Map<String, _WeatherSnapshotPair>;
      final spot = FishingSpot.fromMap(spotRow);
      final weatherPair = weatherBySpot[_normalizeWeatherSpotId(spot.id)] ??
          weatherBySpot[_normalizeWeatherSpotId(normalizedSpotId)];
      final currentWeather = weatherPair?.current;
      final previousWeather = weatherPair?.previous;

      return SpotDetailData(
        spot: spot,
        score: _resolveSpotScore(
          spotId: spot.id,
          storedScore: scoresBySpot[spot.id],
          currentWeather: currentWeather,
          previousWeather: previousWeather,
        ),
        weatherSnapshot: currentWeather,
      );
    }).catchError((error) {
      debugPrint('[SPOT_REPO] result spotId=$spotId found=false error=$error');
      throw error;
    });
  }

  Future<SpotDetailData> enrichSpotDetailData(SpotDetailData detail) async {
    return _runTimed('enrichSpotDetailData', () async {
      final spotId = detail.spot.id.trim();
      if (spotId.isEmpty) {
        return detail;
      }

      final results = await Future.wait<dynamic>([
        _fetchLatestScores(<String>[spotId]),
        _fetchLatestWeatherSnapshotPairs(<String>[spotId]),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final weatherPair = weatherBySpot[_normalizeWeatherSpotId(spotId)];
      final currentWeather = weatherPair?.current;

      return detail.copyWith(
        score: _resolveSpotScore(
          spotId: spotId,
          storedScore: scoresBySpot[spotId],
          currentWeather: currentWeather,
          previousWeather: weatherPair?.previous,
        ),
        weatherSnapshot: currentWeather,
      );
    });
  }

  Future<void> updateSpotVisibility({
    required String spotId,
    required String visibility,
  }) async {
    final profile = await _profile();

    final updatedRows = await _client
        .from('fishing_spots')
        .update({
          'visibility': visibility,
        })
        .eq('id', spotId)
        .eq('owner_profile_id', profile.id)
        .select('id');

    if (updatedRows.isEmpty) {
      throw Exception('Bu merayı yalnızca sahibi güncelleyebilir.');
    }
  }

  String _normalizeSpotVisibilityForInsert(String visibility) {
    final normalized = visibility.trim().toLowerCase();
    if (normalized == 'public') {
      return 'exact';
    }
    return normalized;
  }

  Future<List<NearbySpotMatch>> findNearbySpotMatches({
    required double latitude,
    required double longitude,
    double radiusMeters = _duplicateSpotRadiusMeters,
    int limit = 5,
  }) async {
    return _runTimed('findNearbySpotMatches', () async {
      final visibleSpots = await fetchVisibleSpots(
        includeScores: true,
        includeWeather: false,
      );
      if (visibleSpots.isEmpty) {
        return const <NearbySpotMatch>[];
      }

      const distance = Distance();
      final nearbyItems = visibleSpots
          .map((item) {
            final distanceMeters = distance.as(
              LengthUnit.Meter,
              LatLng(latitude, longitude),
              LatLng(item.spot.latitude, item.spot.longitude),
            );
            return (item, distanceMeters);
          })
          .where((entry) => entry.$2 <= radiusMeters)
          .toList(growable: false);
      if (nearbyItems.isEmpty) {
        return const <NearbySpotMatch>[];
      }

      nearbyItems.sort((left, right) => left.$2.compareTo(right.$2));
      final limitedItems = nearbyItems.take(limit).toList(growable: false);
      final contributionCounts = await _fetchContributionCountsForSpots(
        limitedItems
            .map((entry) => entry.$1.spot.id)
            .where((id) => id.trim().isNotEmpty)
            .toList(growable: false),
      );

      final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24));
      final recentContributionCounts = await _fetchContributionCountsForSpots(
        limitedItems
            .map((entry) => entry.$1.spot.id)
            .where((id) => id.trim().isNotEmpty)
            .toList(growable: false),
        createdAfter: cutoff,
      );

      return limitedItems
          .map(
            (entry) => NearbySpotMatch(
              spot: entry.$1.spot,
              distanceMeters: entry.$2,
              scoreValue: entry.$1.score?.scoreValue,
              contributionCount: contributionCounts[entry.$1.spot.id] ?? 0,
              recentContributionCount:
                  recentContributionCounts[entry.$1.spot.id] ?? 0,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<FishingSpot> addFishingSpot({
    required String name,
    required double latitude,
    required double longitude,
    required String visibility,
    String? region,
    String? waterType,
  }) async {
    final profile = await _profile();
    final normalizedVisibility = _normalizeSpotVisibilityForInsert(visibility);
    final payload = {
      'owner_profile_id': profile.id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'region': _nullableText(region),
      'water_type': _nullableText(waterType),
      'visibility': normalizedVisibility,
    };
    perfLog(
      '[spot-add][audit] current profile id=${profile.id}',
    );
    perfLog(
      '[spot-add][audit] payload sent name=${name.trim()} lat=$latitude lng=$longitude visibility=$normalizedVisibility region=${payload['region'] ?? 'null'} waterType=${payload['water_type'] ?? 'null'}',
    );

    try {
      final row = await _client
          .from('fishing_spots')
          .insert(payload)
          .select(_spotBaseSelect)
          .single();
      final spot = FishingSpot.fromMap(row);
      return spot;
    } catch (error) {
      rethrow;
    }
  }

  Future<void> toggleFavorite({
    required String spotId,
    required bool shouldFavorite,
  }) async {
    final profile = await _profile();

    if (shouldFavorite) {
      await _client.from('favorites').upsert({
        'profile_id': profile.id,
        'fishing_spot_id': spotId,
      }, onConflict: 'profile_id,fishing_spot_id');
      return;
    }

    await _client
        .from('favorites')
        .delete()
        .eq('profile_id', profile.id)
        .eq('fishing_spot_id', spotId);
  }

  Future<bool> isSpotFavorited(String spotId) async {
    final normalizedSpotId = spotId.trim();
    if (normalizedSpotId.isEmpty) {
      return false;
    }

    final favoriteSpotIds =
        await _fetchFavoriteSpotIds(<String>[normalizedSpotId]);
    return favoriteSpotIds.contains(normalizedSpotId);
  }

  Future<List<AppProfile>> fetchShareableProfiles() async {
    final profile = await _profile();
    return fetchFollowingForProfile(profile.id);
  }

  Future<int> fetchUnreadNotificationsCount() async {
    return _runTimed('fetchUnreadNotificationsCount', () async {
      final profile = await _profile();
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', profile.id)
          .eq('is_read', false);
      return (rows as List).length;
    });
  }

  Future<List<AppNotification>> fetchNotifications() async {
    return _runTimed('fetchNotifications', () async {
      final profile = await _profile();
      final rows = await _client
          .from('notifications')
          .select(_notificationBaseSelect)
          .eq('recipient_profile_id', profile.id)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((row) => AppNotification.fromMap(row as Map<String, dynamic>))
          .where((item) => item.id.trim().isNotEmpty)
          .toList(growable: false);
    });
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final normalizedNotificationId = notificationId.trim();
    if (normalizedNotificationId.isEmpty) {
      return;
    }

    final profile = await _profile();
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', normalizedNotificationId)
        .eq('recipient_profile_id', profile.id);
  }

  Future<void> _createDirectMessageNotification({
    required String recipientProfileId,
    required String conversationId,
    required String messagePreview,
  }) async {
    final stopwatch = Stopwatch()..start();
    final normalizedRecipientProfileId = recipientProfileId.trim();
    final normalizedConversationId = conversationId.trim();
    final normalizedMessagePreview = messagePreview.trim();
    if (normalizedRecipientProfileId.isEmpty ||
        normalizedConversationId.isEmpty) {
      stopwatch.stop();
      perfLog(
          '[perf] dm notification create ${stopwatch.elapsedMilliseconds}ms');
      return;
    }

    try {
      await _client.rpc(
        'create_dm_message_notification',
        params: {
          'target_conversation_id': normalizedConversationId,
          'target_recipient_profile_id': normalizedRecipientProfileId,
          'target_message_preview': normalizedMessagePreview.isEmpty
              ? null
              : normalizedMessagePreview,
        },
      );
      _dmAuditLog(
        'dm notification created recipient=$normalizedRecipientProfileId conversation=$normalizedConversationId',
      );
    } finally {
      stopwatch.stop();
      perfLog(
          '[perf] dm notification create ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<List<AppProfile>> fetchSpotSharedProfiles(String spotId) async {
    final normalizedSpotId = spotId.trim();
    if (normalizedSpotId.isEmpty) {
      return const [];
    }

    return _runTimed('fetchSpotSharedProfiles', () async {
      final rows = await _client
          .from('spot_access')
          .select('profile_id')
          .eq('fishing_spot_id', normalizedSpotId)
          .order('created_at', ascending: true);

      final profileIds = (rows as List)
          .map((row) => (row as Map<String, dynamic>)['profile_id']?.toString())
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);

      return _resolveProfilesInOrder(profileIds);
    });
  }

  Future<void> updateSpotAccess({
    required String spotId,
    required List<String> profileIds,
  }) async {
    final normalizedSpotId = spotId.trim();
    if (normalizedSpotId.isEmpty) {
      throw Exception('Geçerli mera kimliği bulunamadı.');
    }

    final profile = await _profile();
    final normalizedProfileIds = profileIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != profile.id)
        .toSet()
        .toList(growable: false);

    final ownerRow = await _client
        .from('fishing_spots')
        .select('id, name')
        .eq('id', normalizedSpotId)
        .eq('owner_profile_id', profile.id)
        .maybeSingle();
    if (ownerRow == null) {
      throw Exception('Bu paylaşımı yalnızca mera sahibi yönetebilir.');
    }

    final existingRows = await _client
        .from('spot_access')
        .select('profile_id')
        .eq('fishing_spot_id', normalizedSpotId);
    final existingProfileIds = (existingRows as List)
        .map((row) => (row as Map<String, dynamic>)['profile_id']?.toString())
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    await _client
        .from('spot_access')
        .delete()
        .eq('fishing_spot_id', normalizedSpotId);

    if (normalizedProfileIds.isEmpty) {
      return;
    }

    await _client.from('spot_access').upsert(
          normalizedProfileIds
              .map(
                (profileId) => {
                  'fishing_spot_id': normalizedSpotId,
                  'profile_id': profileId,
                },
              )
              .toList(growable: false),
          onConflict: 'fishing_spot_id,profile_id',
        );

    final newlyAddedProfileIds = normalizedProfileIds
        .where((profileId) => !existingProfileIds.contains(profileId))
        .toList(growable: false);
    if (newlyAddedProfileIds.isEmpty) {
      return;
    }

    await _client.from('notifications').insert(
          newlyAddedProfileIds
              .map(
                (recipientProfileId) => {
                  'type': 'spot_shared',
                  'recipient_profile_id': recipientProfileId,
                  'actor_profile_id': profile.id,
                  'fishing_spot_id': normalizedSpotId,
                  'is_read': false,
                },
              )
              .toList(growable: false),
        );
  }

  Future<Map<String, int>> _fetchContributionCountsForSpots(
    List<String> spotIds, {
    DateTime? createdAfter,
  }) async {
    final normalizedSpotIds = spotIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedSpotIds.isEmpty) {
      return const <String, int>{};
    }

    final rows = await _client
        .from('post_spots')
        .select('fishing_spot_id, posts!inner(created_at)')
        .inFilter('fishing_spot_id', normalizedSpotIds);

    final counts = <String, int>{
      for (final spotId in normalizedSpotIds) spotId: 0,
    };
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final spotId = map['fishing_spot_id']?.toString().trim() ?? '';
      if (spotId.isEmpty) {
        continue;
      }

      if (createdAfter != null) {
        final posts = map['posts'];
        final firstPost = posts is List && posts.isNotEmpty
            ? Map<String, dynamic>.from(posts.first as Map)
            : posts is Map
                ? Map<String, dynamic>.from(posts)
                : const <String, dynamic>{};
        final createdAt = DateTime.tryParse(
          firstPost['created_at']?.toString() ?? '',
        );
        if (createdAt == null || createdAt.isBefore(createdAfter)) {
          continue;
        }
      }

      counts.update(spotId, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts;
  }

  Future<String> createPost({
    required String caption,
    required String visibility,
    required FishingSpot spot,
    Uint8List? photoBytes,
    String? photoExtension,
  }) async {
    return _runTimed('createPost', () async {
      try {
        final user = _authService.currentUser;
        if (user == null) {
          throw Exception('Oturum açmış kullanıcı bulunamadı.');
        }

        final payload = <String, dynamic>{
          'user_id': user.id,
          'spot_id': spot.id,
          'caption': _nullableText(caption),
          'visibility': visibility,
        };
        final insertPayload = Map<String, dynamic>.from(payload)
          ..remove('spot_id');

        debugPrint('[CREATE_POST] payload keys=${payload.keys}');
        debugPrint('[CREATE_POST] spotId=${payload['spot_id']}');
        debugPrint('[CREATE_POST] userId=${payload['user_id']}');

        final preparationStopwatch = Stopwatch()..start();
        final Map<String, dynamic> postRow;
        try {
          verboseDebugLog('[CREATE_POST_FLOW] repository insert start');
          final insertStopwatch = Stopwatch()..start();
          final res = await _client.from('posts').insert(insertPayload).select();
          insertStopwatch.stop();
          debugPrint('[CREATE_POST] insert success res=$res');
          postRow = (res as List).single as Map<String, dynamic>;
          final insertedPostId = postRow['id'] as String;
          verboseDebugLog(
            '[CREATE_POST_FLOW] repository insert success postId=$insertedPostId',
          );
          verboseDebugLog(
            '[CREATE_POST_FLOW] repository insert duration=${insertStopwatch.elapsedMilliseconds}ms',
          );
        } catch (e, st) {
          debugPrint('[CREATE_POST] insert failure payload=$payload');
          debugPrint('[CREATE_POST] insert error=$e');
          debugPrint('[CREATE_POST] insert stack=$st');
          rethrow;
        }

        final postId = postRow['id'] as String;
        final postSpotStopwatch = Stopwatch()..start();
        await _client.from('post_spots').insert({
          'post_id': postId,
          'fishing_spot_id': spot.id,
          'latitude': spot.latitude,
          'longitude': spot.longitude,
          'region': _nullableText(spot.region),
          'visibility_override': visibility,
        });
        postSpotStopwatch.stop();
        verboseDebugLog(
          '[CREATE_POST_FLOW] repository post_spots insert duration=${postSpotStopwatch.elapsedMilliseconds}ms',
        );
        preparationStopwatch.stop();
        perfLog(
            'createPost preparation took ${preparationStopwatch.elapsedMilliseconds}ms');

        if (photoBytes == null || photoBytes.isEmpty) {
          verboseDebugLog(
            '[CREATE_POST_FLOW] repository createPost end duration=${preparationStopwatch.elapsedMilliseconds}ms postId=$postId photoUploadSkipped=true',
          );
          return postId;
        }

        final normalizedExtension = _normalizedPhotoExtension(photoExtension);
        final storagePath =
            '${user.id}/$postId/${DateTime.now().millisecondsSinceEpoch}.$normalizedExtension';

        final uploadStopwatch = Stopwatch()..start();
        verboseDebugLog(
            '[CREATE_POST_FLOW] image upload bytes=${photoBytes.length}');
        verboseDebugLog('[CREATE_POST_FLOW] image upload start postId=$postId');
        await _client.storage.from('post-photos').uploadBinary(
              storagePath,
              photoBytes,
              fileOptions: FileOptions(
                contentType: _contentTypeForExtension(normalizedExtension),
                upsert: false,
              ),
            );
        uploadStopwatch.stop();
        verboseDebugLog(
          '[CREATE_POST_FLOW] image upload duration=${uploadStopwatch.elapsedMilliseconds}ms postId=$postId',
        );

        final postPhotoInsertStopwatch = Stopwatch()..start();
        await _client.from('post_photos').insert({
          'post_id': postId,
          'storage_path': storagePath,
        });
        postPhotoInsertStopwatch.stop();
        verboseDebugLog(
          '[CREATE_POST_FLOW] repository post_photos insert duration=${postPhotoInsertStopwatch.elapsedMilliseconds}ms',
        );
        perfLog(
            'createPost media upload+link took ${uploadStopwatch.elapsedMilliseconds}ms');
        verboseDebugLog(
          '[CREATE_POST_FLOW] repository createPost end duration=${preparationStopwatch.elapsedMilliseconds + uploadStopwatch.elapsedMilliseconds + postPhotoInsertStopwatch.elapsedMilliseconds}ms postId=$postId',
        );
        return postId;
      } catch (e, st) {
        debugPrint('[CREATE_POST] submit failure error=$e');
        debugPrint('[CREATE_POST] submit stack=$st');
        rethrow;
      }
    });
  }

  Future<List<SocialPost>> hydratePostImages(
    List<SocialPost> posts, {
    int maxResolveCount = _defaultDeferredImageResolveCount,
  }) async {
    final storagePaths = posts
        .where((post) => (post.imageUrl ?? '').trim().isEmpty)
        .map((post) => post.imageStoragePath)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (storagePaths.isEmpty) {
      return posts;
    }

    final signedUrls = await _resolveSignedUrls(
      storagePaths,
      maxResolveCount: maxResolveCount,
    );
    return posts
        .map(
          (post) => post.copyWith(
            imageUrl: post.imageUrl ?? signedUrls[post.imageStoragePath],
          ),
        )
        .toList(growable: false);
  }

  Future<List<SpotFeedItem>> _fetchPublicSharedSpotsForProfile(
    AppProfile profile, {
    required bool includeAllVisibilities,
    List<String>? knownPostIds,
  }) async {
    return _runTimed('_fetchPublicSharedSpotsForProfile', () async {
      final normalizedPostIds = (knownPostIds ?? const <String>[])
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final rows = await _client.rpc(
        'get_profile_shared_spots_base_v1',
        params: {
          'p_profile_lookup': profile.id,
          'p_include_all_visibilities': includeAllVisibilities,
          'p_known_post_ids':
              normalizedPostIds.isEmpty ? null : normalizedPostIds,
        },
      );
      final spots = (rows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where((spot) => spot.id.isNotEmpty)
          .toList(growable: false);

      if (spots.isEmpty) {
        return [];
      }

      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final results = await Future.wait<dynamic>([
        _fetchLatestScores(spotIds),
        _fetchLatestWeatherSnapshotPairs(spotIds),
        _fetchFavoriteSpotIds(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final favoriteSpotIds = results[2] as Set<String>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: true,
        favoriteSpotIds: favoriteSpotIds,
      );
    });
  }

  Future<List<SpotFeedItem>> _fetchOwnedSpotsForProfile(
    AppProfile profile,
  ) async {
    return _runTimed('_fetchOwnedSpotsForProfile', () async {
      final rows = await _client
          .from('fishing_spots')
          .select(_spotBaseSelect)
          .eq('owner_profile_id', profile.id)
          .order('created_at', ascending: false);

      final spots = (rows as List)
          .map((item) => FishingSpot.fromMap(item as Map<String, dynamic>))
          .where((spot) => spot.id.isNotEmpty)
          .toList(growable: false);

      if (spots.isEmpty) {
        return [];
      }

      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final results = await Future.wait<dynamic>([
        _fetchLatestScores(spotIds),
        _fetchLatestWeatherSnapshotPairs(spotIds),
        _fetchFavoriteSpotIds(spotIds),
      ]);
      final scoresBySpot = results[0] as Map<String, FishingScore>;
      final weatherBySpot = results[1] as Map<String, _WeatherSnapshotPair>;
      final favoriteSpotIds = results[2] as Set<String>;

      return _buildSpotFeedItems(
        spots,
        storedScoresBySpot: scoresBySpot,
        weatherBySpot: weatherBySpot,
        exposeWeatherSnapshots: true,
        favoriteSpotIds: favoriteSpotIds,
      );
    });
  }

  Future<Set<String>> _fetchFavoriteSpotIds(List<String> spotIds) async {
    final normalizedSpotIds = spotIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedSpotIds.isEmpty) {
      return const <String>{};
    }

    final profile = await _profile();
    final favoriteRows = await _client
        .from('favorites')
        .select('fishing_spot_id')
        .eq('profile_id', profile.id)
        .inFilter('fishing_spot_id', normalizedSpotIds);

    return (favoriteRows as List)
        .map(
          (row) => (row as Map<String, dynamic>)['fishing_spot_id']
              ?.toString()
              .trim(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Map<String, AppProfile>> _fetchProfilesById(
      List<String> userIds) async {
    return _runTimed('_fetchProfilesById', () async {
      if (userIds.isEmpty) {
        return {};
      }

      final normalizedIds =
          userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
      if (normalizedIds.isEmpty) {
        return {};
      }

      List rows = [];

      try {
        rows = await _client
            .from('profiles')
            .select(_profileBaseSelect)
            .inFilter('auth_user_id', normalizedIds);
      } catch (_) {
        rows = [];
      }

      final profiles = <String, AppProfile>{};
      for (final row in rows) {
        final profile = AppProfile.fromMap(row as Map<String, dynamic>);
        if (profile.id.isNotEmpty) {
          profiles[profile.id] = profile;
        }
        if ((profile.authUserId ?? '').isNotEmpty) {
          profiles[profile.authUserId!] = profile;
        }
        profiles[profile.postUserId] = profile;
      }

      final missingIds =
          normalizedIds.where((id) => !profiles.containsKey(id)).toList();
      if (missingIds.isEmpty) {
        perfLog(
            '_fetchProfilesById resolved ids=${normalizedIds.length} missing=0');
        return profiles;
      }

      try {
        rows = await _client
            .from('profiles')
            .select(_profileBaseSelect)
            .inFilter('id', missingIds);
      } catch (_) {
        rows = [];
      }

      for (final row in rows) {
        final profile = AppProfile.fromMap(row as Map<String, dynamic>);
        if (profile.id.isNotEmpty) {
          profiles[profile.id] = profile;
        }
        if ((profile.authUserId ?? '').isNotEmpty) {
          profiles[profile.authUserId!] = profile;
        }
        profiles[profile.postUserId] = profile;
      }
      perfLog(
          '_fetchProfilesById resolved ids=${normalizedIds.length} missing=${missingIds.length}');
      return profiles;
    });
  }

  Future<List<AppProfile>> _resolveProfilesInOrder(
      List<String> profileIds) async {
    if (profileIds.isEmpty) {
      return const [];
    }

    final profilesById = await _fetchProfilesById(profileIds);
    final orderedProfiles = <AppProfile>[];
    final addedProfileIds = <String>{};

    for (final profileId in profileIds) {
      final profile = profilesById[profileId];
      if (profile == null ||
          profile.id.isEmpty ||
          addedProfileIds.contains(profile.id)) {
        continue;
      }

      orderedProfiles.add(profile);
      addedProfileIds.add(profile.id);
    }

    return orderedProfiles;
  }

  Future<Map<String, dynamic>?> _findProfileByAuthUserId(
      String authUserId) async {
    try {
      return await _client
          .from('profiles')
          .select(_profileBaseSelect)
          .eq('auth_user_id', authUserId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _findLegacyProfileById(String profileId) async {
    try {
      return await _client
          .from('profiles')
          .select(_profileBaseSelect)
          .eq('id', profileId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  Future<AppProfile> _resolveCanonicalCurrentProfile({
    required String scope,
  }) async {
    final authUid = _authService.currentUser?.id;
    if (authUid == null) {
      throw Exception('Oturum açmış kullanıcı bulunamadı.');
    }

    final cachedProfile = _cachedCurrentProfile;
    if (cachedProfile != null && _cachedCurrentProfileAuthUid == authUid) {
      return cachedProfile;
    }

    final pendingProfile = _pendingCurrentProfileResolution;
    if (pendingProfile != null && _cachedCurrentProfileAuthUid == authUid) {
      return pendingProfile;
    }

    final future = perfRunTimed('ensureProfile', () {
      return _authService.ensureProfile();
    });
    _pendingCurrentProfileResolution = future;
    _cachedCurrentProfileAuthUid = authUid;

    try {
      final profile = await future;
      _cachedCurrentProfile = profile;
      return profile;
    } finally {
      if (identical(_pendingCurrentProfileResolution, future)) {
        _pendingCurrentProfileResolution = null;
      }
    }
  }

  Future<String> _resolveCurrentProfileId({
    String? currentProfileId,
    required String scope,
  }) async {
    final normalizedProfileId = currentProfileId?.trim() ?? '';
    if (normalizedProfileId.isNotEmpty) {
      return normalizedProfileId;
    }

    final profile = await _resolveCanonicalCurrentProfile(scope: scope);
    return profile.id.trim();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return const <dynamic>[];
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<String> _asStringList(dynamic value) {
    return _asList(value)
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, FishingScore>> _fetchLatestScores(
      List<String> spotIds) async {
    if (spotIds.isEmpty) {
      return {};
    }

    return _runTimed('_fetchLatestScores', () async {
      final scoreRows = await _client.rpc(
        'get_latest_fishing_scores_v1',
        params: {
          'p_spot_ids': spotIds,
        },
      );

      final latestBySpot = <String, FishingScore>{};

      for (final row in scoreRows as List) {
        final score = _scoreFromRow(row);
        latestBySpot.putIfAbsent(score.fishingSpotId, () => score);
      }

      return latestBySpot;
    });
  }

  FishingScore _scoreFromRow(dynamic row) {
    return FishingScore.fromMap(row as Map<String, dynamic>);
  }

  List<SpotFeedItem> _buildSpotFeedItems(
    List<FishingSpot> spots, {
    required Map<String, FishingScore> storedScoresBySpot,
    required Map<String, _WeatherSnapshotPair> weatherBySpot,
    required Set<String> favoriteSpotIds,
    bool exposeWeatherSnapshots = false,
    Map<String, SpotFeedItem>? existingItemsBySpot,
  }) {
    return spots.map(
      (spot) {
        final weatherPair = weatherBySpot[_normalizeWeatherSpotId(spot.id)];
        final currentWeather = weatherPair?.current;
        final existingItem = existingItemsBySpot?[spot.id.trim()];

        return SpotFeedItem(
          spot: spot,
          score: _resolveSpotScore(
            spotId: spot.id,
            storedScore: storedScoresBySpot[spot.id],
            currentWeather: currentWeather,
            previousWeather: weatherPair?.previous,
          ),
          weatherSnapshot: exposeWeatherSnapshots ? currentWeather : null,
          isSaved: favoriteSpotIds.contains(spot.id),
          sharedByProfileId: existingItem?.sharedByProfileId,
          sharedByDisplayName: existingItem?.sharedByDisplayName,
          sharedByUsername: existingItem?.sharedByUsername,
          sharedByAvatarUrl: existingItem?.sharedByAvatarUrl,
        );
      },
    ).toList(growable: false);
  }

  SpotFeedItem _homeFeedCardItemFromMap(Map<String, dynamic> map) {
    final spotId = _firstNonEmptyString(map, const ['spot_id']) ?? '';
    final authorId = _firstNonEmptyString(map, const ['author_id']);
    final createdAt = _firstParsedDateTime(map, const ['created_at']);
    final scoreSummary = _firstNonEmptyString(map, const ['score_summary']);

    return SpotFeedItem(
      spot: FishingSpot(
        id: spotId,
        ownerProfileId: authorId ?? '',
        name: _firstNonEmptyString(map, const ['spot_name']) ?? 'Adsız mera',
        latitude: _asDouble(map['spot_lat']),
        longitude: _asDouble(map['spot_lng']),
        visibility: 'exact',
        status: 'active',
        createdAt: createdAt,
      ),
      score: _feedCardScore(spotId, scoreSummary),
      sharedByProfileId: authorId,
      sharedByDisplayName: _firstNonEmptyString(map, const ['author_name']),
      sharedByAvatarUrl: _firstNonEmptyString(
        map,
        const ['author_avatar_url'],
      ),
      sourcePostId: _firstNonEmptyString(map, const ['post_id']),
      sourceUserId: authorId,
      sharedAt: createdAt,
    );
  }

  SpotFeedItem _mapSpotCardItemFromMap(Map<String, dynamic> map) {
    final spotId = _firstNonEmptyString(map, const ['spot_id']) ?? '';
    final rawScoreValue = map['score_value'];
    final scoreValue = rawScoreValue == null ? null : _asInt(rawScoreValue);
    return SpotFeedItem(
      spot: FishingSpot(
        id: spotId,
        ownerProfileId: '',
        name: _firstNonEmptyString(map, const ['name']) ?? 'Adsız mera',
        latitude: _asDouble(map['latitude']),
        longitude: _asDouble(map['longitude']),
        visibility: 'exact',
        status: 'active',
        waterType: _firstNonEmptyString(map, const ['water_type']),
      ),
      score: scoreValue == null
          ? null
          : FishingScore(
              id: 'map:$spotId',
              fishingSpotId: spotId,
              scoreValue: scoreValue,
              scoreLabel: scoreValue >= 70 ? 'İyi' : 'Orta',
              scoreSummary: 'Skor $scoreValue',
              scoreTime: DateTime.now(),
            ),
    );
  }

  SocialPost _profilePostCardFromMap(Map<String, dynamic> map) {
    final thumbnail = _firstNonEmptyString(map, const ['thumbnail_url']);
    final imageUrl = _looksLikeRemoteUrl(thumbnail) ? thumbnail : null;
    final imageStoragePath = imageUrl == null ? thumbnail : null;

    return SocialPost.fromMap({
      'id': map['post_id'],
      'user_id': map['profile_id'],
      'author_profile_id': map['profile_id'],
      'caption': map['caption'],
      'created_at': map['created_at'],
      'image_url': imageUrl,
      'image_storage_path': imageStoragePath,
      'fishing_spot_id': map['fishing_spot_id'],
      'linked_fishing_spot_id': map['fishing_spot_id'],
      'region': map['region'],
      'latitude': map['latitude'],
      'longitude': map['longitude'],
    });
  }

  SpotFeedItem _spotFeedItemFromMap(Map<String, dynamic> map) {
    final sharedByProfileId = _firstNonEmptyString(
      map,
      const ['sharer_profile_id', 'shared_by_profile_id'],
    );
    final sharedByDisplayName = _firstNonEmptyString(
      map,
      const ['shared_by_display_name'],
    );
    final sharedByUsername = _firstNonEmptyString(
      map,
      const ['shared_by_username'],
    );
    final sharedByAvatarUrl = _firstNonEmptyString(
      map,
      const ['shared_by_avatar_url'],
    );
    final sharedAt = _firstParsedDateTime(
      map,
      const ['shared_at', 'source_created_at', 'post_created_at'],
    );
    final sourcePostId = _firstNonEmptyString(
      map,
      const ['source_post_id', 'post_id'],
    );
    final sourceUserId = _firstNonEmptyString(
      map,
      const ['source_user_id', 'user_id', 'author_profile_id'],
    );

    return SpotFeedItem(
      spot: FishingSpot.fromMap(map),
      sharedByProfileId:
          (sharedByProfileId == null || sharedByProfileId.isEmpty)
              ? null
              : sharedByProfileId,
      sharedByDisplayName:
          (sharedByDisplayName == null || sharedByDisplayName.isEmpty)
              ? null
              : sharedByDisplayName,
      sharedByUsername: (sharedByUsername == null || sharedByUsername.isEmpty)
          ? null
          : sharedByUsername,
      sharedByAvatarUrl:
          (sharedByAvatarUrl == null || sharedByAvatarUrl.isEmpty)
              ? null
              : sharedByAvatarUrl,
      sharedAt: sharedAt,
      sourcePostId:
          (sourcePostId == null || sourcePostId.isEmpty) ? null : sourcePostId,
      sourceUserId:
          (sourceUserId == null || sourceUserId.isEmpty) ? null : sourceUserId,
    );
  }

  String? _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  DateTime? _firstParsedDateTime(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key]?.toString().trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  FishingScore? _feedCardScore(String spotId, String? scoreSummary) {
    final raw = scoreSummary?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final leadingNumber = RegExp(r'^(\d+)').firstMatch(raw);
    final scoreValue = leadingNumber == null
        ? null
        : int.tryParse(leadingNumber.group(1) ?? '');
    if (scoreValue == null) {
      return null;
    }

    return FishingScore(
      id: 'feed:$spotId',
      fishingSpotId: spotId,
      scoreValue: scoreValue,
      scoreLabel: scoreValue >= 70 ? 'İyi' : 'Orta',
      scoreSummary: raw,
      scoreTime: DateTime.now(),
    );
  }

  bool _looksLikeRemoteUrl(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  Future<Map<String, _WeatherSnapshotPair>> _fetchLatestWeatherSnapshotPairs(
    List<String> spotIds,
  ) async {
    if (spotIds.isEmpty) {
      return {};
    }

    return _runTimed('_fetchLatestWeatherSnapshotPairs', () async {
      final normalizedSpotIds = spotIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .map(_normalizeWeatherSpotId)
          .toSet()
          .toList(growable: false);
      if (normalizedSpotIds.isEmpty) {
        return {};
      }

      final weatherRows = await _client.rpc(
        'get_latest_weather_snapshots_v1',
        params: {
          'p_spot_ids': normalizedSpotIds,
        },
      );
      final rowList = _asList(weatherRows);

      final currentBySpot = <String, WeatherSnapshot>{};
      final previousBySpot = <String, WeatherSnapshot>{};
      for (final row in rowList) {
        final map = _asMap(row);
        if (map.isEmpty) {
          continue;
        }
        final snapshot = WeatherSnapshot.fromMap(map);
        final rank = _asInt(map['snapshot_rank']);
        if (snapshot.fishingSpotId.isEmpty) {
          continue;
        }
        final normalizedSnapshotSpotId =
            _normalizeWeatherSpotId(snapshot.fishingSpotId);

        if (rank == 1) {
          currentBySpot.putIfAbsent(normalizedSnapshotSpotId, () => snapshot);
          continue;
        }

        if (rank == 2) {
          previousBySpot.putIfAbsent(normalizedSnapshotSpotId, () => snapshot);
          continue;
        }
      }

      final weatherBySpot = {
        for (final spotId in normalizedSpotIds)
          if (currentBySpot.containsKey(spotId) ||
              previousBySpot.containsKey(spotId))
            spotId: _WeatherSnapshotPair(
              current: currentBySpot[spotId],
              previous: previousBySpot[spotId],
            ),
      };
      return weatherBySpot;
    });
  }

  FishingScore _resolveSpotScore({
    required String spotId,
    required FishingScore? storedScore,
    required WeatherSnapshot? currentWeather,
    required WeatherSnapshot? previousWeather,
  }) {
    if (currentWeather != null || previousWeather != null) {
      return _buildSmartFishingScore(
        spotId: spotId,
        currentWeather: currentWeather,
        previousWeather: previousWeather,
      );
    }

    if (storedScore != null) {
      return storedScore;
    }

    return _buildSmartFishingScore(
      spotId: spotId,
      currentWeather: null,
      previousWeather: null,
    );
  }

  FishingScore _buildSmartFishingScore({
    required String spotId,
    required WeatherSnapshot? currentWeather,
    required WeatherSnapshot? previousWeather,
  }) {
    final now = (currentWeather?.snapshotTime ?? DateTime.now()).toLocal();

    final pressureScore = _pressureScore(currentWeather?.pressure);
    final windScore = _windScore(
      speedKmh: currentWeather?.windSpeed,
      directionDegrees: currentWeather?.windDirection,
    );
    final precipitationScore =
        _precipitationScore(currentWeather?.precipitation);
    final timeScore = _timeOfDayScore(now);
    final trendBonus = _pressureTrendBonus(
      currentPressure: currentWeather?.pressure,
      previousPressure: previousWeather?.pressure,
    );

    final weightedScore = (pressureScore * 0.30) +
        (windScore * 0.25) +
        (precipitationScore * 0.15) +
        (timeScore * 0.30) +
        trendBonus;
    final finalScore = weightedScore.round().clamp(0, 100).toInt();
    final label = _scoreLabel(finalScore);

    final pressureState = _factorStateForScore(pressureScore);
    final windState = _factorStateForScore(windScore);
    final precipitationState = _factorStateForScore(precipitationScore);
    final timeState = _factorStateForScore(timeScore);

    return FishingScore(
      id: 'smart:$spotId',
      fishingSpotId: spotId,
      scoreValue: finalScore,
      scoreLabel: label,
      scoreSummary: _buildScoreSummary(
        pressureState: pressureState,
        windState: windState,
        precipitationState: precipitationState,
        timeState: timeState,
        trendBonus: trendBonus,
        hasLiveWeather: currentWeather != null,
      ),
      scoreFactors: {
        'pressure': pressureState,
        'wind': windState,
        'precipitation': precipitationState,
        'time': timeState,
        'trend': trendBonus > 0
            ? 'good'
            : trendBonus < 0
                ? 'poor'
                : 'fair',
      },
      catchProbabilityLabel: _catchProbabilityLabel(finalScore),
      activityLevelLabel: _activityLevelLabel(timeScore),
      shoreOpportunityLabel: precipitationScore >= 80 ? 'iyi' : 'orta',
      fishingStyleFit: _fishingStyleFit(windScore),
      forecastWindowStart: _currentBestWindowStart(now),
      forecastWindowEnd: _currentBestWindowEnd(now),
      scoreTime: now,
    );
  }

  int _pressureScore(double? pressure) {
    if (pressure == null) {
      return 60;
    }
    if (pressure >= 1010 && pressure <= 1020) {
      return 100;
    }
    if ((pressure >= 1005 && pressure < 1010) ||
        (pressure > 1020 && pressure <= 1025)) {
      return 70;
    }
    return 30;
  }

  int _windScore({
    required double? speedKmh,
    required int? directionDegrees,
  }) {
    int score;
    if (speedKmh == null) {
      score = 65;
    } else if (speedKmh <= 10) {
      score = 100;
    } else if (speedKmh <= 20) {
      score = 80;
    } else if (speedKmh <= 30) {
      score = 50;
    } else {
      score = 20;
    }

    if (_isFavorableWindDirection(directionDegrees)) {
      score += 10;
    }

    return score.clamp(0, 100);
  }

  bool _isFavorableWindDirection(int? directionDegrees) {
    if (directionDegrees == null) {
      return false;
    }

    final normalized = directionDegrees % 360;
    return normalized >= 120 && normalized <= 220;
  }

  int _precipitationScore(double? precipitation) {
    if (precipitation == null) {
      return 70;
    }
    if (precipitation <= 0) {
      return 100;
    }
    if (precipitation < 1.5) {
      return 80;
    }
    if (precipitation < 5) {
      return 50;
    }
    return 20;
  }

  int _timeOfDayScore(DateTime localTime) {
    if (localTime.hour >= 23 || localTime.hour < 4) {
      return 40;
    }

    final sunrise = _estimatedSunrise(localTime);
    final sunset = _estimatedSunset(localTime);
    if (_isWithinHours(localTime, sunrise, 2) ||
        _isWithinHours(localTime, sunset, 2)) {
      return 100;
    }

    return 60;
  }

  DateTime _estimatedSunrise(DateTime localTime) {
    final sunriseHour = switch (localTime.month) {
      12 || 1 || 2 => 7,
      3 || 4 || 5 => 6,
      6 || 7 => 5,
      8 || 9 => 6,
      10 || 11 => 7,
      _ => 6,
    };

    return DateTime(
        localTime.year, localTime.month, localTime.day, sunriseHour, 30);
  }

  DateTime _estimatedSunset(DateTime localTime) {
    final sunsetHour = switch (localTime.month) {
      12 || 1 => 17,
      2 || 10 || 11 => 18,
      3 || 9 => 19,
      4 || 5 || 8 => 20,
      6 || 7 => 21,
      _ => 19,
    };

    return DateTime(
        localTime.year, localTime.month, localTime.day, sunsetHour, 30);
  }

  bool _isWithinHours(DateTime value, DateTime center, int hours) {
    return value.difference(center).inMinutes.abs() <= hours * 60;
  }

  int _pressureTrendBonus({
    required double? currentPressure,
    required double? previousPressure,
  }) {
    if (currentPressure == null || previousPressure == null) {
      return 0;
    }

    final delta = currentPressure - previousPressure;
    if (delta <= -0.5) {
      return 5;
    }
    if (delta >= 0.5) {
      return -5;
    }
    return 0;
  }

  String _scoreLabel(int score) {
    if (score >= 85) {
      return 'excellent';
    }
    if (score >= 70) {
      return 'good';
    }
    if (score >= 50) {
      return 'medium';
    }
    if (score >= 30) {
      return 'weak';
    }
    return 'bad';
  }

  String _factorStateForScore(int score) {
    if (score >= 85) {
      return 'good';
    }
    if (score >= 50) {
      return 'fair';
    }
    return 'poor';
  }

  String _buildScoreSummary({
    required String pressureState,
    required String windState,
    required String precipitationState,
    required String timeState,
    required int trendBonus,
    required bool hasLiveWeather,
  }) {
    final parts = <String>[
      'Basınç ${_factorText(pressureState)}',
      'rüzgar ${_factorText(windState)}',
      'yağış ${_factorText(precipitationState)}',
      'zaman ${_factorText(timeState)}',
    ];

    final trendText = trendBonus > 0
        ? 'Düşen basınç küçük bir avantaj sağlıyor.'
        : trendBonus < 0
            ? 'Yükselen basınç skoru biraz aşağı çekiyor.'
            : null;

    final sourceText = hasLiveWeather
        ? 'Güncel hava verisiyle hesaplandı.'
        : 'Canlı hava verisi sınırlı olduğu için nötr varsayımlarla hesaplandı.';

    return '${parts.join(', ')}. ${trendText ?? ''} $sourceText'.trim();
  }

  String _factorText(String state) {
    switch (state) {
      case 'good':
        return 'çok uygun';
      case 'fair':
        return 'idare eder';
      default:
        return 'zayıf';
    }
  }

  String _catchProbabilityLabel(int score) {
    if (score >= 85) {
      return 'yüksek';
    }
    if (score >= 50) {
      return 'orta';
    }
    return 'düşük';
  }

  String _activityLevelLabel(int timeScore) {
    if (timeScore >= 100) {
      return 'yüksek';
    }
    if (timeScore >= 60) {
      return 'orta';
    }
    return 'düşük';
  }

  String _fishingStyleFit(int windScore) {
    if (windScore >= 80) {
      return 'hafif ekipman ve kıyı denemeleri';
    }
    if (windScore >= 50) {
      return 'standart kıyı takımı';
    }
    return 'korunaklı bölgeler ve ağır takım';
  }

  DateTime? _currentBestWindowStart(DateTime localTime) {
    final sunrise = _estimatedSunrise(localTime);
    final sunset = _estimatedSunset(localTime);

    if (_isWithinHours(localTime, sunrise, 2)) {
      return sunrise.subtract(const Duration(hours: 2));
    }
    if (_isWithinHours(localTime, sunset, 2)) {
      return sunset.subtract(const Duration(hours: 2));
    }

    return null;
  }

  DateTime? _currentBestWindowEnd(DateTime localTime) {
    final sunrise = _estimatedSunrise(localTime);
    final sunset = _estimatedSunset(localTime);

    if (_isWithinHours(localTime, sunrise, 2)) {
      return sunrise.add(const Duration(hours: 2));
    }
    if (_isWithinHours(localTime, sunset, 2)) {
      return sunset.add(const Duration(hours: 2));
    }

    return null;
  }

  Future<Map<String, String>> _resolveSignedUrls(
    List<String> storagePaths, {
    int maxResolveCount = _defaultDeferredImageResolveCount,
  }) async {
    if (storagePaths.isEmpty) {
      return const {};
    }

    return _runTimed('_resolveSignedUrls', () async {
      final uniquePaths = storagePaths.toSet().toList(growable: false);
      final requestedPaths = uniquePaths.take(maxResolveCount).toList(
            growable: false,
          );
      var cacheHitCount = 0;
      var dedupedCount = 0;
      var remoteCount = 0;
      for (final path in requestedPaths) {
        final cached = _signedUrlCache[path];
        if (cached != null && !cached.isExpired) {
          cacheHitCount += 1;
          continue;
        }
        if (_pendingSignedUrlRequests.containsKey(path)) {
          dedupedCount += 1;
          continue;
        }
        remoteCount += 1;
      }
      debugPrint(
        '[PERF_ROWS] signedUrls requested=${uniquePaths.length} remote=$remoteCount cacheHit=$cacheHitCount deduped=$dedupedCount',
      );
      final entries = await Future.wait(
        requestedPaths
            .map((path) async => MapEntry(path, await _signedUrlForPath(path))),
      );

      return {
        for (final entry in entries)
          if ((entry.value ?? '').isNotEmpty) entry.key: entry.value!,
      };
    });
  }

  Future<void> _assertDirectMessagePermission(
    String userA,
    String userB,
  ) async {
    final rows = await _client
        .from('follows')
        .select('follower_id, following_id')
        .or(
          'and(follower_id.eq.$userA,following_id.eq.$userB),and(follower_id.eq.$userB,following_id.eq.$userA)',
        )
        .limit(1);
    if ((rows as List).isEmpty) {
      throw Exception(
        'Mesaj için en az bir taraf diğerini takip ediyor olmalı.',
      );
    }
  }

  Future<void> _ensureConversationParticipant({
    required String conversationId,
    required String profileId,
  }) async {
    final row = await _client
        .from('conversation_participants')
        .select('id')
        .eq('conversation_id', conversationId)
        .eq('profile_id', profileId)
        .maybeSingle();
    if (row == null) {
      throw Exception('Bu konuşmaya erişimin yok.');
    }
  }

  void _dmAuditLog(String message) {}

  Future<String?> _signedUrlForPath(String storagePath) {
    final cached = _signedUrlCache[storagePath];
    if (cached != null && !cached.isExpired) {
      perfLog('_signedUrlForPath cache hit path=$storagePath');
      return Future.value(cached.url);
    }

    final pending = _pendingSignedUrlRequests[storagePath];
    if (pending != null) {
      perfLog('_signedUrlForPath joined pending request path=$storagePath');
      return pending;
    }

    final request = perfRunTimed('_signedUrlForPath remote', () async {
      final url = await _client.storage
          .from('post-photos')
          .createSignedUrl(storagePath, 60 * 60 * 24 * 7);
      if (url.isNotEmpty) {
        _signedUrlCache[storagePath] = _CachedSignedUrl(
          url: url,
          expiresAt: DateTime.now().add(_signedUrlTtl),
        );
      }
      return url.isEmpty ? null : url;
    }).whenComplete(() {
      _pendingSignedUrlRequests.remove(storagePath);
    });

    _pendingSignedUrlRequests[storagePath] = request;
    return request;
  }

  Future<T> _runTimed<T>(String label, Future<T> Function() action) async {
    return perfRunTimed(label, action);
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  String _normalizedPhotoExtension(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) {
      return 'jpg';
    }

    return trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}

class _CachedSignedUrl {
  const _CachedSignedUrl({
    required this.url,
    required this.expiresAt,
  });

  final String url;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _WeatherSnapshotPair {
  const _WeatherSnapshotPair({
    this.current,
    this.previous,
  });

  final WeatherSnapshot? current;
  final WeatherSnapshot? previous;
}

class _ProfileSummaryData {
  const _ProfileSummaryData({
    required this.profile,
    required this.totalPosts,
    required this.totalFishingSpots,
    required this.followerCount,
    required this.followingCount,
    required this.isOwnProfile,
    required this.isFollowing,
  });

  final AppProfile profile;
  final int totalPosts;
  final int totalFishingSpots;
  final int followerCount;
  final int followingCount;
  final bool isOwnProfile;
  final bool isFollowing;
}
