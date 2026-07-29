import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "../../../setup";
import type { ExportPanelProps } from "../../../../modules/projects/settings/export-import/types";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: ExportPanel } =
  await import("../../../../modules/projects/settings/export-import/components/ExportPanel.vue");

function baseProps(): ExportPanelProps {
  return {
    formatConfig: {
      selected: "ink",
      formats: [
        {
          format: "ink",
          label: "Ink (.ink)",
          extension: "ink",
          localizationMode: "external_catalog",
        },
        {
          format: "unity",
          label: "Unity Dialogue System (JSON)",
          extension: "json",
          localizationMode: "embedded",
        },
      ],
      extension: "zip",
    },
    sectionConfig: {
      selected: ["sheets", "flows", "scenes", "localization"],
      supported: ["sheets", "flows"],
      entityCounts: { sheets: 2, flows: 3, scenes: 4, localization: 8 },
    },
    options: {
      assetMode: "references",
      localizationPolicy: "release",
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

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
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

  it("shows each format localization mode and updates the localization policy", async () => {
    const props = baseProps();
    props.sectionConfig.supported = ["sheets", "flows", "localization"];
    const { live, wrapper } = mountPanel(props);

    expect(wrapper.get('[data-testid="export-format-ink"]').text()).toContain(
      "Localization catalogs",
    );
    expect(wrapper.get('[data-testid="export-format-unity"]').text()).toContain(
      "Embedded localization",
    );

    await wrapper
      .get('[data-testid="export-localization-preview"] [role="radio"]')
      .trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("set_localization_policy", {
      policy: "preview",
    });
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

  it("clears validation progress when LiveView drops the reply", async () => {
    vi.useFakeTimers();
    const { wrapper } = mountPanel();

    await wrapper.get('[data-testid="validate-export"]').trigger("click");
    expect(wrapper.get('[data-testid="validate-export"]').text()).toContain("Validating");

    vi.advanceTimersByTime(15_000);
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-testid="validate-export"]').text()).toContain("Validate");
  });

  it("ignores a stale validation reply after a new validation starts", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPanel();

    await wrapper.get('[data-testid="validate-export"]').trigger("click");
    const staleCallback = vi.mocked(live.pushEvent).mock.calls[0]?.[2];

    vi.advanceTimersByTime(15_000);
    await wrapper.vm.$nextTick();
    await wrapper.get('[data-testid="validate-export"]').trigger("click");

    staleCallback?.({});
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-testid="validate-export"]').text()).toContain("Validating");

    const currentCallback = vi.mocked(live.pushEvent).mock.calls[1]?.[2];
    currentCallback?.({});
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

  it("requires a current validation result while preflight is enabled", () => {
    const { wrapper } = mountPanel();

    expect(wrapper.find('[data-testid="download-export"]').exists()).toBe(false);
    expect(wrapper.text()).toContain("Validate before export");
  });

  it("allows downloading without a result when preflight is explicitly disabled", () => {
    const props = baseProps();
    props.options.validateBeforeExport = false;
    const { wrapper } = mountPanel(props);

    expect(wrapper.get('[data-testid="download-export"]').attributes("href")).toBe("/export/ink");
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
      errors: [{ message: "A blocking issue", rule: "blocking_issue" }],
      warnings: [{ message: "A warning" }],
      info: [{ message: "A note" }],
    } as never;
    const { wrapper } = mountPanel(props);

    const results = wrapper.get("#export-validation-results");
    expect(results.attributes("data-status")).toBe("errors");
    expect(results.attributes("data-stale")).toBe("false");
    expect(results.text()).toContain("A blocking issue");
    expect(results.text()).toContain("A warning");
    expect(results.text()).toContain("A note");
  });

  it("caps long finding lists while preserving the full counts", () => {
    const props = baseProps();
    props.validation = {
      status: "errors",
      errors: Array.from({ length: 55 }, (_, index) => ({
        message: `Blocking issue ${index}`,
        rule: "blocking_issue",
      })),
      warnings: [],
      info: [],
    };
    const { wrapper } = mountPanel(props);

    const results = wrapper.get("#export-validation-results");
    expect(results.text()).toContain("Blocking issue 49");
    expect(results.text()).not.toContain("Blocking issue 50");
    expect(results.text()).toContain("5 more findings are not shown");
    expect(results.text()).toContain("55 errors");
  });

  it("uses singular copy when exactly one finding is hidden", () => {
    const props = baseProps();
    props.validation = {
      status: "errors",
      errors: Array.from({ length: 51 }, (_, index) => ({
        message: `Blocking issue ${index}`,
        rule: "blocking_issue",
      })),
      warnings: [],
      info: [],
    };
    const { wrapper } = mountPanel(props);

    expect(wrapper.get("#export-validation-results").text()).toContain(
      "1 more finding is not shown",
    );
  });

  it("blocks the download when validation has errors", () => {
    const props = baseProps();
    props.validation = {
      status: "errors",
      errors: [{ message: "A blocking issue", rule: "blocking_issue" }],
      warnings: [],
      info: [],
    };
    const { wrapper } = mountPanel(props);

    expect(wrapper.find('[data-testid="download-export"]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      "Resolve the blocking issues below and validate again before downloading.",
    );
  });

  it("keeps stale findings visible but requires validation before downloading", () => {
    const props = baseProps();
    props.validation = {
      status: "passed",
      stale: true,
      errors: [],
      warnings: [{ message: "A previous warning", rule: "previous_warning" }],
      info: [],
    } as never;
    const { wrapper } = mountPanel(props);

    const results = wrapper.get("#export-validation-results");
    expect(results.attributes("data-status")).toBe("passed");
    expect(results.attributes("data-stale")).toBe("true");
    expect(results.text()).toContain("A previous warning");
    expect(results.text()).toContain("Validate before export");
    expect(results.text()).not.toContain("Ready to export");
    expect(wrapper.find('[data-testid="download-export"]').exists()).toBe(false);
  });

  it("does not reuse an Ink error verdict after switching to Unity", async () => {
    const props = baseProps();
    props.validation = {
      status: "errors",
      stale: false,
      errors: [{ message: "Ink cannot compile this reference", rule: "stale_variable_reference" }],
      warnings: [],
      info: [],
    } as never;
    const { wrapper } = mountPanel(props);

    await wrapper.setProps({
      formatConfig: {
        ...props.formatConfig,
        selected: "unity",
        extension: "json",
      },
      validation: {
        status: "errors",
        stale: true,
        errors: [
          { message: "Ink cannot compile this reference", rule: "stale_variable_reference" },
        ],
        warnings: [],
        info: [],
      } as never,
      exportDownloadUrl: "/export/unity",
    });

    expect(wrapper.get("#export-validation-results").attributes("data-stale")).toBe("true");
    expect(wrapper.text()).toContain("Ink cannot compile this reference");
    expect(wrapper.find('[data-testid="download-export"]').exists()).toBe(false);

    await wrapper.setProps({
      validation: {
        status: "warnings",
        stale: false,
        errors: [],
        warnings: [
          {
            message: "Unity cannot preserve this reference safely",
            rule: "stale_variable_reference",
          },
        ],
        info: [],
      } as never,
    });

    expect(wrapper.get("#export-validation-results").attributes("data-stale")).toBe("false");
    expect(wrapper.get('[data-testid="download-export"]').attributes("href")).toBe("/export/unity");
  });

  it("downloads only a successful attachment response", async () => {
    const props = baseProps();
    props.validation = {
      status: "passed",
      stale: false,
      errors: [],
      warnings: [],
      info: [],
    };

    const blob = new Blob(["export"], { type: "application/zip" });
    const blobMock = vi.fn().mockResolvedValue(blob);
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      redirected: false,
      headers: new Headers({
        "content-disposition": 'attachment; filename="story.zip"',
        "content-type": "application/zip",
      }),
      blob: blobMock,
    });
    const createObjectURL = vi.fn().mockReturnValue("blob:storyarn-export");
    const revokeObjectURL = vi.fn();
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
    vi.stubGlobal("fetch", fetchMock);
    vi.stubGlobal("URL", { createObjectURL, revokeObjectURL });
    const { wrapper } = mountPanel(props);

    await wrapper.get('[data-testid="download-export"]').trigger("click");
    await flushPromises();

    expect(fetchMock).toHaveBeenCalledWith("/export/ink");
    expect(blobMock).toHaveBeenCalledOnce();
    expect(createObjectURL).toHaveBeenCalledWith(blob);
    expect(clickSpy).toHaveBeenCalledOnce();
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:storyarn-export");
    expect(wrapper.find("#export-download-error").exists()).toBe(false);
  });

  it("surfaces a failed export in the panel instead of navigating to the 422 response", async () => {
    const props = baseProps();
    props.validation = {
      status: "passed",
      stale: false,
      errors: [],
      warnings: [],
      info: [],
    };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: false,
      status: 422,
      headers: new Headers({ "x-storyarn-export-error": "validation" }),
    });
    vi.stubGlobal("fetch", fetchMock);
    const { wrapper } = mountPanel(props);

    await wrapper.get('[data-testid="download-export"]').trigger("click");
    await flushPromises();

    expect(fetchMock).toHaveBeenCalledWith("/export/ink");
    expect(wrapper.get("#export-download-error").text()).toContain(
      "The export could not be generated",
    );
    expect(wrapper.get('[data-testid="download-export"]').attributes("href")).toBe("/export/ink");
  });

  it("does not mislabel a serializer 422 as a validation failure", async () => {
    const props = baseProps();
    props.validation = {
      status: "passed",
      stale: false,
      errors: [],
      warnings: [],
      info: [],
    };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 422,
        headers: new Headers({ "x-storyarn-export-error": "serialization" }),
      }),
    );
    const { wrapper } = mountPanel(props);

    await wrapper.get('[data-testid="download-export"]').trigger("click");
    await flushPromises();

    expect(wrapper.get("#export-download-error").text()).toContain(
      "The export could not be downloaded",
    );
    expect(wrapper.get("#export-download-error").text()).not.toContain("Validate again");
  });

  it.each([
    {
      name: "a followed login redirect",
      redirected: true,
      disposition: 'attachment; filename="login.html"',
    },
    {
      name: "an HTML response without attachment metadata",
      redirected: false,
      disposition: null,
    },
  ])("rejects $name as a download", async ({ redirected, disposition }) => {
    const props = baseProps();
    props.validation = {
      status: "passed",
      stale: false,
      errors: [],
      warnings: [],
      info: [],
    };

    const headers = new Headers({ "content-type": "text/html; charset=utf-8" });
    if (disposition) headers.set("content-disposition", disposition);

    const blobMock = vi.fn().mockResolvedValue(new Blob(["<html>login</html>"]));
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        redirected,
        headers,
        blob: blobMock,
      }),
    );
    const { wrapper } = mountPanel(props);

    await wrapper.get('[data-testid="download-export"]').trigger("click");
    await flushPromises();

    expect(blobMock).not.toHaveBeenCalled();
    expect(wrapper.get("#export-download-error").text()).toContain(
      "The export could not be downloaded",
    );
  });

  it("keeps the download available when validation only has warnings", () => {
    const props = baseProps();
    props.validation = {
      status: "warnings",
      errors: [],
      warnings: [{ message: "A warning", rule: "warning" }],
      info: [],
    };
    const { wrapper } = mountPanel(props);

    expect(wrapper.get('[data-testid="download-export"]').attributes("href")).toBe("/export/ink");
  });
});
