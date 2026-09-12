import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import BoardHeader from "@app/live/ideation/BoardHeader.vue";
import type { BrainstormingReference } from "@app/live/ideation/referenceTypes";
import { board } from "../../modules/ideation/fixtures";

const reference: BrainstormingReference = {
  id: 4,
  version: 1,
  relation: "origin",
  targetType: "flow",
  targetId: 8,
  status: "changed",
  base: { name: "Original opening flow", fields: [] },
  current: { id: 8, type: "flow", name: "Current opening flow", fields: [], href: "/flows/8" },
  capturedAt: "2026-09-12T10:00:00Z",
};

describe("Board header with starting context", () => {
  it("retains title, settings, rounds, timer and private controls together with return navigation", async () => {
    const current = board();
    const pushEvent = vi.fn();
    const wrapper = mount(BoardHeader, {
      props: {
        session: current.session!,
        epoch: current.epoch,
        canManage: true,
        canEdit: true,
        rounds: [],
        roundsNext: null,
        activeRound: null,
        timer: null,
        contextReference: reference,
      },
      global: {
        provide: {
          _live_vue: {
            pushEvent,
            handleEvent: vi.fn(),
            removeHandleEvent: vi.fn(),
            upload: vi.fn(),
          },
        },
      },
    });
    expect(wrapper.get("#brainstorming-session-title").text()).toBe(current.session!.title);
    expect(wrapper.find("#brainstorming-rounds-trigger").exists()).toBe(true);
    expect(wrapper.find("#brainstorming-timer-trigger").exists()).toBe(true);
    expect(wrapper.find('button[aria-label="Start private mode for everyone"]').exists()).toBe(
      true,
    );
    await wrapper.get('button[aria-label="Session details and settings"]').trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("board_action");
    const back = wrapper.get("#brainstorming-origin-return-4");
    expect(back.attributes("data-size")).toBe("icon-sm");
    expect(back.attributes("aria-label")).toBe("Return to content: Current opening flow");
    expect(back.attributes("aria-describedby")).toBe("brainstorming-origin-4");
    await back.trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("exploration_return");
    expect(pushEvent.mock.calls[1][1]).toEqual({
      epoch: current.epoch,
      session_id: current.session!.id,
      reference_id: 4,
    });
    expect(wrapper.find("#brainstorming-rounds-trigger").exists()).toBe(true);
    wrapper.unmount();
  });
});
