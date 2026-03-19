import { pushWithTarget } from "./event_dispatcher";

/**
 * Sets up a file upload handler on a hook's element.
 * Handles file type validation, size validation, base64 reading, and event dispatching.
 *
 * @param {Object} hook - The LiveView hook instance
 * @param {Object} config - Configuration options
 * @param {string[]} config.acceptTypes - Accepted MIME type prefixes (e.g., ["image/", "audio/"])
 * @param {number} config.maxSize - Maximum file size in bytes
 * @param {string} config.eventName - Event name to push on successful read
 * @param {string} [config.errorEventName] - Event name for validation errors
 * @param {string} [config.startedEventName] - Event name pushed before reading begins
 * @param {Function} [config.buildPayload] - Custom payload builder: (file, base64Data) => payload
 * @param {Function} [config.extraPayload] - Returns extra fields merged into all payloads: () => object
 * @param {string} [config.sizeErrorMessage] - Custom size error message
 * @param {string} [config.typeErrorMessage] - Custom type error message
 * @param {boolean} [config.multiple] - If true, reads all selected files (pushes one event per file)
 * @param {Object} [config.optimizationWarning] - Show warning before uploading files that need optimization
 * @param {string} config.optimizationWarning.modalId - ID of the modal element to show
 * @param {Function} config.optimizationWarning.checkFn - (file) => boolean, returns true if file needs optimization
 * @param {string} config.optimizationWarning.storageKey - localStorage key for "don't show again"
 * @returns {Function} Cleanup function to remove the event listener
 */
export function setupFileUpload(hook, config) {
  const {
    acceptTypes,
    maxSize,
    eventName,
    errorEventName = null,
    startedEventName = null,
    buildPayload = null,
    extraPayload = null,
    sizeErrorMessage = null,
    typeErrorMessage = null,
    multiple = false,
    optimizationWarning = null,
  } = config;

  const processFile = (file, extra) => {
    // Type validation
    const typeMatch = acceptTypes.some((type) => file.type.startsWith(type));
    if (!typeMatch) {
      const msg = typeErrorMessage || `Invalid file type. Accepted: ${acceptTypes.join(", ")}`;
      if (errorEventName) {
        pushWithTarget(hook, errorEventName, { message: msg, ...extra });
      }
      return;
    }

    // Size validation
    if (file.size > maxSize) {
      const maxMB = Math.round(maxSize / (1024 * 1024));
      const msg = sizeErrorMessage || `File must be less than ${maxMB}MB.`;
      if (errorEventName) {
        pushWithTarget(hook, errorEventName, { message: msg, ...extra });
      }
      return;
    }

    // Read file as base64
    const reader = new FileReader();
    reader.onload = (evt) => {
      const payload = buildPayload
        ? buildPayload(file, evt.target.result)
        : {
            filename: file.name,
            content_type: file.type,
            data: evt.target.result,
            ...extra,
          };

      pushWithTarget(hook, eventName, payload);
    };

    reader.onerror = () => {
      if (errorEventName) {
        pushWithTarget(hook, errorEventName, {
          message: "Failed to read file.",
          ...extra,
        });
      }
    };

    reader.readAsDataURL(file);
  };

  const processFiles = (files, extra) => {
    if (startedEventName) {
      pushWithTarget(hook, startedEventName, extra);
    }

    if (multiple) {
      for (const file of files) {
        processFile(file, extra);
      }
    } else {
      processFile(files[0], extra);
    }
  };

  const needsWarning = (files) => {
    if (!optimizationWarning) return false;
    if (localStorage.getItem(optimizationWarning.storageKey)) return false;
    return Array.from(files).some((f) => optimizationWarning.checkFn(f));
  };

  const showWarningModal = (files, extra, inputEl) => {
    const modal = document.getElementById(optimizationWarning.modalId);
    if (!modal || !(modal instanceof HTMLDialogElement)) {
      processFiles(files, extra);
      inputEl.value = "";
      return;
    }

    modal.showModal();

    const confirmBtn = modal.querySelector("[data-proceed-upload]");
    const cancelBtn = modal.querySelector("[data-cancel-upload]");
    const checkbox = modal.querySelector("[data-skip-warning]");

    const cleanup = () => {
      confirmBtn?.removeEventListener("click", onConfirm);
      cancelBtn?.removeEventListener("click", onCancel);
      modal.removeEventListener("close", onClose);
      inputEl.value = "";
    };

    const onConfirm = () => {
      if (checkbox?.checked) {
        localStorage.setItem(optimizationWarning.storageKey, "true");
      }
      modal.close();
      cleanup();
      processFiles(files, extra);
    };

    const onCancel = () => {
      modal.close();
      cleanup();
    };

    // Handles ESC key and backdrop clicks
    const onClose = () => {
      cleanup();
    };

    confirmBtn?.addEventListener("click", onConfirm);
    cancelBtn?.addEventListener("click", onCancel);
    modal.addEventListener("close", onClose);
  };

  const handleChange = (e) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    const extra = extraPayload ? extraPayload() : {};

    if (needsWarning(files)) {
      showWarningModal(files, extra, e.target);
    } else {
      processFiles(files, extra);
      // Reset input so same file can be selected again
      e.target.value = "";
    }
  };

  hook.el.addEventListener("change", handleChange);

  // Return cleanup function
  return () => {
    hook.el.removeEventListener("change", handleChange);
  };
}
