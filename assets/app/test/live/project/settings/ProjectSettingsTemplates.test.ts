import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsTemplates from "../../../../live/project/settings/ProjectSettingsTemplates.vue";
import { createMockLive } from "../../../setup";
import type { LiveInterface } from "../../../../shared/composables/useLive";

function mountTemplates(props = {}, live: LiveInterface = createMockLive()) {
  return mount(ProjectSettingsTemplates, {
    attachTo: document.body,
    props: {
      projectName: "Source Project",
      projectDescription: "Project description",
      projectTemplates: [],
      projectTemplatePublications: [],
      canPublish: true,
      ...props,
    },
    global: {
      provide: { _live_vue: live },
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

describe("ProjectSettingsTemplates", () => {
  it("renders the publication history with its status", () => {
    const wrapper = mountTemplates({
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

    const row = wrapper.get('[data-testid="template-publication-42"]');
    expect(row.text()).toContain("Starter Template");
    expect(row.text()).toContain("Publishing");
    expect(wrapper.text()).not.toContain("No publications yet");
  });

  it("shows an empty state before the first publication", () => {
    const wrapper = mountTemplates();

    expect(wrapper.text()).toContain("No publications yet");
  });

  it("disables publishing while a publication is active", () => {
    const wrapper = mountTemplates({
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

  it("disables publishing and explains when the viewer may not publish", () => {
    const wrapper = mountTemplates({ canPublish: false });

    expect(
      wrapper.get('[data-testid="open-template-publication-dialog"]').attributes("disabled"),
    ).toBeDefined();
    expect(wrapper.text()).toContain("Only the project owner or a workspace admin");
  });

  it("sends version notes when publishing a template", async () => {
    const live = createMockLive();
    const wrapper = mountTemplates({}, live);

    await wrapper.get('[data-testid="open-template-publication-dialog"]').trigger("click");
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

  it("lists published templates and defaults the dialog to updating the first one", async () => {
    const live = createMockLive();
    const wrapper = mountTemplates(
      {
        projectTemplates: [
          { id: 7, name: "Starter", description: "Starter description", current_version_number: 3 },
        ],
      },
      live,
    );

    expect(wrapper.get('[data-testid="project-template-7"]').text()).toBe("Starter · v3");

    await wrapper.get('[data-testid="open-template-publication-dialog"]').trigger("click");
    await wrapper.get('[data-testid="publish-template-submit"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "publish_template",
      {
        template: expect.objectContaining({ mode: "update", template_id: 7, name: "Starter" }),
      },
      undefined,
    );
  });
});
