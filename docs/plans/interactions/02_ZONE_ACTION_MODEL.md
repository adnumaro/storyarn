# Phase 2: Actionable Zones — Domain Model

> **Goal:** Extend the `MapZone` schema with action types so zones can execute instructions, display variable values, or emit named events — in addition to the existing navigation behavior.
>
> **Depends on:** Phase 1 (number constraints — for meaningful interaction)
>
> **Estimated scope:** ~8 files, migration + backend changes

---

## Concept

Currently, map zones only navigate (link to a sheet, flow, or map via `target_type`/`target_id`). This phase adds three new zone behaviors:

| Action Type   | Behavior                          | Use Case                        |
|---------------|-----------------------------------|---------------------------------|
| `navigate`    | Link to sheet/flow/map (existing) | Map drill-down, cross-reference |
| `instruction` | Execute variable assignments      | +/- buttons, toggle switches    |
| `display`     | Show a variable's current value   | Stat displays, counters         |
| `event`       | Emit a named event                | Accept/Cancel buttons, triggers |

A zone's `action_type` determines which behavior applies. The default is `navigate` for backward compatibility.

---

## Data Model

### Schema changes to `MapZone`

**New fields:**

```elixir
field :action_type, :string, default: "navigate"
field :action_data, :map, default: %{}
```

**`action_type`** — One of: `"navigate"`, `"instruction"`, `"display"`, `"event"`

**`action_data`** — Type-specific payload:

```elixir
# navigate (default) — uses existing target_type/target_id, action_data empty
%{}

# instruction — list of assignments (same structure as instruction nodes)
%{
  "assignments" => [
    %{
      "id" => "assgn_1",
      "sheet" => "mc.jaime",
      "variable" => "str",
      "operator" => "add",
      "value" => "1",
      "value_type" => "literal"
    },
    %{
      "id" => "assgn_2",
      "sheet" => "mc.jaime",
      "variable" => "points",
      "operator" => "subtract",
      "value" => "1",
      "value_type" => "literal"
    }
  ],
  "label" => "+"     # optional display label on zone
}

# display — bind to a variable path
%{
  "variable_ref" => "mc.jaime.str",   # full variable reference
  "format" => "number",                # "number" | "text" | "boolean"
  "label" => "STR"                     # optional label above/beside value
}

# event — emit a named event
%{
  "event_name" => "accept",      # the event identifier
  "label" => "Accept"            # display label
}
```

### Validation rules

```elixir
@valid_action_types ~w(navigate instruction display event)

# navigate: target_type/target_id pair (existing validation)
# instruction: action_data must have "assignments" key with list
# display: action_data must have "variable_ref" key with non-empty string
# event: action_data must have "event_name" key with non-empty string
```

### Backward compatibility

- Existing zones have no `action_type` or `action_data` columns → migration adds with defaults
- `action_type` defaults to `"navigate"` → all existing zones behave identically
- `action_data` defaults to `%{}` → no new data for existing zones
- Existing `target_type`/`target_id` fields remain and continue to work for `navigate` zones

---

## Migration

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_add_action_fields_to_map_zones.exs`

```elixir
defmodule Storyarn.Repo.Migrations.AddActionFieldsToMapZones do
  use Ecto.Migration

  def change do
    alter table(:map_zones) do
      add :action_type, :string, default: "navigate", null: false
      add :action_data, :map, default: %{}, null: false
    end

    # Index for filtering zones by action type (useful for interaction node queries)
    create index(:map_zones, [:map_id, :action_type])
  end
end
```

---

## Files to Modify

| File                                                   | Change                             |
|--------------------------------------------------------|------------------------------------|
| `priv/repo/migrations/...`                             | New migration                      |
| `lib/storyarn/maps/map_zone.ex`                        | Add fields, validation             |
| `lib/storyarn/maps/zone_crud.ex`                       | Accept new fields in create/update |
| `lib/storyarn/maps.ex`                                 | New query functions                |
| `lib/storyarn_web/live/map_live/helpers/serializer.ex` | Include action fields in JSON      |
| `test/storyarn/maps/zone_test.exs`                     | New tests                          |

---

## Task 1 — Schema

### 1a — MapZone schema

**`lib/storyarn/maps/map_zone.ex`** — Add fields and validation:

```elixir
@valid_action_types ~w(navigate instruction display event)

schema "map_zones" do
  # ... existing fields ...
  field :action_type, :string, default: "navigate"
  field :action_data, :map, default: %{}
end

def changeset(zone, attrs) do
  zone
  |> cast(attrs, [
    # ... existing fields ...,
    :action_type, :action_data
  ])
  # ... existing validations ...
  |> validate_inclusion(:action_type, @valid_action_types)
  |> validate_action_data()
end

