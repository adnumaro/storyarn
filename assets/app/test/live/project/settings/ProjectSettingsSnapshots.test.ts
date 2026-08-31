import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import ProjectSettingsSnapshots from "../../../../live/project/settings/ProjectSettingsSnapshots.vue";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import type { WorkspaceStorageUsage } from "../../../../shared/utils/storage-accounting";
import { createMockLive, createPromiseMockLive, setTestLocale } from "../../../setup";

const storageUsage = {
  currentAssetsBytes: String(512 * 1024),
  assetTrashBytes: String(128 * 1024),
  fullSnapshotsBytes: String(256 * 1024),
  activeReservationsBytes: String(64 * 1024),
  totalAccountedBytes: String(960 * 1024),
  limitBytes: String(4 * 1024 * 1024),
  remainingBytes: String(3136 * 1024),
  limitKind: "limited" as const,
};

interface SnapshotFixture {
  id: number;
  mode: "full" | null;
  title: string;
  description: string;
  versionNumber: number;
  insertedAt: string;
  entityCounts: Record<string, number>;
  createdByEmail: string;
  lifecycleStatus:
    | "pending"
    | "building"
    | "verifying"
    | "ready"
    | "failed"
    | "cancelled"
    | "deleting"
    | null;
  integrityStatus: "unknown" | "verified" | "missing" | "corrupt" | "incomplete" | null;
  accountedSizeBytes: string | null;
  archiveSizeBytes: string | null;
  sidecarSizeBytes: string | null;
  assetCount: number | null;
  blobCount: number | null;
  activeReservationBytes: string;
  exportReservationBytes: string;
  accountingVersion: number | null;
  accountingMeasuredAt: string | null;
  plannedSizeBytes: string | null;
  progressPhase: string | null;
  progressBytes: string;
  progressTotalBytes: string | null;
  buildJobState: string | null;
  buildAttempt: number;
  buildMaxAttempts: number | null;
  retrying: boolean;
  nextRetryAt: string | null;
  retryErrorCode: string | null;
  failureCode: string | null;
  failureMessage: string | null;
  capturedAt: string | null;
  cancelRequestedAt: string | null;
  canCancel: boolean;
  canDelete: boolean;
  deleteStatus: "ready" | "download_lease" | "active_operation" | "restore_operation" | null;
  canRestore: boolean;
  restoreOperation: {
    id: number;
    status: "queued" | "running" | "retrying" | "completed" | "failed";
    phase: string;
    attempt: number;
    requestedAt: string | null;
    stateUpdatedAt: string | null;
    completedAt: string | null;
    failedAt: string | null;
    failureCode: string | null;
    failureMessage: string | null;
  } | null;
  downloadUrl: string | null;
}

const measuredSnapshot: SnapshotFixture = {
  id: 21,
  mode: "full",
  title: "Playtest checkpoint",
  description: "Ready for QA",
  versionNumber: 2,
  insertedAt: "2026-07-17T10:00:00Z",
  entityCounts: { sheets: 2 },
  createdByEmail: "owner@example.com",
  lifecycleStatus: "ready",
  integrityStatus: "verified",
  accountedSizeBytes: String(6 * 1024),
  archiveSizeBytes: String(4 * 1024),
  sidecarSizeBytes: String(2 * 1024),
  assetCount: 2,
  blobCount: 1,
  activeReservationBytes: "768",
  exportReservationBytes: "256",
  accountingVersion: 1,
  accountingMeasuredAt: "2026-07-17T10:00:00Z",
  plannedSizeBytes: String(6 * 1024),
  progressPhase: "complete",
  progressBytes: String(6 * 1024),
  progressTotalBytes: String(6 * 1024),
  buildJobState: "completed",
  buildAttempt: 1,
  buildMaxAttempts: 3,
  retrying: false,
  nextRetryAt: null,
  retryErrorCode: null,
  failureCode: null,
  failureMessage: null,
  capturedAt: "2026-07-17T09:59:00Z",
  cancelRequestedAt: null,
  canCancel: false,
  canDelete: false,
  deleteStatus: "active_operation",
  canRestore: true,
  restoreOperation: null,
  downloadUrl: "/workspaces/alpha/projects/veilbreak/snapshots/21/download",
};

