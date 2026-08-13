import { defineComponent } from "vue";
import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import { useLive, type LiveInterface } from "../../shared/composables/useLive";
import { createMockLive } from "../setup";

function createPromiseLive(pushEvent: ReturnType<typeof vi.fn>): LiveInterface {
  return {
    ...createMockLive(),
    liveSocket: {},
    pushEvent,
  } as unknown as LiveInterface;
}

describe("useLive", () => {
  it("targets the nearest injected LiveVue hook before the app-global hook", () => {
    const hostLive = createMockLive();
    const injectedLive = createMockLive();
    let live!: LiveInterface;

    const TestComponent = defineComponent({
      setup() {
        live = useLive();
        return () => null;
      },
    });

    mount(TestComponent, {
      global: {
        provide: { _live_vue: injectedLive },
        config: { globalProperties: { $live: hostLive } as never },
      },
    });

    live.pushEvent("import_csv", { content: "csv-content" });

    expect(injectedLive.pushEvent).toHaveBeenCalledWith(
      "import_csv",
      { content: "csv-content" },
      undefined,
    );
    expect(hostLive.pushEvent).not.toHaveBeenCalled();
  });

  it("uses Phoenix's Promise overload to deliver replies when onError is requested", async () => {
    const reply = { ok: true, version: 7 };
    const pushEvent = vi.fn(() => Promise.resolve(reply));
    const callback = vi.fn();
    const onError = vi.fn();
    let live!: LiveInterface;

    const TestComponent = defineComponent({
      setup() {
        live = useLive();
        return () => null;
      },
    });

    const wrapper = mount(TestComponent, {
      global: { provide: { _live_vue: createPromiseLive(pushEvent) } },
    });

    live.pushEvent("preview_restore", { version_number: 7 }, callback, onError);

    expect(pushEvent).toHaveBeenCalledWith("preview_restore", { version_number: 7 });
    await vi.waitFor(() => expect(callback).toHaveBeenCalledWith(reply));
    expect(onError).not.toHaveBeenCalled();

    wrapper.unmount();
  });

  it("forwards asynchronous Phoenix push failures to onError", async () => {
    const error = new Error("socket timeout");
    const pushEvent = vi.fn(() => Promise.reject(error));
    const callback = vi.fn();
    const onError = vi.fn();
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    let live!: LiveInterface;

    const TestComponent = defineComponent({
      setup() {
        live = useLive();
        return () => null;
      },
    });

    const wrapper = mount(TestComponent, {
      global: { provide: { _live_vue: createPromiseLive(pushEvent) } },
    });

    live.pushEvent("preview_restore", { version_number: 8 }, callback, onError);

    await vi.waitFor(() => expect(onError).toHaveBeenCalledWith(error));
    expect(callback).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith(
      '[useLive] pushEvent("preview_restore") dropped:',
      "socket timeout",
    );

    wrapper.unmount();
    warn.mockRestore();
  });
});
