import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/perf_logger.dart';
import '../services/spot_repository.dart';
import 'add_spot_screen.dart';
import 'create_post_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'inbox_screen.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.authService,
    required this.repository,
  });

  final AuthService authService;
  final SpotRepository repository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _refreshSeed = 0;
  int _homeSessionSeed = 0;
  AppProfile? _shellProfile;
  late final StreamSubscription<AuthState> _authStateSubscription;
  Timer? _badgePollTimer;
  String? _lastAuthUid;
  int _unreadNotificationCount = 0;
  int _unreadMessageCount = 0;
  Future<void>? _pendingUnreadMessageRefresh;
  Future<void>? _pendingShellBadgeRefresh;
  bool _didScheduleShellInit = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _lastAuthUid = widget.authService.currentUser?.id;
    widget.repository.clearSessionState(
      previousAuthUid: null,
      nextAuthUid: _lastAuthUid,
      reason: 'shell_init',
    );
    widget.authService.clearSessionState(reason: 'shell_init');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didScheduleShellInit) {
        return;
      }
      _didScheduleShellInit = true;
      if (_lastAuthUid != null) {
        _startBadgePolling();
        unawaited(_primeProfileForCurrentSession());
        unawaited(_refreshShellProfile());
        unawaited(_scheduleDeferredShellBadgeRefresh());
      }
    });

    _authStateSubscription =
        widget.authService.authStateChanges.listen((state) {
      final nextAuthUid =
          state.session?.user.id ?? widget.authService.currentUser?.id;
      final previousAuthUid = _lastAuthUid;
      final didAuthIdentityChange = previousAuthUid != nextAuthUid;

      if (!didAuthIdentityChange) {
        return;
      }

      _lastAuthUid = nextAuthUid;
      widget.authService
          .clearSessionState(reason: 'auth_change:${state.event.name}');
      widget.repository.clearSessionState(
        previousAuthUid: previousAuthUid,
        nextAuthUid: nextAuthUid,
        reason: state.event.name,
      );

      if (mounted) {
        setState(() {
          _selectedIndex = 0;
          _refreshSeed++;
          _homeSessionSeed++;
        });
      }

      if (nextAuthUid != null) {
        _startBadgePolling();
        unawaited(_primeProfileForCurrentSession());
        unawaited(_refreshShellProfile());
        unawaited(_scheduleDeferredShellBadgeRefresh());
      } else {
        _stopBadgePolling();
        if (mounted) {
          setState(() {
            _shellProfile = null;
            _unreadNotificationCount = 0;
            _unreadMessageCount = 0;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _badgePollTimer?.cancel();
    _authStateSubscription.cancel();
    super.dispose();
  }

  void _startBadgePolling() {
    _badgePollTimer?.cancel();
    _badgePollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_scheduleDeferredShellBadgeRefresh()),
    );
  }

  void _stopBadgePolling() {
    _badgePollTimer?.cancel();
    _badgePollTimer = null;
  }

  Future<void> _scheduleDeferredShellBadgeRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }
    await _refreshShellBadgeCounts();
  }

  Future<void> _openAddSpot() async {
    final createdSpot = await Navigator.of(context).push<FishingSpot>(
      MaterialPageRoute<FishingSpot>(
        builder: (_) => AddSpotScreen(repository: widget.repository),
      ),
    );
    if (createdSpot != null && mounted) {
      setState(() {
        _refreshSeed++;
      });
      unawaited(_refreshShellBadgeCounts());
    }
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreatePostScreen(repository: widget.repository),
      ),
    );
    if (created == true && mounted) {
      setState(() {
        _refreshSeed++;
      });
      unawaited(_refreshShellBadgeCounts());
    }
  }

  Future<void> _openSearch() async {
    if (_selectedIndex == 1) {
      return;
    }
    setState(() {
      _selectedIndex = 1;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          repository: widget.repository,
        ),
      ),
    );
    await _refreshShellBadgeCounts();
  }

  Future<void> _openMessages() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InboxScreen(
          repository: widget.repository,
        ),
      ),
    );
    unawaited(_refreshUnreadMessageCount(reason: 'inbox_return'));
  }

  void _openLocation() {
    if (_selectedIndex == 2) {
      return;
    }

    setState(() {
      _selectedIndex = 2;
    });
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _primeProfileForCurrentSession() async {
    try {
      await widget.authService.ensureProfile();
    } catch (_) {}
  }

  Future<void> _refreshShellProfile() async {
    try {
      final profile = await widget.repository.fetchCurrentProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _shellProfile = profile;
      });
    } catch (_) {}
  }

  Future<void> _refreshUnreadNotificationCount() async {
    try {
      final count = await widget.repository.fetchUnreadNotificationsCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _unreadNotificationCount = count;
      });
    } catch (_) {}
  }

  Future<void> _refreshUnreadMessageCount({
    String reason = 'unspecified',
  }) async {
    final pendingRefresh = _pendingUnreadMessageRefresh;
    if (pendingRefresh != null) {
      return pendingRefresh;
    }

    final future = () async {
      try {
        final count = await widget.repository.getUnreadMessageCount(
          currentProfileId: widget.repository.currentProfileIdHint,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _unreadMessageCount = count;
        });
      } catch (_) {}
    }();
    _pendingUnreadMessageRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_pendingUnreadMessageRefresh, future)) {
        _pendingUnreadMessageRefresh = null;
      }
    }
  }

  Future<void> _refreshShellBadgeCounts() async {
    final pendingRefresh = _pendingShellBadgeRefresh;
    if (pendingRefresh != null) {
      return pendingRefresh;
    }

    final future = () async {
      await Future.wait([
        _refreshUnreadNotificationCount(),
        _refreshUnreadMessageCount(reason: 'shell_refresh'),
      ]);
    }();
    _pendingShellBadgeRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_pendingShellBadgeRefresh, future)) {
        _pendingShellBadgeRefresh = null;
      }
    }
  }

  Future<void> _handleLogout() async {
    if (_isSigningOut) {
      return;
    }

    final previousAuthUid = _lastAuthUid ?? widget.authService.currentUser?.id;

    if (mounted) {
      setState(() {
        _isSigningOut = true;
      });
    }

    try {
      await widget.authService.signOut();
      widget.authService.clearSessionState(reason: 'sign_out');
      widget.repository.clearSessionState(
        previousAuthUid: previousAuthUid,
        nextAuthUid: null,
        reason: 'sign_out',
      );
      _lastAuthUid = null;
      _stopBadgePolling();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() {
          _selectedIndex = 0;
          _refreshSeed++;
          _homeSessionSeed++;
          _shellProfile = null;
          _unreadNotificationCount = 0;
          _unreadMessageCount = 0;
        });
      }
    } catch (error) {
      perfLog('[AUTH] signOut failure error=$error');
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: widget.authService.authStateChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        widget.authService.currentSession,
      ),
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? widget.authService.currentSession;
        final authUid = session?.user.id ?? widget.authService.currentUser?.id;

        if (session == null) {
          return KeyedSubtree(
            key: const ValueKey('logged-out'),
            child: LoginScreen(authService: widget.authService),
          );
        }

        final clampedIndex = _selectedIndex.clamp(0, 4);
        if (clampedIndex != _selectedIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _selectedIndex = clampedIndex;
            });
          });
        }

        switch (clampedIndex) {
          case 1:
            return SearchScreen(
              key: ValueKey('search-$authUid'),
              repository: widget.repository,
              showShellChrome: true,
              selectedIndex: _selectedIndex,
              onSelectTab: _selectTab,
              onOpenAddSpot: _openAddSpot,
              onOpenCreatePost: _openCreatePost,
              onOpenSearch: _openSearch,
              onOpenLocation: _openLocation,
              onOpenNotifications: _openNotifications,
              onLogout: _handleLogout,
              unreadNotificationCount: _unreadNotificationCount,
              shellAvatarUrl: _shellProfile?.avatarUrl,
              shellAvatarLabel: _shellProfile?.displayName,
            );
          case 2:
            return MapScreen(
              key: ValueKey('map-$authUid'),
              repository: widget.repository,
              selectedIndex: _selectedIndex,
              refreshSeed: _refreshSeed,
              onSelectTab: _selectTab,
              onOpenAddSpot: _openAddSpot,
              onOpenCreatePost: _openCreatePost,
              onOpenSearch: _openSearch,
              onOpenLocation: _openLocation,
              onOpenMessages: _openMessages,
              onOpenNotifications: _openNotifications,
              unreadMessageCount: _unreadMessageCount,
              unreadNotificationCount: _unreadNotificationCount,
              onLogout: _handleLogout,
              shellAvatarUrl: _shellProfile?.avatarUrl,
              shellAvatarLabel: _shellProfile?.displayName,
            );
          case 3:
            return ExploreScreen(
              key: ValueKey('explore-$authUid'),
              repository: widget.repository,
              selectedIndex: _selectedIndex,
              refreshSeed: _refreshSeed,
              onSelectTab: _selectTab,
              onOpenAddSpot: _openAddSpot,
              onOpenCreatePost: _openCreatePost,
              onOpenSearch: _openSearch,
              onOpenLocation: _openLocation,
              onOpenMessages: _openMessages,
              onOpenNotifications: _openNotifications,
              unreadMessageCount: _unreadMessageCount,
              unreadNotificationCount: _unreadNotificationCount,
              onLogout: _handleLogout,
              shellAvatarUrl: _shellProfile?.avatarUrl,
              shellAvatarLabel: _shellProfile?.displayName,
            );
          case 4:
            return ProfileScreen(
              key: ValueKey('profile-$authUid'),
              repository: widget.repository,
              selectedIndex: _selectedIndex,
              refreshSeed: _refreshSeed,
              onSelectTab: _selectTab,
              onOpenAddSpot: _openAddSpot,
              onOpenCreatePost: _openCreatePost,
              onOpenSearch: _openSearch,
              onOpenLocation: _openLocation,
              onOpenMessages: _openMessages,
              onOpenNotifications: _openNotifications,
              onDirectMessageStateChanged: _refreshUnreadMessageCount,
              unreadMessageCount: _unreadMessageCount,
              unreadNotificationCount: _unreadNotificationCount,
              onLogout: _handleLogout,
              shellAvatarUrl: _shellProfile?.avatarUrl,
              shellAvatarLabel: _shellProfile?.displayName,
            );
          case 0:
          default:
            return HomeScreen(
              key: ValueKey('home-$authUid-$_homeSessionSeed'),
              authService: widget.authService,
              repository: widget.repository,
              selectedIndex: _selectedIndex,
              refreshSeed: _refreshSeed,
              sessionSeed: _homeSessionSeed,
              onSelectTab: _selectTab,
              onOpenAddSpot: _openAddSpot,
              onOpenCreatePost: _openCreatePost,
              onOpenSearch: _openSearch,
              onOpenLocation: _openLocation,
              onOpenMessages: _openMessages,
              onOpenNotifications: _openNotifications,
              onLogout: _handleLogout,
              unreadMessageCount: _unreadMessageCount,
              unreadNotificationCount: _unreadNotificationCount,
              shellAvatarUrl: _shellProfile?.avatarUrl,
              shellAvatarLabel: _shellProfile?.displayName,
            );
        }
      },
    );
  }
}
