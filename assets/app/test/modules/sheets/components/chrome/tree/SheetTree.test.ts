import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SheetTree from "../../../../../../modules/sheets/components/chrome/tree/SheetTree.vue";
import { createMockLive } from "../../../../../setup";

function mountTree(permissions: { canEdit: boolean; canDelete: boolean }) {
  const wrapper = mount(SheetTree, {
    props: {
      sheetsTree: [{ id: 1, name: "Old draft", children: [] }],
      workspaceSlug: "writers-room",
      projectSlug: "veilbreak",
      ...permissions,
    },
    global: { provide: { _live_vue: createMockLive() } },
  });

  return { wrapper };
}

const button = (wrapper: ReturnType<typeof mount>, title: string) =>
  wrapper.findAll("button").find((candidate) => candidate.attributes("title") === title);

describe("SheetTree permissions", () => {
  it("offers creating and deleting to someone who can edit", () => {
    const { wrapper } = mountTree({ canEdit: true, canDelete: true });

    expect(button(wrapper, "Add child sheet")).toBeDefined();
    expect(button(wrapper, "Move to Trash")).toBeDefined();
    expect(wrapper.text()).toContain("New Sheet");
  });

  it("keeps deleting, and nothing else, while the workspace is read-only", () => {
    const { wrapper } = mountTree({ canEdit: false, canDelete: true });

    expect(button(wrapper, "Add child sheet")).toBeUndefined();
    expect(button(wrapper, "Move to Trash")).toBeDefined();
    expect(wrapper.text()).not.toContain("New Sheet");
  });

  it("offers nothing to a viewer", () => {
    const { wrapper } = mountTree({ canEdit: false, canDelete: false });

    expect(button(wrapper, "Add child sheet")).toBeUndefined();
    expect(button(wrapper, "Move to Trash")).toBeUndefined();
  });
});
