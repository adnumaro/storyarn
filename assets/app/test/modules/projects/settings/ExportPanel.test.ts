import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: ExportPanel } =
  await import("../../../../modules/projects/settings/export-import/components/ExportPanel.vue");

function baseProps() {
  return {
    formatConfig: {
      selected: "ink",
      formats: [
        { format: "ink", label: "Ink (.ink)", extension: "ink" },
        { format: "unity", label: "Unity Dialogue System (JSON)", extension: "json" },
      ],
      extension: "zip",
    },
    sectionConfig: {
      selected: ["sheets", "flows", "scenes", "screenplays", "localization"],
      supported: ["sheets", "flows"],
      entityCounts: { sheets: 2, flows: 3, scenes: 4, screenplays: 1, localization: 8 },
    },
    options: {
      assetMode: "references",
      validateBeforeExport: true,
      prettyPrint: true,
    },
    validation: null,
    exportDownloadUrl: "/export/ink",
  };
}

function mountPanel(props = baseProps()) {
  const wrapper = mount(ExportPanel, { props });

  return { live: mockLive, wrapper };
}

describe("ExportPanel", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("summarizes only content supported by the selected format", () => {
    const { wrapper } = mountPanel();

    expect(wrapper.get('[data-testid="export-summary"]').text()).toContain("2 sections");
    expect(wrapper.get('[data-testid="export-summary"]').text()).toContain("5");
    expect(wrapper.get('[data-testid="export-section-scenes"]').text()).toContain("Unavailable");
    expect(wrapper.get('[data-testid="export-section-sheets"]').text()).toContain("2");
  });

  it("uses singular count labels", () => {
    const props = baseProps();
    props.formatConfig.formats = [props.formatConfig.formats[0]];
    props.sectionConfig.selected = ["sheets"];
    const { wrapper } = mountPanel(props);

    expect(wrapper.get("#export-workspace").text()).toContain("1 export target");
    expect(wrapper.get("#export-workspace").text()).not.toContain("1 export targets");
    expect(wrapper.get('[data-testid="export-summary"]').text()).toContain("1 section");
    expect(wrapper.get('[data-testid="export-summary"]').text()).not.toContain("1 sections");
  });

  it("associates legends with the format and asset radio groups", () => {
    const props = baseProps();
    props.formatConfig.selected = "unity";
    props.formatConfig.extension = "json";
    props.sectionConfig.supported = ["sheets", "flows", "localization", "assets"];
    const { wrapper } = mountPanel(props);

    expect(wrapper.get("#export-format-options > legend").text()).toContain("Choose a destination");
    expect(wrapper.get("#export-asset-mode-options > legend").text()).toContain("Assets");
  });

  it("sends format changes through LiveView", async () => {
    const { live, wrapper } = mountPanel();

    await wrapper.get('[data-testid="export-format-unity"] [role="radio"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("set_format", { format: "unity" });
  });

  it("shows progress while the preflight validation is running", async () => {
    const { live, wrapper } = mountPanel();

    await wrapper.get('[data-testid="validate-export"]').trigger("click");

    expect(wrapper.get('[data-testid="validate-export"]').text()).toContain("Validating");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "validate_export",
      {},
      expect.any(Function),
      expect.any(Function),
    );

    const callback = vi.mocked(live.pushEvent).mock.calls[0]?.[2];
    callback?.({});
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-testid="validate-export"]').text()).toContain("Validate");
  });

  it("prevents an empty export", () => {
    const props = baseProps();
    props.sectionConfig.selected = [];
    const { wrapper } = mountPanel(props);

    expect(wrapper.text()).toContain("Select at least one supported content type");
    expect(wrapper.find('[data-testid="download-export"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="validate-export"]').attributes("disabled")).toBeDefined();
  });

  it("only shows asset and formatting controls when the format supports them", () => {
    const { wrapper: inkWrapper } = mountPanel();

    expect(inkWrapper.find('[data-testid="export-assets-references"]').exists()).toBe(false);
    expect(inkWrapper.find("#pretty-print-output").exists()).toBe(false);

    const props = baseProps();
    props.formatConfig.selected = "unity";
    props.formatConfig.extension = "json";
    props.sectionConfig.supported = ["sheets", "flows", "localization", "assets"];
    const { wrapper: unityWrapper } = mountPanel(props);

    expect(unityWrapper.find('[data-testid="export-assets-references"]').exists()).toBe(true);
    expect(unityWrapper.find("#pretty-print-output").exists()).toBe(true);
  });

  it("groups validation findings by severity", () => {
    const props = baseProps();
    props.validation = {
      status: "errors",
      errors: [{ message: "A blocking issue" }],
      warnings: [{ message: "A warning" }],
      info: [{ message: "A note" }],
    } as never;
    const { wrapper } = mountPanel(props);

    const results = wrapper.get("#export-validation-results");
    expect(results.attributes("data-status")).toBe("errors");
    expect(results.text()).toContain("A blocking issue");
    expect(results.text()).toContain("A warning");
    expect(results.text()).toContain("A note");
  });
});
