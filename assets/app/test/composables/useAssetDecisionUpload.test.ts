import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises } from "@vue/test-utils";
import { withSetup } from "../setup";
import { useAssetDecisionUpload } from "@shared/composables/useAssetDecisionUpload";

describe("useAssetDecisionUpload", () => {
  it("keeps state isolated between consumers", () => {
    const first = useAssetDecisionUpload();
    const second = useAssetDecisionUpload();

    first.progress.value = 75;
    first.error.value = "first upload failed";

    expect(second.progress.value).toBe(0);
    expect(second.error.value).toBeNull();
  });
});

describe("image preparation", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    window.history.replaceState({}, "", "/");
  });

  function prepare() {
    window.history.replaceState({}, "", "/workspaces/w/projects/p/flows/1");
    vi.stubGlobal("crypto", { subtle: { digest: vi.fn().mockResolvedValue(new ArrayBuffer(32)) } });
    vi.stubGlobal(
      "URL",
      class extends URL {
        static createObjectURL() {
          return "blob:test";
        }
        static revokeObjectURL() {}
      },
    );
    vi.stubGlobal(
      "Image",
      class {
        naturalWidth = 4000;
        naturalHeight = 3000;
        onload: (() => void) | null = null;
        set src(_value: string) {
          queueMicrotask(() => this.onload?.());
        }
      },
    );
    let completeMaterialization!: () => void;
    const materialization = new Promise((resolve) => {
      completeMaterialization = () =>
        resolve({ ok: true, json: async () => ({ id: 99, url: "/media/assets/99" }) });
    });
    const fetch = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          action: "create_variant_from_existing_original",
          source_exists: true,
          variant_exists: false,
          requires_variant: true,
          variant_profile: "scene_background_web",
          target: null,
          asset_id: null,
        }),
      })
      .mockImplementationOnce(() => materialization);
    vi.stubGlobal("fetch", fetch);
    const file = new File(["png"], "large.png", { type: "image/png" });
    Object.defineProperty(file, "arrayBuffer", { value: async () => new ArrayBuffer(3) });
    const { result, app } = withSetup(() => useAssetDecisionUpload());
    return { file, fetch, api: result, app, completeMaterialization };
  }

  it("waits for confirmation and returns the prepared web asset for the Scenes profile", async () => {
    const { file, fetch, api, app, completeMaterialization } = prepare();
    try {
      const upload = api.uploadWithDecision(file, "scene_background");
      await flushPromises();
      expect(api.dialog.value).toMatchObject({ requiresVariant: true, fileName: "large.png" });
      expect(fetch).toHaveBeenCalledTimes(1);
      api.confirmDecision();
      await flushPromises();
      expect(api.uploading.value).toBe(true);
      expect(api.dialog.value).not.toBeNull();
      completeMaterialization();
      await expect(upload).resolves.toEqual({ id: 99, url: "/media/assets/99" });
      expect(fetch).toHaveBeenLastCalledWith(
        expect.stringContaining("/upload/materialize"),
        expect.objectContaining({ body: expect.stringContaining('"purpose":"scene_background"') }),
      );
      expect(api.dialog.value).toBeNull();
    } finally {
      app.unmount();
    }
  });

  it("cancels pending preparation when its editor closes", async () => {
    const { file, fetch, api, app } = prepare();
    const upload = api.uploadWithDecision(file, "scene_background");
    await flushPromises();
    expect(api.dialog.value).not.toBeNull();
    app.unmount();
    await expect(upload).resolves.toBeNull();
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});
