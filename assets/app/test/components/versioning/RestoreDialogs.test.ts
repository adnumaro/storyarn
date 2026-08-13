import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import CreateVersionDialog from "../../../components/versioning/history/CreateVersionDialog.vue";
import DeleteVersionDialog from "../../../components/versioning/history/DeleteVersionDialog.vue";
import PromoteVersionDialog from "../../../components/versioning/history/PromoteVersionDialog.vue";
import RestorePreviewDialog from "../../../components/versioning/history/RestorePreviewDialog.vue";
import UnsavedChangesDialog from "../../../components/versioning/history/UnsavedChangesDialog.vue";
import VersionHistory from "../../../components/versioning/history/VersionHistory.vue";
import { useVersionHistory } from "../../../components/versioning/history/useVersionHistory";
import { createMockLive, createPromiseMockLive, withSetup } from "../../setup";

const dialogStubs = {
  Dialog: { template: "<div><slot /></div>" },
  DialogContent: { template: "<div><slot /></div>" },
  DialogDescription: { template: "<div><slot /></div>" },
  DialogFooter: { template: "<div><slot /></div>" },
  DialogHeader: { template: "<div><slot /></div>" },
  DialogTitle: { template: "<div><slot /></div>" },
};

type MockLive = ReturnType<typeof createMockLive>;

function eventCalls(live: MockLive, event: string) {
  return vi.mocked(live.pushEvent).mock.calls.filter(([pushedEvent]) => pushedEvent === event);
}

function requestIdFor(live: MockLive, event: string, index = -1): string {
  const requestId = eventCalls(live, event).at(index)?.[1]?.request_id;
  expect(typeof requestId).toBe("string");
  return requestId as string;
}

function createRejectingLive(rejectedEvents: string[]) {
  const error = new Error("socket timeout");
  const rejected = new Set(rejectedEvents);
  const pushEvent = vi.fn((event: unknown, _payload?: unknown, callback?: unknown) => {
    // The callback overload intentionally swallows transport failures in
    // Phoenix. Leaving it pending here makes a missing onError observable as
    // the same stuck loading state without creating an unhandled rejection.
    if (typeof callback === "function") return undefined;
    return rejected.has(String(event)) ? Promise.reject(error) : Promise.resolve({});
  });

  return {
    error,
    live: createPromiseMockLive({}, pushEvent),
    pushEvent,
  };
}

