import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker_sport_roadmap/sport_roadmap.dart';

void main() {
  test('builds a 90-day roadmap with a manual first-three rule', () {
    final roadmap = buildSportRoadmap();

    expect(roadmap.days, hasLength(90));
    expect(roadmap.workouts.length, greaterThan(3));
    expect(
      roadmap.workouts
          .take(3)
          .every((workout) => workout.requiresManualBaseline),
      isTrue,
    );
    expect(
        roadmap.workouts
            .skip(3)
            .every((workout) => !workout.requiresManualBaseline),
        isTrue);
    final baselineIds = roadmap.workouts
        .take(3)
        .expand((workout) => workout.exercises.map((exercise) => exercise.id))
        .toSet();
    expect(
      roadmap.workouts[3].exercises
          .every((exercise) => baselineIds.contains(exercise.id)),
      isTrue,
    );
    expect(roadmap.workouts.map((workout) => workout.template).toSet(),
        hasLength(4));
    for (final workout in roadmap.workouts) {
      expect(workout.exercises, isNotEmpty);
      expect(workout.estimatedMinutes, anyOf(65, 70));
    }
  });

  test('load advisor never invents a first weight and estimates from history',
      () async {
    const advisor = DeterministicSportLoadAdvisor();
    final workout = buildSportRoadmap().workouts[3];

    final withoutHistory = await advisor.suggestLoads(
      workout,
      history: const [],
      recoveryNote: null,
    );
    expect(withoutHistory[workout.exercises.first.id]?.weightKg, isNull);

    final withHistory = await advisor.suggestLoads(
      workout,
      history: [
        SportHistorySet(
          sessionNumber: 1,
          exerciseId: workout.exercises.first.id,
          weightKg: 40,
          repetitions: 10,
          completed: true,
        ),
      ],
      recoveryNote: null,
    );
    expect(withHistory[workout.exercises.first.id]?.weightKg, 41);
    expect(withHistory[workout.exercises.first.id]?.isEstimate, isTrue);
  });
}
