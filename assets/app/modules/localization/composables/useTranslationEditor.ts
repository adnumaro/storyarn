import { computed, nextTick, onBeforeUnmount, ref, watch } from "vue";
import type { LiveInterface } from "@shared/composables/useLive";
import type {
  PlaceholderIssue,
  SaveResponse,
  SaveState,
  SelectedText,
  TextRow,
} from "../domain/types";

const AUTOSAVE_DELAY_MS = 900;
const SAVED_FLASH_MS = 1800;

interface EditorOptions {
  live: LiveInterface;
  selectedText: () => SelectedText | null;
  texts: () => TextRow[];
  canEdit: () => boolean;
  hasMore: () => boolean;
  onSelect: (id: number) => void;
  onClose: () => void;
  onLoadMore: () => void;
}

interface PendingSave {
  id: number;
  snapshot: string;
}

/**
 * State machine of the inline translation editor: hydration from the
 * selected string, autosave with lock versions, conflicts, placeholder
 * validation, and the save-before-navigate rule shared by row selection,
 * previous/next and per-row machine translation.
 */
export function useTranslationEditor(options: EditorOptions) {
  const { live } = options;

  const translatedText = ref("");
  const status = ref("pending");
  const translatorNotes = ref("");
  const voStatus = ref("none");
  const localLockVersion = ref(1);
  const saveState = ref<SaveState>("idle");
  const saveError = ref("");
  const translating = ref(false);
  const hydrating = ref(false);
  const lastSavedSnapshot = ref("");
  const conflictVersion = ref<number | null>(null);
  const conflictText = ref<SelectedText | null>(null);

  let autosaveTimeout: ReturnType<typeof setTimeout> | null = null;
  let savedTimeout: ReturnType<typeof setTimeout> | null = null;
  let pendingSave: PendingSave | null = null;
  let deferredNavigation: (() => void) | null = null;
  let advanceAfterLoad = false;

  const currentIndex = computed(() =>
    options.texts().findIndex((text) => text.id === options.selectedText()?.id),
  );
  const previousText = computed(() =>
    currentIndex.value > 0 ? options.texts()[currentIndex.value - 1] : null,
  );
  const nextText = computed(() => {
    const texts = options.texts();
    return currentIndex.value >= 0 && currentIndex.value < texts.length - 1
      ? texts[currentIndex.value + 1]
      : null;
  });
  const canAdvance = computed(() => nextText.value !== null || options.hasMore());

  const currentSnapshot = computed(() =>
    JSON.stringify({
      translatedText: translatedText.value,
      status: status.value,
      translatorNotes: translatorNotes.value,
      voStatus: voStatus.value,
    }),
  );
  const dirty = computed(() => currentSnapshot.value !== lastSavedSnapshot.value);

  const placeholderIssue = computed<PlaceholderIssue | null>(() => {
    const text = options.selectedText();
    if (!text || translatedText.value.trim() === "") return null;

    const expected = frequencies(text.placeholders);
    const actual = frequencies(translatedText.value.match(/\{[^{}\r\n]+\}/g) ?? []);
    const missing = difference(expected, actual);
    const extra = difference(actual, expected);

    if (missing.length === 0 && extra.length === 0) return null;
    return { missing, extra };
  });

  const finalUnavailable = computed(
    () => translatedText.value.trim() === "" || placeholderIssue.value !== null,
  );

  watch(
    () => options.selectedText(),
    (text) => {
      const activeSave = pendingSave;
      const hasNewerLocalEdit =
        activeSave !== null &&
        activeSave.id === text?.id &&
        currentSnapshot.value !== activeSave.snapshot;

      if (!hasNewerLocalEdit) hydrateEditor(text);
    },
    { immediate: true },
  );

  watch(translatedText, (value, previous) => {
    if (hydrating.value || value === previous) return;
    if (value.trim() === "") status.value = "pending";
    else if (status.value === "pending" || status.value === "final") status.value = "draft";
  });

  watch([translatedText, status, translatorNotes, voStatus], () => {
    if (hydrating.value || !options.selectedText() || !options.canEdit()) return;
    if (!dirty.value) return;

    saveState.value = "dirty";
    scheduleAutosave();
  });

  // "Save & next" past the loaded rows: the page loads one more page and we
  // advance as soon as the new rows arrive.
  watch(
    () => options.texts().length,
    (length, previous) => {
      if (advanceAfterLoad && length > previous) {
        advanceAfterLoad = false;
        selectRelative("next");
      }
    },
  );

  onBeforeUnmount(() => {
    if (autosaveTimeout) clearTimeout(autosaveTimeout);
    if (savedTimeout) clearTimeout(savedTimeout);
  });

  function hydrateEditor(text: SelectedText | null | undefined): void {
    const values = editorValues(text);
    hydrating.value = true;
    translatedText.value = values.translatedText;
    status.value = values.status;
    translatorNotes.value = values.translatorNotes;
    voStatus.value = values.voStatus;
    localLockVersion.value = values.lockVersion;
    conflictVersion.value = null;
    conflictText.value = null;
    saveError.value = "";
    saveState.value = "idle";

    nextTick(() => {
      lastSavedSnapshot.value = currentSnapshot.value;
      hydrating.value = false;
    });
  }

  function scheduleAutosave(): void {
    if (autosaveTimeout) clearTimeout(autosaveTimeout);
    autosaveTimeout = setTimeout(() => saveTranslation(), AUTOSAVE_DELAY_MS);
  }

  function saveAllowed(text: SelectedText | null): text is SelectedText {
    return !!text && options.canEdit() && saveState.value !== "saving" && !placeholderIssue.value;
  }

  function saveTranslation(
    advance = false,
    onSuccess?: () => void,
    onFailure?: () => void,
    force = false,
  ): void {
    const text = options.selectedText();
    if (!saveAllowed(text)) {
      onFailure?.();
      return;
    }

    if (autosaveTimeout) clearTimeout(autosaveTimeout);

    if (!dirty.value && !advance && !force) {
      onSuccess?.();
      return;
    }

    saveState.value = "saving";
    saveError.value = "";
    const request = { id: text.id, snapshot: currentSnapshot.value };
    pendingSave = request;

    live.pushEvent(
      "save_translation",
      {
        id: text.id,
        lock_version: localLockVersion.value,
        localized_text: {
          translated_text: translatedText.value,
          status: status.value,
          translator_notes: translatorNotes.value,
          vo_status: voStatus.value,
        },
      },
      (response: SaveResponse) =>
        handleSaveResponse(response, request, advance, onSuccess, onFailure),
      () => {
        if (superseded(request)) return;
        pendingSave = null;
        handleSaveError({ error: "save_failed" });
        onFailure?.();
      },
    );
  }

  // Only the newest save owns the shared state. A reply to an older request
  // (the selection moved server-side and the translator kept typing) must not
  // clear the in-flight state or the navigation queued behind the newer save.
  function superseded(request: PendingSave): boolean {
    return pendingSave !== request;
  }

  function handleSaveResponse(
    response: SaveResponse,
    request: PendingSave,
    advance: boolean,
    onSuccess?: () => void,
    onFailure?: () => void,
  ): void {
    if (superseded(request)) return;
    pendingSave = null;
    if (discardStaleReply(request)) return;

    if (response?.ok) {
      handleSaveSuccess(response.text, request, advance, onSuccess, onFailure);
      return;
    }

    deferredNavigation = null;
    if (response?.conflict && response.text) handleSaveConflict(response.text);
    else handleSaveError(response);
    onFailure?.();
  }

  // The translator moved to another string (or locale) while this save was in
  // flight: the reply belongs to a row the editor no longer shows, so it must
  // not touch the editor, report a conflict, or navigate.
  function discardStaleReply(request: PendingSave): boolean {
    if (options.selectedText()?.id === request.id) return false;
    deferredNavigation = null;
    if (saveState.value === "saving") saveState.value = "idle";
    return true;
  }

  function handleSaveSuccess(
    savedText: SelectedText | undefined,
    request: PendingSave,
    advance: boolean,
    onSuccess?: () => void,
    onFailure?: () => void,
  ): void {
    const hasNewerLocalEdit =
      options.selectedText()?.id === request.id && currentSnapshot.value !== request.snapshot;

    if (hasNewerLocalEdit) {
      if (savedText) localLockVersion.value = savedText.lockVersion;
      lastSavedSnapshot.value = request.snapshot;
      saveState.value = "dirty";
      saveTranslation(advance, onSuccess, onFailure);
      return;
    }

    if (savedText) hydrateEditor(savedText);
    lastSavedSnapshot.value = request.snapshot;
    saveState.value = "saved";
    if (savedTimeout) clearTimeout(savedTimeout);
    savedTimeout = setTimeout(() => (saveState.value = "idle"), SAVED_FLASH_MS);
    onSuccess?.();

    // A row clicked while this save was in flight wins over "save & next".
    const deferred = deferredNavigation;
    deferredNavigation = null;
    if (deferred) deferred();
    else if (advance) selectRelative("next");
  }

  function handleSaveConflict(latestText: SelectedText): void {
    conflictVersion.value = latestText.lockVersion;
    conflictText.value = latestText;
    saveState.value = "conflict";
    saveError.value = "conflict";
  }

  function handleSaveError(response: SaveResponse): void {
    saveState.value = "error";
    saveError.value = response?.errors
      ? Object.values(response.errors).join(" · ")
      : response?.error || "save_failed";
  }

  /** Re-saves the current translation so the Outdated flag clears while the status stays. */
  function confirmStillCorrect(): void {
    saveTranslation(false, undefined, undefined, true);
  }

  function retryAfterConflict(): void {
    if (conflictVersion.value === null) return;
    localLockVersion.value = conflictVersion.value;
    conflictVersion.value = null;
    conflictText.value = null;
    saveTranslation();
  }

  function reloadAfterConflict(): void {
    if (conflictText.value) hydrateEditor(conflictText.value);
  }

  function requestSelection(id: number): void {
    navigateAfterSave(() => options.onSelect(id));
  }

  function closeEditor(): void {
    navigateAfterSave(() => options.onClose());
  }

  // Leaving a string never loses its edits: a dirty editor saves first, and a
  // navigation requested while a save is already in flight waits for it.
  function navigateAfterSave(navigate: () => void): void {
    if (saveState.value === "saving") {
      deferredNavigation = navigate;
      return;
    }
    if (dirty.value && options.canEdit()) saveTranslation(false, navigate);
    else navigate();
  }

  function selectRelative(direction: "previous" | "next"): void {
    const target = direction === "previous" ? previousText.value : nextText.value;
    if (target) {
      requestSelection(target.id);
    } else if (direction === "next" && options.hasMore()) {
      advanceAfterLoad = true;
      options.onLoadMore();
    }
  }

  function translateText(id: number): void {
    if (translating.value) return;
    translating.value = true;

    // The reply hydrates the editor only while the translated row is the one
    // open: a translator can move on (or a queued click can) before it lands.
    const translate = () => {
      live.pushEvent(
        "translate_single",
        { id },
        (response: SaveResponse) => {
          translating.value = false;
          if (options.selectedText()?.id !== id) return;
          if (response?.ok && response.text) hydrateEditor(response.text);
          else if (!response?.ok) {
            saveState.value = "error";
            saveError.value = response?.error || "translation_failed";
          }
        },
        () => {
          translating.value = false;
          if (options.selectedText()?.id !== id) return;
          saveState.value = "error";
          saveError.value = "translation_failed";
        },
      );
    };

    if (dirty.value && options.selectedText()) {
      saveTranslation(false, translate, () => (translating.value = false));
    } else {
      translate();
    }
  }

  return {
    translatedText,
    status,
    translatorNotes,
    voStatus,
    saveState,
    saveError,
    translating,
    dirty,
    placeholderIssue,
    finalUnavailable,
    currentIndex,
    previousText,
    nextText,
    canAdvance,
    saveTranslation,
    confirmStillCorrect,
    retryAfterConflict,
    reloadAfterConflict,
    requestSelection,
    closeEditor,
    selectRelative,
    translateText,
  };
}

interface EditorValues {
  translatedText: string;
  status: string;
  translatorNotes: string;
  voStatus: string;
  lockVersion: number;
}

function editorValues(text: SelectedText | null | undefined): EditorValues {
  if (!text) {
    return {
      translatedText: "",
      status: "pending",
      translatorNotes: "",
      voStatus: "none",
      lockVersion: 1,
    };
  }
  return {
    translatedText: text.translatedText,
    status: text.status,
    translatorNotes: text.translatorNotes,
    voStatus: text.voStatus,
    lockVersion: text.lockVersion,
  };
}

function frequencies(items: string[]): Map<string, number> {
  const result = new Map<string, number>();
  for (const item of items) result.set(item, (result.get(item) ?? 0) + 1);
  return result;
}

function difference(left: Map<string, number>, right: Map<string, number>): string[] {
  const result: string[] = [];
  for (const [item, count] of left) {
    for (let i = 0; i < Math.max(0, count - (right.get(item) ?? 0)); i += 1) result.push(item);
  }
  return result;
}
