import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_domain/domain.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';

part 'v2_deterministic_parser.dart';

class CaptureV2FeatureFlags {
  const CaptureV2FeatureFlags._();

  static const captureCoreV2Shadow = bool.fromEnvironment(
    'CAPTURE_CORE_V2_SHADOW',
    defaultValue: false,
  );

  /// Explicitly opt-in failure injection for an enabled-hook runtime test.
  /// It is false in every normal build and has no V1 behavior branch.
  static const captureCoreV2ShadowForceFailure = bool.fromEnvironment(
    'CAPTURE_CORE_V2_SHADOW_FORCE_FAILURE',
    defaultValue: false,
  );
  static const captureMoneyV2 =
      bool.fromEnvironment('CAPTURE_MONEY_V2', defaultValue: false);

  /// Internal-rollout builds fetch account-scoped capabilities from the API.
  /// A missing or unavailable remote configuration must fall back to V1.
  static const remoteRolloutEnabled = bool.fromEnvironment(
    'CAPTURE_V2_REMOTE_ROLLOUT',
    defaultValue: false,
  );
}

enum CaptureInputMode { text, voiceTranscript }

enum V2ReviewState {
  created,
  parsed,
  needsReview,
  reviewed,
  shadowReady,
  unsupported,
  discarded,
  parseFailed,
}

enum V2ProjectionCandidate {
  moneyTransaction,
  workInteraction,
  sportSetCandidate,
  englishActivity,
  genericCapture,
  unsupported,
}

enum V2FieldSource { userExplicit, parser, defaultVisible, derived }

enum V2Confidence { high, medium, low, unresolved }

enum V2ConfirmationPolicy {
  alwaysReview,
  reviewIfAmbiguous,
  autoCommitEligible,
}

sealed class CaptureIntentV2 {
  const CaptureIntentV2();
  String get kind;
  Map<String, Object?> toJson();
}

enum MoneyDirectionV2 { expense, income }

class MoneyIntentV2 extends CaptureIntentV2 {
  const MoneyIntentV2({
    required this.direction,
    required this.minorUnits,
    required this.currency,
    required this.account,
    required this.category,
    this.description,
    this.paymentMethod,
    this.counterparty,
  });

  final MoneyDirectionV2 direction;
  final String minorUnits;
  final String currency;
  final String account;
  final String category;
  final String? description;
  final String? paymentMethod;
  final String? counterparty;

  MoneyIntentV2 copyWith({
    MoneyDirectionV2? direction,
    String? minorUnits,
    String? currency,
    String? account,
    String? category,
    String? description,
    String? paymentMethod,
    String? counterparty,
  }) =>
      MoneyIntentV2(
        direction: direction ?? this.direction,
        minorUnits: minorUnits ?? this.minorUnits,
        currency: currency ?? this.currency,
        account: account ?? this.account,
        category: category ?? this.category,
        description: description ?? this.description,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        counterparty: counterparty ?? this.counterparty,
      );

  @override
  String get kind => 'money.${direction.name}';

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'direction': direction.name,
        'minorUnits': minorUnits,
        'currency': currency,
        'account': account,
        'category': category,
        'description': description,
        'paymentMethod': paymentMethod,
        'counterparty': counterparty,
      };
}

class WorkIntentV2 extends CaptureIntentV2 {
  const WorkIntentV2({
    required this.intent,
    this.contactRaw,
    this.outcome,
    this.followUp,
    this.dueDate,
  });

  final String intent;
  final String? contactRaw;
  final String? outcome;
  final String? followUp;
  final String? dueDate;

  @override
  String get kind => 'work.$intent';

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'contactRaw': contactRaw,
        'outcome': outcome,
        'followUp': followUp,
        'dueDate': dueDate,
      };
}

class SportIntentV2 extends CaptureIntentV2 {
  const SportIntentV2({
    required this.intent,
    this.activityType,
    this.exerciseRaw,
    this.weight,
    this.reps,
    this.unit,
    this.durationMinutes,
  });

  final String intent;
  final String? activityType;
  final String? exerciseRaw;
  final String? weight;
  final int? reps;
  final String? unit;
  final int? durationMinutes;

  @override
  String get kind => 'sport.$intent';

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'activityType': activityType,
        'exerciseRaw': exerciseRaw,
        'weight': weight,
        'reps': reps,
        'unit': unit,
        'durationMinutes': durationMinutes,
      };
}

