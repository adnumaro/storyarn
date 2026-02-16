/**
 * AudioUpload hook for handling audio file selection in the AudioPicker.
 *
 * Validates file type (audio/*) and size (max 20MB), reads the file as
 * base64, and pushes it to the LiveComponent via pushEventTo.
 */
export const AudioUpload = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (!file) return;

      const target = this.el.dataset.target;
      const nodeId = this.el.dataset.nodeId;
      const extra = nodeId ? { node_id: nodeId } : {};

      // Validate file type
      if (!file.type.startsWith("audio/")) {
        this._pushEvent(target, "upload_validation_error", {
          message: "Please select an audio file.",
          ...extra,
        });
        e.target.value = "";
        return;
      }

      // Validate file size (max 20MB)
      const maxSize = 20 * 1024 * 1024;
      if (file.size > maxSize) {
        this._pushEvent(target, "upload_validation_error", {
          message: "Audio file must be less than 20MB.",
          ...extra,
        });
        e.target.value = "";
        return;
      }

      // Show loading state
      this._pushEvent(target, "upload_started", extra);

      // Read file as base64
      const reader = new FileReader();
      reader.onload = (event) => {
        this._pushEvent(target, "upload_audio", {
          filename: file.name,
          content_type: file.type,
          data: event.target.result,
          ...extra,
        });
      };
      reader.onerror = () => {
        this._pushEvent(target, "upload_validation_error", {
          message: "Failed to read file.",
          ...extra,
        });
      };
      reader.readAsDataURL(file);

      // Reset input so same file can be selected again
      e.target.value = "";
    });
  },

  _pushEvent(target, event, payload) {
    if (target) {
      this.pushEventTo(target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },
};
