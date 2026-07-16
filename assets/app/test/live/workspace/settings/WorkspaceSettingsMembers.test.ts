import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { describe, expect, it, vi } from "vitest";
import WorkspaceSettingsMembers from "../../../../live/workspace/settings/WorkspaceSettingsMembers.vue";
import { createMockLive } from "../../../setup";

function mountMembers(props = {}) {
  const live = createMockLive();
  const wrapper = mount(WorkspaceSettingsMembers, {
    props: {
      members: [],
      pendingInvitations: [],
      currentUserId: 1,
      canInvite: true,
      canManage: false,
      ...props,
    },
    global: {
      provide: { _live_vue: live },
    },
  });

  return { live, wrapper };
}

describe("WorkspaceSettingsMembers", () => {
  it("shows the invite form to an admin without exposing owner-only controls", () => {
    const { wrapper } = mountMembers({
      members: [
        {
          id: 2,
          display_name: "Project member",
          email: "member@example.com",
          role: "member",
        },
      ],
    });

    expect(wrapper.find("#workspace-invite-form").exists()).toBe(true);
    expect(wrapper.text()).toContain("member@example.com");
    expect(wrapper.find('[title="Remove member"]').exists()).toBe(false);
  });

  it("keeps the form value until the server confirms success", async () => {
    const { live, wrapper } = mountMembers();

    expect(wrapper.get("#invite-email").attributes("maxlength")).toBe("160");
    await wrapper.get("#invite-email").setValue("collaborator@example.com");
    await wrapper.get("#workspace-invite-form").trigger("submit");
    await wrapper.get("#workspace-invite-form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("send_invitation");
    expect(payload).toEqual({
      invite: { email: "collaborator@example.com", role: "member" },
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

    await wrapper.get("#workspace-invite-form").trigger("submit");
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
          id: 84,
          email: "pending@example.com",
          role: "viewer",
          expires_at: "2026-07-22T12:00:00Z",
        },
      ],
    });

    const pendingInvitation = wrapper.get("#workspace-pending-invitation-84");
    expect(pendingInvitation.text()).toContain("pending@example.com");
    expect(pendingInvitation.get('[data-slot="badge"]').text()).toBe("Viewer");

    await wrapper.get("#revoke-workspace-invitation-84").trigger("click");
    await wrapper.get("#revoke-workspace-invitation-84").trigger("click");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("revoke_invitation");
    expect(payload).toEqual({ id: "84" });
    expect(complete).toEqual(expect.any(Function));
  });
});
