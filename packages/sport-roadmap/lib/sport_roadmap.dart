enum SportActivity { gym, mobility, recovery, checkpoint }

enum SportWorkoutTemplate { a, b, c, d }

extension SportWorkoutTemplateLabel on SportWorkoutTemplate {
  String get label => name.toUpperCase();

  String get title => switch (this) {
        SportWorkoutTemplate.a => 'Upper push + legs',
        SportWorkoutTemplate.b => 'Back + posterior chain',
        SportWorkoutTemplate.c => 'Shoulders + arms + core',
        SportWorkoutTemplate.d => 'Legs + back support',
      };
}

class SportExercisePlan {
  const SportExercisePlan({
    required this.id,
    required this.name,
    required this.equipment,
    required this.targetSets,
    required this.repRange,
    required this.technique,
  });

  final String id;
  final String name;
  final String equipment;
  final int targetSets;
  final String repRange;
  final String technique;

  SportExercisePlan copyWith({int? targetSets, String? repRange}) =>
      SportExercisePlan(
        id: id,
        name: name,
        equipment: equipment,
        targetSets: targetSets ?? this.targetSets,
        repRange: repRange ?? this.repRange,
        technique: technique,
      );
}

class SportWorkoutPlan {
  const SportWorkoutPlan({
    required this.id,
    required this.sessionNumber,
    required this.dayNumber,
    required this.phase,
    required this.template,
    required this.estimatedMinutes,
    required this.exercises,
    this.presetId = 'balanced-start',
  });

  final String id;
  final int sessionNumber;
  final int dayNumber;
  final int phase;
  final SportWorkoutTemplate template;
  final int estimatedMinutes;
  final List<SportExercisePlan> exercises;
  final String presetId;

  bool get requiresManualBaseline => sessionNumber <= 3;
}

class SportRoadmapDay {
  const SportRoadmapDay({
    required this.dayNumber,
    required this.phase,
    required this.activity,
    required this.title,
    required this.description,
    this.workout,
  });

  final int dayNumber;
  final int phase;
  final SportActivity activity;
  final String title;
  final String description;
  final SportWorkoutPlan? workout;
}

class SportRoadmap {
  const SportRoadmap({required this.days, required this.workouts});

  final List<SportRoadmapDay> days;
  final List<SportWorkoutPlan> workouts;
}

class SportHistorySet {
  const SportHistorySet({
    required this.sessionNumber,
    required this.exerciseId,
    required this.weightKg,
    required this.repetitions,
    required this.completed,
  });

  final int sessionNumber;
  final String exerciseId;
  final double weightKg;
  final int repetitions;
  final bool completed;
}

class SportLoadAdvice {
  const SportLoadAdvice({
    required this.weightKg,
    required this.reason,
    required this.isEstimate,
  });

  final double? weightKg;
  final String reason;
  final bool isEstimate;
}

/// Future AI replaces this interface without changing local workout storage.
abstract interface class SportLoadAdvisor {
  Future<Map<String, SportLoadAdvice>> suggestLoads(
    SportWorkoutPlan workout, {
    required List<SportHistorySet> history,
    required String? recoveryNote,
  });
}

/// Safe offline baseline. It only increases a known, completed load slightly;
/// it never invents a first weight when there is no personal history.
class DeterministicSportLoadAdvisor implements SportLoadAdvisor {
  const DeterministicSportLoadAdvisor();

  @override
  Future<Map<String, SportLoadAdvice>> suggestLoads(
    SportWorkoutPlan workout, {
    required List<SportHistorySet> history,
    required String? recoveryNote,
  }) async {
    final result = <String, SportLoadAdvice>{};
    for (final exercise in workout.exercises) {
      final previous = history
          .where(
            (item) =>
                item.exerciseId == exercise.id &&
                item.completed &&
                item.weightKg > 0,
          )
          .toList()
        ..sort((a, b) => b.sessionNumber.compareTo(a.sessionNumber));
      if (previous.isEmpty) {
        result[exercise.id] = const SportLoadAdvice(
          weightKg: null,
          reason: 'Нет личной истории: запиши стартовый вес самостоятельно.',
          isEstimate: false,
        );
        continue;
      }
      final last = previous.first;
      final conservativeStep = recoveryNote == null ? 1.025 : 1.0;
      final suggested = _roundToHalf(last.weightKg * conservativeStep);
      result[exercise.id] = SportLoadAdvice(
        weightKg: suggested,
        reason: recoveryNote == null
            ? 'Ориентир: последний подтверждённый вес + небольшой шаг 2.5%.'
            : 'Восстановление требует осторожности: оставь последний подтверждённый вес.',
        isEstimate: true,
      );
    }
    return result;
  }

  double _roundToHalf(double value) => (value * 2).round() / 2;
}