function mountSnapshots(
  snapshot: SnapshotFixture = measuredSnapshot,
  workspaceStorage: WorkspaceStorageUsage = storageUsage,
  live: LiveInterface = createMockLive(),
) {
  const wrapper = mount(ProjectSettingsSnapshots, {
    props: {
      snapshots: [snapshot],
      storageUsage: workspaceStorage,
      snapshotLimit: { used: 2, limit: 10 },
    },
    global: {
      provide: { _live_vue: live },
    },
  });

  return wrapper;
}

afterEach(() => setTestLocale("en"));

describe("ProjectSettingsSnapshots storage accounting", () => {
  it("renders plan-counted workspace usage and its mutually exclusive categories", () => {
    const wrapper = mountSnapshots();
    const text = wrapper.text();

    expect(text).toContain("Storage counted toward your plan");
    expect(text).toContain("960 KB");
    expect(text).toContain("23.44%");
    expect(text).toContain("512 KB");
    expect(text).toContain("Recoverable asset trash");
    expect(text).toContain("128 KB");
    expect(text).toContain("256 KB");
    expect(text).toContain("64 KB");
    expect(text).toContain("3.1 MB");
    expect(text).toContain("Active reservations");
    wrapper.get('[data-testid="workspace-storage-progress"]');
  });

  it("renders canonical snapshot size, exact percentage, breakdown, inventory, and states", () => {
    const wrapper = mountSnapshots();
    const text = wrapper.text();

    expect(text).toContain("6 KB");
    expect(text).toContain("0.15%");
    expect(text).toContain("ZIP archive");
    expect(text).toContain("4 KB");
    expect(text).toContain("Manifest sidecar");
    expect(text).toContain("2 KB");
    expect(text).toContain("Logical assets: 2 · Unique blobs: 1");
    expect(text).toContain("Accounting v1 measured");
    expect(text).toContain("Active work reservation: 768 B");
    expect(text).toContain("ZIP export reservation: 256 B");
    expect(text).toContain("2 sheets");

    const card = wrapper.get('[data-testid="snapshot-card-21"]');
    expect(card.attributes("id")).toBe("snapshot-21");
    expect(card.classes()).toContain("target:ring-2");
    expect(card.text()).toContain("Playtest checkpoint");
    expect(card.text()).not.toContain("v2");
    expect(card.find('[aria-label="Snapshot mode: Full"]').exists()).toBe(false);
    expect(card.find('[aria-label="Snapshot state: Ready"]').exists()).toBe(false);
    expect(card.find('[aria-label="Snapshot integrity: Verified"]').exists()).toBe(false);
    expect(wrapper.find('[aria-label="Snapshot storage: 6 KB"]').exists()).toBe(true);

    expect(wrapper.get("form").element).toBeTruthy();
    expect(wrapper.get('[data-testid="snapshot-slot-usage"]').text()).toContain(
      "Snapshot slots: 2 of 10 used",
    );
    expect(wrapper.get('button[type="submit"]').text()).toContain("Create snapshot");
    const download = wrapper.get('[data-testid="download-snapshot-21"]');
    expect(download.attributes("href")).toBe(
      "/workspaces/alpha/projects/veilbreak/snapshots/21/download",
    );
    expect(download.attributes("download")).toBeUndefined();
    expect(download.attributes("target")).toBeUndefined();
    expect(download.attributes("rel")).toBeUndefined();
    expect(download.attributes("referrerpolicy")).toBe("no-referrer");
    expect(download.attributes("data-live-link-exempt")).toBe("download");
    expect(download.text()).toContain("Download ZIP");
  });

  it("renders export reservation bytes independently from other active work", () => {
    const wrapper = mountSnapshots({
      ...measuredSnapshot,
      activeReservationBytes: "0",
      exportReservationBytes: "256",
    });

    expect(wrapper.text()).toContain("ZIP export reservation: 256 B");
    expect(wrapper.text()).not.toContain("Active work reservation");
  });

  it("keeps deletion visible and explains a protected zero-byte download lease", () => {
    const wrapper = mountSnapshots({
      ...measuredSnapshot,
      activeReservationBytes: "0",
      exportReservationBytes: "0",
      canDelete: false,
      deleteStatus: "download_lease",
    });

    expect(wrapper.get('[data-testid="delete-download-lease-21"]').text()).toContain(
      "Download protection is active.",
    );
    const deleteButton = wrapper.get('[data-testid="delete-snapshot-21"]');
    expect(deleteButton.attributes("disabled")).toBeDefined();
    expect(deleteButton.attributes("aria-describedby")).toBe("delete-snapshot-reason-21");
  });

  it("renders a pending canonical row before accounting measurements are available", () => {
    const wrapper = mountSnapshots({
      ...measuredSnapshot,
      lifecycleStatus: "pending",
      integrityStatus: "unknown",
      accountedSizeBytes: null,
      archiveSizeBytes: null,
      sidecarSizeBytes: null,
      assetCount: 2,
      blobCount: 1,
      activeReservationBytes: String(6 * 1024),
      exportReservationBytes: "0",
      accountingVersion: null,
      accountingMeasuredAt: null,
      progressPhase: "pending",
      progressBytes: "0",
      progressTotalBytes: String(6 * 1024),
      buildJobState: "available",
      buildAttempt: 0,
      buildMaxAttempts: 3,
      canCancel: true,
      deleteStatus: null,
      downloadUrl: null,
    });

    const text = wrapper.text();
    const card = wrapper.get('[data-testid="snapshot-card-21"]');
    expect(card.find('[aria-label="Snapshot mode: Full"]').exists()).toBe(false);
    expect(card.find('[aria-label="Snapshot state: Pending"]').exists()).toBe(false);
    expect(card.find('[aria-label="Snapshot integrity: Integrity unknown"]').exists()).toBe(false);
    expect(text).toContain("Waiting for attempt 1 of 3");
    expect(text).toContain("Reserved storage: 6 KB");
    expect(text).toContain("Planned snapshot: 6 KB");
    expect(wrapper.get("form").element).toBeTruthy();
    expect(wrapper.findAll("button").some((button) => button.text().includes("Cancel build"))).toBe(
      true,
    );
    expect(wrapper.find('a[href*="/snapshots/"]').exists()).toBe(false);
  });

  it("shows durable retry attempt, schedule, and a safe generic error", () => {
    const wrapper = mountSnapshots({
      ...measuredSnapshot,
      lifecycleStatus: "pending",
      integrityStatus: "unknown",
      accountedSizeBytes: null,
      archiveSizeBytes: null,
      sidecarSizeBytes: null,
      progressPhase: "pending",
      progressBytes: "0",
      progressTotalBytes: null,
      buildJobState: "retryable",
      buildAttempt: 2,
      buildMaxAttempts: 3,
      retrying: true,
      nextRetryAt: "2000-01-01T10:00:00Z",
      retryErrorCode: "build_failed",
      canCancel: true,
      deleteStatus: null,
      downloadUrl: null,
    });

    expect(wrapper.find('[aria-label="Snapshot state: Retrying"]').exists()).toBe(true);
    expect(wrapper.text()).toContain("Preparing a safe retry");
    expect(wrapper.get('[data-testid="snapshot-attempt-21"]').text()).toBe("Attempt 2 of 3");
    expect(wrapper.get('[data-testid="snapshot-next-retry-21"]').text()).toContain(
      "Retry due since",
    );
    expect(wrapper.get('[data-testid="snapshot-next-retry-21"]').text()).toContain(
      "waiting for a worker",
    );

    const safeError = wrapper.get('[data-testid="snapshot-retry-error-21"]');
    expect(safeError.attributes("data-error-code")).toBe("build_failed");
    expect(safeError.text()).toContain("Storyarn will retry automatically");
    expect(wrapper.text()).not.toContain("stacktrace");
  });

  it("does not render retry state or controls after the snapshot is terminal", () => {
    const wrapper = mountSnapshots({
      ...measuredSnapshot,
      lifecycleStatus: "failed",
      integrityStatus: "incomplete",
      progressPhase: "failed",
      buildJobState: "discarded",
      buildAttempt: 3,
      buildMaxAttempts: 3,
      retrying: false,
      nextRetryAt: null,
      retryErrorCode: null,
      failureCode: "build_failed",
      failureMessage: "The snapshot could not be created.",
      canCancel: false,
      canDelete: true,
      canRestore: false,
      downloadUrl: null,
    });

    expect(wrapper.find('[aria-label="Snapshot state: Failed"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="snapshot-attempt-21"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="snapshot-next-retry-21"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="snapshot-retry-error-21"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Storyarn will retry automatically");
    expect(wrapper.text()).toContain("The snapshot could not be created.");
  });
  it.each([
    { limitKind: "unknown" as const, limitBytes: null, remainingBytes: null },
    { limitKind: "unlimited" as const, limitBytes: null, remainingBytes: null },
    { limitKind: "limited" as const, limitBytes: "0", remainingBytes: "0" },
  ])("omits a determinate storage progressbar for $limitKind capacity", (limitState) => {
    const wrapper = mountSnapshots(measuredSnapshot, {
      ...storageUsage,
      ...limitState,
      totalAccountedBytes: limitState.limitBytes === "0" ? "0" : storageUsage.totalAccountedBytes,
    });

    expect(wrapper.find('[data-testid="workspace-storage-progress"]').exists()).toBe(false);
  });

  it("formats snapshot dates with the active locale", () => {
    setTestLocale("es");
    const wrapper = mountSnapshots();

    expect(wrapper.text()).toContain("jul");
    const card = wrapper.get('[data-testid="snapshot-card-21"]');
    expect(card.find('[aria-label="Modo de la snapshot: Completa"]').exists()).toBe(false);
    expect(card.find('[aria-label="Integridad de la snapshot: Verificada"]').exists()).toBe(false);
    expect(wrapper.text()).toContain("2 fichas");
  });

  it("shows positive storage below one basis point as less than 0.01%", () => {
    const wrapper = mountSnapshots(measuredSnapshot, {
      ...storageUsage,
      currentAssetsBytes: "1",
      fullSnapshotsBytes: "0",
      activeReservationsBytes: "0",
      totalAccountedBytes: "1",
      limitBytes: "20000",
      remainingBytes: "19999",
    });

    expect(wrapper.text()).toContain("<0.01%");
  });

  it("disables creation when the visible snapshot slot limit is reached", () => {
    const wrapper = mount(ProjectSettingsSnapshots, {
      props: {
        snapshots: [measuredSnapshot],
        storageUsage,
        snapshotLimit: { used: 10, limit: 10 },
      },
    });

    expect(wrapper.get('[data-testid="snapshot-slot-usage"]').text()).toContain(
      "Snapshot slots: 10 of 10 used",
    );
    expect(wrapper.get('button[type="submit"]').attributes("disabled")).toBeDefined();
  });

  it("requires confirmation before requesting durable snapshot deletion", async () => {
    const live = createMockLive();
    const wrapper = mountSnapshots(
      { ...measuredSnapshot, canDelete: true, deleteStatus: "ready" },
      storageUsage,
      live,
    );

    await wrapper.get('[data-testid="delete-snapshot-21"]').trigger("click");

    const confirmation = wrapper.findComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalled();

    confirmation.vm.$emit("confirm");

    expect(live.pushEvent).toHaveBeenCalledWith("delete_snapshot", { id: 21 }, undefined);
  });

  it("requires destructive confirmation and sends a stable UUID for project restore", async () => {
    const live = createMockLive();
    const wrapper = mountSnapshots(measuredSnapshot, storageUsage, live);

    await wrapper.get('[data-testid="restore-snapshot-21"]').trigger("click");

    const dialogs = wrapper.findAllComponents(ConfirmDialog);
    const confirmation = dialogs.find((dialog) => dialog.props("open"));
    expect(confirmation).toBeDefined();
    expect(confirmation?.props("variant")).toBe("destructive");
    expect(confirmation?.props("description")).toContain(
      "Current sheets, flows, scenes, and assets move to recoverable trash",
    );
    expect(confirmation?.props("description")).toContain("remains editable");
    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "restore_snapshot",
      expect.anything(),
      expect.anything(),
    );

    confirmation?.vm.$emit("confirm");
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "restore_snapshot",
      {
        id: 21,
        idempotency_key: expect.stringMatching(
          /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
        ),
      },
      undefined,
    );

    const restoreButton = wrapper.get('[data-testid="restore-snapshot-21"]');
    expect(restoreButton.attributes("disabled")).toBeDefined();
    expect(restoreButton.text()).toContain("Starting restore");
    expect(wrapper.get('[data-testid="delete-snapshot-21"]').attributes("disabled")).toBeDefined();
  });

  it("renders durable restore phase and disables restore/delete while it is active", () => {
    const wrapper = mount(ProjectSettingsSnapshots, {
      props: {
        snapshots: [
          {
            ...measuredSnapshot,
            canRestore: false,
            canDelete: false,
            deleteStatus: "restore_operation",
            restoreOperation: {
              id: 8,
              status: "running",
              phase: "materializing",
              attempt: 1,
              requestedAt: "2026-07-17T10:00:00Z",
              stateUpdatedAt: "2026-07-17T10:01:00Z",
              completedAt: null,
              failedAt: null,
              failureCode: null,
              failureMessage: null,
            },
          },
        ],
        storageUsage,
        snapshotLimit: { used: 2, limit: 10 },
        restoreOperationActive: true,
      },
    });

    const operation = wrapper.get('[data-testid="snapshot-restore-operation-21"]');
    expect(operation.text()).toContain("Project restore");
    expect(operation.text()).toContain("Running");
    expect(operation.text()).toContain("Restoring project content");
    expect(operation.text()).toContain("continues safely");
    expect(wrapper.find('[data-testid="restore-snapshot-21"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="delete-snapshot-21"]').attributes("disabled")).toBeDefined();
    expect(wrapper.get('[data-testid="delete-restore-operation-21"]').text()).toContain(
      "A project restore is active",
    );
  });

  it("surfaces a transport failure and safely re-enables the restore action", async () => {
    const transport = vi.fn((..._args: unknown[]) => Promise.reject(new Error("disconnected")));
    const live = createPromiseMockLive({}, transport);
    const wrapper = mountSnapshots(measuredSnapshot, storageUsage, live);

    await wrapper.get('[data-testid="restore-snapshot-21"]').trigger("click");
    const confirmation = wrapper
      .findAllComponents(ConfirmDialog)
      .find((dialog) => dialog.props("open"));
    confirmation?.vm.$emit("confirm");
    await flushPromises();

    expect(wrapper.get('[data-testid="snapshot-restore-error"]').text()).toContain(
      "connection was interrupted",
    );
    expect(
      wrapper.get('[data-testid="restore-snapshot-21"]').attributes("disabled"),
    ).toBeUndefined();

    const firstRequest = transport.mock.calls.find((call) => call[0] === "restore_snapshot")?.[1];
    await wrapper.get('[data-testid="restore-snapshot-21"]').trigger("click");
    wrapper
      .findAllComponents(ConfirmDialog)
      .find((dialog) => dialog.props("open"))
      ?.vm.$emit("confirm");
    await flushPromises();

    const restoreRequests = transport.mock.calls.filter((call) => call[0] === "restore_snapshot");
    expect(restoreRequests).toHaveLength(2);
    expect(restoreRequests[1]?.[1]).toEqual(firstRequest);
  });

  it("explains canonical ownership drift from snapshot request and restore events", async () => {
    const live = createMockLive();
    const wrapper = mountSnapshots(measuredSnapshot, storageUsage, live);
    const handlers = vi.mocked(live.handleEvent).mock.calls;
    const requestFailed = handlers.find(([event]) => event === "snapshot_request_failed")?.[1];
    const restoreFailed = handlers.find(([event]) => event === "snapshot_restore_failed")?.[1];

    expect(requestFailed).toBeDefined();
    expect(restoreFailed).toBeDefined();

    requestFailed?.({ reason: "ownership_invariant_violation" });
    restoreFailed?.({ snapshotId: 21, reason: "ownership_invariant_violation" });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-testid="snapshot-request-error"]').text()).toContain(
      "project ownership is inconsistent",
    );
    expect(wrapper.get('[data-testid="snapshot-restore-error"]').text()).toContain(
      "project ownership is inconsistent",
    );

    requestFailed?.({ reason: "unauthorized" });
    restoreFailed?.({ snapshotId: 21, reason: "unauthorized" });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-testid="snapshot-request-error"]').text()).toContain(
      "no longer have permission",
    );
    expect(wrapper.get('[data-testid="snapshot-restore-error"]').text()).toContain(
      "no longer have permission",
    );
  });
});
