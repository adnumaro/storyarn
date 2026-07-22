import type { PaletteCommandBase } from "./registry";

export type AIExecutionLane = "managed" | "personal_byok" | "workspace_byok";

export type AIDestination =
  | { type: "panel"; id: string }
  | { type: "inline_editor"; id: string }
  | { type: "route"; id: string }
  | { type: "none" };

export interface AICommandSelection {
  type: string;
  id: string;
  revision?: string;
}

export interface AICommandContext {
  surface: string;
  selection: AICommandSelection | null;
}

export interface AICommandCta {
  labelKey: string;
  destination: AIDestination;
  launch: () => Promise<AILaunchOutcome>;
}

export type AICommandAvailability =
  | { state: "hidden" }
  | { state: "ready" }
  | { state: "blocked"; reasonKey: string }
  | { state: "cta"; reasonKey: string; cta: AICommandCta };

export interface AIDeferredCost {
  kind: "deferred_to_preflight";
}

export interface AIResolvedCost {
  kind: "resolved";
  lane: AIExecutionLane;
  payer: string;
  disclosureKey: string;
  priceId: string | null;
  priceVersion: number | null;
}

interface AICommandBase extends Omit<
  PaletteCommandBase,
  "visible" | "enabled" | "disabledReasonKey"
> {
  kind: "ai";
  run?: never;
  href?: never;
  taskId: string;
  context: AICommandContext;
  availability: AICommandAvailability;
  destination: AIDestination;
}

export type AILaunchOutcome =
  | { status: "launched" }
  | { status: "blocked"; reasonKey: string; cta?: AICommandCta }
  | { status: "failed"; reasonKey: string };

export type AIExecuteOutcome =
  | {
      status: "succeeded";
      operationId: string;
      destination: AIDestination;
    }
  | {
      status: "queued";
      operationId: string;
      destination: AIDestination;
    }
  | { status: "blocked"; reasonKey: string; cta?: AICommandCta }
  | { status: "failed"; reasonKey: string };

export interface AILaunchCommand extends AICommandBase {
  mode: "launch";
  cost: AIDeferredCost;
  launch: () => Promise<AILaunchOutcome>;
}

export interface AIExecuteCommand extends AICommandBase {
  mode: "execute";
  cost: AIResolvedCost;
  execute: () => Promise<AIExecuteOutcome>;
}

export type AIPaletteCommand = AILaunchCommand | AIExecuteCommand;

export interface AIDestinationRuntime {
  open: (destination: AIDestination, context: AICommandContext) => void | Promise<void>;
}

export type AICommandRunResult =
  | { status: "completed"; operationId?: string }
  | { status: "blocked"; reasonKey: string; cta?: AICommandCta }
  | { status: "failed"; reasonKey: string };

export function isAIPaletteCommand(command: unknown): command is AIPaletteCommand {
  return (
    typeof command === "object" && command !== null && "kind" in command && command.kind === "ai"
  );
}

/**
 * Runs only server-resolved AI descriptors. The runner owns destination
 * routing so command payloads never carry raw URLs or result content.
 */
export async function runAIPaletteCommand(
  command: AIPaletteCommand,
  runtime: AIDestinationRuntime,
): Promise<AICommandRunResult> {
  const unavailable = availabilityResult(command.availability);
  if (unavailable) return unavailable;

  try {
    if (command.mode === "launch") {
      const outcome = await command.launch();

      if (outcome.status === "launched") {
        await runtime.open(command.destination, command.context);
        return { status: "completed" };
      }

      return outcome;
    }

    const outcome = await command.execute();

    if (outcome.status === "succeeded" || outcome.status === "queued") {
      await runtime.open(outcome.destination, command.context);
      return { status: "completed", operationId: outcome.operationId };
    }

    if (outcome.status === "blocked") {
      return { status: "blocked", reasonKey: outcome.reasonKey, cta: outcome.cta };
    }

    return { status: "failed", reasonKey: outcome.reasonKey };
  } catch {
    return { status: "failed", reasonKey: "palette.command_failed" };
  }
}

export async function runAICommandCta(
  cta: AICommandCta,
  context: AICommandContext,
  runtime: AIDestinationRuntime,
): Promise<AICommandRunResult> {
  try {
    const outcome = await cta.launch();

    if (outcome.status === "launched") {
      await runtime.open(cta.destination, context);
      return { status: "completed" };
    }

    return outcome;
  } catch {
    return { status: "failed", reasonKey: "palette.command_failed" };
  }
}

function availabilityResult(availability: AICommandAvailability): AICommandRunResult | null {
  switch (availability.state) {
    case "ready":
      return null;
    case "hidden":
      return { status: "blocked", reasonKey: "palette.not_allowed" };
    case "blocked":
      return { status: "blocked", reasonKey: availability.reasonKey };
    case "cta":
      return { status: "blocked", reasonKey: availability.reasonKey, cta: availability.cta };
  }
}
