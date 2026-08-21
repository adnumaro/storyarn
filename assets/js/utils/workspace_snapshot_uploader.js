export function createWorkspaceSnapshotUploader(createRequest = () => new XMLHttpRequest()) {
  const requests = new Map();

  const abortUpload = ({ ref, import_id: importId } = {}) => {
    const states = [
      ref && requests.get(`ref:${ref}`),
      importId && requests.get(`import:${importId}`),
    ];
    new Set(states.filter(Boolean)).forEach((state) => state.abort());
  };

  const uploader = (entries, onViewError) => {
    entries.forEach((entry) => {
      const xhr = createRequest();
      const state = { cancelled: false };
      const importKey = entry.meta.import_id ? `import:${entry.meta.import_id}` : null;
      const unregister = () => {
        requests.delete(`ref:${entry.ref}`);
        if (importKey) requests.delete(importKey);
      };
      state.abort = () => {
        state.cancelled = true;
        xhr.abort();
        unregister();
      };

      requests.set(`ref:${entry.ref}`, state);
      if (importKey) requests.set(importKey, state);
      onViewError(state.abort);
      xhr.open("PUT", entry.meta.url, true);
      Object.entries(entry.meta.headers || {}).forEach(([name, value]) =>
        xhr.setRequestHeader(name, value),
      );
      xhr.upload.addEventListener("progress", (event) => {
        if (event.lengthComputable) {
          entry.progress(Math.min(99, Math.floor((event.loaded / event.total) * 100)));
        }
      });
      xhr.addEventListener("load", () => {
        unregister();
        if (!state.cancelled) {
          if (xhr.status >= 200 && xhr.status < 300) entry.progress(100);
          else entry.error("upload_failed");
        }
      });
      xhr.addEventListener("error", () => {
        unregister();
        if (!state.cancelled) entry.error("upload_failed");
      });
      xhr.send(entry.file);
    });
  };

  return { abortUpload, uploader };
}
