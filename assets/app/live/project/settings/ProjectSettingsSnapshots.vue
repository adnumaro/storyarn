<script setup lang="ts">
import {
  Archive,
  Clock3,
  Database,
  Download,
  FileJson2,
  HardDrive,
  Image,
  LoaderCircle,
  Plus,
  RotateCcw,
  ShieldCheck,
  Trash2,
  X,
} from "@lucide/vue";
import { computed, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Progress } from "@components/ui/progress";
import { Separator } from "@components/ui/separator";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive";
import {
  formatBasisPoints,
  formatBytes,
  positiveByteCount,
  storagePercentage,
  type ByteCount,
  type WorkspaceStorageUsage,
} from "@shared/utils/storage-accounting";

type SnapshotMode = "full";
type SnapshotLifecycle =
  | "pending"
  | "building"
  | "verifying"
  | "ready"
  | "failed"
  | "cancelled"
  | "deleting";
type SnapshotIntegrity = "unknown" | "verified" | "missing" | "corrupt" | "incomplete";
type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

interface Snapshot {
  id: number;
  title?: string;
  description?: string;
  versionNumber: number;
  insertedAt: string;
  entityCounts?: Record<string, number>;
  createdByEmail?: string;
  mode: SnapshotMode | null;
  lifecycleStatus: SnapshotLifecycle | null;
  integrityStatus: SnapshotIntegrity | null;
  accountedSizeBytes: ByteCount | null;
  archiveSizeBytes: ByteCount | null;
  sidecarSizeBytes: ByteCount | null;
  assetCount: number | null;
  blobCount: number | null;
  activeReservationBytes: ByteCount;
  exportReservationBytes: ByteCount;
  accountingVersion: number | null;
  accountingMeasuredAt: string | null;
  plannedSizeBytes: ByteCount | null;
  progressPhase: string | null;
  progressBytes: ByteCount;
  progressTotalBytes: ByteCount | null;
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
  restoreOperation: RestoreOperation | null;
  downloadUrl: string | null;
}

type RestoreStatus = "queued" | "running" | "retrying" | "completed" | "failed";

interface RestoreOperation {
  id: number;
  status: RestoreStatus;
  phase: string;
  attempt: number;
  requestedAt: string | null;
  stateUpdatedAt: string | null;
  completedAt: string | null;
  failedAt: string | null;
  failureCode: string | null;
  failureMessage: string | null;
}

interface SnapshotLimit {
  used: number;
  limit: number | null;
}

const {
  snapshots = [],
  storageUsage,
  snapshotLimit,
  restoreOperationActive = false,
} = defineProps<{
  snapshots?: Snapshot[];
  storageUsage: WorkspaceStorageUsage;
  snapshotLimit: SnapshotLimit;
  restoreOperationActive?: boolean;
}>();

const { locale, t } = useI18n();
const live = useLive();
const title = ref("");
const description = ref("");
const requestIdempotencyKey = ref(newIdempotencyKey());
const isSubmitting = ref(false);
const requestError = ref<string | null>(null);
const cancellingSnapshotIds = ref(new Set<number>());
const deletingSnapshotIds = ref(new Set<number>());
const snapshotToDelete = ref<Snapshot | null>(null);
const deleteError = ref<string | null>(null);
const restoringSnapshotIds = ref(new Set<number>());
const snapshotToRestore = ref<Snapshot | null>(null);
const restoreRequestError = ref<string | null>(null);
const requestIdempotencyKeyForRestore = ref(newIdempotencyKey());
const deleteDialogOpen = computed({
  get: () => snapshotToDelete.value !== null,
  set: (open: boolean) => {
    if (!open) snapshotToDelete.value = null;
  },
});
const restoreDialogOpen = computed({
  get: () => snapshotToRestore.value !== null,
  set: (open: boolean) => {
    if (!open) snapshotToRestore.value = null;
  },
});
const restoreBusy = computed(() => restoreOperationActive || restoringSnapshotIds.value.size > 0);
const snapshotLimitReached = computed(
  () => snapshotLimit.limit !== null && snapshotLimit.used >= snapshotLimit.limit,
);

const snapshotLimitLabel = computed(() => {
  if (snapshotLimit.limit === null) {
    return t("project_settings.snapshots.create.slot_usage_unknown", {
      used: formatCount(snapshotLimit.used),
    });
  }

  return t("project_settings.snapshots.create.slot_usage", {
    used: formatCount(snapshotLimit.used),
    limit: formatCount(snapshotLimit.limit),
  });
});

