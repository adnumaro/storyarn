import { createI18n } from "vue-i18n";

type LocaleMessages = Record<string, Record<string, string>>;

const localesModules: Record<
  string,
  { default?: Record<string, string> } & Record<string, string>
> = import.meta.glob("./locales/**/*.json", { eager: true });

const messages: LocaleMessages = {};

for (const path in localesModules) {
  // Extract language code from path, e.g., "./locales/en/landing.json" -> "en"
  const match = path.match(/\.\/locales\/([^/]+)\/.*\.json$/);
  if (match) {
    const lang = match[1];

    if (!messages[lang]) {
      messages[lang] = {};
    }

    const content = localesModules[path].default || localesModules[path];
    Object.assign(messages[lang], content);
  }
}

export const i18n = createI18n({
  legacy: false,
  locale: document.documentElement.dataset.gettextLocale || document.documentElement.lang || "en",
  fallbackLocale: "en",
  messages,
});
