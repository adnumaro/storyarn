import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import AuthLoginForm from "../../../../live/auth/login/AuthLoginForm.vue";
import { createMockLive } from "../../../setup";

function mountLoginForm() {
  return mount(AuthLoginForm, {
    props: {
      csrfToken: "csrf-token",
      loginAction: "/users/log-in",
      loginToken: null,
      triggerSubmit: false,
      form: {
        name: "user",
        values: {
          email: "ada@example.com",
          password: "",
        },
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

describe("AuthLoginForm", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("submits the hidden session form with the updated LiveView login token", async () => {
    const submittedTokens: string[] = [];

    vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(
      function (this: HTMLFormElement) {
        const tokenInput = this.querySelector<HTMLInputElement>('input[name="user[_login_token]"]');
        submittedTokens.push(tokenInput?.value ?? "");
      },
    );

    const wrapper = mountLoginForm();

    await wrapper.setProps({
      loginToken: "signed-login-token",
      triggerSubmit: true,
    });
    await nextTick();
    await flushPromises();

    expect(submittedTokens).toEqual(["signed-login-token"]);
  });
});
