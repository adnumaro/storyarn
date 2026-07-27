import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import DashboardContent from "../../shell/DashboardContent.vue";

describe("DashboardContent overview states", () => {
  it("announces a localized loading state without exposing the spinner", () => {
    const wrapper = mount(DashboardContent, {
      props: { loading: true, loadingLabel: "Loading dashboard overview" },
    });

    const status = wrapper.get('[data-testid="dashboard-overview-loading"]');
    expect(status.attributes("role")).toBe("status");
    expect(status.attributes("aria-live")).toBe("polite");
    expect(status.text()).toBe("Loading dashboard overview");
    expect(status.get('[aria-hidden="true"]').attributes("aria-hidden")).toBe("true");
  });

  it("prioritizes failure over an empty state and emits retry", async () => {
    const wrapper = mount(DashboardContent, {
      props: {
        failure: {
          kind: "error",
          message: "The dashboard overview could not be loaded.",
          retryLabel: "Retry",
        },
        isEmpty: true,
        emptyMessage: "Nothing here",
      },
    });

    expect(wrapper.get('[data-testid="dashboard-overview-error"]').attributes("role")).toBe(
      "alert",
    );
    expect(wrapper.text()).not.toContain("Nothing here");

    await wrapper.get('[data-testid="dashboard-overview-retry"]').trigger("click");
    expect(wrapper.emitted("retry")).toEqual([[]]);
  });

  it("keeps loaded content under an accessible stale warning", async () => {
    const wrapper = mount(DashboardContent, {
      props: {
        failure: {
          kind: "stale",
          message: "Showing the last loaded data.",
          retryLabel: "Retry",
        },
      },
      slots: { default: '<p data-testid="loaded-content">Loaded content</p>' },
    });

    const stale = wrapper.get('[data-testid="dashboard-overview-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.attributes("aria-live")).toBe("polite");
    expect(wrapper.get('[data-testid="loaded-content"]').text()).toBe("Loaded content");

    await wrapper.get('[data-testid="dashboard-overview-stale-retry"]').trigger("click");
    expect(wrapper.emitted("retry")).toEqual([[]]);
  });
});
