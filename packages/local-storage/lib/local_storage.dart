import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_tracker_domain/domain.dart';

enum LocalDataScopeKind { personal, tenant }

class LocalDataScope {
  const LocalDataScope._({required this.kind, required this.ownerId});

  factory LocalDataScope.personal(String userId) => LocalDataScope._(
        kind: LocalDataScopeKind.personal,
        ownerId: _requireOwnerId(userId, 'userId'),
      );

  factory LocalDataScope.tenant(String tenantId) => LocalDataScope._(
        kind: LocalDataScopeKind.tenant,
        ownerId: _requireOwnerId(tenantId, 'tenantId'),
      );

  final LocalDataScopeKind kind;
  final String ownerId;

  String get key => '${kind.name}:$ownerId';
  String get fingerprint => sha256
      .convert(utf8.encode('personal-tracker/local-scope/v1|$key'))
      .toString();

  static String _requireOwnerId(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, label, 'required');
    return normalized;
  }
}

class LegacyMigrationClaim {
  const LegacyMigrationClaim._(this.scope);

  /// Construct this only after an existing secure session was restored and the
  /// user explicitly confirms the claim UI. A fresh login must not claim a
  /// legacy database whose owner cannot be established.
  factory LegacyMigrationClaim.forRestoredPersonalSession(
    LocalDataScope scope,
  ) {
    if (scope.kind != LocalDataScopeKind.personal) {
      throw ArgumentError.value(scope, 'scope', 'must be personal');
    }
    return LegacyMigrationClaim._(scope);
  }

  final LocalDataScope scope;
}

class LegacyDataQuarantined implements Exception {
  const LegacyDataQuarantined({
    required this.sourceFingerprint,
    required this.tableCounts,
  });

  final String sourceFingerprint;
  final Map<String, int> tableCounts;

  @override
  String toString() => 'legacy_data_quarantined';
}

class LegacyMigrationOwnershipMismatch implements Exception {
  const LegacyMigrationOwnershipMismatch();

  @override
  String toString() => 'legacy_migration_ownership_mismatch';
}

enum LegacyMigrationFaultPoint {
  afterQuarantineCopy,
  afterJournalCreation,
  midCopy,
  afterCopyBeforeVerification,
  afterVerification,
  afterFinalRename,
  beforeJournalMigrated,
  afterJournalMigrated,
}

class EnglishLessonProgress {
  const EnglishLessonProgress({
    required this.readingDone,
    required this.listeningDone,
    required this.writingText,
    required this.speakingPath,
  });

  const EnglishLessonProgress.empty()
      : readingDone = false,
        listeningDone = false,
        writingText = '',
        speakingPath = null;

  final bool readingDone;
  final bool listeningDone;
  final String writingText;
  final String? speakingPath;

  bool get allSkillsDone =>
      readingDone &&
      listeningDone &&
      writingText.trim().isNotEmpty &&
      speakingPath != null;
}

class SportSetLog {
  const SportSetLog({
    required this.sessionId,
    required this.sessionNumber,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.repetitions,
    required this.completed,
  });

  final String sessionId;
  final int sessionNumber;
  final String exerciseId;
  final int setNumber;
  final double weightKg;
  final int repetitions;
  final bool completed;
}

class CanonicalMoneyCommitInput {
  const CanonicalMoneyCommitInput({
    required this.captureId,
    required this.intentJson,
    required this.minorUnits,
    required this.currency,
    required this.direction,
    required this.date,
    required this.description,
    required this.paymentMethod,
    this.accountId = LocalDatabase.unassignedAccountId,
    this.categoryId = LocalDatabase.unclassifiedCategoryId,
  });
  final String captureId,
      intentJson,
      minorUnits,
      currency,
      direction,
      date,
      description,
      paymentMethod;
  final String accountId;
  final String categoryId;
}

class CanonicalMoneySyncStatus {
  const CanonicalMoneySyncStatus({
    required this.pending,
    required this.retrying,
    required this.permanentFailures,
    required this.acknowledged,
    this.nextAttemptAt,
  });

  final int pending;
  final int retrying;
  final int permanentFailures;
  final int acknowledged;
  final DateTime? nextAttemptAt;

  bool get hasOutstanding => pending + retrying + permanentFailures > 0;
  bool get requiresRepair => permanentFailures > 0;
}

class LocalDatabase {
  LocalDatabase._(
    this._db, {
    required this.scope,
    required Directory attachmentsRoot,
    required this.databasePath,
  }) : _attachmentsRoot = attachmentsRoot;
  final Database _db;
  final Directory _attachmentsRoot;
  final LocalDataScope scope;
  final String databasePath;
  static const unassignedAccountId = '__unassigned__';
  static const unclassifiedCategoryId = '__unclassified__';

  static Future<void> _migrationTail = Future<void>.value();

  String get attachmentsRootPath => _attachmentsRoot.path;

  static Future<LocalDatabase> open({
    required LocalDataScope scope,
    Directory? supportDirectory,
    Directory? legacyAttachmentDirectory,
    LegacyMigrationClaim? legacyMigrationClaim,
    LegacyMigrationFaultPoint? migrationFaultPoint,
    bool allowEmptyScopeWithQuarantinedLegacy = false,
  }) async {
    final directory =
        supportDirectory ?? await getApplicationSupportDirectory();
    final attachmentsDirectory =
        legacyAttachmentDirectory ?? await getApplicationDocumentsDirectory();
    await Directory(
      path.join(directory.path, 'scopes'),
    ).create(recursive: true);
    final scopedPath = path.join(
      directory.path,
      'scopes',
      '${scope.fingerprint}.sqlite',
    );
    await _withMigrationLock(
      () => _migrateLegacyIfNeeded(
        supportDirectory: directory,
        scopedPath: scopedPath,
        scope: scope,
        legacyAttachmentDirectory: attachmentsDirectory,
        claim: legacyMigrationClaim,
        faultPoint: migrationFaultPoint,
        allowEmptyScopeWithQuarantinedLegacy:
            allowEmptyScopeWithQuarantinedLegacy,
      ),
    );
    final attachmentRoot = Directory(
      path.join(directory.path, 'attachments', scope.fingerprint),
    );
    await attachmentRoot.create(recursive: true);
    final db = sqlite3.open(scopedPath);
    final local = LocalDatabase._(
      db,
      scope: scope,
      attachmentsRoot: attachmentRoot,
      databasePath: scopedPath,
    );
    local._initializeSchema();
    local._validateScopeMetadata();
    local._seedMoneyDefaults();
    return local;
  }

