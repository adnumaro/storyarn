import { afterEach, describe, expect, it, vi } from "vitest";
import { createLiveVue, getHooks, useLiveVue, type LiveHook } from "live_vue";
import { defineComponent, h, nextTick, onMounted, onUnmounted, ref } from "vue";

type MountedHook = LiveHook & {
  mounted: () => void | Promise<void>;
  updated: () => void;
  destroyed: () => void;
};

const cleanup: Array<() => void> = [];
afterEach(async () => {
  cleanup
    .splice(0)
    .reverse()
    .forEach((dispose) => dispose());
  window.dispatchEvent(new Event("phx:page-loading-stop"));
  await nextTick();
  document.body.replaceChildren();
});

function setup() {
  const boardMounted = vi.fn();
  const boardUnmounted = vi.fn();
  const headerMounted = vi.fn();
  const headerUnmounted = vi.fn();
  const owners: LiveHook[] = [];
  const Board = defineComponent({
    props: { title: String },
    setup(props) {
      const selected = ref(false);
      const draft = ref("");
      owners.push(useLiveVue());
      onMounted(boardMounted);
      onUnmounted(boardUnmounted);
      return () =>
        h("article", { id: "injected-board" }, [
          h("p", props.title),
          h(
            "button",
            { "aria-pressed": selected.value, onClick: () => (selected.value = true) },
            "Select group",
          ),
          h("textarea", {
            value: draft.value,
            onInput: (event: Event) => (draft.value = (event.target as HTMLTextAreaElement).value),
          }),
        ]);
    },
  });
  const Header = defineComponent({
    props: { title: String },
    setup(props) {
      onMounted(headerMounted);
      onUnmounted(headerUnmounted);
      return () => h("header", { id: "injected-header" }, props.title);
    },
  });
  const Layout = defineComponent({
    setup(_, { slots }) {
      return () => h("main", [slots.header?.(), slots.default?.()]);
    },
  });
  const components = { Layout, Board, Header };
  const liveVue = createLiveVue({ resolve: (name) => components[name as keyof typeof components] });
  const { VueHook } = getHooks(liveVue);

  async function mountHook(
    id: string,
    name: keyof typeof components,
    title = "Original",
    slot = "default",
  ) {
    const el = document.createElement("div");
    el.id = id;
    el.setAttribute("data-name", name);
    el.setAttribute("data-props", JSON.stringify({ title }));
    el.setAttribute("data-use-diff", "true");
    if (name !== "Layout") {
      el.setAttribute("data-inject", "injection-layout");
      el.setAttribute("data-inject-slot", slot);
    }
    document.body.append(el);
    const hook = {
      ...VueHook,
      el,
      liveSocket: {},
      pushEvent: vi.fn(),
      handleEvent: vi.fn(),
      removeHandleEvent: vi.fn(),
    } as unknown as MountedHook;
    await hook.mounted();
    await nextTick();
    let active = true;
    const destroy = () => {
      if (!active) return;
      active = false;
      hook.destroyed();
      el.remove();
    };
    cleanup.push(destroy);
    return { hook, destroy };
  }

  async function update(hook: MountedHook, title?: string) {
    // Use the same compact prop patch consumed by production's VueHook.updated.
    hook.el.setAttribute(
      "data-props-diff",
      title === undefined ? "" : `r6:/titles${title.length}:${title}`,
    );
    hook.updated();
    await nextTick();
  }

  return {
    mountHook,
    update,
    boardMounted,
    boardUnmounted,
    headerMounted,
    headerUnmounted,
    owners,
  };
}

function editBoard() {
  const button = document.querySelector<HTMLButtonElement>("#injected-board button")!;
  const input = document.querySelector<HTMLTextAreaElement>("#injected-board textarea")!;
  button.click();
  input.value = "Unsaved group synthesis";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.focus();
  return { button, input };
}

describe("LiveVue injected editor identity", () => {
  it("retains selection, drafts and focus across prop updates and other injected slots", async () => {
    const ctx = setup();
    const layout = await ctx.mountHook("injection-layout", "Layout");
    const board = await ctx.mountHook("injection-board", "Board");
    const { button, input } = editBoard();
    await nextTick();

    await ctx.update(layout.hook, "Presence refreshed");
    await ctx.update(board.hook, "Collaborator title");
    const header = await ctx.mountHook("injection-header", "Header", "Presence", "header");
    await ctx.update(layout.hook, "Header connected");
    await ctx.update(header.hook, "Two participants");
    await ctx.update(layout.hook, "Participants refreshed");
    header.destroy();
    await ctx.update(layout.hook, "Header removed");

    expect(document.querySelector("#injected-board textarea")).toBe(input);
    expect(document.querySelector("#injected-board button")).toBe(button);
    expect(button.getAttribute("aria-pressed")).toBe("true");
    expect(input.value).toBe("Unsaved group synthesis");
    expect(document.activeElement).toBe(input);
    expect(document.querySelector("#injected-board p")?.textContent).toBe("Collaborator title");
    expect(ctx.boardMounted).toHaveBeenCalledOnce();
    expect(ctx.boardUnmounted).not.toHaveBeenCalled();
    expect(ctx.owners).toEqual([board.hook]);
    expect(ctx.headerUnmounted).toHaveBeenCalledOnce();
  });

  it("removes only the departed injector and gives its replacement fresh state and ownership", async () => {
    const ctx = setup();
    const layout = await ctx.mountHook("injection-layout", "Layout");
    await ctx.mountHook("injection-header", "Header", "Presence", "header");
    const header = document.querySelector("#injected-header");
    const board = await ctx.mountHook("injection-board", "Board");
    await ctx.update(layout.hook, "Board connected");
    const { input } = editBoard();
    await nextTick();

    board.destroy();
    await ctx.update(layout.hook, "Board removed");
    expect(document.querySelector("#injected-board")).toBeNull();
    expect(ctx.boardUnmounted).toHaveBeenCalledOnce();
    expect(document.querySelector("#injected-header")).toBe(header);
    expect(ctx.headerUnmounted).not.toHaveBeenCalled();

    const replacement = await ctx.mountHook("injection-board", "Board", "New session");
    await ctx.update(layout.hook, "Board replaced");
    const fresh = document.querySelector<HTMLTextAreaElement>("#injected-board textarea")!;
    expect(fresh).not.toBe(input);
    expect(fresh.value).toBe("");
    expect(document.querySelector("#injected-board button")?.getAttribute("aria-pressed")).toBe(
      "false",
    );
    expect(ctx.owners).toEqual([board.hook, replacement.hook]);
    expect(ctx.boardMounted).toHaveBeenCalledTimes(2);
    expect(ctx.headerMounted).toHaveBeenCalledOnce();

    replacement.destroy();
    await ctx.update(layout.hook, "Replacement removed");
    expect(ctx.boardUnmounted).toHaveBeenCalledTimes(2);
    expect(document.querySelector("#injected-header")).toBe(header);
  });
});
