# Script for populating the database with an RPG demo project.
#
# Run with: mix run priv/repo/seeds.exs
#
# Inspired by Disco Elysium — a detective RPG set in a crumbling city.
# Demonstrates sheets (characters, items, locations, global vars),
# flows (dialogue trees, quests, chapters), conditions, and instructions.

alias Storyarn.{Accounts, Workspaces, Projects, Sheets, Flows}
alias Storyarn.Accounts.Scope

IO.puts("🎲 Seeding Revachol Blues — RPG demo project...")

# =============================================================================
# 1. User, Workspace, Project
# =============================================================================

{:ok, user} = Accounts.register_user(%{email: "detective@revachol.rce", display_name: "Harry"})
scope = Scope.for_user(user)

# register_user auto-creates a default workspace; fetch it
[%{workspace: workspace}] = Workspaces.list_workspaces(scope)

{:ok, project} =
  Projects.create_project(scope, %{
    name: "Revachol Blues",
    description: "A detective RPG in the ruined city of Revachol.",
    workspace_id: workspace.id
  })

IO.puts("  ✓ User, workspace & project created")

# =============================================================================
# Helper: create a block and return it
# =============================================================================

defmodule Seed do
  def block!(sheet, type, label, opts \\ []) do
    value = Keyword.get(opts, :value)
    is_constant = Keyword.get(opts, :is_constant, false)
    position = Keyword.get(opts, :position, 0)
    options = Keyword.get(opts, :options)
    placeholder = Keyword.get(opts, :placeholder)
    mode = Keyword.get(opts, :mode)

    config =
      %{"label" => label}
      |> then(fn c -> if placeholder, do: Map.put(c, "placeholder", placeholder), else: c end)
      |> then(fn c -> if options, do: Map.put(c, "options", options), else: c end)
      |> then(fn c -> if mode, do: Map.put(c, "mode", mode), else: c end)

    val = if value != nil, do: %{"content" => value}, else: %{"content" => nil}

    {:ok, block} =
      Sheets.create_block(sheet, %{
        type: type,
        config: config,
        value: val,
        is_constant: is_constant,
        position: position
      })

    block
  end

  def select_opts(pairs) do
    Enum.map(pairs, fn {k, v} -> %{"key" => k, "value" => v} end)
  end

  def rid, do: "r_#{:erlang.unique_integer([:positive])}"
  def cid, do: "case_#{:erlang.unique_integer([:positive])}"

  def condition_json(logic, rules) do
    Jason.encode!(%{
      "logic" => logic,
      "rules" =>
        Enum.map(rules, fn r ->
          %{
            "id" => "rule_#{:erlang.unique_integer([:positive])}",
            "sheet" => r.sheet,
            "variable" => r.variable,
            "operator" => r.operator,
            "value" => r.value
          }
        end)
    })
  end

  def instruction_json(assignments) do
    Jason.encode!(
      Enum.map(assignments, fn a ->
        %{
          "id" => "assign_#{:erlang.unique_integer([:positive])}",
          "sheet" => a.sheet,
          "variable" => a.variable,
          "operator" => a.operator,
          "value" => a[:value],
          "value_type" => a[:value_type] || "literal",
          "value_sheet" => a[:value_sheet]
        }
      end)
    )
  end
end

# =============================================================================
# 2. SHEETS — Global Variables
# =============================================================================

{:ok, global_sheet} =
  Sheets.create_sheet(project, %{
    name: "Global Variables",
    shortcut: "global",
    description: "World state flags and counters",
    color: "#f59e0b"
  })

Seed.block!(global_sheet, "number", "Day", value: 1, position: 0, placeholder: "1")

Seed.block!(global_sheet, "select", "Time of Day",
  value: "morning",
  position: 1,
  options:
    Seed.select_opts([
      {"morning", "Morning"},
      {"afternoon", "Afternoon"},
      {"evening", "Evening"},
      {"night", "Night"}
    ])
)

Seed.block!(global_sheet, "number", "Money", value: 0, position: 2, placeholder: "0")

Seed.block!(global_sheet, "boolean", "Case Solved",
  value: false,
  position: 3,
  mode: "two_state"
)

Seed.block!(global_sheet, "select", "Political Alignment",
  value: nil,
  position: 4,
  options:
    Seed.select_opts([
      {"communist", "Communist"},
      {"moralist", "Moralist"},
      {"ultraliberal", "Ultraliberal"},
      {"fascist", "Fascist"}
    ])
)

IO.puts("  ✓ Global variables sheet")

# =============================================================================
# 3. SHEETS — Characters
# =============================================================================

{:ok, char_folder} =
  Sheets.create_sheet(project, %{
    name: "Characters",
    shortcut: "char",
    color: "#3b82f6"
  })

# — Detective (protagonist) —
{:ok, detective_sheet} =
  Sheets.create_sheet(project, %{
    name: "Detective",
    shortcut: "char.detective",
    description: "Harrier Du Bois — amnesiac cop, disaster human.",
    color: "#ef4444",
    parent_id: char_folder.id
  })

Seed.block!(detective_sheet, "text", "Name",
  value: "Harrier Du Bois",
  is_constant: true,
  position: 0
)

Seed.block!(detective_sheet, "divider", "", position: 1)
Seed.block!(detective_sheet, "number", "Health", value: 5, position: 2, placeholder: "0-10")
Seed.block!(detective_sheet, "number", "Morale", value: 5, position: 3, placeholder: "0-10")

Seed.block!(detective_sheet, "divider", "", position: 4)

Seed.block!(detective_sheet, "number", "Intellect", value: 3, position: 5, placeholder: "1-6")
Seed.block!(detective_sheet, "number", "Psyche", value: 4, position: 6, placeholder: "1-6")
Seed.block!(detective_sheet, "number", "Physique", value: 2, position: 7, placeholder: "1-6")
Seed.block!(detective_sheet, "number", "Motorics", value: 3, position: 8, placeholder: "1-6")

Seed.block!(detective_sheet, "divider", "", position: 9)

Seed.block!(detective_sheet, "boolean", "Is Alive",
  value: true,
  position: 10,
  mode: "two_state"
)

