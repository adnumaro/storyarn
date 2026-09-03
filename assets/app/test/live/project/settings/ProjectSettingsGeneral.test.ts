import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import type { App } from "vue";
import ProjectSettingsGeneral from "../../../../live/project/settings/ProjectSettingsGeneral.vue";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import SettingsSection from "../../../../components/settings/SettingsSection.vue";
import { createMockLive } from "../../../setup";
import type { LiveInterface } from "../../../../shared/composables/useLive";

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

const english = {
  value: "en",
  localeCode: "en",
  label: "English",
  languageTag: "en",
  flagCode: "gb",
  shortLabel: "EN",
};

const spanish = {
  value: "es",
  label: "Spanish",
  languageTag: "es",
  flagCode: "es",
  shortLabel: "ES",
};

function mountGeneral(props = {}, live: LiveInterface = createMockLive()) {
  return mount(ProjectSettingsGeneral, {
    attachTo: document.body,
    props: {
      projectDetails: {
        name: "Source Project",
        description: "Project description",
        type: "game",
        subtype: "",
        typeOther: "",
      },
      projectMetricsOptions: {
        project_types: ["game"],
        project_subtypes: {},
      },
      sourceLanguage: null,
      sourceLanguageOptions: [],
      canManageProject: true,
      ...props,
    },
    global: {
      plugins: [livePlugin(live)],
      provide: {
        _live_vue: live,
      },
      stubs: {
        Dialog: {
          props: ["open"],
          template: '<div :data-open="String(open)"><slot /></div>',
        },
        DialogContent: { template: "<div><slot /></div>" },
        DialogDescription: { template: "<p><slot /></p>" },
        DialogFooter: { template: "<div><slot /></div>" },
        DialogHeader: { template: "<div><slot /></div>" },
        DialogTitle: { template: "<h2><slot /></h2>" },
      },
    },
  });
}

describe("ProjectSettingsGeneral details", () => {
  it("saves the details on blur only when they changed", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);

    await wrapper.get("#project-name").trigger("blur");
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.get("#project-name").setValue("Renamed Project");
    await wrapper.get("#project-name").trigger("blur");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "update_project",
      {
        project: {
          name: "Renamed Project",
          description: "Project description",
          project_type: "game",
          project_subtype: "",
          project_type_other: "",
        },
      },
      undefined,
    );
  });

  it("does not save an empty name", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);

    await wrapper.get("#project-name").setValue("   ");
    await wrapper.get("#project-name").trigger("blur");

    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("no longer hosts template publishing", () => {
    const wrapper = mountGeneral();

    expect(wrapper.find('[data-testid="open-template-publication-dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Appearance");
  });
});

describe("ProjectSettingsGeneral source language", () => {
  it("requires confirmation before resetting translations", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral(
      { sourceLanguage: english, sourceLanguageOptions: [english, spanish] },
      live,
    );

    wrapper.findComponent(LanguagePicker).vm.$emit("select", spanish);
    await wrapper.vm.$nextTick();

    const confirmation = wrapper.findComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "change_source_language",
      expect.anything(),
      expect.anything(),
    );

    confirmation.vm.$emit("confirm");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "change_source_language",
      { locale_code: "es", reset_translations: true },
      undefined,
    );
  });
});

describe("ProjectSettingsGeneral danger zone", () => {
  it("requires typing the project name before deleting", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);

    await wrapper.get('[data-testid="open-project-delete-dialog"]').trigger("click");

    const confirm = wrapper.get("#confirm-delete-project");
    expect(confirm.attributes("disabled")).toBeDefined();

    await wrapper.get("input[placeholder='Source Project']").setValue("Source Project");
    expect(wrapper.get("#confirm-delete-project").attributes("disabled")).toBeUndefined();

    await wrapper.get("#confirm-delete-project").trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("delete_project", {}, undefined);
  });
});

describe("ProjectSettingsGeneral ownership changes", () => {
  it("locks every section and explains why for non-owners", () => {
    const wrapper = mountGeneral({
      canManageProject: false,
      sourceLanguage: english,
      sourceLanguageOptions: [english],
    });

    expect(wrapper.get('[data-testid="project-owner-controls-unavailable"]').text()).toContain(
      "Only the current project owner",
    );

    const sections = wrapper.findAllComponents(SettingsSection);
    expect(sections.length).toBeGreaterThan(0);
    for (const section of sections) {
      expect(section.props("locked")).toBe(true);
    }

    expect(wrapper.get("#project-name").attributes("disabled")).toBeDefined();
    expect(wrapper.find('[data-testid="project-delete-confirm-dialog"]').exists()).toBe(false);
  });

  it("clears owner-only confirmations instead of reopening stale intent", async () => {
    const wrapper = mountGeneral({
      sourceLanguage: english,
      sourceLanguageOptions: [english, spanish],
      canManageProject: true,
    });

    wrapper.findComponent(LanguagePicker).vm.$emit("select", spanish);
    await wrapper.get('[data-testid="open-project-repair-dialog"]').trigger("click");
    await wrapper.get('[data-testid="open-project-delete-dialog"]').trigger("click");

    expect(wrapper.getComponent(ConfirmDialog).props("open")).toBe(true);
    expect(
      wrapper.get('[data-testid="project-repair-confirm-dialog"]').attributes("data-open"),
    ).toBe("true");
    expect(
      wrapper.get('[data-testid="project-delete-confirm-dialog"]').attributes("data-open"),
    ).toBe("true");

    await wrapper.setProps({ canManageProject: false });
    expect(wrapper.findComponent(ConfirmDialog).exists()).toBe(false);
    expect(wrapper.find('[data-testid="project-repair-confirm-dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="project-delete-confirm-dialog"]').exists()).toBe(false);

    await wrapper.setProps({ canManageProject: true });
    expect(wrapper.getComponent(ConfirmDialog).props("open")).toBe(false);
    expect(wrapper.getComponent(ConfirmDialog).props("description")).not.toContain("Spanish");
    expect(
      wrapper.get('[data-testid="project-repair-confirm-dialog"]').attributes("data-open"),
    ).toBe("false");
    expect(
      wrapper.get('[data-testid="project-delete-confirm-dialog"]').attributes("data-open"),
    ).toBe("false");
  });
});
