import { setupFileUpload } from "../utils/file_upload_handler";

/**
 * GalleryUpload hook for handling gallery block image selection.
 * Supports multiple file selection and sends each as base64 to the server.
 */
export const GalleryUpload = {
  mounted() {
    this._cleanup = setupFileUpload(this, {
      acceptTypes: ["image/"],
      maxSize: 20 * 1024 * 1024,
      eventName: "upload_gallery_image",
      errorEventName: "upload_gallery_validation_error",
      multiple: true,
      extraPayload: () => ({ block_id: this.el.dataset.blockId }),
      typeErrorMessage: "Please select image files.",
      sizeErrorMessage: "Each image must be less than 20MB.",
    });
  },
  destroyed() {
    this._cleanup?.();
  },
};
