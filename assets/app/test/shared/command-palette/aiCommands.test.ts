import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  runAICommandCta,
  runAIPaletteCommand,
  type AICommandContext,
  type AILaunchCommand,
  type AIExecuteCommand,
} from "../../../shared/command-palette/aiCommands";
import {
  openAIDestination,
  registerAIDestination,
  resetAIDestinations,
} from "../../../shared/command-palette/aiDestinationRouter";

const context: AICommandContext = {
  surface: "flows",
  selection: { type: "flow", id: "41", revision: "flow-v7" },
};

function launchCommand(overrides: Partial<AILaunchCommand> = {}): AILaunchCommand {
  return {
    kind: "ai",
    mode: "launch",
    id: "ai.dialogue.translate",
    taskId: "dialogue.translate",
    groupKey: "palette.groups.actions",
    context,
    availability: { state: "ready" },
    destination: { type: "panel", id: "translation-preflight" },
    cost: { kind: "deferred_to_preflight" },
    launch: vi.fn().mockResolvedValue({ status: "launched" }),
    ...overrides,
  };
}

function executeCommand(overrides: Partial<AIExecuteCommand> = {}): AIExecuteCommand {
  return {
    kind: "ai",
    mode: "execute",
    id: "ai.dialogue.translate-now",
    taskId: "dialogue.translate",
    groupKey: "palette.groups.actions",
    context,
    availability: { state: "ready" },
    destination: { type: "inline_editor", id: "dialogue-translation" },
    cost: {
      kind: "resolved",
      lane: "managed",
      payer: "workspace_allowance",
      disclosureKey: "ai.cost.fixed_task",
      priceId: "translation-short-v1",
      priceVersion: 3,
    },
    execute: vi.fn().mockResolvedValue({
      status: "queued",
      operationId: "op-123",
      destination: { type: "panel", id: "ai-operation" },
    }),
    ...overrides,
  };
}

describe("AI command-palette contract", () => {
  beforeEach(() => resetAIDestinations());

  it("launch defers cost, creates no execute operation, and opens its declarative destination", async () => {
    const command = launchCommand();
    const open = vi.fn();

    expect(command.cost).toEqual({ kind: "deferred_to_preflight" });
    expect("execute" in command).toBe(false);

    await expect(runAIPaletteCommand(command, { open })).resolves.toEqual({
      status: "completed",
    });
    expect(command.launch).toHaveBeenCalledOnce();
    expect(open).toHaveBeenCalledWith(command.destination, context);
  });

  it("execute carries server-resolved cost and routes only an accepted operation outcome", async () => {
    const command = executeCommand();
    const open = vi.fn();

    expect(command.cost).toMatchObject({
      kind: "resolved",
      lane: "managed",
      priceId: "translation-short-v1",
      priceVersion: 3,
    });

    await expect(runAIPaletteCommand(command, { open })).resolves.toEqual({
      status: "completed",
      operationId: "op-123",
    });
    expect(open).toHaveBeenCalledWith({ type: "panel", id: "ai-operation" }, context);
  });

  it("presentation availability never invokes a hidden or blocked command", async () => {
    const launch = vi.fn();
    const hidden = launchCommand({ availability: { state: "hidden" }, launch });
    const blocked = launchCommand({
      availability: { state: "blocked", reasonKey: "ai.permission_required" },
      launch,
    });

    await expect(runAIPaletteCommand(hidden, { open: vi.fn() })).resolves.toEqual({
      status: "blocked",
      reasonKey: "palette.not_allowed",
    });
    await expect(runAIPaletteCommand(blocked, { open: vi.fn() })).resolves.toEqual({
      status: "blocked",
      reasonKey: "ai.permission_required",
    });
    expect(launch).not.toHaveBeenCalled();
  });

  it("returns classified blocked state and an executable CTA without recording success", async () => {
    const cta = {
      labelKey: "settings.nav.items.integrations",
      destination: { type: "route", id: "account-ai-integrations" } as const,
      launch: vi.fn().mockResolvedValue({ status: "launched" } as const),
    };
    const command = launchCommand({
      availability: { state: "cta", reasonKey: "ai.connect_key", cta },
    });
    const open = vi.fn();

    await expect(runAIPaletteCommand(command, { open })).resolves.toEqual({
      status: "blocked",
      reasonKey: "ai.connect_key",
      cta,
    });
    expect(command.launch).not.toHaveBeenCalled();
    expect(open).not.toHaveBeenCalled();

    await expect(runAICommandCta(cta, context, { open })).resolves.toEqual({
      status: "completed",
    });
    expect(open).toHaveBeenCalledWith(cta.destination, context);
  });

  it("normalizes rejected promises and never opens a result destination", async () => {
    const command = executeCommand({
      execute: vi.fn().mockRejectedValue(new Error("transport failed")),
    });
    const open = vi.fn();

    await expect(runAIPaletteCommand(command, { open })).resolves.toEqual({
      status: "failed",
      reasonKey: "palette.command_failed",
    });
    expect(open).not.toHaveBeenCalled();
  });

  it("routes by registered destination id and rejects raw or unavailable destinations", async () => {
    const handler = vi.fn();
    const destination = { type: "panel", id: "translation-preflight" } as const;
    const unregister = registerAIDestination(destination, handler);

    await openAIDestination(destination, context);
    expect(handler).toHaveBeenCalledWith(destination, context);

    unregister();
    await expect(openAIDestination(destination, context)).rejects.toThrow(
      "AI destination is not available",
    );
  });
});
