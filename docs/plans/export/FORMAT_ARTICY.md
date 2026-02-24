# Export Format: articy:draft XML

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md) | [RESEARCH_SYNTHESIS.md](./RESEARCH_SYNTHESIS.md)
>
> **Priority:** Tier 3 — Interoperability target (import AND export)
>
> **Serializer module:** `Storyarn.Exports.Serializers.ArticyXML`
>
> **Import parser:** `Storyarn.Imports.Parsers.ArticyXML`
>
> **Expression emitter:** `Storyarn.Exports.ExpressionTranspiler.Articy`

---

## Why articy:draft

articy:draft is Storyarn's primary competitor. Supporting articy interoperability is strategic:

1. **Import from articy** — Helps articy users migrate to Storyarn
2. **Export to articy XML** — Allows collaboration with teams still on articy
3. **articy:draft 3 Unreal importer entering EOL** — Teams need an alternative pipeline

| Metric              | Value                                                    |
|---------------------|----------------------------------------------------------|
| Pricing             | EUR 6.99/month (articy X), free tier caps at 700 objects |
| Mac support         | Launched April 2025 (articy X)                           |
| Unreal importer v3  | Entering EOL — won't support UE beyond 5.5               |
| Godot plugin        | Beta quality, not production-ready                       |
| Expression language | articy:expresso (`&&`, `                                 ||`, dot notation) |

---

## Export: Storyarn → articy XML

### Mapping

| Storyarn           | articy:draft                  | Notes                           |
|--------------------|-------------------------------|---------------------------------|
| Sheet (character)  | Entity                        | TechnicalName = shortcut        |
| Sheet blocks       | Entity Properties             | Typed properties                |
| Flow               | FlowFragment                  | Container for dialogue          |
| Dialogue node      | DialogueFragment              | Speaker, Text, StageDirections  |
| Dialogue responses | Child DialogueFragments       | Connected via Connections       |
| Condition node     | Condition pin on Connection   | articy:expresso expression      |
| Instruction node   | Instruction pin on Connection | articy script expression        |
| Hub node           | Hub                           | Direct equivalent               |
| Jump node          | Jump                          | Direct equivalent               |
| Subflow node       | FlowFragment reference        | Nested FlowFragments            |
| Scene node         | LocationSettings              | int_ext, time_of_day            |
| Variables          | GlobalVariables > Namespace   | Sheet shortcut = Namespace name |
| Connections        | Connection elements           | Source/Target GUIDs             |

### Expression Transpilation (articy:expresso)

**Conditions:**

| Storyarn Operator       | articy:expresso  | Notes                     |
|-------------------------|------------------|---------------------------|
| `equals`                | `==`             |                           |
| `not_equals`            | `!=`             |                           |
| `greater_than`          | `>`              |                           |
| `less_than`             | `<`              |                           |
| `greater_than_or_equal` | `>=`             |                           |
| `less_than_or_equal`    | `<=`             |                           |
| `is_true`               | `== true`        |                           |
| `is_false`              | `== false`       |                           |
| `is_nil`                | `== null`        |                           |
| `is_empty` (text/multi) | `== ""`          |                           |
| `contains` (text)       | Custom function  | articy:expresso custom    |
| `not_contains` (multi)  | Custom function  |                           |
| `starts_with` (text)    | Custom function  |                           |
| `ends_with` (text)      | Custom function  |                           |
| `before` (date)         | `<`              | Dates compared as strings |
| `after` (date)          | `>`              |                           |
| `all` (AND)             | `&&`             |                           |
| `any` (OR)              | `\|\|`           |                           |

