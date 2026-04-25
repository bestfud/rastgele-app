import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import 'app_icons.dart';
import 'app_ui.dart';
import 'score_ui.dart';

String _spotHeroTag(String spotId) => 'spot-card-hero:$spotId';

class SocialPostCard extends StatelessWidget {
  const SocialPostCard({
    super.key,
    required this.post,
    this.profileSurface = false,
    this.onLike,
    this.onTap,
    this.onOpenAuthor,
    this.onOpenComments,
    this.onOpenSpot,
    this.onOpenMap,
    this.onOpenLocation,
  });

  final SocialPost post;
  final bool profileSurface;
  final VoidCallback? onLike;
  final VoidCallback? onTap;
  final VoidCallback? onOpenAuthor;
  final VoidCallback? onOpenComments;
  final VoidCallback? onOpenSpot;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasImage = (post.imageUrl ?? '').isNotEmpty;
    final headline = _headlineFor(post);
    final summary = _summaryFor(post, headline: headline);
    final badgeAction = post.hasExactSpotAction
        ? onOpenSpot
        : (post.hasApproxLocationAction ? onOpenMap : null);
    final locationBadge = _LocationBadge(
      post: post,
      onTap: badgeAction,
    );
    final decisionTone = _DecisionTone.fromPost(post);
    final linkedScorePresentation = buildPostScorePresentation(post);
    final hasLinkedScore = post.linkedSpotScoreValue != null;
    final heroSpotId = (post.linkedFishingSpotId ?? '').trim();
    final horizontalPadding = profileSurface ? 16.0 : 18.0;
    final authorTopPadding = profileSurface ? 14.0 : 16.0;
    final contentBottomPadding = profileSurface ? 12.0 : 14.0;
    final contentTopPadding = profileSurface ? 14.0 : 16.0;
    final cardRadius = profileSurface ? 22.0 : AppRadii.card;
    final cardContent = Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: profileSurface ? 0.05 : 0.08),
            blurRadius: profileSurface ? 18 : 20,
            offset: Offset(0, profileSurface ? 8 : 10),
          ),
        ],
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: profileSurface ? 0.22 : 0.32,
            ),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  authorTopPadding,
                  horizontalPadding,
                  0,
                ),
                child: _AuthorHeader(
                  post: post,
                  compact: profileSurface,
                  onTap: onOpenAuthor,
                ),
              ),
              if (hasImage) ...[
                SizedBox(height: profileSurface ? 10 : 12),
                _PostImage(
                  imageUrl: post.imageUrl!,
                  compact: profileSurface,
                  locationBadge: post.showLocationBadge ? locationBadge : null,
                ),
              ],
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  contentTopPadding,
                  horizontalPadding,
                  contentBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: (profileSurface
                                    ? theme.textTheme.titleLarge
                                    : theme.textTheme.headlineSmall)
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: profileSurface ? 1.08 : 1.06,
                              letterSpacing: -0.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        hasLinkedScore
                            ? _LinkedSpotScoreBadge(
                                presentation: linkedScorePresentation,
                                compact: profileSurface,
                              )
                            : _DecisionBadge(
                                tone: decisionTone,
                                compact: profileSurface,
                              ),
                      ],
                    ),
                    SizedBox(height: profileSurface ? 8 : 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (post.authorSecondaryLabel.isNotEmpty)
                          Text(
                            post.authorSecondaryLabel,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: profileSurface ? 10.5 : null,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.82,
                              ),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.15,
                            ),
                          ),
                        Text(
                          _formatCreatedAt(post.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: profileSurface ? 10.5 : null,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.82,
                            ),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.15,
                          ),
                        ),
                        if (post.distanceKm != null)
                          Text(
                            '${post.distanceKm!.toStringAsFixed(1)} km',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: profileSurface ? 10.5 : null,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.82,
                              ),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.15,
                            ),
                          ),
                      ],
                    ),
                    if (!hasImage && post.showLocationBadge) ...[
                      SizedBox(height: profileSurface ? 8 : 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          locationBadge,
                        ],
                      ),
                    ],
                    if (summary != null) ...[
                      SizedBox(height: profileSurface ? 8 : 10),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.9,
                          ),
                          height: profileSurface ? 1.22 : 1.3,
                        ),
                      ),
                    ],
                    SizedBox(height: profileSurface ? 12 : 14),
                    Divider(
                      height: 1,
                      color: AppColors.border.withValues(
                        alpha: profileSurface ? 0.38 : 0.6,
                      ),
                    ),
                    SizedBox(height: profileSurface ? 8 : 10),
                    Row(
                      children: [
                        _AnimatedActionButton(
                          compact: profileSurface,
                          onTap: onLike,
                          backgroundColor: post.isLiked
                              ? AppColors.dangerSoft
                              : AppColors.background,
                          foregroundColor: post.isLiked
                              ? AppColors.danger
                              : AppColors.textSecondary,
                          icon: AppIcon(
                            AppGlyph.fish,
                            size: 16,
                            color: post.isLiked
                                ? AppColors.danger
                                : AppColors.textSecondary,
                          ),
                          label: 'Beğen',
                          count: '${post.likeCount}',
                        ),
                        const SizedBox(width: 10),
                        _AnimatedActionButton(
                          compact: profileSurface,
                          onTap: onOpenComments,
                          backgroundColor: AppColors.background,
                          foregroundColor: AppColors.textSecondary,
                          icon: const AppIcon(
                            AppGlyph.comment,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          label: 'Yorum',
                          count: '${post.commentCount}',
                        ),
                        const Spacer(),
                        if (post.hasLocationAction &&
                            post.locationActionLabel.isNotEmpty)
                          TextButton.icon(
                            onPressed: post.hasExactSpotAction
                                ? onOpenSpot
                                : (onOpenLocation ?? onOpenMap),
                            icon: const AppIcon(
                              AppGlyph.spot,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            label: Text(post.locationActionLabel),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                              textStyle: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: profileSurface ? 12.5 : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!post.hasExactSpotAction || heroSpotId.isEmpty) {
      return cardContent;
    }

    return Hero(
      tag: _spotHeroTag(heroSpotId),
      transitionOnUserGestures: true,
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        return Material(
          type: MaterialType.transparency,
          child: toHeroContext.widget,
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: cardContent,
      ),
    );
  }

  String _headlineFor(SocialPost post) {
    final linkedSpotName = (post.linkedFishingSpotName ?? '').trim();
    if (linkedSpotName.isNotEmpty) {
      return linkedSpotName;
    }

    final locationLabel = post.locationLabel.trim();
    if (locationLabel.isNotEmpty &&
        locationLabel != 'Yaklaşık konum' &&
        locationLabel != 'Gizli mera') {
      return locationLabel;
    }

    final caption = (post.caption ?? '').trim();
    if (caption.isNotEmpty) {
      return _truncateText(caption, maxLength: 54);
    }

    return 'Yeni paylaşım';
  }

  String? _summaryFor(SocialPost post, {required String headline}) {
    final caption = (post.caption ?? '').trim();
    if (caption.isEmpty) {
      return null;
    }

    if (caption == headline.trim()) {
      return null;
    }

    return _truncateText(caption, maxLength: 84);
  }

  String _truncateText(String text, {required int maxLength}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength - 1).trim()}...';
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Tarih yok';
    }

    return DateFormat('d MMM yyyy, HH:mm').format(createdAt.toLocal());
  }
}

