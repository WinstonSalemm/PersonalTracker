enum EnglishStage { a2ToB1, b1ToB2 }

extension EnglishStageLabel on EnglishStage {
  String get id => switch (this) {
    EnglishStage.a2ToB1 => 'a2_to_b1',
    EnglishStage.b1ToB2 => 'b1_to_b2',
  };

  String get title => switch (this) {
    EnglishStage.a2ToB1 => 'A2.5 → B1',
    EnglishStage.b1ToB2 => 'B1 → B2',
  };

  String get description => switch (this) {
    EnglishStage.a2ToB1 =>
      '90 дней для уверенной повседневной и рабочей коммуникации уровня B1.',
    EnglishStage.b1ToB2 =>
      'Следующий цикл для точности, аргументации и профессиональной речи B2.',
  };
}

enum EnglishLessonKind { integrated, checkpoint }

extension EnglishLessonKindLabel on EnglishLessonKind {
  String get label => switch (this) {
    EnglishLessonKind.integrated => 'Integrated lesson',
    EnglishLessonKind.checkpoint => 'Weekly checkpoint',
  };
}

enum EnglishSkill { reading, writing, listening, speaking }

extension EnglishSkillLabel on EnglishSkill {
  String get label => switch (this) {
    EnglishSkill.reading => 'Reading',
    EnglishSkill.writing => 'Writing',
    EnglishSkill.listening => 'Listening',
    EnglishSkill.speaking => 'Speaking',
  };
}

class EnglishLessonBlock {
  const EnglishLessonBlock({
    required this.skill,
    required this.title,
    required this.instruction,
    required this.content,
    required this.minutes,
    this.url,
  });

  final EnglishSkill skill;
  final String title;
  final String instruction;
  final String content;
  final int minutes;
  final String? url;
}

class EnglishLesson {
  const EnglishLesson({
    required this.id,
    required this.stage,
    required this.week,
    required this.day,
    required this.title,
    required this.focus,
    required this.objective,
    required this.blocks,
    required this.estimatedMinutes,
    required this.checkpoint,
  });

  final String id;
  final EnglishStage stage;
  final int week;
  final int day;
  final String title;
  final String focus;
  final String objective;
  final List<EnglishLessonBlock> blocks;
  final int estimatedMinutes;
  final bool checkpoint;

  EnglishLessonKind get kind =>
      checkpoint ? EnglishLessonKind.checkpoint : EnglishLessonKind.integrated;
}

class EnglishRoadmap {
  const EnglishRoadmap(this.lessons);

  final List<EnglishLesson> lessons;

  List<EnglishLesson> forStage(EnglishStage stage) =>
      lessons.where((lesson) => lesson.stage == stage).toList();

  EnglishLesson? byId(String id) {
    for (final lesson in lessons) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }
}

/// Stable local plan. A future AI implementation can return a revised copy
/// through [EnglishPlanAdvisor] without changing the UI or SQLite contract.
abstract interface class EnglishPlanAdvisor {
  Future<EnglishRoadmap> revise(
    EnglishRoadmap base, {
    required String learnerLevel,
    required Set<String> completedLessonIds,
    String? learnerNote,
  });
}

class DeterministicEnglishPlanAdvisor implements EnglishPlanAdvisor {
  const DeterministicEnglishPlanAdvisor();

  @override
  Future<EnglishRoadmap> revise(
    EnglishRoadmap base, {
    required String learnerLevel,
    required Set<String> completedLessonIds,
    String? learnerNote,
  }) async => base;
}

class _WeekSpec {
  const _WeekSpec({
    required this.title,
    required this.focus,
    required this.objective,
    required this.readingText,
    required this.writingPrompt,
    required this.speakingPrompt,
    required this.listeningSearch,
  });

  final String title;
  final String focus;
  final String objective;
  final String readingText;
  final String writingPrompt;
  final String speakingPrompt;
  final String listeningSearch;
}

