import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_tracker_domain/domain.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late Directory legacyAttachments;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('personal-tracker-ccc-001-');
    legacyAttachments = Directory(path.join(root.path, 'legacy-documents'));
    await legacyAttachments.create(recursive: true);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('A → B → A isolates personal records and attachments', () async {
    final userA = LocalDataScope.personal('user-a');
    final userB = LocalDataScope.personal('user-b');
    final databaseA = await _open(root, legacyAttachments, userA);
    await databaseA.save(_capture('capture-a'));
    await databaseA.saveMoneyTransaction(
      MoneyTransaction(
        id: 'money-a',
        date: '2026-08-11',
        type: MoneyTransactionType.expense,
        amount: 1000,
        currency: 'UZS',
        counterparty: 'A',
        categoryId: 'cola-drinks',
        purpose: 'A',
        paymentMethod: MoneyPaymentMethod.cash,
        accountId: 'cash-main',
        recurring: false,
        status: MoneyTransactionStatus.completed,
        comment: '',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
    );
    await databaseA.savePreference('theme', 'dark');
    await databaseA.saveEnglishLearningProfileJson('{"level":"B1"}');
    await databaseA.saveSportTrainingProfileJson('{"goal":"strength"}');
    final attachmentA =
        await databaseA.attachmentDirectory('english-recordings');
    final audioA = File(path.join(attachmentA.path, 'a.m4a'));
    await audioA.writeAsString('private audio A');
    databaseA.close();

    final databaseB = await _open(root, legacyAttachments, userB);
    expect(databaseB.all(), isEmpty);
    expect(databaseB.moneyTransactions(), isEmpty);
    expect(databaseB.preference('theme'), isNull);
    expect(databaseB.englishLearningProfileJson(), isNull);
    expect(databaseB.sportTrainingProfileJson(), isNull);
    final attachmentB =
        await databaseB.attachmentDirectory('english-recordings');
    expect(File(path.join(attachmentB.path, 'a.m4a')).existsSync(), isFalse);
    expect(databaseB.attachmentsRootPath, isNot(databaseA.attachmentsRootPath));
    databaseB.close();

    final reopenedA = await _open(root, legacyAttachments, userA);
    expect(reopenedA.all().map((record) => record.id), ['capture-a']);
    expect(reopenedA.moneyTransactions().single.id, 'money-a');
    expect(reopenedA.preference('theme'), 'dark');
    expect(reopenedA.englishLearningProfileJson(), '{"level":"B1"}');
    expect(reopenedA.sportTrainingProfileJson(), '{"goal":"strength"}');
    expect(
        File(path.join(
                (await reopenedA.attachmentDirectory('english-recordings'))
                    .path,
                'a.m4a'))
            .existsSync(),
        isTrue);
    reopenedA.close();
  });

  test('tenant A → tenant B → tenant A scopes do not cross', () async {
    final tenantA = LocalDataScope.tenant('tenant-a');
    final tenantB = LocalDataScope.tenant('tenant-b');
    final databaseA = await _open(root, legacyAttachments, tenantA);
    await databaseA.save(_capture('tenant-a-capture'));
    databaseA.close();

    final databaseB = await _open(root, legacyAttachments, tenantB);
    expect(databaseB.all(), isEmpty);
    databaseB.close();

    final reopenedA = await _open(root, legacyAttachments, tenantA);
    expect(reopenedA.all().single.id, 'tenant-a-capture');
    reopenedA.close();
  });

  test('unknown legacy owner is quarantined and never rendered', () async {
    await _createLegacyFixture(root, legacyAttachments);
    final userB = LocalDataScope.personal('user-b');

    await expectLater(
      _open(root, legacyAttachments, userB),
      throwsA(isA<LegacyDataQuarantined>()),
    );

    final quarantine = Directory(path.join(root.path, 'legacy-quarantine'));
    expect(quarantine.existsSync(), isTrue);
    expect(quarantine.listSync().whereType<File>(), isNotEmpty);
    expect(
      File(path.join(root.path, 'scopes', '${userB.fingerprint}.sqlite'))
          .existsSync(),
      isFalse,
    );
  });

  test('new account can explicitly open an empty scope without claiming legacy data',
      () async {
    await _createLegacyFixture(root, legacyAttachments);
    final newUser = LocalDataScope.personal('new-user');

    final empty = await _open(
      root,
      legacyAttachments,
      newUser,
      allowEmptyScopeWithQuarantinedLegacy: true,
    );
    expect(empty.all(), isEmpty);
    empty.close();

    final owner = LocalDataScope.personal('legacy-owner');
    final migrated = await _open(
      root,
      legacyAttachments,
      owner,
      claim: LegacyMigrationClaim.forRestoredPersonalSession(owner),
    );
    expect(migrated.all().single.id, 'legacy-capture');
    migrated.close();
  });

  test('bootstrap metadata contains no domain rows or raw capture content',
      () async {
    await _createLegacyFixture(root, legacyAttachments);
    final userB = LocalDataScope.personal('user-b');
    await expectLater(
      _open(root, legacyAttachments, userB),
      throwsA(isA<LegacyDataQuarantined>()),
    );
    final bootstrap = sqlite3.open(path.join(root.path, 'bootstrap.sqlite'));
    try {
      final tableNames = bootstrap
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(tableNames, contains('legacy_quarantine'));
      expect(tableNames, isNot(contains('money_transactions')));
      expect(tableNames, isNot(contains('capture_records')));
      final metadata =
          bootstrap.select('SELECT * FROM legacy_quarantine').first;
      expect(metadata.values.join('|'), isNot(contains('legacy-capture')));
      expect(metadata.values.join('|'), isNot(contains('Coffee')));
    } finally {
      bootstrap.dispose();
    }
  });

  test('verified restored-owner claim migrates legacy records and attachment',
      () async {
    await _createLegacyFixture(root, legacyAttachments);
    final owner = LocalDataScope.personal('owner-a');

    final database = await _open(
      root,
      legacyAttachments,
      owner,
      claim: LegacyMigrationClaim.forRestoredPersonalSession(owner),
    );

    expect(database.all().single.id, 'legacy-capture');
    expect(database.moneyTransactions().single.id, 'legacy-money');
    final lesson = database.englishLessonProgress('lesson-1');
    expect(lesson.speakingPath, startsWith(database.attachmentsRootPath));
    expect(
        File(lesson.speakingPath!).readAsString(), completion('legacy audio'));
    database.close();

    final otherUser = LocalDataScope.personal('other-user');
    final otherDatabase = await _open(root, legacyAttachments, otherUser);
    expect(otherDatabase.all(), isEmpty);
    expect(otherDatabase.moneyTransactions(), isEmpty);
    otherDatabase.close();

    final reopenedOwner = await _open(
      root,
      legacyAttachments,
      owner,
      claim: LegacyMigrationClaim.forRestoredPersonalSession(owner),
    );
    expect(reopenedOwner.all().single.id, 'legacy-capture');
    reopenedOwner.close();
  });

  test(
      'crash/re-run migration removes stale temporary copy and remains idempotent',
      () async {
    await _createLegacyFixture(root, legacyAttachments);
    final owner = LocalDataScope.personal('owner-a');
    final stale = File(path.join(
        root.path, 'scopes', '${owner.fingerprint}.sqlite.migrating'));
    await stale.parent.create(recursive: true);
    await stale.writeAsString('interrupted migration');

    final claim = LegacyMigrationClaim.forRestoredPersonalSession(owner);
    final first = await _open(root, legacyAttachments, owner, claim: claim);
    expect(first.all().single.id, 'legacy-capture');
    first.close();
    expect(stale.existsSync(), isFalse);

    final second = await _open(root, legacyAttachments, owner, claim: claim);
    expect(second.all(), hasLength(1));
    expect(second.moneyTransactions(), hasLength(1));
    second.close();
  });

  test('crash injection at every migration boundary is recoverable', () async {
    for (final point in LegacyMigrationFaultPoint.values) {
      final caseRoot = await Directory.systemTemp
          .createTemp('personal-tracker-ccc-001-fault-');
      final caseAttachments =
          Directory(path.join(caseRoot.path, 'legacy-documents'))
            ..createSync(recursive: true);
      try {
        await _createLegacyFixture(caseRoot, caseAttachments);
        final owner = LocalDataScope.personal('owner-a');
        await expectLater(
          _open(caseRoot, caseAttachments, owner,
              claim: LegacyMigrationClaim.forRestoredPersonalSession(owner),
              faultPoint: point),
          throwsA(isA<StateError>()),
        );
        final recovered = await _open(
          caseRoot,
          caseAttachments,
          owner,
          claim: LegacyMigrationClaim.forRestoredPersonalSession(owner),
        );
        expect(recovered.all().single.id, 'legacy-capture');
        recovered.close();
      } finally {
        if (caseRoot.existsSync()) await caseRoot.delete(recursive: true);
      }
    }
  });

  test('concurrent claimers serialize and produce one scoped migration',
      () async {
    await _createLegacyFixture(root, legacyAttachments);
    final owner = LocalDataScope.personal('owner-a');
    final claim = LegacyMigrationClaim.forRestoredPersonalSession(owner);
    final opened = await Future.wait([
      _open(root, legacyAttachments, owner, claim: claim),
      _open(root, legacyAttachments, owner, claim: claim),
    ]);
    expect(opened[0].all().map((item) => item.id), ['legacy-capture']);
    expect(opened[1].all().map((item) => item.id), ['legacy-capture']);
    for (final database in opened) {
      database.close();
    }
  });

  test(
      'attachment API rejects traversal and migration avoids basename collision',
      () async {
    final database = await _open(
        root, legacyAttachments, LocalDataScope.personal('attachment-owner'));
    expect(
        () => database.attachmentDirectory('../escape'), throwsArgumentError);
    expect(() => database.attachmentDirectory(r'folder\\escape'),
        throwsArgumentError);
    expect(
        () => database.attachmentDirectory(r'C:\\escape'), throwsArgumentError);
    database.close();

    await _createLegacyFixture(root, legacyAttachments);
    final folderA = Directory(path.join(legacyAttachments.path, 'a'))
      ..createSync(recursive: true);
    final folderB = Directory(path.join(legacyAttachments.path, 'b'))
      ..createSync(recursive: true);
    final first = File(path.join(folderA.path, 'same.m4a'))
      ..writeAsStringSync('first');
    final second = File(path.join(folderB.path, 'same.m4a'))
      ..writeAsStringSync('second');
    final legacyPath = path.join(root.path, 'personal_tracker.sqlite');
    final legacyDb = sqlite3.open(legacyPath);
    try {
      legacyDb.execute(
        '''INSERT INTO english_lesson_work
           (lesson_id, reading_done, listening_done, writing_text, speaking_path, updated_at)
           VALUES (?, 0, 0, '', ?, ?)''',
        ['same-a', first.path, DateTime.utc(2026, 8, 11).toIso8601String()],
      );
      legacyDb.execute(
        '''INSERT INTO english_lesson_work
           (lesson_id, reading_done, listening_done, writing_text, speaking_path, updated_at)
           VALUES (?, 0, 0, '', ?, ?)''',
        ['same-b', second.path, DateTime.utc(2026, 8, 11).toIso8601String()],
      );
    } finally {
      legacyDb.dispose();
    }
    // Recompute the source fingerprint after adding the collision fixtures.
    final owner = LocalDataScope.personal('collision-owner');
    final migrated = await _open(root, legacyAttachments, owner,
        claim: LegacyMigrationClaim.forRestoredPersonalSession(owner));
    final paths = [
      migrated.englishLessonProgress('same-a').speakingPath!,
      migrated.englishLessonProgress('same-b').speakingPath!,
    ];
    expect(paths[0], isNot(paths[1]));
    expect(File(paths[0]).readAsStringSync(), 'first');
    expect(File(paths[1]).readAsStringSync(), 'second');
    migrated.close();
  });

  test('legacy attachment outside source root fails closed', () async {
    await _createLegacyFixture(root, legacyAttachments);
    final outside = File(path.join(root.parent.path, 'outside-ccc-001.m4a'))
      ..writeAsStringSync('outside');
    final legacyDb =
        sqlite3.open(path.join(root.path, 'personal_tracker.sqlite'));
    try {
      legacyDb.execute(
        '''INSERT INTO english_lesson_work
           (lesson_id, reading_done, listening_done, writing_text, speaking_path, updated_at)
           VALUES (?, 0, 0, '', ?, ?)''',
        [
          'wrong-owner',
          outside.path,
          DateTime.utc(2026, 8, 11).toIso8601String()
        ],
      );
    } finally {
      legacyDb.dispose();
    }
    final owner = LocalDataScope.personal('outside-owner');
    await expectLater(
      _open(root, legacyAttachments, owner,
          claim: LegacyMigrationClaim.forRestoredPersonalSession(owner)),
      throwsA(isA<StateError>()),
    );
    if (outside.existsSync()) outside.deleteSync();
  });
}

