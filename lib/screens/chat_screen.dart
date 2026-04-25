import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.repository,
    required this.otherProfile,
    this.conversationId,
    this.pendingConversationId,
    this.currentProfileId,
  }) : assert(
          (conversationId != null && conversationId != '') ||
              pendingConversationId != null,
          'ChatScreen requires a conversation id or a pending conversation future.',
        );

  final SpotRepository repository;
  final String? conversationId;
  final Future<String>? pendingConversationId;
  final String? currentProfileId;
  final AppProfile otherProfile;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Stopwatch _openStopwatch = Stopwatch()..start();

  Timer? _pollTimer;
  List<DirectMessage> _serverMessages = const [];
  List<_PendingOutgoingMessage> _pendingMessages = const [];
  String _conversationId = '';
  String _currentProfileId = '';
  bool _isLoading = true;
  bool _isPolling = false;
  bool _isAppResumed = true;
  bool _hasLoggedOpenTotal = false;
  bool _isMarkingConversationAsRead = false;
  Object? _loadError;

  List<DirectMessage> get _messages {
    if (_pendingMessages.isEmpty) {
      return _serverMessages;
    }

    final pendingIds =
        _pendingMessages.map((message) => message.localId).toSet();
    final merged = <DirectMessage>[
      ..._serverMessages.where((message) => !pendingIds.contains(message.id)),
      ..._pendingMessages.map((message) => message.asDirectMessage()),
    ];
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(merged);
  }

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId?.trim() ?? '';
    _currentProfileId = widget.currentProfileId?.trim() ?? '';
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _ChatLifecycleObserver(onStateChanged: _handleLifecycleChange);

  void _handleLifecycleChange(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
  }

  Future<void> _initialize() async {
    try {
      final results = await Future.wait<dynamic>([
        _resolveConversationId(),
        _resolveCurrentProfileId(),
      ]);
      if (!mounted) {
        return;
      }

      setState(() {
        _conversationId = results[0] as String;
        _currentProfileId = results[1] as String;
      });

      await _refreshMessages(scrollToBottom: true, silent: false);
      _startPolling();
      _logOpenTotal();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = error;
      });
      _logOpenTotal();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sohbet yüklenemedi: $error')),
      );
    }
  }

  Future<String> _resolveConversationId() async {
    final knownConversationId = _conversationId.trim();
    if (knownConversationId.isNotEmpty) {
      return knownConversationId;
    }

    final conversationId = await widget.pendingConversationId!;
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty) {
      throw Exception('Konuşma bulunamadı.');
    }
    return normalizedConversationId;
  }

  Future<String> _resolveCurrentProfileId() async {
    final knownProfileId = _currentProfileId.trim();
    if (knownProfileId.isNotEmpty) {
      return knownProfileId;
    }

    final currentProfile = await widget.repository.fetchCurrentProfile();
    return currentProfile.id.trim();
  }

  Future<void> _refreshMessages({
    bool scrollToBottom = false,
    bool silent = false,
  }) async {
    final normalizedConversationId = _conversationId.trim();
    if (normalizedConversationId.isEmpty) {
      return;
    }
    if (silent && (!_isAppResumed || _isPolling)) {
      return;
    }
    if (silent) {
      _isPolling = true;
    }
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final messages = await widget.repository.fetchMessages(
        normalizedConversationId,
        currentProfileId: _currentProfileId,
      );
      if (!mounted) {
        return;
      }

      final previousCount = _messages.length;
      final hasUnreadIncoming = messages.any(
        (message) =>
            message.senderId != _currentProfileId && message.readAt == null,
      );
      final shouldStickToBottom =
          scrollToBottom || _isNearBottom() || previousCount == 0;

      setState(() {
        _serverMessages = messages;
        _isLoading = false;
        _loadError = null;
      });

      if (hasUnreadIncoming) {
        _scheduleMarkConversationAsRead();
      }
      if (messages.isNotEmpty &&
          (scrollToBottom ||
              (messages.length > previousCount && shouldStickToBottom))) {
        _scrollToBottom();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = error;
      });
    } finally {
      if (silent) {
        _isPolling = false;
      }
    }
  }

  void _scheduleMarkConversationAsRead() {
    if (_isMarkingConversationAsRead) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isMarkingConversationAsRead) {
        return;
      }
      unawaited(_markConversationAsRead());
    });
  }

  Future<void> _markConversationAsRead() async {
    final normalizedConversationId = _conversationId.trim();
    if (normalizedConversationId.isEmpty) {
      return;
    }

    _isMarkingConversationAsRead = true;
    try {
      await widget.repository.markConversationAsRead(
        normalizedConversationId,
        currentProfileId: _currentProfileId,
      );
    } catch (_) {
    } finally {
      _isMarkingConversationAsRead = false;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshMessages(silent: true)),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || _messages.isEmpty) {
        return;
      }

      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        return;
      }

      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return true;
    }
    return (position.maxScrollExtent - position.pixels).abs() < 80;
  }

  Future<void> _send() async {
    if (_conversationId.trim().isEmpty) {
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final tempMessage = _PendingOutgoingMessage.sending(
      localId: 'local:${DateTime.now().microsecondsSinceEpoch}',
      conversationId: _conversationId,
      senderId: _currentProfileId,
      text: text,
      createdAt: DateTime.now(),
    );

    _messageController.clear();
    setState(() {
      _pendingMessages = [..._pendingMessages, tempMessage];
    });
    _scrollToBottom();

    try {
      final insertedMessage = await widget.repository.sendMessage(
        _conversationId,
        text,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingMessages = _pendingMessages
            .where((message) => message.localId != tempMessage.localId)
            .toList(growable: false);
        if (!_serverMessages
            .any((message) => message.id == insertedMessage.id)) {
          _serverMessages = [..._serverMessages, insertedMessage]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      });
      _scrollToBottom();
      unawaited(_postSendRefresh());
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingMessages = _pendingMessages
            .map(
              (message) => message.localId == tempMessage.localId
                  ? message.asFailed()
                  : message,
            )
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $error')),
      );
    }
  }

  Future<void> _postSendRefresh() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _refreshMessages(scrollToBottom: false, silent: true);
    } finally {
      stopwatch.stop();
      perfLog('[perf] post-send refresh ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  bool _isSameSender(DirectMessage? a, DirectMessage? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.senderId == b.senderId;
  }

  bool _shouldShowSeenIndicator({
    required DirectMessage message,
    required int index,
  }) {
    final isLastMessage = index == _messages.length - 1;
    final isMine = message.senderId == _currentProfileId;
    final isRead = message.readAt != null;
    return isLastMessage && isMine && isRead;
  }

  _PendingOutgoingMessage? _pendingMessageFor(DirectMessage message) {
    for (final pendingMessage in _pendingMessages) {
      if (pendingMessage.localId == message.id) {
        return pendingMessage;
      }
    }
    return null;
  }

  void _logOpenTotal() {
    if (_hasLoggedOpenTotal) {
      return;
    }
    _hasLoggedOpenTotal = true;
    perfLog('[perf] chat open total ${_openStopwatch.elapsedMilliseconds}ms');
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final isMine = index.isOdd;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: MediaQuery.sizeOf(context).width * (isMine ? 0.48 : 0.62),
            height: 18 + ((index % 3) * 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewport(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading && _messages.isEmpty) {
      return _buildLoadingPlaceholder(context);
    }

    if (_messages.isEmpty) {
      final text = _loadError == null
          ? 'Henüz mesaj yok. İlk mesajı sen gönder.'
          : 'Mesajlar şu anda yüklenemedi. Yine de ilk mesajı gönderebilirsin.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final pendingMessage = _pendingMessageFor(message);
        final isMine = message.senderId == _currentProfileId;
        final previous = index > 0 ? _messages[index - 1] : null;
        final next = index + 1 < _messages.length ? _messages[index + 1] : null;
        final showsSeenIndicator = _shouldShowSeenIndicator(
          message: message,
          index: index,
        );
        final continuesFromPrevious = _isSameSender(previous, message);
        final continuesToNext = _isSameSender(message, next);
        final topSpacing = continuesFromPrevious ? 3.0 : 12.0;
        final bottomSpacing =
            showsSeenIndicator ? 14.0 : (continuesToNext ? 3.0 : 10.0);
        final bubbleRadius = BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(
            isMine ? 22 : (continuesToNext ? 8 : 22),
          ),
          bottomRight: Radius.circular(
            isMine ? (continuesToNext ? 8 : 22) : 22,
          ),
        );
        final bubbleColor =
            isMine ? AppColors.primary : theme.colorScheme.surfaceContainerLow;
        final bubbleBorderColor = isMine
            ? AppColors.primary.withValues(alpha: 0.18)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
        final textColor = isMine ? Colors.white : theme.colorScheme.onSurface;
        final timeColor = isMine
            ? Colors.white.withValues(alpha: 0.72)
            : theme.colorScheme.onSurfaceVariant;
        final pendingStatusLabel = switch (pendingMessage?.status) {
          _PendingOutgoingStatus.sending => 'Gönderiliyor',
          _PendingOutgoingStatus.failed => 'Gönderilemedi',
          null => null,
        };
        final pendingStatusColor =
            pendingMessage?.status == _PendingOutgoingStatus.failed
                ? (isMine
                    ? Colors.white.withValues(alpha: 0.9)
                    : theme.colorScheme.error)
                : (isMine
                    ? Colors.white.withValues(alpha: 0.78)
                    : theme.colorScheme.onSurfaceVariant);

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.76,
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: bubbleRadius,
                    border: Border.all(color: bubbleBorderColor),
                    boxShadow: isMine
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                              spreadRadius: -14,
                            ),
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            height: 1.38,
                            fontWeight:
                                isMine ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatTime(message.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: timeColor,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                        if (pendingStatusLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            pendingStatusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: pendingStatusColor,
                              fontWeight: FontWeight.w500,
                              fontStyle: pendingMessage?.status ==
                                      _PendingOutgoingStatus.sending
                                  ? FontStyle.italic
                                  : null,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showsSeenIndicator) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Görüldü',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final isConversationReady = _conversationId.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: TextField(
                  controller: _messageController,
                  enabled: isConversationReady,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: isConversationReady
                        ? 'Mesaj yaz...'
                        : 'Sohbet hazırlanıyor...',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 46,
              height: 46,
              child: FilledButton(
                onPressed: !isConversationReady ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  elevation: 0,
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.otherProfile.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _buildViewport(context),
            ),
            _buildComposer(),
          ],
        ),
      ),
    );
  }
}

class _ChatLifecycleObserver with WidgetsBindingObserver {
  _ChatLifecycleObserver({
    required this.onStateChanged,
  });

  final ValueChanged<AppLifecycleState> onStateChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}

enum _PendingOutgoingStatus { sending, failed }

class _PendingOutgoingMessage {
  const _PendingOutgoingMessage({
    required this.localId,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  final String localId;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final _PendingOutgoingStatus status;

  bool get isSending => status == _PendingOutgoingStatus.sending;

  factory _PendingOutgoingMessage.sending({
    required String localId,
    required String conversationId,
    required String senderId,
    required String text,
    required DateTime createdAt,
  }) {
    return _PendingOutgoingMessage(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      status: _PendingOutgoingStatus.sending,
    );
  }

  _PendingOutgoingMessage asFailed() {
    return _PendingOutgoingMessage(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      status: _PendingOutgoingStatus.failed,
    );
  }

  DirectMessage asDirectMessage() {
    return DirectMessage(
      id: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
    );
  }
}
