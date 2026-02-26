import { setupFileUpload } from "../utils/file_upload_handler";

/**
 * AvatarUpload hook for handling sheet avatar file selection.
 *
 * Reads the selected file and sends it as base64 to the server.
 */
export const AvatarUpload = {
  mounted() {
    this._cleanup = setupFileUpload(this, {
      acceptTypes: ["image/"],
      maxSize: 5 * 1024 * 1024,
      eventName: "upload_avatar",
      errorEventName: "upload_validation_error",
      typeErrorMessage: "Please select an image file.",
      sizeErrorMessage: "Image must be less than 5MB.",
      buildPayload: (file, base64) => ({
        sheet_id: this.el.dataset.sheetId,
        filename: file.name,
        content_type: file.type,
        data: base64,
      }),
    });
  },
  destroyed() {
    this._cleanup?.();
  },
};