class _AuthorHeader extends StatelessWidget {
  const _AuthorHeader({
    required this.post,
    this.compact = false,
    this.onTap,
  });

  final SocialPost post;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: compact ? 17 : 18,
            backgroundColor: AppColors.background,
            backgroundImage: (post.avatarUrl ?? '').isNotEmpty
                ? NetworkImage(post.avatarUrl!)
                : null,
            child: (post.avatarUrl ?? '').isEmpty
                ? Text(
                    _initialsFor(post.authorLabel),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          SizedBox(width: compact ? 9 : 10),
          Expanded(
            child: Text(
              post.authorLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: compact ? 15 : null,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initialsFor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'U';
    }

    final cleaned = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    return cleaned.substring(0, 1).toUpperCase();
  }
}

class _PostImage extends StatelessWidget {
  const _PostImage({
    required this.imageUrl,
    this.compact = false,
    this.locationBadge,
  });

  final String imageUrl;
  final bool compact;
  final Widget? locationBadge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      child: AspectRatio(
        aspectRatio: compact ? 4 / 2.8 : 4 / 3.15,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.background),
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) {
                  return child;
                }

                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  return child;
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: AppColors.background),
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                    child,
                  ],
                );
              },
              errorBuilder: (_, __, ___) {
                return Container(
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                );
              },
            ),
            if (locationBadge != null)
              Positioned(
                left: 10,
                bottom: 10,
                child: locationBadge!,
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedActionButton extends StatefulWidget {
  const _AnimatedActionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.backgroundColor,
    required this.foregroundColor,
    this.compact = false,
    this.onTap,
  });

  final Widget icon;
  final String label;
  final String count;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool compact;
  final VoidCallback? onTap;

  @override
  State<_AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<_AnimatedActionButton> {
  double _scale = 1;

  void _setScale(double value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _scale = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _setScale(0.95),
          onTapCancel: () => _setScale(1),
          onTapUp: (_) => _setScale(1),
          borderRadius: BorderRadius.circular(AppRadii.button),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 12,
              vertical: widget.compact ? 7 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.icon,
                SizedBox(width: widget.compact ? 5 : 6),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: widget.foregroundColor,
                        fontWeight: FontWeight.w600,
                        fontSize: widget.compact ? 12.5 : null,
                      ),
                ),
                SizedBox(width: widget.compact ? 5 : 6),
                Text(
                  widget.count,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: widget.foregroundColor,
                        fontWeight: FontWeight.w600,
                        fontSize: widget.compact ? 11 : null,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DecisionTone {
  const _DecisionTone({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  factory _DecisionTone.fromPost(SocialPost post) {
    if (post.hasExactSpotAction) {
      return const _DecisionTone(
        label: 'Şu an iyi',
        backgroundColor: AppColors.successSoft,
        foregroundColor: AppColors.success,
      );
    }

    if (post.hasApproxLocationAction) {
      return const _DecisionTone(
        label: 'Orta',
        backgroundColor: AppColors.warningSoft,
        foregroundColor: AppColors.warning,
      );
    }

    return const _DecisionTone(
      label: 'Zayıf',
      backgroundColor: AppColors.dangerSoft,
      foregroundColor: AppColors.danger,
    );
  }
}

class _DecisionBadge extends StatelessWidget {
  const _DecisionBadge({
    required this.tone,
    this.compact = false,
  });

  final _DecisionTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: tone.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tone.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone.foregroundColor,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : null,
            ),
      ),
    );
  }
}

