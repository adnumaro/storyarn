import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ConfirmDialog from "../../components/ConfirmDialog.vue";

const dialogStubs = {
  Dialog: {
    props: ["open"],
    template: '<div v-if="open"><slot /></div>',
  },
  DialogContent: {
    template: '<section data-testid="dialog-content"><slot /></section>',
  },
  DialogDescription: { template: "<p><slot /></p>" },
  DialogFooter: { template: '<footer data-testid="dialog-actions"><slot /></footer>' },
  DialogHeader: { template: "<header><slot /></header>" },
  DialogTitle: { template: "<h2><slot /></h2>" },
};

function mountDialog(props: { pending?: boolean; pendingText?: string } = {}) {
  return mount(ConfirmDialog, {
    props: {
      open: true,
      title: "Transfer project ownership?",
      confirmText: "Transfer ownership",
      cancelText: "Cancel",
      ...props,
    },
    global: { stubs: dialogStubs },
  });
}

describe("ConfirmDialog", () => {
  it("marks the dialog busy and announces pending work exactly once", () => {
    const wrapper = mountDialog({
      pending: true,
      pendingText: "Transferring project ownership…",
    });

    expect(wrapper.get('[data-testid="dialog-actions"]').attributes("aria-busy")).toBe("true");

    const announcements = wrapper.findAll('[role="status"]');
    expect(announcements).toHaveLength(1);
    const announcement = wrapper.get('[role="status"]');
    expect(announcement.classes()).toContain("sr-only");
    expect(announcement.attributes("aria-live")).toBe("polite");
    expect(announcement.attributes("aria-atomic")).toBe("true");
    expect(announcement.text()).toBe("Transferring project ownership…");

    expect(wrapper.findAll("button").map((button) => button.text())).toEqual([
      "Cancel",
      "Transfer ownership",
    ]);
    expect(
      wrapper.findAll("button").every((button) => button.attributes("disabled") !== undefined),
    ).toBe(true);
    expect(wrapper.get("svg").attributes("aria-hidden")).toBe("true");
  });

  it("does not expose a live status while idle", () => {
    const wrapper = mountDialog();

    expect(wrapper.get('[data-testid="dialog-actions"]').attributes("aria-busy")).toBe("false");
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it("falls back to the confirmation label when no pending label is provided", () => {
    const wrapper = mountDialog({ pending: true });

    expect(wrapper.get('[role="status"]').text()).toBe("Transfer ownership");
  });
});
