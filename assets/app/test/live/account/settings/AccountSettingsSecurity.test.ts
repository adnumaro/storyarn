import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import AccountSettingsSecurity from "../../../../live/account/settings/AccountSettingsSecurity.vue";
import { createMockLive } from "../../../setup";

function mountSecurity(props: Record<string, unknown> = {}) {
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
      ...props,
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
    const hiddenForm = wrapper.get('form[action="/users/update-password"]');

    expect(hiddenForm.attributes("method")).toBe("post");
    expect(
      wrapper.find('form[action="/users/update-password"] input[name="_method"]').exists(),
    ).toBe(false);
    expect(hiddenForm.get('input[name="_csrf_token"]').attributes("name")).toBe("_csrf_token");

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
        "user[email]": "ada@example.com",
        "user[password]": "new-password-123",
        "user[password_confirmation]": "new-password-123",
      },
    ]);
  });

  it("includes a validated sudo grant in the password POST", () => {
    const wrapper = mountSecurity({ sudoGrant: "signed-session-grant" });

    const hiddenForm = wrapper.get('form[action="/users/update-password"]');
    const grantInput = wrapper.get('input[name="sudo_grant"]');
    expect(hiddenForm.attributes("method")).toBe("post");
    expect(
      wrapper.find('form[action="/users/update-password"] input[name="_method"]').exists(),
    ).toBe(false);
    expect(hiddenForm.get('input[name="_csrf_token"]').attributes("name")).toBe("_csrf_token");
    expect(grantInput.attributes("value")).toBe("signed-session-grant");
  });
});