describe("entity restore dialogs", () => {
  it("renders the shared transport failure inside every version action dialog", () => {
    const cases = [
      {
        component: CreateVersionDialog,
        props: { open: true, title: "Milestone", description: "" },
      },
      {
        component: PromoteVersionDialog,
        props: {
          open: true,
          title: "Milestone",
          description: "",
          promoteVersion: { versionNumber: 4 },
        },
      },
      { component: DeleteVersionDialog, props: { open: true } },
      {
        component: UnsavedChangesDialog,
        props: { open: true, versionNumber: 4 },
      },
      {
        component: RestorePreviewDialog,
        props: {
          open: true,
          restoreData: {
            versionNumber: 4,
            report: { hasConflicts: false, conflicts: [] },
          },
        },
      },
    ];

    for (const { component, props } of cases) {
      const wrapper = mount(component, {
        props: { ...props, transportError: true },
        shallow: true,
        global: {
          renderStubDefaultSlot: true,
          stubs: { VersionTransportError: false },
        },
      });

      expect(wrapper.get('[data-testid="version-transport-error"]').attributes("role")).toBe(
        "alert",
      );
      expect(wrapper.get('[data-testid="version-transport-error"]').text()).toBe(
        "The request did not complete. Check your connection and try again.",
      );
      wrapper.unmount();
    }
  });

  it("surfaces a transport failure outside dialogs for list actions", async () => {
    const { live } = createRejectingLive(["load_more_versions"]);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const wrapper = mount(VersionHistory, {
      props: {
        versions: [{ id: 10, versionNumber: 4, title: "Milestone" }],
        namedVersions: [{ id: 10, versionNumber: 4, title: "Milestone" }],
        autoVersions: [],
        hasMore: true,
        canEdit: true,
        canNameVersion: true,
        restoreEnabled: true,
      },
      global: {
        provide: { _live_vue: live },
        stubs: {
          ...dialogStubs,
          CreateVersionDialog: true,
          DeleteVersionDialog: true,
          PromoteVersionDialog: true,
          RestorePreviewDialog: true,
          UnsavedChangesDialog: true,
        },
      },
    });

    const loadMore = wrapper.findAll("button").find((button) => button.text() === "Load more");
    expect(loadMore).toBeDefined();
    await loadMore!.trigger("click");

    await vi.waitFor(() =>
      expect(wrapper.get('[data-testid="version-transport-error"]').text()).toBe(
        "The request did not complete. Check your connection and try again.",
      ),
    );
    expect(loadMore!.attributes("disabled")).toBeUndefined();

    wrapper.unmount();
    warn.mockRestore();
  });

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
      expect.objectContaining({ version_number: 11, request_id: expect.any(String) }),
      expect.any(Function),
    );
    const previewRequestId = requestIdFor(live, "preview_restore");
    vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2]?.({ error: "preview failed" });
    expect(result.loadingAction.value).toBeNull();

    unsavedHandler!({ versionNumber: 11, request_id: previewRequestId });
    result.reviewRestore();
    expect(result.loadingAction.value).toBe("review-restore");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "review_restore",
      expect.objectContaining({ version_number: 11, request_id: expect.any(String) }),
      expect.any(Function),
    );
    const reviewRequestId = requestIdFor(live, "review_restore");
    vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2]?.({ error: "review failed" });
    expect(result.loadingAction.value).toBeNull();

    restoreHandler!({
      versionNumber: 11,
      request_id: reviewRequestId,
      report: { hasConflicts: false, conflicts: [] },
    });
    result.confirmRestore();
    expect(result.loadingAction.value).toBe("confirm-restore");

    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "confirm_restore",
      expect.objectContaining({ version_number: 11, request_id: expect.any(String) }),
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
    unsavedHandler!({
      versionNumber: 12,
      request_id: requestIdFor(live, "preview_restore"),
    });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showUnsavedModal.value).toBe(true);

    result.reviewRestore();
    expect(result.loadingAction.value).toBe("review-restore");
    restoreHandler!({
      versionNumber: 12,
      request_id: requestIdFor(live, "review_restore"),
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showUnsavedModal.value).toBe(false);
    expect(result.showRestoreModal.value).toBe(true);

    result.confirmRestore();
    expect(result.loadingAction.value).toBe("confirm-restore");
    restoredHandler!({ request_id: requestIdFor(live, "confirm_restore") });
    expect(result.loadingAction.value).toBeNull();
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.restoreData.value).toBeNull();

    app.unmount();
  });

  it("accepts restore events without request IDs from an older server", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];
    const restoredHandler = handlers.find(([event]) => event === "version_restored")?.[1];

    result.previewRestore(15);
    unsavedHandler!({ versionNumber: 15 });
    expect(result.showUnsavedModal.value).toBe(true);

    result.reviewRestore();
    restoreHandler!({
      versionNumber: 15,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(true);

    result.confirmRestore();
    restoredHandler!({});
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.restoreData.value).toBeNull();

    app.unmount();
  });

  it("rejects restore events whose request ID is present but malformed", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];
    const restoredHandler = handlers.find(([event]) => event === "version_restored")?.[1];

    result.previewRestore(16);
    unsavedHandler!({ versionNumber: 16, request_id: null });
    restoreHandler!({
      versionNumber: 16,
      request_id: 42,
      report: { hasConflicts: false, conflicts: [] },
    });
    restoredHandler!({ request_id: {} });

    expect(result.showUnsavedModal.value).toBe(false);
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.loadingAction.value).toBe("restore-16");

    restoreHandler!({
      versionNumber: 16,
      request_id: requestIdFor(live, "preview_restore"),
      report: { hasConflicts: false, conflicts: [] },
    });
    result.confirmRestore();
    restoredHandler!({ request_id: {} });

    expect(result.showRestoreModal.value).toBe(true);
    expect(result.loadingAction.value).toBe("confirm-restore");

    app.unmount();
  });

  it("ignores stale callbacks and events across a preview A-B-A race", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];

    expect(unsavedHandler).toBeDefined();
    expect(restoreHandler).toBeDefined();

    result.previewRestore(21);
    const staleCallback = vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2];
    const firstARequestId = requestIdFor(live, "preview_restore");

    result.previewRestore(22);
    const bRequestId = requestIdFor(live, "preview_restore");

    result.previewRestore(21);
    const currentCallback = vi.mocked(live.pushEvent).mock.calls.at(-1)?.[2];
    const currentARequestId = requestIdFor(live, "preview_restore");
    expect(currentARequestId).not.toBe(firstARequestId);
    expect(result.loadingAction.value).toBe("restore-21");

    staleCallback?.({});
    expect(result.loadingAction.value).toBe("restore-21");

    unsavedHandler!({ versionNumber: 21, request_id: firstARequestId });
    restoreHandler!({
      versionNumber: 22,
      request_id: bRequestId,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showUnsavedModal.value).toBe(false);
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.loadingAction.value).toBe("restore-21");

    currentCallback?.({});
    expect(result.loadingAction.value).toBeNull();

    restoreHandler!({
      versionNumber: 21,
      request_id: currentARequestId,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(true);
    expect(result.restoreData.value?.versionNumber).toBe(21);

    app.unmount();
  });

  it("ignores an old review event after previewing the same version again", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];

    result.previewRestore(24);
    unsavedHandler!({
      versionNumber: 24,
      request_id: requestIdFor(live, "preview_restore"),
    });

    result.reviewRestore();
    const oldReviewRequestId = requestIdFor(live, "review_restore");

    result.previewRestore(24);
    const currentPreviewRequestId = requestIdFor(live, "preview_restore");

    restoreHandler!({
      versionNumber: 24,
      request_id: oldReviewRequestId,
      report: { hasConflicts: true, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(false);
    expect(result.loadingAction.value).toBe("restore-24");

    restoreHandler!({
      versionNumber: 24,
      request_id: currentPreviewRequestId,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(true);
    expect(result.restoreData.value?.report.hasConflicts).toBe(false);

    app.unmount();
  });

  it("coalesces duplicate same-version restore actions until their transport settles", () => {
    const live = createMockLive();
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const unsavedHandler = handlers.find(([event]) => event === "show_unsaved_modal")?.[1];
    const restoreHandler = handlers.find(([event]) => event === "show_restore_modal")?.[1];
    result.previewRestore(23);
    result.previewRestore(23);
    expect(eventCalls(live, "preview_restore")).toHaveLength(1);

    eventCalls(live, "preview_restore")[0]?.[2]?.({});
    result.previewRestore(23);
    expect(eventCalls(live, "preview_restore")).toHaveLength(2);

    unsavedHandler!({
      versionNumber: 23,
      request_id: requestIdFor(live, "preview_restore"),
    });
    result.reviewRestore();
    result.reviewRestore();
    expect(eventCalls(live, "review_restore")).toHaveLength(1);

    eventCalls(live, "review_restore")[0]?.[2]?.({});
    result.reviewRestore();
    expect(eventCalls(live, "review_restore")).toHaveLength(2);

    restoreHandler!({
      versionNumber: 23,
      request_id: requestIdFor(live, "review_restore"),
      report: { hasConflicts: false, conflicts: [] },
    });
    result.confirmRestore();
    result.confirmRestore();
    expect(eventCalls(live, "confirm_restore")).toHaveLength(1);

    eventCalls(live, "confirm_restore")[0]?.[2]?.({});
    result.confirmRestore();
    expect(eventCalls(live, "confirm_restore")).toHaveLength(2);

    app.unmount();
  });

  it("clears restore loading state when pushing an event throws", () => {
    const live = createMockLive();
    vi.mocked(live.pushEvent).mockImplementation(() => {
      throw new Error("disconnected");
    });

    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const restoreHandler = vi
      .mocked(live.handleEvent)
      .mock.calls.find(([event]) => event === "show_restore_modal")?.[1];

    result.previewRestore(13);
    expect(result.loadingAction.value).toBeNull();

    result.previewRestore(13);
    expect(live.pushEvent).toHaveBeenCalledTimes(2);

    restoreHandler!({
      versionNumber: 13,
      request_id: requestIdFor(live, "preview_restore"),
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(false);

    app.unmount();
  });

  it("clears and invalidates a restore after an asynchronous Phoenix rejection", async () => {
    const error = new Error("socket timeout");
    const live = {
      ...createMockLive(),
      liveSocket: {},
      pushEvent: vi.fn(() => Promise.reject(error)),
    } as unknown as ReturnType<typeof createMockLive>;
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });
    const restoreHandler = vi
      .mocked(live.handleEvent)
      .mock.calls.find(([event]) => event === "show_restore_modal")?.[1];

    result.previewRestore(14);
    expect(result.loadingAction.value).toBe("restore-14");
    const requestId = requestIdFor(live, "preview_restore");

    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());

    restoreHandler!({
      versionNumber: 14,
      request_id: requestId,
      report: { hasConflicts: false, conflicts: [] },
    });
    expect(result.showRestoreModal.value).toBe(false);

    app.unmount();
    warn.mockRestore();
  });

  it("clears non-restore loading states after asynchronous Phoenix rejections", async () => {
    const { live } = createRejectingLive([
      "create_version",
      "promote_version",
      "delete_version",
      "load_more_versions",
    ]);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });

    result.openCreateModal();
    result.createTitle.value = "Milestone";
    result.submitCreate();
    expect(result.loadingAction.value).toBe("create");
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);
    expect(result.showCreateModal.value).toBe(true);
    expect(result.createTitle.value).toBe("Milestone");
    result.submitCreate();
    expect(result.transportError.value).toBe(false);
    await vi.waitFor(() => expect(eventCalls(live, "create_version")).toHaveLength(2));
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    result.openPromoteModal({ versionNumber: 4, changeSummary: "Auto-save" });
    result.submitPromote();
    expect(result.transportError.value).toBe(false);
    expect(result.loadingAction.value).toBe("promote");
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);
    expect(result.showPromoteModal.value).toBe(true);
    expect(result.promoteVersion.value?.versionNumber).toBe(4);
    result.submitPromote();
    expect(result.transportError.value).toBe(false);
    await vi.waitFor(() => expect(eventCalls(live, "promote_version")).toHaveLength(2));
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    result.openDeleteModal(4);
    result.confirmDelete();
    expect(result.transportError.value).toBe(false);
    expect(result.loadingAction.value).toBe("delete");
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);
    expect(result.showDeleteModal.value).toBe(true);
    expect(result.deleteVersionNumber.value).toBe(4);
    result.confirmDelete();
    expect(result.transportError.value).toBe(false);
    await vi.waitFor(() => expect(eventCalls(live, "delete_version")).toHaveLength(2));
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    result.loadMore();
    expect(result.transportError.value).toBe(false);
    expect(result.loadingAction.value).toBe("load-more");
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);
    result.loadMore();
    expect(result.transportError.value).toBe(false);
    await vi.waitFor(() => expect(eventCalls(live, "load_more_versions")).toHaveLength(2));
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    result.openCreateModal();
    expect(result.transportError.value).toBe(false);

    app.unmount();
    warn.mockRestore();
  });

  it("clears every restore loading state through the real Promise rejection path", async () => {
    const { live } = createRejectingLive(["preview_restore"]);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { result, app } = withSetup(() => useVersionHistory(() => true), { live });

    result.previewRestore(31);
    expect(result.loadingAction.value).toBe("restore-31");
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    // The failed request is invalidated, so the same action can be retried.
    result.previewRestore(31);
    expect(result.transportError.value).toBe(false);
    await vi.waitFor(() => expect(eventCalls(live, "preview_restore")).toHaveLength(2));
    await vi.waitFor(() => expect(result.loadingAction.value).toBeNull());
    expect(result.transportError.value).toBe(true);

    app.unmount();
    warn.mockRestore();
  });

  it("preserves review and confirmation context when their Promise pushes reject", async () => {
    const reviewTransport = createRejectingLive(["review_restore"]);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const reviewSetup = withSetup(() => useVersionHistory(() => true), {
      live: reviewTransport.live,
    });
    const unsavedHandler = vi
      .mocked(reviewTransport.live.handleEvent)
      .mock.calls.find(([event]) => event === "show_unsaved_modal")?.[1];

    reviewSetup.result.previewRestore(32);
    await vi.waitFor(() => expect(reviewSetup.result.loadingAction.value).toBeNull());
    unsavedHandler!({
      versionNumber: 32,
      request_id: requestIdFor(reviewTransport.live, "preview_restore"),
    });
    reviewSetup.result.reviewRestore();
    expect(reviewSetup.result.loadingAction.value).toBe("review-restore");
    await vi.waitFor(() => expect(reviewSetup.result.loadingAction.value).toBeNull());
    expect(reviewSetup.result.transportError.value).toBe(true);
    expect(reviewSetup.result.showUnsavedModal.value).toBe(true);
    expect(reviewSetup.result.unsavedVersionNumber.value).toBe(32);
    reviewSetup.result.reviewRestore();
    expect(reviewSetup.result.transportError.value).toBe(false);
    await vi.waitFor(() =>
      expect(eventCalls(reviewTransport.live, "review_restore")).toHaveLength(2),
    );
    await vi.waitFor(() => expect(reviewSetup.result.loadingAction.value).toBeNull());
    expect(reviewSetup.result.transportError.value).toBe(true);
    reviewSetup.app.unmount();

    const confirmTransport = createRejectingLive(["confirm_restore"]);
    const confirmSetup = withSetup(() => useVersionHistory(() => true), {
      live: confirmTransport.live,
    });
    const restoreHandler = vi
      .mocked(confirmTransport.live.handleEvent)
      .mock.calls.find(([event]) => event === "show_restore_modal")?.[1];

    confirmSetup.result.previewRestore(33);
    await vi.waitFor(() => expect(confirmSetup.result.loadingAction.value).toBeNull());
    restoreHandler!({
      versionNumber: 33,
      request_id: requestIdFor(confirmTransport.live, "preview_restore"),
      report: { hasConflicts: false, conflicts: [] },
    });
    confirmSetup.result.confirmRestore();
    expect(confirmSetup.result.loadingAction.value).toBe("confirm-restore");
    await vi.waitFor(() => expect(confirmSetup.result.loadingAction.value).toBeNull());
    expect(confirmSetup.result.transportError.value).toBe(true);
    expect(confirmSetup.result.showRestoreModal.value).toBe(true);
    expect(confirmSetup.result.restoreData.value?.versionNumber).toBe(33);
    confirmSetup.result.confirmRestore();
    expect(confirmSetup.result.transportError.value).toBe(false);
    await vi.waitFor(() =>
      expect(eventCalls(confirmTransport.live, "confirm_restore")).toHaveLength(2),
    );
    await vi.waitFor(() => expect(confirmSetup.result.loadingAction.value).toBeNull());
    expect(confirmSetup.result.transportError.value).toBe(true);

    confirmSetup.app.unmount();
    warn.mockRestore();
  });
});
