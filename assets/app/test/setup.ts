import { reactive } from "vue";
import { vi } from "vitest";
import { createApp, defineComponent, type App } from "vue";
import { config } from "@vue/test-utils";
import { createI18n } from "vue-i18n";
import type { LiveInterface } from "../shared/composables/useLive";

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

// Load the same locale tree as the browser app so interaction tests can
// exercise translated workflows instead of silently falling back to English.
type LocaleModule = { default?: JsonLocale };
const localeModules: Record<string, LocaleModule> = import.meta.glob("../locales/*/*.json", {
  eager: true,
});

const messages: Record<string, JsonLocale> = {};
for (const path in localeModules) {
  const locale = path.match(/\/locales\/([^/]+)\//)?.[1];
  if (!locale) continue;

  const content = localeModules[path].default ?? (localeModules[path] as JsonLocale);
  Object.assign((messages[locale] ??= {}), content);
}

const i18n = createI18n({
  legacy: false,
  locale: "en",
  fallbackLocale: "en",
  missing: (_locale, key) => key,
  messages,
});
config.global.plugins.push(i18n);

export function setTestLocale(locale: string): void {
  (i18n.global.locale as unknown as { value: string }).value = locale;
}

export function registerTestLocale(locale: string): void {
  const globalI18n = i18n.global as unknown as {
    availableLocales: string[];
    setLocaleMessage: (targetLocale: string, messages: JsonLocale) => void;
  };

  if (!globalI18n.availableLocales.includes(locale)) {
    globalI18n.setLocaleMessage(locale, {});
  }
}

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
    removeHandleEvent: vi.fn(),
    upload: vi.fn(),
    _props: props,
  };
}

/**
 * Create a mock matching LiveVue's real hook shape, including its Promise
 * pushEvent overload. Keep this separate from createMockLive so tests for
 * callback-only adapters can continue exercising that compatibility path.
 */
export function createPromiseMockLive(
  initialProps: Record<string, unknown> = {},
  pushEvent: (...args: unknown[]) => unknown = vi.fn(() => Promise.resolve({})),
): LiveInterface & { _props: Record<string, unknown> } {
  return {
    ...createMockLive(initialProps),
    liveSocket: {},
    pushEvent,
  } as unknown as LiveInterface & { _props: Record<string, unknown> };
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
