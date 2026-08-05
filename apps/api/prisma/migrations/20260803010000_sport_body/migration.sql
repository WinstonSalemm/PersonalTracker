CREATE TABLE "SportMeasurement" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "date" TEXT NOT NULL,
  "weightKg" DOUBLE PRECISION, "waistCm" DOUBLE PRECISION, "abdomenCm" DOUBLE PRECISION, "chestCm" DOUBLE PRECISION,
  "bicepsLeftCm" DOUBLE PRECISION, "bicepsRightCm" DOUBLE PRECISION, "thighLeftCm" DOUBLE PRECISION, "thighRightCm" DOUBLE PRECISION, "bodyFatPercent" DOUBLE PRECISION, "comment" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "SportMeasurement_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "WorkoutSession" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "roadmapDayNumber" INTEGER, "date" TEXT NOT NULL, "workoutType" TEXT NOT NULL, "workoutTemplate" TEXT,
  "startedAt" TIMESTAMP(3) NOT NULL, "finishedAt" TIMESTAMP(3), "durationMinutes" INTEGER, "planned" BOOLEAN NOT NULL DEFAULT false, "completed" BOOLEAN NOT NULL DEFAULT false,
  "perceivedDifficulty" INTEGER, "energyBefore" INTEGER, "notes" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "WorkoutSession_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "WorkoutExercise" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "workoutSessionClientId" TEXT NOT NULL, "exerciseId" TEXT, "nameSnapshot" TEXT NOT NULL, "primaryMuscleSnapshot" TEXT NOT NULL,
  "targetSets" INTEGER NOT NULL, "targetRepRange" TEXT NOT NULL, "completed" BOOLEAN NOT NULL DEFAULT false, "notes" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "WorkoutExercise_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "ExerciseSet" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "workoutExerciseClientId" TEXT NOT NULL, "setNumber" INTEGER NOT NULL, "weight" DOUBLE PRECISION NOT NULL, "repetitions" INTEGER NOT NULL,
  "rpe" INTEGER, "rir" INTEGER, "completed" BOOLEAN NOT NULL DEFAULT false, "warmup" BOOLEAN NOT NULL DEFAULT false, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "ExerciseSet_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "BasketballSession" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "date" TEXT NOT NULL, "durationMinutes" INTEGER NOT NULL, "format" TEXT NOT NULL, "intensity" INTEGER NOT NULL, "gamesPlayed" INTEGER NOT NULL,
  "kneeDiscomfort" INTEGER NOT NULL, "ankleDiscomfort" INTEGER NOT NULL, "notes" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "BasketballSession_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "RecoveryCheckIn" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "date" TEXT NOT NULL, "sleepHours" DOUBLE PRECISION NOT NULL, "sleepQuality" INTEGER NOT NULL, "energy" INTEGER NOT NULL,
  "muscleSoreness" INTEGER NOT NULL, "jointPain" INTEGER NOT NULL, "stress" INTEGER NOT NULL, "motivation" INTEGER NOT NULL, "comment" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "RecoveryCheckIn_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "SportCheckpoint" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "dayNumber" INTEGER NOT NULL, "date" TEXT NOT NULL, "label" TEXT NOT NULL, "notes" TEXT, "completed" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "SportCheckpoint_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "SportRoadmapProgress" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "clientId" TEXT NOT NULL, "dayNumber" INTEGER NOT NULL, "date" TEXT NOT NULL, "phase" INTEGER NOT NULL, "plannedActivity" TEXT NOT NULL, "workoutTemplate" TEXT, "status" TEXT NOT NULL, "skipReason" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "SportRoadmapProgress_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "SportMeasurement_userId_clientId_key" ON "SportMeasurement"("userId", "clientId");
CREATE INDEX "SportMeasurement_userId_date_idx" ON "SportMeasurement"("userId", "date");
CREATE UNIQUE INDEX "WorkoutSession_userId_clientId_key" ON "WorkoutSession"("userId", "clientId");
CREATE INDEX "WorkoutSession_userId_date_workoutType_idx" ON "WorkoutSession"("userId", "date", "workoutType");
CREATE UNIQUE INDEX "WorkoutExercise_userId_clientId_key" ON "WorkoutExercise"("userId", "clientId");
CREATE INDEX "WorkoutExercise_userId_workoutSessionClientId_idx" ON "WorkoutExercise"("userId", "workoutSessionClientId");
CREATE UNIQUE INDEX "ExerciseSet_userId_clientId_key" ON "ExerciseSet"("userId", "clientId");
CREATE INDEX "ExerciseSet_userId_workoutExerciseClientId_idx" ON "ExerciseSet"("userId", "workoutExerciseClientId");
CREATE UNIQUE INDEX "BasketballSession_userId_clientId_key" ON "BasketballSession"("userId", "clientId");
CREATE INDEX "BasketballSession_userId_date_idx" ON "BasketballSession"("userId", "date");
CREATE UNIQUE INDEX "RecoveryCheckIn_userId_clientId_key" ON "RecoveryCheckIn"("userId", "clientId");
CREATE INDEX "RecoveryCheckIn_userId_date_idx" ON "RecoveryCheckIn"("userId", "date");
CREATE UNIQUE INDEX "SportCheckpoint_userId_clientId_key" ON "SportCheckpoint"("userId", "clientId");
CREATE INDEX "SportCheckpoint_userId_date_idx" ON "SportCheckpoint"("userId", "date");
CREATE UNIQUE INDEX "SportRoadmapProgress_userId_clientId_key" ON "SportRoadmapProgress"("userId", "clientId");
CREATE INDEX "SportRoadmapProgress_userId_dayNumber_idx" ON "SportRoadmapProgress"("userId", "dayNumber");
ALTER TABLE "SportMeasurement" ADD CONSTRAINT "SportMeasurement_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "WorkoutSession" ADD CONSTRAINT "WorkoutSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "WorkoutExercise" ADD CONSTRAINT "WorkoutExercise_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ExerciseSet" ADD CONSTRAINT "ExerciseSet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BasketballSession" ADD CONSTRAINT "BasketballSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "RecoveryCheckIn" ADD CONSTRAINT "RecoveryCheckIn_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SportCheckpoint" ADD CONSTRAINT "SportCheckpoint_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SportRoadmapProgress" ADD CONSTRAINT "SportRoadmapProgress_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
