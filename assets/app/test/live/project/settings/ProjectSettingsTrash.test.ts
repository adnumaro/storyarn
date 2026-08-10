import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsTrash from "../../../../live/project/settings/ProjectSettingsTrash.vue";
import { createMockLive } from "../../../setup";

const passthrough = { template: "<div><slot /></div>" };

const trashedAsset = {
  id: 42,
  type: "asset" as const,
  name: "portrait.png",
  deleted_at: "2026-08-10T10:00:00Z",
  deletion_generation: 3,
  content_type: "image/png",
  size: 2048,
  deletion_reason: "user" as const,
  purge_at: "2026-08-11T10:00:00Z",
};

function mountTrash(canManage = true) {
  const live = createMockLive();
  const wrapper = mount(ProjectSettingsTrash, {
    props: {
      trashedItems: [trashedAsset],
      pagination: { page: 1, pageSize: 25, totalCount: 1, totalPages: 1 },
      typeCounts: { sheet: 0, flow: 0, scene: 0, asset: 1 },
      canManage,
    },
    global: {
      provide: { _live_vue: live },
      stubs: {
        Dialog: passthrough,
        DialogContent: passthrough,
        DialogDescription: passthrough,
        DialogFooter: passthrough,
        DialogHeader: passthrough,
        DialogTitle: passthrough,
      },
    },
  });

  return { live, wrapper };
}

describe("ProjectSettingsTrash assets", () => {
  it("renders asset metadata, actor, expiry, and the asset filter", () => {
    const { wrapper } = mountTrash();

    const row = wrapper.get('[data-testid="trash-item-asset-42"]');
    expect(row.text()).toContain("portrait.png");
    expect(row.text()).toContain("image/png");
    expect(row.text()).toContain("2.0 KB");
    expect(row.text()).toContain("Deleted by a user");
    expect(row.text()).toContain("Recoverable until");
    expect(wrapper.get('[data-testid="trash-filter-asset"]').text()).toContain("Asset");
  });

  it("sends the deletion generation when restoring or permanently deleting an asset", async () => {
    const { live, wrapper } = mountTrash();

    await wrapper.get('[data-testid="restore-asset-42"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "restore_item",
      { type: "asset", id: 42, generation: 3 },
      undefined,
    );

    await wrapper.get('[data-testid="delete-asset-42"]').trigger("click");
    const confirmDelete = wrapper
      .findAll("button")
      .filter((button) => button.text() === "Delete")
      .at(-1);

    expect(confirmDelete).toBeDefined();
    await confirmDelete!.trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "delete_item",
      { type: "asset", id: 42, generation: 3 },
      undefined,
    );
  });

  it("distinguishes snapshot-restore trash from user deletion", () => {
    const wrapper = mount(ProjectSettingsTrash, {
      props: {
        trashedItems: [
          {
            ...trashedAsset,
            deletion_reason: "snapshot_restore",
          },
        ],
        pagination: { page: 1, pageSize: 25, totalCount: 1, totalPages: 1 },
        typeCounts: { sheet: 0, flow: 0, scene: 0, asset: 1 },
        canManage: true,
      },
      global: {
        provide: { _live_vue: createMockLive() },
        stubs: {
          Dialog: passthrough,
          DialogContent: passthrough,
          DialogDescription: passthrough,
          DialogFooter: passthrough,
          DialogHeader: passthrough,
          DialogTitle: passthrough,
        },
      },
    });

    expect(wrapper.text()).toContain("Moved to trash by snapshot restore");
  });

  it("hides all trash mutations from read-only members", () => {
    const { wrapper } = mountTrash(false);

    expect(wrapper.find('[data-testid="restore-asset-42"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="delete-asset-42"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="empty-trash-trigger"]').exists()).toBe(false);
  });

  it("shows the recovery deadline for non-asset trash items", () => {
    const wrapper = mount(ProjectSettingsTrash, {
      props: {
        trashedItems: [
          {
            ...trashedAsset,
            id: 84,
            type: "sheet",
            name: "Chapter notes",
            deletion_generation: null,
            content_type: null,
            size: null,
            deletion_reason: null,
          },
        ],
        pagination: { page: 1, pageSize: 25, totalCount: 1, totalPages: 1 },
        typeCounts: { sheet: 1, flow: 0, scene: 0, asset: 0 },
        canManage: true,
      },
      global: {
        provide: { _live_vue: createMockLive() },
        stubs: {
          Dialog: passthrough,
          DialogContent: passthrough,
          DialogDescription: passthrough,
          DialogFooter: passthrough,
          DialogHeader: passthrough,
          DialogTitle: passthrough,
        },
      },
    });

    expect(wrapper.get('[data-testid="trash-item-sheet-84"]').text()).toContain(
      "Recoverable until",
    );
  });
});
