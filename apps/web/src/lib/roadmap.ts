import { addDays, format } from "date-fns";
import type { RoadmapDay, Skill } from "./types";

const startDate = new Date(2026, 7, 3);

const weeks = [
  {
    range: [1, 7],
    theme: "Present Simple и структура предложения",
    topics: ["Present Simple", "to be", "do / does", "вопросы", "third person -s", "there is / there are", "some / any и articles"],
  },
  { range: [8, 14], theme: "Past Simple и Past Continuous", topics: ["regular and irregular verbs", "past questions", "past negatives", "Past Continuous", "Past Simple vs Past Continuous", "bug vocabulary", "weekly test"] },
  { range: [15, 21], theme: "Present Perfect", topics: ["Present Perfect", "for and since", "already / yet / just", "Present Perfect vs Past Simple", "Present Perfect Continuous", "job experience", "weekly test"] },
  { range: [22, 30], theme: "Будущее, модальные глаголы и revision", topics: ["will", "going to", "future arrangements", "modal verbs", "polite requests", "revision", "writing", "first major test", "reflection"] },
  { range: [31, 37], theme: "Conditionals", topics: ["zero conditional", "first conditional", "second conditional", "third conditional", "mixed practice", "speaking", "test"] },
  { range: [38, 44], theme: "Passive Voice и процессы", topics: ["present passive", "past passive", "future passive", "active vs passive", "product development vocabulary", "software development lifecycle", "writing test"] },
  { range: [45, 51], theme: "Reported Speech и клиентская коммуникация", topics: ["reported speech", "reported questions", "say / tell / ask / explain", "scope vocabulary", "client objections", "roleplay", "writing"] },
  { range: [52, 60], theme: "Gerund, infinitive и связность речи", topics: ["verb + to", "verb + ing", "meaning differences", "linking words", "removing filler words", "presentation", "second major test", "reflection", "fluency clinic"] },
  { range: [61, 67], theme: "CV, LinkedIn и самопрезентация", topics: ["professional summary", "responsibilities", "achievements", "business impact", "tell me about yourself", "why should we hire you", "strengths and weaknesses"] },
  { range: [68, 74], theme: "Technical interview", topics: ["tech stack", "architecture", "technical challenge", "bug explanation", "testing", "AI usage", "technical monologue"] },
  { range: [75, 81], theme: "Продажи и переговоры", topics: ["discovery call", "requirements", "scope", "pricing", "timelines", "objections", "full client call"] },
  { range: [82, 88], theme: "Business writing", topics: ["cold message", "proposal", "delay message", "scope change", "invoice reminder", "proofreading", "comparison with old texts"] },
  { range: [89, 90], theme: "Финальное тестирование", topics: ["full rehearsal", "grammar", "reading / listening", "writing", "speaking", "technical interview"] },
] as const;

const skillByDay = (day: number): Skill[] => {
  if (day % 7 === 0 || day === 14 || day === 30 || day === 60 || day >= 89) return ["grammar", "listening", "speaking", "writing", "business"];
  if (day % 5 === 0) return ["vocabulary", "speaking", "business"];
  return ["grammar", "vocabulary", "listening", "speaking", "writing"];
};

const topicFor = (day: number): string => {
  const week = weeks.find((item) => day >= item.range[0] && day <= item.range[1]) ?? weeks[0];
  return week.topics[(day - week.range[0]) % week.topics.length];
};

const themeFor = (day: number): string => weeks.find((item) => day >= item.range[0] && day <= item.range[1])?.theme ?? weeks[0].theme;

export function buildRoadmap(): RoadmapDay[] {
  return Array.from({ length: 90 }, (_, index) => {
    const dayNumber = index + 1;
    const topic = topicFor(dayNumber);
    const skills = skillByDay(dayNumber);
    const skillNames = skills.join(", ");
    const taskLabels = [
      `Разобрать теорию: ${topic}`,
      `Выполнить практику по теме «${topic}»`,
      `Послушать материал и выписать 3 полезные фразы`,
      `Сделать короткое speaking-задание на тему дня`,
      `Написать 5–10 предложений и проверить ошибки`,
    ];
    return {
      id: `day-${dayNumber}`,
      dayNumber,
      date: format(addDays(startDate, index), "yyyy-MM-dd"),
      title: topic,
      description: `${themeFor(dayNumber)} · фокус: ${skillNames}`,
      goal: `Уверенно применять ${topic.toLowerCase()} в рабочей и повседневной речи.`,
      grammarTopic: topic,
      vocabularyTopic: dayNumber % 2 === 0 ? "Work, bugs and delivery" : "Daily routines and collaboration",
      listeningTopic: dayNumber % 3 === 0 ? "BBC Learning English / 6 Minute English" : "Short A2–B1 dialogue",
      speakingTopic: dayNumber % 2 === 0 ? "Explain a work situation clearly" : "Tell a short story without reading",
      writingTopic: dayNumber % 2 === 0 ? "A concise professional update" : "A short personal or work reflection",
      businessTopic: dayNumber >= 61 ? "Career and client communication" : "Clear workplace English",
      estimatedMinutes: dayNumber % 7 === 0 ? 45 : 35 + (dayNumber % 3) * 5,
      searchQueries: [
        `British Council ${topic} A2 B1`,
        dayNumber % 2 === 0 ? "BBC Learning English 6 Minute English" : "VOA Learning English intermediate",
        dayNumber >= 61 ? "software developer interview English" : "English business conversation B1",
      ],
      resources: ["British Council LearnEnglish", "Cambridge English", "BBC Learning English", "VOA Learning English", "YouGlish", "YouTube", "ChatGPT"],
      tags: [...skills, dayNumber % 7 === 0 ? "test" : dayNumber % 6 === 0 ? "revision" : "interview English"],
      tasks: taskLabels.map((label, taskIndex) => ({
        id: `day-${dayNumber}-task-${taskIndex + 1}`,
        label,
        skill: skills[taskIndex % skills.length],
        required: taskIndex < 4,
        completed: false,
      })),
      notes: "",
      writtenAnswer: "",
      voiceLink: "",
      status: dayNumber === 1 ? "available" : "locked",
    } satisfies RoadmapDay;
  });
}

export const START_DATE = startDate;

