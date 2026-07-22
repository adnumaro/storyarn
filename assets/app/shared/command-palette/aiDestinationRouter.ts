import type { AICommandContext, AIDestination } from "./aiCommands";

type DestinationHandler = (
  destination: Exclude<AIDestination, { type: "none" }>,
  context: AICommandContext,
) => void | Promise<void>;

const handlers = new Map<string, DestinationHandler>();

export function registerAIDestination(
  destination: Exclude<AIDestination, { type: "none" }>,
  handler: DestinationHandler,
): () => void {
  const key = destinationKey(destination);

  if (handlers.has(key)) {
    throw new Error(`AI destination already registered: ${key}`);
  }

  handlers.set(key, handler);
  return () => handlers.delete(key);
}

export async function openAIDestination(
  destination: AIDestination,
  context: AICommandContext,
): Promise<void> {
  if (destination.type === "none") return;

  const handler = handlers.get(destinationKey(destination));
  if (!handler) throw new Error("AI destination is not available on this surface");

  await handler(destination, context);
}

/** Test-only: clears all destination handlers. */
export function resetAIDestinations(): void {
  handlers.clear();
}

function destinationKey(destination: Exclude<AIDestination, { type: "none" }>): string {
  return `${destination.type}:${destination.id}`;
}
