import { afterEach, describe, expect, it } from "vitest";
import {
  capturePendingHistoryScroll,
  clearPendingHistoryScroll,
  clearRememberedHistoryScroll,
  consumeHistoryScroll,
  rememberCurrentHistoryScroll,
} from "../../../shared/navigation/historyScroll";

const initialScrollY = Object.getOwnPropertyDescriptor(window, "scrollY");

afterEach(() => {
  clearPendingHistoryScroll();
  clearRememberedHistoryScroll(window.history.state);
  window.history.replaceState(null, "", window.location.href);
  if (initialScrollY) Object.defineProperty(window, "scrollY", initialScrollY);
});

describe("historyScroll", () => {
  it("keeps the popstate scroll even if the live history entry changes before mount", () => {
    Object.defineProperty(window, "scrollY", { configurable: true, value: 0 });
    const landingState = { id: "landing-view", position: 0, scroll: 0 };
    window.history.replaceState(landingState, "", window.location.href);
    rememberCurrentHistoryScroll();

    const overwrittenState = { ...landingState, scroll: 495 };
    window.history.replaceState(overwrittenState, "", window.location.href);
    capturePendingHistoryScroll(overwrittenState);

    expect(consumeHistoryScroll()).toBe(0);
    expect(consumeHistoryScroll()).toBe(495);
  });
});