**Variable access:** Dot notation preserved: `mc.jaime.health` (articy uses identical syntax).

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}` with `type: "block"` and `type: "group"` nesting, max 1 level). See [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats).

**Assignments:**

| Storyarn Operator  | articy:expresso                          | Notes       |
|--------------------|------------------------------------------|-------------|
| `set`              | `variable = value`                       |             |
| `add`              | `variable += value`                      |             |
| `subtract`         | `variable -= value`                      |             |
| `set_true`         | `variable = true`                        |             |
| `set_false`        | `variable = false`                       |             |
| `toggle`           | `variable = !variable`                   |             |
| `clear`            | `variable = ""`                          |             |
| `set_if_unset`     | `if (variable == null) variable = value` | Conditional |

> **NO `multiply` operator.** Storyarn does not have a multiply operator. Source of truth: `lib/storyarn/flows/instruction.ex`
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference. articy: `variable = other_variable` (dot notation preserved).

### GUID Strategy

Generate deterministic GUIDs from Storyarn UUIDs so re-exports produce stable references:

```elixir
defp storyarn_uuid_to_articy_guid(uuid) do
  # Deterministic: same UUID always produces same GUID
  # Use UUID v5 (SHA-1 namespace) with Storyarn namespace
  namespace = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"  # URL namespace
  input = "storyarn:#{uuid}"
  UUID.uuid5(namespace, input)
  |> format_as_articy_guid()
end

defp format_as_articy_guid(uuid) do
  # articy uses format: 0x0000000000000000
  uuid
  |> String.replace("-", "")
  |> String.upcase()
  |> then(&"0x#{&1}")
end
```

### XML Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ArticyData>
  <Project Name="My RPG Project" Guid="0x..." TechnicalName="my_rpg_project">
    <ExportSettings>
      <ExportVersion>1.0</ExportVersion>
      <StoryarnExportVersion>1.0.0</StoryarnExportVersion>
    </ExportSettings>

    <GlobalVariables>
      <Namespace Name="mc" Description="Main character variables">
        <Variable Name="jaime.health" Type="int" Value="100" Description="Character health"/>
        <Variable Name="jaime.class" Type="string" Value="warrior"/>
        <Variable Name="jaime.is_alive" Type="bool" Value="true"/>
      </Namespace>
      <Namespace Name="flags" Description="Game flags">
        <Variable Name="met_jaime" Type="bool" Value="false"/>
      </Namespace>
    </GlobalVariables>

    <Hierarchy>
      <!-- Characters as Entities -->
      <Entity Type="Character" Id="0x..." TechnicalName="mc.jaime">
        <DisplayName>Jaime</DisplayName>
        <Properties>
          <Property Name="health" Type="int">100</Property>
          <Property Name="class" Type="string">warrior</Property>
        </Properties>
      </Entity>

      <!-- Flows as FlowFragments -->
      <FlowFragment Type="Dialogue" Id="0x..." TechnicalName="act1.tavern-intro">
        <DisplayName>Tavern Introduction</DisplayName>
        <Nodes>
          <DialogueFragment Id="0x..." Speaker="mc.jaime" TechnicalName="dlg_001">
            <Text>Hello, traveler!</Text>
            <MenuText/>
            <StageDirections/>
          </DialogueFragment>

          <DialogueFragment Id="0x..." Speaker="" TechnicalName="dlg_002">
            <Text>Hello!</Text>
          </DialogueFragment>

          <Hub Id="0x..." TechnicalName="after_greeting">
            <DisplayName>After Greeting</DisplayName>
          </Hub>

          <Instruction Id="0x..." TechnicalName="inst_001">
            <Expression>flags.met_jaime = true</Expression>
          </Instruction>
        </Nodes>
        <Connections>
          <Connection Source="0x..." Target="0x..." Id="0x..."/>
          <Connection Source="0x..." Target="0x..." Id="0x...">
            <Condition>mc.jaime.health > 50</Condition>
          </Connection>
        </Connections>
      </FlowFragment>
    </Hierarchy>

    <Localization DefaultLanguage="en">
      <Language Code="en" Name="English"/>
      <Language Code="es" Name="Spanish"/>
      <Strings>
        <String Id="dlg_001" Language="es">Hola, viajero!</String>
        <String Id="dlg_002" Language="es">Hola!</String>
      </Strings>
    </Localization>
  </Project>
</ArticyData>
```

---

## Import: articy XML → Storyarn

### Parsing Strategy

1. **Parse XML** — Use `SweetXml` or Erlang's `:xmerl` for XML parsing
2. **Map entities** — articy Entities → Storyarn Sheets with blocks
3. **Map flows** — articy FlowFragments → Storyarn Flows with nodes
4. **Map variables** — articy GlobalVariables → Storyarn Sheet blocks (variable type)
5. **Map connections** — articy Connections → Storyarn Flow connections
6. **Handle GUIDs** — articy GUIDs → Storyarn UUIDs (new UUIDs, store original GUID in metadata)

