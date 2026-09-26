import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import TemplateList from "../../../live/template/list/TemplateList.vue";
import type { TemplateCardItem, TemplateSection } from "../../../live/template/types";
import { createMockLive } from "../../setup";

/** The events the page pushed, each as its name and payload. */
function pushed(live: ReturnType<typeof createMockLive>) {
  return vi.mocked(live.pushEvent).mock.calls.map(([event, payload]) => [event, payload]);
}

function card(overrides: Partial<TemplateCardItem> = {}): TemplateCardItem {
  return {
    id: 7,
    name: "Harbor Starter",
    description: "A port town",
    visibility: "private",
    versionNumber: 2,
    updatedAt: "2026-09-20T10:00:00Z",
    previewNames: ["Captain", "Docks"],
    canManage: true,
    href: "/templates/7",
    ...overrides,
  };
}

function section(
  key: TemplateSection["key"],
  templates: TemplateCardItem[],
  overrides: Partial<TemplateSection> = {},
): TemplateSection {
  return {
    key,
    templates,
    totalCount: templates.length,
    page: 1,
    totalPages: 1,
    prevHref: null,
    nextHref: null,
    ...overrides,
  };
}

function mountList(props: Partial<InstanceType<typeof TemplateList>["$props"]> = {}) {
  const live = createMockLive();
  const wrapper = mount(TemplateList, {
    props: {
      sections: [section("private", [card()]), section("public", []), section("archived", [])],
      workspacesHref: "/workspaces",
      ...props,
    },
    global: { provide: { _live_vue: live } },
  });
  return { wrapper, live };
}

describe("TemplateList", () => {
  it("searches with the typed query", async () => {
    const { wrapper, live } = mountList();

    await wrapper.get("#template-search-input").setValue("Harbor");
    await wrapper.get("#template-search-form").trigger("submit");

    expect(pushed(live)).toContainEqual(["search", { search: { q: "Harbor" } }]);
    expect(wrapper.find("#template-search-clear").exists()).toBe(false);
  });

  it("offers to clear an active search", async () => {
    const { wrapper, live } = mountList({ query: "Harbor" });

    expect(wrapper.get<HTMLInputElement>("#template-search-input").element.value).toBe("Harbor");
    await wrapper.get("#template-search-clear").trigger("click");

    expect(pushed(live)).toContainEqual(["clear_search", {}]);
  });

  it("archives an active template it manages and links to it", async () => {
    const { wrapper, live } = mountList();

    expect(wrapper.get("#template-card-7 a").attributes("href")).toBe("/templates/7");
    await wrapper.get("#archive-template-7").trigger("click");

    expect(pushed(live)).toContainEqual(["archive_template", { id: "7" }]);
  });

  it("shows no management actions on a demo", () => {
    const { wrapper } = mountList({
      sections: [
        section("public", [
          card({ id: 9, visibility: "public", canManage: false, href: "/templates/9" }),
        ]),
      ],
    });

    expect(wrapper.find("#archive-template-9").exists()).toBe(false);
    expect(wrapper.get("#template-card-9 a").attributes("href")).toBe("/templates/9");
  });

  it("restores or deletes an archived template, deleting only after confirmation", async () => {
    const archived = [section("archived", [card()])];
    const { wrapper, live } = mountList({ sections: archived });

    expect(wrapper.find("#template-card-7 a").exists()).toBe(false);
    expect(wrapper.find("#archive-template-7").exists()).toBe(false);
    expect(wrapper.find("#confirm-delete-template-7").exists()).toBe(false);

    await wrapper.get("#unarchive-template-7").trigger("click");
    expect(pushed(live)).toContainEqual(["unarchive_template", { id: "7" }]);

    await wrapper.get("#delete-template-7").trigger("click");
    expect(pushed(live)).toContainEqual(["prepare_delete_template", { id: "7" }]);

    await wrapper.setProps({ pendingDeleteId: 7 });
    expect(wrapper.get("#delete-template-confirmation-7").text()).toContain("cannot be undone");

    await wrapper.get("#cancel-delete-template-7").trigger("click");
    expect(pushed(live)).toContainEqual(["cancel_delete_template", {}]);

    await wrapper.get("#confirm-delete-template-7").trigger("click");
    expect(pushed(live)).toContainEqual(["delete_template", { id: "7" }]);
  });

  it("says when a section is empty and pages a section on its own", () => {
    const { wrapper } = mountList({
      sections: [
        section("private", [card()], {
          totalCount: 12,
          page: 2,
          totalPages: 2,
          prevHref: "/templates?private_page=1",
        }),
        section("public", []),
      ],
    });

    expect(wrapper.get("#public-templates-empty").text()).toBe("No public demos available.");
    expect(wrapper.find("#my-templates-empty").exists()).toBe(false);
    const previous = wrapper.get("#private-templates-prev-page");
    expect(previous.attributes("href")).toBe("/templates?private_page=1");
    expect(previous.attributes("data-phx-link")).toBe("patch");
    expect(wrapper.find("#private-templates-next-page").exists()).toBe(false);
  });
});