const serverEventRefs = [
  live.handleEvent("snapshot_request_accepted", () => {
    title.value = "";
    description.value = "";
    requestIdempotencyKey.value = newIdempotencyKey();
    requestError.value = null;
    isSubmitting.value = false;
  }),
  live.handleEvent("snapshot_request_failed", (payload) => {
    requestError.value = snapshotRequestError(payload);
    isSubmitting.value = false;
  }),
  live.handleEvent("snapshot_cancel_accepted", (payload) => {
    clearCancellingSnapshot(payload.snapshotId);
  }),
  live.handleEvent("snapshot_cancel_failed", (payload) => {
    clearCancellingSnapshot(payload.snapshotId);
    requestError.value =
      typeof payload.message === "string"
        ? payload.message
        : t("project_settings.snapshots.create.cancel_failed");
  }),
  live.handleEvent("snapshot_delete_accepted", (payload) => {
    clearDeletingSnapshot(payload.snapshotId);
    deleteError.value = null;
  }),
  live.handleEvent("snapshot_delete_failed", (payload) => {
    clearDeletingSnapshot(payload.snapshotId);
    if (payload.reason === "restore_operation") {
      deleteError.value = t("project_settings.snapshots.delete.restore_operation");
    } else {
      deleteError.value =
        typeof payload.message === "string"
          ? payload.message
          : t("project_settings.snapshots.delete.failed");
    }
  }),
  live.handleEvent("snapshot_restore_accepted", (payload) => {
    clearRestoringSnapshot(payload.snapshotId);
    requestIdempotencyKeyForRestore.value = newIdempotencyKey();
    restoreRequestError.value = null;
  }),
  live.handleEvent("snapshot_restore_failed", (payload) => {
    clearRestoringSnapshot(payload.snapshotId);
    restoreRequestError.value = snapshotRestoreRequestError(payload);
  }),
];

onUnmounted(() => {
  for (const eventRef of serverEventRefs) {
    if (eventRef !== undefined) live.removeHandleEvent(eventRef);
  }
});

function newIdempotencyKey() {
  return (
    globalThis.crypto?.randomUUID?.() ??
    "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
      const random = Math.floor(Math.random() * 16);
      const value = character === "x" ? random : (random & 0x3) | 0x8;
      return value.toString(16);
    })
  );
}

function createSnapshot() {
  if (isSubmitting.value || snapshotLimitReached.value) return;

  requestError.value = null;
  isSubmitting.value = true;

  live.pushEvent(
    "create_snapshot",
    {
      mode: "full",
      idempotency_key: requestIdempotencyKey.value,
      title: title.value,
      description: description.value,
    },
    undefined,
    () => {
      requestError.value = t("project_settings.snapshots.create.connection_failed");
      isSubmitting.value = false;
    },
  );
}

function cancelSnapshot(snapshot: Snapshot) {
  if (!snapshot.canCancel || cancellingSnapshotIds.value.has(snapshot.id)) return;

  cancellingSnapshotIds.value = new Set(cancellingSnapshotIds.value).add(snapshot.id);
  live.pushEvent("cancel_snapshot", { id: snapshot.id }, undefined, () => {
    clearCancellingSnapshot(snapshot.id);
    requestError.value = t("project_settings.snapshots.create.connection_failed");
  });
}

function clearCancellingSnapshot(snapshotId: unknown) {
  let normalizedId = Number.NaN;
  if (typeof snapshotId === "number") normalizedId = snapshotId;
  if (typeof snapshotId === "string") normalizedId = Number(snapshotId);
  if (!Number.isInteger(normalizedId)) return;
  const next = new Set(cancellingSnapshotIds.value);
  next.delete(normalizedId);
  cancellingSnapshotIds.value = next;
}

function openDeleteDialog(snapshot: Snapshot) {
  if (restoreBusy.value || !snapshot.canDelete || deletingSnapshotIds.value.has(snapshot.id))
    return;
  deleteError.value = null;
  snapshotToDelete.value = snapshot;
}

function deleteSnapshot() {
  const snapshot = snapshotToDelete.value;
  if (
    !snapshot ||
    restoreBusy.value ||
    !snapshot.canDelete ||
    deletingSnapshotIds.value.has(snapshot.id)
  )
    return;

  snapshotToDelete.value = null;
  deletingSnapshotIds.value = new Set(deletingSnapshotIds.value).add(snapshot.id);

  live.pushEvent("delete_snapshot", { id: snapshot.id }, undefined, () => {
    clearDeletingSnapshot(snapshot.id);
    deleteError.value = t("project_settings.snapshots.create.connection_failed");
  });
}

function clearDeletingSnapshot(snapshotId: unknown) {
  const normalizedId = typeof snapshotId === "number" ? snapshotId : Number(snapshotId);
  if (!Number.isInteger(normalizedId)) return;

  const next = new Set(deletingSnapshotIds.value);
  next.delete(normalizedId);
  deletingSnapshotIds.value = next;
}

function deleteDialogDescription(snapshot: Snapshot | null) {
  if (!snapshot) return "";

  return t("project_settings.snapshots.delete.description", {
    name: snapshot.title || t("project_settings.snapshots.untitled"),
    version: formatCount(snapshot.versionNumber),
  });
}

function openRestoreDialog(snapshot: Snapshot) {
  if (!snapshot.canRestore || restoreBusy.value) return;
  restoreRequestError.value = null;
  snapshotToRestore.value = snapshot;
}

function restoreSnapshot() {
  const snapshot = snapshotToRestore.value;
  if (!snapshot || !snapshot.canRestore || restoreBusy.value) return;

  snapshotToRestore.value = null;
  restoringSnapshotIds.value = new Set(restoringSnapshotIds.value).add(snapshot.id);

  live.pushEvent(
    "restore_snapshot",
    {
      id: snapshot.id,
      idempotency_key: requestIdempotencyKeyForRestore.value,
    },
    undefined,
    () => {
      clearRestoringSnapshot(snapshot.id);
      restoreRequestError.value = t("project_settings.snapshots.restore.connection_failed");
    },
  );
}

