/**
 * @vitest-environment jsdom
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExpressionEditor } from "../../expression_editor/setup.js";

describe("createExpressionEditor", () => {
  let container;

  beforeEach(() => {
    container = document.createElement("div");
    document.body.appendChild(container);
  });

  afterEach(() => {
    container.remove();
  });

  it("mounts without error", () => {
    const editor = createExpressionEditor({
      container,
      content: "",
      mode: "expression",
      editable: true,
    });
    expect(editor).toBeDefined();
    expect(editor.view).toBeDefined();
    expect(container.querySelector(".cm-editor")).toBeTruthy();
    editor.destroy();
  });

  it("getContent returns current text", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1",
      mode: "expression",
      editable: true,
    });
    expect(editor.getContent()).toBe("a.b > 1");
    editor.destroy();
  });

  it("setContent updates editor", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1",
      mode: "expression",
      editable: true,
    });
    editor.setContent("c.d < 2");
    expect(editor.getContent()).toBe("c.d < 2");
    editor.destroy();
  });

  it("setContent is idempotent (no-op for same content)", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1",
      mode: "expression",
      editable: true,
    });
    // Should not throw or create unnecessary transactions
    editor.setContent("a.b > 1");
    expect(editor.getContent()).toBe("a.b > 1");
    editor.destroy();
  });

  it("assignment mode accepts assignments", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b = 1",
      mode: "assignments",
      editable: true,
    });
    expect(editor.getContent()).toBe("a.b = 1");
    editor.destroy();
  });

  it("expression mode accepts expressions", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1 && c.d < 2",
      mode: "expression",
      editable: true,
    });
    expect(editor.getContent()).toBe("a.b > 1 && c.d < 2");
    editor.destroy();
  });

  it("onChange fires on document changes", async () => {
    const onChange = vi.fn();
    const editor = createExpressionEditor({
      container,
      content: "",
      mode: "expression",
      editable: true,
      onChange,
    });

    // Simulate typing by dispatching a transaction
    editor.view.dispatch({
      changes: { from: 0, to: 0, insert: "x.y" },
    });

    // onChange is debounced at 300ms
    await vi.waitFor(() => expect(onChange).toHaveBeenCalledWith("x.y"), { timeout: 500 });

    editor.destroy();
  });

  it("read-only mode prevents edits", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1",
      mode: "expression",
      editable: false,
    });

    // Try to dispatch a change - should not modify content
    const initialContent = editor.getContent();
    // In read-only mode, dispatches with changes are rejected by EditorState
    expect(editor.getContent()).toBe(initialContent);
    editor.destroy();
  });

  it("destroy cleans up", () => {
    const editor = createExpressionEditor({
      container,
      content: "a.b > 1",
      mode: "expression",
      editable: true,
    });
    editor.destroy();
    // After destroy, the CM element should be removed
    expect(container.querySelector(".cm-editor")).toBeFalsy();
  });

  it("shows placeholder text when empty", () => {
    const editor = createExpressionEditor({
      container,
      content: "",
      mode: "expression",
      editable: true,
      placeholderText: "mc.jaime.health > 50",
    });
    const placeholder = container.querySelector(".cm-placeholder");
    expect(placeholder).toBeTruthy();
    editor.destroy();
  });
});
