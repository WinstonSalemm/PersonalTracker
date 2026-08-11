part of 'capture_v2.dart';

/// Small, deliberately bounded V2-only semantic layer. It is used for shadow
/// evidence only; it neither changes V1 parsing nor writes a domain record.
class V2DeterministicShadowParser {
  static final _amountToken = RegExp(
    r'(?<![\w.])(?:\$\s*)?(\d+(?:[.,]\d+)?)(?:\s*)(k|к|тыс(?:яч)?|млн|миллион(?:ов)?|лям(?:ов)?|ming|mln|million)?(?![A-Za-zА-Яа-яЁё])',
    caseSensitive: false,
  );

  CaptureEnvelopeV2? parse(
    String input, {
    required DateTime createdAt,
    required CaptureInputMode inputMode,
    required CaptureDraft? v1Draft,
  }) {
    if (_isMultiEvent(input))
      return _unsupported(
          input, createdAt, inputMode, v1Draft, 'unsupported_multi_event');
    return _money(input, createdAt, inputMode, v1Draft) ??
        _sport(input, createdAt, inputMode, v1Draft) ??
        _work(input, createdAt, inputMode, v1Draft) ??
        _english(input, createdAt, inputMode, v1Draft);
  }

  CaptureEnvelopeV2? _money(String input, DateTime createdAt,
      CaptureInputMode inputMode, CaptureDraft? v1Draft) {
    final lower = input.toLowerCase();
    if (RegExp(r'\d[.,]{2,}\d|-[0-9]').hasMatch(lower)) {
      return _unsupported(input, createdAt, inputMode, v1Draft,
          'money_amount_invalid_or_precision_unsupported');
    }
    final expense =
        RegExp(r'купил|потратил|заплатил|оплатил|отдал|sarfladim|toladim|to\x27ladim|berdim|sotib oldim|\bspent\b|\bpaid\b|\bbought\b')
                .hasMatch(lower) &&
            !lower.contains('got paid');
    final income =
        RegExp(r'получил|получила|пришло|пришла|перевели|зарплат|зп|заработал|заработала|maosh|tushdi|kelib tushdi|oldim|\breceived\b|\bgot paid\b|\bsalary\b|\bearned\b')
                .hasMatch(lower) &&
            !lower.contains('sotib oldim');
    if (!expense && !income) return null;
    if (expense && income)
      return _unsupported(
          input, createdAt, inputMode, v1Draft, 'ambiguous_money_direction');
    final matches = _amountToken.allMatches(lower).toList();
    if (matches.length != 1)
      return _unsupported(input, createdAt, inputMode, v1Draft,
          matches.isEmpty ? 'money_amount_missing' : 'unsupported_multi_event');
    final currency = _currency(lower, matches.single.group(0)!);
    final parsed = _exactMinorUnits(
      matches.single.group(1)!,
      matches.single.group(2),
      currency.$1,
    );
    if (parsed == null)
      return _unsupported(input, createdAt, inputMode, v1Draft,
          'money_amount_invalid_or_precision_unsupported');
    final unresolved = <V2UnresolvedField>[
      const V2UnresolvedField(
          field: 'account',
          reason: 'no account identity is inferred from payment method',
          risk: 'low',
          suggestedResolution: 'allow_unassigned'),
      const V2UnresolvedField(
          field: 'category',
          reason: 'no canonical category mapping in shadow core',
          risk: 'low',
          suggestedResolution: 'allow_unclassified'),
    ];
    final paymentMethod = _paymentMethod(lower);
    final dateExpression = _temporal(lower);
    if (dateExpression != null) {
      unresolved.add(const V2UnresolvedField(
          field: 'occurredAt',
          reason: 'relative date is retained as text, not silently resolved',
          risk: 'medium',
          suggestedResolution: 'user_review'));
    }
    return _envelope(
      input,
      createdAt,
      inputMode,
      v1Draft,
      MoneyIntentV2(
        direction: income ? MoneyDirectionV2.income : MoneyDirectionV2.expense,
        minorUnits: parsed,
        currency: currency.$1,
        account: 'unassigned',
        category: 'unclassified',
        description: _description(input, matches.single.group(0)!),
        paymentMethod: paymentMethod,
      ),
      V2ProjectionCandidate.moneyTransaction,
      unresolved: unresolved,
      occurredAtExpression: dateExpression,
      provenance: {
        'intent': const V2FieldProvenance(
            source: V2FieldSource.parser, confidence: V2Confidence.high),
        'amount': const V2FieldProvenance(
            source: V2FieldSource.userExplicit, confidence: V2Confidence.high),
        'currency': V2FieldProvenance(
            source: currency.$2
                ? V2FieldSource.userExplicit
                : V2FieldSource.defaultVisible,
            confidence: currency.$2 ? V2Confidence.high : V2Confidence.medium),
        'account': const V2FieldProvenance(
            source: V2FieldSource.defaultVisible,
            confidence: V2Confidence.unresolved),
        'category': const V2FieldProvenance(
            source: V2FieldSource.defaultVisible,
            confidence: V2Confidence.unresolved),
        if (paymentMethod != null)
          'paymentMethod': const V2FieldProvenance(
              source: V2FieldSource.userExplicit,
              confidence: V2Confidence.high),
      },
    );
  }

