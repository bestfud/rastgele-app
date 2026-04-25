DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(value.toString());
}

double? _parseDouble(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value.toString());
}

int? _parseInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString());
}

Map<String, dynamic>? _parseMap(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  return null;
}

String? _parseString(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }

  return text;
}

String localizedVisibilityLabel(String? rawVisibility) {
  switch ((rawVisibility ?? '').trim().toLowerCase()) {
    case 'exact':
      return 'Tam';
    case 'approx':
      return 'Yaklaşık';
    case 'public':
      return 'Açık';
    case 'private':
      return 'Gizli';
    default:
      return (rawVisibility ?? '').trim();
  }
}

String localizedWaterTypeLabel(String? rawWaterType) {
  switch ((rawWaterType ?? '').trim().toLowerCase()) {
    case 'sea':
      return 'Deniz';
    case 'lake':
      return 'Göl';
    case 'river':
      return 'Nehir';
    default:
      return (rawWaterType ?? '').trim();
  }
}

class AppProfile {
  const AppProfile({
    required this.id,
    required this.displayName,
    this.authUserId,
    this.username,
    this.bio,
    this.city,
    this.avatarUrl,
    this.coverUrl,
    this.homeRegion,
    this.websiteUrl,
    this.instagram,
    this.xHandle,
    this.youtube,
    this.tiktok,
  });

  final String id;
  final String displayName;
  final String? authUserId;
  final String? username;
  final String? bio;
  final String? city;
  final String? avatarUrl;
  final String? coverUrl;
  final String? homeRegion;
  final String? websiteUrl;
  final String? instagram;
  final String? xHandle;
  final String? youtube;
  final String? tiktok;

  factory AppProfile.fromMap(Map<String, dynamic> map) {
    final id = _parseString(map['id']);
    final authUserId = _parseString(map['auth_user_id']);

    return AppProfile(
      id: id ?? '',
      displayName: _parseString(map['display_name']) ?? 'Balıkçı',
      authUserId: authUserId,
      username: _parseString(map['username']),
      bio: _parseString(map['bio']),
      city: _parseString(map['city']),
      avatarUrl: _parseString(map['avatar_url']),
      coverUrl: _parseString(map['cover_url']),
      homeRegion: _parseString(map['home_region']),
      websiteUrl: _parseString(map['website_url']),
      instagram: _parseString(map['instagram']),
      xHandle: _parseString(map['x_handle']),
      youtube: _parseString(map['youtube']),
      tiktok: _parseString(map['tiktok']),
    );
  }

  String get postUserId => authUserId ?? id;

  String get initials {
    final source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (username ?? '').trim();
    if (source.isEmpty) {
      return 'U';
    }

    final parts =
        source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return source.substring(0, 1).toUpperCase();
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class FishingSpot {
  const FishingSpot({
    required this.id,
    required this.ownerProfileId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.visibility,
    required this.status,
    this.region,
    this.waterType,
    this.createdAt,
  });

  final String id;
  final String ownerProfileId;
  final String name;
  final double latitude;
  final double longitude;
  final String visibility;
  final String status;
  final String? region;
  final String? waterType;
  final DateTime? createdAt;

  factory FishingSpot.fromMap(Map<String, dynamic> map) {
    return FishingSpot(
      id: _parseString(map['id']) ?? '',
      ownerProfileId: _parseString(map['owner_profile_id']) ?? '',
      name: _parseString(map['name']) ?? 'Adsız mera',
      latitude: _parseDouble(map['latitude']) ?? 0,
      longitude: _parseDouble(map['longitude']) ?? 0,
      visibility: _parseString(map['visibility']) ?? 'private',
      status: _parseString(map['status']) ?? 'active',
      region: _parseString(map['region']),
      waterType: _parseString(map['water_type']),
      createdAt: _parseDateTime(map['created_at']),
    );
  }

  bool isOwnedByProfile(String? profileId) {
    final normalizedProfileId = (profileId ?? '').trim();
    if (normalizedProfileId.isEmpty) {
      return false;
    }

    return ownerProfileId.trim() == normalizedProfileId;
  }
}

class NearbySpotMatch {
  const NearbySpotMatch({
    required this.spot,
    required this.distanceMeters,
    this.scoreValue,
    this.contributionCount = 0,
    this.recentContributionCount = 0,
  });

  final FishingSpot spot;
  final double distanceMeters;
  final int? scoreValue;
  final int contributionCount;
  final int recentContributionCount;

  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.round()} m';
  }
}

