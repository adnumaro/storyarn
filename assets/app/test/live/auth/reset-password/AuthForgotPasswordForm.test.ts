import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AuthForgotPasswordForm from "../../../../live/auth/reset-password/AuthForgotPasswordForm.vue";
import { createMockLive } from "../../../setup";

function mountForm(props = {}) {
  const live = createMockLive();
  const wrapper = mount(AuthForgotPasswordForm, {
    props: {
      loginUrl: "/users/log-in",
      instructionsSent: false,
      requestError: null,
      form: {
        name: "password_reset",
        values: {
          email: "ada@example.com",
        },
        errors: {},
        valid: true,
      },
      ...props,
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });

  return { wrapper, live };
}

describe("AuthForgotPasswordForm", () => {
  it("renders the reset request form inside the auth layout slot", () => {
    const { wrapper } = mountForm();

    expect(wrapper.find("#forgot-password-form").exists()).toBe(true);
    expect(wrapper.find<HTMLInputElement>("#forgot-password-email").element.value).toBe(
      "ada@example.com",
    );
    expect(wrapper.find('a[href="/users/log-in"]').exists()).toBe(true);
  });

  it("renders a persistent confirmation state after submitting", () => {
    const { wrapper } = mountForm({ instructionsSent: true });

    expect(wrapper.find("#forgot-password-confirmation").exists()).toBe(true);
    expect(wrapper.find("#forgot-password-form").exists()).toBe(false);
    expect(wrapper.find('a[href="/users/log-in"]').exists()).toBe(true);
  });

  it("requests another email form from the confirmation state", async () => {
    const { wrapper, live } = mountForm({ instructionsSent: true });

    await wrapper.find("#forgot-password-try-another").trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("reset_request_form", {});
  });

  it("renders rate-limit errors inline with the form", () => {
    const { wrapper } = mountForm({ requestError: "Too many attempts" });

    expect(wrapper.find("#forgot-password-request-error").text()).toContain("Too many attempts");
    expect(wrapper.find("#forgot-password-form").exists()).toBe(true);
  });
});
