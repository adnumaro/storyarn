import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import TimerDigits from "@modules/ideation/components/TimerDigits.vue";
import { formatSeconds, joinDigits } from "@modules/ideation/composables/useTimerWrites";

describe("timer durations", () => {
  it.each([
    ["05", "00", 300],
    ["", "45", 45],
    ["1", "30", 90],
    ["99", "59", 5999],
    ["0", "1", 1],
  ])("joins minutes %s and seconds %s into %i seconds", (minutes, seconds, total) => {
    expect(joinDigits(minutes, seconds)).toBe(total);
  });

  it.each([
    ["", ""],
    ["00", "00"],
    ["0", "60"],
    ["1", "75"],
    ["abc", "00"],
    ["123", "00"],
  ])("refuses minutes %s with seconds %s", (minutes, seconds) => {
    expect(joinDigits(minutes, seconds)).toBeNull();
  });

  it("formats mm:ss and keeps counting minutes past the hour", () => {
    expect(formatSeconds(0)).toBe("00:00");
    expect(formatSeconds(90)).toBe("01:30");
    expect(formatSeconds(3600)).toBe("60:00");
    expect(formatSeconds(86_400)).toBe("1440:00");
  });
});

describe("timer digits", () => {
  let wrapper: VueWrapper;
  afterEach(() => wrapper?.unmount());
  const minutes = () => wrapper.get("#brainstorming-timer-minutes");
  const seconds = () => wrapper.get("#brainstorming-timer-seconds");
  const start = () => wrapper.get("#brainstorming-timer-start");
  const value = (field: () => ReturnType<VueWrapper["get"]>) =>
    (field().element as HTMLInputElement).value;

  it("moves on to the seconds after two minute digits and starts on Enter or play", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 300 }, attachTo: document.body });
    expect(value(minutes)).toBe("05");
    expect(value(seconds)).toBe("00");
    await minutes().setValue("12");
    expect(document.activeElement).toBe(seconds().element);
    await seconds().setValue("30");
    await seconds().trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("update:seconds")?.at(-1)).toEqual([750]);
    expect(wrapper.emitted("start")).toEqual([[750]]);
    await minutes().setValue("7");
    await seconds().setValue("");
    await start().trigger("click");
    expect(wrapper.emitted("start")?.[1]).toEqual([420]);
    expect(value(minutes)).toBe("07");
    expect(value(seconds)).toBe("00");
  });

  it("keeps two digits per field, refuses an empty clock or 60 seconds, and settles on leaving", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 300 }, attachTo: document.body });
    await minutes().setValue("1234");
    expect(value(minutes)).toBe("12");
    await seconds().setValue("60");
    expect(start().attributes("disabled")).toBeDefined();
    await seconds().trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("start")).toBeUndefined();
    await seconds().trigger("focusout");
    expect(value(minutes)).toBe("05");
    expect(value(seconds)).toBe("00");
    expect(start().attributes("disabled")).toBeUndefined();
  });

  it("takes both digits on a click, so typing replaces them", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 300 }, attachTo: document.body });
    const field = minutes().element as HTMLInputElement;
    const event = new MouseEvent("mouseup", { bubbles: true, cancelable: true });
    field.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(field);
    expect(field.selectionStart).toBe(0);
    expect(field.selectionEnd).toBe(2);
  });

  it("goes back to the minutes on backspace over empty seconds and freezes while a write is pending", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 60 }, attachTo: document.body });
    await seconds().setValue("");
    await seconds().trigger("keydown", { key: "Backspace" });
    expect(document.activeElement).toBe(minutes().element);
    await wrapper.setProps({ seconds: 3600, pending: true });
    expect(value(minutes)).toBe("60");
    expect(minutes().attributes("disabled")).toBeDefined();
    expect(seconds().attributes("disabled")).toBeDefined();
    expect(start().attributes("disabled")).toBeDefined();
  });
});
