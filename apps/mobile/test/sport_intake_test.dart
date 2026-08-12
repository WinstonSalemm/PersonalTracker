import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker_sport_roadmap/sport_roadmap.dart';

import 'package:personal_tracker_assistant/sport_intake.dart';

void main() {
  test('limitations select the conservative return preset', () {
    final preset = recommendSportPreset(
      goal: SportGoal.muscleGain,
      experience: SportExperience.regular,
      hasLimitations: true,
      focusAreas: const [],
    );

    expect(preset.id, 'return-to-training');
  });

  test('targeted lower-body goal selects the lower focus preset', () {
    final preset = recommendSportPreset(
      goal: SportGoal.targeted,
      experience: SportExperience.regular,
      hasLimitations: false,
      focusAreas: const ['ноги'],
    );

    expect(preset.id, 'lower-focus');
  });

  test(
      'preset adjusts actual workout volume without changing the A/B/C/D queue',
      () {
    final restart = buildSportRoadmap(presetId: 'return-to-training');
    final hypertrophy = buildSportRoadmap(presetId: 'hypertrophy-base');

    expect(restart.workouts.first.template, SportWorkoutTemplate.a);
    expect(hypertrophy.workouts.first.template, SportWorkoutTemplate.a);
    expect(restart.workouts.first.exercises.first.targetSets, 2);
    expect(hypertrophy.workouts.first.exercises.first.targetSets, 4);
    expect(restart.workouts.first.estimatedMinutes, 50);
  });
}
