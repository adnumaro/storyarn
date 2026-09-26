import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import type { App } from "vue";
import LanguagePicker from "../../../components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "../../../components/language/types";
import LocalizationGlossary from "../../../live/localization/glossary/LocalizationGlossary.vue";
import type { LiveInterface } from "../../../shared/composables/useLive";
import { createMockLive, createPromiseMockLive } from "../../setup";

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

function mountGlossary(
  live: LiveInterface = createMockLive(),
  extraProps: Record<string, unknown> = {},
) {
  return mount(LocalizationGlossary, {
    props: {
      sourceLanguage: english,
      targetLanguages: [spanish],
      selectedLocale: "es",
      ...extraProps,
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

describe("LocalizationGlossary saving", () => {
  it("frees the save button and reports the failure when the connection drops", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const live = createPromiseMockLive(
      {},
      vi.fn(() => Promise.reject(new Error("disconnected"))),
    );
    const wrapper = mountGlossary(live, { canEdit: true });
    const [source, target] = wrapper.findAll("input:not([type=checkbox])");
    await source.setValue("Lighthouse");
    await target.setValue("Faro");
    const save = wrapper.findAll("button").find((b) => b.text() === "Save term")!;

    await save.trigger("click");
    await Promise.resolve();
    await Promise.resolve();
    await wrapper.vm.$nextTick();

    expect(save.attributes("disabled")).toBeUndefined();
    expect(wrapper.text()).toContain("Could not save the term. Try again.");
  });
});