class EnglishIntentV2 extends CaptureIntentV2 {
  const EnglishIntentV2({required this.activity, this.durationMinutes});

  final String activity;
  final int? durationMinutes;

  @override
  String get kind => 'english.learning_activity';

  @override
  Map<String, Object?> toJson() => {
        'kind': kind,
        'activity': activity,
        'durationMinutes': durationMinutes,
      };
}

class GenericIntentV2 extends CaptureIntentV2 {
  const GenericIntentV2(this.intent);
  final String intent;

  @override
  String get kind => 'generic.$intent';

  @override
  Map<String, Object?> toJson() => {'kind': kind};
}

class V2FieldProvenance {
  const V2FieldProvenance({
    required this.source,
    required this.confidence,
    this.editedByUser = false,
    this.originalValue,
  });

  final V2FieldSource source;
  final V2Confidence confidence;
  final bool editedByUser;
  final Object? originalValue;

  Map<String, Object?> toJson() => {
        'source': source.name,
        'confidence': confidence.name,
        'editedByUser': editedByUser,
        'originalValue': originalValue,
      };
}

class V2UnresolvedField {
  const V2UnresolvedField({
    required this.field,
    required this.reason,
    required this.risk,
    required this.suggestedResolution,
  });

  final String field;
  final String reason;
  final String risk;
  final String suggestedResolution;

  Map<String, Object?> toJson() => {
        'field': field,
        'reason': reason,
        'risk': risk,
        'suggestedResolution': suggestedResolution,
      };
}

class CaptureEnvelopeV2 {
  const CaptureEnvelopeV2({
    required this.captureId,
    required this.schemaVersion,
    required this.originalText,
    required this.inputMode,
    required this.createdAt,
    required this.occurredAt,
    required this.occurredAtExpression,
    required this.timezone,
    required this.intent,
    required this.provenance,
    required this.unresolved,
    required this.reviewState,
    required this.projectionCandidate,
    required this.confirmationPolicy,
    required this.parserName,
    this.v1Draft,
  });

  final String captureId;
  final int schemaVersion;
  final String originalText;
  final CaptureInputMode inputMode;
  final DateTime createdAt;
  final DateTime? occurredAt;
  final String? occurredAtExpression;
  final String timezone;
  final CaptureIntentV2 intent;
  final Map<String, V2FieldProvenance> provenance;
  final List<V2UnresolvedField> unresolved;
  final V2ReviewState reviewState;
  final V2ProjectionCandidate projectionCandidate;
  final V2ConfirmationPolicy confirmationPolicy;
  final String parserName;
  final CaptureDraft? v1Draft;

  bool get isUnsupported => reviewState == V2ReviewState.unsupported;

  Map<String, Object?> toJson() => {
        'captureId': captureId,
        'schemaVersion': schemaVersion,
        'originalText': originalText,
        'inputMode': inputMode.name,
        'parser': {'name': parserName, 'source': 'v1_compatibility_adapter'},
        'createdAt': createdAt.toUtc().toIso8601String(),
        'occurredAt': occurredAt?.toUtc().toIso8601String(),
        'occurredAtExpression': occurredAtExpression,
        'timezone': timezone,
        'intent': intent.toJson(),
        'provenance':
            provenance.map((key, value) => MapEntry(key, value.toJson())),
        'unresolved': unresolved.map((value) => value.toJson()).toList(),
        'reviewState': reviewState.name,
        'projectionCandidate': projectionCandidate.name,
        'confirmationPolicy': confirmationPolicy.name,
      };

  String toJsonString() => jsonEncode(toJson());

  CaptureEnvelopeV2 withReviewState(V2ReviewState next) => CaptureEnvelopeV2(
        captureId: captureId,
        schemaVersion: schemaVersion,
        originalText: originalText,
        inputMode: inputMode,
        createdAt: createdAt,
        occurredAt: occurredAt,
        occurredAtExpression: occurredAtExpression,
        timezone: timezone,
        intent: intent,
        provenance: provenance,
        unresolved: unresolved,
        reviewState: next,
        projectionCandidate: projectionCandidate,
        confirmationPolicy: confirmationPolicy,
        parserName: parserName,
        v1Draft: v1Draft,
      );