class SpotContributionDraft {
  const SpotContributionDraft({
    required this.spot,
    required this.visibility,
    this.caption,
    this.photoBytes,
    this.photoExtension,
  });

  final FishingSpot spot;
  final String visibility;
  final String? caption;
  final Object? photoBytes;
  final String? photoExtension;
}

class SpotTrustSummary {
  const SpotTrustSummary({
    required this.contributionCount,
    required this.recentContributionCount,
    required this.successCount,
    required this.emptyCount,
    required this.totalLikeCount,
    required this.trustScore,
  });

  final int contributionCount;
  final int recentContributionCount;
  final int successCount;
  final int emptyCount;
  final int totalLikeCount;
  final int trustScore;
}

class FishingScore {
  const FishingScore({
    required this.id,
    required this.fishingSpotId,
    required this.scoreValue,
    required this.scoreLabel,
    this.scoreSummary,
    this.scoreFactors,
    this.catchProbabilityLabel,
    this.activityLevelLabel,
    this.shoreOpportunityLabel,
    this.fishingStyleFit,
    this.forecastWindowStart,
    this.forecastWindowEnd,
    this.scoreTime,
  });

  final String id;
  final String fishingSpotId;
  final int scoreValue;
  final String scoreLabel;
  final String? scoreSummary;
  final Map<String, dynamic>? scoreFactors;
  final String? catchProbabilityLabel;
  final String? activityLevelLabel;
  final String? shoreOpportunityLabel;
  final String? fishingStyleFit;
  final DateTime? forecastWindowStart;
  final DateTime? forecastWindowEnd;
  final DateTime? scoreTime;

  factory FishingScore.fromMap(Map<String, dynamic> map) {
    return FishingScore(
      id: _parseString(map['id']) ?? '',
      fishingSpotId: _parseString(map['fishing_spot_id']) ?? '',
      scoreValue: _parseInt(map['score_value']) ?? 0,
      scoreLabel: _parseString(map['score_label']) ?? 'Bilinmiyor',
      scoreSummary: _parseString(map['score_summary']),
      scoreFactors: _parseMap(map['score_factors']),
      catchProbabilityLabel: _parseString(map['catch_probability_label']),
      activityLevelLabel: _parseString(map['activity_level_label']),
      shoreOpportunityLabel: _parseString(map['shore_opportunity_label']),
      fishingStyleFit: _parseString(map['fishing_style_fit']),
      forecastWindowStart: _parseDateTime(map['forecast_window_start']),
      forecastWindowEnd: _parseDateTime(map['forecast_window_end']),
      scoreTime: _parseDateTime(map['score_time']),
    );
  }
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.id,
    required this.fishingSpotId,
    required this.dataSource,
    this.snapshotTime,
    this.pressure,
    this.windSpeed,
    this.windDirection,
    this.airTemperature,
    this.precipitation,
  });

  final String id;
  final String fishingSpotId;
  final String dataSource;
  final DateTime? snapshotTime;
  final double? pressure;
  final double? windSpeed;
  final int? windDirection;
  final double? airTemperature;
  final double? precipitation;

  factory WeatherSnapshot.fromMap(Map<String, dynamic> map) {
    return WeatherSnapshot(
      id: _parseString(map['id']) ?? '',
      fishingSpotId: _parseString(map['fishing_spot_id']) ?? '',
      dataSource: _parseString(map['data_source']) ?? 'unknown',
      snapshotTime: _parseDateTime(map['snapshot_time']),
      pressure: _parseDouble(map['pressure']),
      windSpeed: _parseDouble(map['wind_speed']),
      windDirection: _parseInt(map['wind_direction']),
      airTemperature: _parseDouble(map['air_temperature']),
      precipitation: _parseDouble(map['precipitation']),
    );
  }
}