defp validate_action_data(changeset) do
  action_type = get_field(changeset, :action_type)
  action_data = get_field(changeset, :action_data) || %{}

  case action_type do
    "instruction" ->
      if is_list(action_data["assignments"]) do
        changeset
      else
        add_error(changeset, :action_data, "must include assignments list")
      end

    "display" ->
      if is_binary(action_data["variable_ref"]) and action_data["variable_ref"] != "" do
        changeset
      else
        add_error(changeset, :action_data, "must include variable_ref")
      end

    "event" ->
      if is_binary(action_data["event_name"]) and action_data["event_name"] != "" do
        changeset
      else
        add_error(changeset, :action_data, "must include event_name")
      end

    _ ->
      changeset
  end
end
```

### 1b — Clear target fields when switching away from navigate

When `action_type` changes to non-navigate, clear `target_type`/`target_id`:

```elixir
defp maybe_clear_target(changeset) do
  case get_change(changeset, :action_type) do
    nil -> changeset
    "navigate" -> changeset
    _other ->
      changeset
      |> put_change(:target_type, nil)
      |> put_change(:target_id, nil)
  end
end
```

---

## Task 2 — CRUD

### 2a — ZoneCrud

**`lib/storyarn/maps/zone_crud.ex`** — The existing `create_zone/2` and `update_zone/2` already pass attrs through to the changeset. Since the new fields are in the schema and cast list, they'll be accepted automatically. No CRUD changes needed beyond the schema.

### 2b — New query functions

**`lib/storyarn/maps.ex`** (or a new query module) — Add:

```elixir
@doc """
Lists all event zones for a map (used to generate interaction node outputs).
"""
@spec list_event_zones(integer()) :: [MapZone.t()]
defdelegate list_event_zones(map_id), to: ZoneCrud

@doc """
Lists all actionable zones for a map (non-navigate zones).
"""
@spec list_actionable_zones(integer()) :: [MapZone.t()]
defdelegate list_actionable_zones(map_id), to: ZoneCrud
```

In `zone_crud.ex`:

```elixir
def list_event_zones(map_id) do
  from(z in MapZone,
    where: z.map_id == ^map_id and z.action_type == "event",
    order_by: [asc: z.position]
  )
  |> Repo.all()
end

def list_actionable_zones(map_id) do
  from(z in MapZone,
    where: z.map_id == ^map_id and z.action_type != "navigate",
    order_by: [asc: z.position]
  )
  |> Repo.all()
end
```

---

## Task 3 — Serializer

**`lib/storyarn_web/live/map_live/helpers/serializer.ex`** — In `serialize_zone/1`, include the new fields:

```elixir
defp serialize_zone(zone) do
  %{
    # ... existing fields ...
    action_type: zone.action_type,
    action_data: zone.action_data
  }
end
```

---

## Task 4 — Tests

```elixir
describe "actionable zones" do
  test "create instruction zone" do
    {:ok, zone} = Maps.create_zone(map.id, %{
      name: "Increment STR",
      vertices: [%{"x" => 10, "y" => 10}, %{"x" => 20, "y" => 10}, %{"x" => 15, "y" => 20}],
      action_type: "instruction",
      action_data: %{
        "assignments" => [
          %{"id" => "a1", "sheet" => "mc", "variable" => "str", "operator" => "add", "value" => "1", "value_type" => "literal"}
        ]
      }
    })
    assert zone.action_type == "instruction"
    assert length(zone.action_data["assignments"]) == 1
  end

  test "create display zone" do
    {:ok, zone} = Maps.create_zone(map.id, %{
      name: "STR Display",
      vertices: [...],
      action_type: "display",
      action_data: %{"variable_ref" => "mc.jaime.str", "format" => "number", "label" => "STR"}
    })
    assert zone.action_type == "display"
    assert zone.action_data["variable_ref"] == "mc.jaime.str"
  end

  test "create event zone" do
    {:ok, zone} = Maps.create_zone(map.id, %{
      name: "Accept",
      vertices: [...],
      action_type: "event",
      action_data: %{"event_name" => "accept", "label" => "Accept"}
    })
    assert zone.action_type == "event"
  end

  test "instruction zone requires assignments" do
    {:error, changeset} = Maps.create_zone(map.id, %{
      name: "Bad",
      vertices: [...],
      action_type: "instruction",
      action_data: %{}
    })
    assert errors_on(changeset)[:action_data]
  end

  test "existing zones default to navigate" do
    # Existing zone (created before migration) has action_type "navigate"
    zone = Maps.get_zone(map.id, existing_zone.id)
    assert zone.action_type == "navigate"
  end

  test "list_event_zones returns only event zones" do
    # Create navigate + instruction + event zones
    # list_event_zones returns only the event zone
  end

  test "switching to instruction clears target" do
    # Create navigate zone with target
    # Update to instruction
    # Verify target_type and target_id are nil
  end
end
```

---

## Verification

```bash
mix ecto.migrate
mix test test/storyarn/maps/
just quality
```

Manual:
1. Open map editor → create a zone → verify it defaults to "navigate" (existing behavior unchanged)
2. Via console/API: create an instruction zone → verify it persists correctly
3. Verify existing maps still work identically
