import 'package:personal_tracker_domain/domain.dart';
import 'local_storage.dart';

class MigrationImportReport {
  const MigrationImportReport({
    required this.found,
    required this.imported,
    required this.skipped,
    required this.warnings,
  });
  final int found;
  final int imported;
  final int skipped;
  final List<String> warnings;
}

class WebBackupImporter {
  static Future<MigrationImportReport> importInto(
    LocalDatabase database,
    Map<String, dynamic> backup,
  ) async {
    final warnings = <String>[];
    var found = 0;
    var imported = 0;
    var skipped = 0;

    if (!_looksLikeBackup(backup))
      return const MigrationImportReport(
        found: 0,
        imported: 0,
        skipped: 0,
        warnings: [
          'Файл не похож на backup Personal Tracker: отсутствуют разделы English, Money, Sales или Sport.',
        ],
      );

    Future<void> raw(
      String module,
      String kind,
      Map<String, dynamic> row,
      int index,
    ) async {
      found++;
      final sourceId =
          (row['id'] ?? row['clientId'] ?? row['client_id'] ?? '$index')
              .toString();
      final added = await database.saveImportedRaw(
        id: 'web:$module:$kind:$sourceId',
        module: module,
        kind: kind,
        payload: row,
      );
      if (added) {
        imported++;
      } else {
        skipped++;
      }
    }

    Future<void> capture(CaptureRecord record) async {
      found++;
      final added = await database.saveIfAbsent(record);
      if (added) {
        imported++;
      } else {
        skipped++;
      }
    }

    final money = _map(backup['money']);
    for (var i = 0; i < _list(money['transactions']).length; i++) {
      final row = _list(money['transactions'])[i];
      await raw('money', 'transaction', row, i);
      final type = row['type'] == 'income'
          ? CaptureType.income
          : CaptureType.expense;
      final date = _date(row['date']);
      await capture(
        CaptureRecord(
          id: 'web:money:event:${row['id'] ?? i}',
          createdAt: _createdAt(row, date),
          draft: CaptureDraft(
            type: type,
            originalText: 'Imported from web backup',
            date: date,
            amount: _number(row['amount']),
            currency: row['currency']?.toString() ?? 'UZS',
            category: row['categoryId']?.toString(),
            paymentMethod: row['paymentMethod']?.toString(),
            description:
                row['purpose']?.toString() ?? row['comment']?.toString(),
          ),
        ),
      );
    }
    for (final kind in [
      'accounts',
      'categories',
      'obligations',
      'recurringTransactions',
    ]) {
      final rows = _list(money[kind]);
      for (var i = 0; i < rows.length; i++)
        await raw('money', kind, rows[i], i);
    }
    if (_list(money['accounts']).isNotEmpty ||
        _list(money['obligations']).isNotEmpty)
      warnings.add(
        'Money accounts/obligations сохранены как raw migration rows; отдельный mobile UI для них ещё не подключён.',
      );

    final sales = _map(backup['sales']);
    final clients = _list(sales['clients']);
    for (var i = 0; i < clients.length; i++)
      await raw('sales', 'client', clients[i], i);
    final clientNames = {
      for (final row in clients)
        row['id']?.toString(): row['companyName']?.toString(),
    };
    final calls = _list(sales['calls']);
    for (var i = 0; i < calls.length; i++) {
      final row = calls[i];
      await raw('sales', 'call', row, i);
      await capture(
        CaptureRecord(
          id: 'web:sales:event:${row['id'] ?? i}',
          createdAt: _createdAt(row, _date(row['dateTime'])),
          draft: CaptureDraft(
            type: CaptureType.salesCall,
            originalText: 'Imported from web backup',
            date: _date(row['dateTime']),
            company:
                clientNames[row['clientId']?.toString()] ??
                row['clientId']?.toString(),
            result: row['result']?.toString(),
            whatSaid: row['whatSaid']?.toString(),
            offered: row['offered']?.toString(),
            nextStep: row['nextStep']?.toString(),
            followUpDate: row['nextContactDate']?.toString(),
          ),
        ),
      );
    }
    for (final kind in ['opportunities', 'followUps', 'services']) {
      final rows = _list(sales[kind]);
      for (var i = 0; i < rows.length; i++)
        await raw('sales', kind, rows[i], i);
    }
    if (clients.isNotEmpty || _list(sales['opportunities']).isNotEmpty)
      warnings.add(
        'Sales clients/opportunities сохранены как raw migration rows; события звонков импортированы в Quick Capture history.',
      );

    final english = _map(backup['english']);
    final timerSessions = _list(english['timerSessions']);
    for (var i = 0; i < timerSessions.length; i++) {
      final row = timerSessions[i];
      await raw('english', 'timerSession', row, i);
      await capture(
        CaptureRecord(
          id: 'web:english:event:${row['id'] ?? i}',
          createdAt: _createdAt(row, _date(row['startedAt'])),
          draft: CaptureDraft(
            type: CaptureType.english,
            originalText: 'Imported from web backup',
            date: _date(row['startedAt']),
            durationMinutes: ((_number(row['durationSeconds']) ?? 0) / 60)
                .round(),
            activityType: 'study',
          ),
        ),
      );
    }
    final days = _list(english['days']);
    for (var i = 0; i < days.length; i++)
      await raw('english', 'day', days[i], i);
    for (final kind in [
      'vocabulary',
      'mistakes',
      'writing',
      'speaking',
      'tests',
      'expenses',
    ]) {
      final rows = _list(english[kind]);
      for (var i = 0; i < rows.length; i++)
        await raw('english', kind, rows[i], i);
    }
    if (days.isNotEmpty && timerSessions.isEmpty)
      warnings.add(
        'English roadmap сохранён как raw migration rows, но timerSessions не найдены — событий изучения для Quick Capture не создано.',
      );

    final sport = _map(backup['sport']);
    final workouts = _list(sport['workoutSessions']);
    for (var i = 0; i < workouts.length; i++) {
      final row = workouts[i];
      await raw('sport', 'workoutSession', row, i);
      await capture(
        CaptureRecord(
          id: 'web:sport:event:${row['id'] ?? i}',
          createdAt: _createdAt(row, _date(row['date'])),
          draft: CaptureDraft(
            type: CaptureType.sports,
            originalText: 'Imported from web backup',
            date: _date(row['date']),
            durationMinutes: (_number(row['durationMinutes']))?.round(),
            activityType: row['workoutType']?.toString(),
            comment: row['notes']?.toString(),
          ),
        ),
      );
    }
    for (final kind in [
      'measurements',
      'basketballSessions',
      'recoveryCheckIns',
      'checkpoints',
      'roadmap',
      'exerciseLibrary',
    ]) {
      final rows = _list(sport[kind]);
      for (var i = 0; i < rows.length; i++)
        await raw('sport', kind, rows[i], i);
    }
    if (_list(sport['measurements']).isNotEmpty ||
        _list(sport['recoveryCheckIns']).isNotEmpty)
      warnings.add(
        'Sport measurements/recovery сохранены как raw migration rows; workout events импортированы в Quick Capture history.',
      );

    return MigrationImportReport(
      found: found,
      imported: imported,
      skipped: skipped,
      warnings: warnings,
    );
  }

  static bool _looksLikeBackup(Map<String, dynamic> backup) =>
      backup.containsKey('money') ||
      backup.containsKey('sales') ||
      backup.containsKey('sport') ||
      backup.containsKey('english') ||
      backup.containsKey('days');
  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? [
          for (final row in value)
            if (row is Map) Map<String, dynamic>.from(row),
        ]
      : <Map<String, dynamic>>[];
  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static String _date(Object? value) {
    final text = value?.toString() ?? '';
    return text.length >= 10
        ? text.substring(0, 10)
        : DateTime.now().toIso8601String().substring(0, 10);
  }

  static DateTime _createdAt(Map<String, dynamic> row, String date) =>
      DateTime.tryParse(
        row['createdAt']?.toString() ??
            row['startedAt']?.toString() ??
            row['dateTime']?.toString() ??
            '',
      ) ??
      DateTime.parse('${date}T12:00:00Z');
}
