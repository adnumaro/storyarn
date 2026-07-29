import { describe, expect, it } from "vitest";
import { createI18n } from "vue-i18n";
import en from "../../locales/en/project-settings.json";
import es from "../../locales/es/project-settings.json";

describe("project settings export labels", () => {
  it.each([
    ["en", 1, "1 more finding is not shown."],
    ["en", 2, "2 more findings are not shown."],
    ["es", 1, "No se muestra 1 hallazgo más."],
    ["es", 2, "No se muestran 2 hallazgos más."],
  ])("pluralizes hidden findings in %s", (locale, count, expected) => {
    const i18n = createI18n({
      legacy: false,
      locale,
      messages: { en, es },
    });

    expect(i18n.global.t("project_settings.export.more_findings", { count })).toBe(expected);
  });
});
