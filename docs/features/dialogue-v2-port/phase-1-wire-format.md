# Phase 1 — Wire-format fix

**Goal:** the response-editing surface in `FlowScreenplayEditor.vue` actually works. Today it crashes the LiveView process on every interaction because the push-event payloads don't match what the backend handlers expect. This phase fixes the wire and adds Vitest coverage so it stays fixed.

**Outcome (user-testable):** select a dialogue node → open screenplay panel → Responses tab → Add response (appears) → type text in textarea + blur (persists across reload) → set condition (persists) → set instruction assignments (persists) → Remove response (gone). No `FunctionClauseError` in server logs.

**Estimate:** 2-3h.

**Decisions invoked:** D1 (all writes through `persist_node_update`), D3 (`condition` stringified at wire).

---

## Wire contract (from REFACTOR.md §4)

Backend handlers in `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` pattern-match on these EXACT payloads. Anything else is a `FunctionClauseError`. Quoted strings are wire-level keys.

| Event                                 | Required keys                                        | Notes                                                     |
| ------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------- |
| `add_response`                        | `"node-id"`                                          | hyphen, not underscore                                    |
| `remove_response`                     | `"response-id"`, `"node-id"`                         | both required                                             |
| `update_response_text`                | `"response-id"`, `"node-id"`, `"value"`              | `"value"` not `"text"`                                    |
| `update_response_condition`           | `"response-id"`, `"node-id"`, `"value"` (string)     | string, not object — V2 must `JSON.stringify` before push |
| `update_response_instruction_builder` | `"response-id"`, `"node-id"`, `"assignments"` (list) | NOT `update_response_assignments`                         |

Currently broken in V2 (`assets/app/modules/flows/components/FlowScreenplayEditor.vue`):

```js
// What V2 sends today (BROKEN):
live.pushEvent("add_response", {}); // missing node-id
live.pushEvent("remove_response", { response_id }); // wrong key + missing node-id
live.pushEvent("update_response_text", { response_id, text }); // wrong key + missing node-id + wrong value key
live.pushEvent("update_response_condition", { response_id, condition }); // wrong key + missing node-id + condition is object
live.pushEvent("update_response_assignments", { response_id, assignments }); // event name doesn't exist
```

What V2 must send:

```js
live.pushEvent("add_response", { "node-id": nodeId });
live.pushEvent("remove_response", { "response-id": id, "node-id": nodeId });
live.pushEvent("update_response_text", {
  "response-id": id,
  "node-id": nodeId,
  value: text,
});
live.pushEvent("update_response_condition", {
  "response-id": id,
  "node-id": nodeId,
  value: JSON.stringify(condition),
});
live.pushEvent("update_response_instruction_builder", {
  "response-id": id,
  "node-id": nodeId,
  assignments,
});
```

**Important:** the LiveView wire keeps quoted-hyphen keys exactly as the handler matches. JS object literals can carry hyphenated keys via string keys (`"node-id": value`). This is unusual but required by V1's pattern.

---

## Files to edit

1. **`assets/app/modules/flows/components/FlowScreenplayEditor.vue`** — fix the 5 push-event payloads above. The handler functions are around lines 151-172 (per the audit).
2. **`assets/app/modules/flows/components/FlowScreenplayEditor.vue`** — when receiving `condition` from the server, parse it back from string: `condition: response.condition ? JSON.parse(response.condition) : null` for the `ConditionBuilder` prop. Render-side parse, push-side stringify.
3. **`assets/app/test/modules/flows/components/FlowScreenplayEditor.test.ts`** (new) — 5 test cases minimum (one per event payload shape) plus 1 smoke test (mount + walk add → edit → delete).

No backend changes in Phase 1. The V1 wire is the contract; V2 conforms.

---

## Test plan (Vitest)

