import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { liveNavigate } from "../../../shared/navigation/liveNavigate";
import { rememberCurrentHistoryScroll } from "../../../shared/navigation/historyScroll";

vi.mock("../../../shared/navigation/historyScroll", () => ({
  rememberCurrentHistoryScroll: vi.fn(),
}));

interface CapturedClick {
  href: string;
  phxLink: string | null;
  phxLinkState: string | null;
}

describe("liveNavigate", () => {
  let captured: CapturedClick[] = [];

  function captureClicks(event: Event): void {
    const anchor = (event.target as HTMLElement).closest("a");
    if (!anchor) return;

    event.preventDefault();
    captured.push({
      href: anchor.getAttribute("href") ?? "",
      phxLink: anchor.getAttribute("data-phx-link"),
      phxLinkState: anchor.getAttribute("data-phx-link-state"),
    });
  }

  beforeEach(() => {
    captured = [];
    document.addEventListener("click", captureClicks);
  });

  afterEach(() => {
    document.removeEventListener("click", captureClicks);
    vi.clearAllMocks();
  });

  it("dispatches a redirect click with push state and persists scroll by default", () => {
    liveNavigate("/workspaces/ws/projects/p");

    expect(captured).toEqual([
      { href: "/workspaces/ws/projects/p", phxLink: "redirect", phxLinkState: "push" },
    ]);
    expect(rememberCurrentHistoryScroll).toHaveBeenCalledTimes(1);
  });

  it("dispatches a patch click without persisting scroll", () => {
    liveNavigate("/somewhere", "patch", "replace");

    expect(captured).toEqual([{ href: "/somewhere", phxLink: "patch", phxLinkState: "replace" }]);
    expect(rememberCurrentHistoryScroll).not.toHaveBeenCalled();
  });

  it("removes the synthetic anchor after the click", () => {
    liveNavigate("/cleanup-check");

    expect(document.querySelector("a[data-phx-link]")).toBeNull();
  });
});
