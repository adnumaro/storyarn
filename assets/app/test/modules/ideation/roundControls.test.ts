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
    expect(wrapper.find("#brainstorming-round-edit-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-cancel-20").exists()).toBe(false);
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

  it("edits only a prepared round and sends its current revision", async () => {
    const { send } = controls();
    await wrapper.get("#brainstorming-round-edit-20").trigger("click");
    expect(
      (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
    ).toBe("What motivates this character?");
    await wrapper.get("#brainstorming-round-edit-prompt-20").setValue("  Revised question  ");
    await wrapper.get("#brainstorming-round-20 form").trigger("submit");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("update_round", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      round_id: 20,
      prompt: "Revised question",
    });
    expect(wrapper.find("#brainstorming-round-edit-prompt-20").exists()).toBe(false);
  });

  it("retains an edited question when the save is rejected or disconnected", async () => {
    const send = vi.fn().mockResolvedValue({ status: "error", code: "validation" });
    controls(send);
    await wrapper.get("#brainstorming-round-edit-20").trigger("click");
    await wrapper.get("#brainstorming-round-edit-prompt-20").setValue("Keep my revision");
    await wrapper.get("#brainstorming-round-20 form").trigger("submit");
    await flushPromises();
    expect(
      (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
    ).toBe("Keep my revision");
    expect(wrapper.get("#brainstorming-round-save-20").attributes("disabled")).toBeUndefined();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    send.mockRejectedValue(new Error("disconnected"));
    await wrapper.get("#brainstorming-round-20 form").trigger("submit");
    await flushPromises();
    expect(
      (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
    ).toBe("Keep my revision");
    expect(wrapper.get("#brainstorming-round-save-20").attributes("disabled")).toBeUndefined();
  });

  it("keeps an edited prompt through session refreshes and a null reply, with only one pending save", async () => {
    let finish!: (value: null) => void;
    const { send, current } = controls(
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    await wrapper.get("#brainstorming-round-edit-20").trigger("click");
    await wrapper.get("#brainstorming-round-edit-prompt-20").setValue("My question in progress");
    await wrapper.setProps({
      session: { ...current.session!, revision: 2 },
      rounds: [round({ status: "planned", prompt: "The question changed elsewhere" })],
    });
    expect(
      (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
    ).toBe("My question in progress");
    await wrapper.get("#brainstorming-round-20 form").trigger("submit");
    await wrapper.get("#brainstorming-round-20 form").trigger("submit");
    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith(
      "update_round",
      expect.objectContaining({ revision: 1, prompt: "My question in progress" }),
    );
    finish(null);
    await flushPromises();
    expect(
      (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
    ).toBe("My question in progress");
    expect(wrapper.get("#brainstorming-round-save-20").attributes("disabled")).toBeUndefined();
  });

  it.each([true, false])(
    "requires comparing and explicitly replacing a concurrent question (refresh before save: %s)",
    async (refreshedBeforeSave) => {
      const send = vi
        .fn()
        .mockResolvedValueOnce({ status: "error", code: "stale_revision" })
        .mockResolvedValue({ status: "ok" });
      const { current } = controls(send);
      await wrapper.get("#brainstorming-round-edit-20").trigger("click");
      await wrapper.get("#brainstorming-round-edit-prompt-20").setValue("My edited question");
      const remote = {
        session: { ...current.session!, revision: 2 },
        rounds: [round({ status: "planned", prompt: "Another facilitator's question" })],
      };
      if (refreshedBeforeSave) await wrapper.setProps(remote);
      await wrapper.get("#brainstorming-round-20 form").trigger("submit");
      await flushPromises();
      expect(send).toHaveBeenCalledExactlyOnceWith("update_round", {
        epoch: "epoch-one",
        session_id: 1,
        round_id: 20,
        revision: 1,
        prompt: "My edited question",
      });
      if (!refreshedBeforeSave) {
        expect(wrapper.get("#brainstorming-round-replace-20").attributes("disabled")).toBeDefined();
        expect(wrapper.find("#brainstorming-round-current-prompt-20").exists()).toBe(false);
        await wrapper.setProps(remote);
      }
      expect(wrapper.get("#brainstorming-round-current-prompt-20").text()).toBe(
        "Another facilitator's question",
      );
      expect(
        (wrapper.get("#brainstorming-round-edit-prompt-20").element as HTMLTextAreaElement).value,
      ).toBe("My edited question");
      await wrapper.get("#brainstorming-round-20 form").trigger("submit");
      expect(send).toHaveBeenCalledTimes(1);
      await wrapper.get("#brainstorming-round-replace-20").trigger("click");
      await flushPromises();
      expect(send).toHaveBeenNthCalledWith(2, "update_round", {
        epoch: "epoch-one",
        session_id: 1,
        round_id: 20,
        revision: 2,
        prompt: "My edited question",
      });
      expect(wrapper.find("#brainstorming-round-edit-prompt-20").exists()).toBe(false);
    },
  );

  it("cancels a prepared round without removing its context from the history", async () => {
    const { send } = controls();
    await wrapper.get("#brainstorming-round-cancel-20").trigger("click");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("cancel_round", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      round_id: 20,
    });
    await wrapper.setProps({ rounds: [round({ status: "cancelled", started_at: null })] });
    expect(wrapper.get("#brainstorming-round-20").text()).toContain("Cancelled");
    expect(wrapper.get("#brainstorming-round-20").text()).toContain(
      "What motivates this character?",
    );
    expect(wrapper.find("#brainstorming-round-start-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-edit-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-cancel-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-close-20").exists()).toBe(false);
  });

  it("stops editing if another facilitator starts the round or edit access is lost", async () => {
    controls();
    await wrapper.get("#brainstorming-round-edit-20").trigger("click");
    await wrapper.setProps({ rounds: [round()], activeRound: round() });
    expect(wrapper.find("#brainstorming-round-edit-prompt-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-edit-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-cancel-20").exists()).toBe(false);
    await wrapper.setProps({ rounds: [round({ status: "planned" })], activeRound: null });
    await wrapper.get("#brainstorming-round-edit-20").trigger("click");
    await wrapper.setProps({ canEdit: false });
    expect(wrapper.find("#brainstorming-round-edit-prompt-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-cancel-20").exists()).toBe(false);
  });

  it("does not send a write revision when browsing earlier rounds", async () => {
    const { send } = controls();
    await wrapper.setProps({ roundsNext: 20 });
    const button = wrapper
      .findAll("button")
      .find((button) => button.text() === "Show earlier rounds")!;
    await button.trigger("click");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("browse_rounds", {
      epoch: "epoch-one",
      session_id: 1,
      before_id: 20,
    });
  });
});