  CaptureEnvelopeV2 withMoneyEdits({
    String? account,
    String? category,
  }) {
    final current = intent;
    if (current is! MoneyIntentV2) return this;
    final edited = current.copyWith(account: account, category: category);
    final nextProvenance = Map<String, V2FieldProvenance>.from(provenance);
    if (account != null) {
      nextProvenance['account'] = V2FieldProvenance(
        source: V2FieldSource.userExplicit,
        confidence: V2Confidence.high,
        editedByUser: true,
        originalValue: current.account,
      );
    }
    if (category != null) {
      nextProvenance['category'] = V2FieldProvenance(
        source: V2FieldSource.userExplicit,
        confidence: V2Confidence.high,
        editedByUser: true,
        originalValue: current.category,
      );
    }
    return CaptureEnvelopeV2(
      captureId: captureId,
      schemaVersion: schemaVersion,
      originalText: originalText,
      inputMode: inputMode,
      createdAt: createdAt,
      occurredAt: occurredAt,
      occurredAtExpression: occurredAtExpression,
      timezone: timezone,
      intent: edited,
      provenance: nextProvenance,
      unresolved: unresolved
          .where((item) =>
              (account == null || item.field != 'account') &&
              (category == null || item.field != 'category'))
          .toList(),
      reviewState: reviewState,
      projectionCandidate: projectionCandidate,
      confirmationPolicy: confirmationPolicy,
      parserName: parserName,
      v1Draft: v1Draft,
    );
  }
}

class V1ParserToV2Adapter {
  const V1ParserToV2Adapter(this.parser);
  final CommandParser parser;

  Future<CaptureEnvelopeV2> parse(
    String input, {
    DateTime? now,
    CaptureInputMode inputMode = CaptureInputMode.text,
  }) async {
    final createdAt = now ?? DateTime.now();
    final value = input.trim();
    if (value.isEmpty) {
      return _unsupported(value, createdAt, inputMode, 'empty_input');
    }
    if (_looksMultiEvent(value)) {
      return _unsupported(
        value,
        createdAt,
        inputMode,
        'unsupported_multi_event',
      );
    }
    try {
      final draft = await parser.parse(value);
      final enriched = V2DeterministicShadowParser().parse(
        value,
        createdAt: createdAt,
        inputMode: inputMode,
        v1Draft: draft,
      );
      if (enriched != null) return enriched;
      if (draft == null) {
        return _unsupported(
          value,
          createdAt,
          inputMode,
          'v1_parser_unsupported',
        );
      }
      return _fromDraft(draft, createdAt, inputMode);
    } catch (_) {
      return CaptureEnvelopeV2(
        captureId: _captureId(value, createdAt),
        schemaVersion: 2,
        originalText: value,
        inputMode: inputMode,
        createdAt: createdAt,
        occurredAt: null,
        occurredAtExpression: null,
        timezone: createdAt.timeZoneName,
        intent: const GenericIntentV2('parse_failed'),
        provenance: const {},
        unresolved: const [
          V2UnresolvedField(
            field: 'intent',
            reason: 'v1 parser threw',
            risk: 'high',
            suggestedResolution: 'inspect_diagnostic',
          ),
        ],
        reviewState: V2ReviewState.parseFailed,
        projectionCandidate: V2ProjectionCandidate.unsupported,
        confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
        parserName: 'deterministic-v1',
      );
    }
  }

