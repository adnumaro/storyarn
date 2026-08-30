import { flushPromises, mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vitest";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import ProjectSettingsMembers from "../../../../live/project/settings/ProjectSettingsMembers.vue";
import { createMockLive, createPromiseMockLive, setTestLocale } from "../../../setup";

function mountMembers(props = {}, live = createMockLive()) {
  const wrapper = mount(ProjectSettingsMembers, {
    props: {
      members: [],
      pendingInvitations: [],
      currentUserId: "1",
      ...props,
    },
    global: {
      provide: { _live_vue: live },
    },
  });

  return { live, wrapper };
}

describe("ProjectSettingsMembers", () => {
  afterEach(() => setTestLocale("en"));

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

    const pendingInvitation = wrapper.get("#project-pending-invitation-42");
    expect(pendingInvitation.text()).toContain("pending@example.com");
    expect(pendingInvitation.get('[data-slot="badge"]').text()).toBe("Viewer");

    await wrapper.get("#revoke-project-invitation-42").trigger("click");
    await wrapper.get("#revoke-project-invitation-42").trigger("click");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("revoke_invitation");
    expect(payload).toEqual({ id: "42" });
    expect(complete).toEqual(expect.any(Function));
  });

  it("confirms ownership transfer using the member user id", async () => {
    const { live, wrapper } = mountMembers({
      canTransferOwnership: true,
      members: [
        {
          id: 72,
          user_id: "9007199254740993",
          display_name: "New owner",
          email: "new-owner@example.com",
          role: "editor",
        },
      ],
    });

    await wrapper.get("#transfer-project-ownership-9007199254740993").trigger("click");

    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    expect(confirmation.props("description")).toContain("New owner");
    expect(confirmation.props("description")).toContain("owner-only operations may stop or fail");
    expect(confirmation.props("pendingText")).toBe("Transferring project ownership…");

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

  it("explains the active-operation risk in Spanish", async () => {
    setTestLocale("es");
    const { wrapper } = mountMembers({
      canTransferOwnership: true,
      members: [
        {
          id: 72,
          user_id: "31",
          display_name: "Nueva propietaria",
          email: "new-owner@example.com",
          role: "editor",
        },
      ],
    });

    await wrapper.get("#transfer-project-ownership-31").trigger("click");

    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("description")).toContain("pueden detenerse o fallar");
    expect(confirmation.props("description")).toContain("vuelve a iniciarlas");
    expect(confirmation.props("pendingText")).toBe("Transfiriendo la propiedad del proyecto…");
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
        canTransferOwnership: true,
        members: [
          {
            id: 72,
            user_id: "31",
            display_name: "New owner",
            email: "new-owner@example.com",
            role: "editor",
          },
        ],
      },
      live,
    );

    await wrapper.get("#transfer-project-ownership-31").trigger("click");
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

  it("does not expose ownership transfer when the server denies it", () => {
    const { wrapper } = mountMembers({
      canTransferOwnership: false,
      members: [
        {
          id: 72,
          user_id: "31",
          email: "member@example.com",
          role: "editor",
        },
      ],
    });

    expect(wrapper.find("#transfer-project-ownership-31").exists()).toBe(false);
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
        canTransferOwnership: true,
        members: [
          {
            id: 72,
            user_id: "31",
            display_name: "New owner",
            email: "new-owner@example.com",
            role: "editor",
          },
        ],
      },
      live,
    );

    await wrapper.get("#transfer-project-ownership-31").trigger("click");
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
