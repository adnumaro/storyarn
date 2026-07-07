import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AuthResetPasswordForm from "../../../../live/auth/reset-password/AuthResetPasswordForm.vue";
import { createMockLive } from "../../../setup";

function mountForm(props = {}) {
  return mount(AuthResetPasswordForm, {
    props: {
      loginUrl: "/users/log-in",
      resetComplete: false,
      form: {
        name: "user",
        values: {
          password: "",
          password_confirmation: "",
        },
        errors: {},
        valid: true,
      },
      ...props,
    },
    global: {
      provide: {
        _live_vue: createMockLive(),
      },
    },
  });
}

describe("AuthResetPasswordForm", () => {
  it("renders the password reset form inside the auth layout slot", () => {
    const wrapper = mountForm();

    expect(wrapper.find("#reset-password-form").exists()).toBe(true);
    expect(wrapper.find("#reset-password").exists()).toBe(true);
    expect(wrapper.find("#reset-password-confirmation").exists()).toBe(true);
    expect(wrapper.find('a[href="/users/log-in"]').exists()).toBe(true);
    expect(wrapper.find('a[href="/users/log-in"]').attributes("data-phx-link")).toBe("redirect");
  });

  it("renders a persistent success state after the password is updated", () => {
    const wrapper = mountForm({ resetComplete: true });

    expect(wrapper.find("#reset-password-complete").exists()).toBe(true);
    expect(wrapper.find("#reset-password-form").exists()).toBe(false);
    expect(wrapper.find('a[href="/users/log-in"]').exists()).toBe(true);
    expect(wrapper.find('a[href="/users/log-in"]').attributes("data-phx-link")).toBe("redirect");
  });
});
