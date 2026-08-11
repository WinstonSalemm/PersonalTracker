/// Local, explainable profile matching for Sport.
///
/// This deliberately does not diagnose injuries or invent a programme from a
/// web page. A future server-side AI may use the same saved intake, but the
/// application always shows the chosen source and keeps the final choice with
/// the person using it.
enum SportAgeGroup { under18, age18to34, age35to49, age50to64, age65plus }

extension SportAgeGroupLabel on SportAgeGroup {
  String get label => switch (this) {
        SportAgeGroup.under18 => 'до 18',
        SportAgeGroup.age18to34 => '18–34',
        SportAgeGroup.age35to49 => '35–49',
        SportAgeGroup.age50to64 => '50–64',
        SportAgeGroup.age65plus => '65+',
      };
}

enum SportExperience { newToTraining, returning, regular }

extension SportExperienceLabel on SportExperience {
  String get label => switch (this) {
        SportExperience.newToTraining => 'начинаю',
        SportExperience.returning => 'возвращаюсь',
        SportExperience.regular => 'тренируюсь регулярно',
      };
}

enum SportGoal {
  fatLoss,
  muscleGain,
  strength,
  generalHealth,
  endurance,
  targeted
}

extension SportGoalLabel on SportGoal {
  String get label => switch (this) {
        SportGoal.fatLoss => 'снижение веса',
        SportGoal.muscleGain => 'набор мышц',
        SportGoal.strength => 'сила',
        SportGoal.generalHealth => 'здоровье и тонус',
        SportGoal.endurance => 'выносливость',
        SportGoal.targeted => 'конкретная часть тела',
      };
}

class SportTrainingProfile {
  const SportTrainingProfile({
    required this.ageGroup,
    required this.experience,
    required this.goal,
    required this.daysPerWeek,
    required this.focusAreas,
    required this.limitations,
    required this.hasMedicalClearance,
    required this.presetId,
    required this.sourceUrl,
    required this.sourceTitle,
    this.adaptation = 'none',
  });

  final SportAgeGroup ageGroup;
  final SportExperience experience;
  final SportGoal goal;
  final int daysPerWeek;
  final List<String> focusAreas;
  final String limitations;
  final bool hasMedicalClearance;
  final String presetId;
  final String sourceUrl;
  final String sourceTitle;
  final String adaptation;

  bool get hasLimitations => limitations.trim().isNotEmpty;
  bool get hasExternalSource => sourceUrl.trim().isNotEmpty;

  Map<String, Object> toJson() => {
        'ageGroup': ageGroup.name,
        'experience': experience.name,
        'goal': goal.name,
        'daysPerWeek': daysPerWeek,
        'focusAreas': focusAreas,
        'limitations': limitations,
        'hasMedicalClearance': hasMedicalClearance,
        'presetId': presetId,
        'sourceUrl': sourceUrl,
        'sourceTitle': sourceTitle,
        'adaptation': adaptation,
      };

  factory SportTrainingProfile.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String? raw, T fallback) =>
        values.where((value) => value.name == raw).firstOrNull ?? fallback;
    return SportTrainingProfile(
      ageGroup: enumValue(SportAgeGroup.values, json['ageGroup'] as String?,
          SportAgeGroup.age18to34),
      experience: enumValue(SportExperience.values,
          json['experience'] as String?, SportExperience.newToTraining),
      goal: enumValue(
          SportGoal.values, json['goal'] as String?, SportGoal.generalHealth),
      daysPerWeek: ((json['daysPerWeek'] as num?)?.toInt() ?? 3).clamp(2, 5),
      focusAreas: [
        for (final item in (json['focusAreas'] as List? ?? const []))
          if (item is String) item
      ],
      limitations: json['limitations'] as String? ?? '',
      hasMedicalClearance: json['hasMedicalClearance'] == true,
      presetId: json['presetId'] as String? ?? 'balanced-start',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceTitle: json['sourceTitle'] as String? ?? '',
      adaptation: json['adaptation'] as String? ?? 'none',
    );
  }

  SportTrainingProfile copyWith({String? presetId, String? adaptation}) =>
      SportTrainingProfile(
        ageGroup: ageGroup,
        experience: experience,
        goal: goal,
        daysPerWeek: daysPerWeek,
        focusAreas: focusAreas,
        limitations: limitations,
        hasMedicalClearance: hasMedicalClearance,
        presetId: presetId ?? this.presetId,
        sourceUrl: sourceUrl,
        sourceTitle: sourceTitle,
        adaptation: adaptation ?? this.adaptation,
      );
}