Future<LocalDatabase> _open(
  Directory root,
  Directory legacyAttachments,
  LocalDataScope scope, {
  LegacyMigrationClaim? claim,
  LegacyMigrationFaultPoint? faultPoint,
  bool allowEmptyScopeWithQuarantinedLegacy = false,
}) =>
    LocalDatabase.open(
      scope: scope,
      supportDirectory: root,
      legacyAttachmentDirectory: legacyAttachments,
      legacyMigrationClaim: claim,
      migrationFaultPoint: faultPoint,
      allowEmptyScopeWithQuarantinedLegacy:
          allowEmptyScopeWithQuarantinedLegacy,
    );

CaptureRecord _capture(String id) => CaptureRecord(
      id: id,
      createdAt: DateTime.utc(2026, 8, 11),
      draft: const CaptureDraft(
        type: CaptureType.expense,
        originalText: 'Купил кофе',
        date: '2026-08-11',
        amount: 20000,
        category: 'drinks',
        paymentMethod: 'cash',
      ),
    );

Future<void> _createLegacyFixture(
  Directory root,
  Directory legacyAttachments,
) async {
  final seedScope = LocalDataScope.personal('legacy-seed');
  final seed = await _open(root, legacyAttachments, seedScope);
  await seed.save(_capture('legacy-capture'));
  await seed.saveMoneyTransaction(
    MoneyTransaction(
      id: 'legacy-money',
      date: '2026-08-11',
      type: MoneyTransactionType.expense,
      amount: 20000,
      currency: 'UZS',
      counterparty: 'Coffee',
      categoryId: 'cola-drinks',
      purpose: 'Coffee',
      paymentMethod: MoneyPaymentMethod.cash,
      accountId: 'cash-main',
      recurring: false,
      status: MoneyTransactionStatus.completed,
      comment: '',
      createdAt: DateTime.utc(2026, 8, 11),
    ),
  );
  final oldAudio =
      File(path.join(legacyAttachments.path, 'english_legacy.m4a'));
  await oldAudio.writeAsString('legacy audio');
  await seed.saveEnglishLessonProgress(
    'lesson-1',
    readingDone: true,
    listeningDone: true,
    writingText: 'Legacy writing',
    speakingPath: oldAudio.path,
  );
  final legacy = File(path.join(root.path, 'personal_tracker.sqlite'));
  final seedPath = seed.databasePath;
  seed.close();
  await File(seedPath).copy(legacy.path);

  final database = sqlite3.open(legacy.path);
  try {
    database.execute('DELETE FROM scope_metadata');
  } finally {
    database.dispose();
  }
}
