import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AccountSettingsProfile from "../../../../live/account/settings/AccountSettingsProfile.vue";
import { createMockLive } from "../../../setup";

function mountProfile(values = { display_name: "Ada Lovelace", locale: "en" }) {
  return mount(AccountSettingsProfile, {
    props: {
      profileForm: {
        name: "user",
        values,
        errors: {},
        valid: true,
      },
    },
    global: {
      provide: {
        _live_vue: createMockLive(),
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
});
