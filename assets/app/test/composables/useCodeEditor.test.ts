import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref, type Ref } from "vue";
import { useCodeEditor, type UseCodeEditorReturn } from "@shared/composables/useCodeEditor";
import type { ParsedCondition } from "@plugins/expression-editor/tree-parser";
import type { Variable } from "@shared/domain/variables";

const variables: Variable[] = [
  { sheet_shortcut: "mc", variable_name: "health", block_type: "number" },
  { sheet_shortcut: "mc", variable_name: "alive", block_type: "boolean" },
];

function mountCodeEditor(active: Ref<boolean>) {
  const onConditionChange = vi.fn<(condition: ParsedCondition) => void>();
  let editor!: UseCodeEditorReturn;

  const wrapper = mount(
    defineComponent({
      setup() {
        const container = ref<HTMLElement | null>(null);

        editor = useCodeEditor(container, {
          mode: "condition",
          variables,
          disabled: false,
          active,
          onConditionChange,
        });

        return () => h("div", { ref: container });
      },
    }),
    { attachTo: document.body },
  );

  return { editor, onConditionChange, wrapper };
}

describe("useCodeEditor", () => {
  let wrapper: VueWrapper | null = null;

  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    vi.useRealTimers();
  });

  it("emits parsed code changes after the debounce while active", () => {
    const active = ref(true);
    const mounted = mountCodeEditor(active);
    wrapper = mounted.wrapper;

    mounted.editor.setContent("mc.health > 50");

    vi.advanceTimersByTime(299);
    expect(mounted.onConditionChange).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(mounted.onConditionChange).toHaveBeenCalledTimes(1);
    expect(mounted.onConditionChange.mock.calls[0][0].rules[0]).toMatchObject({
      sheet: "mc",
      variable: "health",
      operator: "greater_than",
      value: "50",
    });
  });

  it("cancels pending parsed code changes when the editor becomes inactive", async () => {
    const active = ref(true);
    const mounted = mountCodeEditor(active);
    wrapper = mounted.wrapper;

    mounted.editor.setContent("mc.health > 50");
    active.value = false;
    await nextTick();

    vi.advanceTimersByTime(300);

    expect(mounted.onConditionChange).not.toHaveBeenCalled();
  });
});
