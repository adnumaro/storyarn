import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { createMockLive } from "../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: ColorPickerPopover } =
  await import("../../../components/forms/ColorPickerPopover.vue");

function mountPicker() {
  return mount(ColorPickerPopover, {
    props: {
      color: "#3b82f6",
      event: "set_color",
    },
    global: {
      stubs: {
        Popover: { template: "<div><slot /></div>" },
        PopoverTrigger: { template: "<div><slot /></div>" },
        PopoverContent: { template: "<div><slot /></div>" },
      },
    },
  });
}

function dispatchColorChange(wrapper: VueWrapper, hex: string) {
  wrapper.find("hex-color-picker").element.dispatchEvent(
    new CustomEvent("color-changed", {
      detail: { value: hex },
    }),
  );
}

describe("ColorPickerPopover", () => {
  let wrapper: VueWrapper | null = null;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    vi.useRealTimers();
  });

  it("debounces color updates during normal interaction", () => {
    wrapper = mountPicker();

    dispatchColorChange(wrapper, "#ff0000");

    expect(wrapper.emitted("update:color")).toBeUndefined();
    expect(mockLive.pushEvent).not.toHaveBeenCalled();

    vi.advanceTimersByTime(150);

    expect(wrapper.emitted("update:color")).toEqual([["#ff0000"]]);
    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_color", { value: "#ff0000" });
  });

  it("flushes a pending color update before unmount", () => {
    wrapper = mountPicker();

    dispatchColorChange(wrapper, "#111111");
    dispatchColorChange(wrapper, "#00ff00");
    vi.advanceTimersByTime(149);

    expect(wrapper.emitted("update:color")).toBeUndefined();

    wrapper.unmount();

    expect(wrapper.emitted("update:color")).toEqual([["#00ff00"]]);
    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_color", { value: "#00ff00" });

    vi.advanceTimersByTime(1);

    expect(wrapper.emitted("update:color")).toHaveLength(1);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);
    wrapper = null;
  });
});
