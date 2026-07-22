import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import { defineComponent } from "vue";
import CommandPaletteLayout from "../../../live/layouts/CommandPalette.vue";
import { paletteGroups, resetPaletteRegistry } from "../../../shared/command-palette/registry";

const CommandPaletteStub = defineComponent({
  name: "CommandPalette",
  template: "<div data-testid='command-palette' />",
});

function commandIds(): string[] {
  return paletteGroups.value.flatMap((group) => group.commands.map((command) => command.id));
}

describe("authenticated command palette boundary", () => {
  beforeEach(resetPaletteRegistry);

  it("owns global account commands and actor-resolved flags", () => {
    const wrapper = mount(CommandPaletteLayout, {
      props: { featureFlags: { aiIntegrations: true } },
      global: { stubs: { CommandPalette: CommandPaletteStub } },
    });

    expect(commandIds()).toEqual([
      "account.profile",
      "account.security",
      "account.tutorials",
      "account.integrations",
    ]);

    wrapper.unmount();
    expect(commandIds()).toEqual([]);
  });
});
