import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import AuthRegistrationForm from "../../../../live/auth/registration/AuthRegistrationForm.vue";
import { createMockLive } from "../../../setup";

function mountRegistrationForm() {
  return mount(AuthRegistrationForm, {
    props: {
      invited: false,
      loginUrl: "/users/log-in",
      loginAction: "/users/log-in?locale=en",
      csrfToken: "csrf-token",
      loginToken: null,
      triggerSubmit: false,
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
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("posts the registration handoff to the session endpoint once the account exists", async () => {
    const submissions: Array<{ action: string; token: string; handoff: string }> = [];

    vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(
      function (this: HTMLFormElement) {
        const field = (name: string) =>
          this.querySelector<HTMLInputElement>(`input[name="${name}"]`)?.value ?? "";

        submissions.push({
          action: this.getAttribute("action") ?? "",
          token: field("user[_login_token]"),
          handoff: field("user[_handoff]"),
        });
      },
    );

    const wrapper = mountRegistrationForm();
    await nextTick();
    expect(submissions).toEqual([]);

    await wrapper.setProps({ loginToken: "signed-registration-token", triggerSubmit: true });
    await nextTick();
    await flushPromises();

    expect(submissions).toEqual([
      {
        action: "/users/log-in?locale=en",
        token: "signed-registration-token",
        handoff: "registration",
      },
    ]);
  });

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
