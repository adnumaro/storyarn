import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import LanguagePicker from "../../../../components/language/LanguagePicker.vue";
import AccountSettingsProfile from "../../../../live/account/settings/AccountSettingsProfile.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive, registerTestLocale } from "../../../setup";

function mountProfile(
  values = { display_name: "Ada Lovelace", locale: "en" },
  live: LiveInterface = createMockLive(),
) {
  registerTestLocale("es");

  return mount(AccountSettingsProfile, {
    props: {
      profileForm: {
        name: "user",
        values,
        errors: {},
        valid: true,
      },
      localeOptions: [
        {
          value: "en",
          label: "English",
          languageTag: "en",
          flagCode: "gb",
          shortLabel: "EN",
        },
        {
          value: "es",
          label: "Español",
          languageTag: "es",
          flagCode: "es",
          shortLabel: "ES",
        },
      ],
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("AccountSettingsProfile", () => {
  it("renders the current display name", () => {
    const wrapper = mountProfile();

    expect((wrapper.get("#profile-display-name").element as HTMLInputElement).value).toBe(
      "Ada Lovelace",
    );
  });

  it("does not render email change controls", () => {
    const wrapper = mountProfile();

    expect(wrapper.find("#profile-email").exists()).toBe(false);
  });

  it("validates and submits the language selected through the shared picker", async () => {
    vi.useFakeTimers();

    try {
      const live = createMockLive();
      const wrapper = mountProfile(undefined, live);

      wrapper.getComponent(LanguagePicker).vm.$emit("update:modelValue", "es");
      await wrapper.vm.$nextTick();
      await vi.advanceTimersByTimeAsync(300);

      expect(live.pushEvent).toHaveBeenCalledWith(
        "validate_profile",
        { user: { display_name: "Ada Lovelace", locale: "es" } },
        expect.any(Function),
      );

      await wrapper.get("#profile-save-button").trigger("click");

      expect(live.pushEvent).toHaveBeenCalledWith(
        "update_profile",
        { user: { display_name: "Ada Lovelace", locale: "es" } },
        expect.any(Function),
      );
    } finally {
      vi.useRealTimers();
    }
  });
});
