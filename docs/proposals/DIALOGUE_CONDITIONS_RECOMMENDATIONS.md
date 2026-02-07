# Dialogue Conditions: Recommendations

> **Based on**: [DIALOGUE_CONDITIONS_RESEARCH.md](../research/DIALOGUE_CONDITIONS_RESEARCH.md)
> **Date**: February 2026
> **Status**: Proposal

---

## Executive Summary

Based on the research findings, I recommend **removing conditions from connections/edges** and adopting a node-centric model aligned with industry standards (articy:draft, Chat Mapper, Arcweave).

---

## Current Implementation Analysis

The current `DIALOGUE_NODE_ENHANCEMENT.md` proposes conditions in **three locations**:

| Location          | Field                          | Purpose                           |
|-------------------|--------------------------------|-----------------------------------|
| Connection (edge) | `condition`, `condition_order` | Routing logic                     |
| Dialogue node     | `input_condition`              | Node availability                 |
| Dialogue node     | `output_instruction`           | Side effects on exit              |
| Response          | `condition`, `instruction`     | Response availability and effects |

**Problem**: Conditions on connections duplicate the functionality of Condition nodes and contradict industry patterns.

---

## Recommendations

### 1. Remove Conditions from Connections

**Rationale**:
- No major tool (articy, Arcweave, Chat Mapper) uses edge-based conditions for routing
- Low visibility - logic is "hidden" on thin lines
- Creates visual spaghetti as projects grow
- Duplicates Condition node functionality

**Action**:
- Remove `condition` and `condition_order` fields from `flow_connections` schema
- Remove connection properties panel for conditions
- Remove dashed line rendering for conditional connections

**Migration**: Existing connection conditions can be converted to Condition nodes.

---

### 2. Keep and Improve Condition Node (Switch/Case)

**Rationale**:
- Arcweave's Branch nodes and articy's Condition nodes are the standard pattern
- High visibility - logic is explicit and inspectable
- Multi-output (switch/case) is more flexible than binary (true/false)

**Current implementation is good**:
```elixir
%{
  "expression" => "",
  "cases" => [
    %{"id" => "uuid1", "value" => "warrior", "label" => "Warrior"},
    %{"id" => "uuid2", "value" => "mage", "label" => "Mage"},
    %{"id" => "uuid3", "value" => "", "label" => "Default"}
  ]
}
```

**Keep as-is**: The multi-output Condition node already implemented is aligned with best practices.

---

### 3. Keep Input Condition on Dialogue Nodes

**Rationale**:
- Matches articy's "input pin" pattern
- Determines node **availability**, not routing
- Different semantic meaning from Condition nodes:
  - Condition node = "Which path to take?"
  - Input condition = "Is this content available?"

**Use cases**:
- `has_item("key")` - Only show if player has item
- `reputation > 50` - Only show if reputation is high enough
- `!talked_to_merchant` - Only show if hasn't talked yet

**Keep as-is**: The `input_condition` field with 🔒 indicator is correct.

---

### 4. Keep Output Instruction on Dialogue Nodes

**Rationale**:
- Matches articy's "output pin" pattern
- Side effects that **always** execute when leaving the node
- Clear semantic: "What happens after this dialogue?"

**Keep as-is**: The `output_instruction` field with ⚡ indicator is correct.

---

### 5. Keep Condition/Instruction on Responses

**Rationale**:
- Responses are "mini-choices" within a dialogue node
- Need their own availability conditions
- Need their own side effects when selected

**Semantic difference**:
- `output_instruction` = Always executes on exit
- `response.instruction` = Only executes if that response is chosen

**Keep as-is**: The response `condition` and `instruction` fields are correct.

---

