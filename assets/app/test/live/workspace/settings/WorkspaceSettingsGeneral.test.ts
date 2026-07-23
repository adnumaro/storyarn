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

    expect(wrapper.getComponent(Switch).props("disabled")).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });
});
