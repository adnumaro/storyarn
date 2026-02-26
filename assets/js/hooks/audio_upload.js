import { setupFileUpload } from "../utils/file_upload_handler";

/**
 * AudioUpload hook for handling audio file selection in the AudioPicker.
 *
 * Validates file type (audio/*) and size (max 20MB), reads the file as
 * base64, and pushes it to the LiveComponent via pushEventTo.
 */
export const AudioUpload = {
  mounted() {
    this._cleanup = setupFileUpload(this, {
      acceptTypes: ["audio/"],
      maxSize: 20 * 1024 * 1024,
      eventName: "upload_audio",
      errorEventName: "upload_validation_error",
      startedEventName: "upload_started",
      typeErrorMessage: "Please select an audio file.",
      sizeErrorMessage: "Audio file must be less than 20MB.",
      extraPayload: () => {
        const nodeId = this.el.dataset.nodeId;
        return nodeId ? { node_id: nodeId } : {};
      },
    });
  },
  destroyed() {
    this._cleanup?.();
  },
};
