import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import 'perf_logger.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;
  Future<AppProfile>? _pendingEnsureProfile;
  String? _pendingEnsureProfileAuthUid;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    await ensureProfile();
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'display_name': displayName,
      },
    );

    final user = response.user;
    if (user == null) {
      throw Exception(
          'Kayıt tamamlandı ancak doğrulanmış kullanıcı bulunamadı.');
    }

    if (response.session != null) {
      await ensureProfile(
        preferredDisplayName: displayName,
      );
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AppProfile> ensureProfile({
    String? preferredDisplayName,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('Oturum açmış kullanıcı bulunamadı.');
    }

    if (_pendingEnsureProfile != null &&
        _pendingEnsureProfileAuthUid == user.id) {
      return _pendingEnsureProfile!;
    }

    final future = _ensureProfileForUser(
      user,
      preferredDisplayName: preferredDisplayName,
    );
    _pendingEnsureProfile = future;
    _pendingEnsureProfileAuthUid = user.id;

    try {
      return await future;
    } finally {
      if (identical(_pendingEnsureProfile, future)) {
        _pendingEnsureProfile = null;
        _pendingEnsureProfileAuthUid = null;
      }
    }
  }

  void clearSessionState({
    String? reason,
  }) {
    _pendingEnsureProfile = null;
    _pendingEnsureProfileAuthUid = null;
    _authLog('clearSessionState reason=${reason ?? 'unspecified'}');
  }

  Future<AppProfile> _ensureProfileForUser(
    User user, {
    String? preferredDisplayName,
  }) async {
    final existing = await _findProfileForAuthUser(user.id);
    if (existing != null) {
      final profile = _profileFromRow(
        existing.row,
        authUid: user.id,
        context: 'ensureProfile.existing',
      );
      _logResolvedProfile(
        authUid: user.id,
        profile: profile,
        created: false,
        usedLegacyFallback: existing.usedLegacyFallback,
      );
      return profile;
    }

    final fallbackName = _fallbackDisplayName(
      user: user,
      preferredDisplayName: preferredDisplayName,
    );

    var createdNewProfile = false;
    try {
      await _client.from('profiles').insert({
        'auth_user_id': user.id,
        'display_name': fallbackName,
      });
      createdNewProfile = true;
    } catch (_) {
      try {
        await _client.from('profiles').insert({
          'id': user.id,
          'auth_user_id': user.id,
          'display_name': fallbackName,
        });
        createdNewProfile = true;
      } catch (_) {
        createdNewProfile = false;
      }
    }

    final resolved = await _findProfileForAuthUser(user.id);
    if (resolved == null) {
      throw Exception('Oturumdaki kullanıcı için profil oluşturulamadı.');
    }

    final profile = _profileFromRow(
      resolved.row,
      authUid: user.id,
      context: 'ensureProfile.resolved',
    );
    _logResolvedProfile(
      authUid: user.id,
      profile: profile,
      created: createdNewProfile,
      usedLegacyFallback: resolved.usedLegacyFallback,
    );
    return profile;
  }

  Future<_ResolvedProfileRow?> _findProfileForAuthUser(
      String authUserId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .eq('auth_user_id', authUserId)
          .limit(2);
      final rowList = (rows as List).cast<dynamic>();
      if (rowList.isNotEmpty) {
        return _ResolvedProfileRow(
          row: Map<String, dynamic>.from(rowList.first as Map),
          usedLegacyFallback: false,
        );
      }
    } catch (_) {
      _authLog('auth_user_id lookup failed authUid=$authUserId');
    }

    try {
      final rows =
          await _client.from('profiles').select().eq('id', authUserId).limit(2);
      final rowList = (rows as List).cast<dynamic>();
      if (rowList.isEmpty) {
        return null;
      }

      final row = Map<String, dynamic>.from(rowList.first as Map);
      final profile = AppProfile.fromMap(row);
      final resolvedAuthUserId = profile.authUserId?.trim();
      if (resolvedAuthUserId != null &&
          resolvedAuthUserId.isNotEmpty &&
          resolvedAuthUserId != authUserId) {
        _authLog(
          'rejecting legacy fallback authUid=$authUserId profileId=${profile.id} resolvedAuthUserId=$resolvedAuthUserId',
        );
        return null;
      }

      return _ResolvedProfileRow(
        row: row,
        usedLegacyFallback: true,
      );
    } catch (_) {
      _authLog('legacy id lookup failed authUid=$authUserId');
      return null;
    }
  }

  AppProfile _profileFromRow(
    Map<String, dynamic> row, {
    required String authUid,
    required String context,
  }) {
    final profile = AppProfile.fromMap(row);
    if (profile.id.trim().isEmpty) {
      _authLog(
        'invalid profile row context=$context authUid=$authUid profileId=missing authUserId=${profile.authUserId ?? 'null'}',
      );
      throw Exception('Geçerli profil kimliği çözümlenemedi.');
    }

    return profile;
  }

  void _logResolvedProfile({
    required String authUid,
    required AppProfile profile,
    required bool created,
    required bool usedLegacyFallback,
  }) {
    _authLog(
      'resolved profile authUid=$authUid profileId=${profile.id} profileAuthUserId=${profile.authUserId ?? 'null'} created=$created usedLegacyFallback=$usedLegacyFallback',
    );
  }

  void _authLog(String message) {
    perfLog('[auth] $message');
  }

  String _fallbackDisplayName({
    required User user,
    String? preferredDisplayName,
  }) {
    final preferred = preferredDisplayName?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }

    final metadataName = user.userMetadata?['display_name']?.toString().trim();
    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    final emailPrefix = user.email?.split('@').first.trim();
    if (emailPrefix != null && emailPrefix.isNotEmpty) {
      return emailPrefix;
    }

    return 'Balıkçı';
  }
}

class _ResolvedProfileRow {
  const _ResolvedProfileRow({
    required this.row,
    required this.usedLegacyFallback,
  });

  final Map<String, dynamic> row;
  final bool usedLegacyFallback;
}