const _a2ToB1 = [
  _WeekSpec(
    title: 'Build clear sentences',
    focus: 'word order, be/do/have, questions and negatives',
    objective:
        'Строить короткие фразы без постоянной паузы на базовую грамматику.',
    readingText:
        'Maya works from a small office near her home. She starts at nine, checks her tasks, and calls her team before lunch. In the evening, she studies English for thirty minutes.',
    writingPrompt:
        'Напиши короткий профиль: где ты живёшь, работаешь и как проходит твой обычный день.',
    speakingPrompt:
        'Представься и расскажи о своём обычном буднем дне в 90–120 секунд.',
    listeningSearch: 'BBC Learning English A2 daily routine introductions',
  ),
  _WeekSpec(
    title: 'Time and stories',
    focus: 'Present Simple, Present Continuous and Past Simple',
    objective: 'Рассказывать, что происходит сейчас и что произошло вчера.',
    readingText:
        'Last Saturday, Omar missed his bus, but he did not panic. He walked to a café, sent a message to his friend, and arrived ten minutes late. Today he is planning his journey more carefully.',
    writingPrompt:
        'Опиши вчерашний день и сравни его с тем, что происходит сегодня.',
    speakingPrompt:
        'Расскажи историю о небольшой проблеме и о том, как ты её решил.',
    listeningSearch: 'VOA Learning English past simple everyday story',
  ),
  _WeekSpec(
    title: 'Future and plans',
    focus: 'will, going to and Present Continuous for arrangements',
    objective: 'Объяснять планы, договорённости и следующие шаги.',
    readingText:
        'The team is meeting on Thursday to plan a new release. They are going to test the main feature first. If the test is successful, the manager will send an update to the client.',
    writingPrompt:
        'Составь план на ближайшие семь дней: договорённости, намерения и прогнозы.',
    speakingPrompt:
        'Расскажи о планах на неделю и объясни, что может измениться.',
    listeningSearch: 'BBC Learning English future plans going to will',
  ),
  _WeekSpec(
    title: 'Nouns and quantity',
    focus: 'articles, countable nouns, some/any and much/many',
    objective: 'Точно описывать предметы, количество и рабочие ресурсы.',
    readingText:
        'Our project needs a clear checklist, two testers, and some extra time. We do not need much equipment, but we need enough information from the customer before work begins.',
    writingPrompt:
        'Опиши ресурсы для своей задачи: что уже есть, чего не хватает и сколько нужно.',
    speakingPrompt:
        'Объясни коллеге, какие материалы или данные нужны для работы.',
    listeningSearch:
        'BBC Learning English countable uncountable nouns much many',
  ),
  _WeekSpec(
    title: 'Comparison and detail',
    focus: 'comparatives, superlatives, adverbs and modifiers',
    objective: 'Сравнивать варианты и добавлять полезные детали к описанию.',
    readingText:
        'The first solution is cheaper, but the second one is faster and easier to maintain. The newest version is slightly more expensive, although it is much safer for daily use.',
    writingPrompt:
        'Сравни два инструмента, сервиса или способа работы и дай рекомендацию.',
    speakingPrompt:
        'Сравни два варианта решения и защити свой выбор простыми аргументами.',
    listeningSearch: 'VOA Learning English comparatives superlatives',
  ),
  _WeekSpec(
    title: 'Experience and results',
    focus: 'Present Perfect, for/since, already/yet and just',
    objective: 'Говорить об опыте, результате и незавершённых задачах.',
    readingText:
        'I have worked on this project for six months. We have already solved the biggest problem, but we have not finished the documentation yet. The team has just started a final review.',
    writingPrompt:
        'Напиши о трёх сделанных задачах, одной незавершённой и опыте за последний год.',
    speakingPrompt:
        'Расскажи о своём опыте и о результате, которым ты гордишься.',
    listeningSearch: 'BBC Learning English present perfect experience results',
  ),
  _WeekSpec(
    title: 'Requests and advice',
    focus: 'can, could, should, have to and polite requests',
    objective: 'Просить, советовать, объяснять обязательства и ограничения.',
    readingText:
        'Before the meeting, you should check the latest numbers. You have to bring one clear example, but you can ask for more time if a question is not clear.',
    writingPrompt:
        'Напиши вежливое сообщение с просьбой и дай коллеге три практических совета.',
    speakingPrompt:
        'Разыграй ситуацию: попроси помощи, уточни ограничение и предложи совет.',
    listeningSearch: 'BBC Learning English polite requests advice could should',
  ),
  _WeekSpec(
    title: 'Conditions and reasons',
    focus: 'zero/first conditional, because, although and so',
    objective: 'Объяснять причины, последствия и рабочие сценарии.',
    readingText:
        'If the traffic is heavy, I take the metro. If we finish the first test today, we will release a small update tomorrow. Although the task looks simple, it needs careful checking.',
    writingPrompt:
        'Опиши рабочий сценарий с условиями, причинами и возможными последствиями.',
    speakingPrompt:
        'Объясни, что ты будешь делать, если возникнут три типичные проблемы.',
    listeningSearch: 'VOA Learning English first conditional if situations',
  ),
  _WeekSpec(
    title: 'Workplace English',
    focus: 'meetings, updates, blockers, follow-up and deadlines',
    objective:
        'Давать понятный статус и задавать уточняющие вопросы на работе.',
    readingText:
        'In the daily meeting, Leo gives a short update. He says what he finished, what he is doing now, and where he is blocked. The team agrees on one next step and a deadline.',
    writingPrompt:
        'Напиши рабочий статус из трёх частей: done, doing, blocked/next step.',
    speakingPrompt:
        'Сделай двухминутный статус по задаче и задай один уточняющий вопрос.',
    listeningSearch: 'BBC Learning English English at work meeting update',
  ),
  _WeekSpec(
    title: 'Opinions and discussion',
    focus: 'agreeing, disagreeing, examples and softening language',
    objective: 'Выражать мнение и поддерживать разговор без чтения по шаблону.',
    readingText:
        'Some people prefer working alone because it is quiet. Others think that regular teamwork leads to better ideas. A balanced approach can be useful when the task is complex.',
    writingPrompt:
        'Напиши мнение на 120 слов, используй один пример и вежливо упомяни другую позицию.',
    speakingPrompt:
        'Выскажи позицию по спорному рабочему вопросу, приведи пример и задай вопрос собеседнику.',
    listeningSearch:
        'BBC Learning English expressing opinions agreeing disagreeing',
  ),
  _WeekSpec(
    title: 'Career and technical basics',
    focus: 'CV, projects, stack, bugs and simple explanations',
    objective: 'Коротко рассказывать о себе, проекте и технической проблеме.',
    readingText:
        'A good project description explains the problem, the action, and the result. It does not need every technical detail. A clear example helps another person understand your contribution.',
    writingPrompt:
        'Напиши описание одного проекта: проблема, твоя роль, действия и результат.',
    speakingPrompt:
        'Расскажи о проекте или задаче так, будто отвечаешь на простой вопрос на интервью.',
    listeningSearch:
        'BBC Learning English job interview talking about experience',
  ),
  _WeekSpec(
    title: 'B1 integration',
    focus: 'revision, mixed skills, speaking and writing checkpoint',
    objective: 'Собрать всё в связную B1-коммуникацию и увидеть пробелы.',
    readingText:
        'A reliable professional does not need perfect English in every sentence. They need to explain the important point, check understanding, and continue the conversation when something goes wrong.',
    writingPrompt:
        'Напиши связный текст о своей цели на следующие 90 дней и способе её достичь.',
    speakingPrompt:
        'Сделай пятиминутную презентацию о себе, работе и ближайшей цели.',
    listeningSearch: 'British Council LearnEnglish B1 listening review',
  ),
  _WeekSpec(
    title: 'B1 confidence lab',
    focus: 'fluency, repair strategies and active recall',
    objective:
        'Снизить паузы и научиться продолжать речь, когда не хватает слова.',
    readingText:
        'When a speaker forgets a word, they can describe it, give an example, or ask for help. Communication continues because the speaker focuses on meaning instead of stopping completely.',
    writingPrompt:
        'Перепиши короткий текст дважды: сначала просто, затем более естественно с linking words.',
    speakingPrompt:
        'Говори три минуты на знакомую тему и используй описания вместо перевода каждого слова.',
    listeningSearch:
        'BBC Learning English speaking fluency communication strategies',
  ),
];

