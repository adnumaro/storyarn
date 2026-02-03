/**
 * BannerUpload hook for handling page banner file selection
 *
 * Reads the selected file and sends it as base64 to the server.
 */
export const BannerUpload = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file type
      if (!file.type.startsWith("image/")) {
        alert("Please select an image file.");
        return;
      }

      // Validate file size (max 10MB for banners)
      const maxSize = 10 * 1024 * 1024;
      if (file.size > maxSize) {
        alert("Image must be less than 10MB.");
        return;
      }

      // Read file as base64
      const reader = new FileReader();
      reader.onload = (event) => {
        const base64 = event.target.result;
        const pageId = this.el.dataset.pageId;
        const target = this.el.dataset.target;

        const payload = {
          page_id: pageId,
          filename: file.name,
          content_type: file.type,
          data: base64,
        };

        if (target) {
          this.pushEventTo(target, "upload_banner", payload);
        } else {
          this.pushEvent("upload_banner", payload);
        }
      };
      reader.readAsDataURL(file);

      // Reset input so same file can be selected again
      e.target.value = "";
    });
  },
};