class SportPreset {
  const SportPreset({
    required this.id,
    required this.title,
    required this.summary,
    required this.frequency,
    required this.bestFor,
    required this.structure,
    required this.safetyNote,
  });

  final String id;
  final String title;
  final String summary;
  final String frequency;
  final List<SportGoal> bestFor;
  final String structure;
  final String safetyNote;
}

const sportPresets = [
  SportPreset(
    id: 'balanced-start',
    title: 'База и техника',
    summary: 'Спокойный full-body старт, чтобы собрать личные веса и технику.',
    frequency: '2–3 силовые / неделя',
    bestFor: [SportGoal.generalHealth, SportGoal.strength],
    structure:
        'A: push + ноги · B: тяга + задняя цепь · C: плечи + корпус · D: ноги + поддержка спины.',
    safetyNote:
        'Держи 3–4 повтора в запасе первые три сессии; боль в суставе — повод остановиться и уточнить у специалиста.',
  ),
  SportPreset(
    id: 'fat-loss-foundation',
    title: 'Снижение веса: силовая база',
    summary:
        'Сохраняет силовые стимулы, а ходьба и питание остаются отдельными привычками.',
    frequency: '3 силовые + ходьба',
    bestFor: [SportGoal.fatLoss],
    structure:
        'Короткие full-body сессии, 6–12 повторов, паузы 60–90 секунд; без экстремального дефицита и кардио-наказаний.',
    safetyNote:
        'Программа не задаёт калории и не обещает темп снижения веса. Корректируй нагрузку по сну, питанию и самочувствию.',
  ),
  SportPreset(
    id: 'hypertrophy-base',
    title: 'Набор мышц: объём без спешки',
    summary:
        'Больше управляемого объёма на ключевые группы с журналом подходов.',
    frequency: '3–4 силовые / неделя',
    bestFor: [SportGoal.muscleGain],
    structure:
        'Push / pull / legs с повторным акцентом на выбранную группу; 8–15 повторов, запас 1–3 повтора.',
    safetyNote:
        'Добавляй вес или повторения только после уверенной техники во всех рабочих подходах.',
  ),
  SportPreset(
    id: 'upper-focus',
    title: 'Акцент: верх тела',
    summary:
        'Дополнительный объём груди, спины, плеч или рук без удаления тренировки ног.',
    frequency: '3–4 силовые / неделя',
    bestFor: [SportGoal.targeted, SportGoal.muscleGain],
    structure:
        'Две тренировки верха, одна full-body/ноги; выбранная группа получает 2–4 дополнительных качественных подхода.',
    safetyNote:
        'Не увеличивай объём на болезненную область и не жертвуй сном ради четвёртой тренировки.',
  ),
  SportPreset(
    id: 'lower-focus',
    title: 'Акцент: ноги и задняя цепь',
    summary:
        'Планомерная работа ног, ягодиц и задней поверхности с поддержкой спины.',
    frequency: '3 силовые / неделя',
    bestFor: [SportGoal.targeted, SportGoal.strength],
    structure:
        'Две тренировки низа с разной нагрузкой и один день верха; объём повышается только после адаптации.',
    safetyNote:
        'При дискомфорте в колене, тазобедренном суставе или пояснице не подбирай замену автоматически — согласуй её со специалистом.',
  ),
  SportPreset(
    id: 'return-to-training',
    title: 'Возвращение к нагрузке',
    summary:
        'Минимальный объём, простые движения и постепенное возвращение привычки.',
    frequency: '2 силовые + ходьба',
    bestFor: [SportGoal.generalHealth, SportGoal.endurance],
    structure:
        'Две короткие full-body сессии, лёгкая мобильность и перерыв между силовыми днями.',
    safetyNote:
        'Если есть недавняя травма, операция, сильная боль или врачебные ограничения, нужен персональный план специалиста.',
  ),
];

SportPreset presetById(String id) =>
    sportPresets.where((item) => item.id == id).firstOrNull ??
    sportPresets.first;

SportPreset recommendSportPreset({
  required SportGoal goal,
  required SportExperience experience,
  required bool hasLimitations,
  required List<String> focusAreas,
}) {
  if (hasLimitations || experience == SportExperience.returning) {
    return presetById('return-to-training');
  }
  if (goal == SportGoal.targeted) {
    final lower = focusAreas.join(' ').toLowerCase();
    return presetById(lower.contains('ног') || lower.contains('ягод')
        ? 'lower-focus'
        : 'upper-focus');
  }
  return sportPresets
          .where((item) => item.bestFor.contains(goal))
          .firstOrNull ??
      sportPresets.first;
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