function clearRestoringSnapshot(snapshotId: unknown) {
  const normalizedId = typeof snapshotId === "number" ? snapshotId : Number(snapshotId);
  if (!Number.isInteger(normalizedId)) return;

  const next = new Set(restoringSnapshotIds.value);
  next.delete(normalizedId);
  restoringSnapshotIds.value = next;
}

function restoreDialogDescription(snapshot: Snapshot | null) {
  if (!snapshot) return "";

  return t("project_settings.snapshots.restore.description", {
    name: snapshot.title || t("project_settings.snapshots.untitled"),
    version: formatCount(snapshot.versionNumber),
  });
}

function snapshotRestoreRequestError(payload: Record<string, unknown>) {
  const reasons: Record<string, string> = {
    restore_temporarily_disabled: "disabled",
    project_snapshot_not_restorable: "not_restorable",
    project_snapshot_restore_in_progress: "in_progress",
    project_snapshot_restore_idempotency_conflict: "request_conflict",
    project_snapshot_not_found: "not_found",
    ownership_invariant_violation: "ownership_invariant",
    unauthorized: "unauthorized",
    invalid_project_snapshot_restore_request: "invalid_request",
    invalid_request: "invalid_request",
  };

  const reason = typeof payload.reason === "string" ? reasons[payload.reason] : undefined;
  return t(`project_settings.snapshots.restore.${reason ?? "request_failed"}`);
}

function snapshotRequestError(payload: Record<string, unknown>) {
  if (payload.reason === "ownership_invariant_violation") {
    return t("project_settings.snapshots.create.ownership_invariant");
  }

  if (payload.reason === "unauthorized") {
    return t("project_settings.snapshots.create.unauthorized");
  }

  if (payload.reason === "storage_limit_reached") {
    return t("project_settings.snapshots.create.storage_limit_reached", {
      required: formatReplyBytes(payload.requiredBytes),
      available: formatReplyBytes(payload.availableBytes),
    });
  }

  if (payload.reason === "snapshot_limit_reached") {
    return t("project_settings.snapshots.create.snapshot_limit_reached", {
      used: formatReplyCount(payload.used),
      limit: formatReplyCount(payload.limit),
    });
  }

  return t("project_settings.snapshots.create.request_failed");
}

function formatReplyBytes(value: unknown) {
  return formatBytes(typeof value === "string" ? value : null, locale.value);
}

function formatReplyCount(value: unknown) {
  return typeof value === "number" ? new Intl.NumberFormat(locale.value).format(value) : "—";
}

function formatSnapshotDate(dateStr: string | undefined) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  return d.toLocaleDateString(locale.value, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
    timeZoneName: "short",
  });
}

const workspacePercentage = computed(() =>
  storagePercentage(
    storageUsage.totalAccountedBytes,
    storageUsage.limitBytes,
    storageUsage.limitKind,
  ),
);

const workspacePercentLabel = computed(() => percentageLabel(workspacePercentage.value));

const workspaceHasDeterminateProgress = computed(
  () =>
    workspacePercentage.value.basisPoints !== null && workspacePercentage.value.state !== "zero",
);

function snapshotPercentage(snapshot: Snapshot) {
  if (snapshot.accountedSizeBytes === null) {
    return storagePercentage(null, storageUsage.limitBytes, storageUsage.limitKind);
  }

  return storagePercentage(
    snapshot.accountedSizeBytes,
    storageUsage.limitBytes,
    storageUsage.limitKind,
  );
}

function snapshotPercentLabel(snapshot: Snapshot) {
  return percentageLabel(snapshotPercentage(snapshot));
}

function percentageLabel(percentage: ReturnType<typeof storagePercentage>) {
  if (percentage.state === "zero") {
    return t("project_settings.snapshots.storage_status.zero_capacity");
  }

  if (percentage.lessThanOneBasisPoint) {
    return t("project_settings.snapshots.storage_status.less_than_percent", {
      percent: formatBasisPoints(1n, locale.value),
    });
  }

  if (percentage.basisPoints !== null) {
    return formatBasisPoints(percentage.basisPoints, locale.value);
  }

  switch (percentage.state) {
    case "unlimited":
      return t("project_settings.snapshots.storage_status.unlimited");
    case "over_limit":
      return t("project_settings.snapshots.storage_status.over_limit");
    default:
      return t("project_settings.snapshots.storage_status.unknown");
  }
}

function remainingStorageLabel() {
  if (storageUsage.limitKind === "unlimited") {
    return t("project_settings.snapshots.storage_status.unlimited");
  }

  if (storageUsage.limitKind === "unknown") {
    return t("project_settings.snapshots.storage_status.unknown");
  }

  return formatBytes(storageUsage.remainingBytes, locale.value);
}

function lifecycleLabel(status: SnapshotLifecycle | null) {
  return t(`project_settings.snapshots.lifecycle.${status ?? "unknown"}`);
}

function snapshotLifecycleLabel(snapshot: Snapshot) {
  return snapshot.retrying
    ? t("project_settings.snapshots.lifecycle.retrying")
    : lifecycleLabel(snapshot.lifecycleStatus);
}

function integrityLabel(status: SnapshotIntegrity | null) {
  return t(`project_settings.snapshots.integrity.${status ?? "unknown"}`);
}

function lifecycleBadgeVisible(snapshot: Snapshot) {
  return (
    snapshot.retrying ||
    ["building", "verifying", "failed", "deleting"].includes(snapshot.lifecycleStatus ?? "")
  );
}

