import { createLiveVue, findComponent } from "live_vue";
import type { SetupContext } from "live_vue";
import { h } from "vue";
import type { App, Component } from "vue";
import VueKonva from "vue-konva";
import { i18n } from "./i18n";

let appCounter = 0;

// Keep i18n locale synced with html lang attribute across LiveView navigations
const syncLocale = (): void => {
  if (i18n.global && i18n.global.locale) {
    (i18n.global.locale as unknown as { value: string }).value =
      document.documentElement.lang || "en";
  }
};

const observer = new MutationObserver((mutations: MutationRecord[]) => {
  for (const m of mutations) {
    if (m.attributeName === "lang") syncLocale();
  }
});
observer.observe(document.documentElement, { attributes: true });

export default createLiveVue({
  resolve: (name: string) => {
    const components: Record<string, { default: Component } | Component> = {
      ...import.meta.glob("./**/*.vue", { eager: true }),
      ...import.meta.glob("../../lib/**/*.vue", { eager: true }),
    };
    return findComponent(components, name);
  },
  setup: ({ createApp, component, props, slots, plugin, el }: SetupContext): App => {
    syncLocale();
    const app = createApp({ render: () => h(component, props, slots) });
    app.config.idPrefix = `vue-${appCounter++}`;
    // Suppress vue-konva false-positive warnings about event listeners on v-group/v-layer
    // vue-konva handles Konva events internally via .on() — Vue's attribute inheritance doesn't apply
    const origWarn = app.config.warnHandler;
    app.config.warnHandler = (msg: string, vm, trace: string) => {
      if (msg.includes("Extraneous non-emits event listeners")) return;
      if (origWarn) origWarn(msg, vm, trace);
      else console.warn(`[Vue warn]: ${msg}${trace}`);
    };
    app.use(plugin);
    app.use(VueKonva);
    app.use(i18n);
    app.mount(el);
    return app;
  },
});
