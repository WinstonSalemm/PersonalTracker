import 'dart:io';

import 'package:personal_tracker_capture_v2/capture_v2.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_domain/domain.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';
import 'package:test/test.dart';

import 'semantic_corpus.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 10, 30);
  final adapter = V1ParserToV2Adapter(DeterministicParser());

  test(
      'exact textual Money never uses V1 double and has declared no-rounding policy',
      () async {
    for (final item in [
      ('spent 0.01 USD', '1'),
      ('spent 10.99 USD', '1099'),
      ('spent 1.5 mln UZS', '1500000'),
      ('spent 999999999999 UZS', '999999999999'),
    ]) {
      final result = await adapter.parse(item.$1, now: now);
      expect((result.intent as MoneyIntentV2).minorUnits, item.$2);
      expect(result.parserName, 'deterministic-v2-shadow');
    }
    for (final input in [
      'spent 1.005 USD',
      'spent 1..5 USD',
      'spent -1 USD',
      'spent 0 USD',
      'spent 9999999999999999999 UZS'
    ]) {
      expect((await adapter.parse(input, now: now)).isUnsupported, isTrue,
          reason: input);
    }
  });

  test('human-labelled corpus satisfies size, language and domain minimums',
      () {
    expect(semanticCorpus, hasLength(120));
    for (final language in ['ru', 'uz', 'en']) {
      expect(
          semanticCorpus.where((f) => f.language == language), hasLength(40));
    }
    expect(semanticCorpus.where((f) => f.intent.startsWith('money.')).length,
        greaterThanOrEqualTo(45));
    expect(semanticCorpus.where((f) => f.intent.startsWith('sport.')).length,
        greaterThanOrEqualTo(20));
    expect(semanticCorpus.where((f) => f.intent.startsWith('work.')).length,
        greaterThanOrEqualTo(20));
    expect(semanticCorpus.where((f) => f.intent.startsWith('english.')).length,
        greaterThanOrEqualTo(15));
    expect(semanticCorpus.where((f) => !f.supported).length,
        greaterThanOrEqualTo(20));
  });

  test('semantic acceptance metrics meet safety thresholds', () async {
    final metrics =
        await SemanticMetrics.evaluate(adapter, semanticCorpus, now);
    print(metrics.reportLine);
    expect(metrics.silentWrong, 0);
    expect(metrics.falseConfidentFinancial, 0);
    expect(metrics.supportedPrecision, greaterThanOrEqualTo(.95));
    expect(metrics.moneySupportedPrecision, 1.0);
  });

  test(
      'shadow runner is owner-scoped and produces no domain or outbox side effect',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-shadow-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('semantic-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final runner =
          CaptureV2ShadowRunner(adapter: adapter, database: db, enabled: true);
      final result = await runner.run('потратил 20 тысяч на колу', now: now);
      expect(result?.failed, isFalse);
      expect(db.captureShadowV2Count(), 1);
      expect(db.all(), isEmpty);
      expect(db.moneyTransactions(), isEmpty);
      expect(db.syncOutboxCount(), 0);
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('enabled shadow failure is contained at the runner boundary', () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-failure-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('failure-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final result = await CaptureV2ShadowRunner(
              adapter: V1ParserToV2Adapter(const _ThrowingParser()),
              database: db,
              enabled: true,
              forceFailureForTest: true)
          .run('input', now: now);
      expect(result?.failed, isTrue);
      expect(db.captureShadowV2Count(), 1);
      expect(db.all(), isEmpty);
      expect(db.syncOutboxCount(), 0);
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('V1-unsupported raw submission still persists one V2 income shadow',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-v1-gap-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('v1-gap-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final result = await CaptureV2ShadowRunner(
              adapter: adapter, database: db, enabled: true)
          .run('Получил зарплату 5 миллионов', now: now);
      expect(result!.envelope!.v1Draft, isNull);
      expect(result.envelope!.intent.kind, 'money.income');
      expect((result.envelope!.intent as MoneyIntentV2).minorUnits, '5000000');
      expect(db.captureShadowV2Count(), 1);
      expect(db.all(), isEmpty);
      expect(db.syncOutboxCount(), 0);
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {}
      }
    }
  });

  test(
      'repeated raw submit is idempotent and does not create a second shadow row',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-repeat-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('repeat-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final runner =
          CaptureV2ShadowRunner(adapter: adapter, database: db, enabled: true);
      await runner.run('Потратил 20 тысяч на кофе', now: now);
      await runner.run('Потратил 20 тысяч на кофе', now: now);
      expect(db.captureShadowV2Count(), 1);
      expect(db.all(), isEmpty);
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {}
      }
    }
  });

  test(
      'canonical Money commit is stable across 100 retries and concurrent calls',
      () async {
    final root =
        await Directory.systemTemp.createTemp('capture-v2-money-idem-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-idempotency'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final service = CanonicalMoneyCommitService(db, enabled: true);
      final envelope = _moneyEnvelope('capture-100', '20000');
      final ids = <String>[];
      for (var index = 0; index < 100; index++) {
        ids.add(await service.confirm(envelope));
      }
      final concurrent = await Future.wait(
        List.generate(12, (_) => service.confirm(envelope)),
      );
      expect({...ids, ...concurrent}, {'money-v2-capture-100'});
      expect(db.canonicalMoneyCommitCount(captureId: 'capture-100'), 1);
      expect(
          db.activeCanonicalMoneyProjectionCount(captureId: 'capture-100'), 1);
      expect(db.canonicalMoneyRowCount(captureId: 'capture-100'), 1);
      final transaction = db.moneyTransactions().single;
      expect(transaction.amount, 20000);
      expect(
          db.canonicalMoneyCaptureIdsForSyntheticExclusion(), {'capture-100'});
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('canonical Money rolls back every injected boundary and safely retries',
      () async {
    final root =
        await Directory.systemTemp.createTemp('capture-v2-money-rollback-');
    const points = [
      'before_canonical_evidence',
      'after_canonical_evidence',
      'before_money_insert',
      'after_money_insert',
      'before_projection_insert',
      'after_projection_insert',
      'before_committed_local',
      'before_sqlite_commit',
    ];
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-rollback'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      for (final point in points) {
        final captureId = 'rollback-$point';
        await expectLater(
          db.commitCanonicalMoney(_moneyInput(captureId, '20000'),
              failAt: point),
          throwsA(isA<StateError>()),
        );
        expect(db.canonicalMoneyCommitCount(captureId: captureId), 0,
            reason: point);
        expect(db.activeCanonicalMoneyProjectionCount(captureId: captureId), 0,
            reason: point);
        expect(db.canonicalMoneyRowCount(captureId: captureId), 0,
            reason: point);
        final id =
            await db.commitCanonicalMoney(_moneyInput(captureId, '20000'));
        expect(id, 'money-v2-$captureId');
      }
      db.close();
    } finally {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test('canonical Money outbox survives restart and acknowledges once',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-outbox-');
    const captureId = 'outbox-restart';
    try {
      final first = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-outbox'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      await first.commitCanonicalMoney(_moneyInput(captureId, '5000000'));
      expect(first.pendingCanonicalMoneySync(), hasLength(1));
      final failedAt = DateTime.utc(2026, 8, 11, 12);
      first.markCanonicalMoneySending(captureId, now: failedAt);
      first.markCanonicalMoneyRetryableFailure(
        captureId,
        errorCode: 'network',
        now: failedAt,
      );
      first.close();

      final reopened = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-outbox'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      expect(reopened.pendingCanonicalMoneySync(now: failedAt), isEmpty);
      expect(
        reopened.pendingCanonicalMoneySync(
            now: failedAt.add(const Duration(minutes: 6))),
        hasLength(1),
      );
      await reopened.markCanonicalMoneySynced([captureId]);
      expect(reopened.pendingCanonicalMoneySync(), isEmpty);
      expect(reopened.canonicalMoneySyncStatus().acknowledged, 1);
      reopened.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('permanent canonical delivery failure needs an explicit repair retry',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-repair-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-repair'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      await db.commitCanonicalMoney(_moneyInput('repairable', '10000'));
      db.markCanonicalMoneySending('repairable');
      db.markCanonicalMoneyPermanentFailure(
        'repairable',
        errorCode: 'account_not_owned',
      );
      expect(db.pendingCanonicalMoneySync(), isEmpty);
      expect(db.canonicalMoneySyncStatus().requiresRepair, isTrue);
      expect(db.requeueCanonicalMoneyFailures(), 1);
      expect(db.pendingCanonicalMoneySync(), hasLength(1));
      db.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('legacy V1 module captures remain readable and never enter V2 outbox',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-compat-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('compat-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final createdAt = DateTime.utc(2026, 8, 11, 10);
      final records = [
        CaptureRecord(
            id: 'legacy-money',
            createdAt: createdAt,
            draft: const CaptureDraft(
                type: CaptureType.expense,
                originalText: 'legacy money',
                date: '2026-08-11',
                amount: 10000,
                description: 'legacy money')),
        CaptureRecord(
            id: 'legacy-sales',
            createdAt: createdAt,
            draft: const CaptureDraft(
                type: CaptureType.salesCall,
                originalText: 'legacy sales',
                date: '2026-08-11',
                company: 'ABC')),
        CaptureRecord(
            id: 'legacy-english',
            createdAt: createdAt,
            draft: const CaptureDraft(
                type: CaptureType.english,
                originalText: 'legacy english',
                date: '2026-08-11',
                durationMinutes: 30)),
        CaptureRecord(
            id: 'legacy-sport',
            createdAt: createdAt,
            draft: const CaptureDraft(
                type: CaptureType.sports,
                originalText: 'legacy sport',
                date: '2026-08-11',
                durationMinutes: 45)),
      ];
      for (final record in records) {
        await db.save(record);
      }
      await db.commitCanonicalMoney(_moneyInput('canonical-new', '20000'));

      expect(db.all().map((item) => item.id).toSet(),
          {'legacy-money', 'legacy-sales', 'legacy-english', 'legacy-sport'});
      expect(db.pending().map((item) => item.id).toSet(),
          {'legacy-money', 'legacy-sales', 'legacy-english', 'legacy-sport'});
      expect(db.syncOutboxCount(), 4);
      expect(db.pendingCanonicalMoneySync(), hasLength(1));

      await db.markSynced(records.map((item) => item.id));
      expect(db.pending(), isEmpty);
      expect(db.all(), hasLength(4));
      expect(db.pendingCanonicalMoneySync(), hasLength(1));
      db.close();
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });

  test('exact amount validation, edit parity, delete and scope isolation hold',
      () async {
    final root =
        await Directory.systemTemp.createTemp('capture-v2-money-lifecycle-');
    try {
      final a = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-owner-a'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      for (final fixture in [
        ('uzs-20k', '20000', 'UZS'),
        ('uzs-5m', '5000000', 'UZS'),
        ('usd-1099', '1099', 'USD')
      ]) {
        await a.commitCanonicalMoney(
            _moneyInput(fixture.$1, fixture.$2, currency: fixture.$3));
      }
      await expectLater(
        a.commitCanonicalMoney(_moneyInput(
            'unsafe', '999999999999999999999999999999999999999999999999')),
        throwsArgumentError,
      );
      final id = await a.commitCanonicalMoney(_moneyInput('editable', '20000'));
      final original =
          a.moneyTransactions().firstWhere((item) => item.id == id);
      await a.saveMoneyTransaction(MoneyTransaction(
        id: id,
        date: original.date,
        type: original.type,
        amount: original.amount,
        currency: original.currency,
        counterparty: original.counterparty,
        categoryId: 'real-category',
        purpose: 'edited description',
        paymentMethod: original.paymentMethod,
        accountId: 'real-account',
        transferToAccountId: original.transferToAccountId,
        recurring: original.recurring,
        status: original.status,
        incomeSource: original.incomeSource,
        obligationId: original.obligationId,
        essential: original.essential,
        comment: original.comment,
        createdAt: original.createdAt,
      ));
      expect(a.canonicalMoneyTransactionId('editable'), id);
      expect(a.canonicalMoneyRowCount(captureId: 'editable'), 1);
      await a.deleteMoneyTransaction(id);
      await a.deleteMoneyTransaction(id);
      expect(a.canonicalMoneyTransactionId('editable'), isNull);
      expect(a.canonicalMoneyCaptureIdsForSyntheticExclusion(),
          contains('editable'));
      final b = await LocalDatabase.open(
          scope: LocalDataScope.personal('money-owner-b'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      expect(b.moneyTransactions(), isEmpty);
      b.close();
      a.close();
    } finally {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test('fixture-batch shadow performance records p50 and p95 locally',
      () async {
    final root = await Directory.systemTemp.createTemp('capture-v2-perf-');
    try {
      final db = await LocalDatabase.open(
          scope: LocalDataScope.personal('performance-owner'),
          supportDirectory: root,
          legacyAttachmentDirectory: root);
      final runner =
          CaptureV2ShadowRunner(adapter: adapter, database: db, enabled: true);
      final parse = <int>[];
      final persist = <int>[];
      for (final fixture in semanticCorpus) {
        final result = await runner.run(fixture.input, now: now);
        parse.add(result!.parseDurationMicros!);
        persist.add(result.persistenceDurationMicros!);
      }
      int percentile(List<int> values, double p) {
        values.sort();
        return values[((values.length - 1) * p).round()];
      }

      print(
          'CCC-002B PERFORMANCE sample=${semanticCorpus.length} parse_us_p50=${percentile(parse, .50)} parse_us_p95=${percentile(parse, .95)} persistence_us_p50=${percentile(persist, .50)} persistence_us_p95=${percentile(persist, .95)}');
      // Equal raw inputs deliberately share the deterministic shadow id; this
      // batch measures all invocations without treating that idempotency as a
      // persistence failure.
      expect(db.captureShadowV2Count(), greaterThanOrEqualTo(119));
      db.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* SQLite handle release is asynchronous on Windows. */
        }
      }
    }
  });
}

CanonicalMoneyCommitInput _moneyInput(String captureId, String minorUnits,
        {String currency = 'UZS'}) =>
    CanonicalMoneyCommitInput(
      captureId: captureId,
      intentJson: '{}',
      minorUnits: minorUnits,
      currency: currency,
      direction: 'expense',
      date: '2026-08-11',
      description: 'fixture',
      paymentMethod: 'other',
    );

CaptureEnvelopeV2 _moneyEnvelope(String captureId, String minorUnits) =>
    CaptureEnvelopeV2(
      captureId: captureId,
      schemaVersion: 2,
      originalText: 'spent 20k',
      inputMode: CaptureInputMode.text,
      createdAt: DateTime.utc(2026, 8, 11),
      occurredAt: DateTime.utc(2026, 8, 11),
      occurredAtExpression: null,
      timezone: 'UTC',
      intent: MoneyIntentV2(
        direction: MoneyDirectionV2.expense,
        minorUnits: minorUnits,
        currency: 'UZS',
        account: 'unassigned',
        category: 'unclassified',
        description: 'fixture',
        paymentMethod: 'other',
      ),
      provenance: const {},
      unresolved: const [],
      reviewState: V2ReviewState.reviewed,
      projectionCandidate: V2ProjectionCandidate.moneyTransaction,
      confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
      parserName: 'test',
    );

class SemanticMetrics {
  SemanticMetrics._(
      this.total,
      this.expectedSupported,
      this.supported,
      this.correctSupported,
      this.falseUnsupported,
      this.falseConfident,
      this.silentWrong,
      this.falseConfidentFinancial,
      this.moneySupported,
      this.correctMoneySupported,
      this.unresolvedCorrect);
  final int total,
      expectedSupported,
      supported,
      correctSupported,
      falseUnsupported,
      falseConfident,
      silentWrong,
      falseConfidentFinancial,
      moneySupported,
      correctMoneySupported,
      unresolvedCorrect;
  double get supportedPrecision =>
      supported == 0 ? 1 : correctSupported / supported;
  double get moneySupportedPrecision =>
      moneySupported == 0 ? 1 : correctMoneySupported / moneySupported;
  String get reportLine =>
      'CCC-002B METRICS total=$total expectedSupported=$expectedSupported supported=$supported correctSupported=$correctSupported precision=${supportedPrecision.toStringAsFixed(3)} recall=${(expectedSupported == 0 ? 1 : correctSupported / expectedSupported).toStringAsFixed(3)} unresolvedCorrect=$unresolvedCorrect falseConfident=$falseConfident silentWrong=$silentWrong falseUnsupported=$falseUnsupported financialFalseConfident=$falseConfidentFinancial moneyPrecision=${moneySupportedPrecision.toStringAsFixed(3)}';
  static Future<SemanticMetrics> evaluate(V1ParserToV2Adapter adapter,
      List<SemanticFixture> fixtures, DateTime now) async {
    var supported = 0,
        correct = 0,
        expected = 0,
        falseUnsupported = 0,
        falseConfident = 0,
        silentWrong = 0,
        financialFalse = 0,
        moneySupported = 0,
        moneyCorrect = 0,
        unresolvedCorrect = 0;
    for (final f in fixtures) {
      final r = await adapter.parse(f.input, now: now);
      final actualSupported = !r.isUnsupported;
      if (f.supported) expected++;
      final actual = r.intent.kind;
      final fields = r.intent.toJson().map((k, v) => MapEntry(k, '$v'));
      final semanticCorrect = actual == f.intent &&
          r.projectionCandidate.name == f.projection &&
          f.extracted.entries.every((e) => fields[e.key] == e.value);
      final unresolved = r.unresolved.map((u) => u.field).toSet();
      final unresolvedOk = f.unresolved.every(unresolved.contains);
      if (unresolvedOk) unresolvedCorrect++;
      if (actualSupported) {
        supported++;
        if (f.intent.startsWith('money.')) moneySupported++;
        if (semanticCorrect && unresolvedOk && f.supported) {
          correct++;
          if (f.intent.startsWith('money.')) moneyCorrect++;
        } else {
          print(
              'MISMATCH ${f.id}: expected=${f.intent}/${f.projection}/${f.extracted} unresolved=${f.unresolved}; actual=$actual/${r.projectionCandidate.name}/$fields unresolved=$unresolved');
          falseConfident++;
          if (f.intent.startsWith('money.')) financialFalse++;
          if (unresolved.intersection(f.unresolved).isEmpty) silentWrong++;
        }
      } else if (f.supported) {
        print(
            'UNSUPPORTED ${f.id}: expected=${f.intent}; actual=${r.unresolved.map((u) => u.reason).toList()}');
        falseUnsupported++;
      }
    }
    return SemanticMetrics._(
        fixtures.length,
        expected,
        supported,
        correct,
        falseUnsupported,
        falseConfident,
        silentWrong,
        financialFalse,
        moneySupported,
        moneyCorrect,
        unresolvedCorrect);
  }
}

class _ThrowingParser implements CommandParser {
  const _ThrowingParser();
  @override
  Future<CaptureDraft?> parse(String input) =>
      throw StateError('injected-shadow-failure');
}
