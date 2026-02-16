/**
 * AssetUpload hook for handling file uploads on the Assets page.
 *
 * Accepts image/* and audio/* files. Validates type and size (max 20MB),
 * reads the file as base64, and pushes it to the LiveView.
 */
export const AssetUpload = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file type
      if (!file.type.startsWith("image/") && !file.type.startsWith("audio/")) {
        this.pushEvent("upload_validation_error", {
          message: "Please select an image or audio file.",
        });
        e.target.value = "";
        return;
      }

      // Validate file size (max 20MB)
      const maxSize = 20 * 1024 * 1024;
      if (file.size > maxSize) {
        this.pushEvent("upload_validation_error", {
          message: "File must be less than 20MB.",
        });
        e.target.value = "";
        return;
      }

      // Show loading state
      this.pushEvent("upload_started", {});

      // Read file as base64
      const reader = new FileReader();
      reader.onload = (event) => {
        this.pushEvent("upload_asset", {
          filename: file.name,
          content_type: file.type,
          data: event.target.result,
        });
      };
      reader.onerror = () => {
        this.pushEvent("upload_validation_error", {
          message: "Failed to read file.",
        });
      };
      reader.readAsDataURL(file);

      // Reset input so same file can be selected again
      e.target.value = "";
    });
  },
};
