import { describe, expect, it, vi } from "vitest";
import { PublicMobileNavigation } from "../../../js/utils/public_mobile_navigation.js";

type MediaQueryListener = (event: MediaQueryListEvent) => void;

function mockMatchMedia(initialMatches: boolean) {
  const listeners = new Set<MediaQueryListener>();
  const mediaQuery = {
    matches: initialMatches,
    media: "(min-width: 80rem)",
  } as MediaQueryList;
  const addEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.add(listener);
  });
  const removeEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.delete(listener);
  });

  Object.assign(mediaQuery, { addEventListener, removeEventListener });

  const matchMedia = vi.fn(() => mediaQuery);
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: matchMedia,
  });

  return {
    matchMedia,
    removeEventListener,
    dispatch(matches: boolean) {
      Object.assign(mediaQuery, { matches });
      listeners.forEach((listener) => listener({ matches } as MediaQueryListEvent));
    },
  };
}

function buildHook() {
  const element = document.createElement("div");
  element.setAttribute("aria-hidden", "false");
  element.setAttribute("data-close", "encoded-close-command");

  const exec = vi.fn(() => element.setAttribute("aria-hidden", "true"));
  const hook: {
    desktopMediaQuery?: MediaQueryList;
    el: HTMLElement;
    handleDesktopViewport?: (mediaQuery: MediaQueryList | MediaQueryListEvent) => void;
    handleKeydown?: (event: KeyboardEvent) => void;
    js: () => { exec: typeof exec };
  } = {
    el: element,
    js: () => ({ exec }),
  };

  return { element, exec, hook };
}

describe("PublicMobileNavigation hook", () => {
  it("closes an open mobile menu when the viewport becomes desktop", () => {
    const media = mockMatchMedia(false);
    const { exec, hook } = buildHook();

    PublicMobileNavigation.mounted.call(hook);
    expect(media.matchMedia).toHaveBeenCalledWith("(min-width: 80rem)");
    expect(exec).not.toHaveBeenCalled();

    media.dispatch(true);
    expect(exec).toHaveBeenCalledOnce();
    expect(exec).toHaveBeenCalledWith("encoded-close-command");

    PublicMobileNavigation.updated.call(hook);
    expect(exec).toHaveBeenCalledOnce();

    PublicMobileNavigation.destroyed.call(hook);
    expect(media.removeEventListener).toHaveBeenCalledWith("change", hook.handleDesktopViewport);
  });

  it("closes an already-open menu when mounted at desktop width", () => {
    mockMatchMedia(true);
    const { exec, hook } = buildHook();

    PublicMobileNavigation.mounted.call(hook);

    expect(exec).toHaveBeenCalledOnce();
    PublicMobileNavigation.destroyed.call(hook);
  });

  it("handles Escape only while the mobile menu is open", () => {
    mockMatchMedia(false);
    const { element, exec, hook } = buildHook();
    element.setAttribute("aria-hidden", "true");

    PublicMobileNavigation.mounted.call(hook);

    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    expect(exec).not.toHaveBeenCalled();

    element.setAttribute("aria-hidden", "false");
    const escapeEvent = new KeyboardEvent("keydown", { cancelable: true, key: "Escape" });
    window.dispatchEvent(escapeEvent);

    expect(exec).toHaveBeenCalledOnce();
    expect(escapeEvent.defaultPrevented).toBe(true);

    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    expect(exec).toHaveBeenCalledOnce();

    PublicMobileNavigation.destroyed.call(hook);
  });

  it("closes an open menu before removing listeners when destroyed", () => {
    const media = mockMatchMedia(false);
    const { element, exec, hook } = buildHook();

    PublicMobileNavigation.mounted.call(hook);
    PublicMobileNavigation.destroyed.call(hook);

    expect(exec).toHaveBeenCalledOnce();
    expect(exec.mock.invocationCallOrder[0]).toBeLessThan(
      media.removeEventListener.mock.invocationCallOrder[0],
    );

    element.setAttribute("aria-hidden", "false");
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    media.dispatch(true);

    expect(exec).toHaveBeenCalledOnce();
  });
});
