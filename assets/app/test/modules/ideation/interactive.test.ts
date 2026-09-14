import { describe, expect, it } from "vitest";
import { interactivePath, interactiveTarget } from "@modules/ideation/lib/interactive";

describe("interactive targets on the canvas", () => {
  it("recognises the chrome even when the clicked text was replaced before the canvas saw the event", () => {
    const root = document.createElement("div");
    const chrome = document.createElement("div");
    chrome.setAttribute("data-canvas-chrome", "");
    const text = document.createElement("span");
    chrome.append(text);
    root.append(chrome);
    document.body.append(root);
    // In a browser Vue swaps the round question for an input between the
    // header's listener and the canvas one, so the canvas gets a detached target.
    text.addEventListener("dblclick", () => text.remove());
    let seen: boolean[] = [];
    root.addEventListener("dblclick", (event) => {
      seen = [interactiveTarget(event.target), interactivePath(event)];
    });
    text.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }));
    expect(seen).toEqual([false, true]);
    root.remove();
  });

  it("treats plain canvas ground as free", () => {
    const ground = document.createElement("div");
    document.body.append(ground);
    let path = true;
    ground.addEventListener("click", (event) => {
      path = interactivePath(event);
    });
    ground.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(interactiveTarget(ground)).toBe(false);
    expect(path).toBe(false);
    ground.remove();
  });
});
