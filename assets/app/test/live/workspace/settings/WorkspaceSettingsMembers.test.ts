import { flushPromises, mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vitest";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import WorkspaceSettingsMembers from "../../../../live/workspace/settings/WorkspaceSettingsMembers.vue";
import { createMockLive, createPromiseMockLive, setTestLocale } from "../../../setup";

function mountMembers(props = {}, live = createMockLive()) {
  const wrapper = mount(WorkspaceSettingsMembers, {
    props: {
      members: [],
      pendingInvitations: [],
      currentUserId: "1",
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
  afterEach(() => setTestLocale("en"));

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

  it("confirms ownership transfer using the member user id", async () => {
    const { live, wrapper } = mountMembers({
      canManage: true,
      canTransferOwnership: true,
      members: [
        {
          id: 82,
          user_id: "9007199254740993",
          display_name: "New owner",
          email: "new-owner@example.com",
          role: "member",
        },
      ],
    });

    await wrapper.get("#transfer-workspace-ownership-9007199254740993").trigger("click");

    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    expect(confirmation.props("description")).toContain("New owner");
    expect(confirmation.props("pendingText")).toBe("Transferring workspace ownership…");

    confirmation.vm.$emit("confirm");
    confirmation.vm.$emit("confirm");
    await nextTick();

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("transfer_owner");
    expect(payload).toEqual({ "user-id": "9007199254740993" });
    expect(complete).toEqual(expect.any(Function));
    expect(confirmation.props("open")).toBe(true);
    expect(confirmation.props("pending")).toBe(true);

    complete?.({});
    await nextTick();

    expect(confirmation.props("open")).toBe(false);
    expect(confirmation.props("pending")).toBe(false);
  });

  it("announces the pending transfer in Spanish", async () => {
    setTestLocale("es");
    const { wrapper } = mountMembers({
      canManage: true,
      canTransferOwnership: true,
      members: [
        {
          id: 82,
          user_id: "41",
          display_name: "Nueva propietaria",
          email: "new-owner@example.com",
          role: "member",
        },
      ],
    });

    await wrapper.get("#transfer-workspace-ownership-41").trigger("click");

    expect(wrapper.getComponent(ConfirmDialog).props("pendingText")).toBe(
      "Transfiriendo la propiedad del espacio…",
    );
  });

  it("keeps an unconfirmed transfer visible when the connection fails", async () => {
    let rejectPush!: (reason?: unknown) => void;
    const pushEvent = vi.fn(
      () =>
        new Promise<Record<string, unknown>>((_resolve, reject) => {
          rejectPush = reject;
        }),
    );
    const live = createPromiseMockLive({}, pushEvent);
    const { wrapper } = mountMembers(
      {
        canManage: true,
        canTransferOwnership: true,
        members: [
          {
            id: 82,
            user_id: "41",
            display_name: "New owner",
            email: "new-owner@example.com",
            role: "member",
          },
        ],
      },
      live,
    );

    await wrapper.get("#transfer-workspace-ownership-41").trigger("click");
    const confirmation = wrapper.getComponent(ConfirmDialog);
    confirmation.vm.$emit("confirm");
    await nextTick();

    expect(confirmation.props("pending")).toBe(true);
    expect(confirmation.props("open")).toBe(true);

    rejectPush(new Error("disconnected"));
    await flushPromises();

    expect(confirmation.props("pending")).toBe(false);
    expect(confirmation.props("open")).toBe(true);
    expect(confirmation.props("error")).toContain("could not confirm the result");
  });

  it("does not expose ownership transfer to workspace admins", () => {
    const { wrapper } = mountMembers({
      canManage: false,
      canTransferOwnership: false,
      members: [
        {
          id: 82,
          user_id: "41",
          email: "member@example.com",
          role: "member",
        },
      ],
    });

    expect(wrapper.find("#transfer-workspace-ownership-41").exists()).toBe(false);
  });

  it("invalidates an in-flight transfer when ownership capability is revoked", async () => {
    let rejectPush!: (reason?: unknown) => void;
    const pushEvent = vi.fn(
      () =>
        new Promise<Record<string, unknown>>((_resolve, reject) => {
          rejectPush = reject;
        }),
    );
    const live = createPromiseMockLive({}, pushEvent);
    const { wrapper } = mountMembers(
      {
        canManage: true,
        canTransferOwnership: true,
        members: [
          {
            id: 82,
            user_id: "41",
            display_name: "New owner",
            email: "new-owner@example.com",
            role: "member",
          },
        ],
      },
      live,
    );

    await wrapper.get("#transfer-workspace-ownership-41").trigger("click");
    const confirmation = wrapper.getComponent(ConfirmDialog);
    confirmation.vm.$emit("confirm");
    await nextTick();
    expect(confirmation.props("pending")).toBe(true);

    await wrapper.setProps({ canTransferOwnership: false });
    expect(confirmation.props("open")).toBe(false);
    expect(confirmation.props("pending")).toBe(false);

    rejectPush(new Error("late disconnect"));
    await flushPromises();
    await wrapper.setProps({ canTransferOwnership: true });

    expect(confirmation.props("open")).toBe(false);
    expect(confirmation.props("error")).toBeUndefined();
    expect(confirmation.props("description")).not.toContain("New owner");
  });
});
