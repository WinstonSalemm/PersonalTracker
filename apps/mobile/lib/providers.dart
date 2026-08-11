import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_tracker_api_client/api_client.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';

import 'beta_auth.dart';

final localDataScopeProvider = Provider<LocalDataScope>((ref) {
  final manager = ref.watch(authManagerProvider);
  final session = manager.session;
  if (session == null) throw StateError('local_scope_unavailable');
  // Current Money, English, Sport, Capture and solo Work data are personal.
  // Future tenant-owned repositories must request LocalDataScope.tenant
  // explicitly rather than reusing the active tenant for personal data.
  return LocalDataScope.personal(session.user.id);
});

final legacyMigrationClaimRequestedProvider =
    StateProvider.autoDispose<bool>((ref) => false);

final databaseProvider = FutureProvider.autoDispose<LocalDatabase>((ref) async {
  final scope = ref.watch(localDataScopeProvider);
  final manager = ref.watch(authManagerProvider);
  final claimRequested = ref.watch(legacyMigrationClaimRequestedProvider);
  final claim = claimRequested && manager.restoredExistingSession
      ? LegacyMigrationClaim.forRestoredPersonalSession(scope)
      : null;
  final database = await LocalDatabase.open(
    scope: scope,
    legacyMigrationClaim: claim,
    // An explicit compile-time offline fixture must be able to create its own
    // empty scope while a real user's unverified legacy DB remains quarantined.
    allowEmptyScopeWithQuarantinedLegacy:
        BetaConfig.explicitOfflineFixture && !BetaConfig.configured,
  );
  ref.onDispose(database.close);
  return database;
});

final commandParserProvider =
    Provider<CommandParser>((ref) => DeterministicParser());
final authManagerProvider = ChangeNotifierProvider<SessionManager>((ref) {
  final manager = SessionManager(
    api: AuthApiClient(baseUrl: BetaConfig.apiBaseUrl),
    storage: const SecureTokenStorage(),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final apiProvider = Provider<PersonalTrackerApi>((ref) {
  final manager = ref.watch(authManagerProvider);
  return PersonalTrackerApi(
    baseUrl: BetaConfig.apiBaseUrl,
    accessToken: manager.session?.tokens.accessToken,
  );
});
