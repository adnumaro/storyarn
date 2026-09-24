import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import Prepare from "@app/live/ideation/DecisionTaskPrepare.vue";
import { accepted, revision, source } from "./decisionFixtures";

let wrapper: VueWrapper;

afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

function prepare(writeText = vi.fn().mockResolvedValue(undefined)) {
  Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
  wrapper = mount(Prepare, {
    attachTo: document.body,
    props: {
      decision: accepted({
        accepted: revision({
          revision: 2,
          operation: "accept",
          sources: [source({ title: "Guarded road" })],
        }),
      }),
    },
  });
  return writeText;
}

describe("preparing a task", () => {
  it("leaves the sources out until the reader ticks them", async () => {
    prepare();
    const preview = () => wrapper.get("#decision-task-preview").text();
    expect(preview()).toContain("The party avoids the road.");
    expect(preview()).toContain("It creates a difficult choice.");
    expect(preview()).not.toContain("Guarded road");
    expect(preview()).toContain("?decision=4");

    await wrapper.get("#decision-task-part-sources").trigger("click");
    expect(preview()).toContain("Guarded road");
    await wrapper.get("#decision-task-part-reason").trigger("click");
    expect(preview()).not.toContain("It creates a difficult choice.");
  });

  it("copies exactly the previewed text", async () => {
    const writeText = prepare();
    await wrapper.get("#decision-task-copy").trigger("click");
    await flushPromises();
    expect(writeText).toHaveBeenCalledWith(wrapper.get("#decision-task-preview").text());
    expect(wrapper.get("#decision-task-copy").text()).toContain("Copied");
  });

  it("asks the reader to copy by hand when the clipboard refuses", async () => {
    prepare(vi.fn().mockRejectedValue(new Error("denied")));
    await wrapper.get("#decision-task-copy").trigger("click");
    await flushPromises();
    expect(wrapper.get("[role=alert]").text()).toContain("copy it by hand");
  });

  it("closes without copying", async () => {
    const writeText = prepare();
    await wrapper
      .findAll("button")
      .find((button) => button.text() === "Close")!
      .trigger("click");
    expect(wrapper.emitted("close")).toHaveLength(1);
    expect(writeText).not.toHaveBeenCalled();
  });
});
