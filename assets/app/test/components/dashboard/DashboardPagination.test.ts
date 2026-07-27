import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import DashboardPagination from "../../../components/dashboard/DashboardPagination.vue";

function mountPagination(page: number, totalPages: number, total = 250) {
  return mount(DashboardPagination, {
    props: {
      pagination: { page, totalPages, total },
      totalLabel: `${total} issues`,
      previousLabel: "Previous page",
      nextLabel: "Next page",
    },
  });
}

describe("DashboardPagination", () => {
  it("renders a bounded page window for large result sets", () => {
    const wrapper = mountPagination(50, 100, 2_500);

    const pageButtons = wrapper.findAll('[data-testid^="dashboard-pagination-page-"]');

    expect(pageButtons).toHaveLength(5);
    expect(pageButtons.map((button) => button.text())).toEqual(["1", "49", "50", "51", "100"]);
    expect(wrapper.findAll('[data-testid$="-ellipsis"]')).toHaveLength(2);
    expect(
      wrapper.get('[data-testid="dashboard-pagination-page-50"]').attributes("aria-current"),
    ).toBe("page");
    expect(
      wrapper.get('[data-testid="dashboard-pagination-page-49"]').attributes("aria-label"),
    ).toBe("Page 49");
    expect(wrapper.get('[data-testid="dashboard-pagination-pages"]').attributes("aria-label")).toBe(
      "Pagination",
    );
    expect(wrapper.get('[data-testid="dashboard-pagination-pages"]').classes()).toContain(
      "flex-wrap",
    );
  });

  it("keeps the first and last page windows bounded", () => {
    const firstWindow = mountPagination(1, 100);
    const lastWindow = mountPagination(100, 100);

    expect(
      firstWindow
        .findAll('[data-testid^="dashboard-pagination-page-"]')
        .map((button) => button.text()),
    ).toEqual(["1", "2", "3", "4", "5", "100"]);
    expect(
      lastWindow
        .findAll('[data-testid^="dashboard-pagination-page-"]')
        .map((button) => button.text()),
    ).toEqual(["1", "96", "97", "98", "99", "100"]);
  });

  it("emits valid page changes and ignores the current page", async () => {
    const wrapper = mountPagination(3, 5);

    await wrapper.get('[data-testid="dashboard-pagination-previous"]').trigger("click");
    await wrapper.get('[data-testid="dashboard-pagination-page-3"]').trigger("click");
    await wrapper.get('[data-testid="dashboard-pagination-page-5"]').trigger("click");
    await wrapper.get('[data-testid="dashboard-pagination-next"]').trigger("click");

    expect(wrapper.emitted("page")).toEqual([[2], [5], [4]]);
  });

  it("disables boundary controls and gives icon buttons accessible names", () => {
    const firstPage = mountPagination(1, 3);
    const lastPage = mountPagination(3, 3);

    expect(
      firstPage.get('[data-testid="dashboard-pagination-previous"]').attributes("disabled"),
    ).toBeDefined();
    expect(
      firstPage.get('[data-testid="dashboard-pagination-previous"]').attributes("aria-label"),
    ).toBe("Previous page");
    expect(
      lastPage.get('[data-testid="dashboard-pagination-next"]').attributes("disabled"),
    ).toBeDefined();
    expect(lastPage.get('[data-testid="dashboard-pagination-next"]').attributes("aria-label")).toBe(
      "Next page",
    );
  });

  it("still displays the total when there is only one page", () => {
    const wrapper = mountPagination(1, 1, 7);

    expect(wrapper.get('[data-testid="dashboard-pagination-total"]').text()).toBe("7 issues");
    expect(wrapper.find('[data-testid="dashboard-pagination-pages"]').exists()).toBe(false);
  });
});
