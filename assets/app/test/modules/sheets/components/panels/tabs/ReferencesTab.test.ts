import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ReferencesTab from "@modules/sheets/components/panels/tabs/ReferencesTab.vue";

const passthroughStubs = {
  Badge: { template: "<span><slot /></span>" },
  Collapsible: { template: "<section><slot /></section>" },
  CollapsibleContent: { template: "<div><slot /></div>" },
  CollapsibleTrigger: { template: "<button><slot /></button>" },
};

describe("ReferencesTab Scene ambient-flow usages", () => {
  it("links an ambient event read to its Scene without inventing a canvas focus", () => {
    const wrapper = mount(ReferencesTab, {
      props: {
        workspaceSlug: "writers-room",
        projectSlug: "veilbreak",
        variableUsage: [
          {
            blockId: 17,
            label: "Health",
            shortcut: "hero.profile.health",
            type: "number",
            writes: [],
            reads: [
              {
                sourceType: "scene_ambient_flow",
                sceneId: 41,
                sceneName: "Moonlit Courtyard",
                flowName: "Night ambience",
                stale: false,
              },
              {
                sourceType: "scene_pin",
                sceneId: 41,
                sceneName: "Moonlit Courtyard",
                pinLabel: "North gate",
                stale: false,
              },
            ],
          },
        ],
      },
      global: {
        mocks: { $t: (key: string) => key },
        stubs: passthroughStubs,
      },
    });

    const [ambientLink, pinLink] = wrapper.findAll("a");

    expect(ambientLink.attributes("href")).toBe(
      "/workspaces/writers-room/projects/veilbreak/scenes/41",
    );
    expect(ambientLink.text()).toContain("Moonlit Courtyard");
    expect(ambientLink.text()).toContain("Night ambience");
    expect(ambientLink.attributes("href")).not.toContain("undefined");

    expect(pinLink.attributes("href")).toBe(
      "/workspaces/writers-room/projects/veilbreak/scenes/41",
    );
    expect(pinLink.text()).toContain("North gate");
    expect(pinLink.attributes("href")).not.toContain("undefined");
  });
});
