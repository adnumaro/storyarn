import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import VersionHistory from "@modules/flows/editor/components/versioning/VersionHistory.vue";
import { createMockLive } from "../../../setup";

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
  it("shows pending and failed creation without exposing an unfinished version", async () => {
    const { global } = liveGlobal();
    const wrapper = mount(VersionHistory, {
      props: { restoreEnabled: false, creation: { pending: true, failed: false } },
      global,
    });
    expect(wrapper.get("#flow-version-creation-pending").text()).toBe("Creating version…");
    expect(wrapper.find("#flow-version-creation-failed").exists()).toBe(false);
    expect(wrapper.find('[data-testid^="restore-version-"]').exists()).toBe(false);
    await wrapper.setProps({ creation: { pending: false, failed: true } });
    expect(wrapper.find("#flow-version-creation-pending").exists()).toBe(false);
    expect(wrapper.get("#flow-version-creation-failed").attributes("role")).toBe("alert");
    await wrapper.setProps({ creation: { pending: false, failed: false } });
    expect(wrapper.find("#flow-version-creation-failed").exists()).toBe(false);
  });

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
      expect.objectContaining({
        version_number: 3,
        request_id: expect.any(String),
      }),
      expect.any(Function),
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
      expect.objectContaining({
        version_number: 3,
        request_id: expect.any(String),
      }),
      expect.any(Function),
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      2,
      "preview_restore",
      expect.objectContaining({
        version_number: 2,
        request_id: expect.any(String),
      }),
      expect.any(Function),
    );
  });
});
