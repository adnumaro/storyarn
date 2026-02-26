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
  } = config;

  const handleChange = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const extra = extraPayload ? extraPayload() : {};

    // Type validation
    const typeMatch = acceptTypes.some((type) => file.type.startsWith(type));
    if (!typeMatch) {
      const msg =
        typeErrorMessage ||
        `Invalid file type. Accepted: ${acceptTypes.join(", ")}`;
      if (errorEventName) {
        pushWithTarget(hook, errorEventName, { message: msg, ...extra });
      }
      e.target.value = "";
      return;
    }

    // Size validation
    if (file.size > maxSize) {
      const maxMB = Math.round(maxSize / (1024 * 1024));
      const msg = sizeErrorMessage || `File must be less than ${maxMB}MB.`;
      if (errorEventName) {
        pushWithTarget(hook, errorEventName, { message: msg, ...extra });
      }
      e.target.value = "";
      return;
    }

    // Notify upload started
    if (startedEventName) {
      pushWithTarget(hook, startedEventName, extra);
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

    // Reset input so same file can be selected again
    e.target.value = "";
  };

  hook.el.addEventListener("change", handleChange);

  // Return cleanup function
  return () => {
    hook.el.removeEventListener("change", handleChange);
  };
}
