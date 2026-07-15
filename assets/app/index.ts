import { createLiveVue, findComponent } from "live_vue";
import type { ComponentMap, SetupContext } from "live_vue";
import { defineAsyncComponent, h } from "vue";
import type { App, Component } from "vue";
import VueKonva from "vue-konva";
import { i18n } from "./i18n";
import AuthForgotPasswordForm from "./live/auth/reset-password/AuthForgotPasswordForm.vue";
import AuthResetPasswordForm from "./live/auth/reset-password/AuthResetPasswordForm.vue";
import AuthLoginForm from "./live/auth/login/AuthLoginForm.vue";
import AuthRegistrationForm from "./live/auth/registration/AuthRegistrationForm.vue";
import AuthLayout from "./live/layouts/auth/Layout.vue";
import DocsLayout from "./live/layouts/docs/Layout.vue";
import PublicContact from "./live/public/contact/PublicContact.vue";
import PublicLanding from "./live/public/landing/PublicLanding.vue";
import LegalPage from "./live/public/legal/LegalPage.vue";
import DocsContent from "./live/docs/show/DocsContent.vue";

let appCounter = 0;

type ComponentLoader = () => Promise<{ default: Component }>;

const componentLoaders = {
  ...import.meta.glob<{ default: Component }>([
    "./**/*.vue",
    "!./components/forms/PasswordInput.vue",
    "!./components/ThemeSelector.vue",
    "!./components/ui/input/Input.vue",
    "!./components/ui/label/Label.vue",
    "!./live/auth/login/AuthLoginForm.vue",
    "!./live/auth/registration/AuthRegistrationForm.vue",
    "!./live/auth/reset-password/AuthForgotPasswordForm.vue",
    "!./live/auth/reset-password/AuthResetPasswordForm.vue",
    "!./live/docs/show/DocsContent.vue",
    "!./live/layouts/auth/Layout.vue",
    "!./live/layouts/docs/Layout.vue",
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

// These are the complete public, docs, and authentication surfaces reachable
// from public navigation. Resolving both their layouts and page components
// synchronously keeps the current LiveView frame populated on a cold cache;
// a background dynamic import alone cannot guarantee that.
const eagerPublicComponents = new Map<string, Component>([
  ["live/auth/login/AuthLoginForm", AuthLoginForm],
  ["live/auth/registration/AuthRegistrationForm", AuthRegistrationForm],
  ["live/auth/reset-password/AuthForgotPasswordForm", AuthForgotPasswordForm],
  ["live/auth/reset-password/AuthResetPasswordForm", AuthResetPasswordForm],
  ["live/docs/show/DocsContent", DocsContent],
  ["live/layouts/auth/Layout", AuthLayout],
  ["live/layouts/docs/Layout", DocsLayout],
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
      document.documentElement.dataset.gettextLocale || document.documentElement.lang || "en";
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
