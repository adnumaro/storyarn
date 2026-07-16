import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import type { App } from "vue";
import LanguagePicker from "../../../components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "../../../components/language/types";
import LocalizationGlossary from "../../../live/localization/glossary/LocalizationGlossary.vue";
import type { LiveInterface } from "../../../shared/composables/useLive";
import { createMockLive } from "../../setup";

const english: LanguagePickerOption = {
  value: "en",
  label: "English",
  languageTag: "en",
  flagCode: "gb",
  shortLabel: "EN",
};

const spanish: LanguagePickerOption = {
  value: "es",
  label: "Spanish",
  languageTag: "es",
  flagCode: "es",
  shortLabel: "ES",
};

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountGlossary(live: LiveInterface = createMockLive()) {
  return mount(LocalizationGlossary, {
    props: {
      sourceLanguage: english,
      targetLanguages: [spanish],
      selectedLocale: "es",
    },
    global: {
      plugins: [livePlugin(live)],
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("LocalizationGlossary language picker", () => {
  it("passes the shared flag metadata to the canonical picker", () => {
    const picker = mountGlossary().getComponent(LanguagePicker);

    expect(picker.props("modelValue")).toBe("es");
    expect(picker.props("options")).toEqual([spanish]);
    expect(picker.props("appearance")).toEqual({
      align: "end",
      triggerClass: "w-52",
    });
  });

  it("changes locale using the selected shared option", () => {
    const live = createMockLive();
    const wrapper = mountGlossary(live);

    wrapper.getComponent(LanguagePicker).vm.$emit("select", spanish);

    expect(live.pushEvent).toHaveBeenCalledWith("change_locale", { locale: "es" }, undefined);
  });
});
