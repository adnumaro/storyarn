import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import { nextTick } from "vue";
import AccountSettingsProfile from "../../../../live/account/settings/AccountSettingsProfile.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive } from "../../../setup";

function mountProfile(props: Record<string, unknown> = {}, live: LiveInterface = createMockLive()) {
  return mount(AccountSettingsProfile, {
    attachTo: document.body,
    props: {
      profileForm: {
        name: "user",
        values: { display_name: "Ada Lovelace", locale: "en" },
        errors: {},
        valid: true,
      },
      email: "ada@example.com",
      reauth: {
        confirmAction: "/users/confirm-access",
        csrfToken: "csrf",
        returnTo: "/users/settings",
        sudoHandoff: null,
        triggerSubmit: false,
      },
      ...props,
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("AccountSettingsProfile", () => {
  it("renders the display name and the email", () => {
    const wrapper = mountProfile();

    expect((wrapper.get("#profile-display-name").element as HTMLInputElement).value).toBe(
      "Ada Lovelace",
    );
    expect(wrapper.text()).toContain("ada@example.com");
    expect(wrapper.find('[data-testid="settings-reauth"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it("saves the display name when the field loses focus after a change", async () => {
    const live = createMockLive();
    const wrapper = mountProfile({}, live);
    const input = wrapper.get("#profile-display-name");

    await input.trigger("blur");
    expect(live.pushEvent).not.toHaveBeenCalledWith(
      "update_profile",
      expect.anything(),
      expect.anything(),
    );

    await input.setValue("Ada L.");
    await input.trigger("blur");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "update_profile",
      { user: { display_name: "Ada L.", locale: "en" } },
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it("locks the identity section behind re-authentication", () => {
    const wrapper = mountProfile({ sudoActive: false });

    expect(wrapper.find('[data-testid="settings-reauth"]').exists()).toBe(true);
    expect(wrapper.get("#profile-display-name").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#profile-change-email").attributes("disabled")).toBeDefined();
    wrapper.unmount();
  });

  it("asks for the new email in a dialog and sends the request", async () => {
    const live = createMockLive();
    const wrapper = mountProfile({}, live);

    await wrapper.get("#profile-change-email").trigger("click");
    await nextTick();

    const input = document.body.querySelector<HTMLInputElement>("#profile-new-email");
    expect(input).not.toBeNull();

    input!.value = "new@example.com";
    input!.dispatchEvent(new Event("input", { bubbles: true }));
    await nextTick();
    document.body.querySelector<HTMLFormElement>("#profile-email-form")!.requestSubmit();
    await nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "request_email_change",
      { email: "new@example.com" },
      expect.any(Function),
    );
    wrapper.unmount();
  });
});