Seed.block!(detective_sheet, "select", "Archetype",
  value: nil,
  position: 11,
  options:
    Seed.select_opts([
      {"thinker", "Thinker"},
      {"sensitive", "Sensitive"},
      {"physical", "Physical"},
      {"balanced", "Balanced"}
    ])
)

IO.puts("  ✓ Detective sheet")

# — Kim Kitsuragi —
{:ok, kim_sheet} =
  Sheets.create_sheet(project, %{
    name: "Kim Kitsuragi",
    shortcut: "char.kim",
    description: "Lieutenant from Precinct 57. Your partner.",
    color: "#f97316",
    parent_id: char_folder.id
  })

Seed.block!(kim_sheet, "text", "Name", value: "Kim Kitsuragi", is_constant: true, position: 0)
Seed.block!(kim_sheet, "divider", "", position: 1)
Seed.block!(kim_sheet, "number", "Trust", value: 50, position: 2, placeholder: "0-100")
Seed.block!(kim_sheet, "number", "Respect", value: 40, position: 3, placeholder: "0-100")
Seed.block!(kim_sheet, "boolean", "Is Partner", value: true, position: 4, mode: "two_state")

Seed.block!(kim_sheet, "select", "Mood",
  value: "neutral",
  position: 5,
  options:
    Seed.select_opts([
      {"neutral", "Neutral"},
      {"pleased", "Pleased"},
      {"annoyed", "Annoyed"},
      {"impressed", "Impressed"}
    ])
)

IO.puts("  ✓ Kim Kitsuragi sheet")

# — Evrart Claire —
{:ok, evrart_sheet} =
  Sheets.create_sheet(project, %{
    name: "Evrart Claire",
    shortcut: "char.evrart",
    description: "Union boss of the Débardeurs. Smiling menace.",
    color: "#22c55e",
    parent_id: char_folder.id
  })

Seed.block!(evrart_sheet, "text", "Name", value: "Evrart Claire", is_constant: true, position: 0)
Seed.block!(evrart_sheet, "divider", "", position: 1)
Seed.block!(evrart_sheet, "boolean", "Favor Owed", value: false, position: 2, mode: "two_state")
Seed.block!(evrart_sheet, "number", "Trust", value: 10, position: 3, placeholder: "0-100")

Seed.block!(evrart_sheet, "boolean", "Quest Completed",
  value: false,
  position: 4,
  mode: "two_state"
)

IO.puts("  ✓ Evrart Claire sheet")

# — Klaasje —
{:ok, klaasje_sheet} =
  Sheets.create_sheet(project, %{
    name: "Klaasje",
    shortcut: "char.klaasje",
    description: "Woman found in the room above the hanged man.",
    color: "#a855f7",
    parent_id: char_folder.id
  })

Seed.block!(klaasje_sheet, "text", "Name",
  value: "Klaasje Amandou",
  is_constant: true,
  position: 0
)

Seed.block!(klaasje_sheet, "divider", "", position: 1)
Seed.block!(klaasje_sheet, "number", "Trust", value: 20, position: 2, placeholder: "0-100")

Seed.block!(klaasje_sheet, "boolean", "Told Truth",
  value: false,
  position: 3,
  mode: "two_state"
)

Seed.block!(klaasje_sheet, "boolean", "Has Escaped",
  value: false,
  position: 4,
  mode: "two_state"
)

IO.puts("  ✓ Klaasje sheet")

# =============================================================================
# 4. SHEETS — Items
# =============================================================================

{:ok, items_folder} =
  Sheets.create_sheet(project, %{
    name: "Items",
    shortcut: "items",
    color: "#eab308"
  })

# — Inventory —
{:ok, inv_sheet} =
  Sheets.create_sheet(project, %{
    name: "Inventory",
    shortcut: "items.inv",
    description: "Key items carried by the detective.",
    color: "#eab308",
    parent_id: items_folder.id
  })

Seed.block!(inv_sheet, "boolean", "Badge", value: false, position: 0, mode: "two_state")
Seed.block!(inv_sheet, "boolean", "Gun", value: false, position: 1, mode: "two_state")
Seed.block!(inv_sheet, "boolean", "Tape Recorder", value: false, position: 2, mode: "two_state")
Seed.block!(inv_sheet, "boolean", "Ledger", value: false, position: 3, mode: "two_state")
Seed.block!(inv_sheet, "boolean", "Speed", value: false, position: 4, mode: "two_state")

IO.puts("  ✓ Inventory sheet")

# — Evidence —
{:ok, ev_sheet} =
  Sheets.create_sheet(project, %{
    name: "Evidence",
    shortcut: "items.evidence",
    description: "Evidence collected during the investigation.",
    color: "#dc2626",
    parent_id: items_folder.id
  })

Seed.block!(ev_sheet, "boolean", "Bullet Casing", value: false, position: 0, mode: "two_state")
Seed.block!(ev_sheet, "boolean", "Boot Print", value: false, position: 1, mode: "two_state")
Seed.block!(ev_sheet, "boolean", "Victim ID", value: false, position: 2, mode: "two_state")

Seed.block!(ev_sheet, "boolean", "Witness Testimony",
  value: false,
  position: 3,
  mode: "two_state"
)

Seed.block!(ev_sheet, "boolean", "Armor Fragment",
  value: false,
  position: 4,
  mode: "two_state"
)

IO.puts("  ✓ Evidence sheet")

# =============================================================================
# 5. SHEETS — Locations
# =============================================================================

{:ok, loc_folder} =
  Sheets.create_sheet(project, %{
    name: "Locations",
    shortcut: "loc",
    color: "#06b6d4"
  })

# — Whirling-in-Rags Hotel —
{:ok, hotel_sheet} =
  Sheets.create_sheet(project, %{
    name: "Whirling-in-Rags",
    shortcut: "loc.hotel",
    description: "A hostel on the coast. Your temporary home.",
    color: "#06b6d4",
    parent_id: loc_folder.id
  })

Seed.block!(hotel_sheet, "boolean", "Is Unlocked", value: true, position: 0, mode: "two_state")
Seed.block!(hotel_sheet, "boolean", "Has Visited", value: false, position: 1, mode: "two_state")

