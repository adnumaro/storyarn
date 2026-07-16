import { shallowMount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import LanguagePicker from "../../../components/language/LanguagePicker.vue";
import LocalizationReport from "../../../live/localization/report/LocalizationReport.vue";
import { createMockLive } from "../../setup";

const targetLanguages = [
  {
    value: "es",
    label: "Spanish",
    languageTag: "es",
    flagCode: "es",
    shortLabel: "ES",
  },
  {
    value: "fr",
    label: "French",
    languageTag: "fr",
    flagCode: "fr",
    shortLabel: "FR",
  },
];

describe("LocalizationReport", () => {
  it("uses the shared language picker contract and changes the report locale", async () => {
    const live = createMockLive();
    const wrapper = shallowMount(LocalizationReport, {
      props: {
        targetLanguages,
        selectedLocale: "es",
        speakerStats: [
          {
            speakerSheetId: null,
            speakerName: null,
            lineCount: 1,
            wordCount: 2,
          },
        ],
      },
      global: {
        config: { globalProperties: { $live: live } as never },
      },
    });

    const picker = wrapper.getComponent(LanguagePicker);
    expect(picker.props("modelValue")).toBe("es");
    expect(picker.props("options")).toEqual(targetLanguages);
    expect(picker.props("label")).toBe("Target language");

    picker.vm.$emit("update:modelValue", "fr");
    await wrapper.vm.$nextTick();

    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledWith(
      "change_locale",
      { locale: "fr" },
      undefined,
    );
  });
});