class SpotFeedItem {
  const SpotFeedItem({
    required this.spot,
    this.score,
    this.weatherSnapshot,
    this.isSaved = false,
    this.sharedByProfileId,
    this.sharedByDisplayName,
    this.sharedByUsername,
    this.sharedByAvatarUrl,
    this.sharedAt,
    this.sourcePostId,
    this.sourceUserId,
  });

  final FishingSpot spot;
  final FishingScore? score;
  final WeatherSnapshot? weatherSnapshot;
  final bool isSaved;
  final String? sharedByProfileId;
  final String? sharedByDisplayName;
  final String? sharedByUsername;
  final String? sharedByAvatarUrl;
  final DateTime? sharedAt;
  final String? sourcePostId;
  final String? sourceUserId;

  SpotSharerIdentity? get sharerIdentity {
    final profileId = sharedByProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      return null;
    }

    return SpotSharerIdentity(
      profileId: profileId,
      displayName: sharedByDisplayName,
      username: sharedByUsername,
      avatarUrl: sharedByAvatarUrl,
      sourcePostId: sourcePostId,
      sourceUserId: sourceUserId,
    );
  }

  SpotFeedItem copyWith({
    FishingSpot? spot,
    FishingScore? score,
    WeatherSnapshot? weatherSnapshot,
    bool? isSaved,
    String? sharedByProfileId,
    String? sharedByDisplayName,
    String? sharedByUsername,
    String? sharedByAvatarUrl,
    DateTime? sharedAt,
    String? sourcePostId,
    String? sourceUserId,
  }) {
    return SpotFeedItem(
      spot: spot ?? this.spot,
      score: score ?? this.score,
      weatherSnapshot: weatherSnapshot ?? this.weatherSnapshot,
      isSaved: isSaved ?? this.isSaved,
      sharedByProfileId: sharedByProfileId ?? this.sharedByProfileId,
      sharedByDisplayName: sharedByDisplayName ?? this.sharedByDisplayName,
      sharedByUsername: sharedByUsername ?? this.sharedByUsername,
      sharedByAvatarUrl: sharedByAvatarUrl ?? this.sharedByAvatarUrl,
      sharedAt: sharedAt ?? this.sharedAt,
      sourcePostId: sourcePostId ?? this.sourcePostId,
      sourceUserId: sourceUserId ?? this.sourceUserId,
    );
  }

  String? sharedByLabel({String? currentProfileId}) {
    if ((currentProfileId ?? '').isNotEmpty &&
        sharedByProfileId == currentProfileId) {
      return 'Sen paylaştın';
    }

    final displayName = sharedByDisplayName?.trim();
    final username = sharedByUsername?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      if (username != null && username.isNotEmpty) {
        final handle = username.startsWith('@') ? username : '@$username';
        return 'Paylaşan: $displayName ($handle)';
      }
      return 'Paylaşan: $displayName';
    }

    if (username != null && username.isNotEmpty) {
      final handle = username.startsWith('@') ? username : '@$username';
      return 'Paylaşan: $handle';
    }

    return null;
  }
}

class SpotSharerIdentity {
  const SpotSharerIdentity({
    required this.profileId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.sourcePostId,
    this.sourceUserId,
  });

  final String profileId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? sourcePostId;
  final String? sourceUserId;

  String primaryLabel({String? currentProfileId}) {
    if ((currentProfileId ?? '').trim().isNotEmpty &&
        profileId == currentProfileId!.trim()) {
      return 'Sen';
    }

    final trimmedDisplayName = displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      return trimmedDisplayName;
    }

    final trimmedUsername = username?.trim();
    if (trimmedUsername != null && trimmedUsername.isNotEmpty) {
      return trimmedUsername.startsWith('@')
          ? trimmedUsername
          : '@$trimmedUsername';
    }

