import { setupFileUpload } from "../utils/file_upload_handler";

/**
 * AssetUpload hook for handling file uploads on the Assets page.
 *
 * Accepts image/* and audio/* files. Validates type and size (max 20MB),
 * reads the file as base64, and pushes it to the LiveView.
 */
export const AssetUpload = {
  mounted() {
    this._cleanup = setupFileUpload(this, {
      acceptTypes: ["image/", "audio/"],
      maxSize: 20 * 1024 * 1024,
      eventName: "upload_asset",
      errorEventName: "upload_validation_error",
      startedEventName: "upload_started",
      typeErrorMessage: "Please select an image or audio file.",
    });
  },
  destroyed() {
    this._cleanup?.();
  },
};
