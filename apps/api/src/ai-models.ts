export type AiModelDefinition = {
  id: string;
  label: string;
  description: string;
  creditsPerChat: number;
};

// Keep the catalog server-owned so the client cannot select an arbitrary
// provider model or bypass the credit policy.
export const aiModels: AiModelDefinition[] = [
  { id: "gpt-4o-mini", label: "Быстрая", description: "Короткие повседневные ответы", creditsPerChat: 1 },
  { id: "gpt-4o", label: "Баланс", description: "Сложнее рассуждения и длиннее контекст", creditsPerChat: 2 },
  { id: "gpt-5", label: "Точная", description: "Максимальное качество из доступных", creditsPerChat: 4 },
];

export const defaultAiModel = aiModels.find((model) => model.id === "gpt-5") ?? aiModels[0];
export const findAiModel = (id?: string) => aiModels.find((model) => model.id === id) ?? defaultAiModel;
