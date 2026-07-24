import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowAnalysisDismissForm from "../../../../../../modules/flows/editor/components/panels/FlowAnalysisDismissForm.vue";

const REASON_CODES = ["intentional_design", "other"];

function mountForm(props: Record<string, unknown> = {}) {
  return mount(FlowAnalysisDismissForm, {
    props: { reasonCodes: REASON_CODES, maxNoteLength: 2000, error: null, ...props },
  });
}

describe("FlowAnalysisDismissForm", () => {
  it("keeps confirm disabled until a reason is chosen", async () => {
    const wrapper = mountForm();
    const confirm = wrapper.get('[data-testid="analysis-dismiss-confirm"]');

    expect(confirm.attributes("disabled")).toBeDefined();

    const reason = wrapper.findAll("label").find((l) => l.text().includes("Intentional design"));
    await reason!.get("[role=radio]").trigger("click");

    expect(confirm.attributes("disabled")).toBeUndefined();
  });

  it("requires a note for the other reason", async () => {
    const wrapper = mountForm();
    const confirm = wrapper.get('[data-testid="analysis-dismiss-confirm"]');

    const other = wrapper.findAll("label").find((l) => l.text().includes("Other reason"));
    await other!.get("[role=radio]").trigger("click");
    expect(confirm.attributes("disabled")).toBeDefined();

    await wrapper.get("textarea").setValue("unforeseen case");
    expect(confirm.attributes("disabled")).toBeUndefined();

    await confirm.trigger("click");
    expect(wrapper.emitted("submit")).toEqual([["other", "unforeseen case"]]);
  });

  it("renders the action error as an alert", () => {
    const wrapper = mountForm({ error: "The action could not reach the server. Try again." });

    expect(wrapper.get("[role=alert]").text()).toContain("could not reach the server");
  });
});
