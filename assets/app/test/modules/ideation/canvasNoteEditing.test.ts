import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { nextTick } from "vue";
import { EditorContent, type Editor } from "@tiptap/vue-3";
import CanvasNote from "@modules/ideation/components/CanvasNote.vue";
import { idea } from "./fixtures";

const mounted: VueWrapper[] = [];
async function note() {
  const wrapper = mount(CanvasNote, {
    props: { note: idea(), body: "<p>Start</p>", editing: true, selected: true, author: "Alex" },
    attachTo: document.body,
  });
  mounted.push(wrapper);
  await nextTick();
  await nextTick();
  const editor = wrapper.getComponent(EditorContent).props("editor") as Editor;
  return { wrapper, editor };
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
});

describe("canvas note native undo", () => {
  it("keeps the current editor and local undo when quick-create is unavailable", async () => {
    const { wrapper, editor } = await note();
    await wrapper.setProps({ canCreate: false });
    editor.commands.setTextSelection(6);
    editor.commands.insertContent(" changed");
    editor.view.dom.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Enter",
        metaKey: true,
        bubbles: true,
        cancelable: true,
      }),
    );
    expect(wrapper.emitted("quickCreate")).toBeUndefined();
    expect(wrapper.emitted("finish")).toBeUndefined();
    expect(editor.isEditable).toBe(true);
    expect(editor.commands.undo()).toBe(true);
    expect(editor.getHTML()).toBe("<p>Start</p>");
  });

  it("preserves spaces while each keystroke is echoed through its body prop", async () => {
    const { wrapper, editor } = await note();
    editor.commands.setTextSelection(6);
    for (const character of " with spaces ") {
      editor.view.dispatch(editor.state.tr.insertText(character));
      await wrapper.setProps({ body: editor.getHTML() });
    }
    expect(editor.getText()).toBe("Start with spaces ");
    expect(editor.commands.undo()).toBe(true);
    expect(editor.getHTML()).toBe("<p>Start</p>");
  });
  it("retains typing history through server echoes, selection changes and the first persisted ID", async () => {
    const { wrapper, editor } = await note();
    editor.commands.setTextSelection(6);
    editor.commands.insertContent(" updated");
    const updated = editor.getHTML();
    await wrapper.setProps({
      body: updated,
      note: idea({ id: 20, body: updated }),
      editing: false,
    });
    await wrapper.setProps({ editing: true });
    expect(wrapper.getComponent(EditorContent).props("editor")).toBe(editor);
    expect(editor.commands.undo()).toBe(true);
    expect(editor.getHTML()).toBe("<p>Start</p>");
    expect(wrapper.emitted("change")?.at(-1)).toEqual(["<p>Start</p>"]);
    expect(editor.commands.redo()).toBe(true);
    expect(editor.getHTML()).toBe(updated);
  });
  it("compares document structure so equivalent HTML does not replace the local undo transaction", async () => {
    const { wrapper, editor } = await note();
    editor.commands.selectAll();
    editor.commands.insertContent("<p><strong>Revised</strong></p>");
    await wrapper.setProps({ body: "<p><b>Revised</b></p>" });
    expect(editor.getHTML()).toBe("<p><strong>Revised</strong></p>");
    expect(editor.commands.undo()).toBe(true);
    expect(editor.getHTML()).toBe("<p>Start</p>");
  });
  it("toggling edit mode reports no change and records no undo step", async () => {
    const { wrapper, editor } = await note();
    expect(editor.can().undo()).toBe(false);
    await wrapper.setProps({ editing: false });
    await wrapper.setProps({ editing: true });
    expect(wrapper.emitted("change")).toBeUndefined();
    expect(editor.can().undo()).toBe(false);
  });
  it("does not make an incoming server document into an undoable local edit", async () => {
    const { wrapper, editor } = await note();
    expect(editor.can().undo()).toBe(false);
    await wrapper.setProps({ body: "<p>Another contributor updated this text</p>" });
    expect(editor.getHTML()).toBe("<p>Another contributor updated this text</p>");
    expect(editor.can().undo()).toBe(false);
    expect(wrapper.emitted("change")).toBeUndefined();
  });
});
