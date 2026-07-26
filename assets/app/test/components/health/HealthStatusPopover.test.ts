import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import HealthStatusPopover from "../../../components/health/HealthStatusPopover.vue";
import type { HealthStatus, HealthStatusItem, HealthStatusReason } from "@shared/types/health";
import { setTestLocale } from "../../setup";

const passthrough = { template: "<div><slot /></div>" };

function health(reasons: HealthStatusReason[], label = "Node 1"): HealthStatus {
  return {
    errorItems: [],
    warningItems: [{ label, reasons }],
    infoItems: [],
  };
}

function mountPopover(status: HealthStatus) {
  return mount(HealthStatusPopover, {
    props: {
      health: status,
      translationPrefix: "flows.health",
      testIdPrefix: "flow",
      canNavigate: () => false,
      itemKey: (_item: HealthStatusItem, index: number) => `item-${index}`,
      itemDataAttributes: () => ({}),
    },
    global: {
      stubs: {
        Popover: passthrough,
        PopoverAnchor: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
        ToolbarTooltip: passthrough,
      },
    },
  });
}

describe("HealthStatusPopover finding labels", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  // vue-i18n 11 renders an array passed as a named param as pretty-printed
  // JSON (`["true","false"]` becomes `[\n  "true",\n  "false"\n]`). Every list
  // detail must therefore be joined into a string before it reaches `t()`.
  it("renders list details as a joined string, never as JSON", () => {
    const wrapper = mountPopover(
      health([{ code: "missing_output_connections", details: { pins: ["true", "false"] } }]),
    );

    const text = wrapper.text();

    expect(text).toContain("true, false");
    expect(text).not.toContain("[");
    expect(text).not.toContain('"');
  });

  it("interpolates the pins of a stale-pin finding", () => {
    const wrapper = mountPopover(
      health([{ code: "invalid_output_pins", details: { node_type: "dialogue", pins: ["r2"] } }]),
    );

    expect(wrapper.text()).toContain("Connection on a removed output pin: r2");
  });

  it("interpolates a scalar count detail", () => {
    const wrapper = mountPopover(health([{ code: "multiple_entries", details: { count: 3 } }]));

    expect(wrapper.text()).toContain("3");
  });

  it("interpolates the hub name of an orphan hub", () => {
    const wrapper = mountPopover(
      health([{ code: "orphan_hub", details: { node_type: "hub", hub_id: "lonely" } }]),
    );

    expect(wrapper.text()).toContain("lonely");
  });

  // `hub_id` comes from `node.data["hub_id"]`, which can be absent. vue-i18n
  // renders a `null` named param as an empty placeholder; this pins that, so
  // nobody "fixes" it into a `String(value)` coercion that prints "null".
  it("never renders a null detail as the word null", () => {
    const wrapper = mountPopover(
      health([{ code: "orphan_hub", details: { node_type: "hub", hub_id: null } }]),
    );

    expect(wrapper.text()).not.toContain("null");
    expect(wrapper.text()).toContain("is never reached by connection or jump");
  });

  it("leaves a finding without details untouched", () => {
    const wrapper = mountPopover(health([{ code: "isolated_node" }]));

    expect(wrapper.text()).toContain("Node has no connections");
  });
});
