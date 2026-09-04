import { mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { beforeEach, describe, expect, it } from "vitest";
import ProjectSettingsExportImport from "../../../../live/project/settings/export-import/ProjectSettingsExportImport.vue";
import type {
  ExportConfig,
  ImportState,
} from "../../../../modules/projects/settings/export-import/types";

let nextImportPanelInstance = 0;

const ImportPanelProbe = defineComponent({
  name: "ImportPanel",
  props: {
    canImport: { type: Boolean, required: true },
    uploadConfig: { type: Object, default: null },
  },
  setup() {
    return { instanceId: ++nextImportPanelInstance };
  },
  template: `
    <div
      data-testid="import-panel"
      :data-instance-id="instanceId"
      :data-can-import="String(canImport)"
      :data-has-upload-config="String(Boolean(uploadConfig))"
    />
  `,
});

const exportConfig: ExportConfig = {
  formatConfig: {
    selected: "yarn",
    formats: [],
    extension: "yarn",
  },
  sectionConfig: {
    selected: [],
    supported: [],
    entityCounts: {},
  },
  options: {
    assetMode: "references",
    localizationPolicy: "release",
    validateBeforeExport: true,
    prettyPrint: true,
  },
  validation: null,
  downloadUrl: "/projects/example/export",
};

const importState: ImportState = {
  step: "upload",
  stage: null,
  attemptId: null,
  preview: null,
  conflictStrategy: "rename",
  importMode: "additive",
  replaceEligible: false,
  warningCodes: [],
  status: null,
};

const uploadConfig = { entries: [] } as never;

function mountPage(canImport: boolean) {
  return mount(ProjectSettingsExportImport, {
    props: {
      mode: "import" as const,
      exportConfig,
      canEdit: true,
      canImport,
      resumeStorageKey: "opaque-resume-key",
      importState,
      uploadConfig: canImport ? uploadConfig : null,
    },
    global: {
      stubs: {
        ImportPanel: ImportPanelProbe,
        ExportPanel: true,
      },
    },
  });
}

function importPanelState(wrapper: ReturnType<typeof mountPage>) {
  const panel = wrapper.get('[data-testid="import-panel"]');

  return {
    instanceId: panel.attributes("data-instance-id"),
    canImport: panel.attributes("data-can-import"),
    hasUploadConfig: panel.attributes("data-has-upload-config"),
  };
}

describe("ProjectSettingsExportImport ownership changes", () => {
  beforeEach(() => {
    nextImportPanelInstance = 0;
  });

  it("recreates the import panel when ownership grants upload access", async () => {
    const wrapper = mountPage(false);
    expect(importPanelState(wrapper)).toEqual({
      instanceId: "1",
      canImport: "false",
      hasUploadConfig: "false",
    });

    await wrapper.setProps({ canImport: true, uploadConfig });

    expect(importPanelState(wrapper)).toEqual({
      instanceId: "2",
      canImport: "true",
      hasUploadConfig: "true",
    });
  });

  it("recreates the import panel when ownership revokes upload access", async () => {
    const wrapper = mountPage(true);
    expect(importPanelState(wrapper)).toEqual({
      instanceId: "1",
      canImport: "true",
      hasUploadConfig: "true",
    });

    await wrapper.setProps({ canImport: false, uploadConfig: null });

    expect(importPanelState(wrapper)).toEqual({
      instanceId: "2",
      canImport: "false",
      hasUploadConfig: "false",
    });
  });
});
