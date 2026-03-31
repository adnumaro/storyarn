import { onMounted, ref } from "vue";
import { useLive } from "@composables/useLive";

/**
 * Shared composable for version history logic.
 * Used by sheets (HistoryTab), scenes (VersionHistoryPanel), and flows.
 *
 * All server events are the same across entity types — the server
 * knows which entity is active from the LiveView socket assigns.
 */
export function useVersionHistory() {
  const live = useLive();

  // Local state
  const showAutoVersions = ref(false);
  const expandedChangelogs = ref(new Set());
  const showCreateModal = ref(false);
  const showPromoteModal = ref(false);
  const promoteVersion = ref(null);
  const showDeleteModal = ref(false);
  const deleteVersionNumber = ref(null);
  const showUnsavedModal = ref(false);
  const unsavedVersionNumber = ref(null);
  const showRestoreModal = ref(false);
  const restoreData = ref(null);
  const loadingAction = ref(null);

  // Form state
  const createTitle = ref("");
  const createDescription = ref("");
  const promoteTitle = ref("");
  const promoteDescription = ref("");

  // Server push event handlers
  onMounted(() => {
    live.handleEvent("show_unsaved_modal", ({ versionNumber }) => {
      loadingAction.value = null;
      unsavedVersionNumber.value = versionNumber;
      showUnsavedModal.value = true;
    });

    live.handleEvent("show_restore_modal", ({ versionNumber, report, skipPreSnapshot }) => {
      loadingAction.value = null;
      showUnsavedModal.value = false;
      restoreData.value = { versionNumber, report, skipPreSnapshot };
      showRestoreModal.value = true;
    });

    live.handleEvent("version_restored", () => {
      showRestoreModal.value = false;
      restoreData.value = null;
      loadingAction.value = null;
    });
  });

  function toggleChangelog(versionNumber) {
    if (expandedChangelogs.value.has(versionNumber)) {
      expandedChangelogs.value.delete(versionNumber);
    } else {
      expandedChangelogs.value.add(versionNumber);
    }
    expandedChangelogs.value = new Set(expandedChangelogs.value);
  }

  function openCreateModal() {
    createTitle.value = "";
    createDescription.value = "";
    showCreateModal.value = true;
  }

  function submitCreate() {
    if (!createTitle.value.trim()) return;
    loadingAction.value = "create";
    live.pushEvent(
      "create_version",
      {
        title: createTitle.value.trim(),
        description: createDescription.value.trim(),
      },
      () => {
        loadingAction.value = null;
        showCreateModal.value = false;
      },
    );
  }

  function openPromoteModal(version) {
    promoteVersion.value = version;
    promoteTitle.value = version.changeSummary || "";
    promoteDescription.value = "";
    showPromoteModal.value = true;
  }

  function submitPromote() {
    if (!promoteVersion.value || !promoteTitle.value.trim()) return;
    loadingAction.value = "promote";
    live.pushEvent(
      "promote_version",
      {
        version_number: promoteVersion.value.versionNumber,
        title: promoteTitle.value.trim(),
        description: promoteDescription.value.trim(),
      },
      () => {
        loadingAction.value = null;
        showPromoteModal.value = false;
        promoteVersion.value = null;
      },
    );
  }

  function openDeleteModal(versionNumber) {
    deleteVersionNumber.value = versionNumber;
    showDeleteModal.value = true;
  }

  function confirmDelete() {
    if (!deleteVersionNumber.value) return;
    loadingAction.value = "delete";
    live.pushEvent("delete_version", { version_number: deleteVersionNumber.value }, () => {
      loadingAction.value = null;
      showDeleteModal.value = false;
      deleteVersionNumber.value = null;
    });
  }

  function previewRestore(versionNumber) {
    loadingAction.value = `restore-${versionNumber}`;
    live.pushEvent("preview_restore", { version_number: versionNumber });
  }

  function saveAndRestore() {
    loadingAction.value = "save-restore";
    live.pushEvent("save_and_restore", {
      version_number: unsavedVersionNumber.value,
    });
  }

  function discardAndRestore() {
    loadingAction.value = "discard-restore";
    live.pushEvent("discard_and_restore", {
      version_number: unsavedVersionNumber.value,
    });
  }

  function confirmRestore() {
    if (!restoreData.value) return;
    loadingAction.value = "confirm-restore";
    live.pushEvent("confirm_restore", {
      version_number: restoreData.value.versionNumber,
      skip_pre_snapshot: restoreData.value.skipPreSnapshot,
    });
  }

  function loadMore() {
    loadingAction.value = "load-more";
    live.pushEvent("load_more_versions", {}, () => {
      loadingAction.value = null;
    });
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
    saveAndRestore,
    discardAndRestore,
    confirmRestore,
    loadMore,
  };
}
