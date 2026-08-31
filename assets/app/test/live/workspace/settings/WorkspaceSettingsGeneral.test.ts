import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import { Dialog } from "../../../../components/ui/dialog";
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
        isOwner: true,
        canEditWorkspace: true,
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
        canEditWorkspace: true,
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

  it("keeps member access to personal BYOK independent from managed Storyarn AI", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: true,
        canEditWorkspace: true,
        ai: {
          visible: true,
          managedAllowed: true,
          personalMembersAllowed: false,
          allowance: { status: "active", availableUnits: 25 },
        },
      },
      global: { provide: { _live_vue: live } },
    });

    expect(wrapper.get("#personal-ai-members-policy").text()).toContain("Personal AI for members");
    expect(wrapper.get("#personal-ai-members-policy").text()).toContain(
      "workspace owner can always",
    );
    expect(wrapper.get("#personal-ai-members-policy").text()).toContain("leaves Storyarn");
    expect(wrapper.get("#personal-ai-members-policy").text()).toContain(
      "cannot guarantee zero retention or no training",
    );
    expect(wrapper.get("#personal-ai-members-policy a").attributes("href")).toBe(
      "/users/settings/integrations",
    );

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

  it("renders a disabled policy control for non-owners", () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: false,
        canEditWorkspace: false,
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

describe("WorkspaceSettingsGeneral permission changes", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("discards a stale delete confirmation when ownership is lost", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: true,
        canEditWorkspace: true,
      },
      global: { provide: { _live_vue: live } },
    });

    await wrapper.get("#delete-workspace-button").trigger("click");
    expect(wrapper.getComponent(Dialog).props("open")).toBe(true);

    await wrapper.setProps({ isOwner: false, canEditWorkspace: false });
    expect(wrapper.findComponent(Dialog).exists()).toBe(false);

    await wrapper.setProps({ isOwner: true, canEditWorkspace: true });
    expect(wrapper.getComponent(Dialog).props("open")).toBe(false);
    expect(live.pushEvent).not.toHaveBeenCalledWith("delete", expect.anything(), undefined);
  });

  it("does not finish a banner upload after edit access is revoked", async () => {
    const live = createMockLive();
    const wrapper = mount(WorkspaceSettingsGeneral, {
      props: {
        workspaceName: "Narrative Team",
        workspaceBannerUrl: "/images/banner.png",
        sourceLocale: "en",
        languageOptions: [],
        isOwner: true,
        canEditWorkspace: true,
      },
      global: { provide: { _live_vue: live } },
    });

    const readers: DeferredFileReader[] = [];

    class DeferredFileReader {
      result: FileReader["result"] = null;
      onload: FileReader["onload"] = null;
      readAsDataURL = vi.fn();

      constructor() {
        readers.push(this);
      }
    }

    const file = new File(["banner"], "banner.png", { type: "image/png" });
    vi.stubGlobal("FileReader", DeferredFileReader);
    vi.spyOn(HTMLInputElement.prototype, "click").mockImplementation(
      function (this: HTMLInputElement) {
        Object.defineProperty(this, "files", { configurable: true, value: [file] });
        this.dispatchEvent(new Event("change"));
      },
    );

    await wrapper.get("#change-workspace-banner").trigger("click");
    const [reader] = readers;
    if (!reader) throw new Error("expected a pending banner read");
    expect(reader.readAsDataURL).toHaveBeenCalledWith(file);

    await wrapper.setProps({ canEditWorkspace: false });
    if (!reader.onload) throw new Error("expected a pending banner read");

    reader.result = "data:image/png;base64,YmFubmVy";
    reader.onload.call(
      reader as unknown as FileReader,
      new ProgressEvent("load") as ProgressEvent<FileReader>,
    );

    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "upload_workspace_banner",
      expect.anything(),
      undefined,
    );
  });
});
