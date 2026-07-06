import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsGeneral from "../../../../live/project/settings/ProjectSettingsGeneral.vue";
import { createMockLive } from "../../../setup";

function mountGeneral(props = {}) {
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
      sourceLanguageName: "",
      projectTemplates: [],
      projectTemplatePublications: [],
      ...props,
    },
    global: {
      provide: {
        _live_vue: createMockLive(),
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
});
