import 'package:personal_tracker_domain/domain.dart';

export 'assistant_parser.dart';

abstract interface class CommandParser {
  Future<CaptureDraft?> parse(String input);
}

class DeterministicParser implements CommandParser {
  @override
  Future<CaptureDraft?> parse(String input) async {
    final value = input.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    final date = DateTime.now().toIso8601String().substring(0, 10);

    if (_containsAny(lower, [
      'купил',
      'купила',
      'потрат',
      'расход',
      'заплатил',
    ])) {
      final amount = _amount(lower);
      if (amount == null) return null;
      final payment = lower.contains('налич')
          ? 'cash'
          : lower.contains('карт')
          ? 'card'
          : 'other';
      final category = lower.contains('кол') || lower.contains('напит')
          ? 'drinks'
          : lower.contains('еда') || lower.contains('продукт')
          ? 'food'
          : 'other';
      return CaptureDraft(
        type: CaptureType.expense,
        originalText: value,
        date: date,
        amount: amount,
        category: category,
        paymentMethod: payment,
        description: _expenseDescription(value),
        currency: _currency(lower),
      );
    }

    if (_containsAny(lower, [
      'позвонил',
      'позвонила',
      'компан',
      'клиент',
      'перезвон',
    ])) {
      final company = RegExp(
        r'(?:компани[юя]|компания|клиенту?)\s+([^.,]+)',
        caseSensitive: false,
      ).firstMatch(value)?.group(1)?.trim();
      final followUp = lower.contains('пятниц')
          ? _nextWeekday(DateTime.friday)
          : null;
      return CaptureDraft(
        type: CaptureType.salesCall,
        originalText: value,
        date: date,
        company: company ?? 'Новая компания',
        result: lower.contains('перезвон') ? 'follow_up' : 'contacted',
        whatSaid: value,
        offered: lower.contains('предлож') ? _after(value, 'предлож') : null,
        nextStep: followUp == null ? null : 'Перезвонить',
        followUpDate: followUp,
      );
    }

    if (_containsAny(lower, ['английск', 'english'])) {
      final minutes = _durationMinutes(lower) ?? 0;
      return CaptureDraft(
        type: CaptureType.english,
        originalText: value,
        date: date,
        durationMinutes: minutes,
        activityType: 'study',
        completedTask: _description(value),
      );
    }

    if (_containsAny(lower, [
      'играл',
      'трениров',
      'спорт',
      'теннис',
      'бегал',
      'зал',
    ])) {
      return CaptureDraft(
        type: CaptureType.sports,
        originalText: value,
        date: date,
        durationMinutes: _durationMinutes(lower),
        activityType: _sportType(lower),
        comment: value,
      );
    }
    return null;
  }

  bool _containsAny(String value, List<String> words) =>
      words.any(value.contains);

  double? _amount(String value) {
    final match = RegExp(
      r'(\d[\d\s.]*)\s*(тысяч|тыс|к|000)?',
    ).firstMatch(value);
    if (match == null) return null;
    final digits = match.group(1)!.replaceAll(RegExp(r'[\s.]'), '');
    final base = double.tryParse(digits);
    if (base == null) return null;
    return (match.group(2) == 'тысяч' ||
            match.group(2) == 'тыс' ||
            match.group(2) == 'к')
        ? base * 1000
        : base;
  }

  String _currency(String value) =>
      value.contains('доллар') || value.contains('usd')
      ? 'USD'
      : value.contains('евро') || value.contains('eur')
      ? 'EUR'
      : 'UZS';

  int? _durationMinutes(String value) {
    if (value.contains('полтора часа')) return 90;
    final hour = RegExp(r'(\d+)\s*час').firstMatch(value);
    final minute = RegExp(r'(\d+)\s*мин').firstMatch(value);
    final total =
        (hour == null ? 0 : int.parse(hour.group(1)!) * 60) +
        (minute == null ? 0 : int.parse(minute.group(1)!));
    return total == 0 ? null : total;
  }

  String _sportType(String value) => value.contains('теннис')
      ? 'table_tennis'
      : value.contains('бег')
      ? 'running'
      : value.contains('зал')
      ? 'gym'
      : 'general';

  String _expenseDescription(String value) =>
      RegExp(
        r'(?:купил|купила|потратил|потратила)\s+(.+?)\s+за\s+\d',
        caseSensitive: false,
      ).firstMatch(value)?.group(1)?.trim() ??
      value;
  String _description(String value) => value
      .replaceFirst(
        RegExp(r'^.*?(?:за|занимался|играл)\s+', caseSensitive: false),
        '',
      )
      .trim()
      .replaceFirst(
        RegExp(r'\s+(?:за\s+)?\d[\d\s.]*.*?$', caseSensitive: false),
        '',
      )
      .trim();
  String? _after(String value, String word) {
    final index = value.toLowerCase().indexOf(word);
    return index < 0
        ? null
        : value
              .substring(index + word.length)
              .trim()
              .replaceFirst(RegExp(r'^[:\s]+'), '');
  }

  String _nextWeekday(int weekday) {
    final now = DateTime.now();
    var delta = (weekday - now.weekday) % 7;
    if (delta == 0) delta = 7;
    return DateTime(
      now.year,
      now.month,
      now.day + delta,
    ).toIso8601String().substring(0, 10);
  }
}

class AiParser implements CommandParser {
  const AiParser({this.endpoint});
  final Uri? endpoint;

  @override
  Future<CaptureDraft?> parse(String input) async {
    // Intentionally no network call in v1. A future implementation must call a
    // protected backend endpoint; secrets must never be shipped in the client.
    return null;
  }
}
