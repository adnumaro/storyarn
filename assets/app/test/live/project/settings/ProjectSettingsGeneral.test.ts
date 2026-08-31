import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import type { App } from "vue";
import ProjectSettingsGeneral from "../../../../live/project/settings/ProjectSettingsGeneral.vue";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import { createMockLive } from "../../../setup";
import type { LiveInterface } from "../../../../shared/composables/useLive";

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

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
      projectTemplates: [],
      projectTemplatePublications: [],
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

describe("ProjectSettingsGeneral template publication", () => {
  it("renders recent template publication status", () => {
    const wrapper = mountGeneral({
      projectTemplatePublications: [
        {
          id: 42,
          mode: "new",
          status: "running",
          template_id: null,
          template_version_id: null,
          name: "Starter Template",
          description: "",
        },
      ],
    });

    expect(wrapper.get('[data-testid="template-publication-42"]').text()).toContain(
      "Starter Template",
    );
    expect(wrapper.get('[data-testid="template-publication-42"]').text()).toContain("Publishing");
  });

  it("disables publishing when this project already has an active publication", () => {
    const wrapper = mountGeneral({
      projectTemplatePublications: [
        {
          id: 42,
          mode: "new",
          status: "queued",
          template_id: null,
          template_version_id: null,
          name: "Starter Template",
          description: "",
        },
      ],
    });

    const trigger = wrapper.get('[data-testid="open-template-publication-dialog"]');
    expect(trigger.attributes("disabled")).toBeDefined();
    expect(trigger.text()).toContain("Publication running");
  });

  it("sends version notes when publishing a template", async () => {
    const live = createMockLive();
    const wrapper = mountGeneral({}, live);

    await wrapper.get("#template-version-notes").setValue("First release notes");
    await wrapper.get('[data-testid="publish-template-submit"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "publish_template",
      {
        template: expect.objectContaining({
          mode: "new",
          name: "Source Project",
          description: "Project description",
          version_notes: "First release notes",
        }),
      },
      undefined,
    );
  });
});

describe("ProjectSettingsGeneral source language", () => {
  it("requires confirmation before resetting translations", async () => {
    const live = createMockLive();
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

describe("ProjectSettingsGeneral ownership changes", () => {
  it("keeps shared controls available but removes owner-only controls", () => {
    const english = {
      value: "en",
      localeCode: "en",
      label: "English",
      languageTag: "en",
      flagCode: "gb",
      shortLabel: "EN",
    };

    const wrapper = mountGeneral({
      canManageProject: false,
      sourceLanguage: english,
      sourceLanguageOptions: [english],
    });

    expect(wrapper.get('[data-testid="project-owner-controls-unavailable"]').text()).toContain(
      "Only the current project owner",
    );
    expect(wrapper.find("#project-name").exists()).toBe(false);
    expect(wrapper.findComponent(LanguagePicker).exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Project Theme");
    expect(wrapper.text()).not.toContain("Maintenance");
    expect(wrapper.text()).not.toContain("Danger Zone");

    expect(wrapper.find('[data-testid="open-template-publication-dialog"]').exists()).toBe(true);
    expect(wrapper.text()).toContain("Appearance");
  });

  it("clears owner-only confirmations instead of reopening stale intent", async () => {
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