  CaptureEnvelopeV2 _fromDraft(
    CaptureDraft draft,
    DateTime createdAt,
    CaptureInputMode inputMode,
  ) {
    final occurredAtExpression = _temporalExpression(draft.originalText);
    final occurredAt =
        occurredAtExpression == null ? DateTime.tryParse(draft.date) : null;
    final provenance = <String, V2FieldProvenance>{
      'intent': const V2FieldProvenance(
        source: V2FieldSource.parser,
        confidence: V2Confidence.medium,
      ),
      'occurredAt': const V2FieldProvenance(
        source: V2FieldSource.parser,
        confidence: V2Confidence.medium,
      ),
    };
    final unresolved = <V2UnresolvedField>[];
    if (occurredAtExpression != null) {
      unresolved.add(
        const V2UnresolvedField(
          field: 'occurredAt',
          reason: 'V1 parser did not resolve the local time expression',
          risk: 'medium',
          suggestedResolution: 'resolve_or_leave_unresolved',
        ),
      );
    }
    late CaptureIntentV2 intent;
    late V2ProjectionCandidate projection;
    switch (draft.type) {
      case CaptureType.expense:
      case CaptureType.income:
        // A V2 Money envelope is never derived from V1's `double` amount.
        // The V2-only textual parser above either creates an exact envelope or
        // the input remains unsupported in shadow mode.
        return _unsupported(
          draft.originalText,
          createdAt,
          inputMode,
          'v2_exact_money_semantics_unsupported',
        );
      /* final amount = draft.amount;
        if (amount == null || amount.isNaN || amount.isInfinite) {
          unresolved.add(
            const V2UnresolvedField(
              field: 'amount',
              reason: 'amount missing or invalid',
              risk: 'high',
              suggestedResolution: 'user_edit',
            ),
          );
        }
        final currency = draft.currency.trim().isEmpty ? 'UZS' : draft.currency;
        final account = 'unassigned';
        final category = (draft.category == null ||
                draft.category!.trim().isEmpty ||
                draft.category == 'other')
            ? 'unclassified'
            : draft.category!;
        if (draft.category == null ||
            draft.category!.trim().isEmpty ||
            draft.category == 'other') {
          unresolved.add(
            const V2UnresolvedField(
              field: 'category',
              reason: 'V1 parser did not resolve category',
              risk: 'low',
              suggestedResolution: 'allow_unclassified',
            ),
          );
        }
        if (draft.paymentMethod == null || draft.paymentMethod == 'other') {
          unresolved.add(
            const V2UnresolvedField(
              field: 'account',
              reason: 'no explicit account identity in V1 draft',
              risk: 'low',
              suggestedResolution: 'allow_unassigned',
            ),
          );
        }
        intent = MoneyIntentV2(
          direction: draft.type == CaptureType.income
              ? MoneyDirectionV2.income
              : MoneyDirectionV2.expense,
          minorUnits: _minorUnits(amount, currency),
          currency: currency,
          account: account,
          category: category,
          description: draft.description,
          paymentMethod: draft.paymentMethod,
        );
        provenance.addAll({
          'amount': V2FieldProvenance(
            source: V2FieldSource.parser,
            confidence:
                amount == null ? V2Confidence.unresolved : V2Confidence.medium,
          ),
          'currency': const V2FieldProvenance(
            source: V2FieldSource.parser,
            confidence: V2Confidence.medium,
          ),
          'account': V2FieldProvenance(
            source: V2FieldSource.defaultVisible,
            confidence: V2Confidence.unresolved,
          ),
          'category': V2FieldProvenance(
            source: draft.category == null || draft.category == 'other'
                ? V2FieldSource.defaultVisible
                : V2FieldSource.parser,
            confidence: draft.category == null || draft.category == 'other'
                ? V2Confidence.unresolved
                : V2Confidence.medium,
          ),
          if (draft.paymentMethod != null)
            'paymentMethod': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
          if (draft.description != null)
            'description': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
        });
        projection = V2ProjectionCandidate.moneyTransaction; */
      case CaptureType.salesCall:
        intent = WorkIntentV2(
          intent: draft.result == 'follow_up' ? 'follow_up' : 'interaction',
          contactRaw: draft.company,
          outcome: draft.result,
          followUp: draft.nextStep,
          dueDate: draft.followUpDate,
        );
        projection = V2ProjectionCandidate.workInteraction;
        provenance.addAll({
          if (draft.company != null)
            'contact': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
          if (draft.result != null)
            'outcome': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
          if (draft.nextStep != null)
            'followUp': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
          if (draft.followUpDate != null)
            'dueDate': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
        });
        if (draft.company == null || draft.company!.trim().isEmpty) {
          unresolved.add(
            const V2UnresolvedField(
              field: 'contact',
              reason: 'contact identity unresolved',
              risk: 'medium',
              suggestedResolution: 'user_select',
            ),
          );
        }
      case CaptureType.sports:
        intent = SportIntentV2(
          intent: draft.durationMinutes == null ? 'activity' : 'activity',
          activityType: draft.activityType,
          exerciseRaw: draft.comment,
          durationMinutes: draft.durationMinutes,
        );
        projection = V2ProjectionCandidate.sportSetCandidate;
        provenance.addAll({
          if (draft.activityType != null)
            'activityType': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
          if (draft.comment != null)
            'exerciseRaw': const V2FieldProvenance(
              source: V2FieldSource.userExplicit,
              confidence: V2Confidence.high,
            ),
          if (draft.durationMinutes != null)
            'durationMinutes': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
        });
        unresolved.add(
          const V2UnresolvedField(
            field: 'exerciseId',
            reason: 'V1 sports draft has no canonical exercise identity',
            risk: 'medium',
            suggestedResolution: 'user_select',
          ),
        );
      case CaptureType.english:
        intent = EnglishIntentV2(
          activity:
              draft.completedTask ?? draft.activityType ?? 'learning_activity',
          durationMinutes: draft.durationMinutes,
        );
        projection = V2ProjectionCandidate.englishActivity;
        provenance.addAll({
          'activity': const V2FieldProvenance(
            source: V2FieldSource.parser,
            confidence: V2Confidence.medium,
          ),
          if (draft.durationMinutes != null)
            'durationMinutes': const V2FieldProvenance(
              source: V2FieldSource.parser,
              confidence: V2Confidence.medium,
            ),
        });
    }
    final state = unresolved.any((item) => item.risk == 'high')
        ? V2ReviewState.needsReview
        : V2ReviewState.parsed;
    return CaptureEnvelopeV2(
      captureId: _captureId(draft.originalText, createdAt),
      schemaVersion: 2,
      originalText: draft.originalText,
      inputMode: inputMode,
      createdAt: createdAt,
      occurredAt: occurredAt,
      occurredAtExpression: occurredAtExpression ?? draft.date,
      timezone: createdAt.timeZoneName,
      intent: intent,
      provenance: provenance,
      unresolved: unresolved,
      reviewState: state,
      projectionCandidate: projection,
      confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
      parserName: 'deterministic-v1',
      v1Draft: draft,
    );
  }

