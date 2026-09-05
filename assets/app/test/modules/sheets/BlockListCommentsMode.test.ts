import { mount } from "@vue/test-utils";
import { defineComponent, inject, nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";
import BlockList from "@modules/sheets/components/entities/blocks/BlockList.vue";

const TextBlockStub = defineComponent({
  props: { block: { type: Object, required: true } },
  setup(props) {
    const selectBlock = inject<(id: number) => void>("selectBlock", () => {});
    return { props, selectBlock };
  },
  template:
    '<button data-testid="select-block" @click="selectBlock(Number(props.block.id))">Block</button>',
});

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("BlockList comment mode", () => {
  it("releases the selected block lock and neutralizes shortcuts during comment UI", async () => {
    const live = createMockLive();
    const wrapper = mount(BlockList, {
      props: {
        blocks: [],
        inheritedGroups: [
          {
            sourceSheet: { id: 3, name: "Base character" },
            blocks: [{ id: 42, type: "text", config: { label: "Health" } }],
          },
        ],
        canEdit: true,
        workspaceSlug: "workspace",
        projectSlug: "project",
        blockLocks: {},
        currentUserId: 4,
        commentsActive: false,
        commentsPlacing: false,
      },
      global: {
        provide: { _live_vue: live },
        stubs: {
          DnDProvider: { template: "<div><slot /></div>" },
          BlockDndRoot: true,
          TextBlock: TextBlockStub,
          AddBlockMenu: true,
          FormulaPanel: true,
          UserAvatar: true,
        },
      },
    });

    await wrapper.get('[data-testid="select-block"]').trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "acquire_block_lock",
      { block_id: 42 },
      undefined,
    );

    await wrapper.setProps({ commentsActive: true, commentsPlacing: true });
    await nextTick();
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "release_block_lock",
      { block_id: 42 },
      undefined,
    );

    expect(wrapper.get("[data-sheet-block-id='42']").attributes("tabindex")).toBe("0");
    expect(wrapper.get("[data-sheet-block-id='42']").attributes("aria-describedby")).toBe(
      "sheet-comment-block-keyboard-instructions",
    );

    vi.mocked(live.pushEvent).mockClear();
    document.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Delete",
        bubbles: true,
        cancelable: true,
      }),
    );
    document.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "d",
        metaKey: true,
        bubbles: true,
        cancelable: true,
      }),
    );
    document.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "z",
        ctrlKey: true,
        bubbles: true,
        cancelable: true,
      }),
    );
    expect(live.pushEvent).not.toHaveBeenCalled();

    wrapper.unmount();
  });
});
