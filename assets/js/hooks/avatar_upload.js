/**
 * AvatarUpload hook for handling sheet avatar file selection
 *
 * Reads the selected file and sends it as base64 to the server.
 */
export const AvatarUpload = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file type
      if (!file.type.startsWith("image/")) {
        const target = this.el.dataset.target;
        if (target) {
          this.pushEventTo(target, "upload_validation_error", { message: "Please select an image file." });
        } else {
          this.pushEvent("upload_validation_error", { message: "Please select an image file." });
        }
        return;
      }

      // Validate file size (max 5MB)
      const maxSize = 5 * 1024 * 1024;
      if (file.size > maxSize) {
        const target = this.el.dataset.target;
        if (target) {
          this.pushEventTo(target, "upload_validation_error", { message: "Image must be less than 5MB." });
        } else {
          this.pushEvent("upload_validation_error", { message: "Image must be less than 5MB." });
        }
        return;
      }

      // Read file as base64
      const reader = new FileReader();
      reader.onload = (event) => {
        const base64 = event.target.result;
        const sheetId = this.el.dataset.sheetId;
        const target = this.el.dataset.target;

        const payload = {
          sheet_id: sheetId,
          filename: file.name,
          content_type: file.type,
          data: base64,
        };

        if (target) {
          this.pushEventTo(target, "upload_avatar", payload);
        } else {
          this.pushEvent("upload_avatar", payload);
        }
      };
      reader.readAsDataURL(file);

      // Reset input so same file can be selected again
      e.target.value = "";
    });
  },
};
