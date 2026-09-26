import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vitest";
import SaveIndicator from "../../components/SaveIndicator.vue";
import LogicToggle from "../../components/builders/condition/LogicToggle.vue";
import FlowLogicToggle from "../../modules/flows/editor/components/expression/builders/condition/LogicToggle.vue";
import { setTestLocale } from "../setup";

afterEach(() => setTestLocale("en"));

// The label, the two choices and the words after them, as the user reads them.
function wordingOf(wrapper: VueWrapper): string[] {
  const spans = wrapper.findAll(":scope > span");
  return [spans[0].text(), ...wrapper.findAll("button").map((b) => b.text()), spans[1].text()];
}

describe("shared components in the viewer's language", () => {
  it("shows the save status in Spanish", () => {
    setTestLocale("es");

    expect(mount(SaveIndicator, { props: { status: "saving" } }).text()).toBe("Guardando...");
    expect(mount(SaveIndicator, { props: { status: "saved" } }).text()).toBe("Guardado");
  });

  it.each([
    ["shared", LogicToggle],
    ["Flows", FlowLogicToggle],
  ])("words the %s condition match so it agrees in Spanish", (_copy, component) => {
    setTestLocale("es");
    const parts = (props: Record<string, unknown>) => wordingOf(mount(component, { props }));

    expect(parts({ logic: "all", kind: "rules" })).toEqual([
      "Cumplir",
      "todas",
      "alguna",
      "las reglas",
    ]);
    expect(parts({ logic: "any", kind: "rules" })).toEqual([
      "Cumplir",
      "todas",
      "alguna",
      "de las reglas",
    ]);
    expect(parts({ logic: "any", kind: "blocks" })).toEqual([
      "Cumplir",
      "todos",
      "alguno",
      "de los bloques",
    ]);
  });

  it("keeps the English wording", () => {
    const wrapper = mount(LogicToggle, { props: { logic: "all", kind: "group" } });

    expect(wordingOf(wrapper)).toEqual(["Match", "all", "any", "of the blocks in the group"]);
  });
});
