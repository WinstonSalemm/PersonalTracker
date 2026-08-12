/// Local, explainable first-use intake for the English module.
///
/// The diagnostic is deliberately a *placement hint*, not an exam or an AI
/// assessment. Grammar and reading answers are scored locally; listening and
/// speaking are explicitly marked as self-reported until checked elsewhere.
enum EnglishGoal { work, relocation, travel, conversation, exam, study }

extension EnglishGoalLabel on EnglishGoal {
  String get label => switch (this) {
    EnglishGoal.work => 'работа и карьера',
    EnglishGoal.relocation => 'переезд и жизнь за границей',
    EnglishGoal.travel => 'путешествия',
    EnglishGoal.conversation => 'разговорная практика',
    EnglishGoal.exam => 'экзамен',
    EnglishGoal.study => 'учёба и общий уровень',
  };

  String get youtubeQuery => switch (this) {
    EnglishGoal.work => 'English at work B1 listening with transcript',
    EnglishGoal.relocation =>
      'English everyday life B1 listening with transcript',
    EnglishGoal.travel => 'English travel situations A2 B1 listening',
    EnglishGoal.conversation => 'English conversation practice A2 B1',
    EnglishGoal.exam => 'English exam listening practice official sample',
    EnglishGoal.study => 'English B1 listening with transcript',
  };
}

enum EnglishCourseLength {
  sixWeeks,
  twelveWeeks,
  twentyFourWeeks,
  thirtySixWeeks,
}

extension EnglishCourseLengthLabel on EnglishCourseLength {
  String get label => switch (this) {
    EnglishCourseLength.sixWeeks => '6 недель',
    EnglishCourseLength.twelveWeeks => '12 недель',
    EnglishCourseLength.twentyFourWeeks => '24 недели',
    EnglishCourseLength.thirtySixWeeks => '36 недель',
  };

  int get weeks => switch (this) {
    EnglishCourseLength.sixWeeks => 6,
    EnglishCourseLength.twelveWeeks => 12,
    EnglishCourseLength.twentyFourWeeks => 24,
    EnglishCourseLength.thirtySixWeeks => 36,
  };
}

enum EnglishIntensity { gentle, steady, focused }

extension EnglishIntensityLabel on EnglishIntensity {
  String get label => switch (this) {
    EnglishIntensity.gentle => 'бережный',
    EnglishIntensity.steady => 'стабильный',
    EnglishIntensity.focused => 'интенсивный',
  };

  String get schedule => switch (this) {
    EnglishIntensity.gentle => '3 занятия по 20–25 минут в неделю',
    EnglishIntensity.steady => '5 занятий по 30–40 минут в неделю',
    EnglishIntensity.focused => '6 занятий по 50–60 минут в неделю',
  };

  int get minutesPerWeek => switch (this) {
    EnglishIntensity.gentle => 70,
    EnglishIntensity.steady => 175,
    EnglishIntensity.focused => 330,
  };
}

enum EnglishPlacementBand { a1ToA2, a2ToB1, b1ToB2 }

extension EnglishPlacementBandLabel on EnglishPlacementBand {
  String get label => switch (this) {
    EnglishPlacementBand.a1ToA2 => 'ориентир A1–A2',
    EnglishPlacementBand.a2ToB1 => 'ориентир A2–B1',
    EnglishPlacementBand.b1ToB2 => 'ориентир B1–B2',
  };
}

class EnglishLearningProfile {
  const EnglishLearningProfile({
    required this.goal,
    required this.courseLength,
    required this.intensity,
    required this.placement,
    required this.grammarReadingScore,
    required this.listeningSelfReport,
    required this.speakingSelfReport,
    required this.preferredFormats,
    required this.createdAt,
    this.goalNarrative = '',
    this.intakeFacts = const {},
    this.missingFacts = const [],
    this.aiSummary = '',
  });

  final EnglishGoal goal;
  final EnglishCourseLength courseLength;
  final EnglishIntensity intensity;
  final EnglishPlacementBand placement;
  final int grammarReadingScore;
  final String listeningSelfReport;
  final String speakingSelfReport;
  final List<String> preferredFormats;
  final DateTime createdAt;
  final String goalNarrative;
  final Map<String, String> intakeFacts;
  final List<String> missingFacts;
  final String aiSummary;

  String get goalText =>
      goalNarrative.trim().isEmpty ? goal.label : goalNarrative.trim();
  String get deadlineText => intakeFacts['deadline']?.trim() ?? '';

  String get workload => intensity.schedule;

  /// Honest description: it deliberately avoids a promised CEFR result.
  String get outcomeBoundary =>
      'За ${courseLength.weeks} недель цель — регулярная практика для «${goal.label}». '
      'Это не обещание уровня, беглости или результата экзамена.';

  String get confidenceNote =>
      'Ориентир получен по 4 коротким заданиям на грамматику и чтение. '
      'Аудирование и речь отмечены по твоей самооценке; это не официальный тест.';

  String get youtubeSearchUrl => Uri.https('www.youtube.com', '/results', {
    'search_query': goal.youtubeQuery,
  }).toString();

  Map<String, Object> toJson() => {
    'goal': goal.name,
    'courseLength': courseLength.name,
    'intensity': intensity.name,
    'placement': placement.name,
    'grammarReadingScore': grammarReadingScore,
    'listeningSelfReport': listeningSelfReport,
    'speakingSelfReport': speakingSelfReport,
    'preferredFormats': preferredFormats,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'goalNarrative': goalNarrative,
    'intakeFacts': intakeFacts,
    'missingFacts': missingFacts,
    'aiSummary': aiSummary,
  };

  factory EnglishLearningProfile.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String? raw, T fallback) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
      return fallback;
    }

    return EnglishLearningProfile(
      goal: enumValue(
        EnglishGoal.values,
        json['goal'] as String?,
        EnglishGoal.study,
      ),
      courseLength: enumValue(
        EnglishCourseLength.values,
        json['courseLength'] as String?,
        EnglishCourseLength.twelveWeeks,
      ),
      intensity: enumValue(
        EnglishIntensity.values,
        json['intensity'] as String?,
        EnglishIntensity.steady,
      ),
      placement: enumValue(
        EnglishPlacementBand.values,
        json['placement'] as String?,
        EnglishPlacementBand.a2ToB1,
      ),
      grammarReadingScore: ((json['grammarReadingScore'] as num?)?.toInt() ?? 0)
          .clamp(0, 4),
      listeningSelfReport:
          json['listeningSelfReport'] as String? ?? 'не оценено',
      speakingSelfReport: json['speakingSelfReport'] as String? ?? 'не оценено',
      preferredFormats: [
        for (final value in (json['preferredFormats'] as List? ?? const []))
          if (value is String) value,
      ],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      goalNarrative: json['goalNarrative'] as String? ?? '',
      intakeFacts: {
        for (final entry in (json['intakeFacts'] as Map? ?? const {}).entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      },
      missingFacts: [
        for (final value in (json['missingFacts'] as List? ?? const []))
          if (value is String) value,
      ],
      aiSummary: json['aiSummary'] as String? ?? '',
    );
  }
}

EnglishPlacementBand placementForScore(int score) {
  if (score <= 1) return EnglishPlacementBand.a1ToA2;
  if (score <= 3) return EnglishPlacementBand.a2ToB1;
  return EnglishPlacementBand.b1ToB2;
}