SportRoadmap buildSportRoadmap({String presetId = 'balanced-start'}) {
  final workouts = <SportWorkoutPlan>[];
  final days = <SportRoadmapDay>[];
  var sessionNumber = 0;
  final checkpoints = {1, 7, 14, 30, 45, 60, 75, 89, 90};
  for (var day = 1; day <= 90; day++) {
    final phase = day <= 14
        ? 1
        : day <= 35
            ? 2
            : day <= 63
                ? 3
                : day <= 80
                    ? 4
                    : 5;
    if (checkpoints.contains(day)) {
      days.add(
        SportRoadmapDay(
          dayNumber: day,
          phase: phase,
          activity: SportActivity.checkpoint,
          title: day == 90 ? '90-day review' : 'Recovery checkpoint',
          description:
              'Зафиксируй фактические данные, самочувствие и качество техники без гонки за цифрами.',
        ),
      );
      continue;
    }
    final cycle = (day - 1) % 4;
    final gym = cycle == 0 || cycle == 2;
    if (!gym) {
      days.add(
        SportRoadmapDay(
          dayNumber: day,
          phase: phase,
          activity:
              cycle == 1 ? SportActivity.mobility : SportActivity.recovery,
          title: cycle == 1 ? 'Mobility and walking' : 'Recovery check-in',
          description:
              'Лёгкая активность, сон и восстановление. Силовая очередь не двигается из-за пропуска.',
        ),
      );
      continue;
    }
    sessionNumber++;
    final template = SportWorkoutTemplate.values[(sessionNumber - 1) % 4];
    final workout = _workout(sessionNumber, day, phase, template, presetId);
    workouts.add(workout);
    days.add(
      SportRoadmapDay(
        dayNumber: day,
        phase: phase,
        activity: SportActivity.gym,
        title: 'Strength workout ${template.label}',
        description: phase == 1
            ? 'Освой движение, запиши все подходы и оставь 3–4 повтора в запасе.'
            : 'Сохраняй технику, фиксируй подходы и используй рекомендацию веса только как ориентир.',
        workout: workout,
      ),
    );
  }
  return SportRoadmap(days: days, workouts: workouts);
}

SportWorkoutPlan _workout(
  int sessionNumber,
  int day,
  int phase,
  SportWorkoutTemplate template,
  String presetId,
) {
  final exercises = sessionNumber <= 3
      ? _baselineExercises
      : switch (template) {
          SportWorkoutTemplate.a => const [
              SportExercisePlan(
                id: 'bench-press',
                name: 'Жим штанги лёжа',
                equipment: 'штанга + скамья',
                targetSets: 3,
                repRange: '8–12',
                technique:
                    'Лопатки собраны, стопы устойчивы, движение контролируемое.',
              ),
              SportExercisePlan(
                id: 'incline-dumbbell-press',
                name: 'Наклонный жим гантелей',
                equipment: 'гантели',
                targetSets: 3,
                repRange: '8–12',
                technique:
                    'Не бросай гантели вниз, держи плечи в комфортной позиции.',
              ),
              SportExercisePlan(
                id: 'leg-press',
                name: 'Жим ногами',
                equipment: 'тренажёр',
                targetSets: 3,
                repRange: '8–12',
                technique:
                    'Не отрывай таз от спинки и не блокируй колени резко.',
              ),
              SportExercisePlan(
                id: 'cable-pushdown',
                name: 'Разгибание рук на блоке',
                equipment: 'верхний блок',
                targetSets: 3,
                repRange: '10–15',
                technique: 'Локти стабильны, без рывка корпусом.',
              ),
            ],
          SportWorkoutTemplate.b => const [
              SportExercisePlan(
                id: 'lat-pulldown',
                name: 'Вертикальная тяга',
                equipment: 'верхний блок',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Веди локти вниз и контролируй возврат.',
              ),
              SportExercisePlan(
                id: 'seated-row',
                name: 'Горизонтальная тяга',
                equipment: 'нижний блок',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Начинай движением лопаток, не округляй поясницу.',
              ),
              SportExercisePlan(
                id: 'romanian-deadlift',
                name: 'Румынская тяга',
                equipment: 'штанга или гантели',
                targetSets: 3,
                repRange: '6–10',
                technique: 'Отводи таз назад, сохраняй нейтральную спину.',
              ),
              SportExercisePlan(
                id: 'ez-curl',
                name: 'Подъём EZ-грифа',
                equipment: 'EZ-гриф',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Локти близко к корпусу, без раскачки.',
              ),
            ],
          SportWorkoutTemplate.c => const [
              SportExercisePlan(
                id: 'overhead-press',
                name: 'Жим гантелей вверх',
                equipment: 'гантели',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Не прогибайся чрезмерно, контролируй рёбра.',
              ),
              SportExercisePlan(
                id: 'lateral-raise',
                name: 'Махи гантелей в стороны',
                equipment: 'гантели',
                targetSets: 3,
                repRange: '12–15',
                technique:
                    'Без раскачки, поднимай руки в комфортной амплитуде.',
              ),
              SportExercisePlan(
                id: 'dumbbell-curl',
                name: 'Подъём гантелей',
                equipment: 'гантели',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Контролируй опускание и не выводи плечо вперёд.',
              ),
              SportExercisePlan(
                id: 'plank',
                name: 'Планка',
                equipment: 'вес тела',
                targetSets: 3,
                repRange: '30–60 сек',
                technique: 'Рёбра и таз под контролем, не провисай в пояснице.',
              ),
            ],
          SportWorkoutTemplate.d => const [
              SportExercisePlan(
                id: 'squat',
                name: 'Присед',
                equipment: 'штанга или вес тела',
                targetSets: 3,
                repRange: '6–10',
                technique:
                    'Выбирай глубину, где сохраняются контроль и комфорт суставов.',
              ),
              SportExercisePlan(
                id: 'bulgarian-split-squat',
                name: 'Болгарские выпады',
                equipment: 'гантели или вес тела',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Начни с комфортной глубины и устойчивого баланса.',
              ),
              SportExercisePlan(
                id: 'chest-supported-row',
                name: 'Тяга с упором грудью',
                equipment: 'тренажёр или гантели',
                targetSets: 3,
                repRange: '8–12',
                technique: 'Опора грудью убирает лишнюю нагрузку с поясницы.',
              ),
              SportExercisePlan(
                id: 'calf-raise',
                name: 'Подъёмы на икры',
                equipment: 'тренажёр или вес тела',
                targetSets: 3,
                repRange: '10–20',
                technique: 'Контролируй амплитуду, не отскакивай.',
              ),
            ],
        };
  final adjusted = _adjustForPreset(exercises, presetId, template);
  return SportWorkoutPlan(
    id: 'sport-session-$sessionNumber',
    sessionNumber: sessionNumber,
    dayNumber: day,
    phase: phase,
    template: template,
    estimatedMinutes: _estimatedMinutes(sessionNumber, presetId),
    exercises: adjusted,
    presetId: presetId,
  );
}

