import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import NotificationBell from "../../../components/notifications/NotificationBell.vue";
import type {
  NotificationCenterState,
  NotificationItem,
} from "../../../components/notifications/types";
import type { LiveInterface } from "../../../shared/composables/useLive";
import { createMockLive, setTestLocale } from "../../setup";

const passthrough = { template: "<div><slot /></div>" };

const unreadNotification: NotificationItem = {
  id: 17,
  kind: "content_created",
  entityType: "sheet",
  entityName: "Character bible",
  status: null,
  createdAt: "2026-08-12T12:00:00Z",
  readAt: null,
  actorName: "Ana",
  projectName: "Veilbreak",
};

const readNotification: NotificationItem = {
  id: 23,
  kind: "async_operation",
  entityType: "project_snapshot",
  entityName: "Before release",
  status: "success",
  createdAt: "2026-08-11T12:00:00Z",
  readAt: "2026-08-11T12:05:00Z",
  actorName: null,
  projectName: "Veilbreak",
};

function center(overrides: Partial<NotificationCenterState> = {}): NotificationCenterState {
  return {
    filter: "all",
    items: [unreadNotification, readNotification],
    unreadCount: 1,
    ...overrides,
  };
}

async function mountBell(initialState: NotificationCenterState = center(), replyOnMount = true) {
  const live = createMockLive();
  vi.mocked(live.handleEvent).mockReturnValue(71);
  const pushEvent = vi.mocked(live.pushEvent);

  pushEvent.mockImplementation((event, _payload, callback) => {
    if (event === "refresh_notifications" && replyOnMount) {
      callback?.(initialState as unknown as Record<string, unknown>);
    }
  });

  const wrapper = mount(NotificationBell, {
    global: {
      provide: { _live_vue: live },
      stubs: {
        Popover: {
          template:
            '<div><button data-testid="open-popover" @click="$emit(\'update:open\', true)" /><slot /></div>',
        },
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
      },
    },
  });

  await nextTick();
  pushEvent.mockClear();

  return {
    live,
    wrapper,
    pushEvent,
  };
}

function buttonWithText(wrapper: VueWrapper, text: string) {
  const button = wrapper.findAll("button").find((candidate) => candidate.text() === text);
  expect(button, `button with text "${text}"`).toBeDefined();
  return button!;
}

function replyTo(live: LiveInterface, callIndex: number, state: NotificationCenterState): void {
  const callback = vi.mocked(live.pushEvent).mock.calls[callIndex]?.[2];
  expect(callback).toBeTypeOf("function");
  callback?.(state as unknown as Record<string, unknown>);
}