## Proposed Final Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     STORYARN CONDITION MODEL                            │
├──────────────────┬──────────────────────────────────────────────────────┤
│ Need             │ Solution                                             │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Route based on   │ Condition Node (switch/case)                         │
│ game state       │ → Visible, explicit, multiple outputs                │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Hide/show a      │ input_condition on Dialogue node                     │
│ dialogue node    │ → 🔒 indicator                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Execute action   │ output_instruction on Dialogue node                  │
│ after dialogue   │ → ⚡ indicator                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Hide/show a      │ condition on Response                                │
│ response option  │ → [?] indicator                                      │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Execute action   │ instruction on Response                              │
│ when response    │                                                      │
│ is chosen        │                                                      │
└──────────────────┴──────────────────────────────────────────────────────┘
```

---

## Visual Indicators Summary

| Elementn       | Has Condition                | Has Instruction        |
|----------------|------------------------------|------------------------|
| Dialogue node  | 🔒 (input_condition)         | ⚡ (output_instruction) |
| Response       | [?] badge                    | (no indicator needed)  |
| Condition node | Expression visible in header | N/A                    |
| Connection     | None (simple line)           | None                   |

---

## Migration Path

### For Existing Connection Conditions

If there are flows using connection conditions, they should be migrated:

**Before**:
```
[Dialogue A] ──(gold >= 100)──→ [Dialogue B: Buy]
      └─────(else)────────────→ [Dialogue C: Can't afford]
```

**After**:
```
[Dialogue A] ───→ [Condition: gold >= 100] ──"true"──→ [Dialogue B: Buy]
                              └──────────"false"──────→ [Dialogue C: Can't afford]
```

### Migration Script

```elixir
def migrate_connection_conditions do
  # 1. Find all connections with conditions
  # 2. For each source node with conditional outputs:
  #    a. Create a Condition node after the source
  #    b. Move the condition expression to the Condition node
  #    c. Create cases based on the connection conditions
  #    d. Rewire connections through the new Condition node
  # 3. Remove condition fields from connections
end
```

---

## What This Removes

| Feature                            | Status  | Reason                                           |
|------------------------------------|---------|--------------------------------------------------|
| `flow_connections.condition`       | REMOVE  | Not industry standard, low visibility            |
| `flow_connections.condition_order` | REMOVE  | Not needed without conditions                    |
| Connection properties panel        | REMOVE  | No condition fields to edit                      |
| Dashed connection rendering        | REMOVE  | No conditional connections                       |
| Connection click selection         | KEEP    | May be useful for future features (labels, etc.) |

---

## What This Keeps

| Feature                       | Status   | Reason                             |
|-------------------------------|----------|------------------------------------|
| Condition node (switch/case)  | KEEP     | Industry standard, high visibility |
| `dialogue.input_condition`    | KEEP     | Matches articy input pins          |
| `dialogue.output_instruction` | KEEP     | Matches articy output pins         |
| `response.condition`          | KEEP     | Standard for dialogue choices      |
| `response.instruction`        | KEEP     | Standard for choice effects        |
| All visual indicators         | KEEP     | Improves discoverability           |

---

## Benefits of This Approach

1. **Industry alignment**: Matches articy:draft, Arcweave, Chat Mapper patterns
2. **Visual clarity**: All logic is visible on nodes, not hidden on lines
3. **Simpler mental model**: One way to do routing (Condition nodes)
4. **Reduced spaghetti**: Connections are just connections, no hidden complexity
5. **Better for writers**: Non-programmers can see logic at a glance
6. **Easier debugging**: Clear path through Condition nodes

---

## Risks and Mitigations

| Risk                 | Mitigation                                                        |
|----------------------|-------------------------------------------------------------------|
| More nodes on canvas | Condition nodes are compact; benefit of visibility outweighs cost |
| Migration effort     | Provide automated migration script                                |
| Learning curve       | Model is simpler overall; matches tools users may already know    |

---

## Implementation Priority

1. **High**: Remove connection condition UI (prevents new usage)
2. **Medium**: Create migration script for existing data
3. **Low**: Remove database fields (can be done in future cleanup)

---

## References

- [Research Document](../research/DIALOGUE_CONDITIONS_RESEARCH.md)
- [articy:draft Conditions](https://www.articy.com/help/adx/Scripting_Conditions_Instructions.html)
- [Arcweave Branches](https://arcweave.com/docs/1.0/branches)
