import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import AccountSettingsPreferences from "../../../../live/account/settings/AccountSettingsPreferences.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive, registerTestLocale } from "../../../setup";

function mountPreferences(locale = "en", live: LiveInterface = createMockLive()) {
  registerTestLocale("es");

  return mount(AccountSettingsPreferences, {
    props: {
      locale,
      localeOptions: [
        { value: "en", label: "English", languageTag: "en", flagCode: "gb", shortLabel: "EN" },
        { value: "es", label: "Español", languageTag: "es", flagCode: "es", shortLabel: "ES" },
      ],
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("AccountSettingsPreferences", () => {
  afterEach(() => {
    localStorage.removeItem("phx:theme");
  });

  it("saves a new language through the shared picker", async () => {
    const live = createMockLive();
    const wrapper = mountPreferences("en", live);

    wrapper.getComponent(LanguagePicker).vm.$emit("update:modelValue", "en");
    await nextTick();
    expect(live.pushEvent).not.toHaveBeenCalled();

    wrapper.getComponent(LanguagePicker).vm.$emit("update:modelValue", "es");
    await nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith("update_locale", { locale: "es" }, undefined);
  });

  it("stores the theme on this device and announces the change", async () => {
    const listener = vi.fn();
    window.addEventListener("phx:set-theme", listener);

    const wrapper = mountPreferences();
    await wrapper.get('[data-testid="preferences-theme-dark"]').trigger("click");
    await nextTick();

    expect(localStorage.getItem("phx:theme")).toBe("dark");
    expect(listener).toHaveBeenCalled();

    await wrapper.get('[data-testid="preferences-theme-system"]').trigger("click");
    await nextTick();

    expect(localStorage.getItem("phx:theme")).toBeNull();
    window.removeEventListener("phx:set-theme", listener);
  });
});