const _b1ToB2 = [
  _WeekSpec(
    title: 'Tense nuance',
    focus: 'narrative tenses, sequence and emphasis',
    objective: 'Выбирать время по смыслу, а не только по маркерам даты.',
    readingText:
        'By the time the client called, the team had already found the cause. They were discussing the next step when the system became available again.',
    writingPrompt:
        'Напиши историю инцидента с чёткой последовательностью событий.',
    speakingPrompt:
        'Объясни, что произошло в проекте, используя минимум три времени.',
    listeningSearch: 'BBC Learning English narrative tenses advanced',
  ),
  _WeekSpec(
    title: 'Modality and uncertainty',
    focus: 'probability, assumptions, obligation and hedging',
    objective: 'Различать факт, вероятность, рекомендацию и предположение.',
    readingText:
        'The delay may be related to the new integration, but we cannot be certain yet. The team should collect more evidence before making a final decision.',
    writingPrompt:
        'Составь осторожный статус с фактами, гипотезами и рекомендацией.',
    speakingPrompt:
        'Обсуди риск и объясни, что известно точно, а что пока только вероятно.',
    listeningSearch: 'BBC Learning English modal verbs probability certainty',
  ),
  _WeekSpec(
    title: 'Conditionals and alternatives',
    focus: 'second, third and mixed conditionals',
    objective: 'Обсуждать альтернативы, риски и последствия решений.',
    readingText:
        'If we had tested the edge case earlier, we would have avoided the incident. If the requirements were clearer now, the next release would be easier to estimate.',
    writingPrompt:
        'Разбери решение: что произошло, что можно было сделать иначе и что изменится теперь.',
    speakingPrompt:
        'Объясни три альтернативных сценария и выбери самый реалистичный.',
    listeningSearch: 'BBC Learning English third conditional mixed conditional',
  ),
  _WeekSpec(
    title: 'Passive and causative structures',
    focus: 'passive voice, have/get something done and process language',
    objective:
        'Описывать процессы и ответственность в профессиональном контексте.',
    readingText:
        'The report was reviewed by two engineers before it was sent. We had the final numbers checked again because a small inconsistency had been found.',
    writingPrompt:
        'Опиши процесс выпуска продукта, используя passive и causative structures.',
    speakingPrompt:
        'Объясни процесс или сервис так, чтобы ответственность и шаги были ясны.',
    listeningSearch:
        'BBC Learning English passive voice causative have something done',
  ),
  _WeekSpec(
    title: 'Reported communication',
    focus: 'reported speech, questions, say/tell/ask and summaries',
    objective:
        'Пересказывать разговоры, требования и решения без потери смысла.',
    readingText:
        'The manager said that the deadline could move if the team found a serious risk. She asked everyone to report problems early rather than hide them.',
    writingPrompt:
        'Перескажи короткую встречу: решения, вопросы и следующие действия.',
    speakingPrompt:
        'Передай содержание воображаемого разговора с клиентом своему коллеге.',
    listeningSearch: 'BBC Learning English reported speech say tell ask',
  ),
  _WeekSpec(
    title: 'Complex sentences',
    focus: 'relative clauses, participles and sentence reduction',
    objective: 'Соединять идеи в более плотную, естественную речь.',
    readingText:
        'The tool, which was introduced last month, has reduced the time needed for routine checks. Users working on older devices can still use a lighter version.',
    writingPrompt:
        'Соедини десять простых предложений в связный абзац с relative clauses.',
    speakingPrompt:
        'Объясни продукт или проект, добавляя уточнения без длинных пауз.',
    listeningSearch: 'BBC Learning English relative clauses participle clauses',
  ),
  _WeekSpec(
    title: 'Discourse and cohesion',
    focus: 'linking, contrast, concession and paragraph logic',
    objective: 'Строить связное объяснение, письмо или презентацию.',
    readingText:
        'The proposal is more expensive at first; nevertheless, it may reduce maintenance costs. In addition, it gives the team a clearer process for future changes.',
    writingPrompt:
        'Напиши четыре связанных абзаца: position, reason, contrast, conclusion.',
    speakingPrompt:
        'Проведи мини-презентацию с чётким вступлением, переходами и выводом.',
    listeningSearch: 'British Council LearnEnglish discourse markers cohesion',
  ),
  _WeekSpec(
    title: 'Collocations and precision',
    focus: 'collocations, phrasal verbs, register and false friends',
    objective: 'Заменять общие слова на точные рабочие выражения.',
    readingText:
        'The team reached an agreement after a detailed discussion. They raised a concern about the timeline and came up with a practical compromise.',
    writingPrompt:
        'Отредактируй простой текст, заменив общие слова на 10 точных collocations.',
    speakingPrompt:
        'Объясни одну задачу двумя способами: casual и professional.',
    listeningSearch: 'BBC Learning English collocations work business English',
  ),
  _WeekSpec(
    title: 'Negotiation and persuasion',
    focus: 'trade-offs, objections, proposals and diplomatic language',
    objective: 'Объяснять компромиссы и защищать решение без резкости.',
    readingText:
        'The proposal does not solve every problem, but it offers a reasonable balance between speed and reliability. The team is willing to review the decision after the first month.',
    writingPrompt:
        'Напиши предложение с выгодами, ограничениями, компромиссом и следующим шагом.',
    speakingPrompt:
        'Защити решение перед человеком, который не согласен, и ответь на два возражения.',
    listeningSearch: 'BBC Learning English negotiation diplomacy objections',
  ),
  _WeekSpec(
    title: 'Technical explanation',
    focus: 'architecture, incidents, trade-offs and root causes',
    objective:
        'Объяснять сложную техническую тему человеку с другим уровнем знаний.',
    readingText:
        'The service failed because a dependency returned unexpected data. Instead of adding a quick patch only, the team is improving validation and monitoring to reduce the chance of repetition.',
    writingPrompt:
        'Напиши post-incident summary: impact, cause, fix, prevention.',
    speakingPrompt:
        'Объясни техническую проблему нетехническому слушателю через аналогию и конкретный результат.',
    listeningSearch: 'English technical communication explain complex ideas',
  ),
  _WeekSpec(
    title: 'Argument and professional writing',
    focus: 'position, evidence, tone, summaries and editing',
    objective:
        'Писать убедительный, структурный и естественный профессиональный текст.',
    readingText:
        'A strong argument connects a clear position with relevant evidence. It also recognises a limitation, because honest qualification often makes a recommendation more credible.',
    writingPrompt:
        'Напиши аргументированный memo на 220–260 слов и отредактируй тон.',
    speakingPrompt:
        'Сформулируй позицию, два доказательства, ограничение и вывод за пять минут.',
    listeningSearch:
        'BBC Learning English advanced professional writing argument',
  ),
  _WeekSpec(
    title: 'B2 capstone',
    focus: 'full review, interview, presentation and adaptive weak spots',
    objective:
        'Показать B2-коммуникацию и сформировать следующий индивидуальный цикл.',
    readingText:
        'Strong communication is not only a collection of advanced grammar points. It is the ability to choose an appropriate register, organise ideas, respond to another person, and repair a misunderstanding.',
    writingPrompt:
        'Составь финальный профессиональный текст и список трёх целей после B2.',
    speakingPrompt:
        'Запиши интервью или презентацию на 8–10 минут без чтения полного сценария.',
    listeningSearch: 'British Council LearnEnglish B2 listening review',
  ),
];

