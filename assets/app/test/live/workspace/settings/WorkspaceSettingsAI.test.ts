import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import { Switch } from "../../../../components/ui/switch";
import WorkspaceSettingsAI from "../../../../live/workspace/settings/WorkspaceSettingsAI.vue";
import { createMockLive } from "../../../setup";

function mountAI(props: Record<string, unknown>, live = createMockLive()) {
  return mount(WorkspaceSettingsAI, {
    props: {
      isOwner: true,
      integrationsPath: "/users/settings/integrations",
      ...props,
    },
    global: { provide: { _live_vue: live } },
  });
}

describe("WorkspaceSettingsAI", () => {
  it("lets only the owner request a managed-policy change", async () => {
    const live = createMockLive();
    const wrapper = mountAI(
      {
        ai: {
          visible: true,
          managedAllowed: false,
          allowance: {
            status: "active",
            availableUnits: 25,
            reservedUnits: 0,
            committedUnits: 5,
          },
          provenance: {
            provider: "fireworks",
            model: "accounts/fireworks/models/test-model",
            region: "global",
            dataRetention: "zero_data_retention",
            trainingUsage: "disabled",
          },
        },
      },
      live,
    );

    expect(wrapper.get("#storyarn-ai-settings").text()).toContain("25");
    expect(wrapper.get("#storyarn-ai-settings").text()).toContain("leaves Storyarn");
    expect(wrapper.get("#storyarn-ai-settings").text()).toContain("fireworks");
    wrapper.getComponent(Switch).vm.$emit("update:modelValue", true);
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "update_managed_ai_policy",
      { enabled: true },
      undefined,
    );
  });

  it("keeps member access to personal BYOK independent from managed Storyarn AI", async () => {
    const live = createMockLive();
    const wrapper = mountAI(
      {
        ai: {
          visible: true,
          managedAllowed: true,
          personalMembersAllowed: false,
          allowance: { status: "active", availableUnits: 25 },
        },
      },
      live,
    );

    const personal = wrapper.get("#personal-ai-members-policy");
    expect(personal.text()).toContain("Personal AI for members");
    expect(personal.text()).toContain("workspace owner can always");
    expect(personal.text()).toContain("leaves Storyarn");
    expect(personal.text()).toContain("cannot guarantee zero retention or no training");
    expect(personal.get("a").attributes("href")).toBe("/users/settings/integrations");

    const [, personalSwitch] = wrapper.findAllComponents(Switch);
    expect(personalSwitch.props("modelValue")).toBe(false);
    personalSwitch.vm.$emit("update:modelValue", true);
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "update_personal_ai_members_policy",
      { enabled: true },
      undefined,
    );
    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "update_managed_ai_policy",
      expect.anything(),
      undefined,
    );
  });

  it("renders disabled policy controls for non-owners", () => {
    const live = createMockLive();
    const wrapper = mountAI(
      {
        isOwner: false,
        ai: {
          visible: true,
          managedAllowed: true,
          allowance: { status: "unavailable", availableUnits: 0 },
        },
      },
      live,
    );

    const switches = wrapper.findAllComponents(Switch);
    expect(switches).toHaveLength(2);
    expect(switches.every((control) => control.props("disabled") === true)).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("explains when AI is not enabled for the workspace", () => {
    const wrapper = mountAI({ ai: { visible: false } });

    expect(wrapper.text()).toContain("AI is not enabled for this workspace");
    expect(wrapper.findAllComponents(Switch)).toHaveLength(0);
  });
});
