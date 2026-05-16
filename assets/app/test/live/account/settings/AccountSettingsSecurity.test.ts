import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AccountSettingsSecurity from "../../../../live/account/settings/AccountSettingsSecurity.vue";
import { createMockLive } from "../../../setup";

function mountSecurity() {
  return mount(AccountSettingsSecurity, {
    props: {
      currentEmail: "ada@example.com",
      triggerSubmit: false,
      passwordAction: "/users/update-password",
      passwordForm: {
        name: "user",
        values: {
          email: "ada@example.com",
          password: "",
          password_confirmation: "",
        },
        errors: {
          password: ["can't be blank"],
        },
        valid: false,
      },
    },
    global: {
      provide: {
        _live_vue: createMockLive(),
      },
    },
  });
}

describe("AccountSettingsSecurity", () => {
  it("does not show untouched password errors on initial render", () => {
    const wrapper = mountSecurity();

    expect(wrapper.text()).not.toContain("can't be blank");
  });
});