EnglishRoadmap buildEnglishRoadmap() {
  final lessons = <EnglishLesson>[];
  _addStageLessons(lessons, EnglishStage.a2ToB1, _a2ToB1, dayCount: 90);
  _addStageLessons(lessons, EnglishStage.b1ToB2, _b1ToB2, dayCount: 84);
  return EnglishRoadmap(lessons);
}

void _addStageLessons(
  List<EnglishLesson> lessons,
  EnglishStage stage,
  List<_WeekSpec> specs, {
  required int dayCount,
}) {
  for (var index = 0; index < dayCount; index++) {
    final weekIndex = index ~/ 7;
    final dayInWeek = index % 7;
    final spec = specs[weekIndex];
    final checkpoint = dayInWeek == 6 || index == dayCount - 1;
    final estimatedMinutes = dayInWeek == 0 || checkpoint ? 70 : 60;
    lessons.add(
      EnglishLesson(
        id: '${stage.id}-w${weekIndex + 1}-d${dayInWeek + 1}',
        stage: stage,
        week: weekIndex + 1,
        day: index + 1,
        title: checkpoint ? '${spec.title} checkpoint' : spec.title,
        focus: spec.focus,
        objective: spec.objective,
        blocks: _blocksFor(spec, index + 1, checkpoint, estimatedMinutes),
        estimatedMinutes: estimatedMinutes,
        checkpoint: checkpoint,
      ),
    );
  }
}

