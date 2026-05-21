import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AuthConfirmAccessForm from "../../../../live/auth/confirm-access/AuthConfirmAccessForm.vue";

function mountForm() {
  return mount(AuthConfirmAccessForm, {
    props: {
      email: "ada@example.com",
      loginAction: "/users/log-in",
      csrfToken: "csrf-token",
    },
  });
}

describe("AuthConfirmAccessForm", () => {
  it("renders and submits the current user's email", () => {
    const wrapper = mountForm();
    const emailInput = wrapper.find('input[name="user[email]"]');

    expect((emailInput.element as HTMLInputElement).value).toBe("ada@example.com");
    expect(emailInput.attributes("readonly")).toBeDefined();
  });

  it("marks the submit as a confirmed access login", () => {
    const wrapper = mountForm();
    const actionInput = wrapper.find('input[name="_action"]');

    expect(actionInput.attributes("value")).toBe("confirmed");
  });
});
