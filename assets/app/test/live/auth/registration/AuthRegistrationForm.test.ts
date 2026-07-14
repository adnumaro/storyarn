import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AuthRegistrationForm from "../../../../live/auth/registration/AuthRegistrationForm.vue";
import { createMockLive } from "../../../setup";

function mountRegistrationForm() {
  return mount(AuthRegistrationForm, {
    props: {
      invited: false,
      loginUrl: "/users/log-in",
      form: {
        name: "user",
        values: {
          email: "",
          password: "",
          password_confirmation: "",
        },
        errors: {
          email: ["can't be blank"],
          password: ["can't be blank"],
          password_confirmation: ["does not match password"],
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

describe("AuthRegistrationForm", () => {
  it("does not mark untouched fields invalid on initial render", () => {
    const wrapper = mountRegistrationForm();

    for (const selector of [
      "#register-email",
      "#register-password",
      "#register-password-confirmation",
    ]) {
      const input = wrapper.get(selector);
      expect(input.attributes("aria-invalid")).not.toBe("true");
      expect(input.attributes("aria-describedby")).toBeUndefined();
    }

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