    return 'Paylaşan';
  }

  String? secondaryLabel({String? currentProfileId}) {
    if ((currentProfileId ?? '').trim().isNotEmpty &&
        profileId == currentProfileId!.trim()) {
      return null;
    }

    final trimmedUsername = username?.trim();
    if (trimmedUsername == null || trimmedUsername.isEmpty) {
      return null;
    }

    return trimmedUsername.startsWith('@')
        ? trimmedUsername
        : '@$trimmedUsername';
  }
}

class HomeScreenData {
  const HomeScreenData({
    required this.authUid,
    required this.profile,
    required this.followedPublicSpots,
    required this.reusedStaleCache,
    required this.repositoryMethod,
    required this.followedCount,
    required this.ownPublicSpotCount,
    required this.candidatePostIds,
    required this.finalResultIds,
    required this.earlyEmptyReturn,
  });

  final String? authUid;
  final AppProfile profile;
  final List<SpotFeedItem> followedPublicSpots;
  final bool reusedStaleCache;
  final String repositoryMethod;
  final int followedCount;
  final int ownPublicSpotCount;
  final List<String> candidatePostIds;
  final List<String> finalResultIds;
  final bool earlyEmptyReturn;

  HomeScreenData copyWith({
    String? authUid,
    AppProfile? profile,
    List<SpotFeedItem>? followedPublicSpots,
    bool? reusedStaleCache,
    String? repositoryMethod,
    int? followedCount,
    int? ownPublicSpotCount,
    List<String>? candidatePostIds,
    List<String>? finalResultIds,
    bool? earlyEmptyReturn,
  }) {
    return HomeScreenData(
      authUid: authUid ?? this.authUid,
      profile: profile ?? this.profile,
      followedPublicSpots: followedPublicSpots ?? this.followedPublicSpots,
      reusedStaleCache: reusedStaleCache ?? this.reusedStaleCache,
      repositoryMethod: repositoryMethod ?? this.repositoryMethod,
      followedCount: followedCount ?? this.followedCount,
      ownPublicSpotCount: ownPublicSpotCount ?? this.ownPublicSpotCount,
      candidatePostIds: candidatePostIds ?? this.candidatePostIds,
      finalResultIds: finalResultIds ?? this.finalResultIds,
      earlyEmptyReturn: earlyEmptyReturn ?? this.earlyEmptyReturn,
    );
  }
}

class SpotDetailData {
  const SpotDetailData({
    required this.spot,
    this.score,
    this.weatherSnapshot,
  });

  final FishingSpot spot;
  final FishingScore? score;
  final WeatherSnapshot? weatherSnapshot;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.recipientProfileId,
    required this.isRead,
    required this.createdAt,
    this.actorProfileId,
    this.actorDisplayName,
    this.actorUsername,
    this.fishingSpotId,
    this.conversationId,
    this.messagePreview,
  });

  final String id;
  final String type;
  final String recipientProfileId;
  final bool isRead;
  final DateTime createdAt;
  final String? actorProfileId;
  final String? actorDisplayName;
  final String? actorUsername;
  final String? fishingSpotId;
  final String? conversationId;
  final String? messagePreview;

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final actorProfile = _parseMap(map['actor_profile']) ??
        _parseMap(map['actor']) ??
        _parseMap(map['profiles']);

    return AppNotification(
      id: _parseString(map['id']) ?? '',
      type: _parseString(map['type']) ?? 'unknown',
      recipientProfileId: _parseString(map['recipient_profile_id']) ?? '',
      isRead: map['is_read'] == true,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      actorProfileId: _parseString(map['actor_profile_id']) ??
          _parseString(actorProfile?['id']),
      actorDisplayName: _parseString(map['actor_display_name']) ??
          _parseString(actorProfile?['display_name']),
      actorUsername: _parseString(map['actor_username']) ??
          _parseString(actorProfile?['username']),
      fishingSpotId: _parseString(map['fishing_spot_id']),
      conversationId: _parseString(map['conversation_id']),
      messagePreview: _parseString(map['message_preview']),
    );
  }
}

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory DirectMessage.fromMap(Map<String, dynamic> map) {
    return DirectMessage(
      id: _parseString(map['id']) ?? '',
      conversationId: _parseString(map['conversation_id']) ?? '',
      senderId: _parseString(map['sender_id']) ?? '',
      text: _parseString(map['text']) ?? '',
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      readAt: _parseDateTime(map['read_at']),
    );
  }
}

