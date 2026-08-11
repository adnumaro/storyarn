import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vitest";
import ProjectSettingsSnapshots from "../../../../live/project/settings/ProjectSettingsSnapshots.vue";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import type { WorkspaceStorageUsage } from "../../../../shared/utils/storage-accounting";
import { createMockLive, setTestLocale } from "../../../setup";

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
  title: string;
  description: string;
  versionNumber: number;
  insertedAt: string;
  entityCounts: Record<string, number>;
  createdByEmail: string;
  mode: "full" | null;
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
  failureCode: string | null;
  failureMessage: string | null;
  capturedAt: string | null;
  cancelRequestedAt: string | null;
  canCancel: boolean;
  canDelete: boolean;
  deleteStatus: "ready" | "download_lease" | "active_operation" | null;
  downloadUrl: string | null;
}

const measuredSnapshot: SnapshotFixture = {
  id: 21,
  title: "Playtest checkpoint",
  description: "Ready for QA",
  versionNumber: 2,
  insertedAt: "2026-07-17T10:00:00Z",
  entityCounts: { sheets: 2 },
  createdByEmail: "owner@example.com",
  mode: "full",
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
  failureCode: null,
  failureMessage: null,
  capturedAt: "2026-07-17T09:59:00Z",
  cancelRequestedAt: null,
  canCancel: false,
  canDelete: false,
  deleteStatus: "active_operation",
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

    expect(text).toContain("Full");
    expect(text).toContain("Ready");
    expect(text).toContain("Verified");
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

    const modeBadge = wrapper.find('[aria-label="Snapshot mode: Full"]');
    expect(modeBadge.exists()).toBe(true);
    expect(wrapper.find('[aria-label="Snapshot state: Ready"]').exists()).toBe(true);
    expect(wrapper.find('[aria-label="Snapshot integrity: Verified"]').exists()).toBe(true);
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
      mode: "full",
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
      canCancel: true,
      deleteStatus: null,
      downloadUrl: null,
    });

    const text = wrapper.text();
    expect(text).toContain("Full");
    expect(text).toContain("Pending");
    expect(text).toContain("Integrity unknown");
    expect(text).toContain("Reserved storage: 6 KB");
    expect(text).toContain("Planned snapshot: 6 KB");
    expect(wrapper.get("form").element).toBeTruthy();
    expect(wrapper.findAll("button").some((button) => button.text().includes("Cancel build"))).toBe(
      true,
    );
    expect(wrapper.find('a[href*="/snapshots/"]').exists()).toBe(false);
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
    expect(wrapper.text()).toContain("Completa");
    expect(wrapper.text()).toContain("Verificada");
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
});