  static Future<T> _withMigrationLock<T>(Future<T> Function() action) async {
    final previous = _migrationTail;
    final release = Completer<void>();
    _migrationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  static Future<void> _migrateLegacyIfNeeded({
    required Directory supportDirectory,
    required String scopedPath,
    required LocalDataScope scope,
    required Directory legacyAttachmentDirectory,
    required LegacyMigrationClaim? claim,
    required LegacyMigrationFaultPoint? faultPoint,
    required bool allowEmptyScopeWithQuarantinedLegacy,
  }) async {
    final legacyFile = File(
      path.join(supportDirectory.path, 'personal_tracker.sqlite'),
    );
    final bootstrap = sqlite3.open(
      path.join(supportDirectory.path, 'bootstrap.sqlite'),
    );
    try {
      bootstrap.execute('''CREATE TABLE IF NOT EXISTS legacy_quarantine (
        source_fingerprint TEXT PRIMARY KEY,
        quarantine_path TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        state TEXT NOT NULL,
        claimed_scope_fingerprint TEXT,
        migrated_database_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
      if (!legacyFile.existsSync()) return;

      final sourceBytes = await legacyFile.readAsBytes();
      final sourceFingerprint = sha256.convert(sourceBytes).toString();
      final quarantineDirectory = Directory(
        path.join(supportDirectory.path, 'legacy-quarantine'),
      );
      await quarantineDirectory.create(recursive: true);
      final quarantineFile = File(
        path.join(quarantineDirectory.path, '$sourceFingerprint.sqlite'),
      );
      if (!quarantineFile.existsSync() ||
          await _fileSha256(quarantineFile) != sourceFingerprint ||
          quarantineFile.lengthSync() != sourceBytes.length) {
        if (quarantineFile.existsSync()) await quarantineFile.delete();
        await legacyFile.copy(quarantineFile.path);
      }
      if (await _fileSha256(quarantineFile) != sourceFingerprint ||
          quarantineFile.lengthSync() != sourceBytes.length) {
        throw StateError('legacy_quarantine_checksum_mismatch');
      }
      _fault(faultPoint, LegacyMigrationFaultPoint.afterQuarantineCopy);

      final manifest = _legacyManifest(quarantineFile.path);
      manifest['sourceBytes'] = sourceBytes.length;
      manifest['quarantineBytes'] = quarantineFile.lengthSync();
      manifest['checksumVerified'] = true;
      final now = DateTime.now().toUtc().toIso8601String();
      bootstrap.execute('BEGIN IMMEDIATE');
      bootstrap.execute(
        '''INSERT INTO legacy_quarantine (
          source_fingerprint, quarantine_path, manifest_json, state,
          claimed_scope_fingerprint, migrated_database_path, created_at, updated_at
        ) VALUES (?, ?, ?, 'quarantined', NULL, NULL, ?, ?)
        ON CONFLICT(source_fingerprint) DO UPDATE SET
          quarantine_path = excluded.quarantine_path,
          manifest_json = excluded.manifest_json,
          updated_at = excluded.updated_at''',
        [
          sourceFingerprint,
          quarantineFile.path,
          jsonEncode(manifest),
          now,
          now,
        ],
      );
      bootstrap.execute('COMMIT');
      _fault(faultPoint, LegacyMigrationFaultPoint.afterJournalCreation);

      final existing = bootstrap.select(
        'SELECT state, claimed_scope_fingerprint, migrated_database_path FROM legacy_quarantine WHERE source_fingerprint = ? LIMIT 1',
        [sourceFingerprint],
      ).first;
      final state = existing['state'] as String;
      final claimedScope = existing['claimed_scope_fingerprint'] as String?;
      if (claimedScope != null && claimedScope != scope.fingerprint) {
        // A legacy source may already be migrated to another personal scope.
        // It must not block a different user from opening a new empty scope,
        // and it must never make that user eligible to re-claim the source.
        return;
      }

      if (File(scopedPath).existsSync() &&
          claimedScope == scope.fingerprint &&
          state != 'migrated') {
        if (_isHealthySqlite(scopedPath)) {
          _setMigrationState(
            bootstrap,
            sourceFingerprint,
            'migrated',
            scope,
            scopedPath,
          );
          return;
        }
        throw StateError('legacy_scoped_database_corrupt');
      }
      if (state == 'migrated' && claimedScope == scope.fingerprint) return;
      if (File(scopedPath).existsSync() && claimedScope == null) return;

      if (claim == null) {
        if (allowEmptyScopeWithQuarantinedLegacy) return;
        throw LegacyDataQuarantined(
          sourceFingerprint: sourceFingerprint,
          tableCounts: Map<String, int>.from(manifest['tableCounts'] as Map),
        );
      }
      if (claim.scope.key != scope.key ||
          scope.kind != LocalDataScopeKind.personal) {
        throw const LegacyMigrationOwnershipMismatch();
      }

      _setMigrationState(
        bootstrap,
        sourceFingerprint,
        'claim_verified',
        scope,
        null,
      );

      final temporaryPath = '$scopedPath.migrating';
      final temporaryFile = File(temporaryPath);
      if (temporaryFile.existsSync()) await temporaryFile.delete();
      _setMigrationState(bootstrap, sourceFingerprint, 'copying', scope, null);
      _fault(faultPoint, LegacyMigrationFaultPoint.midCopy);
      await quarantineFile.copy(temporaryPath);
      _fault(faultPoint, LegacyMigrationFaultPoint.afterCopyBeforeVerification);
      _setMigrationState(bootstrap, sourceFingerprint, 'copied', scope, null);
      _migrateLegacyAttachments(
        databasePath: temporaryPath,
        sourceRoot: legacyAttachmentDirectory,
        targetRoot: Directory(
          path.join(supportDirectory.path, 'attachments', scope.fingerprint),
        ),
      );
      _setMigrationState(
        bootstrap,
        sourceFingerprint,
        'verifying',
        scope,
        null,
      );
      if (!_isHealthySqlite(temporaryPath)) {
        throw StateError('legacy_migration_verification_failed');
      }
      _fault(faultPoint, LegacyMigrationFaultPoint.afterVerification);
      _setMigrationState(
        bootstrap,
        sourceFingerprint,
        'ready_to_activate',
        scope,
        null,
      );
      await Directory(path.dirname(scopedPath)).create(recursive: true);
      await temporaryFile.rename(scopedPath);
      _fault(faultPoint, LegacyMigrationFaultPoint.afterFinalRename);
      _setMigrationState(
        bootstrap,
        sourceFingerprint,
        'activated',
        scope,
        scopedPath,
      );
      _fault(faultPoint, LegacyMigrationFaultPoint.beforeJournalMigrated);
      _setMigrationState(
        bootstrap,
        sourceFingerprint,
        'migrated',
        scope,
        scopedPath,
      );
      _fault(faultPoint, LegacyMigrationFaultPoint.afterJournalMigrated);
    } finally {
      bootstrap.dispose();
    }
  }

  static void _fault(
    LegacyMigrationFaultPoint? actual,
    LegacyMigrationFaultPoint expected,
  ) {
    if (actual == expected) {
      throw StateError('injected_migration_crash:${expected.name}');
    }
  }

  static void _setMigrationState(
    Database database,
    String fingerprint,
    String state,
    LocalDataScope scope,
    String? migratedPath,
  ) {
    database.execute(
      '''UPDATE legacy_quarantine SET state = ?, claimed_scope_fingerprint = ?,
        migrated_database_path = ?, updated_at = ? WHERE source_fingerprint = ?''',
      [
        state,
        scope.fingerprint,
        migratedPath,
        DateTime.now().toUtc().toIso8601String(),
        fingerprint,
      ],
    );
  }

  static bool _isHealthySqlite(String databasePath) {
    final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
    try {
      final result =
          database.select('PRAGMA integrity_check').first.values.first;
      return result == 'ok';
    } finally {
      database.dispose();
    }
  }

  static Future<String> _fileSha256(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  static Map<String, dynamic> _legacyManifest(String databasePath) {
    final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
    try {
      final names = database
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .map((row) => row['name'] as String);
      final counts = <String, int>{};
      for (final name in names) {
        final quoted = '"${name.replaceAll('"', '""')}"';
        counts[name] = (database
                .select('SELECT COUNT(*) AS count FROM $quoted')
                .first['count'] as num)
            .toInt();
      }
      return {'tableCounts': counts};
    } finally {
      database.dispose();
    }
  }

  static void _migrateLegacyAttachments({
    required String databasePath,
    required Directory sourceRoot,
    required Directory targetRoot,
  }) {
    if (!sourceRoot.existsSync()) return;
    targetRoot.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    try {
      final tableExists = database
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'english_lesson_work' LIMIT 1",
          )
          .isNotEmpty;
      if (!tableExists) return;
      final canonicalRoot = sourceRoot.resolveSymbolicLinksSync();
      final sourcePrefix = '${path.normalize(canonicalRoot)}${path.separator}';
      for (final row in database.select(
        'SELECT lesson_id, speaking_path FROM english_lesson_work WHERE speaking_path IS NOT NULL',
      )) {
        final sourcePath = row['speaking_path'] as String;
        final normalizedSource = path.normalize(File(sourcePath).absolute.path);
        final source = File(normalizedSource);
        if (!source.existsSync()) continue;
        String canonicalSourcePath;
        try {
          canonicalSourcePath = source.resolveSymbolicLinksSync();
        } on FileSystemException {
          throw StateError('legacy_attachment_canonicalization_failed');
        }
        if (!path.normalize(canonicalSourcePath).startsWith(sourcePrefix)) {
          throw StateError('legacy_attachment_outside_scope');
        }
        final canonicalSource = File(canonicalSourcePath);
        final collisionSafeName =
            '${sha256.convert(utf8.encode(path.normalize(canonicalSource.path))).toString().substring(0, 16)}_${path.basename(canonicalSource.path)}';
        final target = File(
          path.join(targetRoot.path, 'english-recordings', collisionSafeName),
        );
        target.parent.createSync(recursive: true);
        if (!target.existsSync()) canonicalSource.copySync(target.path);
        database.execute(
          'UPDATE english_lesson_work SET speaking_path = ? WHERE lesson_id = ?',
          [target.path, row['lesson_id']],
        );
      }
    } finally {
      database.dispose();
    }
  }

  void _initializeSchema() {
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS capture_records (id TEXT PRIMARY KEY, type TEXT NOT NULL, date TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL, synced_at TEXT)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS sync_outbox (record_id TEXT PRIMARY KEY, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, FOREIGN KEY(record_id) REFERENCES capture_records(id) ON DELETE CASCADE)''',
    );
    _ensureColumn(
        'sync_outbox', 'delivery_protocol', "TEXT NOT NULL DEFAULT 'v1'");
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS english_lesson_progress (lesson_id TEXT PRIMARY KEY, completed_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS english_lesson_work (lesson_id TEXT PRIMARY KEY, reading_done INTEGER NOT NULL DEFAULT 0, listening_done INTEGER NOT NULL DEFAULT 0, writing_text TEXT NOT NULL DEFAULT '', speaking_path TEXT, updated_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS english_learning_profile (id INTEGER PRIMARY KEY CHECK (id = 1), profile_json TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS sport_workout_progress (session_id TEXT PRIMARY KEY, session_number INTEGER NOT NULL, completed_at TEXT)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS sport_set_logs (session_id TEXT NOT NULL, session_number INTEGER NOT NULL, exercise_id TEXT NOT NULL, set_number INTEGER NOT NULL, weight_kg REAL NOT NULL DEFAULT 0, repetitions INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, PRIMARY KEY (session_id, exercise_id, set_number))''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS sport_training_profile (id INTEGER PRIMARY KEY CHECK (id = 1), profile_json TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS assistant_tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, original_text TEXT NOT NULL, due_at TEXT, notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'planned', created_at TEXT NOT NULL, completed_at TEXT)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS assistant_contacts (id TEXT PRIMARY KEY, name TEXT NOT NULL, name_normalized TEXT NOT NULL UNIQUE, phone TEXT, telegram_username TEXT, created_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS money_accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency TEXT NOT NULL, initial_balance REAL NOT NULL DEFAULT 0, color TEXT NOT NULL, created_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS money_categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, color TEXT NOT NULL, system INTEGER NOT NULL DEFAULT 1)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS money_transactions (id TEXT PRIMARY KEY, date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, counterparty TEXT NOT NULL DEFAULT '', category_id TEXT NOT NULL, purpose TEXT NOT NULL DEFAULT '', payment_method TEXT NOT NULL, account_id TEXT NOT NULL, transfer_to_account_id TEXT, recurring INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'completed', income_source TEXT, obligation_id TEXT, essential INTEGER NOT NULL DEFAULT 1, comment TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS capture_canonical_commits_v2 (capture_id TEXT PRIMARY KEY, intent_json TEXT NOT NULL, exact_minor_units TEXT NOT NULL, currency TEXT NOT NULL, state TEXT NOT NULL, created_at TEXT NOT NULL, undone_at TEXT)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS capture_money_projection_v2 (capture_id TEXT PRIMARY KEY, money_transaction_id TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL, undone_at TEXT)''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS capture_canonical_sync_outbox_v2 (capture_id TEXT PRIMARY KEY, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, synced_at TEXT)''',
    );
    _ensureColumn('capture_canonical_sync_outbox_v2', 'state',
        "TEXT NOT NULL DEFAULT 'pending'");
    _ensureColumn('capture_canonical_sync_outbox_v2', 'error_code', 'TEXT');
    _ensureColumn(
        'capture_canonical_sync_outbox_v2', 'last_attempt_at', 'TEXT');
    _ensureColumn(
        'capture_canonical_sync_outbox_v2', 'next_attempt_at', 'TEXT');
    _ensureColumn(
      'capture_canonical_sync_outbox_v2',
      'delivery_protocol',
      "TEXT NOT NULL DEFAULT 'v2'",
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS money_obligations (id TEXT PRIMARY KEY, name TEXT NOT NULL, total_amount REAL NOT NULL, paid_amount REAL NOT NULL DEFAULT 0, currency TEXT NOT NULL, due_date TEXT NOT NULL, recurrence TEXT, comment TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS money_recurring (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, counterparty TEXT NOT NULL DEFAULT '', category_id TEXT NOT NULL, account_id TEXT NOT NULL, next_date TEXT NOT NULL, recurrence TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active')''',
    );
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS app_preferences (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    );
    _db.execute('''CREATE TABLE IF NOT EXISTS scope_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        scope_kind TEXT NOT NULL,
        scope_fingerprint TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
    _db.execute('''CREATE TABLE IF NOT EXISTS capture_shadow_v2 (
        capture_id TEXT PRIMARY KEY,
        envelope_json TEXT NOT NULL,
        diagnostics_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        shadow_only INTEGER NOT NULL DEFAULT 1
      )''');
    _db.execute('''CREATE TABLE IF NOT EXISTS capture_shadow_projection_v2 (
        capture_id TEXT PRIMARY KEY,
        candidate TEXT NOT NULL,
        decision_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        shadow_only INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(capture_id) REFERENCES capture_shadow_v2(capture_id)
      )''');
    _ensureColumn('money_transactions', 'capture_id', 'TEXT');
    _ensureColumn(
      'money_transactions',
      'source',
      "TEXT NOT NULL DEFAULT 'manual'",
    );
    _ensureColumn('money_transactions', 'minor_units', 'TEXT');
    _db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS money_transactions_canonical_capture_unique ON money_transactions(capture_id) WHERE capture_id IS NOT NULL",
    );
  }

  void _ensureColumn(String table, String column, String definition) {
    final columns = _db.select('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void _validateScopeMetadata() {
    final rows = _db.select(
      'SELECT scope_kind, scope_fingerprint FROM scope_metadata WHERE id = 1',
    );
    if (rows.isEmpty) {
      _db.execute(
        'INSERT INTO scope_metadata (id, scope_kind, scope_fingerprint, created_at) VALUES (1, ?, ?, ?)',
        [
          scope.kind.name,
          scope.fingerprint,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return;
    }
    final row = rows.first;
    if (row['scope_kind'] != scope.kind.name ||
        row['scope_fingerprint'] != scope.fingerprint) {
      throw StateError('local_scope_metadata_mismatch');
    }
  }

  Future<Directory> attachmentDirectory(String kind) async {
    final normalized = kind.trim();
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'must use lowercase safe segments',
      );
    }
    final directory = Directory(path.join(_attachmentsRoot.path, normalized));
    await directory.create(recursive: true);
    return directory;
  }

  dynamic preference(String key) {
    final rows = _db.select(
      'SELECT value_json FROM app_preferences WHERE key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['value_json'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePreference(String key, Object? value) async {
    _db.execute(
      '''INSERT OR REPLACE INTO app_preferences (key, value_json, updated_at) VALUES (?, ?, ?)''',
      [key, jsonEncode(value), DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<void> saveCaptureShadowV2(
    String captureId,
    String envelopeJson,
    String diagnosticsJson, {
    String? projectionCandidate,
    String? projectionDecisionJson,
  }) async {
    _db.execute(
      '''INSERT OR REPLACE INTO capture_shadow_v2
         (capture_id, envelope_json, diagnostics_json, created_at, shadow_only)
         VALUES (?, ?, ?, ?, 1)''',
      [
        captureId,
        envelopeJson,
        diagnosticsJson,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    if (projectionCandidate != null && projectionDecisionJson != null) {
      _db.execute(
        '''INSERT OR REPLACE INTO capture_shadow_projection_v2
           (capture_id, candidate, decision_json, created_at, shadow_only)
           VALUES (?, ?, ?, ?, 1)''',
        [
          captureId,
          projectionCandidate,
          projectionDecisionJson,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  }

  int captureShadowV2Count() => (_db
          .select('SELECT COUNT(*) AS count FROM capture_shadow_v2')
          .first['count'] as num)
      .toInt();

  int syncOutboxCount() =>
      (_db.select('SELECT COUNT(*) AS count FROM sync_outbox').first['count']
              as num)
          .toInt();

  List<Map<String, Object?>> captureShadowV2Rows() => _db
      .select(
        'SELECT capture_id, envelope_json, diagnostics_json, shadow_only FROM capture_shadow_v2 ORDER BY created_at',
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  bool hasMeaningfulUserData() {
    final checks = <String>[
      'capture_records',
      'english_learning_profile',
      'sport_training_profile',
      'money_transactions',
      'money_obligations',
      'assistant_tasks',
    ];
    for (final table in checks) {
      final count = _db.select('SELECT COUNT(*) AS count FROM $table').first;
      if (((count['count'] as num?)?.toInt() ?? 0) > 0) return true;
    }
    return false;
  }

  void _seedMoneyDefaults() {
    if (_db.select('SELECT id FROM money_accounts LIMIT 1').isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final account in const [
        ['cash-main', 'Наличные', 'cash', 'UZS', '#F0B429'],
        ['card-main', 'Карта', 'card', 'UZS', '#60A5FA'],
      ]) {
        _db.execute(
          'INSERT INTO money_accounts (id, name, type, currency, initial_balance, color, created_at) VALUES (?, ?, ?, ?, 0, ?, ?)',
          [account[0], account[1], account[2], account[3], account[4], now],
        );
      }
    }
    if (_db.select('SELECT id FROM money_categories LIMIT 1').isEmpty) {
      const categories = [
        ['salary', 'Зарплата', 'income', '#34D399'],
        ['freelance', 'Фриланс', 'income', '#60A5FA'],
        ['sales-income', 'Продажи', 'income', '#A78BFA'],
        ['other-income', 'Другое', 'income', '#94A3B8'],
        ['groceries', 'Продукты', 'expense', '#FB923C'],
        ['eating-out', 'Общепит', 'expense', '#F97316'],
        ['cola-drinks', 'Кола и напитки', 'expense', '#FACC15'],
        ['cigarettes', 'Сигареты', 'expense', '#FB7185'],
        ['transport', 'Транспорт', 'expense', '#60A5FA'],
        ['taxi', 'Такси', 'expense', '#38BDF8'],
        ['family', 'Семья', 'expense', '#F472B6'],
        ['housing', 'Жильё', 'expense', '#8B5CF6'],
        ['health', 'Здоровье', 'expense', '#34D399'],
        ['entertainment', 'Развлечения', 'expense', '#14B8A6'],
        ['subscriptions', 'Подписки', 'expense', '#C084FC'],
        ['business', 'Бизнес', 'expense', '#FACC15'],
        ['other-expense', 'Другое', 'expense', '#94A3B8'],
      ];
      for (final category in categories) {
        _db.execute(
          'INSERT INTO money_categories (id, name, kind, color, system) VALUES (?, ?, ?, ?, 1)',
          category,
        );
      }
    }
  }

  Future<void> save(CaptureRecord record) async {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'INSERT OR REPLACE INTO capture_records (id, type, date, payload_json, created_at, synced_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          record.id,
          record.draft.type.wireName,
          record.draft.date,
          jsonEncode(record.draft.toJson()),
          record.createdAt.toUtc().toIso8601String(),
          record.syncedAt?.toUtc().toIso8601String(),
        ],
      );
      _db.execute(
        "INSERT OR REPLACE INTO sync_outbox (record_id, attempts, last_error, delivery_protocol) VALUES (?, 0, NULL, 'v1')",
        [record.id],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<bool> saveIfAbsent(CaptureRecord record) async {
    final exists = _db.select(
      'SELECT id FROM capture_records WHERE id = ? LIMIT 1',
      [record.id],
    ).isNotEmpty;
    if (exists) return false;
    await save(record);
    return true;
  }

  Future<bool> saveImportedRaw({
    required String id,
    required String module,
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS imported_backup_rows (id TEXT PRIMARY KEY, module TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL, imported_at TEXT NOT NULL)''',
    );
    final result = _db.select(
      'SELECT id FROM imported_backup_rows WHERE id = ? LIMIT 1',
      [id],
    );
    if (result.isNotEmpty) return false;
    _db.execute(
      'INSERT INTO imported_backup_rows (id, module, kind, payload_json, imported_at) VALUES (?, ?, ?, ?, ?)',
      [
        id,
        module,
        kind,
        jsonEncode(payload),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return true;
  }

  int importedRawCount() {
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS imported_backup_rows (id TEXT PRIMARY KEY, module TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL, imported_at TEXT NOT NULL)''',
    );
    return (_db
            .select('SELECT COUNT(*) AS count FROM imported_backup_rows')
            .first['count'] as int?) ??
        0;
  }

  List<CaptureRecord> pending() => _rows(
        '''SELECT r.* FROM capture_records r JOIN sync_outbox o ON o.record_id = r.id WHERE r.synced_at IS NULL AND o.delivery_protocol = 'v1' ORDER BY r.created_at ASC''',
      );
  List<CaptureRecord> all() =>
      _rows('SELECT * FROM capture_records ORDER BY created_at DESC');

  Future<void> markSynced(Iterable<String> ids) async {
    _db.execute('BEGIN');
    try {
      for (final id in ids) {
        _db.execute('UPDATE capture_records SET synced_at = ? WHERE id = ?', [
          DateTime.now().toUtc().toIso8601String(),
          id,
        ]);
        _db.execute('DELETE FROM sync_outbox WHERE record_id = ?', [id]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, int> todaySummary() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = _db.select(
      'SELECT type, COUNT(*) AS count FROM capture_records WHERE date = ? GROUP BY type',
      [today],
    );
    return {for (final row in rows) row['type'] as String: row['count'] as int};
  }

  Future<void> saveAssistantTask(AssistantTask task) async {
    _db.execute(
      '''INSERT OR REPLACE INTO assistant_tasks (id, title, original_text, due_at, notes, status, created_at, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        task.id,
        task.title,
        task.originalText,
        task.dueAt?.toUtc().toIso8601String(),
        task.notes,
        task.status,
        task.createdAt.toUtc().toIso8601String(),
        null,
      ],
    );
  }

  List<AssistantTask> assistantTasks() => [
        for (final row in _db.select(
          'SELECT * FROM assistant_tasks ORDER BY COALESCE(due_at, created_at) ASC',
        ))
          AssistantTask(
            id: row['id'] as String,
            title: row['title'] as String,
            originalText: row['original_text'] as String,
            dueAt: row['due_at'] == null
                ? null
                : DateTime.tryParse(row['due_at'] as String),
            notes: row['notes'] as String,
            status: row['status'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
      ];

  Future<void> completeAssistantTask(String id) async {
    _db.execute(
      'UPDATE assistant_tasks SET status = ?, completed_at = ? WHERE id = ?',
      ['completed', DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> saveAssistantContact(AssistantContact contact) async {
    _db.execute(
      '''INSERT OR REPLACE INTO assistant_contacts (id, name, name_normalized, phone, telegram_username, created_at) VALUES (?, ?, ?, ?, ?, ?)''',
      [
        contact.id,
        contact.name,
        _normalizeContactName(contact.name),
        contact.phone,
        contact.telegramUsername,
        contact.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  AssistantContact? assistantContactByName(String name) {
    final rows = _db.select(
      'SELECT * FROM assistant_contacts WHERE name_normalized = ? LIMIT 1',
      [_normalizeContactName(name)],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return AssistantContact(
      id: row['id'] as String,
      name: row['name'] as String,
      phone: row['phone'] as String?,
      telegramUsername: row['telegram_username'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  List<AssistantContact> assistantContacts() => [
        for (final row in _db.select(
          'SELECT * FROM assistant_contacts ORDER BY name ASC',
        ))
          AssistantContact(
            id: row['id'] as String,
            name: row['name'] as String,
            phone: row['phone'] as String?,
            telegramUsername: row['telegram_username'] as String?,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
      ];

  String _normalizeContactName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'["«»]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Set<String> completedEnglishLessons() => {
        for (final row in _db.select('''SELECT progress.lesson_id
         FROM english_lesson_progress progress
         INNER JOIN english_lesson_work work ON work.lesson_id = progress.lesson_id
         WHERE work.reading_done = 1
           AND work.listening_done = 1
           AND TRIM(work.writing_text) <> ''
           AND work.speaking_path IS NOT NULL''')) row['lesson_id'] as String,
      };

  Future<void> setEnglishLessonCompleted(
    String lessonId,
    bool completed,
  ) async {
    if (completed) {
      _db.execute(
        'INSERT OR REPLACE INTO english_lesson_progress (lesson_id, completed_at) VALUES (?, ?)',
        [lessonId, DateTime.now().toUtc().toIso8601String()],
      );
      return;
    }
    _db.execute('DELETE FROM english_lesson_progress WHERE lesson_id = ?', [
      lessonId,
    ]);
  }

  EnglishLessonProgress englishLessonProgress(String lessonId) {
    final rows = _db.select(
      'SELECT reading_done, listening_done, writing_text, speaking_path FROM english_lesson_work WHERE lesson_id = ? LIMIT 1',
      [lessonId],
    );
    if (rows.isEmpty) return const EnglishLessonProgress.empty();
    final row = rows.first;
    return EnglishLessonProgress(
      readingDone: row['reading_done'] == 1,
      listeningDone: row['listening_done'] == 1,
      writingText: row['writing_text'] as String? ?? '',
      speakingPath: row['speaking_path'] as String?,
    );
  }

  Future<void> saveEnglishLessonProgress(
    String lessonId, {
    required bool readingDone,
    required bool listeningDone,
    required String writingText,
    required String? speakingPath,
  }) async {
    _db.execute(
      '''INSERT OR REPLACE INTO english_lesson_work (lesson_id, reading_done, listening_done, writing_text, speaking_path, updated_at) VALUES (?, ?, ?, ?, ?, ?)''',
      [
        lessonId,
        readingDone ? 1 : 0,
        listeningDone ? 1 : 0,
        writingText,
        speakingPath,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// Optional English intake kept separately from lesson records. Old local
  /// databases stay valid and the questionnaire can evolve as JSON.
  String? englishLearningProfileJson() {
    final rows = _db.select(
      'SELECT profile_json FROM english_learning_profile WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['profile_json'] as String;
  }

  Future<void> saveEnglishLearningProfileJson(String profileJson) async {
    _db.execute(
      '''INSERT OR REPLACE INTO english_learning_profile (id, profile_json, updated_at) VALUES (1, ?, ?)''',
      [profileJson, DateTime.now().toUtc().toIso8601String()],
    );
  }

  Set<String> completedSportWorkouts() => {
        for (final row in _db.select(
          'SELECT session_id FROM sport_workout_progress WHERE completed_at IS NOT NULL',
        ))
          row['session_id'] as String,
      };

  /// The Sport intake is isolated from generic captures so an old database or
  /// backup continues to work unchanged. JSON lets the questionnaire evolve
  /// without overwriting a person's previous answers.
  String? sportTrainingProfileJson() {
    final rows = _db.select(
      'SELECT profile_json FROM sport_training_profile WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['profile_json'] as String;
  }

  Future<void> saveSportTrainingProfileJson(String profileJson) async {
    _db.execute(
      '''INSERT OR REPLACE INTO sport_training_profile (id, profile_json, updated_at) VALUES (1, ?, ?)''',
      [profileJson, DateTime.now().toUtc().toIso8601String()],
    );
  }

  List<SportSetLog> allSportSetLogs() => [
        for (final row in _db.select(
          'SELECT * FROM sport_set_logs ORDER BY session_number ASC, exercise_id ASC, set_number ASC',
        ))
          _sportSetLog(row),
      ];

  List<SportSetLog> sportSetLogsFor(String sessionId) => [
        for (final row in _db.select(
          'SELECT * FROM sport_set_logs WHERE session_id = ? ORDER BY set_number ASC',
          [sessionId],
        ))
          _sportSetLog(row),
      ];

  Future<void> saveSportSetLog({
    required String sessionId,
    required int sessionNumber,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int repetitions,
    required bool completed,
  }) async {
    _db.execute(
      '''INSERT OR REPLACE INTO sport_set_logs (session_id, session_number, exercise_id, set_number, weight_kg, repetitions, completed, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        sessionId,
        sessionNumber,
        exerciseId,
        setNumber,
        weightKg,
        repetitions,
        completed ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> setSportWorkoutCompleted(
    String sessionId,
    int sessionNumber,
    bool completed,
  ) async {
    _db.execute(
      '''INSERT OR REPLACE INTO sport_workout_progress (session_id, session_number, completed_at) VALUES (?, ?, ?)''',
      [
        sessionId,
        sessionNumber,
        completed ? DateTime.now().toUtc().toIso8601String() : null,
      ],
    );
  }

  List<MoneyAccount> moneyAccounts() => [
        for (final row in _db.select(
          'SELECT * FROM money_accounts ORDER BY created_at ASC',
        ))
          MoneyAccount(
            id: row['id'] as String,
            name: row['name'] as String,
            type: moneyAccountTypeFrom(row['type'] as String),
            currency: row['currency'] as String,
            initialBalance: (row['initial_balance'] as num).toDouble(),
            color: row['color'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
      ];

  List<MoneyCategory> moneyCategories() => [
        for (final row in _db.select(
          'SELECT * FROM money_categories ORDER BY kind ASC, name ASC',
        ))
          MoneyCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            kind: moneyCategoryKindFrom(row['kind'] as String),
            color: row['color'] as String,
            system: row['system'] == 1,
          ),
      ];

  List<MoneyTransaction> moneyTransactions() => [
        for (final row in _db.select(
          'SELECT * FROM money_transactions ORDER BY date DESC, created_at DESC',
        ))
          MoneyTransaction(
            id: row['id'] as String,
            date: row['date'] as String,
            type: moneyTransactionTypeFrom(row['type'] as String),
            amount: (row['amount'] as num).toDouble(),
            currency: row['currency'] as String,
            counterparty: row['counterparty'] as String,
            categoryId: row['category_id'] as String,
            purpose: row['purpose'] as String,
            paymentMethod:
                moneyPaymentMethodFrom(row['payment_method'] as String),
            accountId: row['account_id'] as String,
            transferToAccountId: row['transfer_to_account_id'] as String?,
            recurring: row['recurring'] == 1,
            status: moneyTransactionStatusFrom(row['status'] as String),
            incomeSource: row['income_source'] as String?,
            obligationId: row['obligation_id'] as String?,
            essential: row['essential'] == 1,
            comment: row['comment'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
      ];

  Future<void> saveMoneyAccount(MoneyAccount account) async {
    _db.execute(
      'INSERT OR REPLACE INTO money_accounts (id, name, type, currency, initial_balance, color, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        account.id,
        account.name,
        _moneyEnum(account.type),
        account.currency,
        account.initialBalance,
        account.color,
        account.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> saveMoneyTransaction(MoneyTransaction transaction) async {
    _db.execute(
      '''INSERT INTO money_transactions (id, date, type, amount, currency, counterparty, category_id, purpose, payment_method, account_id, transfer_to_account_id, recurring, status, income_source, obligation_id, essential, comment, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        date = excluded.date, type = excluded.type, amount = excluded.amount,
        currency = excluded.currency, counterparty = excluded.counterparty,
        category_id = excluded.category_id, purpose = excluded.purpose,
        payment_method = excluded.payment_method, account_id = excluded.account_id,
        transfer_to_account_id = excluded.transfer_to_account_id,
        recurring = excluded.recurring, status = excluded.status,
        income_source = excluded.income_source, obligation_id = excluded.obligation_id,
        essential = excluded.essential, comment = excluded.comment,
        created_at = excluded.created_at''',
      [
        transaction.id,
        transaction.date,
        _moneyEnum(transaction.type),
        transaction.amount,
        transaction.currency,
        transaction.counterparty,
        transaction.categoryId,
        transaction.purpose,
        _moneyEnum(transaction.paymentMethod),
        transaction.accountId,
        transaction.transferToAccountId,
        transaction.recurring ? 1 : 0,
        _moneyEnum(transaction.status),
        transaction.incomeSource,
        transaction.obligationId,
        transaction.essential ? 1 : 0,
        transaction.comment,
        transaction.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  String? canonicalMoneyTransactionId(String captureId) {
    final rows = _db.select(
      'SELECT money_transaction_id FROM capture_money_projection_v2 WHERE capture_id = ? AND undone_at IS NULL',
      [captureId],
    );
    return rows.isEmpty ? null : rows.single['money_transaction_id'] as String;
  }

  Set<String> activeCanonicalMoneyCaptureIds() => {
        for (final row in _db.select(
          'SELECT capture_id FROM capture_money_projection_v2 WHERE undone_at IS NULL',
        ))
          row['capture_id'] as String,
      };

  /// Keeps a retired canonical projection from falling back to the legacy
  /// synthetic mapper after a delete. It is an audit/dedup marker, not an
  /// active Money projection.
  Set<String> canonicalMoneyCaptureIdsForSyntheticExclusion() => {
        for (final row in _db.select(
          'SELECT capture_id FROM capture_money_projection_v2',
        ))
          row['capture_id'] as String,
      };

  int canonicalMoneyCommitCount({String? captureId}) => (_db
          .select(
            captureId == null
                ? 'SELECT COUNT(*) AS count FROM capture_canonical_commits_v2'
                : 'SELECT COUNT(*) AS count FROM capture_canonical_commits_v2 WHERE capture_id = ?',
            captureId == null ? const [] : [captureId],
          )
          .single['count'] as num)
      .toInt();

  int activeCanonicalMoneyProjectionCount({String? captureId}) => (_db
          .select(
            captureId == null
                ? 'SELECT COUNT(*) AS count FROM capture_money_projection_v2 WHERE undone_at IS NULL'
                : 'SELECT COUNT(*) AS count FROM capture_money_projection_v2 WHERE capture_id = ? AND undone_at IS NULL',
            captureId == null ? const [] : [captureId],
          )
          .single['count'] as num)
      .toInt();

  int canonicalMoneyRowCount({String? captureId}) => (_db
          .select(
            captureId == null
                ? "SELECT COUNT(*) AS count FROM money_transactions WHERE source = 'canonical_capture'"
                : 'SELECT COUNT(*) AS count FROM money_transactions WHERE capture_id = ?',
            captureId == null ? const [] : [captureId],
          )
          .single['count'] as num)
      .toInt();

  List<Map<String, Object?>> pendingCanonicalMoneySync({DateTime? now}) {
    final effectiveNow = (now ?? DateTime.now()).toUtc().toIso8601String();
    return [
      for (final row in _db.select(
          '''SELECT c.capture_id, c.intent_json, c.exact_minor_units, c.currency, m.date, m.type, m.purpose, m.payment_method, m.account_id, m.category_id FROM capture_canonical_commits_v2 c JOIN money_transactions m ON m.capture_id = c.capture_id LEFT JOIN capture_canonical_sync_outbox_v2 o ON o.capture_id = c.capture_id WHERE c.state = 'committed_local' AND (o.capture_id IS NULL OR (o.delivery_protocol = 'v2' AND o.state IN ('pending', 'retryable_failure') AND (o.next_attempt_at IS NULL OR o.next_attempt_at <= ?))) ORDER BY c.created_at ASC''',
          [effectiveNow]))
        Map<String, Object?>.from(row),
    ];
  }

  CanonicalMoneySyncStatus canonicalMoneySyncStatus() {
    final rows = _db.select(
        '''SELECT state, COUNT(*) AS count, MIN(next_attempt_at) AS next_attempt_at FROM capture_canonical_sync_outbox_v2 WHERE delivery_protocol = 'v2' GROUP BY state''');
    var pending = 0;
    var retrying = 0;
    var permanentFailures = 0;
    var acknowledged = 0;
    DateTime? nextAttemptAt;
    for (final row in rows) {
      final count = (row['count'] as num).toInt();
      switch (row['state']) {
        case 'pending':
        case 'sending':
          pending += count;
        case 'retryable_failure':
          retrying += count;
          final value = row['next_attempt_at'] as String?;
          final parsed = value == null ? null : DateTime.tryParse(value);
          if (parsed != null &&
              (nextAttemptAt == null || parsed.isBefore(nextAttemptAt))) {
            nextAttemptAt = parsed;
          }
        case 'permanent_failure':
          permanentFailures += count;
        case 'acknowledged':
          acknowledged += count;
      }
    }
    return CanonicalMoneySyncStatus(
      pending: pending,
      retrying: retrying,
      permanentFailures: permanentFailures,
      acknowledged: acknowledged,
      nextAttemptAt: nextAttemptAt,
    );
  }

  void markCanonicalMoneySending(String captureId, {DateTime? now}) {
    _db.execute(
      '''INSERT INTO capture_canonical_sync_outbox_v2 (capture_id, attempts, state, last_attempt_at, next_attempt_at, delivery_protocol) VALUES (?, 1, 'sending', ?, NULL, 'v2') ON CONFLICT(capture_id) DO UPDATE SET attempts = capture_canonical_sync_outbox_v2.attempts + 1, state = 'sending', last_attempt_at = excluded.last_attempt_at, next_attempt_at = NULL''',
      [captureId, (now ?? DateTime.now()).toUtc().toIso8601String()],
    );
  }

  Duration _canonicalRetryDelay(String captureId, int attempts) {
    final exponent = attempts.clamp(1, 8);
    final baseSeconds = 1 << exponent;
    final jitterMilliseconds =
        captureId.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 1000;
    return Duration(
        seconds: baseSeconds > 300 ? 300 : baseSeconds,
        milliseconds: jitterMilliseconds);
  }

  void markCanonicalMoneyRetryableFailure(
    String captureId, {
    required String errorCode,
    DateTime? now,
  }) {
    final current = _db.select(
      'SELECT attempts FROM capture_canonical_sync_outbox_v2 WHERE capture_id = ? LIMIT 1',
      [captureId],
    );
    final attempts =
        current.isEmpty ? 1 : (current.single['attempts'] as num).toInt();
    final timestamp = (now ?? DateTime.now()).toUtc();
    final nextAttempt =
        timestamp.add(_canonicalRetryDelay(captureId, attempts));
    _db.execute(
      '''INSERT INTO capture_canonical_sync_outbox_v2 (capture_id, attempts, state, error_code, last_attempt_at, next_attempt_at, delivery_protocol) VALUES (?, ?, 'retryable_failure', ?, ?, ?, 'v2') ON CONFLICT(capture_id) DO UPDATE SET state = 'retryable_failure', error_code = excluded.error_code, last_attempt_at = excluded.last_attempt_at, next_attempt_at = excluded.next_attempt_at''',
      [
        captureId,
        attempts,
        errorCode,
        timestamp.toIso8601String(),
        nextAttempt.toIso8601String()
      ],
    );
  }

  void markCanonicalMoneyPermanentFailure(
    String captureId, {
    required String errorCode,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO capture_canonical_sync_outbox_v2 (capture_id, attempts, state, error_code, last_attempt_at, next_attempt_at, delivery_protocol) VALUES (?, 1, 'permanent_failure', ?, ?, NULL, 'v2') ON CONFLICT(capture_id) DO UPDATE SET state = 'permanent_failure', error_code = excluded.error_code, last_attempt_at = excluded.last_attempt_at, next_attempt_at = NULL''',
      [captureId, errorCode, timestamp],
    );
  }

  int requeueCanonicalMoneyFailures() {
    _db.execute(
      "UPDATE capture_canonical_sync_outbox_v2 SET state = 'pending', error_code = NULL, next_attempt_at = NULL WHERE delivery_protocol = 'v2' AND state = 'permanent_failure'",
    );
    return _db.getUpdatedRows();
  }

  Future<void> markCanonicalMoneySynced(Iterable<String> captureIds) async {
    for (final id in captureIds) {
      _db.execute(
        '''INSERT INTO capture_canonical_sync_outbox_v2 (capture_id, attempts, state, synced_at, last_error, next_attempt_at, delivery_protocol) VALUES (?, 1, 'acknowledged', ?, NULL, NULL, 'v2') ON CONFLICT(capture_id) DO UPDATE SET state = 'acknowledged', synced_at = excluded.synced_at, last_error = NULL, error_code = NULL, next_attempt_at = NULL''',
        [id, DateTime.now().toUtc().toIso8601String()],
      );
    }
  }

  Future<String> commitCanonicalMoney(
    CanonicalMoneyCommitInput input, {
    String? failAt,
  }) async {
    final scale = switch (input.currency) {
      'UZS' => 0,
      'USD' || 'EUR' => 2,
      _ => throw ArgumentError('unsupported_currency'),
    };
    final minor = BigInt.tryParse(input.minorUnits);
    if (minor == null || minor <= BigInt.zero)
      throw ArgumentError('invalid_minor_units');
    final divisor = BigInt.from(10).pow(scale);
    final amount = minor.toDouble() / divisor.toDouble();
    if (!amount.isFinite ||
        BigInt.from((amount * divisor.toDouble()).round()) != minor)
      throw ArgumentError('unsafe_legacy_real_compatibility');
    final id = 'money-v2-${input.captureId}';
    final now = DateTime.now().toUtc().toIso8601String();
    void inject(String point) {
      if (failAt == point) throw StateError('injected_failure:$point');
    }

    inject('before_canonical_evidence');
    _db.execute('BEGIN IMMEDIATE');
    try {
      // The lookup must be inside the write transaction: a concurrent caller
      // observes the already committed projection instead of surfacing UNIQUE.
      final existing = canonicalMoneyTransactionId(input.captureId);
      if (existing != null) {
        _db.execute('COMMIT');
        return existing;
      }
      _db.execute(
        'INSERT INTO capture_canonical_commits_v2 (capture_id,intent_json,exact_minor_units,currency,state,created_at) VALUES (?,?,?,?,?,?)',
        [
          input.captureId,
          input.intentJson,
          input.minorUnits,
          input.currency,
          'committing',
          now,
        ],
      );
      inject('after_canonical_evidence');
      inject('before_money_insert');
      _db.execute(
        '''INSERT INTO money_transactions (id,date,type,amount,currency,counterparty,category_id,purpose,payment_method,account_id,recurring,status,essential,comment,created_at,capture_id,source,minor_units) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        [
          id,
          input.date,
          input.direction,
          amount,
          input.currency,
          '',
          input.categoryId,
          input.description,
          input.paymentMethod,
          input.accountId,
          0,
          'completed',
          1,
          'Created from canonical capture',
          now,
          input.captureId,
          'canonical_capture',
          input.minorUnits,
        ],
      );
      inject('after_money_insert');
      inject('before_projection_insert');
      _db.execute(
        'INSERT INTO capture_money_projection_v2 (capture_id,money_transaction_id,created_at) VALUES (?,?,?)',
        [input.captureId, id, now],
      );
      inject('after_projection_insert');
      inject('before_committed_local');
      _db.execute(
        "UPDATE capture_canonical_commits_v2 SET state = 'committed_local' WHERE capture_id = ?",
        [input.captureId],
      );
      _db.execute(
        'INSERT OR IGNORE INTO capture_canonical_sync_outbox_v2 (capture_id) VALUES (?)',
        [input.captureId],
      );
      inject('before_sqlite_commit');
      _db.execute('COMMIT');
      return id;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> deleteMoneyTransaction(String id) async {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final projection = _db.select(
        'SELECT capture_id FROM capture_money_projection_v2 WHERE money_transaction_id = ? AND undone_at IS NULL',
        [id],
      );
      _db.execute('DELETE FROM money_transactions WHERE id = ?', [id]);
      if (projection.isNotEmpty) {
        final captureId = projection.single['capture_id'] as String;
        final now = DateTime.now().toUtc().toIso8601String();
        _db.execute(
          'UPDATE capture_money_projection_v2 SET undone_at = ? WHERE capture_id = ?',
          [now, captureId],
        );
        _db.execute(
          "UPDATE capture_canonical_commits_v2 SET state = 'undone', undone_at = ? WHERE capture_id = ?",
          [now, captureId],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> saveMoneyObligation(MoneyObligation obligation) async {
    _db.execute(
      'INSERT OR REPLACE INTO money_obligations (id, name, total_amount, paid_amount, currency, due_date, recurrence, comment, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        obligation.id,
        obligation.name,
        obligation.totalAmount,
        obligation.paidAmount,
        obligation.currency,
        obligation.dueDate,
        obligation.recurrence == null
            ? null
            : _moneyEnum(obligation.recurrence!),
        obligation.comment,
        obligation.status,
      ],
    );
  }

  List<MoneyObligation> moneyObligations() => [
        for (final row in _db.select(
          'SELECT * FROM money_obligations ORDER BY due_date ASC',
        ))
          MoneyObligation(
            id: row['id'] as String,
            name: row['name'] as String,
            totalAmount: (row['total_amount'] as num).toDouble(),
            paidAmount: (row['paid_amount'] as num).toDouble(),
            currency: row['currency'] as String,
            dueDate: row['due_date'] as String,
            recurrence: moneyRecurrenceFrom(row['recurrence'] as String?),
            comment: row['comment'] as String,
            status: row['status'] as String,
          ),
      ];

  Future<void> deleteMoneyObligation(String id) async {
    _db.execute('DELETE FROM money_obligations WHERE id = ?', [id]);
  }

  List<MoneyRecurringTemplate> moneyRecurring() => [
        for (final row in _db.select(
          'SELECT * FROM money_recurring ORDER BY next_date ASC',
        ))
          MoneyRecurringTemplate(
            id: row['id'] as String,
            name: row['name'] as String,
            type: moneyTransactionTypeFrom(row['type'] as String),
            amount: (row['amount'] as num).toDouble(),
            currency: row['currency'] as String,
            counterparty: row['counterparty'] as String,
            categoryId: row['category_id'] as String,
            accountId: row['account_id'] as String,
            nextDate: row['next_date'] as String,
            recurrence: moneyRecurrenceFrom(row['recurrence'] as String) ??
                MoneyRecurrence.monthly,
            status: row['status'] as String,
          ),
      ];

  Future<void> saveMoneyRecurring(MoneyRecurringTemplate item) async {
    _db.execute(
      'INSERT OR REPLACE INTO money_recurring (id, name, type, amount, currency, counterparty, category_id, account_id, next_date, recurrence, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        item.id,
        item.name,
        _moneyEnum(item.type),
        item.amount,
        item.currency,
        item.counterparty,
        item.categoryId,
        item.accountId,
        item.nextDate,
        _moneyEnum(item.recurrence),
        item.status,
      ],
    );
  }

  Future<void> deleteMoneyRecurring(String id) async {
    _db.execute('DELETE FROM money_recurring WHERE id = ?', [id]);
  }

  String _moneyEnum(Object value) => value.toString().split('.').last;

  SportSetLog _sportSetLog(Row row) => SportSetLog(
        sessionId: row['session_id'] as String,
        sessionNumber: row['session_number'] as int,
        exerciseId: row['exercise_id'] as String,
        setNumber: row['set_number'] as int,
        weightKg: (row['weight_kg'] as num).toDouble(),
        repetitions: row['repetitions'] as int,
        completed: row['completed'] == 1,
      );

  List<CaptureRecord> _rows(String query) => [
        for (final row in _db.select(query)) _record(row),
      ];
  CaptureRecord _record(Row row) {
    final data =
        jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    final type = CaptureType.values.firstWhere(
      (item) => item.wireName == row['type'],
    );
    return CaptureRecord(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      syncedAt: row['synced_at'] == null
          ? null
          : DateTime.parse(row['synced_at'] as String),
      draft: CaptureDraft(
        type: type,
        originalText: data['originalText'] as String? ?? '',
        date: data['date'] as String? ?? '',
        amount: (data['amount'] as num?)?.toDouble(),
        currency: data['currency'] as String? ?? 'UZS',
        category: data['category'] as String?,
        paymentMethod: data['paymentMethod'] as String?,
        description: data['description'] as String?,
        company: data['company'] as String?,
        result: data['result'] as String?,
        whatSaid: data['whatSaid'] as String?,
        offered: data['offered'] as String?,
        nextStep: data['nextStep'] as String?,
        followUpDate: data['followUpDate'] as String?,
        durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
        activityType: data['activityType'] as String?,
        completedTask: data['completedTask'] as String?,
        comment: data['comment'] as String?,
      ),
    );
  }

  void close() => _db.dispose();
}
