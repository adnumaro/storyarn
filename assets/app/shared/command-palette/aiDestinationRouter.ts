import type { AICommandContext, AIDestination } from "./aiCommands";

type DestinationHandler = (
  destination: Exclude<AIDestination, { type: "none" }>,
  context: AICommandContext,
) => void | Promise<void>;

interface DestinationRegistration {
  token: symbol;
  handler: DestinationHandler;
}

const handlers = new Map<string, DestinationRegistration>();

export function registerAIDestination(
  destination: Exclude<AIDestination, { type: "none" }>,
  handler: DestinationHandler,
): () => void {
  const key = destinationKey(destination);
  const token = Symbol(key);

  // Last registration wins. A LiveVue remount runs the incoming component's
  // setup BEFORE the outgoing one's onUnmounted, so refusing a duplicate would
  // crash the surface on every remount. The token check below is what stops
  // the outgoing instance's cleanup from removing the incoming registration.
  handlers.set(key, { token, handler });

  return () => {
    if (handlers.get(key)?.token === token) handlers.delete(key);
  };
}

export async function openAIDestination(
  destination: AIDestination,
  context: AICommandContext,
): Promise<void> {
  if (destination.type === "none") return;

  const registration = handlers.get(destinationKey(destination));
  if (!registration) throw new Error("AI destination is not available on this surface");

  await registration.handler(destination, context);
}

/** Test-only: clears all destination handlers. */
export function resetAIDestinations(): void {
  handlers.clear();
}

function destinationKey(destination: Exclude<AIDestination, { type: "none" }>): string {
  return `${destination.type}:${destination.id}`;
}
