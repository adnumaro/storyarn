import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import VersionHistory from "../../../components/versioning/history/VersionHistory.vue";
import ProjectSettingsSnapshots from "../../../live/project/settings/ProjectSettingsSnapshots.vue";
import WorkspaceSettingsDeletedProjects from "../../../live/workspace/settings/WorkspaceSettingsDeletedProjects.vue";
import { createMockLive } from "../../setup";

const dialogStubs = {
  Dialog: { template: "<div><slot /></div>" },
  DialogClose: { template: "<div><slot /></div>" },
  DialogContent: { template: "<div><slot /></div>" },
  DialogDescription: { template: "<div><slot /></div>" },
  DialogFooter: { template: "<div><slot /></div>" },
  DialogHeader: { template: "<div><slot /></div>" },
  DialogTitle: { template: "<div><slot /></div>" },
  CreateVersionDialog: true,
  DeleteVersionDialog: true,
  PromoteVersionDialog: true,
  RestorePreviewDialog: true,
  UnsavedChangesDialog: true,
};

function liveGlobal() {
  const live = createMockLive();

  return {
    live,
    global: {
      provide: {
        _live_vue: live,
      },
      stubs: dialogStubs,
    },
  };
}

describe("restore containment", () => {
  it("hides version restore while preserving compare and delete", async () => {
    const { live, global } = liveGlobal();

    const wrapper = mount(VersionHistory, {
      props: {
        versions: [
          {
            id: 10,
            versionNumber: 3,
            title: "Milestone",
          },
        ],
        namedVersions: [
          {
            id: 10,
            versionNumber: 3,
            title: "Milestone",
          },
        ],
        autoVersions: [],
        canEdit: true,
        canNameVersion: true,
        restoreEnabled: false,
      },
      global,
    });

    expect(wrapper.find('[data-testid^="restore-version-"]').exists()).toBe(false);
    expect(wrapper.find('button[title="Compare with current"]').exists()).toBe(true);
    expect(wrapper.find('button[title="Delete version"]').exists()).toBe(true);

    await wrapper.get('button[title="Compare with current"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "compare_version",
      {
        version_number: 3,
      },
      undefined,
    );
  });

  it("renders version restore only when the server capability is enabled", async () => {
    const { live, global } = liveGlobal();

    const wrapper = mount(VersionHistory, {
      props: {
        versions: [{ id: 10, versionNumber: 3, title: "Milestone" }],
        namedVersions: [{ id: 10, versionNumber: 3, title: "Milestone" }],
        autoVersions: [],
        canEdit: true,
        restoreEnabled: true,
      },
      global,
    });

    await wrapper.get('[data-testid="restore-version-3"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "preview_restore",
      {
        version_number: 3,
      },
      undefined,
    );
  });

  it("targets named and automatic restores by version number", async () => {
    const { live, global } = liveGlobal();

    const wrapper = mount(VersionHistory, {
      props: {
        versions: [
          { id: 10, versionNumber: 3, title: "Milestone" },
          { id: 11, versionNumber: 2, changeSummary: "Auto-save" },
        ],
        namedVersions: [{ id: 10, versionNumber: 3, title: "Milestone" }],
        autoVersions: [{ id: 11, versionNumber: 2, changeSummary: "Auto-save" }],
        canEdit: true,
        canNameVersion: true,
        restoreEnabled: true,
      },
      global,
    });

    const autoVersionsToggle = wrapper
      .findAll("button")
      .find((button) => button.text().includes("auto-save"));

    expect(autoVersionsToggle).toBeDefined();
    await autoVersionsToggle!.trigger("click");

    await wrapper.get('[data-testid="restore-version-3"]').trigger("click");
    await wrapper.get('[data-testid="restore-version-2"]').trigger("click");

    expect(live.pushEvent).toHaveBeenNthCalledWith(
      1,
      "preview_restore",
      {
        version_number: 3,
      },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      2,
      "preview_restore",
      {
        version_number: 2,
      },
      undefined,
    );
  });

  it("hides project snapshot restore while preserving download and delete", () => {
    const { global } = liveGlobal();

    const wrapper = mount(ProjectSettingsSnapshots, {
      props: {
        snapshots: [
          {
            id: 21,
            title: "Safe copy",
            versionNumber: 2,
            insertedAt: "2026-07-17T10:00:00Z",
          },
        ],
        restoreEnabled: false,
        workspaceSlug: "writers",
        projectSlug: "story",
      },
      global,
    });

    expect(wrapper.find('[data-testid="restore-project-snapshot"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="delete-project-snapshot"]').exists()).toBe(true);
    wrapper.get('a[href="/workspaces/writers/projects/story/snapshots/21/download"]');
    wrapper.get("form");
  });

  it("hides deleted-project recovery and makes project expansion inert", async () => {
    const { live, global } = liveGlobal();

    const wrapper = mount(WorkspaceSettingsDeletedProjects, {
      props: {
        deletedProjects: [
          {
            id: 31,
            name: "Deleted story",
            deleted_time_ago: "Deleted today",
            snapshot_count: 1,
          },
        ],
        expandedProjectId: 31,
        snapshots: [
          {
            id: 41,
            version_number: 1,
            formatted_date: "Today",
          },
        ],
        recoveryEnabled: false,
      },
      global,
    });

    expect(wrapper.find('[data-testid="recover-deleted-project"]').exists()).toBe(false);

    const projectButton = wrapper.get("button");
    expect(projectButton.attributes("disabled")).toBeDefined();
    await projectButton.trigger("click");
    expect(live.pushEvent).not.toHaveBeenCalled();
  });
});
