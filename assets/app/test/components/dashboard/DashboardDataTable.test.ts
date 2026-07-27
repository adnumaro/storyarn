import { mount } from "@vue/test-utils";
import { h } from "vue";
import { describe, expect, it } from "vitest";
import DashboardDataTable from "../../../components/dashboard/DashboardDataTable.vue";
import type {
  DashboardTableColumn,
  DashboardTablePagination,
  DashboardTableRow,
} from "../../../components/dashboard/types";
import { TableCell } from "../../../components/ui/table";

interface TestRow extends DashboardTableRow {
  name: string;
  count: number;
}

const rows: TestRow[] = [
  { id: 10, name: "Opening", count: 4 },
  { id: "credits", name: "Credits", count: 2 },
];

const columns: DashboardTableColumn[] = [
  { key: "name", label: "Name", align: "left" },
  {
    key: "count",
    label: "Nodes",
    align: "right",
    hiddenClass: "hidden sm:table-cell",
  },
];

const pagination: DashboardTablePagination = {
  page: 1,
  totalPages: 2,
  total: rows.length,
  sortBy: "name",
  sortDir: "asc",
};

function mountTable(options: { hasActions?: boolean; pagination?: DashboardTablePagination } = {}) {
  return mount(DashboardDataTable, {
    props: {
      title: "All flows",
      rows,
      columns,
      pagination: options.pagination ?? pagination,
      totalLabel: "2 flows",
      previousLabel: "Previous page",
      nextLabel: "Next page",
      hasActions: options.hasActions,
    },
    slots: {
      row: ({ row }: { row: DashboardTableRow }) => {
        const testRow = row as TestRow;

        return [
          h(TableCell, { "data-testid": `row-name-${testRow.id}` }, () => testRow.name),
          h(
            TableCell,
            {
              "data-testid": `row-count-${testRow.id}`,
              class: "text-right",
            },
            () => String(testRow.count),
          ),
        ];
      },
      actions: ({ row }: { row: DashboardTableRow }) => {
        const testRow = row as TestRow;

        return h(
          "button",
          {
            type: "button",
            "data-testid": `row-action-${testRow.id}`,
          },
          `Edit ${testRow.name}`,
        );
      },
    },
  });
}

describe("DashboardDataTable", () => {
  it("renders the shared shell, columns, and domain-specific row slot", () => {
    const wrapper = mountTable();
    const headers = wrapper.findAll("thead th");

    expect(wrapper.get('[data-testid="dashboard-data-table"]').get("h2").text()).toBe("All flows");
    expect(headers).toHaveLength(2);
    expect(headers.map((header) => header.text())).toEqual(["Name", "Nodes"]);
    expect(headers[1].classes()).toEqual(
      expect.arrayContaining(["text-right", "hidden", "sm:table-cell"]),
    );
    expect(headers[1].get("button").classes()).toContain("ml-auto");
    expect(headers[0].attributes("aria-sort")).toBe("ascending");
    expect(headers[1].attributes("aria-sort")).toBeUndefined();

    expect(wrapper.findAll("tbody tr")).toHaveLength(2);
    expect(wrapper.get('[data-testid="row-name-10"]').text()).toBe("Opening");
    expect(wrapper.get('[data-testid="row-count-10"]').text()).toBe("4");
    expect(wrapper.get('[data-testid="row-name-credits"]').text()).toBe("Credits");
    expect(wrapper.get('[data-testid="row-count-credits"]').text()).toBe("2");
  });

  it("forwards sort and pagination interactions through its public events", async () => {
    const wrapper = mountTable();
    const sortButtons = wrapper.findAll("thead button");

    await sortButtons[1].trigger("click");
    await wrapper.get('[data-testid="dashboard-pagination-next"]').trigger("click");

    expect(wrapper.emitted("sort")).toEqual([["count"]]);
    expect(wrapper.emitted("page")).toEqual([[2]]);
    expect(wrapper.get('[data-testid="dashboard-pagination-total"]').text()).toBe("2 flows");
  });

  it("exposes the active sort direction to assistive technology", async () => {
    const wrapper = mountTable();

    await wrapper.setProps({
      pagination: {
        ...pagination,
        sortBy: "count",
        sortDir: "desc",
      },
    });

    const headers = wrapper.findAll("thead th");
    expect(headers[0].attributes("aria-sort")).toBeUndefined();
    expect(headers[1].attributes("aria-sort")).toBe("descending");
  });

  it("renders action cells only when the dashboard enables them", () => {
    const withActions = mountTable({ hasActions: true });
    const withoutActions = mountTable();

    expect(withActions.findAll('[data-testid="dashboard-data-table-actions-header"]')).toHaveLength(
      1,
    );
    expect(withActions.findAll('[data-testid="dashboard-data-table-actions-cell"]')).toHaveLength(
      rows.length,
    );
    expect(withActions.get('[data-testid="row-action-10"]').text()).toBe("Edit Opening");
    expect(withActions.get('[data-testid="row-action-credits"]').text()).toBe("Edit Credits");

    expect(
      withoutActions.find('[data-testid="dashboard-data-table-actions-header"]').exists(),
    ).toBe(false);
    expect(withoutActions.find('[data-testid="dashboard-data-table-actions-cell"]').exists()).toBe(
      false,
    );
    expect(withoutActions.find('[data-testid^="row-action-"]').exists()).toBe(false);
  });

  it("keeps row DOM identity when stable IDs are reordered", async () => {
    const wrapper = mountTable();
    const originalOpening = wrapper.get('[data-testid="row-name-10"]').element;

    await wrapper.setProps({ rows: [...rows].reverse() });

    expect(wrapper.get('[data-testid="row-name-10"]').element).toBe(originalOpening);
  });

  it("omits pagination when there are no table results", () => {
    const wrapper = mountTable({
      pagination: {
        ...pagination,
        totalPages: 1,
        total: 0,
      },
    });

    expect(wrapper.find('[data-testid="dashboard-pagination"]').exists()).toBe(false);
  });
});