```ts
// assets/app/test/modules/flows/components/FlowScreenplayEditor.test.ts
import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import FlowScreenplayEditor from "@modules/flows/components/FlowScreenplayEditor.vue";
import { createMockLive } from "../../../setup";

const NODE = { id: 42, data: { responses: [{ id: "r1", text: "hi", condition: null }] } };

function mountIt(props = {}, live = createMockLive()) {
  return {
    wrapper: mount(FlowScreenplayEditor, {
      props: { open: true, node: NODE, canEdit: true, ...props },
      global: { mocks: { $live: live } },
    }),
    live,
  };
}

describe("FlowScreenplayEditor — response wire payloads", () => {
  it("add_response sends only node-id", async () => {
    const { wrapper, live } = mountIt();
    await wrapper.find('[data-test="add-response"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("add_response", { "node-id": 42 });
  });

  it("remove_response sends response-id + node-id", async () => {
    const { wrapper, live } = mountIt();
    await wrapper.find('[data-test="remove-response-r1"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("remove_response", {
      "response-id": "r1",
      "node-id": 42,
    });
  });

  it("update_response_text uses value key + node-id", async () => {
    const { wrapper, live } = mountIt();
    const input = wrapper.find('[data-test="response-text-r1"]');
    await input.setValue("new text");
    await input.trigger("blur");
    expect(live.pushEvent).toHaveBeenCalledWith("update_response_text", {
      "response-id": "r1",
      "node-id": 42,
      value: "new text",
    });
  });

  it("update_response_condition stringifies the condition object", async () => {
    const { wrapper, live } = mountIt();
    const builder = wrapper.findComponent({ name: "ConditionBuilder" });
    builder.vm.$emit("update:condition", { logic: "all", rules: [] });
    expect(live.pushEvent).toHaveBeenCalledWith("update_response_condition", {
      "response-id": "r1",
      "node-id": 42,
      value: '{"logic":"all","rules":[]}',
    });
  });

  it("update_response_instruction_builder sends assignments", async () => {
    const { wrapper, live } = mountIt();
    const builder = wrapper.findComponent({ name: "InstructionBuilder" });
    builder.vm.$emit("update:assignments", [{ variable: "a", op: "set", value: "1" }]);
    expect(live.pushEvent).toHaveBeenCalledWith("update_response_instruction_builder", {
      "response-id": "r1",
      "node-id": 42,
      assignments: [{ variable: "a", op: "set", value: "1" }],
    });
  });

  it("smoke: add → edit → delete walks through without errors", async () => {
    // mount, push add, set props with returned response, push update_text, push remove
    // (uses the live mock to capture event sequence)
  });
});
```

The actual selectors (`data-test="..."`) need to be added to `FlowScreenplayEditor.vue` as part of this phase — V1 didn't have testids; V2 is fresh.

---

## Verification checklist

Before marking Phase 1 complete:

- [ ] Vitest: `npm test -- assets/app/test/modules/flows/components/FlowScreenplayEditor.test.ts` — 6+ tests pass.
- [ ] Backend: `mix test test/storyarn_web/live/flow_live/nodes/dialogue_node_test.exs` — green.
- [ ] Browser: open dialogue, exercise add → edit text → set condition (use the builder) → set instruction (use the builder) → remove. Watch dev server logs — zero `FunctionClauseError`.
- [ ] Reload the page and confirm responses persist (text, condition, instruction).
- [ ] Multi-tab: open two tabs, edit a response in one, expect the other to show stale state until selected (collab is Phase 6).
- [ ] No regression in canvas: response sockets render, badges (condition/instruction/error) appear correctly.

---

## Out of scope for Phase 1

- Adding the audio picker (Phase 2).
- Camelcase prop interface (Phase 3).
- Visual polish (Phase 4).
- i18n key sweep (Phase 5).
- Collab broadcast (Phase 6).
- Backend changes — none. The V1 wire IS the contract.

---

## Done means

- Commit lands on `feat/live-vue-sheets` with message `fix(flows/dialogue): align response wire-format with V1 backend handlers`.
- `EXECUTION.md` Phase 1 row marked `✅` (manual edit).
- Memory `project_dialogue_v2_port_status.md` updated to reflect Phase 1 shipped.