function integrityBadgeVisible(status: SnapshotIntegrity | null) {
  return ["missing", "corrupt", "incomplete"].includes(status ?? "");
}

function progressPhaseLabel(snapshot: Snapshot) {
  const phase = snapshot.retrying ? "retrying" : (snapshot.progressPhase ?? "pending");
  return t(`project_settings.snapshots.progress.${phase}`);
}

function buildAttemptLabel(snapshot: Snapshot) {
  if (snapshot.buildMaxAttempts === null) return null;

  if (snapshot.buildAttempt <= 0) {
    return t("project_settings.snapshots.retry.waiting_attempt", {
      attempt: 1,
      max: snapshot.buildMaxAttempts,
    });
  }

  return t("project_settings.snapshots.retry.attempt", {
    attempt: snapshot.buildAttempt,
    max: snapshot.buildMaxAttempts,
  });
}

function retryScheduleLabel(snapshot: Snapshot) {
  if (!snapshot.retrying) return null;
  if (!snapshot.nextRetryAt) return t("project_settings.snapshots.retry.waiting_for_worker");

  const retryAt = new Date(snapshot.nextRetryAt);
  if (Number.isNaN(retryAt.getTime())) {
    return t("project_settings.snapshots.retry.waiting_for_worker");
  }

  const date = formatSnapshotDate(snapshot.nextRetryAt);
  const key = retryAt.getTime() <= Date.now() ? "retry_due" : "next_retry";
  return t(`project_settings.snapshots.retry.${key}`, { date });
}

function retryErrorLabel(snapshot: Snapshot) {
  if (!snapshot.retrying || !snapshot.retryErrorCode) return null;
  return t("project_settings.snapshots.retry.build_failed");
}

function snapshotIsActive(snapshot: Snapshot) {
  return ["pending", "building", "verifying"].includes(snapshot.lifecycleStatus ?? "");
}

function snapshotProgress(snapshot: Snapshot) {
  if (snapshot.progressTotalBytes === null) return 0;

  const total = BigInt(snapshot.progressTotalBytes);
  if (total <= 0n) return 0;

  const current = BigInt(snapshot.progressBytes);
  return Number((current * 10_000n) / total) / 100;
}

function lifecycleVariant(status: SnapshotLifecycle | null): BadgeVariant {
  if (status === "failed" || status === "cancelled") return "destructive";
  if (status === "ready") return "outline";
  return "secondary";
}

function integrityVariant(status: SnapshotIntegrity | null): BadgeVariant {
  if (status === "verified") return "default";
  if (status === "unknown") return "secondary";
  if (!status) return "secondary";
  return "destructive";
}

function restoreStatusLabel(status: RestoreStatus) {
  return t(`project_settings.snapshots.restore.status.${status}`);
}

function restorePhaseLabel(phase: string) {
  return t(`project_settings.snapshots.restore.phase.${phase}`);
}

function restoreStatusVariant(status: RestoreStatus): BadgeVariant {
  if (status === "failed") return "destructive";
  if (status === "completed") return "default";
  return "secondary";
}

function restoreOperationIsActive(operation: RestoreOperation) {
  return ["queued", "running", "retrying"].includes(operation.status);
}

function formatCount(value: number | null) {
  return value === null ? "\u2014" : new Intl.NumberFormat(locale.value).format(value);
}

function accessibleMeasurement(label: string, value: ByteCount | null) {
  return t("project_settings.snapshots.accessibility.measurement", {
    label,
    value: formatBytes(value, locale.value),
  });
}

function entityCountLabel(type: string, count: number) {
  return t(`project_settings.snapshots.entity_types.${type}`, { count: formatCount(count) }, count);
}

function accountingMeasurementLabel(snapshot: Snapshot) {
  if (snapshot.accountingVersion === null || !snapshot.accountingMeasuredAt) return null;

  return t("project_settings.snapshots.measurements.measured", {
    version: snapshot.accountingVersion,
    date: formatSnapshotDate(snapshot.accountingMeasuredAt),
  });
}

const entityTypeOrder = [
  "sheets",
  "flows",
  "scenes",
  "languages",
  "localized_texts",
  "glossary_entries",
];

function sortedEntityCounts(counts: Record<string, number> | undefined) {
  if (!counts) return [];
  return entityTypeOrder
    .filter((type) => counts[type] && counts[type] > 0)
    .map((type) => ({ type, count: counts[type] }));
}
</script>

