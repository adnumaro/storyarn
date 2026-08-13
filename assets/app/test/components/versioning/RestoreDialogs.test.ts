import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import RestorePreviewDialog from "../../../components/versioning/history/RestorePreviewDialog.vue";
import UnsavedChangesDialog from "../../../components/versioning/history/UnsavedChangesDialog.vue";
import { useVersionHistory } from "../../../components/versioning/history/useVersionHistory";
import { createMockLive, withSetup } from "../../setup";

const dialogStubs = {
  Dialog: { template: "<div><slot /></div>" },
  DialogContent: { template: "<div><slot /></div>" },
  DialogDescription: { template: "<div><slot /></div>" },
  DialogFooter: { template: "<div><slot /></div>" },
  DialogHeader: { template: "<div><slot /></div>" },
  DialogTitle: { template: "<div><slot /></div>" },
};

describe("entity restore dialogs", () => {
  it("offers one restore path and explains the mandatory safety version", async () => {
    const wrapper = mount(UnsavedChangesDialog, {
      props: { open: true, versionNumber: 4 },
      global: { stubs: dialogStubs },
    });

    expect(wrapper.text()).toContain(
      "Storyarn will save and verify the current state as a safety version",
    );
    expect(wrapper.text()).toContain("Review restore");
    expect(wrapper.text()).not.toContain("Discard changes");

    const reviewButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("Review restore"));

    expect(reviewButton).toBeDefined();
    await reviewButton!.trigger("click");
    expect(wrapper.emitted("review-restore")).toHaveLength(1);
    expect(wrapper.emitted("discard-and-restore")).toBeUndefined();
  });

  it("blocks confirmation when a required reference is unavailable", () => {
    const wrapper = mount(RestorePreviewDialog, {
      props: {
        open: true,
        restoreData: {
          versionNumber: 7,
          report: {
            hasConflicts: true,
            conflicts: [
              {
                type: "asset",
                id: "malformed-id",
                contexts: ["Scene background"],
              },
              {
                type: "avatar",
                id: null,
                contexts: ["Dialogue speaker"],
              },
              {
                type: "reference",
                id: "invalid",
                contexts: ["Rich text mention"],
              },
              {
                type: "variable",
                id: "hero.health",
                contexts: ["Dialogue condition"],
              },
            ],
          },
        },
      },
      global: { stubs: dialogStubs },
    });

    expect(wrapper.text()).toContain("Restore is blocked");
    expect(wrapper.text()).toContain("malformed-id");
    expect(wrapper.text()).toContain("ID: invalid");
    expect(wrapper.text()).toContain("Missing avatar");
    expect(wrapper.text()).toContain("Missing reference");
    expect(wrapper.text()).toContain("Missing variable");
    expect(wrapper.text()).not.toContain("Missing entity");
    expect(wrapper.text()).toContain("Restore unavailable");

    const conflictIcons = wrapper.findAll("svg.text-destructive");
    expect(conflictIcons).toHaveLength(4);

    const restoreButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("Restore unavailable"));

    expect(restoreButton?.attributes("disabled")).toBeDefined();
  });

  it("allows a shortcut collision that the restore resolves automatically", async () => {
    const wrapper = mount(RestorePreviewDialog, {
      props: {
        open: true,
        restoreData: {
          versionNumber: 8,
          report: {
            hasConflicts: true,
            shortcutCollision: true,
            resolvedShortcut: "hero-restored",
            conflicts: [],
          },
        },
      },
      global: { stubs: dialogStubs },
    });

    const restoreButton = wrapper
      .findAll("button")
      .find((button) => button.text().trim() === "Restore");

    expect(restoreButton).toBeDefined();
    expect(restoreButton!.attributes("disabled")).toBeUndefined();
    await restoreButton!.trigger("click");
    expect(wrapper.emitted("confirm")).toHaveLength(1);
  });

  it("clears every restore loading state when LiveView replies with an error", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];

    expect(unsavedHandler).toBeDefined();
    expect(restoreHandler).toBeDefined();

    result.previewRestore(11);
    expect(result.loadingAction.value).toBe("restore-11");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "preview_restore",
      { version_number: 11 },
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2]?.({ error: "preview failed" });
    expect(result.loadingAction.value).toBeNull();

    unsavedHandler!({ versionNumber: 11 });
    result.reviewRestore();
    expect(result.loadingAction.value).toBe("review-restore");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "review_restore",
      { version_number: 11 },
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2]?.({ error: "review failed" });
    expect(result.loadingAction.value).toBeNull();

    restoreHandler!({
      versionNumber: 11,
      report: { hasConflicts: false, conflicts: [] },
    });
    result.confirmRestore();
    expect(result.loadingAction.value).toBe("confirm-restore");

    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "confirm_restore",
      { version_number: 11 },
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2]?.({ error: "restore failed" });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showRestoreModal.value).toBe(true);

    app.unmount();
  });

  it("preserves restore modal transitions while clearing their loading states", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];
    const restoredHandler = handlers.find(([event]) => event === "version_restored")?.[1];

    expect(unsavedHandler).toBeDefined();
    expect(restoreHandler).toBeDefined();
    expect(restoredHandler).toBeDefined();

    result.previewRestore(12);
    expect(result.loadingAction.value).toBe("restore-12");
    unsavedHandler!({ versionNumber: 12 });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showUnsavedModal.value).toBe(true);

    result.reviewRestore();
    expect(result.loadingAction.value).toBe("review-restore");
    restoreHandler!({
      versionNumber: 12,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showUnsavedModal.value).toBe(false);
    expect(result.showRestoreModal.value).toBe(true);

    result.confirmRestore();
    expect(result.loadingAction.value).toBe("confirm-restore");
    restoredHandler!({});
    expect(result.loadingAction.value).toBeNull();
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.restoreData.value).toBeNull();

    app.unmount();
  });

  it("clears restore loading state when pushing an event throws", () => {
    const live = createMockLive();
    vi.mocked(live.pushEvent).mockImplementation(() => {
      throw new Error("disconnected");
    });

    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });

    result.previewRestore(13);
    expect(result.loadingAction.value).toBeNull();

    app.unmount();
  });
});
