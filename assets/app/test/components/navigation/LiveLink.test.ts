import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vitest";
import LiveLink from "../../../components/navigation/LiveLink.vue";
import { clearRememberedHistoryScroll } from "../../../shared/navigation/historyScroll";

const initialUrl = window.location.href;
const initialScrollY = Object.getOwnPropertyDescriptor(window, "scrollY");

afterEach(() => {
  clearRememberedHistoryScroll(window.history.state);
  window.history.replaceState(null, "", initialUrl);
  if (initialScrollY) Object.defineProperty(window, "scrollY", initialScrollY);
});

describe("LiveLink", () => {
  it("stores a zero scroll position before a pushed LiveView navigation", async () => {
    Object.defineProperty(window, "scrollY", { configurable: true, value: 0 });
    window.history.replaceState(
      { type: "patch", id: "landing-view", position: 0 },
      "",
      window.location.href,
    );

    const wrapper = mount(LiveLink, {
      props: { to: "/users/register" },
      slots: { default: "Create account" },
      attrs: { onClick: (event: MouseEvent) => event.preventDefault() },
    });

    await wrapper.get("a").trigger("click");

    expect(window.history.state).toEqual({
      type: "patch",
      id: "landing-view",
      position: 0,
      scroll: 0,
      storyarnScroll: { target: "window", top: 0 },
    });
  });

  it("does not alter history for external links", async () => {
    Object.defineProperty(window, "scrollY", { configurable: true, value: 320 });
    window.history.replaceState({ marker: "unchanged" }, "", window.location.href);

    const wrapper = mount(LiveLink, {
      props: { to: "https://example.com", mode: "external" },
      slots: { default: "External" },
      attrs: { onClick: (event: MouseEvent) => event.preventDefault() },
    });

    await wrapper.get("a").trigger("click");

    expect(window.history.state).toEqual({ marker: "unchanged" });
  });
});
