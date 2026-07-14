import { afterEach, describe, expect, it, vi } from "vitest";
import {
  capturePendingHistoryScroll,
  consumeHistoryScroll,
  rememberCurrentHistoryScroll,
} from "../../../shared/navigation/historyScroll";

const initialScrollY = Object.getOwnPropertyDescriptor(window, "scrollY");

afterEach(() => {
  window.sessionStorage.clear();
  window.history.replaceState(null, "", window.location.href);
  document.getElementById("docs-main")?.remove();
  if (initialScrollY) Object.defineProperty(window, "scrollY", initialScrollY);
  vi.restoreAllMocks();
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

  it("captures and consumes the docs scroll surface independently from the window", () => {
    const docsMain = document.createElement("main");
    docsMain.id = "docs-main";
    docsMain.scrollTop = 320;
    document.body.append(docsMain);

    const docsState = { id: "docs-view", position: 1, scroll: 0 };
    window.history.replaceState(docsState, "", window.location.href);
    rememberCurrentHistoryScroll();

    docsMain.scrollTop = 0;
    capturePendingHistoryScroll(window.history.state);

    expect(consumeHistoryScroll(0, "docs-main")).toBe(320);
    expect(
      Array.from({ length: window.sessionStorage.length }, (_, index) =>
        window.sessionStorage.key(index),
      ).filter((key) => key?.startsWith("storyarn:history-scroll:")),
    ).toEqual([]);
  });

  it("restores numeric scroll entries stored before positions included a target", () => {
    window.sessionStorage.setItem("storyarn:pending-history-scroll", JSON.stringify(275));

    expect(consumeHistoryScroll()).toBe(275);
  });

  it("does not interrupt navigation when session storage rejects writes", () => {
    Object.defineProperty(window, "scrollY", { configurable: true, value: 120 });
    window.history.replaceState({ id: "landing-view", position: 0 }, "", window.location.href);
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("Quota exceeded", "QuotaExceededError");
    });

    expect(() => rememberCurrentHistoryScroll()).not.toThrow();
    expect(window.history.state.storyarnScroll).toEqual({ target: "window", top: 120 });
  });
});