  CaptureEnvelopeV2 _unsupported(
    String value,
    DateTime createdAt,
    CaptureInputMode inputMode,
    String reason,
  ) =>
      CaptureEnvelopeV2(
        captureId: _captureId(value, createdAt),
        schemaVersion: 2,
        originalText: value,
        inputMode: inputMode,
        createdAt: createdAt,
        occurredAt: null,
        occurredAtExpression: null,
        timezone: createdAt.timeZoneName,
        intent: GenericIntentV2(reason),
        provenance: const {},
        unresolved: [
          V2UnresolvedField(
            field: 'intent',
            reason: reason,
            risk: 'medium',
            suggestedResolution: 'user_rephrase_or_review',
          ),
        ],
        reviewState: V2ReviewState.unsupported,
        projectionCandidate: V2ProjectionCandidate.unsupported,
        confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
        parserName: 'deterministic-v1',
      );

  bool _looksMultiEvent(String value) {
    final lower = value.toLowerCase();
    final conjunction = lower.contains(' и ') || lower.contains(' and ');
    final amountMatches = RegExp(r'\d').allMatches(lower).length;
    return conjunction && amountMatches >= 2;
  }

  String? _temporalExpression(String value) {
    final match = RegExp(
      r'(вчера|сегодня|завтра|today|yesterday|tomorrow|\b\d{1,2}:\d{2}\b)',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(0);
  }

  String _captureId(String input, DateTime createdAt) => sha256
      .convert(
        utf8.encode(
          'personal-tracker/capture-v2-shadow/v1|${createdAt.toUtc().toIso8601String()}|$input',
        ),
      )
      .toString()
      .substring(0, 32);
}

class ShadowProjectionDecision {
  const ShadowProjectionDecision({
    required this.candidate,
    required this.reason,
  });

  final V2ProjectionCandidate candidate;
  final String reason;

  Map<String, Object?> toJson() => {
        'candidate': candidate.name,
        'reason': reason,
      };
}

class ShadowRunResult {
  const ShadowRunResult({
    required this.enabled,
    required this.envelope,
    required this.decision,
    required this.v1Draft,
    this.parseDurationMicros,
    this.persistenceDurationMicros,
    this.error,
  });

  final bool enabled;
  final CaptureEnvelopeV2? envelope;
  final ShadowProjectionDecision? decision;
  final CaptureDraft? v1Draft;
  final String? error;
  final int? parseDurationMicros;
  final int? persistenceDurationMicros;

  bool get failed => error != null;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'envelope': envelope?.toJson(),
        'decision': decision?.toJson(),
        'v1Draft': v1Draft?.toJson(),
        'error': error,
        'parseDurationMicros': parseDurationMicros,
        'persistenceDurationMicros': persistenceDurationMicros,
      };
}

class CaptureV2ShadowRunner {
  const CaptureV2ShadowRunner({
    required this.adapter,
    required this.database,
    this.enabled = CaptureV2FeatureFlags.captureCoreV2Shadow,
    this.forceFailureForTest =
        CaptureV2FeatureFlags.captureCoreV2ShadowForceFailure,
  });

