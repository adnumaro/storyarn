import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import LanguageFlag from "../../../components/language/LanguageFlag.vue";

describe("LanguageFlag", () => {
  it("renders a decorative circular flag when metadata is available", () => {
    const wrapper = mount(LanguageFlag, {
      props: { flagCode: "GB", shortLabel: "EN" },
    });

    expect(wrapper.attributes("aria-hidden")).toBe("true");
    expect(wrapper.find(".fi-gb").exists()).toBe(true);
    expect(wrapper.classes()).toContain("rounded-full");
  });

  it("falls back to the short language label without inventing a flag", () => {
    const wrapper = mount(LanguageFlag, {
      props: { flagCode: null, shortLabel: "LA" },
    });

    expect(wrapper.find(".fi").exists()).toBe(false);
    expect(wrapper.text()).toBe("LA");
  });

  it("keeps the label visible for a syntactically valid flag without a bundled asset", () => {
    const wrapper = mount(LanguageFlag, {
      props: { flagCode: "ca", shortLabel: "EN" },
    });

    expect(wrapper.find(".fi-ca").exists()).toBe(true);
    expect(wrapper.get(".storyarn-language-flag-label").text()).toBe("EN");
  });
});
