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
});