<template>
  <div class="space-y-6">
    <section aria-labelledby="snapshot-storage-heading">
      <div class="rounded-xl border border-border bg-muted/25 p-4 sm:p-5">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <div class="flex items-center gap-2">
              <HardDrive class="size-4 text-primary" aria-hidden="true" />
              <h3 id="snapshot-storage-heading" class="font-semibold">
                {{ $t("project_settings.snapshots.storage_heading") }}
              </h3>
            </div>
            <p class="mt-1 text-sm text-muted-foreground">
              {{ $t("project_settings.snapshots.storage_description") }}
            </p>
          </div>
          <Badge
            variant="outline"
            class="w-fit tabular-nums"
            :aria-label="
              $t('project_settings.snapshots.accessibility.workspace_percentage', {
                percent: workspacePercentLabel,
              })
            "
          >
            {{ workspacePercentLabel }}
          </Badge>
        </div>

        <div class="mt-4 flex items-baseline justify-between gap-4 text-sm">
          <span
            class="font-semibold tabular-nums"
            :aria-label="
              accessibleMeasurement(
                $t('project_settings.snapshots.storage_heading'),
                storageUsage.totalAccountedBytes,
              )
            "
          >
            {{ formatBytes(storageUsage.totalAccountedBytes, locale) }}
          </span>
          <span class="text-muted-foreground tabular-nums">
            <template v-if="storageUsage.limitKind === 'limited'">
              {{ formatBytes(storageUsage.limitBytes, locale) }}
            </template>
            <template v-else>
              {{ workspacePercentLabel }}
            </template>
          </span>
        </div>
        <Progress
          v-if="workspaceHasDeterminateProgress"
          data-testid="workspace-storage-progress"
          :model-value="workspacePercentage.progressPercent"
          class="mt-2"
          :aria-label="
            $t('project_settings.snapshots.storage_progress_label', {
              percent: workspacePercentLabel,
            })
          "
        />

        <div class="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Image class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.current_assets") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.currentAssetsBytes, locale) }}
            </div>
          </div>
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Trash2 class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.asset_trash") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.assetTrashBytes, locale) }}
            </div>
          </div>
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Archive class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.full_snapshots") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.fullSnapshotsBytes, locale) }}
            </div>
          </div>
        </div>

        <div class="mt-3 grid gap-2 text-xs text-muted-foreground sm:grid-cols-2">
          <div class="flex items-center gap-1.5 rounded-md bg-background/55 px-3 py-2">
            <Database class="size-3.5" aria-hidden="true" />
            <span>{{ $t("project_settings.snapshots.storage_remaining") }}</span>
            <span class="ml-auto font-medium text-foreground tabular-nums">
              {{ remainingStorageLabel() }}
            </span>
          </div>
          <div class="flex items-center gap-1.5 rounded-md bg-background/55 px-3 py-2">
            <Clock3 class="size-3.5" aria-hidden="true" />
            <span>{{ $t("project_settings.snapshots.storage_reservations") }}</span>
            <span class="ml-auto font-medium text-foreground tabular-nums">
              {{ formatBytes(storageUsage.activeReservationsBytes, locale) }}
            </span>
          </div>
        </div>

        <p class="mt-3 text-xs text-muted-foreground">
          {{ $t("project_settings.snapshots.storage_counted_note") }}
        </p>
      </div>
    </section>

    <Separator />

    <section aria-labelledby="create-snapshot-heading">
      <div class="overflow-hidden rounded-xl border border-border bg-card shadow-sm">
        <div class="border-b border-border bg-muted/30 px-4 py-4 sm:px-5">
          <div class="flex items-start gap-3">
            <div class="rounded-lg bg-primary/10 p-2 text-primary">
              <ShieldCheck class="size-4" aria-hidden="true" />
            </div>
            <div>
              <h3 id="create-snapshot-heading" class="font-semibold">
                {{ $t("project_settings.snapshots.create.heading") }}
              </h3>
              <p class="mt-1 text-sm text-muted-foreground">
                {{ $t("project_settings.snapshots.create.description") }}
              </p>
            </div>
          </div>
        </div>

        <form class="space-y-4 p-4 sm:p-5" @submit.prevent="createSnapshot">
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="space-y-1.5">
              <label for="snapshot-title" class="text-sm font-medium">
                {{ $t("project_settings.snapshots.create.title") }}
              </label>
              <Input
                id="snapshot-title"
                v-model="title"
                :maxlength="255"
                :placeholder="$t('project_settings.snapshots.create.title_placeholder')"
                :disabled="isSubmitting"
              />
            </div>
            <div class="space-y-1.5">
              <label for="snapshot-description" class="text-sm font-medium">
                {{ $t("project_settings.snapshots.create.notes") }}
              </label>
              <Textarea
                id="snapshot-description"
                v-model="description"
                :maxlength="500"
                :placeholder="$t('project_settings.snapshots.create.notes_placeholder')"
                :disabled="isSubmitting"
                class="min-h-20 resize-none"
              />
            </div>
          </div>

          <div
            class="flex flex-col gap-3 rounded-lg border border-border/70 bg-muted/25 p-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="text-sm">
              <p class="font-medium">{{ $t("project_settings.snapshots.create.full_mode") }}</p>
              <p class="mt-0.5 text-xs text-muted-foreground">
                {{ $t("project_settings.snapshots.create.reservation_note") }}
              </p>
              <p
                class="mt-1 text-xs font-medium"
                :class="snapshotLimitReached ? 'text-destructive' : 'text-muted-foreground'"
                data-testid="snapshot-slot-usage"
              >
                {{ snapshotLimitLabel }}
              </p>
            </div>
            <Button type="submit" :disabled="isSubmitting || snapshotLimitReached" class="shrink-0">
              <LoaderCircle v-if="isSubmitting" class="size-4 animate-spin" aria-hidden="true" />
              <Plus v-else class="size-4" aria-hidden="true" />
              {{
                isSubmitting
                  ? $t("project_settings.snapshots.create.submitting")
                  : $t("project_settings.snapshots.create.submit")
              }}
            </Button>
          </div>

          <p
            v-if="requestError"
            role="alert"
            data-testid="snapshot-request-error"
            class="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
          >
            {{ requestError }}
          </p>
        </form>
      </div>
    </section>

    <Separator />

    <!-- Snapshot List -->
    <section>
      <h3 class="text-lg font-semibold mb-4">
        {{ $t("project_settings.snapshots.snapshots_heading") }}
      </h3>

      <p
        v-if="deleteError"
        role="alert"
        class="mb-4 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
      >
        {{ deleteError }}
      </p>

      <p
        v-if="restoreRequestError"
        role="alert"
        class="mb-4 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        data-testid="snapshot-restore-error"
      >
        {{ restoreRequestError }}
      </p>

      <!-- Empty state -->
      <div v-if="snapshots.length === 0" class="text-center py-12">
        <Archive class="size-12 mx-auto mb-4 text-muted-foreground/30" />
        <p class="font-medium text-muted-foreground/70">
          {{ $t("project_settings.snapshots.empty_title") }}
        </p>
        <p class="text-sm text-muted-foreground/50 mt-1">
          {{ $t("project_settings.snapshots.empty_description") }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="snapshot in snapshots"
          :id="`snapshot-${snapshot.id}`"
          :key="snapshot.id"
          class="scroll-mt-4 rounded-lg border border-border bg-muted/30 p-4 transition-shadow target:ring-2 target:ring-primary/50 target:ring-offset-2 target:ring-offset-background"
          :data-testid="`snapshot-card-${snapshot.id}`"
        >
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div class="flex-1 min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span class="min-w-0 text-base font-semibold leading-tight">
                  {{ snapshot.title || $t("project_settings.snapshots.untitled") }}
                </span>
                <Badge
                  v-if="lifecycleBadgeVisible(snapshot)"
                  :variant="lifecycleVariant(snapshot.lifecycleStatus)"
                  class="text-xs"
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.lifecycle', {
                      status: snapshotLifecycleLabel(snapshot),
                    })
                  "
                >
                  {{ snapshotLifecycleLabel(snapshot) }}
                </Badge>
                <Badge
                  v-if="integrityBadgeVisible(snapshot.integrityStatus)"
                  :variant="integrityVariant(snapshot.integrityStatus)"
                  class="text-xs"
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.integrity', {
                      status: integrityLabel(snapshot.integrityStatus),
                    })
                  "
                >
                  {{ integrityLabel(snapshot.integrityStatus) }}
                </Badge>
              </div>
              <p v-if="snapshot.description" class="text-sm text-muted-foreground mt-1">
                {{ snapshot.description }}
              </p>
              <div
                v-if="snapshotIsActive(snapshot)"
                class="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3"
              >
                <div class="flex items-center justify-between gap-3 text-xs">
                  <span class="inline-flex items-center gap-1.5 font-medium text-primary">
                    <LoaderCircle class="size-3.5 animate-spin" aria-hidden="true" />
                    {{ progressPhaseLabel(snapshot) }}
                  </span>
                  <span class="tabular-nums text-muted-foreground">
                    {{ formatBytes(snapshot.progressBytes, locale) }} /
                    {{ formatBytes(snapshot.progressTotalBytes, locale) }}
                  </span>
                </div>
                <Progress
                  :model-value="snapshotProgress(snapshot)"
                  class="mt-2 h-1.5"
                  :aria-label="
                    $t('project_settings.snapshots.progress.accessibility', {
                      percent: `${snapshotProgress(snapshot)}%`,
                    })
                  "
                />
                <div class="mt-2 space-y-1 text-xs text-muted-foreground">
                  <p
                    v-if="buildAttemptLabel(snapshot)"
                    :data-testid="`snapshot-attempt-${snapshot.id}`"
                    class="font-medium text-foreground/80"
                  >
                    {{ buildAttemptLabel(snapshot) }}
                  </p>
                  <p
                    v-if="retryScheduleLabel(snapshot)"
                    :data-testid="`snapshot-next-retry-${snapshot.id}`"
                  >
                    {{ retryScheduleLabel(snapshot) }}
                  </p>
                  <p
                    v-if="retryErrorLabel(snapshot)"
                    role="status"
                    :data-testid="`snapshot-retry-error-${snapshot.id}`"
                    :data-error-code="snapshot.retryErrorCode"
                    class="rounded-md border border-amber-500/30 bg-amber-500/10 px-2.5 py-2 text-foreground/80"
                  >
                    {{ retryErrorLabel(snapshot) }}
                  </p>
                </div>
                <div class="mt-2 flex items-center justify-between gap-3">
                  <span class="text-xs text-muted-foreground">
                    {{
                      $t("project_settings.snapshots.progress.reserved", {
                        storage: formatBytes(snapshot.plannedSizeBytes, locale),
                      })
                    }}
                  </span>
                  <Button
                    v-if="snapshot.canCancel"
                    type="button"
                    variant="ghost"
                    size="sm"
                    class="h-7 text-xs text-muted-foreground hover:text-destructive"
                    :disabled="cancellingSnapshotIds.has(snapshot.id)"
                    @click="cancelSnapshot(snapshot)"
                  >
                    <LoaderCircle
                      v-if="cancellingSnapshotIds.has(snapshot.id)"
                      class="size-3.5 animate-spin"
                      aria-hidden="true"
                    />
                    <X v-else class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.progress.cancel") }}
                  </Button>
                  <span
                    v-else-if="snapshot.cancelRequestedAt"
                    class="text-xs text-muted-foreground"
                  >
                    {{ $t("project_settings.snapshots.progress.cancelling") }}
                  </span>
                </div>
              </div>
              <p
                v-if="snapshot.lifecycleStatus === 'failed' && snapshot.failureMessage"
                role="status"
                class="mt-3 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
              >
                {{ snapshot.failureMessage }}
              </p>
              <div
                v-if="snapshot.restoreOperation"
                class="mt-3 rounded-lg border border-border/70 bg-background/70 p-3"
                :data-testid="`snapshot-restore-operation-${snapshot.id}`"
              >
                <div class="flex flex-wrap items-center gap-2">
                  <LoaderCircle
                    v-if="restoreOperationIsActive(snapshot.restoreOperation)"
                    class="size-3.5 animate-spin text-primary"
                    aria-hidden="true"
                  />
                  <RotateCcw v-else class="size-3.5 text-muted-foreground" aria-hidden="true" />
                  <span class="text-xs font-medium">
                    {{ $t("project_settings.snapshots.restore.operation") }}
                  </span>
                  <Badge
                    :variant="restoreStatusVariant(snapshot.restoreOperation.status)"
                    class="text-xs"
                  >
                    {{ restoreStatusLabel(snapshot.restoreOperation.status) }}
                  </Badge>
                  <span class="text-xs text-muted-foreground">
                    {{ restorePhaseLabel(snapshot.restoreOperation.phase) }}
                  </span>
                </div>
                <p
                  v-if="
                    snapshot.restoreOperation.status === 'failed' &&
                    snapshot.restoreOperation.failureMessage
                  "
                  role="status"
                  class="mt-2 text-xs text-destructive"
                >
                  {{ snapshot.restoreOperation.failureMessage }}
                </p>
                <p v-else class="mt-2 text-xs text-muted-foreground">
                  {{
                    $t(
                      snapshot.restoreOperation.status === "completed"
                        ? "project_settings.snapshots.restore.completed_note"
                        : "project_settings.snapshots.restore.durable_note",
                    )
                  }}
                </p>
              </div>
              <div class="flex flex-wrap gap-3 mt-2 text-xs text-muted-foreground/60">
                <span v-if="snapshot.createdByEmail">
                  {{ snapshot.createdByEmail }}
                </span>
                <span>{{ formatSnapshotDate(snapshot.insertedAt) }}</span>
                <span
                  class="font-medium text-foreground/75 tabular-nums"
                  :aria-label="
                    accessibleMeasurement(
                      $t('project_settings.snapshots.measurements.accounted_size'),
                      snapshot.accountedSizeBytes,
                    )
                  "
                >
                  {{ formatBytes(snapshot.accountedSizeBytes, locale) }}
                </span>
                <span v-if="snapshot.accountedSizeBytes === null" class="tabular-nums">
                  {{
                    $t("project_settings.snapshots.measurements.planned_size", {
                      storage: formatBytes(snapshot.plannedSizeBytes, locale),
                    })
                  }}
                </span>
                <span
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.snapshot_percentage', {
                      percent: snapshotPercentLabel(snapshot),
                    })
                  "
                >
                  {{
                    $t("project_settings.snapshots.accessibility.snapshot_percentage", {
                      percent: snapshotPercentLabel(snapshot),
                    })
                  }}
                </span>
                <span v-for="ec in sortedEntityCounts(snapshot.entityCounts)" :key="ec.type">
                  {{ entityCountLabel(ec.type, ec.count) }}
                </span>
              </div>

              <div
                class="mt-3 grid gap-2 rounded-lg border border-border/60 bg-background/60 p-3 sm:grid-cols-2"
                :data-testid="`archive-breakdown-${snapshot.id}`"
              >
                <div>
                  <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <Archive class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.measurements.zip_archive") }}
                  </div>
                  <div class="mt-1 text-sm font-medium tabular-nums">
                    {{ formatBytes(snapshot.archiveSizeBytes, locale) }}
                  </div>
                </div>
                <div>
                  <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <FileJson2 class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.measurements.manifest_sidecar") }}
                  </div>
                  <div class="mt-1 text-sm font-medium tabular-nums">
                    {{ formatBytes(snapshot.sidecarSizeBytes, locale) }}
                  </div>
                </div>
              </div>
              <p class="mt-2 text-xs text-muted-foreground">
                {{
                  $t("project_settings.snapshots.measurements.inventory", {
                    assets: formatCount(snapshot.assetCount),
                    blobs: formatCount(snapshot.blobCount),
                  })
                }}
              </p>
              <p
                v-if="accountingMeasurementLabel(snapshot)"
                class="mt-1 text-xs text-muted-foreground"
              >
                {{ accountingMeasurementLabel(snapshot) }}
              </p>
              <div
                v-if="
                  positiveByteCount(snapshot.activeReservationBytes) ||
                  positiveByteCount(snapshot.exportReservationBytes)
                "
                class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground"
              >
                <span
                  v-if="positiveByteCount(snapshot.activeReservationBytes)"
                  class="inline-flex items-center gap-1.5"
                >
                  <Clock3 class="size-3.5" aria-hidden="true" />
                  {{
                    $t("project_settings.snapshots.measurements.active_reservation", {
                      storage: formatBytes(snapshot.activeReservationBytes, locale),
                    })
                  }}
                </span>
                <span
                  v-if="positiveByteCount(snapshot.exportReservationBytes)"
                  class="inline-flex items-center gap-1.5"
                >
                  <Download class="size-3.5" aria-hidden="true" />
                  {{
                    $t("project_settings.snapshots.measurements.export_reservation", {
                      storage: formatBytes(snapshot.exportReservationBytes, locale),
                    })
                  }}
                </span>
              </div>
            </div>
            <div class="flex shrink-0 flex-col items-stretch gap-2 lg:items-end">
              <Button v-if="snapshot.downloadUrl" variant="outline" size="sm" as-child>
                <a
                  :href="snapshot.downloadUrl"
                  referrerpolicy="no-referrer"
                  data-live-link-exempt="download"
                  :data-testid="`download-snapshot-${snapshot.id}`"
                >
                  <Download class="size-4" aria-hidden="true" />
                  {{ $t("project_settings.snapshots.download.action") }}
                </a>
              </Button>
              <p
                v-if="snapshot.canRestore && restoreBusy"
                :id="`restore-snapshot-reason-${snapshot.id}`"
                class="max-w-56 text-xs leading-relaxed text-muted-foreground lg:text-right"
                :data-testid="`restore-active-operation-${snapshot.id}`"
              >
                {{ $t("project_settings.snapshots.restore.active_operation") }}
              </p>
              <Button
                v-if="snapshot.canRestore"
                type="button"
                variant="outline"
                size="sm"
                :disabled="restoreBusy"
                :aria-describedby="
                  restoreBusy ? `restore-snapshot-reason-${snapshot.id}` : undefined
                "
                :data-testid="`restore-snapshot-${snapshot.id}`"
                @click="openRestoreDialog(snapshot)"
              >
                <LoaderCircle
                  v-if="restoringSnapshotIds.has(snapshot.id)"
                  class="size-4 animate-spin"
                  aria-hidden="true"
                />
                <RotateCcw v-else class="size-4" aria-hidden="true" />
                {{
                  restoringSnapshotIds.has(snapshot.id)
                    ? $t("project_settings.snapshots.restore.submitting")
                    : $t("project_settings.snapshots.restore.action")
                }}
              </Button>
              <p
                v-if="
                  (restoreBusy && snapshot.deleteStatus !== null) ||
                  snapshot.deleteStatus === 'restore_operation'
                "
                :id="`delete-snapshot-reason-${snapshot.id}`"
                class="max-w-56 text-xs leading-relaxed text-muted-foreground lg:text-right"
                :data-testid="`delete-restore-operation-${snapshot.id}`"
              >
                {{ $t("project_settings.snapshots.delete.restore_operation") }}
              </p>
              <p
                v-else-if="snapshot.deleteStatus === 'download_lease'"
                :id="`delete-snapshot-reason-${snapshot.id}`"
                class="max-w-56 text-xs leading-relaxed text-muted-foreground lg:text-right"
                :data-testid="`delete-download-lease-${snapshot.id}`"
              >
                {{ $t("project_settings.snapshots.delete.download_lease") }}
              </p>
              <p
                v-else-if="snapshot.deleteStatus === 'active_operation'"
                :id="`delete-snapshot-reason-${snapshot.id}`"
                class="max-w-56 text-xs leading-relaxed text-muted-foreground lg:text-right"
                :data-testid="`delete-active-operation-${snapshot.id}`"
              >
                {{ $t("project_settings.snapshots.delete.active_operation") }}
              </p>
              <Button
                v-if="snapshot.deleteStatus"
                type="button"
                variant="ghost"
                size="sm"
                class="text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                :disabled="
                  restoreBusy || !snapshot.canDelete || deletingSnapshotIds.has(snapshot.id)
                "
                :aria-describedby="
                  snapshot.canDelete && !restoreBusy
                    ? undefined
                    : `delete-snapshot-reason-${snapshot.id}`
                "
                :data-testid="`delete-snapshot-${snapshot.id}`"
                @click="openDeleteDialog(snapshot)"
              >
                <LoaderCircle
                  v-if="deletingSnapshotIds.has(snapshot.id)"
                  class="size-4 animate-spin"
                  aria-hidden="true"
                />
                <Trash2 v-else class="size-4" aria-hidden="true" />
                {{ $t("project_settings.snapshots.delete.action") }}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </section>

    <ConfirmDialog
      v-model:open="deleteDialogOpen"
      :title="$t('project_settings.snapshots.delete.title')"
      :description="deleteDialogDescription(snapshotToDelete)"
      :confirm-text="$t('project_settings.snapshots.delete.confirm')"
      :cancel-text="$t('project_settings.snapshots.delete.cancel')"
      variant="destructive"
      :icon="Trash2"
      @confirm="deleteSnapshot"
    />

    <ConfirmDialog
      v-model:open="restoreDialogOpen"
      :title="$t('project_settings.snapshots.restore.title')"
      :description="restoreDialogDescription(snapshotToRestore)"
      :confirm-text="$t('project_settings.snapshots.restore.confirm')"
      :cancel-text="$t('project_settings.snapshots.restore.cancel')"
      variant="destructive"
      :icon="RotateCcw"
      @confirm="restoreSnapshot"
    />
  </div>
</template>