  CaptureEnvelopeV2? _sport(String input, DateTime createdAt,
      CaptureInputMode mode, CaptureDraft? v1) {
    final lower = input.toLowerCase();
    final set = RegExp(
            r'(жим|присед|bench|squat|bosdim).{0,18}?(\d+(?:[.,]\d+)?)\s*(?:кг|kg)?\s*(?:x|на|ga)?\s*(\d+)')
        .firstMatch(lower);
    if (set != null)
      return _envelope(
        input,
        createdAt,
        mode,
        v1,
        SportIntentV2(
            intent: 'detailed_set',
            exerciseRaw: set.group(1),
            weight: set.group(2),
            reps: int.tryParse(set.group(3)!),
            unit: 'kg'),
        V2ProjectionCandidate.sportSetCandidate,
        unresolved: const [
          V2UnresolvedField(
              field: 'exerciseId',
              reason: 'raw exercise is not a canonical exercise identity',
              risk: 'medium',
              suggestedResolution: 'user_select')
        ],
        provenance: const {
          'exerciseRaw': V2FieldProvenance(
              source: V2FieldSource.userExplicit, confidence: V2Confidence.high)
        },
      );
    final reverseSet = RegExp(
            r'(\d+(?:[.,]\d+)?)\s*(?:кг|kg)\s*(\d+)\s*(?:раз|marta)?\s*(bench|squat)')
        .firstMatch(lower);
    if (reverseSet != null)
      return _envelope(
        input,
        createdAt,
        mode,
        v1,
        SportIntentV2(
            intent: 'detailed_set',
            exerciseRaw: reverseSet.group(3),
            weight: reverseSet.group(1),
            reps: int.tryParse(reverseSet.group(2)!),
            unit: 'kg'),
        V2ProjectionCandidate.sportSetCandidate,
        unresolved: const [
          V2UnresolvedField(
              field: 'exerciseId',
              reason: 'raw exercise is not a canonical exercise identity',
              risk: 'medium',
              suggestedResolution: 'user_select')
        ],
      );
    final activity = RegExp(
            r'(пробеж|yugur|ran|basketball|basketbol|баскетбол|теннис|tennis)')
        .firstMatch(lower);
    final duration =
        RegExp(r'(\d+)\s*(минут|мин|minutes|daqiqa)').firstMatch(lower);
    final distance = RegExp(r'(\d+(?:[.,]\d+)?)\s*км|\b(\d+(?:[.,]\d+)?)\s*km')
        .firstMatch(lower);
    if (activity == null) return null;
    return _envelope(
      input,
      createdAt,
      mode,
      v1,
      SportIntentV2(
          intent: 'activity',
          activityType: activity.group(1),
          durationMinutes:
              duration == null ? null : int.tryParse(duration.group(1)!)),
      V2ProjectionCandidate.sportSetCandidate,
      unresolved: [
        if (distance != null)
          const V2UnresolvedField(
              field: 'distance',
              reason:
                  'distance is retained for review but no canonical activity mapping exists',
              risk: 'low',
              suggestedResolution: 'user_review')
      ],
      provenance: const {
        'activityType': V2FieldProvenance(
            source: V2FieldSource.userExplicit, confidence: V2Confidence.high)
      },
    );
  }

