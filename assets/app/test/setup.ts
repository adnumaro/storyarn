import { reactive } from "vue";
import { vi } from "vitest";
import { createApp, defineComponent, type App } from "vue";
import type { LiveInterface } from "@composables/useLive";

/**
 * Create a mock LiveInterface with vi.fn() spies on all methods.
 * Pass initial props to pre-populate the reactive props object.
 */
export function createMockLive(
  initialProps: Record<string, unknown> = {},
): LiveInterface & { _props: Record<string, unknown> } {
  const props = reactive({ ...initialProps });

  return {
    pushEvent: vi.fn(),
    handleEvent: vi.fn(),
    upload: vi.fn(),
    _props: props,
  };
}

/**
 * Run a composable inside a minimal Vue app and return its result.
 * Useful for testing composables that call getCurrentInstance().
 */
export function withSetup<T>(
  composable: () => T,
  options?: { live?: LiveInterface },
): { result: T; app: App } {
  let result!: T;

  const TestComponent = defineComponent({
    setup() {
      result = composable();
      return () => null;
    },
  });

  const app = createApp(TestComponent);

  if (options?.live) {
    app.config.globalProperties.$live = options.live;
  }

  app.mount(document.createElement("div"));

  return { result, app };
}
