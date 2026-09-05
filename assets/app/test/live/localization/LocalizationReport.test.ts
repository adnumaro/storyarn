import { mount, shallowMount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import LanguagePicker from "../../../components/language/LanguagePicker.vue";
import { Tabs } from "../../../components/ui/tabs";
import LocalizationReport from "../../../live/localization/report/LocalizationReport.vue";
import type { LanguageProgress } from "../../../modules/localization/domain/types";
import { createMockLive } from "../../setup";

const targetLanguages = [
  { value: "es", label: "Spanish", languageTag: "es", flagCode: "es", shortLabel: "ES" },
  { value: "fr", label: "French", languageTag: "fr", flagCode: "fr", shortLabel: "FR" },
];

function progress(localeCode: string, name: string): LanguageProgress {
  return {
    localeCode,
    name,
    flagCode: localeCode,
    shortLabel: localeCode.toUpperCase(),
    total: 52,
    pending: 19,
    draft: 7,
    inProgress: 5,
    review: 6,
    final: 15,
    stale: 4,
    wordCount: 274,
    percentage: 28.8,
    workbenchUrl: `/localization/texts/${localeCode}`,
  };
}

describe("LocalizationReport", () => {
  it("switches the detail language through the tabs", async () => {
    const live = createMockLive();
    const wrapper = shallowMount(LocalizationReport, {
      props: {
        languageProgress: [progress("es", "Spanish"), progress("fr", "French")],
        targetLanguages,
        selectedLocale: "es",
      },
      global: { config: { globalProperties: { $live: live } as never } },
    });

    const tabs = wrapper.getComponent(Tabs);
    expect(tabs.props("modelValue")).toBe("es");

    tabs.vm.$emit("update:modelValue", "fr");
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith("change_locale", { locale: "fr" }, undefined);
  });

  it("links every language count to the filtered workbench", () => {
    const live = createMockLive();
    const wrapper = mount(LocalizationReport, {
      props: {
        languageProgress: [progress("es", "Spanish")],
        targetLanguages: [targetLanguages[0]],
        selectedLocale: "es",
        voProgress: { none: 30, needed: 6, recorded: 3, approved: 3 },
        typeCounts: { flow_node: 42, block: 6, sheet: 4 },
      },
      global: { config: { globalProperties: { $live: live } as never } },
    });

    const card = wrapper.get('[data-testid="localization-language-card-es"]');
    const hrefs = card.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/localization/texts/es?status=pending");
    expect(hrefs).toContain("/localization/texts/es?stale=1");
    expect(hrefs).toContain("/localization/texts/es");
    expect(card.text()).toContain("29%");
    expect(wrapper.html()).toContain("/localization/texts/es?vo_status=needed");
    expect(wrapper.html()).toContain("/localization/texts/es?source_type=block");
  });

  it("adds the first target language from the empty state", async () => {
    const live = createMockLive();
    const wrapper = mount(LocalizationReport, {
      props: {
        languageProgress: [],
        targetLanguages: [],
        sourceLanguage: { localeCode: "en", name: "English", flagCode: "gb", shortLabel: "EN" },
        capabilities: { canEdit: true, hasProvider: false },
        emptyState: {
          addLanguageOptions: [targetLanguages[1]],
          runtimeWordCount: 274,
          settingsUrl: "/settings/localization",
        },
      },
      global: { config: { globalProperties: { $live: live } as never } },
    });

    const submit = wrapper.get('[data-testid="localization-overview-add-language-submit"]');
    expect(submit.attributes("disabled")).toBeDefined();

    wrapper.getComponent(LanguagePicker).vm.$emit("select", targetLanguages[1]);
    await wrapper.vm.$nextTick();
    expect(submit.attributes("disabled")).toBeUndefined();

    await wrapper.get("form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "add_target_language",
      { locale_code: "fr" },
      expect.any(Function),
    );
    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledTimes(1);
  });

  it("does not offer the add form to viewers", () => {
    const live = createMockLive();
    const wrapper = mount(LocalizationReport, {
      props: {
        languageProgress: [],
        targetLanguages: [],
        sourceLanguage: { localeCode: "en", name: "English", flagCode: "gb", shortLabel: "EN" },
        capabilities: { canEdit: false, hasProvider: false },
      },
      global: { config: { globalProperties: { $live: live } as never } },
    });

    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.get('[data-testid="localization-empty-overview"]').text()).toContain(
      "Only project owners and editors can add languages.",
    );
  });
});