### articy Entity → Storyarn Sheet

| articy                  | Storyarn                              |
|-------------------------|---------------------------------------|
| Entity.DisplayName      | Sheet.name                            |
| Entity.TechnicalName    | Sheet.shortcut                        |
| Entity.Properties       | Sheet.blocks (one block per property) |
| Entity Type="Character" | Sheet with is_character flag          |

### articy FlowFragment → Storyarn Flow

| articy                      | Storyarn                                                 |
|-----------------------------|----------------------------------------------------------|
| FlowFragment.DisplayName    | Flow.name                                                |
| FlowFragment.TechnicalName  | Flow.shortcut                                            |
| DialogueFragment            | Dialogue node                                            |
| DialogueFragment.Speaker    | Dialogue node.speaker_sheet_id (lookup by TechnicalName) |
| Hub                         | Hub node                                                 |
| Jump                        | Jump node                                                |
| Condition (on connection)   | Condition node (inserted between connected nodes)        |
| Instruction (on connection) | Instruction node (inserted between connected nodes)      |
| Connection                  | Flow connection                                          |

### articy Expression → Storyarn Structured Condition

Parse articy:expresso expressions back into Storyarn's structured format:

```
mc.jaime.health > 50 && flags.met_jaime == true
```

→

```json
{
  "logic": "all",
  "rules": [
    {"sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50"},
    {"sheet": "flags", "variable": "met_jaime", "operator": "equals", "value": "true"}
  ]
}
```

This is the reverse of the expression transpiler — a parser for articy:expresso back into Storyarn structured data.

### Import Parser Module

```elixir
defmodule Storyarn.Imports.Parsers.ArticyXML do
  @moduledoc "Parse articy:draft XML into Storyarn data structures"

  def parse(xml_binary) do
    with {:ok, doc} <- parse_xml(xml_binary),
         {:ok, project} <- extract_project(doc),
         {:ok, variables} <- extract_global_variables(doc),
         {:ok, entities} <- extract_entities(doc),
         {:ok, flows} <- extract_flow_fragments(doc),
         {:ok, localization} <- extract_localization(doc) do
      {:ok, %{
        project: project,
        sheets: entities_to_sheets(entities, variables),
        flows: fragments_to_flows(flows),
        localization: localization,
        guid_mapping: build_guid_mapping(entities, flows)
      }}
    end
  end
end
```

---

## Edge Cases

| Feature                            | Export Handling                          | Import Handling                      |
|------------------------------------|------------------------------------------|--------------------------------------|
| articy Hubs                        | Direct equivalent                        | Direct mapping                       |
| articy Jumps                       | Direct equivalent                        | Direct mapping                       |
| articy Conditions on connections   | Transpile to articy:expresso             | Parse back to structured rules       |
| articy Instructions on connections | Transpile to articy script               | Parse back to structured assignments |
| articy Pins (complex)              | Simplified to connections                | Parse pin structure                  |
| Nested FlowFragments               | Map from Storyarn tree structure         | Flatten or preserve hierarchy        |
| articy Templates                   | Not supported (export as generic Entity) | Import as generic Sheet              |
| articy Assets                      | Reference paths only                     | Download/reference strategy TBD      |
| articy GUID format                 | Deterministic generation from UUID       | Store original, generate new UUID    |

---

## Testing Strategy

### Export
- [ ] Valid XML output (schema validation)
- [ ] Deterministic GUIDs (re-export produces identical GUIDs)
- [ ] All node types correctly mapped to articy equivalents
- [ ] articy:expresso expressions are syntactically valid
- [ ] GlobalVariables organized by Namespace (sheet shortcut)
- [ ] Connections reference correct Source/Target GUIDs
- [ ] Localization strings included per language

### Import
- [ ] Parse articy:draft X export XML
- [ ] Parse articy:draft 3 export XML (backward compatibility)
- [ ] Entities → Sheets with correct block types
- [ ] FlowFragments → Flows with correct node types
- [ ] Conditions on connections → Condition nodes
- [ ] Instructions on connections → Instruction nodes
- [ ] GlobalVariables → Sheet blocks (variable type)
- [ ] GUID → UUID mapping stored correctly
- [ ] Malformed XML produces clear error messages
- [ ] Large articy projects parse without OOM