  final V1ParserToV2Adapter adapter;
  final LocalDatabase database;
  final bool enabled;
  final bool forceFailureForTest;

  Future<ShadowRunResult?> run(String input, {DateTime? now}) async {
    if (!enabled) return null;
    try {
      if (forceFailureForTest)
        throw StateError('injected_shadow_runner_failure');
      final parseWatch = Stopwatch()..start();
      final envelope = await adapter.parse(input, now: now);
      parseWatch.stop();
      final decision = ShadowProjectionDecision(
        candidate: envelope.projectionCandidate,
        reason: envelope.isUnsupported
            ? 'no safe destination'
            : 'shadow destination only; no domain write',
      );
      final result = ShadowRunResult(
        enabled: true,
        envelope: envelope,
        decision: decision,
        v1Draft: envelope.v1Draft,
      );
      final persistWatch = Stopwatch()..start();
      await database.saveCaptureShadowV2(
        envelope.captureId,
        envelope.toJsonString(),
        jsonEncode(result.toJson()),
        projectionCandidate: decision.candidate.name,
        projectionDecisionJson: jsonEncode(decision.toJson()),
      );
      persistWatch.stop();
      return ShadowRunResult(
        enabled: result.enabled,
        envelope: result.envelope,
        decision: result.decision,
        v1Draft: result.v1Draft,
        parseDurationMicros: parseWatch.elapsedMicroseconds,
        persistenceDurationMicros: persistWatch.elapsedMicroseconds,
      );
    } catch (error) {
      final timestamp = now ?? DateTime.now();
      final failureEnvelope = CaptureEnvelopeV2(
        captureId: sha256
            .convert(utf8.encode(
                'personal-tracker/capture-v2-shadow/failure|${timestamp.toUtc().toIso8601String()}|$input'))
            .toString()
            .substring(0, 32),
        schemaVersion: 2,
        originalText: input,
        inputMode: CaptureInputMode.text,
        createdAt: timestamp,
        occurredAt: null,
        occurredAtExpression: null,
        timezone: timestamp.timeZoneName,
        intent: const GenericIntentV2('shadow_failure'),
        provenance: const {},
        unresolved: const [
          V2UnresolvedField(
              field: 'shadow',
              reason: 'shadow_runner_failure',
              risk: 'high',
              suggestedResolution: 'inspect_local_diagnostic')
        ],
        reviewState: V2ReviewState.parseFailed,
        projectionCandidate: V2ProjectionCandidate.unsupported,
        confirmationPolicy: V2ConfirmationPolicy.alwaysReview,
        parserName: 'deterministic-v2-shadow',
      );
      final result = ShadowRunResult(
        enabled: true,
        envelope: failureEnvelope,
        decision: null,
        v1Draft: null,
        error: error.toString(),
      );
      try {
        await database.saveCaptureShadowV2(
          failureEnvelope.captureId,
          failureEnvelope.toJsonString(),
          jsonEncode(result.toJson()),
        );
      } catch (_) {}
      return result;
    }
  }
}

class CanonicalMoneyCommitService {
  const CanonicalMoneyCommitService(this.database, {bool? enabled})
      : _enabled = enabled;
  final LocalDatabase database;
  final bool? _enabled;

  Future<String> confirm(CaptureEnvelopeV2 envelope, {String? failAt}) {
    if (!(_enabled ?? CaptureV2FeatureFlags.captureMoneyV2))
      throw StateError('capture_money_v2_disabled');
    if (envelope.reviewState != V2ReviewState.reviewed)
      throw StateError('money_review_required');
    final intent = envelope.intent;
    if (intent is! MoneyIntentV2 ||
        envelope.isUnsupported ||
        envelope.unresolved.any((u) => u.risk == 'high'))
      throw StateError('money_commit_ineligible');
    return database.commitCanonicalMoney(
        CanonicalMoneyCommitInput(
            captureId: envelope.captureId,
            intentJson: envelope.toJsonString(),
            minorUnits: intent.minorUnits,
            currency: intent.currency,
            direction: intent.direction.name,
            date: envelope.occurredAt?.toIso8601String().substring(0, 10) ??
                envelope.createdAt.toIso8601String().substring(0, 10),
            description: intent.description ?? envelope.originalText,
            paymentMethod: intent.paymentMethod ?? 'other',
            accountId: intent.account,
            categoryId: intent.category),
        failAt: failAt);
  }
}
