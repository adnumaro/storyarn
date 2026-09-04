import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import { Dialog } from "../../../../components/ui/dialog";
import WorkspaceSettingsGeneral from "../../../../live/workspace/settings/WorkspaceSettingsGeneral.vue";
import { createMockLive } from "../../../setup";

const languageOptions = [
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
];

function mountGeneral(props: Record<string, unknown> = {}, live = createMockLive()) {
  return mount(WorkspaceSettingsGeneral, {
    props: {
      workspaceName: "Narrative Team",
      workspaceDescription: "Shared workspace",
      sourceLocale: "en-US",
      languageOptions,
      isOwner: true,
      canEditWorkspace: true,
      ...props,
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("WorkspaceSettingsGeneral details", () => {
  it("saves the language selected through the shared picker", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({ workspaceBannerUrl: "/images/banner.png" }, live);

    wrapper.getComponent(LanguagePicker).vm.$emit("update:modelValue", "pt-br");
    await wrapper.vm.$nextTick();

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

  it("saves the name when the field loses focus after a change", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);
    const name = wrapper.get("#workspace-name");

    await name.trigger("blur");
    expect(live.pushEvent).not.toHaveBeenCalled();

    await name.setValue("Story Team");
    await name.trigger("blur");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "save",
      expect.objectContaining({ workspace: expect.objectContaining({ name: "Story Team" }) }),
      undefined,
    );
  });

  it("locks every field for a non-owner", () => {
    const wrapper = mountGeneral({ isOwner: false, canEditWorkspace: false });

    expect(wrapper.get("#workspace-name").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#workspace-description").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#delete-workspace-button").exists()).toBe(false);
  });
});

describe("WorkspaceSettingsGeneral permission changes", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("requires the workspace name before deleting and discards the dialog when ownership is lost", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);

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
    const wrapper = mountGeneral({ workspaceBannerUrl: "/images/banner.png" }, live);

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
