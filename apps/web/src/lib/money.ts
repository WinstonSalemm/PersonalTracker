import type { MoneyCategory, MoneyCategoryKind, MoneyCurrency, MoneyState, MoneyTransaction } from "@/lib/types";

export const incomeCategories: Array<{ id: string; name: string; color: string }> = [
  { id: "accounting", name: "Бухгалтерия", color: "#34d399" },
  { id: "poj-support", name: "POJ PRO сопровождение", color: "#2dd4bf" },
  { id: "poj-development", name: "POJ PRO разработка", color: "#60a5fa" },
  { id: "websites", name: "Разработка сайтов", color: "#8b5cf6" },
  { id: "erp", name: "ERP", color: "#facc15" },
  { id: "shops", name: "Интернет-магазины", color: "#fb923c" },
  { id: "automation", name: "Автоматизация", color: "#f472b6" },
  { id: "salary", name: "Зарплата", color: "#4ade80" },
  { id: "one-off-income", name: "Разовая выплата", color: "#a78bfa" },
  { id: "other-income", name: "Другое", color: "#94a3b8" },
];

export const expenseCategories: Array<{ id: string; name: string; color: string }> = [
  { id: "groceries", name: "Продукты", color: "#fb923c" },
  { id: "eating-out", name: "Общепит", color: "#f97316" },
  { id: "cola-drinks", name: "Кола и напитки", color: "#facc15" },
  { id: "cigarettes", name: "Сигареты", color: "#fb7185" },
  { id: "transport", name: "Транспорт", color: "#60a5fa" },
  { id: "taxi", name: "Такси", color: "#38bdf8" },
  { id: "table-tennis", name: "Настольный теннис", color: "#2dd4bf" },
  { id: "family", name: "Семья", color: "#f472b6" },
  { id: "grandmother", name: "Бабушка", color: "#c084fc" },
  { id: "university", name: "Университет", color: "#a78bfa" },
  { id: "phone", name: "Телефон", color: "#818cf8" },
  { id: "car", name: "Автомобиль", color: "#94a3b8" },
  { id: "repair", name: "Ремонт", color: "#f59e0b" },
  { id: "parts", name: "Автозапчасти", color: "#64748b" },
  { id: "housing", name: "Жильё", color: "#8b5cf6" },
  { id: "health", name: "Здоровье", color: "#34d399" },
  { id: "clothing", name: "Одежда", color: "#f472b6" },
  { id: "entertainment", name: "Развлечения", color: "#14b8a6" },
  { id: "subscriptions", name: "Подписки", color: "#c084fc" },
  { id: "business", name: "Бизнес", color: "#facc15" },
  { id: "other-expense", name: "Другое", color: "#94a3b8" },
  { id: "uncategorized", name: "Не классифицировано", color: "#64748b" },
];

export const defaultCategories: MoneyCategory[] = [
  ...incomeCategories.map((item) => ({ ...item, kind: "income" as const, system: true })),
  ...expenseCategories.map((item) => ({ ...item, kind: "expense" as const, system: true })),
];

export const currencySymbol = (currency: MoneyCurrency) => currency === "USD" ? "$" : "сум";
export const formatMoney = (amount: number, currency: MoneyCurrency) => `${new Intl.NumberFormat("ru-RU", { maximumFractionDigits: currency === "USD" ? 2 : 0 }).format(amount)} ${currencySymbol(currency)}`;
export const toBase = (amount: number, currency: MoneyCurrency, state: Pick<MoneyState, "exchangeRate" | "baseCurrency">) => {
  if (currency === state.baseCurrency) return amount;
  return state.baseCurrency === "UZS" ? amount * state.exchangeRate : amount / state.exchangeRate;
};
export const getCategory = (categories: MoneyCategory[], id: string, kind?: MoneyCategoryKind) => categories.find((category) => category.id === id && (!kind || category.kind === kind));
export const isCompleted = (transaction: MoneyTransaction) => transaction.status === "completed";
export const dateInMonth = (date: string, month: string) => date.startsWith(month);
