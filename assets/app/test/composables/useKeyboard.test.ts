import { withSetup } from "../setup";
import { useKeyboard, type KeyboardBindings } from "../../shared/composables/useKeyboard";

function fireKey(
  target: EventTarget,
  key: string,
  mods: { ctrl?: boolean; shift?: boolean; alt?: boolean; meta?: boolean } = {},
) {
  const event = new KeyboardEvent("keydown", {
    key,
    ctrlKey: mods.ctrl || false,
    shiftKey: mods.shift || false,
    altKey: mods.alt || false,
    metaKey: mods.meta || false,
    bubbles: true,
    cancelable: true,
  });
  target.dispatchEvent(event);
  return event;
}

describe("useKeyboard", () => {
  describe("key combo building", () => {
    it("matches a plain key", () => {
      const handler = vi.fn();
      const bindings: KeyboardBindings = { delete: handler };

      const { app } = withSetup(() => useKeyboard(bindings));
      fireKey(document, "Delete");
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });

    it("matches ctrl+key (via ctrlKey)", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ "ctrl+z": handler }));

      fireKey(document, "z", { ctrl: true });
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });

    it("matches ctrl+key (via metaKey for Mac)", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ "ctrl+z": handler }));

      fireKey(document, "z", { meta: true });
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });

    it("matches ctrl+shift+key", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ "ctrl+shift+z": handler }));

      fireKey(document, "z", { ctrl: true, shift: true });
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });

    it("matches alt+key", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ "alt+s": handler }));

      fireKey(document, "s", { alt: true });
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });

    it("does not fire when combo does not match", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ "ctrl+z": handler }));

      fireKey(document, "z"); // no ctrl
      expect(handler).not.toHaveBeenCalled();
      app.unmount();
    });

    it("normalizes key to lowercase", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ escape: handler }));

      fireKey(document, "Escape");
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });
  });

  describe("editable target detection", () => {
    it("ignores events from INPUT elements", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ delete: handler }));

      const input = document.createElement("input");
      document.body.appendChild(input);

      const event = new KeyboardEvent("keydown", {
        key: "Delete",
        bubbles: true,
      });
      Object.defineProperty(event, "target", { value: input });
      document.dispatchEvent(event);

      expect(handler).not.toHaveBeenCalled();
      document.body.removeChild(input);
      app.unmount();
    });

    it("ignores events from TEXTAREA elements", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ delete: handler }));

      const textarea = document.createElement("textarea");
      document.body.appendChild(textarea);

      const event = new KeyboardEvent("keydown", {
        key: "Delete",
        bubbles: true,
      });
      Object.defineProperty(event, "target", { value: textarea });
      document.dispatchEvent(event);

      expect(handler).not.toHaveBeenCalled();
      document.body.removeChild(textarea);
      app.unmount();
    });

    it("ignores events from contentEditable elements", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ delete: handler }));

      const div = document.createElement("div");
      div.contentEditable = "true";
      // jsdom does not implement isContentEditable, so we define it manually
      Object.defineProperty(div, "isContentEditable", { value: true });
      document.body.appendChild(div);

      div.dispatchEvent(new KeyboardEvent("keydown", { key: "Delete", bubbles: true }));

      expect(handler).not.toHaveBeenCalled();
      document.body.removeChild(div);
      app.unmount();
    });

    it("allows only explicitly opted-in bindings inside editable targets", () => {
      const closePalette = vi.fn();
      const deleteItem = vi.fn();
      const { app } = withSetup(() =>
        useKeyboard(
          { "ctrl+k": closePalette, delete: deleteItem },
          { allowInEditable: (combo) => combo === "ctrl+k" },
        ),
      );

      const input = document.createElement("input");
      document.body.appendChild(input);

      input.dispatchEvent(new KeyboardEvent("keydown", { key: "k", ctrlKey: true, bubbles: true }));
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Delete", bubbles: true }));

      expect(closePalette).toHaveBeenCalledOnce();
      expect(deleteItem).not.toHaveBeenCalled();
      input.remove();
      app.unmount();
    });
  });

  describe("preventDefault behavior", () => {
    it("calls preventDefault by default", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ escape: handler }));

      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      const preventSpy = vi.spyOn(event, "preventDefault");
      const stopSpy = vi.spyOn(event, "stopPropagation");
      document.dispatchEvent(event);

      expect(preventSpy).toHaveBeenCalled();
      expect(stopSpy).toHaveBeenCalled();
      app.unmount();
    });

    it("does not call preventDefault when prevent is false", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ escape: handler }, { prevent: false }));

      const event = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      const preventSpy = vi.spyOn(event, "preventDefault");
      document.dispatchEvent(event);

      expect(handler).toHaveBeenCalled();
      expect(preventSpy).not.toHaveBeenCalled();
      app.unmount();
    });
  });

  describe("custom target", () => {
    it("listens on a custom target instead of document", () => {
      const handler = vi.fn();
      const customTarget = new EventTarget();

      const { app } = withSetup(() => useKeyboard({ escape: handler }, { target: customTarget }));

      fireKey(document, "Escape");
      expect(handler).not.toHaveBeenCalled();

      fireKey(customTarget, "Escape");
      expect(handler).toHaveBeenCalledOnce();
      app.unmount();
    });
  });

  describe("cleanup on unmount", () => {
    it("removes the event listener on unmount", () => {
      const handler = vi.fn();
      const { app } = withSetup(() => useKeyboard({ escape: handler }));

      fireKey(document, "Escape");
      expect(handler).toHaveBeenCalledOnce();

      app.unmount();

      fireKey(document, "Escape");
      expect(handler).toHaveBeenCalledOnce(); // still 1, not 2
    });
  });

  describe("multiple bindings", () => {
    it("routes different combos to different handlers", () => {
      const undoHandler = vi.fn();
      const redoHandler = vi.fn();
      const deleteHandler = vi.fn();

      const { app } = withSetup(() =>
        useKeyboard({
          "ctrl+z": undoHandler,
          "ctrl+shift+z": redoHandler,
          delete: deleteHandler,
        }),
      );

      fireKey(document, "z", { ctrl: true });
      fireKey(document, "Delete");

      expect(undoHandler).toHaveBeenCalledOnce();
      expect(redoHandler).not.toHaveBeenCalled();
      expect(deleteHandler).toHaveBeenCalledOnce();
      app.unmount();
    });
  });
});
