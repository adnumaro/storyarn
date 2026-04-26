import { reactive } from "vue";
import { vi } from "vitest";
import { createApp, defineComponent, type App } from "vue";
import { config } from "@vue/test-utils";
import { createI18n } from "vue-i18n";
import type { LiveInterface } from "@composables/useLive";

// Nested JSON locale shape — string leaves, object branches. Matches what
// our `assets/app/locales/en/*.json` files actually contain. We don't use
// vue-i18n's `LocaleMessageDictionary` because its generic is keyed on a
// schema we don't enforce in tests; we just want a type vue-i18n's
// `createI18n` accepts (it does, via `Record<string, any>` in messages).
type JsonLocale = { [key: string]: string | JsonLocale };

// jsdom doesn't implement scrollIntoView; reka-ui's Listbox/Command primitives
// call it on highlighted elements and surface unhandled rejections that
// otherwise stay quiet but show up in vitest output.
if (typeof Element !== "undefined" && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {
    /* no-op for jsdom */
  };
}

// Load all English locale files for component tests
type LocaleModule = { default?: JsonLocale };
const localeModules: Record<string, LocaleModule> = import.meta.glob(
  "../locales/en/*.json",
  { eager: true },
);

const enMessages: JsonLocale = {};
for (const path in localeModules) {
  const content = localeModules[path].default ?? (localeModules[path] as JsonLocale);
  Object.assign(enMessages, content);
}

const i18n = createI18n({
  legacy: false,
  locale: "en",
  fallbackLocale: "en",
  missing: (_locale, key) => key,
  messages: { en: enMessages },
});
config.global.plugins.push(i18n);

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