class UserConversation {
  const UserConversation({
    required this.id,
    required this.otherProfile,
    this.lastMessageText,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final AppProfile otherProfile;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int unreadCount;
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.userId,
    this.authorProfileId,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.distanceKm,
    this.visibility,
    this.visibilityOverride,
    this.currentSpotVisibility,
    this.linkedFishingSpotId,
    this.linkedFishingSpotName,
    this.region,
    this.latitude,
    this.longitude,
    this.caption,
    this.imageUrl,
    this.imageStoragePath,
    this.fishingSpotId,
    this.createdAt,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.linkedSpotScoreValue,
    this.linkedSpotScoreLabel,
    this.linkedSpotScoreSummary,
  });

  final String id;
  final String userId;
  final String? authorProfileId;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final double? distanceKm;
  final String? visibility;
  final String? visibilityOverride;
  final String? currentSpotVisibility;
  final String? linkedFishingSpotId;
  final String? linkedFishingSpotName;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String? caption;
  final String? imageUrl;
  final String? imageStoragePath;
  final String? fishingSpotId;
  final DateTime? createdAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final int? linkedSpotScoreValue;
  final String? linkedSpotScoreLabel;
  final String? linkedSpotScoreSummary;

  factory SocialPost.fromMap(Map<String, dynamic> map) {
    final postSpots = map['post_spots'];
    final postPhotos = map['post_photos'];
    final authorProfile = _parseMap(map['author_profile']) ??
        _parseMap(map['profile']) ??
        _parseMap(map['profiles']);
    Map<String, dynamic>? firstPostSpot;
    String? firstPhotoStoragePath;

    if (postSpots is List && postSpots.isNotEmpty) {
      firstPostSpot = _parseMap(postSpots.first);
    }

    if (postPhotos is List && postPhotos.isNotEmpty) {
      final firstPostPhoto = _parseMap(postPhotos.first);
      firstPhotoStoragePath = _parseString(firstPostPhoto?['storage_path']);
    }

    final linkedFishingSpotId = _parseString(map['linked_fishing_spot_id']) ??
        _parseString(firstPostSpot?['fishing_spot_id']);
    final visibilityOverride = _parseString(map['visibility_override']) ??
        _parseString(firstPostSpot?['visibility_override']);
    final region =
        _parseString(map['region']) ?? _parseString(firstPostSpot?['region']);
    final latitude = _parseDouble(map['latitude']) ??
        _parseDouble(firstPostSpot?['latitude']);
    final longitude = _parseDouble(map['longitude']) ??
        _parseDouble(firstPostSpot?['longitude']);

    return SocialPost(
      id: _parseString(map['id']) ?? '',
      userId: _parseString(map['user_id']) ?? '',
      authorProfileId: _parseString(map['author_profile_id']) ??
          _parseString(map['profile_id']) ??
          _parseString(authorProfile?['id']),
      likeCount: _parseInt(map['like_count']) ?? 0,
      commentCount: _parseInt(map['comment_count']) ?? 0,
      isLiked: map['is_liked'] == true,
      visibility: _parseString(map['visibility']),
      visibilityOverride: visibilityOverride,
      currentSpotVisibility: _parseString(map['current_spot_visibility']),
      linkedFishingSpotId: linkedFishingSpotId,
      linkedFishingSpotName: _parseString(map['linked_fishing_spot_name']),
      region: region,
      latitude: latitude,
      longitude: longitude,
      caption: _parseString(map['caption']),
      imageUrl: _parseString(map['image_url']),
      imageStoragePath:
          _parseString(map['image_storage_path']) ?? firstPhotoStoragePath,
      fishingSpotId:
          _parseString(map['fishing_spot_id']) ?? linkedFishingSpotId,
      createdAt: _parseDateTime(map['created_at']),
      displayName: _parseString(map['display_name']),
      username: _parseString(map['username']),
      avatarUrl: _parseString(map['avatar_url']),
      linkedSpotScoreValue: _parseInt(map['linked_spot_score_value']),
      linkedSpotScoreLabel: _parseString(map['linked_spot_score_label']),
      linkedSpotScoreSummary: _parseString(map['linked_spot_score_summary']),
    );
  }

