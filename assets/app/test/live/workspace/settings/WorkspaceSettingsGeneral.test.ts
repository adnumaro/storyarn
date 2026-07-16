import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
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
