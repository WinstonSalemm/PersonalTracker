import { describe, expect, it } from "vitest";

type ExerciseSet = { id: string; setNumber: number; weight: number; repetitions: number; rir?: number; completed: boolean; warmup: boolean };
type WorkoutExercise = { id: string; exerciseId?: string; nameSnapshot: string; primaryMuscleSnapshot: string; targetSets: number; targetRepRange: string; completed: boolean; notes: string; sets: ExerciseSet[] };
type WorkoutSession = { id: string; date: string; workoutType: string; workoutTemplate?: "A" | "B" | "C" | "D"; startedAt: string; planned: boolean; completed: boolean; notes: string; exercises: WorkoutExercise[]; createdAt: string; updatedAt: string };
type SportRoadmapDay = { id: string; dayNumber: number; date: string; phase: number; title: string; description: string; goal: string; plannedActivity: string; estimatedMinutes: number; tasks: unknown[]; adaptationNotes: string; status: string };

const sport = await import("../src/sport-calculations.js") as {
  doubleProgression: (exercise: WorkoutExercise) => string | null;
  estimatedOneRepMax: (weight: number, repetitions: number) => number | null;
  loadAdaptation: (date: string, basketball: Array<{ id: string; date: string; durationMinutes: number; format: string; intensity: number; gamesPlayed: number; kneeDiscomfort: number; ankleDiscomfort: number; notes: string; createdAt: string; updatedAt: string }>, recovery: { id: string; date: string; sleepHours: number; sleepQuality: number; energy: number; muscleSoreness: number; jointPain: number; stress: number; motivation: number; comment: string; createdAt: string } | undefined, template: "A" | "B" | "C" | "D") => { suggestedTemplate?: string; notes: string[] };
  nextTemplate: (sessions: WorkoutSession[]) => "A" | "B" | "C" | "D";
  personalRecordsFor: (sessions: WorkoutSession[]) => Array<{ type: string; value: number }>;
  recoveryStatus: (recovery: { id: string; date: string; sleepHours: number; sleepQuality: number; energy: number; muscleSoreness: number; jointPain: number; stress: number; motivation: number; comment: string; createdAt: string }) => { tone: string };
  roadmapCompletion: (roadmap: SportRoadmapDay[]) => number;
  weeklyAverageWeight: (measurements: Array<{ id: string; date: string; weightKg?: number; comment: string; createdAt: string }>, weekStart: string) => number | null;
  workoutVolume: (session: WorkoutSession) => number;
};

const { doubleProgression, estimatedOneRepMax, loadAdaptation, nextTemplate, personalRecordsFor, recoveryStatus, roadmapCompletion, weeklyAverageWeight, workoutVolume } = sport;

const exercise: WorkoutExercise = { id: "exercise-1", exerciseId: "bench", nameSnapshot: "Жим", primaryMuscleSnapshot: "chest", targetSets: 3, targetRepRange: "8–12", completed: true, notes: "", sets: [{ id: "set-1", setNumber: 1, weight: 80, repetitions: 12, rir: 2, completed: true, warmup: false }, { id: "set-2", setNumber: 2, weight: 80, repetitions: 12, rir: 2, completed: true, warmup: false }, { id: "set-3", setNumber: 3, weight: 80, repetitions: 12, rir: 2, completed: true, warmup: false }] };
const session = (template: "A" | "B" | "C" | "D", date = "2026-08-03"): WorkoutSession => ({ id: `session-${template}`, date, workoutType: "gym", workoutTemplate: template, startedAt: `${date}T10:00:00.000Z`, planned: true, completed: true, notes: "", exercises: [exercise], createdAt: `${date}T10:00:00.000Z`, updatedAt: `${date}T11:00:00.000Z` });

describe("sport calculations", () => {
  it("calculates training volume, e1RM and a record from completed sets", () => {
    expect(workoutVolume(session("A"))).toBe(2880);
    expect(estimatedOneRepMax(80, 10)).toBe(106.7);
    expect(personalRecordsFor([session("A")]).some((record) => record.type === "estimated_1rm" && record.value === 112)).toBe(true);
  });
  it("keeps A–D queue based only on completed gym sessions", () => {
    expect(nextTemplate([session("A")])).toBe("B");
    expect(nextTemplate([session("A"), session("B", "2026-08-05")])).toBe("C");
  });
  it("flags recovery and basketball adaptation without changing history", () => {
    expect(recoveryStatus({ id: "r", date: "2026-08-04", sleepHours: 5, sleepQuality: 2, energy: 2, muscleSoreness: 3, jointPain: 0, stress: 3, motivation: 3, comment: "", createdAt: "" }).tone).toBe("yellow");
    expect(loadAdaptation("2026-08-04", [{ id: "b", date: "2026-08-03", durationMinutes: 70, format: "five_on_five", intensity: 4, gamesPlayed: 2, kneeDiscomfort: 0, ankleDiscomfort: 0, notes: "", createdAt: "", updatedAt: "" }], undefined, "D").suggestedTemplate).toBe("B");
    expect(doubleProgression(exercise)).toContain("можно обсудить небольшой доступный шаг веса");
  });
  it("uses actual measurements and roadmap statuses", () => {
    expect(weeklyAverageWeight([{ id: "m1", date: "2026-08-03", weightKg: 89, comment: "", createdAt: "" }, { id: "m2", date: "2026-08-05", weightKg: 88, comment: "", createdAt: "" }], "2026-08-03")).toBe(88.5);
    const roadmap = [{ id: "1", dayNumber: 1, date: "2026-08-03", phase: 1, title: "", description: "", goal: "", plannedActivity: "gym", estimatedMinutes: 60, tasks: [], adaptationNotes: "", status: "completed" }, { id: "2", dayNumber: 2, date: "2026-08-04", phase: 1, title: "", description: "", goal: "", plannedActivity: "recovery", estimatedMinutes: 20, tasks: [], adaptationNotes: "", status: "available" }] satisfies SportRoadmapDay[];
    expect(roadmapCompletion(roadmap)).toBe(50);
  });
});
