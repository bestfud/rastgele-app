import 'package:flutter/material.dart';

import 'app_logo.dart';
import 'app_ui.dart';

void _noopCallback() {}

class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
    required this.onOpenSearch,
    required this.onOpenLocation,
    this.onOpenMessages = _noopCallback,
    this.onOpenNotifications = _noopCallback,
    required this.onLogout,
    this.unreadMessageCount = 0,
    this.unreadNotificationCount = 0,
    this.headerAvatarUrl,
    this.headerAvatarLabel,
    this.actions,
  });

  final String title;
  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocation;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenNotifications;
  final VoidCallback onLogout;
  final int unreadMessageCount;
  final int unreadNotificationCount;
  final String? headerAvatarUrl;
  final String? headerAvatarLabel;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final showCreateFab = selectedIndex >= 0 && selectedIndex <= 3;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 56,
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _HeaderAvatarButton(
              avatarUrl: headerAvatarUrl,
              avatarLabel: headerAvatarLabel ?? title,
              onTap: () => onSelectIndex(4),
            ),
          ),
        ),
        centerTitle: false,
        title: const _HeaderBrand(),
        titleSpacing: 8,
        actions: [
          if (actions != null) ...actions!,
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _HeaderNotificationButton(
              unreadCount: unreadNotificationCount,
              onTap: onOpenNotifications,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _HeaderMessageButton(
              unreadCount: unreadMessageCount,
              onTap: onOpenMessages,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border.withValues(alpha: 0.55),
          ),
        ),
      ),
      body: body,
      floatingActionButton: showCreateFab
          ? _CreateContentFab(
              onOpenAddSpot: onOpenAddSpot,
              onOpenCreatePost: onOpenCreatePost,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.card,
          elevation: 0,
          height: 72 + bottomInset,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 10.5,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.68),
                );
          }),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelectIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 22),
              selectedIcon: Icon(Icons.home_rounded, size: 22),
              label: 'Ana Sayfa',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded, size: 22),
              selectedIcon: Icon(Icons.search_rounded, size: 22),
              label: 'Arama',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined, size: 24),
              selectedIcon: Icon(Icons.map_rounded, size: 24),
              label: 'Harita',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, size: 22),
              selectedIcon: Icon(Icons.explore_rounded, size: 22),
              label: 'Keşfet',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded, size: 22),
              selectedIcon: Icon(Icons.person_rounded, size: 22),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBrand extends StatelessWidget {
  const _HeaderBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(height: 24),
        const SizedBox(width: 10),
        Text(
          'Rastgele',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _CreateContentFab extends StatefulWidget {
  const _CreateContentFab({
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
  });

  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;

  @override
  State<_CreateContentFab> createState() => _CreateContentFabState();
}

class _CreateContentFabState extends State<_CreateContentFab> {
  final MenuController _menuController = MenuController();

  void _handleSelect(VoidCallback action) {
    _menuController.close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      child: MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, -12),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            theme.colorScheme.surface.withValues(alpha: 0.96),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: () => _handleSelect(widget.onOpenAddSpot),
            leadingIcon: const Icon(Icons.place_outlined, size: 18),
            child: const Text('Mera ekle'),
          ),
          MenuItemButton(
            onPressed: () => _handleSelect(widget.onOpenCreatePost),
            leadingIcon: const Icon(Icons.edit_outlined, size: 18),
            child: const Text('Post ekle'),
          ),
        ],
        builder: (context, controller, child) {
          final isOpen = controller.isOpen;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: theme.colorScheme.surface.withValues(alpha: 0.92),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOpen ? Icons.close_rounded : Icons.add_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Paylaş',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderAvatarButton extends StatelessWidget {
  const _HeaderAvatarButton({
    required this.avatarUrl,
    required this.avatarLabel,
    required this.onTap,
  });

  final String? avatarUrl;
  final String avatarLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trimmedAvatarUrl = avatarUrl?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primarySoft,
            backgroundImage:
                trimmedAvatarUrl != null && trimmedAvatarUrl.isNotEmpty
                    ? NetworkImage(trimmedAvatarUrl)
                    : null,
            child: trimmedAvatarUrl == null || trimmedAvatarUrl.isEmpty
                ? Text(
                    _avatarInitials(avatarLabel),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  static String _avatarInitials(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      return 'U';
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

class _HeaderNotificationButton extends StatelessWidget {
  const _HeaderNotificationButton({
    required this.unreadCount,
    required this.onTap,
    required this.color,
  });

  final int unreadCount;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppColors.danger,
        label: Text(
          unreadCount > 99 ? '99+' : '$unreadCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Icon(
          Icons.notifications_none_rounded,
          color: color,
          size: 22,
        ),
      ),
    );
  }
}

class _HeaderMessageButton extends StatelessWidget {
  const _HeaderMessageButton({
    required this.unreadCount,
    required this.onTap,
    required this.color,
  });

  final int unreadCount;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppColors.primary,
        label: Text(
          unreadCount > 99 ? '99+' : '$unreadCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Icon(
          Icons.chat_bubble_outline_rounded,
          color: color,
          size: 22,
        ),
      ),
    );
  }
}
