import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsUsageLimits from "../../../../live/project/settings/ProjectSettingsUsageLimits.vue";

function usageLimits(overrides = {}) {
  return {
    plan: { key: "free", name: "Free" },
    project: {
      items: { used: 6, limit: 700 },
      projectSnapshots: { used: 2, limit: 10 },
      namedVersions: { used: 1, limit: 10 },
    },
    workspace: {
      projects: { used: 1, limit: 3 },
      members: { used: 1, limit: 2 },
      storageBytes: { used: String(1024 * 1024), limit: String(4 * 1024 * 1024) },
    },
    itemBreakdown: { sheets: 1, flows: 1, scenes: 1, flowNodes: 3 },
    storage: {
      projectAccountedBytes: String(640 * 1024),
      projectAssetBytes: String(512 * 1024),
      projectSnapshotBytes: String(96 * 1024),
      projectReservationBytes: String(32 * 1024),
      assetCount: 4,
      workspace: {
        currentAssetsBytes: String(640 * 1024),
        fullSnapshotsBytes: String(256 * 1024),
        linkedSnapshotsBytes: String(64 * 1024),
        activeReservationsBytes: String(64 * 1024),
        totalAccountedBytes: String(1024 * 1024),
        limitBytes: String(4 * 1024 * 1024),
        remainingBytes: String(3 * 1024 * 1024),
        limitKind: "limited" as const,
      },
    },
    ...overrides,
  };
}

describe("ProjectSettingsUsageLimits storage accounting", () => {
  it("renders counted total, remaining bytes, reservations, and storage categories", () => {
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: { usageLimits: usageLimits() },
    });
    const text = wrapper.text();

    expect(text).toContain("Counted storage");
    expect(text).toContain("1 MB");
    expect(text).toContain("25%");
    expect(text).toContain("Remaining capacity");
    expect(text).toContain("3 MB");
    expect(text).toContain("Active reservations");
    expect(text).toContain("Retained project assets");
    expect(text).not.toContain("recoverable trash");
    expect(text).not.toContain("Recoverable asset trash");
    expect(text).toContain("Full snapshots");
    expect(text).toContain("Linked snapshot payloads");
    expect(text).toContain("Provider replication");
    expect(text).not.toContain("monitored separately");
    wrapper.get('[data-testid="workspace-storage-progress"]');
  });

  it("shows exact over-limit usage without capping the readable percentage", () => {
    const fiveMiB = String(5 * 1024 * 1024);
    const fourMiB = String(4 * 1024 * 1024);
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: fiveMiB, limit: fourMiB },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              totalAccountedBytes: fiveMiB,
              limitBytes: fourMiB,
              remainingBytes: "0",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("125%");
    expect(wrapper.text()).toContain("Limit reached");
    wrapper.get('[data-testid="workspace-storage-progress"]');
  });

  it("does not present an unknown allowance as unlimited", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: base.workspace.storageBytes.used, limit: null },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              limitBytes: null,
              remainingBytes: null,
              limitKind: "unknown",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("Unknown");
    expect(wrapper.text()).not.toContain("No limit");
    expect(wrapper.find('[data-testid="workspace-storage-progress"]').exists()).toBe(false);
  });

  it("fails closed for unknown and zero count limits", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          project: {
            ...base.project,
            projectSnapshots: { used: 0, limit: null },
            namedVersions: { used: 0, limit: 0 },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("Unknown");
    expect(wrapper.text()).toContain("Limit reached");
    expect(wrapper.text()).not.toContain("No limit");
    expect(wrapper.find('[aria-label="Project snapshots"]').exists()).toBe(false);
    expect(wrapper.find('[aria-label="Named versions"]').exists()).toBe(false);
  });

  it("presents a zero-byte allowance as zero capacity rather than unlimited", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: "0", limit: "0" },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              totalAccountedBytes: "0",
              limitBytes: "0",
              remainingBytes: "0",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("No storage capacity");
    expect(wrapper.text()).toContain("0 B");
    expect(wrapper.text()).not.toContain("No limit");
    expect(wrapper.find('[data-testid="workspace-storage-progress"]').exists()).toBe(false);
  });

  it("does not render a determinate storage bar for unlimited capacity", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: base.workspace.storageBytes.used, limit: null },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              limitBytes: null,
              remainingBytes: null,
              limitKind: "unlimited",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("No limit");
    expect(wrapper.find('[data-testid="workspace-storage-progress"]').exists()).toBe(false);
  });

  it("does not render a determinate bar when usage exceeds a zero-byte denominator", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: "1", limit: "0" },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              totalAccountedBytes: "1",
              limitBytes: "0",
              remainingBytes: "0",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("Over limit");
    expect(wrapper.find('[data-testid="workspace-storage-progress"]').exists()).toBe(false);
  });

  it("keeps bigint values exact and labels tiny positive usage below 0.01%", () => {
    const base = usageLimits();
    const wrapper = mount(ProjectSettingsUsageLimits, {
      props: {
        usageLimits: {
          ...base,
          workspace: {
            ...base.workspace,
            storageBytes: { used: "1", limit: "9007199254740993" },
          },
          storage: {
            ...base.storage,
            workspace: {
              ...base.storage.workspace,
              currentAssetsBytes: "1",
              fullSnapshotsBytes: "0",
              linkedSnapshotsBytes: "0",
              activeReservationsBytes: "0",
              totalAccountedBytes: "1",
              limitBytes: "9007199254740993",
              remainingBytes: "9007199254740992",
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain("<0.01%");
    expect(wrapper.text()).toContain("8 PB");
    expect(wrapper.find('[aria-label="Storage status: Available"]').exists()).toBe(true);
  });
});