Seed.block!(hotel_sheet, "select", "State",
  value: "pristine",
  position: 2,
  options:
    Seed.select_opts([
      {"pristine", "Pristine"},
      {"damaged", "Damaged"},
      {"destroyed", "Destroyed"}
    ])
)

# — Docks —
{:ok, docks_sheet} =
  Sheets.create_sheet(project, %{
    name: "Martinaise Docks",
    shortcut: "loc.docks",
    description: "The harbour district, controlled by the union.",
    color: "#64748b",
    parent_id: loc_folder.id
  })

Seed.block!(docks_sheet, "boolean", "Is Unlocked", value: false, position: 0, mode: "two_state")
Seed.block!(docks_sheet, "boolean", "Has Visited", value: false, position: 1, mode: "two_state")

Seed.block!(docks_sheet, "boolean", "Strike Active",
  value: true,
  position: 2,
  mode: "two_state"
)

# — Fishing Village —
{:ok, fishing_sheet} =
  Sheets.create_sheet(project, %{
    name: "Fishing Village",
    shortcut: "loc.fishing",
    description: "A small settlement beyond the ice.",
    color: "#0ea5e9",
    parent_id: loc_folder.id
  })

Seed.block!(fishing_sheet, "boolean", "Is Unlocked",
  value: false,
  position: 0,
  mode: "two_state"
)

Seed.block!(fishing_sheet, "boolean", "Has Visited",
  value: false,
  position: 1,
  mode: "two_state"
)

IO.puts("  ✓ Location sheets")

# =============================================================================
# 6. FLOWS — Chapter: Prologue (main flow)
# =============================================================================

# -- Flow folder: Chapters --
{:ok, ch_folder} =
  Flows.create_flow(project, %{
    name: "Chapters",
    shortcut: "ch"
  })

# -- Prologue --
{:ok, prologue} =
  Flows.create_flow(project, %{
    name: "Prologue — Waking Up",
    shortcut: "ch.prologue",
    description: "The detective wakes up in a trashed hotel room with no memory.",
    parent_id: ch_folder.id
  })

Flows.set_main_flow(prologue)

# Grab auto-created entry & exit
[entry_node] = Flows.list_nodes(prologue.id) |> Enum.filter(&(&1.type == "entry"))
[exit_node] = Flows.list_nodes(prologue.id) |> Enum.filter(&(&1.type == "exit"))

# Move entry & exit to better positions
Flows.update_node_position(entry_node, %{position_x: 50.0, position_y: 300.0})
Flows.update_node_position(exit_node, %{position_x: 1800.0, position_y: 300.0})

# — Scene: Hotel room —
{:ok, s_hotel_room} =
  Flows.create_node(prologue, %{
    type: "scene",
    position_x: 150.0,
    position_y: 300.0,
    data: %{
      "location_sheet_id" => hotel_sheet.id,
      "int_ext" => "int",
      "sub_location" => "Room",
      "time_of_day" => "morning",
      "description" => "A wrecked hotel room. Bottles and clothes everywhere.",
      "technical_id" => "PRO_SCENE_HOTEL"
    }
  })

# — Dialogue: Internal monologue —
resp_wake_1 = Seed.rid()
resp_wake_2 = Seed.rid()

{:ok, d_wake} =
  Flows.create_node(prologue, %{
    type: "dialogue",
    position_x: 250.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => detective_sheet.id,
      "text" =>
        "<p>The ceiling is spinning. Everything hurts. You smell like industrial solvent and regret.</p>",
      "stage_directions" => "The detective opens his eyes in a wrecked hotel room.",
      "menu_text" => "",
      "technical_id" => "PRO_WAKE_01",
      "responses" => [
        %{
          "id" => resp_wake_1,
          "text" => "Try to remember who you are.",
          "condition" => "",
          "instruction" => ""
        },
        %{
          "id" => resp_wake_2,
          "text" => "Go back to sleep.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# — Instruction: Mark hotel as visited —
{:ok, i_visit} =
  Flows.create_node(prologue, %{
    type: "instruction",
    position_x: 550.0,
    position_y: 200.0,
    data: %{
      "instructions" =>
        Jason.decode!(
          Seed.instruction_json([
            %{sheet: "loc.hotel", variable: "has_visited", operator: "set_true"}
          ])
        )
    }
  })

# — Condition: Check health > 3 —
healthy_case = Seed.cid()
wounded_case = Seed.cid()

{:ok, c_health} =
  Flows.create_node(prologue, %{
    type: "condition",
    position_x: 800.0,
    position_y: 200.0,
    data: %{
      "expression" =>
        Jason.decode!(
          Seed.condition_json("all", [
            %{
              sheet: "char.detective",
              variable: "health",
              operator: "greater_than",
              value: "3"
            }
          ])
        ),
      "cases" => [
        %{"id" => healthy_case, "value" => "true", "label" => "Healthy enough"},
        %{"id" => wounded_case, "value" => "false", "label" => "Barely alive"}
      ]
    }
  })

# — Dialogue: Memory fragment (healthy branch) —
resp_remember = Seed.rid()

{:ok, d_memory} =
  Flows.create_node(prologue, %{
    type: "dialogue",
    position_x: 1100.0,
    position_y: 100.0,
    data: %{
      "speaker_sheet_id" => detective_sheet.id,
      "text" =>
        "<p>Fragments surface. A badge. A name — maybe yours. A city that hates you back.</p>",
      "stage_directions" => "A flash of memory.",
      "technical_id" => "PRO_MEMORY_01",
      "responses" => [
        %{
          "id" => resp_remember,
          "text" => "Pick up the badge from the floor.",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "items.inv", variable: "badge", operator: "set_true"}
            ])
        }
      ]
    }
  })

# — Dialogue: Barely alive branch —
resp_crawl = Seed.rid()

{:ok, d_crawl} =
  Flows.create_node(prologue, %{
    type: "dialogue",
    position_x: 1100.0,
    position_y: 400.0,
    data: %{
      "speaker_sheet_id" => detective_sheet.id,
      "text" =>
        "<p>Your body screams in protest. Every joint a declaration of war against consciousness.</p>",
      "stage_directions" => "The detective drags himself upright.",
      "technical_id" => "PRO_CRAWL_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.detective", variable: "health", operator: "subtract", value: "1"}
        ]),
      "responses" => [
        %{
          "id" => resp_crawl,
          "text" => "Stumble toward the door.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# — Hub: Lobby convergence —
{:ok, h_lobby} =
  Flows.create_node(prologue, %{
    type: "hub",
    position_x: 1350.0,
    position_y: 300.0,
    data: %{"color" => "purple"}
  })

# — Dialogue: Go back to sleep (dead end) —
{:ok, d_sleep} =
  Flows.create_node(prologue, %{
    type: "dialogue",
    position_x: 550.0,
    position_y: 500.0,
    data: %{
      "speaker_sheet_id" => detective_sheet.id,
      "text" => "<p>The darkness takes you back. This time it feels permanent.</p>",
      "stage_directions" => "GAME OVER.",
      "technical_id" => "PRO_SLEEP_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.detective", variable: "is_alive", operator: "set_false"}
        ]),
      "responses" => []
    }
  })

