import { onMounted, ref } from "vue";
import { useLive } from "@shared/composables/useLive";

export interface VersionEntry {
  id?: number;
  versionNumber: number;
  title?: string;
  description?: string;
  changeSummary?: string;
  changeDetails?: {
    stats?: { added?: number; modified?: number; removed?: number };
    changes?: { action: string; detail: string }[];
  };
  insertedAt?: string;
  createdBy?: string;
}

export interface RestoreConflict {
  type: string;
  id: number | string | null;
  contexts: string[];
}

export interface RestoreReport {
  hasConflicts: boolean;
  shortcutCollision?: boolean;
  resolvedShortcut?: string;
  conflicts: RestoreConflict[];
}

export interface RestoreData {
  versionNumber: number;
  report: RestoreReport;
}

type RestorePhase = "preview" | "unsaved" | "review" | "ready" | "confirm";

interface RestoreRequest {
  requestId: string;
  phase: RestorePhase;
  versionNumber: number;
  loadingKey: string;
  pending: boolean;
}

function randomRequestId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/**
 * Shared composable for version history logic.
 * Used by sheets (HistoryTab), scenes (VersionHistoryPanel), and flows.
 *
 * All server events are the same across entity types — the server
 * knows which entity is active from the LiveView socket assigns.
 */
