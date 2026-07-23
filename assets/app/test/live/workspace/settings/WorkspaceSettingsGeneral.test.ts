import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import { Switch } from "../../../../components/ui/switch";
import WorkspaceSettingsGeneral from "../../../../live/workspace/settings/WorkspaceSettingsGeneral.vue";
import { createMockLive } from "../../../setup";

describe("WorkspaceSettingsGeneral source language", () => {
  it("submits the language selected through the shared picker", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        workspaceDescription: "Shared workspace",
        workspaceBannerUrl: "/images/banner.png",
        sourceLocale: "en-US",
        languageOptions: [
          {
            value: "en-us",
            label: "English (US)",
            languageTag: "en-US",
            flagCode: "us",
            shortLabel: "EN",
          },
          {
            value: "pt-br",
            label: "Portuguese (Brazil)",
            languageTag: "pt-BR",
            flagCode: "br",
            shortLabel: "PT",
          },
        ],
      },
      global: {
        provide: {
          _live_vue: live,
        },
      },
    });

    wrapper.getComponent(LanguagePicker).vm.$emit("update:modelValue", "pt-br");
    await wrapper.vm.$nextTick();
    await wrapper.get("#workspace-settings-form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "save",
      {
        workspace: {
          name: "Narrative Team",
          description: "Shared workspace",
          banner_url: "/images/banner.png",
          source_locale: "pt-br",
        },
      },
      undefined,
    );
  });
});

describe("WorkspaceSettingsGeneral Storyarn AI policy", () => {
  it("lets only the owner request a managed-policy change", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: true,
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
      global: { provide: { _live_vue: live } },
    });

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

  it("keeps personal BYOK policy independent from managed Storyarn AI", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: true,
        ai: {
          visible: true,
          managedAllowed: true,
          personalAllowed: false,
          allowance: { status: "active", availableUnits: 25 },
        },
      },
      global: { provide: { _live_vue: live } },
    });

    expect(wrapper.get("#personal-ai-policy").text()).toContain("billed by the provider");
    expect(wrapper.get("#personal-ai-policy").text()).toContain("leave Storyarn");
    expect(wrapper.get("#personal-ai-policy").text()).toContain("no automatic fallback");
    expect(wrapper.get("#personal-ai-policy a").attributes("href")).toBe(
      "/users/settings/integrations",
    );

    const [, personalSwitch] = wrapper.findAllComponents(Switch);
    expect(personalSwitch.props("modelValue")).toBe(false);
    personalSwitch.vm.$emit("update:modelValue", true);
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "update_personal_ai_policy",
      { enabled: true },
      undefined,
    );
    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "update_managed_ai_policy",
      expect.anything(),
      undefined,
    );
  });

  it("renders a disabled policy control for non-owners", () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: false,
        ai: {
          visible: true,
          managedAllowed: true,
          allowance: { status: "unavailable", availableUnits: 0 },
        },
      },
      global: { provide: { _live_vue: live } },
    });

    const switches = wrapper.findAllComponents(Switch);
    expect(switches).toHaveLength(2);
    expect(switches.every((control) => control.props("disabled") === true)).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });
});