# Connections — Prologue
Flows.create_connection(prologue, entry_node, s_hotel_room, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(prologue, s_hotel_room, d_wake, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(prologue, d_wake, i_visit, %{
  source_pin: resp_wake_1,
  target_pin: "input"
})

Flows.create_connection(prologue, d_wake, d_sleep, %{
  source_pin: resp_wake_2,
  target_pin: "input"
})

Flows.create_connection(prologue, d_sleep, exit_node, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(prologue, i_visit, c_health, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(prologue, c_health, d_memory, %{
  source_pin: healthy_case,
  target_pin: "input"
})

Flows.create_connection(prologue, c_health, d_crawl, %{
  source_pin: wounded_case,
  target_pin: "input"
})

Flows.create_connection(prologue, d_memory, h_lobby, %{
  source_pin: resp_remember,
  target_pin: "input"
})

Flows.create_connection(prologue, d_crawl, h_lobby, %{
  source_pin: resp_crawl,
  target_pin: "input"
})

Flows.create_connection(prologue, h_lobby, exit_node, %{
  source_pin: "output",
  target_pin: "input"
})

IO.puts("  ✓ Prologue flow (main) with #{length(Flows.list_nodes(prologue.id))} nodes")

# =============================================================================
# 7. FLOWS — Chapter 1: The Crime Scene
# =============================================================================

{:ok, ch1} =
  Flows.create_flow(project, %{
    name: "Chapter 1 — The Crime Scene",
    shortcut: "ch.crime-scene",
    description: "Investigate the hanged man behind the hostel.",
    parent_id: ch_folder.id
  })

[ch1_entry] = Flows.list_nodes(ch1.id) |> Enum.filter(&(&1.type == "entry"))
[ch1_exit] = Flows.list_nodes(ch1.id) |> Enum.filter(&(&1.type == "exit"))

Flows.update_node_position(ch1_entry, %{position_x: 50.0, position_y: 300.0})
Flows.update_node_position(ch1_exit, %{position_x: 2000.0, position_y: 300.0})

# — Scene: Crime scene exterior —
{:ok, s_crime_scene} =
  Flows.create_node(ch1, %{
    type: "scene",
    position_x: 150.0,
    position_y: 300.0,
    data: %{
      "location_sheet_id" => hotel_sheet.id,
      "int_ext" => "ext",
      "sub_location" => "Backyard",
      "time_of_day" => "morning",
      "description" => "Behind the hostel. A body hangs from an old oak tree.",
      "technical_id" => "CH1_SCENE_CRIME"
    }
  })

# — Dialogue: Kim introduction —
resp_kim_hello = Seed.rid()
resp_kim_skip = Seed.rid()

{:ok, d_kim_intro} =
  Flows.create_node(ch1, %{
    type: "dialogue",
    position_x: 250.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>A man in an orange bomber jacket waits by the body. He looks like he has been waiting a while.</p><p>\"Lieutenant Kim Kitsuragi, Precinct 57. You must be the RCM officer assigned to this case.\"</p>",
      "stage_directions" => "Kim is standing by the tree, notebook in hand.",
      "technical_id" => "CH1_KIM_INTRO",
      "responses" => [
        %{
          "id" => resp_kim_hello,
          "text" => "\"I... yes. That's me. Probably.\"",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "char.kim", variable: "trust", operator: "add", value: "5"}
            ])
        },
        %{
          "id" => resp_kim_skip,
          "text" => "\"Show me the body.\"",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# — Dialogue: Examine body —
resp_examine_close = Seed.rid()
resp_examine_ask = Seed.rid()

{:ok, d_body} =
  Flows.create_node(ch1, %{
    type: "dialogue",
    position_x: 550.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => nil,
      "text" =>
        "<p>The victim hangs from an old oak tree. Male, middle-aged, wearing corporate security armor. He has been dead for days.</p>",
      "stage_directions" => "The body swings gently in the coastal wind.",
      "technical_id" => "CH1_BODY_01",
      "responses" => [
        %{
          "id" => resp_examine_close,
          "text" => "Examine the body up close.",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "items.evidence", variable: "victim_id", operator: "set_true"}
            ])
        },
        %{
          "id" => resp_examine_ask,
          "text" => "Ask Kim what he knows.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# — Hub: Investigation hub —
{:ok, h_investigate} =
  Flows.create_node(ch1, %{
    type: "hub",
    position_x: 850.0,
    position_y: 300.0,
    data: %{"color" => "blue"}
  })

# — Condition: Has enough evidence? —
enough_case = Seed.cid()
not_enough_case = Seed.cid()

{:ok, c_evidence} =
  Flows.create_node(ch1, %{
    type: "condition",
    position_x: 1100.0,
    position_y: 300.0,
    data: %{
      "expression" =>
        Jason.decode!(
          Seed.condition_json("all", [
            %{
              sheet: "items.evidence",
              variable: "victim_id",
              operator: "is_true",
              value: nil
            },
            %{
              sheet: "items.evidence",
              variable: "boot_print",
              operator: "is_true",
              value: nil
            }
          ])
        ),
      "cases" => [
        %{"id" => enough_case, "value" => "true", "label" => "Enough evidence"},
        %{"id" => not_enough_case, "value" => "false", "label" => "Need more clues"}
      ]
    }
  })

# — Dialogue: Enough evidence —
{:ok, d_enough} =
  Flows.create_node(ch1, %{
    type: "dialogue",
    position_x: 1400.0,
    position_y: 200.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"Good work, detective. We have enough to proceed to the next phase of the investigation.\"</p>",
      "stage_directions" => "Kim nods approvingly.",
      "technical_id" => "CH1_ENOUGH_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.kim", variable: "respect", operator: "add", value: "10"}
        ]),
      "responses" => []
    }
  })

# — Dialogue: Need more clues —
resp_back = Seed.rid()

{:ok, d_need_more} =
  Flows.create_node(ch1, %{
    type: "dialogue",
    position_x: 1400.0,
    position_y: 450.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" => "<p>\"We still need more evidence. Let's keep looking around.\"</p>",
      "technical_id" => "CH1_NEED_MORE",
      "responses" => [
        %{
          "id" => resp_back,
          "text" => "Continue investigating.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# — Instruction: find boot print —
{:ok, i_boot} =
  Flows.create_node(ch1, %{
    type: "instruction",
    position_x: 550.0,
    position_y: 100.0,
    data: %{
      "instructions" =>
        Jason.decode!(
          Seed.instruction_json([
            %{sheet: "items.evidence", variable: "boot_print", operator: "set_true"}
          ])
        )
    }
  })

# Connections — Chapter 1
Flows.create_connection(ch1, ch1_entry, s_crime_scene, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(ch1, s_crime_scene, d_kim_intro, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(ch1, d_kim_intro, d_body, %{
  source_pin: resp_kim_hello,
  target_pin: "input"
})

Flows.create_connection(ch1, d_kim_intro, d_body, %{
  source_pin: resp_kim_skip,
  target_pin: "input"
})

Flows.create_connection(ch1, d_body, i_boot, %{
  source_pin: resp_examine_close,
  target_pin: "input"
})

Flows.create_connection(ch1, d_body, h_investigate, %{
  source_pin: resp_examine_ask,
  target_pin: "input"
})

Flows.create_connection(ch1, i_boot, h_investigate, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(ch1, h_investigate, c_evidence, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(ch1, c_evidence, d_enough, %{
  source_pin: enough_case,
  target_pin: "input"
})

Flows.create_connection(ch1, c_evidence, d_need_more, %{
  source_pin: not_enough_case,
  target_pin: "input"
})

Flows.create_connection(ch1, d_enough, ch1_exit, %{
  source_pin: "output",
  target_pin: "input"
})

# Jump: loop back to investigation hub
h_investigate = Flows.get_node!(ch1.id, h_investigate.id)

{:ok, j_back_investigate} =
  Flows.create_node(ch1, %{
    type: "jump",
    position_x: 1650.0,
    position_y: 450.0,
    data: %{"target_hub_id" => h_investigate.data["hub_id"]}
  })

Flows.create_connection(ch1, d_need_more, j_back_investigate, %{
  source_pin: resp_back,
  target_pin: "input"
})

IO.puts("  ✓ Chapter 1 flow with #{length(Flows.list_nodes(ch1.id))} nodes")

# =============================================================================
# 8. FLOWS — Side Quests
# =============================================================================

{:ok, quest_folder} =
  Flows.create_flow(project, %{
    name: "Side Quests",
    shortcut: "quest"
  })

# -- Badge Quest --
{:ok, quest_badge} =
  Flows.create_flow(project, %{
    name: "The Missing Badge",
    shortcut: "quest.badge",
    description: "Find your RCM badge — or get a new one.",
    parent_id: quest_folder.id
  })

[qb_entry] = Flows.list_nodes(quest_badge.id) |> Enum.filter(&(&1.type == "entry"))
[qb_exit] = Flows.list_nodes(quest_badge.id) |> Enum.filter(&(&1.type == "exit"))

Flows.update_node_position(qb_entry, %{position_x: 50.0, position_y: 250.0})
Flows.update_node_position(qb_exit, %{position_x: 1200.0, position_y: 250.0})

# Condition: already have badge?
has_badge_case = Seed.cid()
no_badge_case = Seed.cid()

{:ok, c_badge} =
  Flows.create_node(quest_badge, %{
    type: "condition",
    position_x: 250.0,
    position_y: 250.0,
    data: %{
      "expression" =>
        Jason.decode!(
          Seed.condition_json("all", [
            %{sheet: "items.inv", variable: "badge", operator: "is_true", value: nil}
          ])
        ),
      "cases" => [
        %{"id" => has_badge_case, "value" => "true", "label" => "Has badge"},
        %{"id" => no_badge_case, "value" => "false", "label" => "No badge"}
      ]
    }
  })

# Already have it
{:ok, d_have_badge} =
  Flows.create_node(quest_badge, %{
    type: "dialogue",
    position_x: 550.0,
    position_y: 100.0,
    data: %{
      "speaker_sheet_id" => detective_sheet.id,
      "text" =>
        "<p>You pat your pocket. The badge is there. Slightly bent, but real. You are a cop.</p>",
      "technical_id" => "QB_HAVE_BADGE",
      "responses" => []
    }
  })

# Don't have it — ask Kim
resp_ask_kim_badge = Seed.rid()

{:ok, d_no_badge} =
  Flows.create_node(quest_badge, %{
    type: "dialogue",
    position_x: 550.0,
    position_y: 350.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"You don't have your badge?\" Kim's expression doesn't change. \"We'll need to requisition a replacement.\"</p>",
      "technical_id" => "QB_NO_BADGE",
      "responses" => [
        %{
          "id" => resp_ask_kim_badge,
          "text" => "\"Can I borrow yours?\"",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# Kim's response
{:ok, d_kim_badge} =
  Flows.create_node(quest_badge, %{
    type: "dialogue",
    position_x: 850.0,
    position_y: 350.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"No.\" A pause. \"But I'll note it in my report. We'll sort it out after the case.\"</p>",
      "technical_id" => "QB_KIM_BADGE",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.kim", variable: "trust", operator: "subtract", value: "5"}
        ]),
      "responses" => []
    }
  })

Flows.create_connection(quest_badge, qb_entry, c_badge, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(quest_badge, c_badge, d_have_badge, %{
  source_pin: has_badge_case,
  target_pin: "input"
})

Flows.create_connection(quest_badge, c_badge, d_no_badge, %{
  source_pin: no_badge_case,
  target_pin: "input"
})

Flows.create_connection(quest_badge, d_have_badge, qb_exit, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(quest_badge, d_no_badge, d_kim_badge, %{
  source_pin: resp_ask_kim_badge,
  target_pin: "input"
})

Flows.create_connection(quest_badge, d_kim_badge, qb_exit, %{
  source_pin: "output",
  target_pin: "input"
})

IO.puts("  ✓ Badge quest flow")

# -- Evrart's Favor --
{:ok, quest_evrart} =
  Flows.create_flow(project, %{
    name: "Evrart's Favor",
    shortcut: "quest.evrart",
    description: "The union boss wants something from you.",
    parent_id: quest_folder.id
  })

[qe_entry] = Flows.list_nodes(quest_evrart.id) |> Enum.filter(&(&1.type == "entry"))
[qe_exit] = Flows.list_nodes(quest_evrart.id) |> Enum.filter(&(&1.type == "exit"))

Flows.update_node_position(qe_entry, %{position_x: 50.0, position_y: 300.0})
Flows.update_node_position(qe_exit, %{position_x: 1500.0, position_y: 300.0})

# Evrart's pitch
resp_accept = Seed.rid()
resp_refuse = Seed.rid()

{:ok, d_evrart_pitch} =
  Flows.create_node(quest_evrart, %{
    type: "dialogue",
    position_x: 300.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => evrart_sheet.id,
      "text" =>
        "<p>Evrart leans back in his chair, which groans under the effort. \"I need you to open a door for me, officer. Just a little door. Nothing illegal.\"</p>",
      "stage_directions" => "His smile does not reach his eyes.",
      "technical_id" => "QE_PITCH_01",
      "input_condition" =>
        Seed.condition_json("all", [
          %{
            sheet: "char.evrart",
            variable: "quest_completed",
            operator: "is_false",
            value: nil
          }
        ]),
      "responses" => [
        %{
          "id" => resp_accept,
          "text" => "\"Fine. What door?\"",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "char.evrart", variable: "favor_owed", operator: "set_true"}
            ])
        },
        %{
          "id" => resp_refuse,
          "text" => "\"I'm not your errand boy.\"",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "char.evrart", variable: "trust", operator: "subtract", value: "10"}
            ])
        }
      ]
    }
  })

# Accept path
{:ok, d_evrart_thanks} =
  Flows.create_node(quest_evrart, %{
    type: "dialogue",
    position_x: 700.0,
    position_y: 200.0,
    data: %{
      "speaker_sheet_id" => evrart_sheet.id,
      "text" =>
        "<p>\"Wonderful! I knew you were a reasonable man. Here—\" He slides a key across the desk. \"Apartment 10B, behind the Whirling. Don't worry about what's inside.\"</p>",
      "technical_id" => "QE_THANKS_01",
      "responses" => []
    }
  })

# Instruction: mark quest done
{:ok, i_evrart_done} =
  Flows.create_node(quest_evrart, %{
    type: "instruction",
    position_x: 1000.0,
    position_y: 200.0,
    data: %{
      "instructions" =>
        Jason.decode!(
          Seed.instruction_json([
            %{sheet: "char.evrart", variable: "quest_completed", operator: "set_true"},
            %{sheet: "char.evrart", variable: "trust", operator: "add", value: "15"}
          ])
        )
    }
  })

# Refuse path
{:ok, d_evrart_shrug} =
  Flows.create_node(quest_evrart, %{
    type: "dialogue",
    position_x: 700.0,
    position_y: 450.0,
    data: %{
      "speaker_sheet_id" => evrart_sheet.id,
      "text" =>
        "<p>\"That's a shame.\" The smile stays frozen. \"But you'll change your mind. Everyone does, eventually.\"</p>",
      "technical_id" => "QE_SHRUG_01",
      "responses" => []
    }
  })

Flows.create_connection(quest_evrart, qe_entry, d_evrart_pitch, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(quest_evrart, d_evrart_pitch, d_evrart_thanks, %{
  source_pin: resp_accept,
  target_pin: "input"
})

Flows.create_connection(quest_evrart, d_evrart_pitch, d_evrart_shrug, %{
  source_pin: resp_refuse,
  target_pin: "input"
})

Flows.create_connection(quest_evrart, d_evrart_thanks, i_evrart_done, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(quest_evrart, i_evrart_done, qe_exit, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(quest_evrart, d_evrart_shrug, qe_exit, %{
  source_pin: "output",
  target_pin: "input"
})

IO.puts("  ✓ Evrart's Favor quest flow")

# =============================================================================
# 9. FLOWS — Dialogues
# =============================================================================

{:ok, dlg_folder} =
  Flows.create_flow(project, %{
    name: "Dialogues",
    shortcut: "dlg"
  })

# -- Talk to Kim (detailed dialogue tree) --
{:ok, dlg_kim} =
  Flows.create_flow(project, %{
    name: "Talk to Kim",
    shortcut: "dlg.kim",
    description: "Conversation with Kim at the crime scene.",
    parent_id: dlg_folder.id
  })

[dk_entry] = Flows.list_nodes(dlg_kim.id) |> Enum.filter(&(&1.type == "entry"))
[dk_exit] = Flows.list_nodes(dlg_kim.id) |> Enum.filter(&(&1.type == "exit"))

Flows.update_node_position(dk_entry, %{position_x: 50.0, position_y: 300.0})
Flows.update_node_position(dk_exit, %{position_x: 1800.0, position_y: 300.0})

# Hub: Main conversation hub
{:ok, h_kim_main} =
  Flows.create_node(dlg_kim, %{
    type: "hub",
    position_x: 300.0,
    position_y: 300.0,
    data: %{"color" => "orange"}
  })

# Dialogue options from hub
resp_case = Seed.rid()
resp_personal = Seed.rid()
resp_leave = Seed.rid()

{:ok, d_kim_menu} =
  Flows.create_node(dlg_kim, %{
    type: "dialogue",
    position_x: 550.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>Kim turns to you, pen poised over his notebook. \"What would you like to discuss?\"</p>",
      "technical_id" => "DK_MENU_01",
      "responses" => [
        %{
          "id" => resp_case,
          "text" => "Ask about the case.",
          "condition" => "",
          "instruction" => ""
        },
        %{
          "id" => resp_personal,
          "text" => "Ask about himself.",
          "condition" =>
            Seed.condition_json("all", [
              %{
                sheet: "char.kim",
                variable: "trust",
                operator: "greater_than_or_equal",
                value: "40"
              }
            ]),
          "instruction" => ""
        },
        %{
          "id" => resp_leave,
          "text" => "\"That's all for now.\"",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# Case branch
resp_case_back = Seed.rid()

{:ok, d_case_info} =
  Flows.create_node(dlg_kim, %{
    type: "dialogue",
    position_x: 900.0,
    position_y: 150.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"The victim is a mercenary. Corporate security, likely Wild Pines. He was hanged — not suicide. The belt marks suggest he was dragged.\"</p><p>\"Whoever did this wanted to send a message.\"</p>",
      "stage_directions" => "Kim flips through his notes.",
      "technical_id" => "DK_CASE_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "items.evidence", variable: "witness_testimony", operator: "set_true"}
        ]),
      "responses" => [
        %{
          "id" => resp_case_back,
          "text" => "Ask something else.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# Personal branch
resp_personal_back = Seed.rid()

{:ok, d_personal} =
  Flows.create_node(dlg_kim, %{
    type: "dialogue",
    position_x: 900.0,
    position_y: 450.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"I've been with Precinct 57 for fifteen years.\" He adjusts his glasses. \"Before that... well. That's a longer story.\"</p>",
      "stage_directions" => "Kim's expression softens briefly.",
      "technical_id" => "DK_PERSONAL_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.kim", variable: "trust", operator: "add", value: "5"},
          %{sheet: "char.kim", variable: "mood", operator: "set", value: "pleased"}
        ]),
      "responses" => [
        %{
          "id" => resp_personal_back,
          "text" => "Ask something else.",
          "condition" => "",
          "instruction" => ""
        }
      ]
    }
  })

# Connections — Talk to Kim
Flows.create_connection(dlg_kim, dk_entry, h_kim_main, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_kim, h_kim_main, d_kim_menu, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_kim, d_kim_menu, d_case_info, %{
  source_pin: resp_case,
  target_pin: "input"
})

Flows.create_connection(dlg_kim, d_kim_menu, d_personal, %{
  source_pin: resp_personal,
  target_pin: "input"
})

Flows.create_connection(dlg_kim, d_kim_menu, dk_exit, %{
  source_pin: resp_leave,
  target_pin: "input"
})

# Jump nodes: loop back to conversation hub
h_kim_main = Flows.get_node!(dlg_kim.id, h_kim_main.id)

{:ok, j_case_back} =
  Flows.create_node(dlg_kim, %{
    type: "jump",
    position_x: 1200.0,
    position_y: 150.0,
    data: %{"target_hub_id" => h_kim_main.data["hub_id"]}
  })

{:ok, j_personal_back} =
  Flows.create_node(dlg_kim, %{
    type: "jump",
    position_x: 1200.0,
    position_y: 450.0,
    data: %{"target_hub_id" => h_kim_main.data["hub_id"]}
  })

Flows.create_connection(dlg_kim, d_case_info, j_case_back, %{
  source_pin: resp_case_back,
  target_pin: "input"
})

Flows.create_connection(dlg_kim, d_personal, j_personal_back, %{
  source_pin: resp_personal_back,
  target_pin: "input"
})

IO.puts("  ✓ Talk to Kim dialogue flow")

# -- Klaasje Interrogation --
{:ok, dlg_klaasje} =
  Flows.create_flow(project, %{
    name: "Klaasje Interrogation",
    shortcut: "dlg.klaasje",
    description: "Interrogate the woman from the room upstairs.",
    parent_id: dlg_folder.id
  })

[dkl_entry] = Flows.list_nodes(dlg_klaasje.id) |> Enum.filter(&(&1.type == "entry"))
[dkl_exit] = Flows.list_nodes(dlg_klaasje.id) |> Enum.filter(&(&1.type == "exit"))

Flows.update_node_position(dkl_entry, %{position_x: 50.0, position_y: 300.0})
Flows.update_node_position(dkl_exit, %{position_x: 2000.0, position_y: 300.0})

# Opening dialogue
resp_gentle = Seed.rid()
resp_pressure = Seed.rid()
resp_evidence = Seed.rid()

{:ok, d_klaasje_open} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 300.0,
    position_y: 300.0,
    data: %{
      "speaker_sheet_id" => klaasje_sheet.id,
      "text" =>
        "<p>She sits on the bed, legs crossed, smoking. There's something calculated in the way she looks at you.</p><p>\"Officer. I was wondering when you'd come up.\"</p>",
      "stage_directions" => "Klaasje's room. Sparse, temporary.",
      "technical_id" => "DKL_OPEN_01",
      "responses" => [
        %{
          "id" => resp_gentle,
          "text" => "\"Just a few questions, if you don't mind.\"",
          "condition" => "",
          "instruction" => ""
        },
        %{
          "id" => resp_pressure,
          "text" => "\"A man is dead outside your window. Start talking.\"",
          "condition" =>
            Seed.condition_json("all", [
              %{
                sheet: "char.detective",
                variable: "psyche",
                operator: "greater_than_or_equal",
                value: "4"
              }
            ]),
          "instruction" => ""
        },
        %{
          "id" => resp_evidence,
          "text" => "\"I found this near the body.\" [Show armor fragment]",
          "condition" =>
            Seed.condition_json("all", [
              %{
                sheet: "items.evidence",
                variable: "armor_fragment",
                operator: "is_true",
                value: nil
              }
            ]),
          "instruction" => ""
        }
      ]
    }
  })

# Gentle path
resp_gentle_truth = Seed.rid()
resp_gentle_lie = Seed.rid()

{:ok, d_gentle} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 650.0,
    position_y: 150.0,
    data: %{
      "speaker_sheet_id" => klaasje_sheet.id,
      "text" =>
        "<p>\"Of course.\" She smiles. \"I barely knew the man. I heard something that night — a commotion — but I was asleep by then.\"</p>",
      "technical_id" => "DKL_GENTLE_01",
      "responses" => [
        %{
          "id" => resp_gentle_truth,
          "text" => "\"I believe you.\" [Accept her story]",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "char.klaasje", variable: "trust", operator: "add", value: "15"}
            ])
        },
        %{
          "id" => resp_gentle_lie,
          "text" => "\"Something doesn't add up.\" [Press further]",
          "condition" => "",
          "instruction" =>
            Seed.instruction_json([
              %{sheet: "char.klaasje", variable: "trust", operator: "subtract", value: "10"}
            ])
        }
      ]
    }
  })

# Pressure path
{:ok, d_pressure} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 650.0,
    position_y: 450.0,
    data: %{
      "speaker_sheet_id" => klaasje_sheet.id,
      "text" =>
        "<p>Her composure cracks, just for a moment. \"I... Fine. I was with him that evening. But I didn't kill him. I couldn't have.\"</p>",
      "stage_directions" => "She stubs out the cigarette with trembling fingers.",
      "technical_id" => "DKL_PRESSURE_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.klaasje", variable: "told_truth", operator: "set_true"},
          %{sheet: "char.klaasje", variable: "trust", operator: "add", value: "5"}
        ]),
      "responses" => []
    }
  })

