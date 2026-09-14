import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import TimerDigits from "@modules/ideation/components/TimerDigits.vue";
import { formatSeconds, parseDuration } from "@modules/ideation/composables/useTimerWrites";

describe("timer durations", () => {
  it.each([
    ["5", 300],
    [" 2 ", 120],
    ["0:45", 45],
    ["1:30", 90],
    ["90:00", 5400],
    ["1:00:00", 3600],
    ["24:00:00", 86_400],
  ])("reads %s as %i seconds", (text, seconds) => {
    expect(parseDuration(text)).toBe(seconds);
  });

  it.each(["", "0", "0:00", "abc", "1:60", "-5", "1.5", "24:00:01", "1:2:3:4", "1440:01"])(
    "refuses %s",
    (text) => {
      expect(parseDuration(text)).toBeNull();
    },
  );

  it("formats m:ss below an hour and h:mm:ss from an hour up", () => {
    expect(formatSeconds(0)).toBe("0:00");
    expect(formatSeconds(90)).toBe("1:30");
    expect(formatSeconds(3600)).toBe("1:00:00");
    expect(formatSeconds(86_400)).toBe("24:00:00");
  });
});

describe("timer digits", () => {
  let wrapper: VueWrapper;
  afterEach(() => wrapper?.unmount());
  const input = () => wrapper.get("#brainstorming-timer-input");
  const start = () => wrapper.get("#brainstorming-timer-start");

  it("starts with what was typed, in seconds, on Enter or play", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 300 } });
    expect((input().element as HTMLInputElement).value).toBe("5:00");
    await input().setValue("1:30");
    await input().trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("update:seconds")).toEqual([[90]]);
    expect(wrapper.emitted("start")).toEqual([[90]]);
    await input().setValue("7");
    await start().trigger("click");
    expect(wrapper.emitted("start")?.[1]).toEqual([420]);
    expect((input().element as HTMLInputElement).value).toBe("7:00");
  });

  it("puts the last good value back when the text makes no sense, and disables play meanwhile", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 300 } });
    await input().setValue("abc");
    expect(start().attributes("disabled")).toBeDefined();
    await input().trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("start")).toBeUndefined();
    await input().trigger("blur");
    expect((input().element as HTMLInputElement).value).toBe("5:00");
    expect(start().attributes("disabled")).toBeUndefined();
  });

  it("follows the seconds it is given and waits while a write is pending", async () => {
    wrapper = mount(TimerDigits, { props: { seconds: 60, pending: true } });
    expect(input().attributes("disabled")).toBeDefined();
    expect(start().attributes("disabled")).toBeDefined();
    await wrapper.setProps({ seconds: 3600, pending: false });
    expect((input().element as HTMLInputElement).value).toBe("1:00:00");
    await start().trigger("click");
    expect(wrapper.emitted("start")).toEqual([[3600]]);
    expect(wrapper.emitted("update:seconds")).toBeUndefined();
  });
});
