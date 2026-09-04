import { mount } from "@vue/test-utils";
import { computed, ref } from "vue";
import { beforeEach, describe, expect, it, vi } from "vitest";
import WorkspaceSettingsProjects from "../../../../live/workspace/settings/WorkspaceSettingsProjects.vue";
import { createMockLive, setTestLocale } from "../../../setup";

const { mockUseLiveUpload } = vi.hoisted(() => ({ mockUseLiveUpload: vi.fn() }));

vi.mock("live_vue", () => ({
  useLiveUpload: mockUseLiveUpload,
}));

interface FakeUploadEntry {
  ref: string;
  client_name: string;
  client_size: number;
  progress: number;
  valid: boolean;
}

const passthrough = { template: "<div><slot /></div>" };
const uploadConfig = {
  entries: [],
} as never;

const baseProps = {
  imports: [],
  deletedProjects: [],
  quotaRejection: null,
  requestErrorCode: null,
  uploadErrorCode: null,
  uploadConfig,
};

let mockLive = createMockLive();

function configureUpload(initialEntries: FakeUploadEntry[] = []) {
  const entries = ref(initialEntries);
  const showFilePicker = vi.fn();
  const submit = vi.fn();
  const cancel = vi.fn();

  mockUseLiveUpload.mockReturnValue({
    entries: computed(() => entries.value),
    showFilePicker,
    submit,
    cancel,
  });

  return { entries, showFilePicker, submit, cancel };
}

function mountImports(props: Record<string, unknown> = {}) {
  return mount(WorkspaceSettingsProjects, {
    props: { ...baseProps, ...props },
    global: {
      provide: { _live_vue: mockLive },
      stubs: {
        Dialog: {
          props: ["open"],
          template: '<div v-if="open"><slot /></div>',
        },
        DialogContent: passthrough,
        DialogDescription: passthrough,
        DialogFooter: passthrough,
        DialogHeader: passthrough,
        DialogTitle: passthrough,
      },
    },
  });
}

describe("WorkspaceSettingsProjects", () => {
  beforeEach(() => {
    setTestLocale("en");
    vi.clearAllMocks();
    mockLive = createMockLive();
    configureUpload();
  });

  it("uses the LiveView upload contract and submits one valid ZIP", async () => {
    const upload = configureUpload([
      {
        ref: "upload-ref",
        client_name: "complete-project.zip",
        client_size: 1_048_576,
        progress: 0,
        valid: true,
      },
    ]);
    const wrapper = mountImports();

    await wrapper.get("#workspace-snapshot-import-picker").trigger("click");
    expect(upload.showFilePicker).toHaveBeenCalledOnce();
    expect(wrapper.get('[data-testid="workspace-snapshot-import-file"]').text()).toContain(
      "complete-project.zip",
    );
    expect(wrapper.get('[data-testid="workspace-snapshot-import-file"]').text()).toContain("1 MB");

    await wrapper.get("#workspace-snapshot-import-submit").trigger("click");

    expect(upload.submit).toHaveBeenCalledOnce();
    expect(wrapper.get("#workspace-snapshot-import-submit").attributes("disabled")).toBeDefined();
    await wrapper
      .findAll("button")
      .find((button) => button.text().includes("Cancel upload"))!
      .trigger("click");
    expect(upload.cancel).toHaveBeenCalledWith("upload-ref");
    expect(mockUseLiveUpload.mock.calls.at(-1)?.[1]).toEqual({
      changeEvent: "validate_snapshot_zip",
      submitEvent: "import_snapshot",
    });
  });

  it("shows terminal quota and upload grant errors without a retry action", () => {
    const wrapper = mountImports({
      quotaRejection: {
        requiredBytes: "125829120",
        availableBytes: "20971520",
        limitBytes: "104857600",
      },
      requestErrorCode: "rate_limited",
    });

    const modal = wrapper.get('[data-testid="workspace-snapshot-quota-modal"]');
    expect(modal.text()).toContain("Not enough workspace storage");
    expect(modal.text()).toContain("120 MB");
    expect(modal.text()).toContain("20 MB");
    expect(modal.text()).toContain("100 MB");
    expect(modal.text()).not.toContain("Retry");
    expect(modal.text()).not.toContain("partial");
    expect(wrapper.text()).toContain("Try again in about an hour");
  });

  it("renders durable progress, retry attempts, and the completed project destination", () => {
    const wrapper = mountImports({
      imports: [
        {
          id: 41,
          fileName: "recover.zip",
          projectName: "Recovered story",
          status: "retrying",
          phase: "retrying",
          progressBytes: "2097152",
          progressTotalBytes: "4194304",
          attempt: 2,
          maxAttempts: 3,
          insertedAt: "2026-08-20T10:00:00Z",
          completedAt: null,
          failureCode: "temporary_storage_failure",
          projectPath: null,
        },
        {
          id: 42,
          fileName: "finished.zip",
          projectName: "Finished story",
          status: "completed",
          phase: "completed",
          progressBytes: "4194304",
          progressTotalBytes: "4194304",
          attempt: 1,
          maxAttempts: 3,
          insertedAt: "2026-08-20T09:00:00Z",
          completedAt: "2026-08-20T09:01:00Z",
          failureCode: null,
          projectPath: "/workspaces/writers-room/projects/finished-story",
        },
      ],
    });

    const retrying = wrapper.get('[data-testid="workspace-snapshot-import-41"]');
    expect(wrapper.get("#workspace-snapshot-import-picker").attributes("disabled")).toBeDefined();
    expect(wrapper.text()).toContain("Wait for the active project import");
    expect(retrying.text()).toContain("Preparing another attempt");
    expect(retrying.text()).toContain("2 MB / 4 MB");
    expect(retrying.text()).toContain("Attempt 2 of 3");
    expect(retrying.get('[role="progressbar"]').attributes("aria-valuenow")).toBe("50");

    const completed = wrapper.get('[data-testid="workspace-snapshot-import-42"]');
    expect(completed.get("a").attributes("href")).toBe(
      "/workspaces/writers-room/projects/finished-story",
    );
  });

  it("keeps internal failure codes out of user-facing error copy", () => {
    const wrapper = mountImports({
      imports: [
        {
          id: 43,
          fileName: "broken.zip",
          projectName: null,
          status: "failed",
          phase: "failed",
          progressBytes: "0",
          progressTotalBytes: "1024",
          attempt: 3,
          maxAttempts: 3,
          insertedAt: "2026-08-20T09:00:00Z",
          completedAt: "2026-08-20T09:01:00Z",
          failureCode: "internal_worker_crash",
          projectPath: null,
        },
      ],
    });

    const failed = wrapper.get('[data-testid="workspace-snapshot-import-43"]');
    expect(failed.text()).toContain("The project could not be imported.");
    expect(failed.text()).not.toContain("internal_worker_crash");
  });
});
