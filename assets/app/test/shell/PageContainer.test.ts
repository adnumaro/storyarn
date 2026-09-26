import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import { h } from "vue";
import DashboardContent from "../../shell/DashboardContent.vue";
import PageContainer from "../../shell/PageContainer.vue";

const sections = (wrapper: ReturnType<typeof mount>) => wrapper.get("[data-page-sections]");

describe("PageContainer", () => {
  it("fills the height, scrolls and pads every page alike", () => {
    const page = mount(PageContainer, { slots: { default: "<section>One</section>" } });
    expect(page.classes()).toEqual(
      expect.arrayContaining([
        "h-full",
        "w-full",
        "overflow-y-auto",
        "px-4",
        "py-4",
        "lg:px-6",
        "lg:py-6",
      ]),
    );
  });

  it("centres contained content at 1200 px and lets full content use the whole width", () => {
    const contained = mount(PageContainer);
    expect(contained.attributes("data-width")).toBe("contained");
    expect(sections(contained).classes()).toEqual(
      expect.arrayContaining(["mx-auto", "max-w-[1200px]"]),
    );

    const full = mount(PageContainer, { props: { width: "full" } });
    expect(sections(full).classes()).not.toContain("mx-auto");
    expect(sections(full).classes()).not.toContain("max-w-[1200px]");
  });

  it("owns the section layout: a spaced stack, a side column, or a last section that fills", () => {
    expect(sections(mount(PageContainer)).classes()).toEqual(
      expect.arrayContaining(["flex", "flex-col", "gap-6"]),
    );
    const aside = mount(PageContainer, { props: { layout: "aside" } });
    expect(sections(aside).classes()).toEqual(
      expect.arrayContaining(["grid", "gap-6", "lg:grid-cols-[minmax(0,1fr)_360px]"]),
    );
    const fill = mount(PageContainer, { props: { fill: true } });
    expect(sections(fill).classes()).toEqual(
      expect.arrayContaining(["h-full", "[&>:last-child]:flex-1"]),
    );
  });

  it("receives the dashboard's parts as its own sections", () => {
    const page = mount(PageContainer, {
      slots: {
        default: () =>
          h(DashboardContent, { title: "Brainstorming" }, { default: () => h("div", "Sessions") }),
      },
    });
    const children = [...sections(page).element.children].map((child) => child.textContent);
    expect(children).toHaveLength(2);
    expect(children[0]).toContain("Brainstorming");
    expect(children[1]).toBe("Sessions");
  });
});
