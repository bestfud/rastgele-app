import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import 'post_location_preview_screen.dart';
import 'spot_detail_screen.dart';
import '../widgets/social_post_card.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.repository,
    required this.post,
  });

  final SpotRepository repository;
  final SocialPost post;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  late SocialPost _post;
  final Stopwatch _openStopwatch = Stopwatch();

  List<PostComment>? _comments;
  bool _isLoadingComments = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  Object? _commentsError;
  bool _didLogMeaningfulPaint = false;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    perfLog('Post Detail open start postId=${widget.post.id}');
    perfLogFrame('Post Detail', _openStopwatch);
    _post = widget.post;
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoadingComments = true;
      _commentsError = null;
    });

    try {
      final comments =
          await widget.repository.fetchCommentsForPost(widget.post.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _comments = comments;
      });
      perfLog(
        'Post Detail comments load complete in ${_openStopwatch.elapsedMilliseconds}ms comments=${comments.length}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _commentsError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
      }
      if (_openStopwatch.isRunning) {
        _openStopwatch.stop();
        perfLog(
            'post detail open took ${_openStopwatch.elapsedMilliseconds}ms');
      }
    }
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final comment = await widget.repository.createComment(
        postId: widget.post.id,
        body: body,
      );

      _commentController.clear();
      if (!mounted) {
        return;
      }

      setState(() {
        _comments = [...?_comments, comment];
        _post = _post.copyWith(commentCount: _post.commentCount + 1);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Yorum gönderilemedi: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openLocation() async {
    if (widget.post.hasExactSpotAction &&
        (widget.post.linkedSpotId ?? '').isNotEmpty) {
      debugPrint(
        '[SPOT_NAV] tap source=post_detail postId=${widget.post.id} passedSpotId=${widget.post.linkedSpotId!} linkedSpotId=${widget.post.linkedSpotId ?? 'null'} linkedFishingSpotId=${widget.post.linkedFishingSpotId ?? 'null'} itemSpotId=null visibility=${widget.post.visibilityValue}',
      );
      try {
        await widget.repository.fetchSpotDetail(widget.post.linkedSpotId!);
        if (!mounted) {
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SpotDetailScreen(
              repository: widget.repository,
              spotId: widget.post.linkedSpotId!,
            ),
          ),
        );
      } catch (error) {
        debugPrint(
          '[SPOT_NAV] failure source=post_detail postId=${widget.post.id} passedSpotId=${widget.post.linkedSpotId!} error=$error',
        );
        if (!mounted) {
          return;
        }

        if (widget.post.latitude != null && widget.post.longitude != null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PostLocationPreviewScreen(post: widget.post),
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

    if (widget.post.hasApproxLocationAction &&
        widget.post.latitude != null &&
        widget.post.longitude != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostLocationPreviewScreen(post: widget.post),
        ),
      );
      return;
    }

    if (widget.post.hasApproxLocationAction &&
        (widget.post.region ?? '').isNotEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.post.region!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_didLogMeaningfulPaint) {
      _didLogMeaningfulPaint = true;
      perfLog(
          'Post Detail structure ready at ${_openStopwatch.elapsedMilliseconds}ms');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paylaşım')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SocialPostCard(
                post: _post,
                onOpenSpot: _post.hasExactSpotAction ? _openLocation : null,
                onOpenMap: _post.hasApproxLocationAction ? _openLocation : null,
                onOpenLocation: _post.hasLocationAction ? _openLocation : null,
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  boxShadow: appSoftShadow(theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yorumlar',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Düşünceni ekle ve sohbete katıl.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadii.input),
                          ),
                          child: TextField(
                            controller: _commentController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Bir yorum yaz',
                              filled: false,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(16, 14, 8, 14),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: IconButton(
                                  onPressed:
                                      _isSubmitting ? null : _submitComment,
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.send_rounded),
                                  tooltip: 'Gönder',
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_isLoadingComments)
                const _CommentSkeletonList()
              else if (_commentsError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Yorumlar yüklenemedi: $_commentsError'),
                  ),
                )
              else if ((_comments ?? const <PostComment>[]).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: AppEmptyState(
                    iconWidget: AppIcon(
                      AppGlyph.comment,
                      size: 24,
                      color: AppColors.textSecondary,
                    ),
                    message: 'Henüz yorum yok. İlk yorumu sen yaz.',
                  ),
                )
              else
                Column(
                  children: (_comments ?? const <PostComment>[])
                      .map(
                        (comment) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CommentCard(comment: comment),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentSkeletonList extends StatelessWidget {
  const _CommentSkeletonList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppSkeletonCard(
            child: _CommentSkeleton(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppSkeletonCard(
            child: _CommentSkeleton(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppSkeletonCard(
            child: _CommentSkeleton(),
          ),
        ),
      ],
    );
  }
}

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppSkeletonBox(height: 36, width: 36, radius: 18),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonBox(height: 14, width: 100, radius: 10),
                  SizedBox(height: 8),
                  AppSkeletonBox(height: 12, width: 70, radius: 10),
                ],
              ),
            ),
            AppSkeletonBox(height: 12, width: 56, radius: 10),
          ],
        ),
        SizedBox(height: 14),
        AppSkeletonBox(height: 12, radius: 10),
        SizedBox(height: 8),
        AppSkeletonBox(height: 12, width: 180, radius: 10),
      ],
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
  });

  final PostComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: (comment.avatarUrl ?? '').isNotEmpty
                      ? NetworkImage(comment.avatarUrl!)
                      : null,
                  child: (comment.avatarUrl ?? '').isEmpty
                      ? Text(_initialsFor(comment.authorLabel))
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.authorLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (comment.authorSecondaryLabel.isNotEmpty)
                        Text(
                          comment.authorSecondaryLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatCreatedAt(comment.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              comment.body,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Tarih yok';
    }

    return DateFormat('d MMM yyyy, HH:mm').format(createdAt.toLocal());
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
