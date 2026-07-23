import { describe, expect, it } from "vitest";
import { accountPaletteCommands } from "../../../shared/command-palette/accountCommands";

describe("account palette commands", () => {
  it("omits AI integrations when the actor feature flag is disabled", () => {
    expect(accountPaletteCommands().map((command) => command.id)).not.toContain(
      "account.integrations",
    );
  });

  it("exposes AI integrations as typed navigation when the flag is enabled", () => {
    const command = accountPaletteCommands({ aiIntegrations: true }).find(
      (item) => item.id === "account.integrations",
    );

    expect(command).toMatchObject({ href: "/users/settings/integrations" });
  });

  it("preserves a validated sudo grant on sensitive account destinations", () => {
    const commands = accountPaletteCommands({ aiIntegrations: true }, "grant with + symbols");

    expect(commands.find((command) => command.id === "account.profile")).toMatchObject({
      href: "/users/settings?sudo_grant=grant+with+%2B+symbols",
    });
    expect(commands.find((command) => command.id === "account.security")).toMatchObject({
      href: "/users/settings/security?sudo_grant=grant+with+%2B+symbols",
    });
    expect(commands.find((command) => command.id === "account.integrations")).toMatchObject({
      href: "/users/settings/integrations?sudo_grant=grant+with+%2B+symbols",
    });
    expect(commands.find((command) => command.id === "account.tutorials")).toMatchObject({
      href: "/users/settings/tutorials",
    });
  });
});