  SocialPost copyWith({
    String? id,
    String? userId,
    String? authorProfileId,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    double? distanceKm,
    String? visibility,
    String? visibilityOverride,
    String? currentSpotVisibility,
    String? linkedFishingSpotId,
    String? linkedFishingSpotName,
    String? region,
    double? latitude,
    double? longitude,
    String? caption,
    String? imageUrl,
    String? imageStoragePath,
    String? fishingSpotId,
    DateTime? createdAt,
    String? displayName,
    String? username,
    String? avatarUrl,
    int? linkedSpotScoreValue,
    String? linkedSpotScoreLabel,
    String? linkedSpotScoreSummary,
  }) {
    return SocialPost(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorProfileId: authorProfileId ?? this.authorProfileId,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      distanceKm: distanceKm ?? this.distanceKm,
      visibility: visibility ?? this.visibility,
      visibilityOverride: visibilityOverride ?? this.visibilityOverride,
      currentSpotVisibility:
          currentSpotVisibility ?? this.currentSpotVisibility,
      linkedFishingSpotId: linkedFishingSpotId ?? this.linkedFishingSpotId,
      linkedFishingSpotName:
          linkedFishingSpotName ?? this.linkedFishingSpotName,
      region: region ?? this.region,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      caption: caption ?? this.caption,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      fishingSpotId: fishingSpotId ?? this.fishingSpotId,
      createdAt: createdAt ?? this.createdAt,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      linkedSpotScoreValue: linkedSpotScoreValue ?? this.linkedSpotScoreValue,
      linkedSpotScoreLabel: linkedSpotScoreLabel ?? this.linkedSpotScoreLabel,
      linkedSpotScoreSummary:
          linkedSpotScoreSummary ?? this.linkedSpotScoreSummary,
    );
  }

  String get authorLabel {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) {
      return display;
    }

    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle.startsWith('@') ? handle : '@$handle';
    }

    return userId.length <= 8 ? userId : userId.substring(0, 8);
  }

  String get authorSecondaryLabel {
    final handle = username?.trim();
    if (handle != null &&
        handle.isNotEmpty &&
        authorLabel != (handle.startsWith('@') ? handle : '@$handle')) {
      return handle.startsWith('@') ? handle : '@$handle';
    }

    return '';
  }

  String get visibilityValue => visibility?.trim().toLowerCase() ?? '';

  bool get isExactLocation => visibilityValue == 'exact';

  bool get isApproxLocation => visibilityValue == 'approx';

  bool get isPrivateLocation => visibilityValue == 'private';

  bool get hasLocationAction => hasExactSpotAction || hasApproxLocationAction;

  bool get hasExactSpotAction =>
      isExactLocation && (linkedFishingSpotId ?? '').isNotEmpty;

  bool get hasApproxLocationAction =>
      !isPrivateLocation &&
      !hasExactSpotAction &&
      (latitude != null || longitude != null || (region ?? '').isNotEmpty);

  String get locationLabel {
    if (visibilityValue == 'exact' &&
        (linkedFishingSpotName ?? '').isNotEmpty) {
      return linkedFishingSpotName!;
    }

    if (visibilityValue == 'approx') {
      if ((region ?? '').isNotEmpty) {
        return region!;
      }
      return 'Yaklaşık konum';
    }

    if (visibilityValue == 'private') {
      return 'Gizli mera';
    }

    if ((region ?? '').isNotEmpty) {
      return region!;
    }

    if ((linkedFishingSpotName ?? '').isNotEmpty) {
      return linkedFishingSpotName!;
    }

    return '';
  }

  bool get showLocationBadge => locationLabel.isNotEmpty;

  String get locationActionLabel {
    if (hasExactSpotAction) {
      return 'Merayı aç';
    }

    if (hasApproxLocationAction && latitude != null && longitude != null) {
      return 'Haritada gör';
    }

    if (hasApproxLocationAction && (region ?? '').isNotEmpty) {
      return 'Bölgeyi gör';
    }

    return '';
  }

  String? get linkedSpotId => linkedFishingSpotId;
}

