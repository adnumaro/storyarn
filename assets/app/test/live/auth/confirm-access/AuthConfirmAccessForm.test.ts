import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import AuthConfirmAccessForm from "../../../../live/auth/confirm-access/AuthConfirmAccessForm.vue";
import { createMockLive } from "../../../setup";
import type { LiveInterface } from "../../../../shared/composables/useLive";

function mountForm(live: LiveInterface = createMockLive()) {
  return mount(AuthConfirmAccessForm, {
    props: {
      email: "ada@example.com",
      backUrl: "/workspaces/ada",
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("AuthConfirmAccessForm", () => {
  it("renders the current user's email as read only", () => {
    const wrapper = mountForm();
    const emailInput = wrapper.find('input[name="user[email]"]');

    expect((emailInput.element as HTMLInputElement).value).toBe("ada@example.com");
    expect(emailInput.attributes("readonly")).toBeDefined();
  });

  it("uses a LiveView event without exposing session or redirect fields", async () => {
    const live = createMockLive();
    const wrapper = mountForm(live);

    await wrapper.get("#confirm-password").setValue("correct horse battery staple");
    await wrapper.get("#confirm-access-form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "confirm_access",
      { password: "correct horse battery staple" },
      expect.any(Function),
    );

    const form = wrapper.get("#confirm-access-form");
    expect(form.attributes("action")).toBeUndefined();
    expect(wrapper.find('input[name="_csrf_token"]').exists()).toBe(false);
    expect(wrapper.find('input[name="return_to"]').exists()).toBe(false);
  });

  it("keeps the back destination outside protected settings", () => {
    const wrapper = mountForm();

    expect(wrapper.get("#confirm-access-back-link").attributes("href")).toBe("/workspaces/ada");
  });

  it("allows toggling password visibility", async () => {
    const wrapper = mountForm();
    const passwordInput = wrapper.get("#confirm-password");

    expect(passwordInput.attributes("type")).toBe("password");

    await wrapper.get('button[aria-label="Show password"]').trigger("click");

    expect(passwordInput.attributes("type")).toBe("text");
  });

  it("shows an accessible server error when confirmation fails", async () => {
    const live = createMockLive();

    vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) => {
      callback?.({ ok: false, error: "invalid_password" });
    });

    const wrapper = mountForm(live);
    await wrapper.get("#confirm-password").setValue("wrong password");
    await wrapper.get("#confirm-access-form").trigger("submit");

    const passwordInput = wrapper.get("#confirm-password");
    const error = wrapper.get("#confirm-password-error");

    expect(error.text()).toBe("The password you entered is incorrect.");
    expect(error.attributes("role")).toBe("alert");
    expect(passwordInput.attributes("aria-invalid")).toBe("true");
    expect(passwordInput.attributes("aria-describedby")).toBe("confirm-password-error");
  });

  it("accepts the empty reply returned before a successful LiveView navigation", async () => {
    const live = createMockLive();

    vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) => {
      callback?.(null as unknown as Record<string, unknown>);
    });

    const wrapper = mountForm(live);
    await wrapper.get("#confirm-password").setValue("correct horse battery staple");
    await wrapper.get("#confirm-access-form").trigger("submit");

    expect(wrapper.find("#confirm-password-error").exists()).toBe(false);
    expect(wrapper.get('button[type="submit"]').attributes("disabled")).toBeUndefined();
  });

  it("recovers when a disconnected LiveView never acknowledges the event", async () => {
    vi.useFakeTimers();

    try {
      const live = createMockLive();
      vi.mocked(live.pushEvent).mockImplementation(() => undefined);

      const wrapper = mountForm(live);
      await wrapper.get("#confirm-password").setValue("correct horse battery staple");
      await wrapper.get("#confirm-access-form").trigger("submit");

      expect(wrapper.get('button[type="submit"]').attributes("disabled")).toBeDefined();

      await vi.advanceTimersByTimeAsync(10_000);

      expect(wrapper.get("#confirm-password-error").text()).toBe(
        "Your session has expired. Refresh the page and log in again.",
      );
      expect(wrapper.get('button[type="submit"]').attributes("disabled")).toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });

  it("ignores a late callback from a timed-out attempt while a retry is pending", async () => {
    vi.useFakeTimers();

    try {
      const callbacks: Array<(reply: Record<string, unknown>) => void> = [];
      const live = createMockLive();

      vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) => {
        if (callback) callbacks.push(callback);
      });

      const wrapper = mountForm(live);
      const passwordInput = wrapper.get("#confirm-password");
      const submitButton = wrapper.get('button[type="submit"]');

      await passwordInput.setValue("first password");
      await wrapper.get("#confirm-access-form").trigger("submit");
      await vi.advanceTimersByTimeAsync(10_000);

      await passwordInput.setValue("second password");
      await wrapper.get("#confirm-access-form").trigger("submit");

      callbacks[0]?.({ ok: false, error: "invalid_password" });
      await wrapper.vm.$nextTick();

      expect(submitButton.attributes("disabled")).toBeDefined();
      expect(wrapper.find("#confirm-password-error").exists()).toBe(false);

      callbacks[1]?.({ ok: false, error: "invalid_password" });
      await wrapper.vm.$nextTick();

      expect(submitButton.attributes("disabled")).toBeUndefined();
      expect(wrapper.get("#confirm-password-error").text()).toBe(
        "The password you entered is incorrect.",
      );
    } finally {
      vi.useRealTimers();
    }
  });
});
