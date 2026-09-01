/**
 * Per-mount Vue app setup shared by every wrapped component:
 * vue-i18n with the app's English catalog (mirrors assets/app/i18n.ts, which
 * uses a vite-only glob — here the en/ files are imported explicitly),
 * the `_live_vue` stub, and a theme ref so adapters can propagate `.dark`
 * onto content that reka-ui teleports outside the design's dark subtree.
 */
import type { App, Ref } from "vue";
import { createI18n } from "vue-i18n";
import { installLiveStub } from "./liveStub";

import auth from "../../../assets/app/locales/en/auth.json";
import common from "../../../assets/app/locales/en/common.json";
import docs from "../../../assets/app/locales/en/docs.json";
import flows from "../../../assets/app/locales/en/flows.json";
import integrations from "../../../assets/app/locales/en/integrations.json";
import landing from "../../../assets/app/locales/en/landing.json";
import layout from "../../../assets/app/locales/en/layout.json";
import localization from "../../../assets/app/locales/en/localization.json";
import notifications from "../../../assets/app/locales/en/notifications.json";
import onboarding from "../../../assets/app/locales/en/onboarding.json";
import palette from "../../../assets/app/locales/en/palette.json";
import projectSettings from "../../../assets/app/locales/en/project-settings.json";
import publicMsgs from "../../../assets/app/locales/en/public.json";
import scenes from "../../../assets/app/locales/en/scenes.json";
import settings from "../../../assets/app/locales/en/settings.json";
import sheets from "../../../assets/app/locales/en/sheets.json";
import workspace from "../../../assets/app/locales/en/workspace.json";

const en: Record<string, string> = Object.assign(
  {},
  auth,
  common,
  docs,
  flows,
  integrations,
  landing,
  layout,
  localization,
  notifications,
  onboarding,
  palette,
  projectSettings,
  publicMsgs,
  scenes,
  settings,
  sheets,
  workspace,
);

export const DS_THEME_KEY = "storyarn-ds-theme";

export interface DsTheme {
  isDark: Ref<boolean>;
}

export function installHost(app: App, theme: DsTheme): void {
  const i18n = createI18n({
    legacy: false,
    locale: "en",
    fallbackLocale: "en",
    messages: { en },
  });
  app.use(i18n);
  installLiveStub(app);
  app.provide(DS_THEME_KEY, theme);
}
