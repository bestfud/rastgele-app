import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import 'app_ui.dart';
import 'score_ui.dart';

class SpotCard extends StatelessWidget {
  const SpotCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onSharerTap,
    this.currentProfileId,
    this.distanceLabel,
    this.isBestSpot = false,
    this.onToggleSaved,
    this.showSaveAction = true,
    this.compact = false,
  });

  final SpotFeedItem item;
  final VoidCallback onTap;
  final VoidCallback? onSharerTap;
  final String? currentProfileId;
  final String? distanceLabel;
  final bool isBestSpot;
  final VoidCallback? onToggleSaved;
  final bool showSaveAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scorePresentation = buildScorePresentation(
      score: item.score,
      weatherSnapshot: item.weatherSnapshot,
    );
    final authorName = _authorDisplayName();
    final authorTime = _relativeSharedTime();
    final compactMetaLine = compact ? _compactMetaLine() : null;
    final metaParts = <String>[
      if ((item.spot.waterType ?? '').isNotEmpty)
        localizedWaterTypeLabel(item.spot.waterType),
      if (distanceLabel != null && distanceLabel!.trim().isNotEmpty)
        distanceLabel!.trim(),
    ];
    final insights = _buildInsightTags(item).take(3).toList(growable: false);
    final canSave = showSaveAction &&
        onToggleSaved != null &&
        !item.spot.isOwnedByProfile(currentProfileId);
    final signalLabel =
        _signalLabel(item.score?.scoreValue, isBestSpot: isBestSpot);
    final sharerIdentity = item.sharerIdentity;
    final insightLine = compact ? _feedDecisionLabel(item) : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 22 : AppRadii.card),
        boxShadow: compact
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.045),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                  spreadRadius: -20,
                ),
                BoxShadow(
                  color: colorScheme.onSurface.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                  spreadRadius: -18,
                ),
              ]
            : appSoftShadow(colorScheme.primary),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: compact
            ? colorScheme.surface.withValues(alpha: 0.985)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 22 : AppRadii.card),
          side: BorderSide(
            color: compact
                ? colorScheme.outlineVariant.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 13 : 14,
              compact ? 10 : 14,
              compact ? 13 : 14,
              compact ? 12 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  _CompactUserRow(
                    primaryLabel: authorName,
                    secondaryLabel: _compactSharedTime(authorTime),
                    avatarUrl:
                        sharerIdentity?.avatarUrl ?? item.sharedByAvatarUrl,
                  )
                else if (sharerIdentity != null && onSharerTap != null)
                  Row(
                    children: [
                      Expanded(
                        child: _SharerRow(
                          primaryLabel: authorName,
                          secondaryLabel: authorTime,
                          avatarUrl: sharerIdentity.avatarUrl,
                          onTap: onSharerTap!,
                          compact: compact,
                        ),
                      ),
                      if (!compact && signalLabel != null) ...[
                        SizedBox(width: compact ? 6 : 8),
                        _SignalPill(
                          label: signalLabel,
                          compact: compact,
                          subdued: isBestSpot,
                        ),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      _AuthorAvatar(
                        imageUrl: item.sharedByAvatarUrl,
                        fallbackLabel: authorName,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                            ),
                            if (authorTime != null)
                              Text(
                                authorTime,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!compact && signalLabel != null)
                        _SignalPill(
                          label: signalLabel,
                          compact: compact,
                          subdued: isBestSpot,
                        ),
                    ],
                  ),
                SizedBox(height: compact ? 9 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.spot.name,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: (compact
                                      ? theme.textTheme.titleMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(
                                fontWeight:
                                    compact ? FontWeight.w700 : FontWeight.w800,
                                fontSize: compact ? 16 : 20,
                                height: 1.12,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: EdgeInsets.only(top: compact ? 0 : 2),
                            child: _SpotScoreBadge(
                              presentation: scorePresentation,
                              compact: compact,
                            ),
                          ),
                        ],
                      ),
                      if (compact && insightLine != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          insightLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.15,
                            height: 1.1,
                          ),
                        ),
                      ],
                      if ((compact
                          ? compactMetaLine != null
                          : metaParts.isNotEmpty)) ...[
                        SizedBox(height: compact ? 5 : 8),
                        Text(
                          compact ? compactMetaLine! : metaParts.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.82),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ] else if (!compact && insights.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final insight in insights)
                              _InsightChip(label: insight, compact: false),
                          ],
                        ),
                      ],
                      if (compact) ...[
                        const SizedBox(height: 10),
                        _CompactSpotMapPreview(
                          latitude: item.spot.latitude,
                          longitude: item.spot.longitude,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: AppColors.border.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onTap,
                        icon: const Icon(
                          Icons.map_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: const Text('Haritada aç'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (canSave)
                        _SaveChipButton(
                          isSaved: item.isSaved,
                          onPressed: onToggleSaved,
                          compact: false,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _compactSharedTime(String? fallback) {
    final sharedAt = item.sharedAt;
    if (sharedAt == null) {
      return fallback;
    }

    final difference = DateTime.now().difference(sharedAt.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'şimdi';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}dk';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}s';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}g';
    }
    final weeks = (difference.inDays / 7).floor();
    if (weeks < 5) {
      return '${weeks}hf';
    }
    final months = (difference.inDays / 30).floor();
    if (months < 12) {
      return '${months}ay';
    }
    final years = (difference.inDays / 365).floor();
    return '${years}y';
  }

  String _feedDecisionLabel(SpotFeedItem item) {
    final scoreValue = item.score?.scoreValue;
    if (scoreValue == null) {
      return 'Değerlendir';
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

  String? _compactMetaLine() {
    final weather = item.weatherSnapshot;
    final weatherState = weather == null ? null : _compactWeatherState(weather);
    final parts = <String>[
      if (distanceLabel != null && distanceLabel!.trim().isNotEmpty)
        distanceLabel!.trim(),
      if (weather?.airTemperature != null)
        '${weather!.airTemperature!.round()}°',
      if (weatherState != null) weatherState,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' • ');
  }

  String? _compactWeatherState(WeatherSnapshot weather) {
    final precipitation = weather.precipitation;
    if (precipitation != null) {
      if (precipitation <= 0.2) {
        return 'Yağış yok';
      }
      if (precipitation <= 1.5) {
        return 'Hafif yağış';
      }
      return 'Yağışlı';
    }

    final windSpeed = weather.windSpeed;
    if (windSpeed != null) {
      if (windSpeed <= 10) {
        return 'Hafif rüzgar';
      }
      if (windSpeed <= 22) {
        return 'Orta rüzgar';
      }
      return 'Sert rüzgar';
    }

    return null;
  }

  String _authorDisplayName() {
    if ((currentProfileId ?? '').isNotEmpty &&
        item.sharedByProfileId == currentProfileId) {
      return 'Sen';
    }

    final displayName = item.sharedByDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final username = item.sharedByUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username.startsWith('@') ? username : '@$username';
    }

    return 'Paylaşan bilinmiyor';
  }

  String? _relativeSharedTime() {
    final sharedAt = item.sharedAt;
    if (sharedAt == null) {
      return null;
    }

    final difference = DateTime.now().difference(sharedAt.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Az önce';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dk önce';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    }
    final weeks = (difference.inDays / 7).floor();
    if (weeks < 5) {
      return '$weeks hf önce';
    }
    final months = (difference.inDays / 30).floor();
    if (months < 12) {
      return '$months ay önce';
    }
    final years = (difference.inDays / 365).floor();
    return '$years yıl önce';
  }

  List<String> _buildInsightTags(SpotFeedItem item) {
    final tags = <String>[];
    final factors = item.score?.scoreFactors;
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
      tags.add('Basınç $pressure');
    }
    if (wind != null) {
      tags.add('Rüzgar $wind');
    }
    if (rain != null) {
      tags.add('Yağış $rain');
    }

    if (tags.isEmpty) {
      final weather = item.weatherSnapshot;
      if (weather?.pressure != null) {
        tags.add('Basınç ${weather!.pressure!.toStringAsFixed(0)}');
      }
      if (weather?.windSpeed != null) {
        tags.add('Rüzgar ${weather!.windSpeed!.toStringAsFixed(1)}');
      }
      if (weather?.precipitation != null) {
        tags.add('Yağış ${weather!.precipitation!.toStringAsFixed(1)}');
      }
    }

    return tags;
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
      if (normalizedValue == null) {
        continue;
      }
      return normalizedValue;
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

  String? _signalLabel(int? scoreValue, {required bool isBestSpot}) {
    if (isBestSpot) {
      return 'En iyi nokta';
    }
    if (scoreValue == null) {
      return null;
    }
    if (scoreValue >= 72) {
      return 'Bugün iyi';
    }
    if (scoreValue >= 58) {
      return 'Şu an uygun';
    }
    return null;
  }
}

class _CompactUserRow extends StatelessWidget {
  const _CompactUserRow({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.avatarUrl,
  });

  final String primaryLabel;
  final String? secondaryLabel;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        _AuthorAvatar(
          imageUrl: avatarUrl,
          fallbackLabel: primaryLabel,
          radius: 14,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  primaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(width: 6),
                Text(
                  secondaryLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SharerRow extends StatelessWidget {
  const _SharerRow({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.avatarUrl,
    required this.onTap,
    this.compact = false,
  });

  final String primaryLabel;
  final String? secondaryLabel;
  final String? avatarUrl;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 2,
            vertical: compact ? 1 : 2,
          ),
          child: Row(
            children: [
              _AuthorAvatar(
                imageUrl: avatarUrl,
                fallbackLabel: primaryLabel,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12.5 : null,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (secondaryLabel != null)
                      Text(
                        secondaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.78),
                          fontWeight: FontWeight.w500,
                          fontSize: compact ? 10.5 : null,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: compact ? 16 : 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({
    required this.label,
    this.compact = false,
    this.subdued = false,
  });

  final String label;
  final bool compact;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: subdued
            ? AppColors.primarySoft.withValues(alpha: compact ? 0.45 : 0.58)
            : AppColors.primarySoft.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: subdued
              ? AppColors.primary.withValues(alpha: 0.8)
              : AppColors.primary,
          fontWeight: subdued ? FontWeight.w600 : FontWeight.w700,
          fontSize: compact ? 10.5 : null,
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    this.radius = 16,
  });

  final String? imageUrl;
  final String fallbackLabel;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmedImageUrl = imageUrl?.trim();

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primarySoft,
      backgroundImage: trimmedImageUrl != null && trimmedImageUrl.isNotEmpty
          ? NetworkImage(trimmedImageUrl)
          : null,
      child: (trimmedImageUrl == null || trimmedImageUrl.isEmpty)
          ? Text(
              _initialsFromLabel(fallbackLabel),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            )
          : null,
    );
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
}

class _SpotScoreBadge extends StatelessWidget {
  const _SpotScoreBadge({
    required this.presentation,
    this.compact = false,
  });

  final AppScorePresentation presentation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        compact ? _compactScoreStyleFor(presentation) : presentation.style;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 9,
        vertical: compact ? 5 : 5,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: compact ? style.border.withValues(alpha: 0.55) : style.border,
        ),
        boxShadow: [
          BoxShadow(
            color: style.shadow,
            blurRadius: compact ? 14 : 10,
            offset: const Offset(0, 4),
            spreadRadius: compact ? -8 : -7,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact)
            Text(
              presentation.value?.toString() ?? '...',
              style: theme.textTheme.labelMedium?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: -0.1,
              ),
            )
          else ...[
            if (presentation.value != null) ...[
              Text(
                '${presentation.value!}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              presentation.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: style.foreground.withValues(alpha: 0.88),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  AppScoreStyle _compactScoreStyleFor(AppScorePresentation presentation) {
    final value = presentation.value;
    if (value == null) {
      return const AppScoreStyle(
        background: Color(0xFFF1F4F7),
        foreground: Color(0xFF52606D),
        border: Color(0xFFDCE4EA),
        shadow: Color(0x1052606D),
      );
    }

    if (value >= 80) {
      return const AppScoreStyle(
        background: Color(0xFFE8F4EC),
        foreground: Color(0xFF236145),
        border: Color(0xFFCFE5D7),
        shadow: Color(0x142F6A4C),
      );
    }

    if (value >= 60) {
      return const AppScoreStyle(
        background: Color(0xFFFFF4DE),
        foreground: Color(0xFF8B6724),
        border: Color(0xFFF0E1B8),
        shadow: Color(0x12A37C2C),
      );
    }

    return const AppScoreStyle(
      background: Color(0xFFF8E8E6),
      foreground: Color(0xFF97493F),
      border: Color(0xFFEACBC6),
      shadow: Color(0x12A24B42),
    );
  }
}

class _CompactSpotMapPreview extends StatelessWidget {
  const _CompactSpotMapPreview({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 84,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 13.4,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.fishing_app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.22),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.place_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.0),
                    theme.colorScheme.surface.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SaveChipButton extends StatelessWidget {
  const _SaveChipButton({
    required this.isSaved,
    this.onPressed,
    this.compact = false,
  });

  final bool isSaved;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor =
        isSaved ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: isSaved ? AppColors.primarySoft : AppColors.background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 10,
            vertical: compact ? 5 : 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSaved
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 15,
                color: foregroundColor,
              ),
              const SizedBox(width: 5),
              Text(
                isSaved ? 'Kaydedildi' : 'Kaydet',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 11 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
