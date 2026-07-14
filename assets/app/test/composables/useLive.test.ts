import { defineComponent } from "vue";
import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import { useLive, type LiveInterface } from "../../shared/composables/useLive";
import { createMockLive } from "../setup";

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
});
