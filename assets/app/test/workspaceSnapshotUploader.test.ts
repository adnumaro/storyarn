import { describe, expect, it, vi } from "vitest";
import { createWorkspaceSnapshotUploader } from "../../js/utils/workspace_snapshot_uploader";

type Callback = (detail?: Record<string, unknown>) => void;

function fakeRequest() {
  const listeners: Record<string, Callback> = {};
  const xhr = {
    status: 0,
    open: vi.fn(),
    setRequestHeader: vi.fn(),
    send: vi.fn(),
    abort: vi.fn(),
    upload: {
      addEventListener: (event: string, callback: Callback) =>
        (listeners[`upload:${event}`] = callback),
    },
    addEventListener: (event: string, callback: Callback) => (listeners[event] = callback),
    emit: (event: string, detail = {}) => listeners[event]?.(detail),
  };
  return xhr;
}

function entry(ref: string, importId: number) {
  return {
    ref,
    file: new Blob(["zip"]),
    meta: {
      import_id: importId,
      url: "https://uploads.example/snapshot.zip",
      headers: { "content-type": "application/zip" },
    },
    progress: vi.fn(),
    error: vi.fn(),
  };
}

describe("workspace snapshot external uploader", () => {
  it("publishes 100 only after 2xx and aborts without reporting a client error", () => {
    const requests: ReturnType<typeof fakeRequest>[] = [];
    const { abortUpload, uploader } = createWorkspaceSnapshotUploader(() => {
      const xhr = fakeRequest();
      requests.push(xhr);
      return xhr as unknown as XMLHttpRequest;
    });
    const successful = entry("one", 11);
    const failed = entry("two", 12);
    const cancelled = entry("three", 13);

    uploader([successful, failed, cancelled], vi.fn());
    requests[0].emit("upload:progress", { lengthComputable: true, loaded: 10, total: 10 });
    expect(successful.progress).toHaveBeenLastCalledWith(99);
    requests[0].status = 204;
    requests[0].emit("load");
    expect(successful.progress).toHaveBeenLastCalledWith(100);

    requests[1].status = 500;
    requests[1].emit("load");
    expect(failed.error).toHaveBeenCalledWith("upload_failed");

    abortUpload({ import_id: 13 });
    expect(requests[2].abort).toHaveBeenCalledOnce();
    requests[2].emit("error");
    expect(cancelled.error).not.toHaveBeenCalled();
  });
});