  CaptureEnvelopeV2? _work(String input, DateTime createdAt,
      CaptureInputMode mode, CaptureDraft? v1) {
    final lower = input.toLowerCase();
    final reminder =
        RegExp(r'завтра|tomorrow|ertaga|написать|писать|yozish|call .*tomorrow')
            .hasMatch(lower);
    final interaction =
        RegExp(r'позвонил|созвон|call(?:ed)?|qo\x27ng|mijoz').hasMatch(lower);
    if (!reminder && !interaction) return null;
    final temporal = _temporal(lower);
    return _envelope(
      input,
      createdAt,
      mode,
      v1,
      WorkIntentV2(
          intent: reminder ? 'follow_up' : 'interaction',
          contactRaw: _contact(input),
          dueDate: temporal),
      V2ProjectionCandidate.workInteraction,
      unresolved: [
        if (temporal != null)
          const V2UnresolvedField(
              field: 'dueDate',
              reason: 'relative due expression is not converted to a date',
              risk: 'medium',
              suggestedResolution: 'user_review')
      ],
      occurredAtExpression: temporal,
      provenance: const {
        'intent': V2FieldProvenance(
            source: V2FieldSource.parser, confidence: V2Confidence.medium)
      },
    );
  }

  CaptureEnvelopeV2? _english(String input, DateTime createdAt,
      CaptureInputMode mode, CaptureDraft? v1) {
    final lower = input.toLowerCase();
    if (!RegExp(r'english|английск|ingliz|словар|words|soz').hasMatch(lower))
      return null;
    final duration =
        RegExp(r'(\d+)\s*(минут|мин|minutes|daqiqa)').firstMatch(lower);
    return _envelope(
      input,
      createdAt,
      mode,
      v1,
      EnglishIntentV2(
          activity: 'learning_activity',
          durationMinutes:
              duration == null ? null : int.tryParse(duration.group(1)!)),
      V2ProjectionCandidate.englishActivity,
      provenance: const {
        'activity': V2FieldProvenance(
            source: V2FieldSource.parser, confidence: V2Confidence.medium)
      },
    );
  }

  (String, bool) _currency(String lower, String token) {
    if (token.contains(r'$') ||
        RegExp(r'\busd\b|dollar|доллар|бакс').hasMatch(lower))
      return ('USD', true);
    if (RegExp(r'\beur\b|euro|евро').hasMatch(lower)) return ('EUR', true);
    if (RegExp(r'сум|so\x27m|so.m|\buzs\b').hasMatch(lower))
      return ('UZS', true);
    return (
      'UZS',
      false
    ); // Product policy: visible locale default, never silent.
  }