class _LinkedSpotScoreBadge extends StatelessWidget {
  const _LinkedSpotScoreBadge({
    required this.presentation,
    this.compact = false,
  });

  final AppScorePresentation presentation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = presentation.style;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: style.border.withValues(alpha: compact ? 0.72 : 1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${presentation.value!}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: style.foreground,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 12.5 : null,
            ),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            presentation.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.foreground.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationBadge extends StatelessWidget {
  const _LocationBadge({
    required this.post,
    this.onTap,
  });

  final SocialPost post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibility = post.visibility?.toLowerCase();

    Color backgroundColor;
    Color foregroundColor;
    AppGlyph glyph;

    switch (visibility) {
      case 'exact':
        backgroundColor = AppColors.success.withValues(alpha: 0.92);
        foregroundColor = Colors.white;
        glyph = AppGlyph.exact;
        break;
      case 'approx':
        backgroundColor = AppColors.warning.withValues(alpha: 0.96);
        foregroundColor = Colors.white;
        glyph = AppGlyph.approx;
        break;
      case 'private':
      default:
        backgroundColor = AppColors.textSecondary.withValues(alpha: 0.85);
        foregroundColor = Colors.white;
        glyph = AppGlyph.private;
        break;
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                glyph,
                size: 14,
                color: foregroundColor,
              ),
              const SizedBox(width: 5),
              Text(
                post.locationLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
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
