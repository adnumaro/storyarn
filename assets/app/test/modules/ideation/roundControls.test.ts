import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import RoundControls from "@modules/ideation/RoundControls.vue";
import { createPromiseMockLive } from "../../setup";
import { board, round } from "./fixtures";

let wrapper: VueWrapper;
function controls(send = vi.fn().mockResolvedValue({ status: "ok" }), manage = true) {
  const current = board();
  wrapper = mount(RoundControls, {
    props: {
      session: current.session!,
      epoch: current.epoch,
      rounds: [round({ status: "planned", started_at: null })],
      roundsNext: null,
      activeRound: null,
      canManage: manage,
      canEdit: true,
    },
    global: {
      provide: { _live_vue: createPromiseMockLive({}, send) },
      stubs: {
        Popover: { template: "<div><slot /></div>" },
        PopoverTrigger: { template: "<div><slot /></div>" },
        PopoverContent: { template: "<div><slot /></div>" },
      },
    },
  });
  return { send, current };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("optional round controls", () => {
  it("prepares shared context and leaves starting the round as a separate action", async () => {
    const { send } = controls();
    await wrapper.get("#brainstorming-round-prompt").setValue("  A new question  ");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("create_round", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      prompt: "A new question",
    });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    expect(wrapper.get("#brainstorming-round-start-20").attributes("disabled")).toBeUndefined();
  });

  it("blocks another start while a round is active and closes without a reveal event", async () => {
    const { send } = controls();
    await wrapper.setProps({ activeRound: round({ id: 21, number: 2 }) });
    expect(wrapper.get("#brainstorming-round-start-20").attributes("disabled")).toBeDefined();
    await wrapper.get("#brainstorming-round-close-21").trigger("click");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("close_round", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      round_id: 21,
    });
  });

  it("allows participants to consult prompts without offering facilitator controls", () => {
    controls(undefined, false);
    expect(wrapper.text()).toContain("What motivates this character?");
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-start-20").exists()).toBe(false);
  });

  it("releases controls after a null reply while keeping the prompt for retry", async () => {
    controls(vi.fn().mockResolvedValue(null));
    await wrapper.get("#brainstorming-round-prompt").setValue("Do not lose this question");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("#brainstorming-round-create").attributes("disabled")).toBeUndefined();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Do not lose this question",
    );
  });

  it("retains context and releases controls on disconnection", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    controls(vi.fn().mockRejectedValue(new Error("disconnected")));
    await wrapper.get("#brainstorming-round-prompt").setValue("Keep this prompt");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("#brainstorming-round-create").attributes("disabled")).toBeUndefined();
    expect(wrapper.get('[role="alert"]').text()).toContain("connection");
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Keep this prompt");
  });

  it("keeps a prepared prompt while another participant refreshes the same session", async () => {
    const { current } = controls();
    await wrapper.get("#brainstorming-round-prompt").setValue("Prompt in progress");
    await wrapper.setProps({ session: { ...current.session!, revision: 2 } });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Prompt in progress",
    );
  });

  it("ignores a delayed reply after navigating to another session", async () => {
    let finish!: (value: { status: string }) => void;
    const { current } = controls(
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    await wrapper.get("form").trigger("submit");
    await wrapper.setProps({ session: { ...current.session!, id: 2 } });
    await wrapper.get("#brainstorming-round-prompt").setValue("Second session question");
    finish({ status: "ok" });
    await flushPromises();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Second session question",
    );
    expect(wrapper.get("#brainstorming-round-create").attributes("disabled")).toBeUndefined();
  });
});
