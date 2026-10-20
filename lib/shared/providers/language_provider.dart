import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_currency.dart';
import '../models/app_language.dart';

const _kLanguageKey = 'selected_language';
const _kCurrencyKey = 'selected_currency';
const _kOnboardingCompleteKey = 'onboarding_complete';
const kAuthUserIdPrefKey = 'auth_user_id';

/// Provider for SharedPreferences instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

/// The Supabase client when the app is pointed at a backend, else `null`.
/// Overridden in `main()` right after `Supabase.initialize`. When non-null,
/// auth and privileged user administration run against Supabase (production);
/// when null (widget tests / pure-offline dev) the app uses the local store.
/// Lives here (a leaf provider file) so both the auth layer and the users layer
/// can read it without importing each other.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

// ─── Onboarding ──────────────────────────────────────────────────

/// Whether the user has completed onboarding (language selection).
final onboardingCompleteProvider =
    StateNotifierProvider<OnboardingNotifier, bool>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return OnboardingNotifier(prefs);
    });

class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier(this._prefs)
    : super(_prefs.getBool(_kOnboardingCompleteKey) ?? false);

  final SharedPreferences _prefs;

  Future<void> complete() async {
    await _prefs.setBool(_kOnboardingCompleteKey, true);
    state = true;
  }
}

// ─── Display language ────────────────────────────────────────────

/// The currently selected display language (English by default).
final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LanguageNotifier(prefs);
});

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier(this._prefs)
    : super(
        AppLanguage.fromCode(
          _prefs.getString(_kLanguageKey) ?? AppLanguage.english.code,
        ),
      );

  final SharedPreferences _prefs;

  Future<void> setLanguage(AppLanguage language) async {
    await _prefs.setString(_kLanguageKey, language.code);
    state = language;
  }
}

// ─── Currency ────────────────────────────────────────────────────

/// The currently selected currency (AED by default).
final currencyProvider = StateNotifierProvider<CurrencyNotifier, AppCurrency>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CurrencyNotifier(prefs);
});

class CurrencyNotifier extends StateNotifier<AppCurrency> {
  // Yorks' company reporting currency is fixed. A retained device-only choice
  // from the earlier prototype is deliberately ignored.
  CurrencyNotifier(this._prefs) : super(AppCurrency.aed);

  final SharedPreferences _prefs;

  Future<void> setCurrency(AppCurrency currency) async {
    await _prefs.remove(_kCurrencyKey);
    state = AppCurrency.aed;
  }
}

// ─── Auth Session ────────────────────────────────────────────────

/// The signed-in user's id, or `null` when logged out. Set only after
/// credentials are verified (see `authControllerProvider` in session_provider).
/// Connected startup waits for AuthController to verify the Supabase session.
final authSessionProvider = StateNotifierProvider<AuthSessionNotifier, String?>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AuthSessionNotifier(
      prefs,
      restoreLocalSession: ref.watch(supabaseClientProvider) == null,
    );
  },
);

/// Convenience boolean for redirect logic / widgets.
final isLoggedInProvider = Provider<bool>(
  (ref) => ref.watch(authSessionProvider) != null,
);

class AuthSessionNotifier extends StateNotifier<String?> {
  AuthSessionNotifier(this._prefs, {bool restoreLocalSession = true})
    : super(restoreLocalSession ? _prefs.getString(kAuthUserIdPrefKey) : null);

  final SharedPreferences _prefs;
  int _generation = 0;

  Future<void> setUser(String userId) async {
    if (state == userId) return;
    final generation = ++_generation;
    await _prefs.setString(kAuthUserIdPrefKey, userId);
    if (generation == _generation) state = userId;
  }

  Future<void> logout() async {
    // Revoke presentation access before waiting for device storage. Also
    // invalidate an in-flight setUser so it cannot restore a signed-out user.
    _generation++;
    state = null;
    await _prefs.remove(kAuthUserIdPrefKey);
  }
}