  String? _exactMinorUnits(String number, String? suffix, String currency) {
    if (number.contains(RegExp(r'\.{2,}|,{2,}')) || number.startsWith('-'))
      return null;
    final normalized = number.replaceAll(',', '.');
    final parts = normalized.split('.');
    if (parts.length > 2 || parts.any((p) => p.isEmpty)) return null;
    final multiplier = switch ((suffix ?? '').toLowerCase()) {
      'k' || 'к' || 'тыс' || 'тысяч' || 'ming' => BigInt.from(1000),
      'млн' ||
      'миллион' ||
      'миллионов' ||
      'лям' ||
      'лямов' ||
      'mln' ||
      'million' =>
        BigInt.from(1000000),
      _ => BigInt.one
    };
    final scale =
        switch (currency) { 'UZS' => 0, 'USD' || 'EUR' => 2, _ => -1 };
    if (scale < 0) return null;
    final whole = BigInt.tryParse(parts.first);
    final fraction = parts.length == 2 ? parts[1] : '';
    if (whole == null || !RegExp(r'^\d*$').hasMatch(fraction)) return null;
    final denominator = BigInt.from(10).pow(fraction.length);
    final numerator = whole * denominator +
        (fraction.isEmpty ? BigInt.zero : BigInt.parse(fraction));
    final minorNumerator = numerator * multiplier * BigInt.from(10).pow(scale);
    if (minorNumerator.remainder(denominator) != BigInt.zero)
      return null; // no rounding policy
    final value = minorNumerator ~/ denominator;
    if (value <= BigInt.zero || value > BigInt.parse('999999999999999999'))
      return null;
    return value.toString();
  }

  bool _isMultiEvent(String input) {
    final lower = input.toLowerCase();
    return RegExp(r'\b(и|and|va|yana)\b').hasMatch(lower) &&
        _amountToken.allMatches(lower).length >= 2;
  }

  String? _paymentMethod(String lower) =>
      RegExp(r'налич|naqd|cash').hasMatch(lower)
          ? 'cash'
          : RegExp(r'карт|karta|card').hasMatch(lower)
              ? 'card'
              : null;
  String? _temporal(String lower) => RegExp(
          r'вчера|сегодня|завтра|today|yesterday|tomorrow|ertaga|\b\d{1,2}:\d{2}\b')
      .firstMatch(lower)
      ?.group(0);
  String? _description(String input, String amount) {
    final value = input.replaceFirst(amount, '').trim();
    return value.isEmpty ? null : value;
  }

  String? _contact(String input) =>
      RegExp(r'(?:клиент\w*|мijoz\w*|director\w*|директор\w*|john|hasan)',
              caseSensitive: false)
          .firstMatch(input)
          ?.group(0);

  CaptureEnvelopeV2 _unsupported(String input, DateTime createdAt,
          CaptureInputMode mode, CaptureDraft? v1, String reason) =>
      _envelope(
          input,
          createdAt,
          mode,
          v1,
          const GenericIntentV2('unsupported'),
          V2ProjectionCandidate.unsupported,
          unsupported: true,
          unresolved: [
            V2UnresolvedField(
                field: 'intent',
                reason: reason,
                risk: 'medium',
                suggestedResolution: 'user_rephrase_or_review')
          ]);
  CaptureEnvelopeV2 _envelope(
          String input,
          DateTime createdAt,
          CaptureInputMode mode,
          CaptureDraft? v1,
          CaptureIntentV2 intent,
          V2ProjectionCandidate candidate,
          {Map<String, V2FieldProvenance> provenance = const {},
          List<V2UnresolvedField> unresolved = const [],
          String? occurredAtExpression,
          bool unsupported = false}) =>
      CaptureEnvelopeV2(
          captureId: sha256
              .convert(utf8.encode(
                  'personal-tracker/capture-v2-shadow/v2|${createdAt.toUtc().toIso8601String()}|$input'))
              .toString()
              .substring(0, 32),
          schemaVersion: 2,
          originalText: input,
          inputMode: mode,
          createdAt: createdAt,
          occurredAt: null,
          occurredAtExpression: occurredAtExpression,
          timezone: createdAt.timeZoneName,
          intent: intent,
          provenance: provenance,
          unresolved: unresolved,
          reviewState: unsupported
              ? V2ReviewState.unsupported
              : (unresolved.any((u) => u.risk == 'high')
                  ? V2ReviewState.needsReview
                  : V2ReviewState.parsed),
          projectionCandidate: candidate,
          confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
          parserName: 'deterministic-v2-shadow',
          v1Draft: v1);
}
