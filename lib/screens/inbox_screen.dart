import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.repository,
  });

  final SpotRepository repository;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final Stopwatch _openStopwatch = Stopwatch()..start();
  List<UserConversation> _conversations = const [];
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _isPolling = false;
  bool _isAppResumed = true;
  bool _hasLoggedOpenTotal = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    unawaited(_refreshInbox(reason: 'init'));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _refreshInbox({required String reason}) async {
    final isSilentPoll = reason == 'poll';
    if (isSilentPoll && (!_isAppResumed || _isPolling)) {
      return;
    }
    if (isSilentPoll) {
      _isPolling = true;
    }
    if (mounted) {
      setState(() {
        _isLoading = !isSilentPoll;
        _loadError = null;
      });
    }

    try {
      final conversations =
          await widget.repository.fetchUserConversationsWithMeta(
        currentProfileId: widget.repository.currentProfileIdHint,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
      if (!isSilentPoll) {
        _startPolling();
        _logOpenTotal();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
      if (!isSilentPoll) {
        _logOpenTotal();
      }
    } finally {
      if (isSilentPoll) {
        _isPolling = false;
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_refreshInbox(reason: 'poll')),
    );
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _InboxLifecycleObserver(
    onStateChanged: (state) {
      _isAppResumed = state == AppLifecycleState.resumed;
    },
  );

  Future<void> _openConversation(UserConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          repository: widget.repository,
          conversationId: conversation.id,
          otherProfile: conversation.otherProfile,
          currentProfileId: widget.repository.currentProfileIdHint,
        ),
      ),
    );
    unawaited(_refreshInbox(reason: 'chat_return'));
  }

  void _logOpenTotal() {
    if (_hasLoggedOpenTotal) {
      return;
    }
    _hasLoggedOpenTotal = true;
    perfLog('[perf] inbox open total ${_openStopwatch.elapsedMilliseconds}ms');
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.background,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120 + ((index % 3) * 36),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return '';
    }

    final local = value.toLocal();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfTarget = DateTime(local.year, local.month, local.day);
    if (startOfTarget == startOfToday) {
      return DateFormat('HH:mm').format(local);
    }
    if (now.year == local.year) {
      return DateFormat('d MMM').format(local);
    }
    return DateFormat('d MMM yyyy').format(local);
  }

  Color _rowBackgroundColor(BuildContext context, bool hasUnread) {
    final theme = Theme.of(context);
    return hasUnread
        ? AppColors.primarySoft.withValues(alpha: 0.48)
        : theme.colorScheme.surface;
  }

  String _lastMessageLabel(UserConversation conversation) {
    final text = conversation.lastMessageText?.trim();
    if (text == null || text.isEmpty) {
      return 'Henüz mesaj yok.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesajlar'),
      ),
      body: _isLoading && _conversations.isEmpty
          ? _buildLoadingPlaceholder(context)
          : _loadError != null && _conversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Mesajlar yüklenemedi: $_loadError'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _refreshInbox(reason: 'pull_to_refresh'),
                  child: _conversations.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
                          children: const [
                            AppEmptyState(
                              iconWidget: Icon(
                                Icons.mail_outline_rounded,
                                size: 26,
                                color: AppColors.textSecondary,
                              ),
                              message: 'Henüz konuşman yok.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            final hasUnread = conversation.unreadCount > 0;
                            final timeLabel =
                                _formatTimestamp(conversation.lastMessageAt);
                            return Card(
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              color: _rowBackgroundColor(context, hasUnread),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                                side: BorderSide(
                                  color: hasUnread
                                      ? AppColors.primary.withValues(
                                          alpha: 0.24,
                                        )
                                      : theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.card),
                                onTap: () => _openConversation(conversation),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    13,
                                    14,
                                    13,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundColor: hasUnread
                                                ? AppColors.primarySoft
                                                : AppColors.background,
                                            backgroundImage: (conversation
                                                            .otherProfile
                                                            .avatarUrl ??
                                                        '')
                                                    .isNotEmpty
                                                ? NetworkImage(
                                                    conversation.otherProfile
                                                        .avatarUrl!,
                                                  )
                                                : null,
                                            child: (conversation.otherProfile
                                                            .avatarUrl ??
                                                        '')
                                                    .isEmpty
                                                ? Text(
                                                    conversation
                                                        .otherProfile.initials,
                                                    style: theme
                                                        .textTheme.labelLarge
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: hasUnread
                                                          ? AppColors.primary
                                                          : AppColors
                                                              .textSecondary,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          if (hasUnread)
                                            Positioned(
                                              right: -1,
                                              top: -1,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: theme
                                                        .colorScheme.surface,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    conversation.otherProfile
                                                        .displayName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.titleSmall
                                                        ?.copyWith(
                                                      fontWeight: hasUnread
                                                          ? FontWeight.w800
                                                          : FontWeight.w700,
                                                      letterSpacing: -0.1,
                                                    ),
                                                  ),
                                                ),
                                                if (timeLabel.isNotEmpty) ...[
                                                  const SizedBox(width: 10),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 1,
                                                    ),
                                                    child: Text(
                                                      timeLabel,
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: hasUnread
                                                            ? AppColors.primary
                                                            : theme.colorScheme
                                                                .onSurfaceVariant,
                                                        fontWeight: hasUnread
                                                            ? FontWeight.w700
                                                            : FontWeight.w600,
                                                        letterSpacing: 0.15,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 7),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _lastMessageLabel(
                                                      conversation,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodyMedium
                                                        ?.copyWith(
                                                      color: hasUnread
                                                          ? theme.colorScheme
                                                              .onSurface
                                                          : theme.colorScheme
                                                              .onSurfaceVariant,
                                                      fontWeight: hasUnread
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                      height: 1.33,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                hasUnread
                                                    ? _UnreadBadge(
                                                        count: conversation
                                                            .unreadCount,
                                                      )
                                                    : Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: theme
                                                              .colorScheme
                                                              .outlineVariant
                                                              .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                          shape:
                                                              BoxShape.circle,
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
                          },
                        ),
                ),
    );
  }
}

class _InboxLifecycleObserver with WidgetsBindingObserver {
  _InboxLifecycleObserver({
    required this.onStateChanged,
  });

  final ValueChanged<AppLifecycleState> onStateChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 6),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0.1,
              ),
        ),
      ),
    );
  }
}
