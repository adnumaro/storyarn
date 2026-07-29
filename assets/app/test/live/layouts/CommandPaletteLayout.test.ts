import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import { defineComponent, nextTick } from "vue";
import CommandPaletteLayout from "../../../live/layouts/CommandPalette.vue";
import { paletteGroups, resetPaletteRegistry } from "../../../shared/command-palette/registry";

const CommandPaletteStub = defineComponent({
  name: "CommandPalette",
  props: {
    operationCatalog: {
      type: Array,
      default: () => [],
    },
  },
  template: "<div data-testid='command-palette' :data-operation-count='operationCatalog.length' />",
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

  it("marks the boundary ready after mount and forwards sudo grants", async () => {
    const wrapper = mount(CommandPaletteLayout, {
      props: { sudoGrant: "validated-grant" },
      global: { stubs: { CommandPalette: CommandPaletteStub } },
    });

    await nextTick();

    expect(wrapper.attributes("data-command-palette-ready")).toBe("true");
    expect(
      paletteGroups.value
        .flatMap((group) => group.commands)
        .find((command) => command.id === "account.security"),
    ).toMatchObject({ href: "/users/settings/security?sudo_grant=validated-grant" });
  });

  it("forwards the server-owned operation catalog to the palette", () => {
    const wrapper = mount(CommandPaletteLayout, {
      props: {
        operationCatalog: [
          {
            id: "goto",
            domain: "navigation",
            parameters: [],
            latency: "instant",
            authorization: "view",
            resultType: "navigation",
            phrase: [],
            help: {
              labelKey: "palette.operations.goto.label",
              descriptionKey: "palette.operations.goto.description",
              exampleKey: "palette.operations.goto.example",
              pattern: null,
            },
          },
        ],
      },
      global: { stubs: { CommandPalette: CommandPaletteStub } },
    });

    expect(wrapper.find("[data-testid='command-palette']").attributes("data-operation-count")).toBe(
      "1",
    );
  });
});
