import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker_english_roadmap/english_onboarding.dart';
import 'package:personal_tracker_english_roadmap/english_roadmap.dart';

void main() {
  test('builds the 90-day A2.5 to B2 roadmap', () {
    final roadmap = buildEnglishRoadmap();

    expect(roadmap.lessons, hasLength(174));
    expect(roadmap.forStage(EnglishStage.a2ToB1), hasLength(90));
    expect(roadmap.forStage(EnglishStage.b1ToB2), hasLength(84));
    expect(
      roadmap.lessons.where((lesson) => lesson.checkpoint),
      hasLength(25),
    );
    expect(roadmap.lessons.first.stage, EnglishStage.a2ToB1);
    expect(roadmap.lessons.last.stage, EnglishStage.b1ToB2);
    for (final lesson in roadmap.lessons) {
      expect(lesson.blocks, hasLength(4));
      expect(
        lesson.blocks.map((block) => block.skill),
        containsAll(const [
          EnglishSkill.reading,
          EnglishSkill.writing,
          EnglishSkill.listening,
          EnglishSkill.speaking,
        ]),
      );
      expect(
          lesson.blocks
              .singleWhere(
                (block) => block.skill == EnglishSkill.listening,
              )
              .url,
          startsWith('https://www.youtube.com/'));
      expect(lesson.estimatedMinutes, anyOf(60, 70));
    }
  });

  test('future advisor seam preserves deterministic baseline', () async {
    final roadmap = buildEnglishRoadmap();
    const advisor = DeterministicEnglishPlanAdvisor();

    final revised = await advisor.revise(
      roadmap,
      learnerLevel: 'A2.5',
      completedLessonIds: const {},
    );

    expect(revised.lessons.length, roadmap.lessons.length);
    expect(revised.lessons.first.title, roadmap.lessons.first.title);
  });

  test('English intake produces an honest local placement and safe search URL',
      () {
    expect(placementForScore(0), EnglishPlacementBand.a1ToA2);
    expect(placementForScore(2), EnglishPlacementBand.a2ToB1);
    expect(placementForScore(4), EnglishPlacementBand.b1ToB2);

    final profile = EnglishLearningProfile(
      goal: EnglishGoal.work,
      courseLength: EnglishCourseLength.twelveWeeks,
      intensity: EnglishIntensity.steady,
      placement: EnglishPlacementBand.a2ToB1,
      grammarReadingScore: 2,
      listeningSelfReport: 'понимаю общий смысл',
      speakingSelfReport: 'могу коротко, но с паузами',
      preferredFormats: const ['видео'],
      createdAt: DateTime.utc(2026, 8, 6),
      goalNarrative: 'Поступить за границу через 8 месяцев',
      intakeFacts: const {'deadline': '8 месяцев', 'exam': 'IELTS'},
      missingFacts: const ['weekly_time'],
      aiSummary: 'Правильно: у вас 8 месяцев.',
    );

    final restored = EnglishLearningProfile.fromJson(profile.toJson());
    expect(restored.goal, EnglishGoal.work);
    expect(restored.youtubeSearchUrl, contains('youtube.com/results'));
    expect(restored.youtubeSearchUrl, contains('English'));
    expect(restored.outcomeBoundary, contains('не обещание'));
    expect(restored.confidenceNote, contains('самооценке'));
    expect(restored.goalText, contains('8 месяцев'));
    expect(restored.intakeFacts['exam'], 'IELTS');
  });
}
