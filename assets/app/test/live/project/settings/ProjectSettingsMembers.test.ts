import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { describe, expect, it, vi } from "vitest";
import ProjectSettingsMembers from "../../../../live/project/settings/ProjectSettingsMembers.vue";
import { createMockLive } from "../../../setup";

function mountMembers(props = {}) {
  const live = createMockLive();
  const wrapper = mount(ProjectSettingsMembers, {
    props: {
      members: [],
      pendingInvitations: [],
      currentUserId: 1,
      ...props,
    },
    global: {
      provide: { _live_vue: live },
    },
  });

  return { live, wrapper };
}

describe("ProjectSettingsMembers", () => {
  it("keeps the form value on errors and clears it only after success", async () => {
    const { live, wrapper } = mountMembers();

    expect(wrapper.get("#invite-email").attributes("maxlength")).toBe("160");
    await wrapper.get("#invite-email").setValue("collaborator@example.com");
    await wrapper.get("#project-invite-form").trigger("submit");
    await wrapper.get("#project-invite-form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("send_invitation");
    expect(payload).toEqual({
      invite: { email: "collaborator@example.com", role: "editor" },
    });
    expect(complete).toEqual(expect.any(Function));
    expect(wrapper.get("button[type=submit]").attributes("disabled")).toBeDefined();
    expect(wrapper.get<HTMLInputElement>("#invite-email").element.value).toBe(
      "collaborator@example.com",
    );

    complete?.({});
    await nextTick();
    expect(wrapper.get<HTMLInputElement>("#invite-email").element.value).toBe(
      "collaborator@example.com",
    );

    await wrapper.get("#project-invite-form").trigger("submit");
    expect(live.pushEvent).toHaveBeenCalledTimes(2);

    const successHandler = vi
      .mocked(live.handleEvent)
      .mock.calls.find(([event]) => event === "invitation_sent")?.[1];

    successHandler?.({});
    await nextTick();

    expect(wrapper.get<HTMLInputElement>("#invite-email").element.value).toBe("");
  });

  it("renders pending invitations and sends the revoke event", async () => {
    const { live, wrapper } = mountMembers({
      pendingInvitations: [
        {
          id: 42,
          email: "pending@example.com",
          role: "viewer",
          expires_at: "2026-07-22T12:00:00Z",
        },
      ],
    });

    expect(wrapper.get("#project-pending-invitations").text()).toContain("pending@example.com");
    expect(wrapper.find("#invite-role").exists()).toBe(true);

    await wrapper.get("#revoke-project-invitation-42").trigger("click");
    await wrapper.get("#revoke-project-invitation-42").trigger("click");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("revoke_invitation");
    expect(payload).toEqual({ id: "42" });
    expect(complete).toEqual(expect.any(Function));
  });
});
