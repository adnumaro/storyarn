import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import { defineComponent } from "vue";
import ConnectKeyDialog from "../../../../live/account/settings/integrations/ConnectKeyDialog.vue";
import type { IntegrationCardData } from "../../../../live/account/settings/integrations/IntegrationCard.vue";
import { setTestLocale } from "../../../setup";

const DialogStub = defineComponent({
  name: "Dialog",
  props: { open: { type: Boolean, required: true } },
  emits: ["update:open"],
  template: '<div v-if="open"><slot /></div>',
});

const dialogStubs = {
  Dialog: DialogStub,
  DialogContent: { name: "DialogContent", template: "<section><slot /></section>" },
  DialogDescription: { name: "DialogDescription", template: "<div><slot /></div>" },
  DialogFooter: { name: "DialogFooter", template: "<footer><slot /></footer>" },
  DialogHeader: { name: "DialogHeader", template: "<header><slot /></header>" },
  DialogTitle: { name: "DialogTitle", template: "<h2><slot /></h2>" },
  PasswordInput: {
    name: "PasswordInput",
    props: { modelValue: { type: String, default: "" } },
    emits: ["update:modelValue"],
    template: "<input />",
  },
};

function card(): IntegrationCardData {
  return {
    integration_id: null,
    provider: "anthropic",
    name: "Anthropic Claude",
    key_generation_url: "https://example.com/keys",
    docs_url: "https://example.com/docs",
    key_placeholder: "sk-...",
    status: "not_connected",
    account_email: null,
    account_display_name: null,
    key_last_four: null,
    connected_at: null,
    catalog_status: "connection_only",
    models: [],
    workspace_assignments: [],
  };
}

function mountDialog(props: { submitting?: boolean } = {}) {
  return mount(ConnectKeyDialog, {
    props: { open: true, card: card(), ...props },
    global: { stubs: dialogStubs },
  });
}

function cancelButton(wrapper: ReturnType<typeof mountDialog>) {
  return wrapper.find('button[type="button"]');
}

describe("ConnectKeyDialog", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("emits cancel from the cancel button while idle", async () => {
    const wrapper = mountDialog();

    await cancelButton(wrapper).trigger("click");

    expect(wrapper.emitted("cancel")).toHaveLength(1);
  });

  it("emits cancel when the dialog is dismissed while idle", async () => {
    const wrapper = mountDialog();

    wrapper.findComponent(DialogStub).vm.$emit("update:open", false);

    expect(wrapper.emitted("cancel")).toHaveLength(1);
  });

  it("disables the cancel button and ignores clicks while submitting", async () => {
    const wrapper = mountDialog({ submitting: true });

    const button = cancelButton(wrapper);
    expect(button.attributes("disabled")).toBeDefined();

    await button.trigger("click");

    expect(wrapper.emitted("cancel")).toBeUndefined();
  });

  it("blocks dialog dismissal while submitting so an in-flight connect cannot be orphaned", () => {
    const wrapper = mountDialog({ submitting: true });

    wrapper.findComponent(DialogStub).vm.$emit("update:open", false);

    expect(wrapper.emitted("cancel")).toBeUndefined();
  });
});
