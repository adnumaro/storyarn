import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import Panel from "@app/live/ideation/SessionPanel.vue";
import { board } from "../../modules/ideation/fixtures";

let wrapper: VueWrapper;
function panel(canManage = true, reply: Record<string, unknown> = { status: "ok", value: {} }) {
  const pushEvent = vi.fn(
    (
      _event: string,
      _payload: Record<string, unknown>,
      done?: (r: Record<string, unknown>) => void,
    ) => done?.(reply),
  );
  const current = board();
  wrapper = mount(Panel, {
    attachTo: document.body,
    props: {
      session: current.session!,
      epoch: current.epoch,
      members: current.members,
      canManage,
      open: true,
    },
    global: {
      provide: {
        _live_vue: { pushEvent, handleEvent: vi.fn(), removeHandleEvent: vi.fn(), upload: vi.fn() },
      },
      stubs: {
        Sidebar: {
          emits: ["close"],
          template:
            "<aside><slot name='header'/><slot/><button id='outside-test' @click='$emit(\"close\")'>out</button></aside>",
        },
      },
    },
  });
  return { pushEvent, current };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("session settings panel", () => {
  it("saves the details with the session's revision and the board context", async () => {
    const { pushEvent, current } = panel();
    expect((wrapper.get("#session-title").element as HTMLInputElement).value).toBe(
      current.session!.title,
    );
    await wrapper.get("#session-title").setValue("Yarn, revisited");
    await wrapper.get("#brainstorming-session-form").trigger("submit");
    await flushPromises();
    expect(pushEvent.mock.calls.map(([event, payload]) => [event, payload])).toContainEqual([
      "update_session",
      {
        title: "Yarn, revisited",
        objective: current.session!.objective ?? "",
        context: current.session!.context ?? "",
        revision: current.session!.revision,
        epoch: current.epoch,
        session_id: current.session!.id,
      },
    ]);
  });

  it("follows a collaborator's save except in the field being edited", async () => {
    const { current } = panel();
    await wrapper.get("#session-objective").setValue("Half-written");
    const session = current.session!;
    await wrapper.setProps({
      session: { ...session, revision: session.revision + 1, title: "Renamed by a peer" },
    });
    expect((wrapper.get("#session-title").element as HTMLInputElement).value).toBe(
      "Renamed by a peer",
    );
    expect((wrapper.get("#session-objective").element as HTMLTextAreaElement).value).toBe(
      "Half-written",
    );
    await wrapper.setProps({
      session: { ...session, revision: session.revision + 2, objective: "Theirs" },
    });
    expect((wrapper.get("#session-objective").element as HTMLTextAreaElement).value).toBe(
      "Half-written",
    );
  });

  it("closes new contributions from the panel and lets a manager reopen them", async () => {
    const { pushEvent, current } = panel();
    await wrapper.get("#brainstorming-contributions-toggle").trigger("click");
    await flushPromises();
    const [event, payload] = pushEvent.mock.calls.at(-1)!;
    expect(event).toBe("set_contributions_open");
    expect(payload).toEqual(
      expect.objectContaining({ open: false, revision: current.session!.revision }),
    );
  });

  it("closes through the board, from its button or from a click outside", async () => {
    const { pushEvent, current } = panel();
    await wrapper.get("#brainstorming-session-close").trigger("click");
    await wrapper.get("#outside-test").trigger("click");
    const closes = pushEvent.mock.calls
      .filter(([event]) => event === "session_panel")
      .map(([, payload]) => payload);
    expect(closes).toEqual([
      { open: false, epoch: current.epoch, session_id: current.session!.id },
      { open: false, epoch: current.epoch, session_id: current.session!.id },
    ]);
  });

  it("keeps participants to reading and shows a failed write", async () => {
    panel(false);
    expect(wrapper.find("#brainstorming-contributions-toggle").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-session-archive").exists()).toBe(false);
    expect(wrapper.get("fieldset").attributes("disabled")).toBeDefined();
    wrapper.unmount();
    panel(true, { status: "error", code: "stale_revision" });
    await wrapper.get("#brainstorming-session-form").trigger("submit");
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).not.toBe("");
  });
});