int _estimatedMinutes(int sessionNumber, String presetId) => switch (presetId) {
      'return-to-training' => 50,
      'fat-loss-foundation' => 55,
      'hypertrophy-base' ||
      'upper-focus' ||
      'lower-focus' =>
        sessionNumber <= 3 ? 75 : 70,
      _ => sessionNumber <= 3 ? 70 : 65,
    };

List<SportExercisePlan> _adjustForPreset(
  List<SportExercisePlan> exercises,
  String presetId,
  SportWorkoutTemplate template,
) {
  final shouldAddFocusVolume = (presetId == 'upper-focus' &&
          (template == SportWorkoutTemplate.a ||
              template == SportWorkoutTemplate.c)) ||
      (presetId == 'lower-focus' &&
          (template == SportWorkoutTemplate.b ||
              template == SportWorkoutTemplate.d));
  return [
    for (final exercise in exercises)
      switch (presetId) {
        'return-to-training' => exercise.copyWith(
            targetSets: 2,
            repRange: exercise.id == 'plank' ? '20–40 сек' : '8–12',
          ),
        'fat-loss-foundation' => exercise.copyWith(
            repRange: exercise.id == 'plank' ? '30–45 сек' : '10–15',
          ),
        'hypertrophy-base' => exercise.copyWith(
            targetSets: 4,
            repRange: exercise.id == 'plank' ? '30–60 сек' : '8–15',
          ),
        'upper-focus' ||
        'lower-focus' when shouldAddFocusVolume =>
          exercise.copyWith(targetSets: exercise.targetSets + 1),
        _ => exercise,
      },
  ];
}

const _baselineExercises = [
  SportExercisePlan(
    id: 'squat',
    name: 'Присед',
    equipment: 'штанга или вес тела',
    targetSets: 3,
    repRange: '6–10',
    technique: 'Выбирай глубину, где сохраняются контроль и комфорт суставов.',
  ),
  SportExercisePlan(
    id: 'bench-press',
    name: 'Жим штанги лёжа',
    equipment: 'штанга + скамья',
    targetSets: 3,
    repRange: '8–12',
    technique: 'Лопатки собраны, стопы устойчивы, движение контролируемое.',
  ),
  SportExercisePlan(
    id: 'lat-pulldown',
    name: 'Вертикальная тяга',
    equipment: 'верхний блок',
    targetSets: 3,
    repRange: '8–12',
    technique: 'Веди локти вниз и контролируй возврат.',
  ),
  SportExercisePlan(
    id: 'chest-supported-row',
    name: 'Тяга с упором грудью',
    equipment: 'тренажёр или гантели',
    targetSets: 3,
    repRange: '8–12',
    technique: 'Опора грудью убирает лишнюю нагрузку с поясницы.',
  ),
  SportExercisePlan(
    id: 'bulgarian-split-squat',
    name: 'Болгарские выпады',
    equipment: 'гантели или вес тела',
    targetSets: 2,
    repRange: '8–12',
    technique: 'Начни с комфортной глубины и устойчивого баланса.',
  ),
  SportExercisePlan(
    id: 'calf-raise',
    name: 'Подъёмы на икры',
    equipment: 'тренажёр или вес тела',
    targetSets: 2,
    repRange: '10–20',
    technique: 'Контролируй амплитуду, не отскакивай.',
  ),
];
