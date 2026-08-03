export type Skill =
  | "grammar"
  | "vocabulary"
  | "listening"
  | "speaking"
  | "writing"
  | "business";

export type DayStatus = "locked" | "available" | "in_progress" | "completed" | "missed";
export type VocabularyStatus = "new" | "learning" | "familiar" | "mastered";

export interface Task {
  id: string;
  label: string;
  skill: Skill;
  required: boolean;
  completed: boolean;
}

export interface RoadmapDay {
  id: string;
  dayNumber: number;
  date: string;
  title: string;
  description: string;
  goal: string;
  grammarTopic: string;
  vocabularyTopic: string;
  listeningTopic: string;
  speakingTopic: string;
  writingTopic: string;
  businessTopic: string;
  estimatedMinutes: number;
  searchQueries: string[];
  resources: string[];
  tags: string[];
  tasks: Task[];
  notes: string;
  writtenAnswer: string;
  voiceLink: string;
  status: DayStatus;
}

export interface VocabularyItem {
  id: string;
  expression: string;
  translation: string;
  meaning: string;
  example: string;
  ownExample: string;
  category: string;
  addedAt: string;
  level: string;
  repetitions: number;
  nextReview: string;
  status: VocabularyStatus;
}

export interface MistakeItem {
  id: string;
  wrong: string;
  correct: string;
  rule: string;
  ownExample: string;
  category: string;
  repetitions: number;
  lastReviewed: string;
  fixed: boolean;
}

export interface WritingEntry {
  id: string;
  dayNumber: number;
  topic: string;
  original: string;
  corrected: string;
  comments: string;
  wordCount: number;
  minutes: number;
  errors: number;
  score: number;
  createdAt: string;
}

export interface SpeakingEntry {
  id: string;
  dayNumber: number;
  topic: string;
  durationSeconds: number;
  source: string;
  pauses: number;
  unknownWords: string;
  grammarErrors: string;
  comments: string;
  fluency: number;
  grammar: number;
  pronunciation: number;
  vocabulary: number;
  confidence: number;
  createdAt: string;
}

export interface TestResult {
  id: string;
  dayNumber: number;
  grammar: number;
  reading: number;
  listening: number;
  writing: number;
  speaking: number;
  business: number;
  comments: string;
  createdAt: string;
}

export interface TimerSession {
  id: string;
  dayNumber: number;
  startedAt: string;
  durationSeconds: number;
}

export type ExpenseCategory =
  | "food"
  | "transport"
  | "home"
  | "health"
  | "work"
  | "shopping"
  | "entertainment"
  | "subscriptions"
  | "other";

export interface ExpenseItem {
  id: string;
  amount: number;
  currency: string;
  category: ExpenseCategory;
  description: string;
  spentAt: string;
  paymentMethod: string;
  note: string;
}

export interface EnglishState {
  version: number;
  days: RoadmapDay[];
  vocabulary: VocabularyItem[];
  mistakes: MistakeItem[];
  writing: WritingEntry[];
  speaking: SpeakingEntry[];
  tests: TestResult[];
  timerSessions: TimerSession[];
  expenses: ExpenseItem[];
  monthlyBudget: number;
  currency: string;
  activeDayNumber: number;
  bestStreak: number;
  lastCompletedDay: number;
}

export type MoneyCurrency = "UZS" | "USD";
export type MoneyTransactionType = "income" | "expense" | "transfer";
export type MoneyPaymentMethod = "cash" | "card" | "bank" | "other";
export type MoneyTransactionStatus = "completed" | "planned" | "expected";
export type MoneyRecurrence = "weekly" | "monthly" | "quarterly" | "yearly";
export type MoneyAccountType = "cash" | "card" | "bank" | "wallet";
export type MoneyCategoryKind = "income" | "expense";

export interface MoneyAccount {
  id: string;
  name: string;
  type: MoneyAccountType;
  currency: MoneyCurrency;
  initialBalance: number;
  color: string;
  createdAt: string;
}

export interface MoneyCategory {
  id: string;
  name: string;
  kind: MoneyCategoryKind;
  color: string;
  system: boolean;
}

export interface MoneyTransaction {
  id: string;
  date: string;
  type: MoneyTransactionType;
  amount: number;
  currency: MoneyCurrency;
  counterparty: string;
  categoryId: string;
  purpose: string;
  paymentMethod: MoneyPaymentMethod;
  accountId: string;
  transferToAccountId?: string;
  recurring: boolean;
  status: MoneyTransactionStatus;
  incomeSource?: string;
  comment: string;
  obligationId?: string;
  essential?: boolean;
  createdAt: string;
}

export interface MoneyObligation {
  id: string;
  name: string;
  totalAmount: number;
  paidAmount: number;
  currency: MoneyCurrency;
  dueDate: string;
  recurrence: "once" | MoneyRecurrence;
  comment: string;
  status: "active" | "paid" | "paused";
}

export interface RecurringTransaction {
  id: string;
  name: string;
  type: "income" | "expense";
  amount: number;
  currency: MoneyCurrency;
  counterparty: string;
  categoryId: string;
  purpose: string;
  accountId: string;
  nextDate: string;
  recurrence: MoneyRecurrence;
  status: "active" | "paused";
}

export interface MoneyState {
  version: number;
  accounts: MoneyAccount[];
  categories: MoneyCategory[];
  transactions: MoneyTransaction[];
  obligations: MoneyObligation[];
  recurringTransactions: RecurringTransaction[];
  exchangeRate: number;
  baseCurrency: MoneyCurrency;
}

export type SalesSource = "2gis" | "olx" | "referral" | "former_client" | "friend" | "other";
export type SalesClientStatus = "new" | "to_call" | "reached" | "no_answer" | "admin" | "owner" | "interested" | "proposal_sent" | "follow_up" | "won" | "lost" | "irrelevant";
export type SalesCallResult = "no_answer" | "busy" | "wrong_number" | "admin" | "owner" | "call_back" | "interested" | "lost";
export type SalesOpportunityStatus = "none" | "draft" | "proposal_sent" | "negotiation" | "won" | "lost";
export type SalesFollowUpStatus = "today" | "overdue" | "future" | "completed";

export interface SalesClient {
  id: string;
  companyName: string;
  contactName: string;
  position: string;
  phone: string;
  telegram: string;
  city: string;
  niche: string;
  source: SalesSource;
  companyUrl: string;
  comment: string;
  createdAt: string;
  status: SalesClientStatus;
}

export interface SalesCall {
  id: string;
  clientId: string;
  dateTime: string;
  attemptNumber: number;
  result: SalesCallResult;
  whatSaid: string;
  problem: string;
  offered: string;
  objection: string;
  nextStep: string;
  nextContactDate: string;
  comment: string;
}

export interface SalesOpportunity {
  id: string;
  clientId: string;
  serviceId: string;
  taskDescription: string;
  amount: number;
  currency: MoneyCurrency;
  probability: number;
  decisionDate: string;
  status: SalesOpportunityStatus;
  proposalUrl: string;
  comment: string;
}

export interface SalesService {
  id: string;
  name: string;
  system: boolean;
}

export interface SalesFollowUp {
  id: string;
  clientId: string;
  date: string;
  reason: string;
  lastResult: string;
  nextStep: string;
  status: SalesFollowUpStatus;
  note: string;
}

export interface SalesState {
  version: number;
  dailyCallGoal: number;
  clients: SalesClient[];
  calls: SalesCall[];
  opportunities: SalesOpportunity[];
  services: SalesService[];
  followUps: SalesFollowUp[];
}
