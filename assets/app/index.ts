import { createLiveVue, findComponent } from "live_vue";
import type { ComponentMap, SetupContext } from "live_vue";
import { defineAsyncComponent, h } from "vue";
import type { App, Component } from "vue";
import VueKonva from "vue-konva";
import { i18n } from "./i18n";
import PublicContact from "./live/public/contact/PublicContact.vue";
import PublicLanding from "./live/public/landing/PublicLanding.vue";
import LegalPage from "./live/public/legal/LegalPage.vue";

let appCounter = 0;

type ComponentLoader = () => Promise<{ default: Component }>;

const componentLoaders = {
  ...import.meta.glob<{ default: Component }>([
    "./**/*.vue",
    "!./live/public/contact/PublicContact.vue",
    "!./live/public/landing/PublicLanding.vue",
    "!./live/public/legal/LegalPage.vue",
    "!./components/navigation/LiveLink.vue",
    "!./components/ui/button/Button.vue",
    "!./modules/public/landing/sections/cta/CtaSignup.vue",
  ]),
  ...import.meta.glob<{ default: Component }>("../../lib/**/*.vue"),
} satisfies Record<string, ComponentLoader>;

const asyncComponents = new Map<string, Component>();

// These pages share the SSR public shell and are common navigation targets.
// Resolving them synchronously prevents an empty async-component frame while
// LiveView moves between the journal and the marketing pages.
const eagerPublicComponents = new Map<string, Component>([
  ["live/public/contact/PublicContact", PublicContact],
  ["live/public/landing/PublicLanding", PublicLanding],
  ["live/public/legal/LegalPage", LegalPage],
]);

const resolveAsyncComponent = (name: string): Component => {
  let component = asyncComponents.get(name);

  if (!component) {
    const loader = findComponent(
      componentLoaders as unknown as ComponentMap,
      name,
    ) as unknown as ComponentLoader;
    component = defineAsyncComponent(loader);
    asyncComponents.set(name, component);
  }

  return component;
};

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
    return eagerPublicComponents.get(name) ?? resolveAsyncComponent(name);
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