describe("NotificationBell", () => {
  beforeEach(() => setTestLocale("en"));

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("shows a real loading state before the first successful response", async () => {
    const { wrapper } = await mountBell(center(), false);

    expect(wrapper.get('[role="status"]').text()).toBe("Updating notifications");
    expect(wrapper.text()).not.toContain("You're all caught up");
  });

  it("renders the current state and caps a large unread badge", async () => {
    const { wrapper } = await mountBell(center({ unreadCount: 105 }));

    const trigger = wrapper.get("#notification-bell-trigger");
    expect(trigger.attributes("aria-label")).toBe("Notifications, 105 unread");
    expect(trigger.text()).toBe("99+");
    expect(wrapper.text()).toContain("Ana created sheet: Character bible");
    expect(wrapper.text()).toContain("project snapshot: Before release completed");
    expect(wrapper.findAll('button[aria-label="Mark as read"]')).toHaveLength(1);
  });

  it("renders the notification copy in Spanish", async () => {
    setTestLocale("es");
    const { wrapper } = await mountBell();

    expect(wrapper.get("#notification-bell-trigger").attributes("aria-label")).toBe(
      "Notificaciones, 1 sin leer",
    );
    expect(wrapper.text()).toContain("Ana creó ficha: Character bible");
    expect(wrapper.text()).toContain("Marcar todo como leído");
  });

  it("requests and applies the unread filter", async () => {
    const { live, pushEvent, wrapper } = await mountBell();

    await buttonWithText(wrapper, "Unread").trigger("click");

    expect(pushEvent).toHaveBeenCalledWith(
      "notification_filter_changed",
      { filter: "unread" },
      expect.any(Function),
    );
    expect(wrapper.get('[role="status"]').text()).toBe("Updating notifications");

    replyTo(live, 0, center({ filter: "unread", items: [unreadNotification] }));
    await nextTick();

    expect(buttonWithText(wrapper, "Unread").attributes("aria-pressed")).toBe("true");
    expect(wrapper.text()).toContain("Character bible");
    expect(wrapper.text()).not.toContain("Before release");
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it("keeps a pending filter request authoritative over an older pushed state", async () => {
    const { live, wrapper } = await mountBell();

    await buttonWithText(wrapper, "Unread").trigger("click");

    const pushedUpdate = vi.mocked(live.handleEvent).mock.calls[0]?.[1];
    pushedUpdate?.(center({ filter: "all" }) as unknown as Record<string, unknown>);
    await nextTick();

    expect(wrapper.get('[role="status"]').text()).toBe("Updating notifications");

    replyTo(live, 0, center({ filter: "unread", items: [unreadNotification] }));
    await nextTick();

    expect(buttonWithText(wrapper, "Unread").attributes("aria-pressed")).toBe("true");
    expect(wrapper.text()).not.toContain("Before release");
  });

  it("refreshes the current filter whenever the popover opens", async () => {
    const { pushEvent, wrapper } = await mountBell(
      center({ filter: "unread", items: [unreadNotification] }),
    );

    await wrapper.get('[data-testid="open-popover"]').trigger("click");

    expect(pushEvent).toHaveBeenCalledWith(
      "refresh_notifications",
      { filter: "unread" },
      expect.any(Function),
    );
  });

  it("marks one notification as read and applies the returned state", async () => {
    const { live, pushEvent, wrapper } = await mountBell();

    await wrapper.get('button[aria-label="Mark as read"]').trigger("click");

    expect(pushEvent).toHaveBeenCalledWith(
      "mark_notification_read",
      { id: unreadNotification.id },
      expect.any(Function),
    );

    replyTo(
      live,
      0,
      center({
        items: [{ ...unreadNotification, readAt: "2026-08-12T12:05:00Z" }, readNotification],
        unreadCount: 0,
      }),
    );
    await nextTick();

    expect(wrapper.find('button[aria-label="Mark as read"]').exists()).toBe(false);
    expect(wrapper.get("#notification-bell-trigger").text()).toBe("");
    expect(wrapper.get("#notification-bell-trigger").attributes("aria-label")).toBe(
      "Notifications",
    );
  });

  it("marks all notifications as read", async () => {
    const secondUnread = { ...readNotification, readAt: null };
    const { live, pushEvent, wrapper } = await mountBell(
      center({ items: [unreadNotification, secondUnread], unreadCount: 2 }),
    );

    await buttonWithText(wrapper, "Mark all as read").trigger("click");

    expect(pushEvent).toHaveBeenCalledWith("mark_all_notifications_read", {}, expect.any(Function));

    replyTo(
      live,
      0,
      center({
        items: [
          { ...unreadNotification, readAt: "2026-08-12T12:05:00Z" },
          { ...secondUnread, readAt: "2026-08-12T12:05:00Z" },
        ],
        unreadCount: 0,
      }),
    );
    await nextTick();

    expect(buttonWithText(wrapper, "Mark all as read").attributes()).toHaveProperty("disabled");
    expect(wrapper.findAll('button[aria-label="Mark as read"]')).toHaveLength(0);
  });

  it("shows an update error and retries the same request", async () => {
    const { live, pushEvent, wrapper } = await mountBell();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    pushEvent.mockImplementationOnce(() => {
      throw new Error("socket disconnected");
    });

    await buttonWithText(wrapper, "Unread").trigger("click");
    await nextTick();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      "We couldn't update your notifications.",
    );

    await buttonWithText(wrapper, "Try again").trigger("click");

    expect(pushEvent).toHaveBeenCalledTimes(2);
    expect(pushEvent.mock.calls[1]?.slice(0, 2)).toEqual([
      "notification_filter_changed",
      { filter: "unread" },
    ]);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);

    replyTo(live, 1, center({ filter: "unread", items: [unreadNotification] }));
    await nextTick();

    expect(buttonWithText(wrapper, "Unread").attributes("aria-pressed")).toBe("true");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it("applies pushed notification state and removes its handler on unmount", async () => {
    const { live, wrapper } = await mountBell();
    const handleEvent = vi.mocked(live.handleEvent);

    expect(handleEvent).toHaveBeenCalledWith("notifications_updated", expect.any(Function));
    const update = handleEvent.mock.calls[0]?.[1];
    const pushedState = center({ filter: "unread", items: [], unreadCount: 0 });
    update?.(pushedState as unknown as Record<string, unknown>);
    await nextTick();

    expect(wrapper.get("#notification-bell-trigger").attributes("aria-label")).toBe(
      "Notifications",
    );
    expect(wrapper.text()).toContain("No unread notifications");

    wrapper.unmount();

    expect(live.removeHandleEvent).toHaveBeenCalledWith(71);
  });
});