class ProfileStats {
  const ProfileStats({
    required this.totalPosts,
    required this.totalFishingSpots,
    required this.followerCount,
    required this.followingCount,
  });

  final int totalPosts;
  final int totalFishingSpots;
  final int followerCount;
  final int followingCount;

  ProfileStats copyWith({
    int? totalPosts,
    int? totalFishingSpots,
    int? followerCount,
    int? followingCount,
  }) {
    return ProfileStats(
      totalPosts: totalPosts ?? this.totalPosts,
      totalFishingSpots: totalFishingSpots ?? this.totalFishingSpots,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }
}

class ProfileScreenData {
  const ProfileScreenData({
    required this.profile,
    required this.stats,
    required this.posts,
    required this.publicSpots,
    required this.savedSpots,
    required this.sharedWithMeSpots,
    required this.isOwnProfile,
    required this.isFollowing,
  });

  final AppProfile profile;
  final ProfileStats stats;
  final List<SocialPost> posts;
  final List<SpotFeedItem> publicSpots;
  final List<SpotFeedItem> savedSpots;
  final List<SpotFeedItem> sharedWithMeSpots;
  final bool isOwnProfile;
  final bool isFollowing;

  ProfileScreenData copyWith({
    AppProfile? profile,
    ProfileStats? stats,
    List<SocialPost>? posts,
    List<SpotFeedItem>? publicSpots,
    List<SpotFeedItem>? savedSpots,
    List<SpotFeedItem>? sharedWithMeSpots,
    bool? isOwnProfile,
    bool? isFollowing,
  }) {
    return ProfileScreenData(
      profile: profile ?? this.profile,
      stats: stats ?? this.stats,
      posts: posts ?? this.posts,
      publicSpots: publicSpots ?? this.publicSpots,
      savedSpots: savedSpots ?? this.savedSpots,
      sharedWithMeSpots: sharedWithMeSpots ?? this.sharedWithMeSpots,
      isOwnProfile: isOwnProfile ?? this.isOwnProfile,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}

class ProfileScreenPhaseOneData {
  const ProfileScreenPhaseOneData({
    required this.data,
    required this.postIds,
  });

  final ProfileScreenData data;
  final List<String> postIds;
}

class PostLikeData {
  const PostLikeData({
    required this.likeCount,
    required this.isLiked,
  });

  final int likeCount;
  final bool isLiked;
}

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.profileId,
    required this.body,
    this.createdAt,
    this.displayName,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String postId;
  final String profileId;
  final String body;
  final DateTime? createdAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  factory PostComment.fromMap(Map<String, dynamic> map) {
    return PostComment(
      id: _parseString(map['id']) ?? '',
      postId: _parseString(map['post_id']) ?? '',
      profileId: _parseString(map['profile_id']) ?? '',
      body: _parseString(map['body']) ?? '',
      createdAt: _parseDateTime(map['created_at']),
      displayName: _parseString(map['display_name']),
      username: _parseString(map['username']),
      avatarUrl: _parseString(map['avatar_url']),
    );
  }

  String get authorLabel {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) {
      return display;
    }

    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle.startsWith('@') ? handle : '@$handle';
    }

    return profileId.length <= 8 ? profileId : profileId.substring(0, 8);
  }

  String get authorSecondaryLabel {
    final handle = username?.trim();
    if (handle != null &&
        handle.isNotEmpty &&
        authorLabel != (handle.startsWith('@') ? handle : '@$handle')) {
      return handle.startsWith('@') ? handle : '@$handle';
    }

    return '';
  }
}