# Evidence path
{:ok, d_evidence} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 650.0,
    position_y: 600.0,
    data: %{
      "speaker_sheet_id" => klaasje_sheet.id,
      "text" =>
        "<p>Her eyes widen. \"Where did you—\" She catches herself. \"That doesn't prove anything. Anyone could have worn that armor.\"</p>",
      "technical_id" => "DKL_EVIDENCE_01",
      "output_instruction" =>
        Seed.instruction_json([
          %{sheet: "char.klaasje", variable: "trust", operator: "subtract", value: "15"}
        ]),
      "responses" => []
    }
  })

# Hub: merge branches
{:ok, h_klaasje_end} =
  Flows.create_node(dlg_klaasje, %{
    type: "hub",
    position_x: 1200.0,
    position_y: 300.0,
    data: %{"color" => "purple"}
  })

# Final condition: did she tell the truth?
truth_case = Seed.cid()
no_truth_case = Seed.cid()

{:ok, c_truth} =
  Flows.create_node(dlg_klaasje, %{
    type: "condition",
    position_x: 1450.0,
    position_y: 300.0,
    data: %{
      "expression" =>
        Jason.decode!(
          Seed.condition_json("all", [
            %{sheet: "char.klaasje", variable: "told_truth", operator: "is_true", value: nil}
          ])
        ),
      "cases" => [
        %{"id" => truth_case, "value" => "true", "label" => "Told the truth"},
        %{"id" => no_truth_case, "value" => "false", "label" => "Still hiding something"}
      ]
    }
  })

