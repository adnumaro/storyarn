import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../setup";
import type { Block } from "../../../modules/sheets/types";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

// Import after the mock so both the component and `useServerSearch` resolve to it.
const { default: ReferenceBlock } =
  await import("../../../modules/sheets/components/entities/blocks/fields/ReferenceBlock.vue");

const passthrough = { template: "<div><slot /></div>" };

const BLOCK: Block = {
  id: 42,
  type: "reference",
  config: { label: "Owner" },
  reference_target: null,
};

function mountIt() {
  return mount(ReferenceBlock, {
    props: { block: BLOCK, canEdit: true },
    global: {
      stubs: {
        Popover: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
      },
    },
  });
}

function typeQuery(wrapper: ReturnType<typeof mountIt>, value: string) {
  return wrapper.find("[data-slot='command-input']").setValue(value);
}

describe("ReferenceBlock search", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces consecutive keystrokes into a single search push", async () => {
    const wrapper = mountIt();

    await typeQuery(wrapper, "a");
    await typeQuery(wrapper, "ab");

    // Nothing has left the client yet — this is what the direct-pushEvent
    // bypass used to defeat, sending one request per keystroke.
    expect(mockLive.pushEvent).not.toHaveBeenCalled();

    vi.advanceTimersByTime(300);

    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "search_references",
      { query: "ab", "block-id": 42 },
      expect.any(Function),
    );
  });

  it("shows the searching state between the keystroke and the server response", async () => {
    const wrapper = mountIt();

    await typeQuery(wrapper, "ab");

    // `loading` flips synchronously inside `search()`, so the in-flight copy is
    // reachable — with the bypass it never was, and the user read "No results."
    expect(wrapper.text()).toContain("Searching...");
    expect(wrapper.text()).not.toContain("No results.");

    vi.advanceTimersByTime(300);
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain("Searching...");

    // Server answers via the pushEvent callback.
    const respond = vi.mocked(mockLive.pushEvent).mock.calls[0][2] as () => void;
    respond();
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).not.toContain("Searching...");
    expect(wrapper.text()).toContain("No results.");
  });

  it("feeds the typed query back into the input binding", async () => {
    const wrapper = mountIt();

    await typeQuery(wrapper, "ab");

    // Assert the bound prop, not the DOM value: `CommandInput` keeps its own
    // internal search state, so the rendered input reads "ab" either way. Only
    // `modelValue` shows whether `query` actually tracks what was typed — it
    // stayed frozen at "" while the composable's `search()` was bypassed.
    expect(wrapper.findComponent({ name: "CommandInput" }).props("modelValue")).toBe("ab");
  });
});
