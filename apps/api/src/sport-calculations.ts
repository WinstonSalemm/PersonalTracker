/**
 * Server-owned Sport calculations.  Keep this independent of the archived web
 * client so API tests and future AI tools share one implementation.
 */
type ExerciseSet = { weight: number; repetitions: number; rir?: number; completed: boolean; warmup: boolean };
type WorkoutExercise = { exerciseId?: string; nameSnapshot: string; targetSets: number; targetRepRange: string; sets: ExerciseSet[] };
type WorkoutSession = { id: string; date: string; workoutType: string; workoutTemplate?: "A" | "B" | "C" | "D"; completed: boolean; exercises: WorkoutExercise[] };

const addDays = (date: string, days: number) => {
  const value = new Date(`${date}T12:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
};

export const workoutVolume = (session: WorkoutSession) => session.exercises.reduce(
  (total, exercise) => total + exercise.sets.filter((set) => set.completed && !set.warmup)
    .reduce((sum, set) => sum + set.weight * set.repetitions, 0),
  0,
);

export const estimatedOneRepMax = (weight: number, repetitions: number) =>
  repetitions >= 1 && repetitions <= 12 && weight > 0
    ? Math.round(weight * (1 + repetitions / 30) * 10) / 10
    : null;

export const personalRecordsFor = (sessions: WorkoutSession[]) => {
  const records = new Map<string, { type: string; value: number; date: string }>();
  for (const session of sessions.filter((row) => row.completed)) for (const exercise of session.exercises) {
    for (const set of exercise.sets.filter((row) => row.completed && !row.warmup)) {
      const key = `${exercise.exerciseId ?? exercise.nameSnapshot}:estimated_1rm`;
      const value = estimatedOneRepMax(set.weight, set.repetitions);
      if (value != null && (records.get(key)?.value ?? -Infinity) < value) records.set(key, { type: "estimated_1rm", value, date: session.date });
    }
  }
  return [...records.values()];
};

export const nextTemplate = (sessions: WorkoutSession[]): "A" | "B" | "C" | "D" => {
  const order: Array<"A" | "B" | "C" | "D"> = ["A", "B", "C", "D"];
  const last = sessions.filter((row) => row.completed && row.workoutType === "gym" && row.workoutTemplate)
    .sort((a, b) => b.date.localeCompare(a.date))[0]?.workoutTemplate;
  return last ? order[(order.indexOf(last) + 1) % order.length] : "A";
};

export const recoveryStatus = (checkIn?: { sleepHours: number; sleepQuality: number; energy: number; jointPain: number }) => {
  if (!checkIn) return { tone: "neutral" };
  if (checkIn.jointPain >= 5) return { tone: "red" };
  if (checkIn.sleepHours < 6 || checkIn.energy <= 2 || checkIn.sleepQuality <= 2) return { tone: "yellow" };
  return { tone: "green" };
};

export const loadAdaptation = (
  date: string,
  basketball: Array<{ date: string; intensity: number; durationMinutes: number }>,
  recovery: Parameters<typeof recoveryStatus>[0],
  template: "A" | "B" | "C" | "D",
) => {
  const hardBasketball = basketball.some((row) => row.date === addDays(date, -1) && row.intensity >= 4 && row.durationMinutes >= 60);
  const notes: string[] = [];
  if (hardBasketball) notes.push("Вчера была интенсивная баскетбольная сессия.");
  if (recoveryStatus(recovery).tone !== "green") notes.push("Нагрузка требует осторожной адаптации.");
  return { suggestedTemplate: hardBasketball && (template === "A" || template === "D") ? "B" : template, notes };
};

export const doubleProgression = (exercise: WorkoutExercise) => {
  const match = exercise.targetRepRange.match(/(\d+)\D+(\d+)/);
  const top = match ? Number(match[2]) : null;
  const working = exercise.sets.filter((set) => set.completed && !set.warmup);
  return Boolean(top && working.length >= exercise.targetSets && working.every((set) => set.repetitions >= top && (set.rir ?? 0) >= 2))
    ? "Все рабочие подходы достигли верхней границы диапазона с запасом ≥2 RIR: на следующей тренировке можно обсудить небольшой доступный шаг веса."
    : "Сохрани текущий вес и стремись к верхней границе повторений с чистой техникой.";
};

export const weeklyAverageWeight = (measurements: Array<{ date: string; weightKg?: number }>, weekStart: string) => {
  const rows = measurements.filter((row) => row.date >= weekStart && row.date <= addDays(weekStart, 6) && row.weightKg != null);
  return rows.length ? Math.round(rows.reduce((sum, row) => sum + (row.weightKg ?? 0), 0) / rows.length * 10) / 10 : null;
};

export const roadmapCompletion = (roadmap: Array<{ status: string }>) => roadmap.length ? Math.round(roadmap.filter((row) => row.status === "completed").length / roadmap.length * 100) : 0;
