import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import LanguagePicker from "../../../components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "../../../components/language/types";

const passthrough = { template: "<div><slot /></div>" };

const options: LanguagePickerOption[] = [
  {
    value: "en",
    label: "English",
    languageTag: "en",
    flagCode: "gb",
    shortLabel: "EN",
    href: "/docs",
  },
  {
    value: "es",
    label: "Español",
    languageTag: "es",
    flagCode: "es",
    shortLabel: "ES",
    href: "/es/docs",
  },
  {
    value: "pt-br",
    label: "Português (Brasil)",
    languageTag: "pt-BR",
    flagCode: "br",
    shortLabel: "PT",
  },
];

function mountPicker(props: Record<string, unknown> = {}) {
  return mount(LanguagePicker, {
    props: {
      id: "language-picker",
      modelValue: "en",
      options,
      label: "Page language",
      ...props,
    },
    global: {
      stubs: {
        Popover: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
      },
    },
  });
}

describe("LanguagePicker", () => {
  it("uses the same flag and label contract in its trigger and options", () => {
    const wrapper = mountPicker();

    expect(wrapper.get("#language-picker-trigger").attributes("aria-label")).toBe(
      "Page language: English",
    );
    expect(wrapper.get("#language-picker-trigger").text()).toContain("English");
    expect(wrapper.get("#language-picker-en").find(".fi-gb").exists()).toBe(true);
    expect(wrapper.get("#language-picker-es").text()).toContain("Español");
  });

  it("emits one semantic selection with the complete option", async () => {
    const wrapper = mountPicker();
    const spanishItem = wrapper.findAllComponents({ name: "CommandItem" }).at(1)!;

    spanishItem.vm.$emit("select", new Event("select"));
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted("update:modelValue")).toEqual([["es"]]);
    expect(wrapper.emitted("select")).toEqual([[options[1]]]);
  });

  it("finds regional languages by their complete locale code", async () => {
    const wrapper = mountPicker();

    await wrapper.get("[data-slot='command-input']").setValue("pt-BR");

    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(1);
    expect(wrapper.get("#language-picker-pt-br").text()).toContain("Português (Brasil)");
  });

  it("keeps language navigation as real LiveView links", () => {
    const wrapper = mountPicker({ mode: "navigate", appearance: { searchable: false } });

    const current = wrapper.get("#language-picker-en");
    const spanish = wrapper.get("#language-picker-es");

    expect(current.attributes("aria-current")).toBe("page");
    expect(spanish.attributes("href")).toBe("/es/docs");
    expect(spanish.attributes("hreflang")).toBe("es");
    expect(spanish.attributes("data-phx-link")).toBe("redirect");
    expect(wrapper.find("[role='menu']").exists()).toBe(false);
    expect(wrapper.find("[role='menuitem']").exists()).toBe(false);
  });
});
