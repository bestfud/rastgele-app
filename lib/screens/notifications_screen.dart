import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/spot_repository.dart';
import '../widgets/app_ui.dart';
import 'chat_screen.dart';
import 'spot_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repository,
  });

  final SpotRepository repository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _notificationsFuture;
  Map<String, String> _spotNamesById = const {};

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _loadNotifications();
  }

  Future<List<AppNotification>> _loadNotifications() async {
    final items = await widget.repository.fetchNotifications();
    unawaited(_loadSpotNames(items));
    return items;
  }

  Future<void> _loadSpotNames(List<AppNotification> items) async {
    final spotIds = items
        .where((item) => item.type.trim().toLowerCase() == 'spot_shared')
        .map((item) => (item.fishingSpotId ?? '').trim())
        .where((id) => id.isNotEmpty && !_spotNamesById.containsKey(id))
        .toSet();

    if (spotIds.isEmpty) {
      return;
    }

    final entries = await Future.wait(
      spotIds.map((spotId) async {
        try {
          final detail = await widget.repository.fetchSpotDetail(spotId);
          final spotName = detail.spot.name.trim();
          if (spotName.isEmpty) {
            return null;
          }
          return MapEntry(spotId, spotName);
        } catch (_) {
          return null;
        }
      }),
    );

    if (!mounted) {
      return;
    }

    final resolvedNames = {
      for (final entry in entries)
        if (entry != null) entry.key: entry.value,
    };
    if (resolvedNames.isEmpty) {
      return;
    }

    setState(() {
      _spotNamesById = {
        ..._spotNamesById,
        ...resolvedNames,
      };
    });
  }

  Future<void> _reload() async {
    final future = _loadNotifications();
    setState(() {
      _notificationsFuture = future;
    });
    await future;
  }

  Future<void> _openNotification(AppNotification item) async {
    if (!item.isRead) {
      try {
        await widget.repository.markNotificationAsRead(item.id);
      } catch (_) {}
    }

    final type = item.type.trim().toLowerCase();
    if (type == 'dm_message') {
      final conversationId = (item.conversationId ?? '').trim();
      final actorProfileId = (item.actorProfileId ?? '').trim();
      if (conversationId.isEmpty || actorProfileId.isEmpty) {
        await _reload();
        return;
      }

      final otherProfile = AppProfile(
        id: actorProfileId,
        displayName: _actorDisplayName(item),
        username: item.actorUsername,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            repository: widget.repository,
            conversationId: conversationId,
            otherProfile: otherProfile,
            currentProfileId: widget.repository.currentProfileIdHint,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      await _reload();
      return;
    }

    final spotId = (item.fishingSpotId ?? '').trim();
    if (spotId.isEmpty) {
      await _reload();
      return;
    }

    try {
      debugPrint(
        '[SPOT_NAV] tap source=notification postId=null passedSpotId=$spotId linkedSpotId=null linkedFishingSpotId=null itemSpotId=null notificationSpotId=$spotId',
      );
      await widget.repository.fetchSpotDetail(spotId);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SpotDetailScreen(
            repository: widget.repository,
            spotId: spotId,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      await _reload();
    } catch (error) {
      debugPrint(
        '[SPOT_NAV] failure source=notification postId=null passedSpotId=$spotId error=$error',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu meraya artık erişimin yok.')),
      );
      await _reload();
    }
  }

  String _actorDisplayName(AppNotification item) {
    final actorName = (item.actorDisplayName ?? '').trim();
    final fallback = (item.actorUsername ?? '').trim();
    if (actorName.isNotEmpty) {
      return actorName;
    }
    if (fallback.isNotEmpty) {
      return fallback.startsWith('@') ? fallback : '@$fallback';
    }
    return 'Bir kullanıcı';
  }

  Widget _buildNotificationContent(
    BuildContext context,
    AppNotification item, {
    required bool isUnread,
  }) {
    final theme = Theme.of(context);
    final type = item.type.trim().toLowerCase();
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = isUnread
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.78);

    if (type == 'spot_shared') {
      final spotName = _spotNamesById[(item.fishingSpotId ?? '').trim()] ??
          'Paylaşılan mera';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _actorDisplayName(item),
            style: theme.textTheme.titleSmall?.copyWith(
              color: primaryTextColor,
              fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'seninle bir mera paylaştı',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor,
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            spotName,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: primaryTextColor,
              fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      );
    }

    if (type == 'dm_message') {
      final preview = (item.messagePreview ?? '').trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _actorDisplayName(item),
            style: theme.textTheme.titleSmall?.copyWith(
              color: primaryTextColor,
              fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'sana mesaj gönderdi',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor,
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: primaryTextColor,
                fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    return Text(
      'Yeni bir bildirimin var',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: primaryTextColor,
        fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }

  String _timeAgoLabel(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt.toLocal());

    if (diff.inMinutes < 1) {
      return 'Simdi';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} dk once';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} sa once';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} gun once';
    }
    return '${createdAt.day.toString().padLeft(2, '0')}.'
        '${createdAt.month.toString().padLeft(2, '0')}.'
        '${createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: FutureBuilder<List<AppNotification>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Bildirimler yüklenemedi: ${snapshot.error}'),
              ),
            );
          }

          final items = snapshot.data ?? const <AppNotification>[];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 180),
                  AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    message: 'Şu anda bildirimin yok.',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                final isUnread = !item.isRead;
                final cardColor = isUnread
                    ? AppColors.primarySoft
                    : theme.colorScheme.surface;
                return Card(
                  elevation: 0,
                  color: cardColor,
                  child: ListTile(
                    onTap: () => _openNotification(item),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const CircleAvatar(
                          child: Icon(Icons.notifications_none_rounded),
                        ),
                        if (isUnread)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: _buildNotificationContent(
                      context,
                      item,
                      isUnread: isUnread,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _timeAgoLabel(item.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isUnread
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.72),
                          fontWeight:
                              isUnread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
