import { flushPromises } from "@vue/test-utils";
import type { App } from "vue";
import { useSequenceImageImport } from "@modules/flows/editor/composables/useSequenceImageImport";
import { withSetup } from "../../../setup";

interface UploadedAsset {
  id: number;
  url: string;
}

const uploadFile = vi.fn<(file: File, purpose: string) => Promise<UploadedAsset | null>>();
vi.mock("@shared/composables/useUpload", () => ({ useUpload: () => ({ uploadFile }) }));
vi.mock("vue-i18n", async (importOriginal) => ({
  ...(await importOriginal<typeof import("vue-i18n")>()),
  useI18n: () => ({
    t: (key: string, params?: { name: string }) => (params ? `${key}: ${params.name}` : key),
  }),
}));

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

function image(name: string, type = "image/png") {
  return new File(["image bytes"], name, { type });
}

const mountedApps = new Set<App>();

function setup(canUpload: () => boolean = () => true) {
  const { result, app } = withSetup(() => useSequenceImageImport(canUpload));
  mountedApps.add(app);
  return {
    api: result,
    unmount: () => {
      app.unmount();
      mountedApps.delete(app);
    },
  };
}

describe("useSequenceImageImport", () => {
  beforeEach(() => uploadFile.mockReset());
  afterEach(() => {
    for (const app of mountedApps) app.unmount();
    mountedApps.clear();
  });

  it("uploads sequentially with purpose=image and waits for each attachment before continuing", async () => {
    const firstUpload = deferred<UploadedAsset>();
    const secondUpload = deferred<UploadedAsset>();
    const attachment = deferred<void>();
    uploadFile.mockReturnValueOnce(firstUpload.promise).mockReturnValueOnce(secondUpload.promise);
    const onUploaded = vi.fn().mockReturnValueOnce(attachment.promise);
    const { api } = setup();
    const first = image("hero.png");
    const second = image("room.webp", "image/webp");
    const importing = api.importImages([first, second], onUploaded);

    expect(api.importing.value).toBe(true);
    expect(api.fileName.value).toBe("hero.png");
    expect(uploadFile).toHaveBeenCalledExactlyOnceWith(first, "image");
    firstUpload.resolve({ id: 101, url: "/media/assets/101" });
    await flushPromises();
    expect(onUploaded).toHaveBeenCalledExactlyOnceWith({
      id: 101,
      url: "/media/assets/101",
      filename: "hero.png",
    });
    expect(uploadFile).toHaveBeenCalledOnce();

    attachment.resolve();
    await flushPromises();
    expect(api.fileName.value).toBe("room.webp");
    expect(uploadFile).toHaveBeenNthCalledWith(2, second, "image");
    secondUpload.resolve({ id: 202, url: "/media/assets/202" });
    await importing;
    expect(onUploaded).toHaveBeenNthCalledWith(2, {
      id: 202,
      url: "/media/assets/202",
      filename: "room.webp",
    });
    expect(api.importing.value).toBe(false);
    expect(api.fileName.value).toBe("");
    expect(api.errors.value).toEqual([]);
  });

  it("rejects unsupported formats without uploading them and continues with supported images", async () => {
    uploadFile.mockResolvedValue({ id: 1, url: "/media/assets/1" });
    const { api } = setup();
    const onUploaded = vi.fn();
    const rejected = [
      image("vector.svg", "image/svg+xml"),
      image("photo.avif", "image/avif"),
      image("notes.txt", "text/plain"),
      image("unknown.png", ""),
    ];
    const accepted = [image("portrait.jpg", "image/jpeg"), image("pose.gif", "image/gif")];
    await api.importImages([...rejected, ...accepted], onUploaded);

    expect(uploadFile.mock.calls.map(([file]) => file)).toEqual(accepted);
    expect(api.errors.value).toEqual(
      rejected.map((file) => `flows.sequence_library.unsupported_image: ${file.name}`),
    );
    expect(onUploaded).toHaveBeenCalledTimes(2);
    expect(api.importing.value).toBe(false);
  });

  it("reports individual upload and attachment failures while importing the remaining files", async () => {
    uploadFile
      .mockRejectedValueOnce(new Error("Connection lost"))
      .mockResolvedValueOnce({ id: 2, url: "/media/assets/2" })
      .mockResolvedValueOnce({ id: 3, url: "/media/assets/3" });
    const onUploaded = vi.fn().mockRejectedValueOnce(new Error("Layer not saved"));
    const { api } = setup();
    await api.importImages([image("failed.png"), image("layer.png"), image("ok.png")], onUploaded);

    expect(uploadFile).toHaveBeenCalledTimes(3);
    expect(onUploaded).toHaveBeenLastCalledWith({
      id: 3,
      url: "/media/assets/3",
      filename: "ok.png",
    });
    expect(api.errors.value).toEqual(["failed.png: Connection lost", "layer.png: Layer not saved"]);
    expect(api.importing.value).toBe(false);

    uploadFile.mockResolvedValueOnce({ id: 4, url: "/media/assets/4" });
    await api.importImages([image("retry.png")], onUploaded);
    expect(api.errors.value).toEqual([]);
  });

  it("ignores a second import while an upload is in progress", async () => {
    const pending = deferred<UploadedAsset>();
    uploadFile.mockReturnValue(pending.promise);
    const { api } = setup();
    const firstCallback = vi.fn();
    const secondCallback = vi.fn();
    const importing = api.importImages([image("first.png")], firstCallback);
    await api.importImages([image("second.png")], secondCallback);

    expect(uploadFile).toHaveBeenCalledOnce();
    expect(api.importing.value).toBe(true);
    expect(api.fileName.value).toBe("first.png");
    pending.resolve({ id: 1, url: "/media/assets/1" });
    await importing;
    expect(firstCallback).toHaveBeenCalledOnce();
    expect(secondCallback).not.toHaveBeenCalled();
  });

  it("discards a completed upload and its remaining queue after unmount", async () => {
    const pending = deferred<UploadedAsset>();
    uploadFile.mockReturnValue(pending.promise);
    const { api, unmount } = setup();
    const onUploaded = vi.fn();
    const importing = api.importImages([image("first.png"), image("queued.png")], onUploaded);
    unmount();
    pending.resolve({ id: 1, url: "/media/assets/1" });
    await importing;
    await api.importImages([image("after-unmount.png")], onUploaded);

    expect(uploadFile).toHaveBeenCalledOnce();
    expect(onUploaded).not.toHaveBeenCalled();
    expect(api.importing.value).toBe(false);
    expect(api.fileName.value).toBe("");
  });

  it("stops the queue when unmounted while an attachment callback is pending", async () => {
    const attachment = deferred<void>();
    uploadFile.mockResolvedValue({ id: 1, url: "/media/assets/1" });
    const onUploaded = vi.fn().mockReturnValue(attachment.promise);
    const { api, unmount } = setup();
    const importing = api.importImages([image("first.png"), image("queued.png")], onUploaded);
    await flushPromises();
    expect(onUploaded).toHaveBeenCalledOnce();
    unmount();
    attachment.resolve();
    await importing;

    expect(uploadFile).toHaveBeenCalledOnce();
    expect(onUploaded).toHaveBeenCalledOnce();
  });

  it("blocks new uploads after permission changes but registers an asset already uploaded", async () => {
    let allowed = false;
    const pending = deferred<UploadedAsset>();
    uploadFile.mockReturnValue(pending.promise);
    const { api } = setup(() => allowed);
    const onUploaded = vi.fn();
    await api.importImages([image("blocked.png")], onUploaded);
    expect(uploadFile).not.toHaveBeenCalled();
    expect(api.importing.value).toBe(false);

    allowed = true;
    const importing = api.importImages([image("first.png"), image("queued.png")], onUploaded);
    allowed = false;
    pending.resolve({ id: 1, url: "/media/assets/1" });
    await importing;

    expect(uploadFile).toHaveBeenCalledOnce();
    expect(onUploaded).toHaveBeenCalledExactlyOnceWith({
      id: 1,
      url: "/media/assets/1",
      filename: "first.png",
    });
    expect(api.importing.value).toBe(false);
    expect(api.errors.value).toEqual([]);
  });
});