export function useVersionHistory(restoreEnabled: () => boolean) {
  const live = useLive();

  // Local state
  const showAutoVersions = ref(false);
  const expandedChangelogs = ref(new Set<number>());
  const showCreateModal = ref(false);
  const showPromoteModal = ref(false);
  const promoteVersion = ref<VersionEntry | null>(null);
  const showDeleteModal = ref(false);
  const deleteVersionNumber = ref<number | null>(null);
  const showUnsavedModal = ref(false);
  const unsavedVersionNumber = ref<number | null>(null);
  const showRestoreModal = ref(false);
  const restoreData = ref<RestoreData | null>(null);
  const loadingAction = ref<string | null>(null);
  const transportError = ref(false);

  let restoreRequest: RestoreRequest | null = null;

  // Form state
  const createTitle = ref("");
  const createDescription = ref("");
  const promoteTitle = ref("");
  const promoteDescription = ref("");

  // Server push event handlers
  onMounted(() => {
    live.handleEvent("show_unsaved_modal", (payload) => {
      if (!restoreEnabled()) {
        invalidateRestoreRequest();
        return;
      }

      const versionNumber = payload.versionNumber;
      const hasRequestId = Object.prototype.hasOwnProperty.call(payload, "request_id");
      const requestId = payload.request_id;
      if (typeof versionNumber !== "number") return;
      if (hasRequestId && typeof requestId !== "string") return;

      const request = matchingRestoreRequest(
        ["preview"],
        hasRequestId ? (requestId as string) : undefined,
        versionNumber,
      );
      if (!request) return;

      clearRestoreLoading(request);
      restoreRequest = { ...request, phase: "unsaved", pending: false };
      unsavedVersionNumber.value = versionNumber;
      showUnsavedModal.value = true;
    });

    live.handleEvent("show_restore_modal", (payload) => {
      if (!restoreEnabled()) {
        invalidateRestoreRequest();
        return;
      }

      const versionNumber = payload.versionNumber;
      const hasRequestId = Object.prototype.hasOwnProperty.call(payload, "request_id");
      const requestId = payload.request_id;
      if (typeof versionNumber !== "number") return;
      if (hasRequestId && typeof requestId !== "string") return;

      const request = matchingRestoreRequest(
        ["preview", "review"],
        hasRequestId ? (requestId as string) : undefined,
        versionNumber,
      );
      if (!request) return;

      clearRestoreLoading(request);
      restoreRequest = { ...request, phase: "ready", pending: false };
      showUnsavedModal.value = false;
      restoreData.value = {
        versionNumber,
        report: payload.report as RestoreReport,
      };
      showRestoreModal.value = true;
    });

    live.handleEvent("version_restored", (payload) => {
      const hasRequestId = Object.prototype.hasOwnProperty.call(payload, "request_id");
      const requestId = payload.request_id;
      if (hasRequestId && typeof requestId !== "string") return;

      const request = matchingRestoreRequest(
        ["confirm"],
        hasRequestId ? (requestId as string) : undefined,
      );
      if (!request) return;

      clearRestoreLoading(request);
      restoreRequest = null;
      showRestoreModal.value = false;
      restoreData.value = null;
    });
  });

  function beginRestoreRequest(
    phase: RestorePhase,
    versionNumber: number,
    loadingKey: string,
  ): RestoreRequest {
    const request = {
      requestId: randomRequestId(),
      phase,
      versionNumber,
      loadingKey,
      pending: true,
    };

    restoreRequest = request;
    transportError.value = false;
    loadingAction.value = loadingKey;

    return request;
  }

  function matchingRestoreRequest(
    phases: RestorePhase[],
    requestId?: string,
    versionNumber?: number,
  ): RestoreRequest | null {
    if (!restoreRequest || !phases.includes(restoreRequest.phase)) return null;
    if (requestId !== undefined && restoreRequest.requestId !== requestId) return null;
    if (versionNumber !== undefined && restoreRequest.versionNumber !== versionNumber) return null;

    return restoreRequest;
  }

  function clearRestoreLoading(request: RestoreRequest) {
    if (restoreRequest?.requestId !== request.requestId) return;
    if (loadingAction.value === request.loadingKey) loadingAction.value = null;
  }

  function clearLoadingAction(loadingKey: string) {
    if (loadingAction.value === loadingKey) loadingAction.value = null;
  }

  function beginLoadingAction(loadingKey: string) {
    transportError.value = false;
    loadingAction.value = loadingKey;
  }

  function failLoadingAction(loadingKey: string) {
    if (loadingAction.value !== loadingKey) return;

    loadingAction.value = null;
    transportError.value = true;
  }

  function finishRestoreTransport(request: RestoreRequest) {
    if (restoreRequest?.requestId !== request.requestId) return;

    clearRestoreLoading(request);
    restoreRequest = { ...restoreRequest, pending: false };
  }

  function failRestoreTransport(request: RestoreRequest) {
    if (restoreRequest?.requestId !== request.requestId) return;

    clearRestoreLoading(request);
    restoreRequest = null;
    transportError.value = true;
  }

  function invalidateRestoreRequest() {
    if (!restoreRequest) return;

    clearRestoreLoading(restoreRequest);
    restoreRequest = null;
  }

  function duplicateRestoreRequest(phase: RestorePhase, versionNumber: number) {
    return (
      restoreRequest?.pending === true &&
      restoreRequest.phase === phase &&
      restoreRequest.versionNumber === versionNumber
    );
  }

  function toggleChangelog(versionNumber: number) {
    if (expandedChangelogs.value.has(versionNumber)) {
      expandedChangelogs.value.delete(versionNumber);
    } else {
      expandedChangelogs.value.add(versionNumber);
    }
    expandedChangelogs.value = new Set(expandedChangelogs.value);
  }

  function openCreateModal() {
    transportError.value = false;
    createTitle.value = "";
    createDescription.value = "";
    showCreateModal.value = true;
  }

  function submitCreate() {
    if (!createTitle.value.trim()) return;
    beginLoadingAction("create");
    live.pushEvent(
      "create_version",
      {
        title: createTitle.value.trim(),
        description: createDescription.value.trim(),
      },
      () => {
        clearLoadingAction("create");
        showCreateModal.value = false;
      },
      () => failLoadingAction("create"),
    );
  }

  function openPromoteModal(version: VersionEntry) {
    transportError.value = false;
    promoteVersion.value = version;
    promoteTitle.value = version.changeSummary || "";
    promoteDescription.value = "";
    showPromoteModal.value = true;
  }

  function submitPromote() {
    if (!promoteVersion.value || !promoteTitle.value.trim()) return;
    beginLoadingAction("promote");
    live.pushEvent(
      "promote_version",
      {
        version_number: promoteVersion.value.versionNumber,
        title: promoteTitle.value.trim(),
        description: promoteDescription.value.trim(),
      },
      () => {
        clearLoadingAction("promote");
        showPromoteModal.value = false;
        promoteVersion.value = null;
      },
      () => failLoadingAction("promote"),
    );
  }

  function openDeleteModal(versionNumber: number) {
    transportError.value = false;
    deleteVersionNumber.value = versionNumber;
    showDeleteModal.value = true;
  }

  function confirmDelete() {
    if (!deleteVersionNumber.value) return;
    beginLoadingAction("delete");
    live.pushEvent(
      "delete_version",
      { version_number: deleteVersionNumber.value },
      () => {
        clearLoadingAction("delete");
        showDeleteModal.value = false;
        deleteVersionNumber.value = null;
      },
      () => failLoadingAction("delete"),
    );
  }

  function previewRestore(versionNumber: number) {
    if (!restoreEnabled()) return;
    if (duplicateRestoreRequest("preview", versionNumber)) return;

    showUnsavedModal.value = false;
    unsavedVersionNumber.value = null;
    showRestoreModal.value = false;
    restoreData.value = null;

    const request = beginRestoreRequest("preview", versionNumber, `restore-${versionNumber}`);

    live.pushEvent(
      "preview_restore",
      { version_number: versionNumber, request_id: request.requestId },
      () => finishRestoreTransport(request),
      () => failRestoreTransport(request),
    );
  }

  function reviewRestore() {
    if (!restoreEnabled()) return;
    if (unsavedVersionNumber.value === null) return;
    if (duplicateRestoreRequest("review", unsavedVersionNumber.value)) return;

    const request = beginRestoreRequest("review", unsavedVersionNumber.value, "review-restore");

    live.pushEvent(
      "review_restore",
      {
        version_number: unsavedVersionNumber.value,
        request_id: request.requestId,
      },
      () => finishRestoreTransport(request),
      () => failRestoreTransport(request),
    );
  }

  function confirmRestore() {
    if (!restoreEnabled()) return;
    if (!restoreData.value) return;
    if (duplicateRestoreRequest("confirm", restoreData.value.versionNumber)) return;

    const request = beginRestoreRequest(
      "confirm",
      restoreData.value.versionNumber,
      "confirm-restore",
    );

    live.pushEvent(
      "confirm_restore",
      {
        version_number: restoreData.value.versionNumber,
        request_id: request.requestId,
      },
      () => finishRestoreTransport(request),
      () => failRestoreTransport(request),
    );
  }

  function loadMore() {
    beginLoadingAction("load-more");
    live.pushEvent(
      "load_more_versions",
      {},
      () => clearLoadingAction("load-more"),
      () => failLoadingAction("load-more"),
    );
  }

  return {
    // State
    showAutoVersions,
    expandedChangelogs,
    showCreateModal,
    showPromoteModal,
    promoteVersion,
    showDeleteModal,
    deleteVersionNumber,
    showUnsavedModal,
    unsavedVersionNumber,
    showRestoreModal,
    restoreData,
    loadingAction,
    transportError,
    createTitle,
    createDescription,
    promoteTitle,
    promoteDescription,
    // Actions
    toggleChangelog,
    openCreateModal,
    submitCreate,
    openPromoteModal,
    submitPromote,
    openDeleteModal,
    confirmDelete,
    previewRestore,
    reviewRestore,
    confirmRestore,
    loadMore,
  };
}
