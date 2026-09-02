import { describe, expect, it } from "vitest";
import { createI18n } from "vue-i18n";
import en from "../../locales/en/project-settings.json";
import es from "../../locales/es/project-settings.json";

describe("project settings localized copy", () => {
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

  it.each([
    ["en", "strategy_skip", "Keep existing content; skip conflicting imports"],
    ["en", "strategy_overwrite", "Replace existing content with conflicting imports"],
    ["es", "strategy_skip", "Conservar el contenido existente; omitir lo importado en conflicto"],
    ["es", "strategy_overwrite", "Reemplazar el contenido existente por lo importado en conflicto"],
  ])(
    "describes the %s import %s strategy from the imported content perspective",
    (locale, key, expected) => {
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: { en, es },
      });

      expect(i18n.global.t(`project_settings.import.${key}`)).toBe(expected);
    },
  );

  it.each([
    [
      "en",
      "strategy_overwrite_unavailable",
      "Replacing existing content is unavailable when shortcuts conflict because it could break links from other project content. Keep the existing content or import both versions instead.",
    ],
    [
      "es",
      "strategy_overwrite_unavailable",
      "Reemplazar el contenido existente no está disponible cuando hay atajos en conflicto porque podría romper enlaces desde otras partes del proyecto. Conserva el contenido existente o importa ambas versiones.",
    ],
    [
      "en",
      "errors.preflight_overwrite_conflict",
      "Existing content cannot be replaced safely while shortcuts conflict. Choose Keep existing content or Keep both, then start the import again.",
    ],
    [
      "es",
      "errors.preflight_overwrite_conflict",
      "El contenido existente no se puede reemplazar de forma segura mientras haya atajos en conflicto. Elige conservar el contenido existente o conservar ambas versiones y vuelve a iniciar la importación.",
    ],
    [
      "en",
      "errors.overwrite_conflict",
      "The import was stopped because replacing conflicting content could break existing references. No project content was changed. Start again and choose Keep existing content or Keep both.",
    ],
    [
      "es",
      "errors.overwrite_conflict",
      "La importación se detuvo porque reemplazar contenido en conflicto podría romper referencias existentes. No se modificó ningún contenido del proyecto. Empieza de nuevo y elige conservar el contenido existente o ambas versiones.",
    ],
    [
      "en",
      "errors.preflight_skip_variable_contract_mismatch",
      "An existing sheet does not contain the variables this import expects. Choose Keep both by renaming imported content, then start the import again.",
    ],
    [
      "es",
      "errors.preflight_skip_variable_contract_mismatch",
      "Una ficha existente no contiene las variables que espera esta importación. Elige Conservar ambos renombrando lo importado y vuelve a iniciar la importación.",
    ],
    [
      "en",
      "errors.preflight_skip_conflict_ambiguous",
      "Storyarn cannot identify one safe existing item for every conflicting import. Choose Keep both by renaming imported content, then start the import again.",
    ],
    [
      "es",
      "errors.preflight_skip_conflict_ambiguous",
      "Storyarn no puede identificar un único elemento existente seguro para cada importación en conflicto. Elige Conservar ambos renombrando lo importado y vuelve a iniciar la importación.",
    ],
    [
      "en",
      "errors.skip_variable_contract_mismatch",
      "The import stopped because an existing sheet does not contain compatible variables. No project content was changed. Start again and choose Keep both by renaming imported content.",
    ],
    [
      "es",
      "errors.skip_variable_contract_mismatch",
      "La importación se detuvo porque una ficha existente no contiene variables compatibles. No se modificó ningún contenido del proyecto. Empieza de nuevo y elige Conservar ambos renombrando lo importado.",
    ],
    [
      "en",
      "errors.skip_conflict_ambiguous",
      "The import stopped because Storyarn could not identify one safe existing item for every conflict. No project content was changed. Start again and choose Keep both by renaming imported content.",
    ],
    [
      "es",
      "errors.skip_conflict_ambiguous",
      "La importación se detuvo porque Storyarn no pudo identificar un único elemento existente seguro para cada conflicto. No se modificó ningún contenido del proyecto. Empieza de nuevo y elige Conservar ambos renombrando lo importado.",
    ],
  ])("keeps the %s import safeguard copy explicit for %s", (locale, key, expected) => {
    const i18n = createI18n({
      legacy: false,
      locale,
      messages: { en, es },
    });

    expect(i18n.global.t(`project_settings.import.${key}`)).toBe(expected);
  });
});