List<EnglishLessonBlock> _blocksFor(
  _WeekSpec spec,
  int day,
  bool checkpoint,
  int estimatedMinutes,
) {
  final extra = checkpoint
      ? ' Это checkpoint: сохрани результат, а не только отметку о просмотре.'
      : '';
  final readingMinutes = estimatedMinutes == 70 ? 20 : 15;
  final writingMinutes = estimatedMinutes == 70 ? 20 : 15;
  return [
    EnglishLessonBlock(
      skill: EnglishSkill.reading,
      title: 'Read and notice',
      instruction:
          'Прочитай текст дважды. Во второй раз отметь 5 полезных фраз и ответь на 3 вопроса по смыслу.$extra',
      content: spec.readingText,
      minutes: readingMinutes,
    ),
    EnglishLessonBlock(
      skill: EnglishSkill.listening,
      title: 'Listen and catch the meaning',
      instruction:
          'Открой материал, послушай его два раза, затем перескажи основную мысль без субтитров.$extra',
      content: 'YouTube search: ${spec.listeningSearch}',
      url:
          'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(spec.listeningSearch)}',
      minutes: 15,
    ),
    EnglishLessonBlock(
      skill: EnglishSkill.speaking,
      title: 'Speak and record',
      instruction:
          'Запиши ответ на английском. Не читай полный текст: используй только 3–5 ключевых слов.$extra',
      content: spec.speakingPrompt,
      minutes: 15,
    ),
    EnglishLessonBlock(
      skill: EnglishSkill.writing,
      title: 'Write and improve',
      instruction:
          'Напиши ответ, затем проверь порядок слов, времена и связки. Исправь минимум 2 предложения.$extra',
      content: spec.writingPrompt,
      minutes: writingMinutes,
    ),
  ];
}