# Truth ending
{:ok, d_truth_end} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 1700.0,
    position_y: 200.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"She gave us something to work with. Let's verify her story before we proceed.\"</p>",
      "technical_id" => "DKL_TRUTH_END",
      "responses" => []
    }
  })

# No truth ending
{:ok, d_no_truth_end} =
  Flows.create_node(dlg_klaasje, %{
    type: "dialogue",
    position_x: 1700.0,
    position_y: 450.0,
    data: %{
      "speaker_sheet_id" => kim_sheet.id,
      "text" =>
        "<p>\"She's hiding something. We'll need more evidence before we can press her again.\"</p>",
      "technical_id" => "DKL_NO_TRUTH_END",
      "responses" => []
    }
  })

# Connections — Klaasje Interrogation
Flows.create_connection(dlg_klaasje, dkl_entry, d_klaasje_open, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_klaasje_open, d_gentle, %{
  source_pin: resp_gentle,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_klaasje_open, d_pressure, %{
  source_pin: resp_pressure,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_klaasje_open, d_evidence, %{
  source_pin: resp_evidence,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_gentle, h_klaasje_end, %{
  source_pin: resp_gentle_truth,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_gentle, h_klaasje_end, %{
  source_pin: resp_gentle_lie,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_pressure, h_klaasje_end, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_evidence, h_klaasje_end, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, h_klaasje_end, c_truth, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, c_truth, d_truth_end, %{
  source_pin: truth_case,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, c_truth, d_no_truth_end, %{
  source_pin: no_truth_case,
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_truth_end, dkl_exit, %{
  source_pin: "output",
  target_pin: "input"
})

Flows.create_connection(dlg_klaasje, d_no_truth_end, dkl_exit, %{
  source_pin: "output",
  target_pin: "input"
})

IO.puts("  ✓ Klaasje Interrogation dialogue flow")

# =============================================================================
# 10. Second user — adnumaro (editor on workspace + project)
# =============================================================================

{:ok, user2} =
  Accounts.register_user_only(%{email: "john@test.com", display_name: "Adnumaro"})

Workspaces.create_membership(workspace.id, user2.id, "admin")
Projects.create_membership(project.id, user2.id, "editor")

IO.puts("  ✓ User john@test.com (admin/editor)")

# =============================================================================
# Summary
# =============================================================================

sheet_count = length(Sheets.list_all_sheets(project.id))
flow_count = length(Flows.list_flows(project.id))

IO.puts("")
IO.puts("🎲 Seeding complete!")
IO.puts("   Project: Revachol Blues")
IO.puts("   Sheets:  #{sheet_count}")
IO.puts("   Flows:   #{flow_count}")
IO.puts("")
IO.puts("   Login as: detective@revachol.rce")
IO.puts("        or:  john@test.com")
IO.puts("   (use magic link — no password needed)")
