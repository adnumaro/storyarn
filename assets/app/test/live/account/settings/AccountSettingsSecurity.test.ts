import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
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
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("does not show untouched password errors on initial render", () => {
    const wrapper = mountSecurity();
    const passwordInput = wrapper.get("#security-password");

    expect(wrapper.text()).not.toContain("can't be blank");
    expect(passwordInput.attributes("aria-invalid")).not.toBe("true");
    expect(passwordInput.attributes("aria-describedby")).toBeUndefined();
  });

  it("submits the hidden password form with the updated password fields", async () => {
    const submittedValues: Array<Record<string, string>> = [];

    vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(
      function (this: HTMLFormElement) {
        const formData = new FormData(this);
        submittedValues.push(Object.fromEntries(formData.entries()) as Record<string, string>);
      },
    );

    const wrapper = mountSecurity();

    await wrapper.get("#security-password").setValue("new-password-123");
    await wrapper.get("#security-password-confirmation").setValue("new-password-123");
    await wrapper.setProps({
      triggerSubmit: true,
    });
    await nextTick();
    await flushPromises();

    expect(submittedValues).toEqual([
      {
        _csrf_token: "",
        _method: "put",
        "user[email]": "ada@example.com",
        "user[password]": "new-password-123",
        "user[password_confirmation]": "new-password-123",
      },
    ]);
  });
});
