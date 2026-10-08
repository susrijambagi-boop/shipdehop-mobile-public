import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'pending_verification_storage.dart';

enum AuthMethod {
  phoneWhatsapp,
  emailMagicLink,
  devTest,
}

enum AuthFlowStatus {
  loading,
  unauthenticated,
  authenticatedIdentityRequired,
  authenticatedIdentityPending,
  authenticatedVerified,
  authenticatedRestricted,
}

class AppAuthState {
  final String? userId;
  final String? accessToken;
  final String? phoneE164;
  final String identityStatus;
  final bool isBootstrapping;
  final AuthMethod authMethod;

  const AppAuthState({
    this.userId,
    this.accessToken,
    this.phoneE164,
    this.identityStatus = 'NOT_STARTED',
    this.isBootstrapping = true,
    this.authMethod = AuthMethod.phoneWhatsapp,
  });

  bool get isAuthenticated => userId != null && accessToken != null;
  bool get isIdentityVerified => identityStatus == 'VERIFIED';
  bool get isIdentityPending => identityStatus == 'PENDING_REVIEW' || identityStatus == 'IN_PROGRESS';
  bool get isIdentityRequired => isAuthenticated && (identityStatus == 'NOT_STARTED' || identityStatus.isEmpty);
  bool get isRestricted => identityStatus == 'REJECTED' || identityStatus == 'REVOKED';

  AuthFlowStatus get flowStatus {
    if (isBootstrapping) return AuthFlowStatus.loading;
    if (!isAuthenticated) return AuthFlowStatus.unauthenticated;
    if (isRestricted) return AuthFlowStatus.authenticatedRestricted;
    if (isIdentityRequired) return AuthFlowStatus.authenticatedIdentityRequired;
    if (isIdentityPending) return AuthFlowStatus.authenticatedIdentityPending;
    return AuthFlowStatus.authenticatedVerified;
  }

  AppAuthState copyWith({
    String? userId,
    String? accessToken,
    String? phoneE164,
    String? identityStatus,
    bool? isBootstrapping,
    AuthMethod? authMethod,
  }) {
    return AppAuthState(
      userId: userId ?? this.userId,
      accessToken: accessToken ?? this.accessToken,
      phoneE164: phoneE164 ?? this.phoneE164,
      identityStatus: identityStatus ?? this.identityStatus,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      authMethod: authMethod ?? this.authMethod,
    );
  }
}

class SessionManager extends Notifier<AppAuthState> {
  @override
  AppAuthState build() {
    // Supabase is initialized by main() in the real app, but several unit tests
    // construct SessionManager directly without bootstrapping Supabase first.
    // Keep those tests isolated while still wiring native magic-link auth in production.
    try {
      final supabaseAuth = Supabase.instance.client.auth;

      final authSubscription = supabaseAuth.onAuthStateChange.listen((authState) {
        final session = authState.session;
        if (session != null) {
          Future<void>.microtask(() => _applySupabaseSession(session));
        } else if (
            authState.event == AuthChangeEvent.signedOut &&
            state.authMethod == AuthMethod.emailMagicLink) {
          state = const AppAuthState(
            isBootstrapping: false,
            authMethod: AuthMethod.emailMagicLink,
          );
        }
      });
      ref.onDispose(authSubscription.cancel);

      final existingSupabaseSession = supabaseAuth.currentSession;
      if (existingSupabaseSession != null) {
        Future<void>.microtask(() => _applySupabaseSession(existingSupabaseSession));
      }
    } catch (_) {
      // Expected in isolated unit tests where Supabase.initialize() is not called.
    }

    // Also attempt the legacy ShipdeHop phone-session restore. If an email
    // session has already been restored, a failed cookie refresh will preserve it.
    Future<void>.microtask(restoreSessionFromCookie);
    return const AppAuthState(isBootstrapping: true);
  }

  Future<void> _applySupabaseSession(Session session) async {
    var identityStatus = 'NOT_STARTED';

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/identity/status'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        identityStatus = data['verificationStatus']?.toString() ?? 'NOT_STARTED';
      }
    } catch (_) {
      // Authentication is still valid even if the identity badge cannot be loaded yet.
    }

    state = AppAuthState(
      userId: session.user.id,
      accessToken: session.accessToken,
      phoneE164: session.user.phone,
      identityStatus: identityStatus,
      isBootstrapping: false,
      authMethod: AuthMethod.emailMagicLink,
    );
  }

  /// Restores session on app startup via same-origin HttpOnly cookie
  Future<bool> restoreSessionFromCookie() async {
    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/auth/session/refresh');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawStatus = data['identityStatus']?.toString() ?? 'NOT_STARTED';
        final isVerified = data['isIdentityVerified'] == true;
        final identityStatus = isVerified ? 'VERIFIED' : rawStatus;

        state = AppAuthState(
          userId: data['userId'] as String?,
          accessToken: data['accessToken'] as String?,
          phoneE164: data['phoneE164'] as String?,
          identityStatus: identityStatus,
          isBootstrapping: false,
          authMethod: AuthMethod.phoneWhatsapp,
        );
        return true;
      }
    } catch (_) {}

    // Bootstrap finished without active session (preserve state if already authenticated)
    if (!state.isAuthenticated) {
      state = const AppAuthState(isBootstrapping: false);
    } else {
      state = state.copyWith(isBootstrapping: false);
    }
    return false;
  }

  /// Sets active session in memory (Access JWT only; refresh token is handled by browser HttpOnly cookie)
  void setSession({
    required String userId,
    required String accessToken,
    String? phoneE164,
    String identityStatus = 'NOT_STARTED',
    bool isIdentityVerified = false,
    AuthMethod authMethod = AuthMethod.phoneWhatsapp,
  }) {
    final effectiveStatus = isIdentityVerified ? 'VERIFIED' : identityStatus;
    state = AppAuthState(
      userId: userId,
      accessToken: accessToken,
      phoneE164: phoneE164,
      identityStatus: effectiveStatus,
      isBootstrapping: false,
      authMethod: authMethod,
    );
  }

  void setIdentityStatus(String status) {
    state = state.copyWith(identityStatus: status);
  }

  void markIdentityVerified() {
    state = state.copyWith(identityStatus: 'VERIFIED');
  }

  /// Rotates access token via browser HttpOnly cookie
  Future<bool> refreshSession() async {
    return restoreSessionFromCookie();
  }

  /// Signs out both Supabase email auth and the ShipdeHop backend session.
  Future<void> signOut() async {
    final wasEmailSession = state.authMethod == AuthMethod.emailMagicLink;
    state = const AppAuthState(isBootstrapping: false);
    await PendingVerificationStorage.clearPendingSessionId();

    try {
      final supabaseAuth = Supabase.instance.client.auth;
      if (wasEmailSession || supabaseAuth.currentSession != null) {
        await supabaseAuth.signOut();
      }
    } catch (_) {
      // Supabase may be intentionally uninitialized in isolated unit tests.
    }

    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/auth/session/logout');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({}),
      );
    } catch (_) {}
  }
}
