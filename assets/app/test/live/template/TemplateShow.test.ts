import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import TemplateShow from "../../../live/template/show/TemplateShow.vue";
import type {
  TemplateDetail,
  TemplateInstallState,
  TemplateVersion,
} from "../../../live/template/types";
import { createMockLive, setTestLocale } from "../../setup";

/** The events the page pushed, each as its name and payload. */
function pushed(live: ReturnType<typeof createMockLive>) {
  return vi.mocked(live.pushEvent).mock.calls.map(([event, payload]) => [event, payload]);
}

const template: TemplateDetail = {
  id: 5,
  name: "Harbor Starter",
  description: "A port town",
  visibility: "private",
  status: "active",
  canPublish: true,
};

const versions: TemplateVersion[] = [
  {
    id: 12,
    versionNumber: 2,
    notes: "Second pass",
    publishedAt: "2026-09-20T10:00:00Z",
    publishedByEmail: "owner@example.com",
    isCurrent: true,
  },
  {
    id: 11,
    versionNumber: 1,
    notes: null,
    publishedAt: "2026-09-10T10:00:00Z",
    publishedByEmail: "owner@example.com",
    isCurrent: false,
  },
];

function installState(overrides: Partial<TemplateInstallState> = {}): TemplateInstallState {
  return {
    workspaces: [{ id: "3", name: "Studio" }],
    defaults: { workspaceId: "3", versionId: "12", name: "Harbor Starter" },
    activeInstallations: [],
    ...overrides,
  };
}

function mountShow(props: Partial<InstanceType<typeof TemplateShow>["$props"]> = {}) {
  const live = createMockLive();
  const wrapper = mount(TemplateShow, {
    props: {
      template,
      currentVersion: {
        ...versions[0],
        entityCounts: [
          ["glossary_entries", 3],
          ["sheet_avatars", 2],
        ],
        preview: { sheets: ["Captain"], flows: [], scenes: [] },
      },
      versions,
      install: installState(),
      templatesHref: "/templates",
      ...props,
    },
    global: { provide: { _live_vue: live } },
  });
  return { wrapper, live };
}

afterEach(() => {
  setTestLocale("en");
});

describe("TemplateShow", () => {
  it("publishes a new version with its notes and clears them once queued", async () => {
    const { wrapper, live } = mountShow();

    await wrapper.get("#template-version-notes").setValue("Third pass");
    await wrapper.get("#publish-template-version-form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "publish_new_version",
      { publication: { version_notes: "Third pass" } },
      expect.any(Function),
    );
    const onQueued = vi.mocked(live.pushEvent).mock.calls[0][2] as () => void;
    onQueued();
    await wrapper.vm.$nextTick();
    expect(wrapper.get<HTMLTextAreaElement>("#template-version-notes").element.value).toBe("");
  });

  it("names what the current version holds", () => {
    const { wrapper } = mountShow();
    const panel = wrapper.get("#template-version-panel").text();

    expect(panel).toContain("Glossary entries 3");
    expect(panel).toContain("sheet_avatars 2");
    expect(wrapper.get("#template-current-preview").text()).toContain("Captain");
  });

  it("does not publish while a publication is running", async () => {
    const { wrapper, live } = mountShow({ hasActivePublication: true });

    const button = wrapper.get("#publish-template-version-button");
    expect(button.attributes("disabled")).toBeDefined();
    expect(button.text()).toBe("Publication running");
    await wrapper.get("#publish-template-version-form").trigger("submit");

    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("hides publishing and the template's history from readers who do not manage it", () => {
    const { wrapper } = mountShow({ template: { ...template, canPublish: false } });

    expect(wrapper.find("#publish-template-version-form").exists()).toBe(false);
    expect(wrapper.find("#archive-template-button").exists()).toBe(false);
    expect(wrapper.find("#template-install-history").exists()).toBe(false);
    expect(wrapper.get("#template-versions-panel").text()).not.toContain("owner@example.com");
  });

  it("creates a project from the chosen defaults", async () => {
    const { wrapper, live } = mountShow();

    await wrapper.get("#template-install-form").trigger("submit");

    expect(pushed(live)).toEqual([
      ["install", { install: { workspace_id: "3", version_id: "12", name: "Harbor Starter" } }],
    ]);
    expect(wrapper.get("#template-install-submit").text()).toBe("Starting installation…");
  });

  it("follows a running installation and blocks another one", async () => {
    const { wrapper, live } = mountShow({
      install: installState({
        activeInstallations: [{ id: 44, projectName: "Harbor Copy", stage: "verifying" }],
      }),
    });

    const active = wrapper.get("#template-active-installation-44");
    expect(active.text()).toContain("Harbor Copy");
    expect(active.text()).toContain("Verifying the template…");
    expect(wrapper.get("#template-install-submit").attributes("disabled")).toBeDefined();

    await wrapper.get("#template-install-form").trigger("submit");
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("names an installation failure by its code and dismisses it by reference", async () => {
    const { wrapper, live } = mountShow({
      installationFailure: { id: 42, errorCode: "checksum_mismatch" },
    });

    expect(wrapper.get("#template-installation-failure").text()).toBe(
      "Template installation failed: The template failed its integrity check. Reference: 42",
    );

    await wrapper.get("#dismiss-template-installation-failure").trigger("click");
    expect(pushed(live)).toContainEqual([
      "dismiss_template_installation_failure",
      {
        installation_id: "42",
      },
    ]);
  });

  it("falls back to the generic reason for a code it does not know", () => {
    const { wrapper } = mountShow({
      installationFailure: { id: 43, errorCode: "materialization_failed" },
    });

    expect(wrapper.get("#template-installation-failure").text()).toContain(
      "The project could not be created. No partial project was kept.",
    );
  });

  it("names the failure in the reader's language", () => {
    setTestLocale("es");
    const { wrapper } = mountShow({
      installationFailure: { id: 42, errorCode: "checksum_mismatch" },
    });

    expect(wrapper.get("#template-installation-failure").text()).toBe(
      "La instalación de la template ha fallado: " +
        "La template no ha superado la comprobación de integridad. Referencia: 42",
    );
  });
});
