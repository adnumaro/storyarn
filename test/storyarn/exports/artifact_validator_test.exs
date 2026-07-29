defmodule Storyarn.Exports.ArtifactValidatorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Exports.ArtifactValidator
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    %{project: project_fixture(user)}
  end

  test "derives stale references from every serialized expression source", %{project: project} do
    flow =
      flow(10, "References", "references", [
        node(101, "condition", %{
          "condition" => condition("missing", "condition", "equals")
        }),
        node(102, "instruction", %{
          "assignments" => [
            assignment("missing", "write"),
            assignment("missing", "target",
              value_type: "variable_ref",
              value_sheet: "missing",
              value: "read"
            )
          ]
        }),
        node(103, "dialogue", %{
          "localization_id" => "dialogue_refs",
          "condition" => condition("missing", "dialogue", "equals"),
          "responses" => [
            %{
              "id" => "response_refs",
              "condition" => condition("missing", "response", "equals"),
              "instruction_assignments" => [assignment("missing", "response_write")]
            }
          ]
        })
      ])

    findings = findings(project.id, :ink, [flow], [])
    stale = Enum.filter(findings, &(&1.rule == :stale_variable_reference))

    assert stale |> Enum.map(& &1.node_id) |> Enum.sort() == [101, 102, 103]
    assert Enum.all?(stale, &(&1.level == :error))

    dialogue = Enum.find(stale, &(&1.node_id == 103))

    assert dialogue.details.references == [
             "missing.dialogue",
             "missing.response",
             "missing.response_write"
           ]
  end

  test "variable liveness is independent from the selected sheets", %{project: project} do
    selected = sheet_fixture(project, %{name: "Selected", shortcut: "selected"})
    _selected_block = block_fixture(selected, %{variable_name: "present"})

    excluded = sheet_fixture(project, %{name: "Excluded", shortcut: "excluded"})
    excluded_block = block_fixture(excluded, %{variable_name: "target"})

    flow =
      flow(20, "Selection", "selection", [
        node(201, "condition", %{
          "condition" => condition(excluded.shortcut, excluded_block.variable_name, "equals")
        })
      ])

    selected_only = [sheet_brief(selected)]
    all_sheets = [sheet_brief(selected), sheet_brief(excluded)]

    refute Enum.any?(
             findings(project.id, :ink, [flow], selected_only),
             &(&1.rule == :stale_variable_reference and &1.node_id == 201)
           )

    refute Enum.any?(
             findings(project.id, :ink, [flow], all_sheets),
             &(&1.rule == :stale_variable_reference and &1.node_id == 201)
           )

    excluded_block
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    assert Enum.any?(
             findings(project.id, :ink, [flow], all_sheets),
             &(&1.rule == :stale_variable_reference and &1.node_id == 201)
           )
  end

  test "pin and zone variables are live references", %{
    project: project
  } do
    scene = scene_fixture(project)
    pin = pin_fixture(scene, %{"label" => "Gate", "shortcut" => "gate"})
    zone = zone_fixture(scene, %{"name" => "Courtyard", "shortcut" => "courtyard"})

    flow =
      flow(21, "Scene variables", "scene-variables", [
        node(211, "condition", %{
          "condition" => condition(pin.shortcut, "hidden", "equals")
        }),
        node(212, "condition", %{
          "condition" => condition(zone.shortcut, "hidden", "equals")
        })
      ])

    ink = findings(project.id, :ink, [flow], [])
    yarn = findings(project.id, :yarn, [flow], [])

    refute Enum.any?(
             ink ++ yarn,
             &(&1.rule == :stale_variable_reference and &1.node_id in [211, 212])
           )
  end

  test "uses tracked reference identity when a stale shortcut resolves to another variable", %{
    project: project
  } do
    original = sheet_fixture(project, %{name: "Original hero", shortcut: "hero"})
    original_block = block_fixture(original, %{variable_name: "health"})
    persisted_flow = flow_fixture(project, %{name: "Tracked reference"})

    instruction =
      node_fixture(persisted_flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            assignment(original.shortcut, original_block.variable_name)
          ]
        }
      })

    :ok = References.update_flow_node_variable_references(instruction)

    persisted_flow = Repo.preload(persisted_flow, [:nodes, :connections], force: true)
    entry = Enum.find(persisted_flow.nodes, &(&1.type == "entry"))
    Storyarn.FlowsFixtures.connection_fixture(persisted_flow, entry, instruction)

    {:ok, _renamed} = Sheets.update_sheet(original, %{shortcut: "protagonist"})
    replacement = sheet_fixture(project, %{name: "Replacement hero", shortcut: "hero"})
    _replacement_block = block_fixture(replacement, %{variable_name: "health"})

    persisted_flow = Repo.preload(persisted_flow, [:nodes, :connections], force: true)

    finding =
      project.id
      |> findings(:ink, [persisted_flow], [])
      |> Enum.find(&(&1.rule == :stale_variable_reference and &1.node_id == instruction.id))

    assert finding.level == :error
    assert finding.details.references == ["hero.health"]
    assert finding.details.tracked_reference_stale
  end

  test "tracked stale draft refs do not taint live condition or instruction rows", %{
    project: project
  } do
    original = sheet_fixture(project, %{name: "Original hero", shortcut: "hero"})
    original_block = block_fixture(original, %{variable_name: "health"})
    live_sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    live_block = block_fixture(live_sheet, %{variable_name: "ready", type: "boolean"})
    persisted_flow = flow_fixture(project, %{name: "Tracked draft references"})

    stale_draft_rule = %{
      "id" => "stale-draft",
      "sheet" => original.shortcut,
      "variable" => original_block.variable_name,
      "operator" => nil,
      "value" => nil
    }

    live_rule = %{
      "id" => "live",
      "sheet" => live_sheet.shortcut,
      "variable" => live_block.variable_name,
      "operator" => "is_true",
      "value" => nil
    }

    condition_with = fn rules ->
      %{
        "logic" => "all",
        "blocks" => [
          %{"id" => "block", "type" => "block", "logic" => "all", "rules" => rules}
        ]
      }
    end

    stale_draft_assignment =
      assignment(original.shortcut, original_block.variable_name, operator: nil)

    live_assignment =
      assignment(live_sheet.shortcut, live_block.variable_name, operator: "set_true")

    draft_condition =
      node_fixture(persisted_flow, %{
        type: "condition",
        data: %{"condition" => condition_with.([stale_draft_rule])}
      })

    mixed_condition =
      node_fixture(persisted_flow, %{
        type: "condition",
        data: %{"condition" => condition_with.([live_rule, stale_draft_rule])}
      })

    draft_instruction =
      node_fixture(persisted_flow, %{
        type: "instruction",
        data: %{"assignments" => [stale_draft_assignment]}
      })

    mixed_instruction =
      node_fixture(persisted_flow, %{
        type: "instruction",
        data: %{"assignments" => [live_assignment, stale_draft_assignment]}
      })

    tracked_nodes = [draft_condition, mixed_condition, draft_instruction, mixed_instruction]
    Enum.each(tracked_nodes, &References.update_flow_node_variable_references/1)

    persisted_flow = Repo.preload(persisted_flow, [:nodes, :connections], force: true)
    entry = Enum.find(persisted_flow.nodes, &(&1.type == "entry"))

    Storyarn.FlowsFixtures.connection_fixture(persisted_flow, entry, draft_condition)

    Storyarn.FlowsFixtures.connection_fixture(persisted_flow, draft_condition, mixed_condition, source_pin: "true")

    Storyarn.FlowsFixtures.connection_fixture(persisted_flow, mixed_condition, draft_instruction, source_pin: "true")

    Storyarn.FlowsFixtures.connection_fixture(persisted_flow, draft_instruction, mixed_instruction)

    {:ok, _renamed} = Sheets.update_sheet(original, %{shortcut: "protagonist"})
    replacement = sheet_fixture(project, %{name: "Replacement hero", shortcut: "hero"})
    _replacement_block = block_fixture(replacement, %{variable_name: "health"})

    stale_ref = "hero.health"

    stale_by_node =
      [persisted_flow.id]
      |> References.list_stale_node_variable_refs_by_flow()
      |> Map.fetch!(persisted_flow.id)

    assert Enum.all?(tracked_nodes, fn node ->
             Map.get(stale_by_node, node.id) == MapSet.new([stale_ref])
           end)

    persisted_flow = Repo.preload(persisted_flow, [:nodes, :connections], force: true)
    tracked_node_ids = MapSet.new(tracked_nodes, & &1.id)

    stale_findings =
      project.id
      |> findings(:ink, [persisted_flow], [])
      |> Enum.filter(
        &(&1.rule == :stale_variable_reference and
            MapSet.member?(tracked_node_ids, &1.node_id))
      )

    assert stale_findings == []
  end

  test "legacy response instructions are transpiled when the structured list is empty", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "visited"})

    response =
      %{
        "id" => "response_legacy",
        "instruction_assignments" => [],
        "instruction" =>
          Jason.encode!([
            assignment(sheet.shortcut, block.variable_name, operator: "set_if_unset")
          ])
      }

    corrupt_response = %{
      "id" => "response_corrupt",
      "instruction_assignments" => [],
      "instruction" => "{not-json"
    }

    flow =
      flow(30, "Legacy", "legacy", [
        node(301, "dialogue", %{
          "localization_id" => "dialogue_legacy",
          "responses" => [response, corrupt_response]
        })
      ])

    result = findings(project.id, :yarn, [flow], [sheet_brief(sheet)])

    assert Enum.any?(
             result,
             &(&1.rule == :semantic_loss and
                 &1.expression_source == {:response_instruction, 1})
           )

    assert Enum.any?(
             result,
             &(&1.rule == :invalid_export_expression and
                 &1.expression_source == {:response_instruction, 2})
           )
  end

  test "default empty conditions are no-ops while corrupt JSON blocks", %{project: project} do
    flow =
      flow(40, "Conditions", "conditions", [
        node(401, "condition", %{"condition" => %{"logic" => "all", "rules" => []}}),
        node(402, "condition", %{"condition" => %{"logic" => "all", "blocks" => []}}),
        node(403, "condition", %{"condition" => "{not-json"})
      ])

    invalid =
      project.id
      |> findings(:ink, [flow], [])
      |> Enum.filter(&(&1.rule == :invalid_export_expression))

    assert Enum.map(invalid, & &1.node_id) == [403]
  end

  test "transient incomplete instruction rows are no-ops in every format", %{
    project: project
  } do
    incomplete_assignment = %{
      "id" => "draft-assignment",
      "sheet" => nil,
      "variable" => nil,
      "operator" => "set",
      "value" => nil,
      "value_type" => "literal",
      "value_sheet" => nil
    }

    operatorless_assignment = %{
      "id" => "operatorless-draft",
      "sheet" => "missing",
      "variable" => "draft",
      "operator" => nil,
      "value" => nil,
      "value_type" => "literal",
      "value_sheet" => nil
    }

    flow =
      flow(42, "Draft instructions", "draft-instructions", [
        node(421, "instruction", %{"assignments" => [incomplete_assignment]}),
        node(422, "dialogue", %{
          "localization_id" => "draft_response_instruction",
          "responses" => [
            %{
              "id" => "draft_response",
              "instruction_assignments" => [incomplete_assignment]
            }
          ]
        }),
        node(423, "instruction", %{"assignments" => [operatorless_assignment]}),
        node(424, "dialogue", %{
          "localization_id" => "operatorless_response_instruction",
          "responses" => [
            %{
              "id" => "operatorless_response",
              "instruction_assignments" => [operatorless_assignment]
            }
          ]
        })
      ])

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      invalid =
        project.id
        |> findings(format, [flow], [])
        |> Enum.filter(&(&1.rule == :invalid_export_expression))

      refute Enum.any?(invalid, &(&1.node_id in [421, 422, 423, 424]))

      refute Enum.any?(
               findings(project.id, format, [flow], []),
               &(&1.rule == :stale_variable_reference and &1.node_id in [423, 424])
             )
    end
  end

  test "valid instruction rows still transpile when mixed with an incomplete row", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "visited"})

    incomplete_assignment = %{
      "id" => "draft-assignment",
      "sheet" => nil,
      "variable" => nil,
      "operator" => "set",
      "value" => nil,
      "value_type" => "literal",
      "value_sheet" => nil
    }

    flow =
      flow(43, "Mixed instructions", "mixed-instructions", [
        node(431, "instruction", %{
          "assignments" => [
            incomplete_assignment,
            assignment(sheet.shortcut, block.variable_name, operator: "set_if_unset")
          ]
        })
      ])

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      refute Enum.any?(
               findings(project.id, format, [flow], [sheet_brief(sheet)]),
               &(&1.rule == :invalid_export_expression and &1.node_id == 431)
             )
    end

    assert Enum.any?(
             findings(project.id, :ink, [flow], [sheet_brief(sheet)]),
             &(&1.rule == :semantic_loss and &1.node_id == 431)
           )
  end

  test "incomplete instruction rows that serializers would emit still block export", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "visited"})

    flow =
      flow(44, "Incomplete instructions", "incomplete-instructions", [
        node(441, "instruction", %{
          "assignments" => [
            assignment(sheet.shortcut, block.variable_name, value: nil)
          ]
        })
      ])

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      assert Enum.any?(
               findings(project.id, format, [flow], [sheet_brief(sheet)]),
               &(&1.rule == :invalid_export_expression and &1.node_id == 441)
             )
    end
  end

  test "malformed instruction containers still block export", %{project: project} do
    flow =
      flow(45, "Malformed instructions", "malformed-instructions", [
        node(451, "instruction", %{"assignments" => %{}})
      ])

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      assert Enum.any?(
               findings(project.id, format, [flow], []),
               &(&1.rule == :invalid_export_expression and &1.node_id == 451)
             )
    end
  end

  test "legacy flat conditions are validated and transpiled", %{project: project} do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "ready"})

    flat_condition = %{
      "logic" => "all",
      "rules" => [
        %{
          "sheet" => sheet.shortcut,
          "variable" => block.variable_name,
          "operator" => "is_true",
          "value" => nil
        }
      ]
    }

    flow = flow(41, "Flat condition", "flat-condition", [node(411, "condition", %{"condition" => flat_condition})])
    result = findings(project.id, :ink, [flow], [sheet_brief(sheet)])

    refute Enum.any?(result, &(&1.rule == :invalid_export_expression and &1.node_id == 411))
    refute Enum.any?(result, &(&1.rule == :stale_variable_reference and &1.node_id == 411))
  end

  test "nil node data is normalized instead of crashing", %{project: project} do
    flow = flow(50, "Nil data", "nil-data", [node(501, "dialogue", nil)])

    assert Enum.any?(
             findings(project.id, :ink, [flow], []),
             &(&1.rule == :invalid_dialogue_runtime_id and &1.node_id == 501)
           )
  end

  test "control references accept active flows outside selection and reject unavailable targets", %{
    project: project
  } do
    target = flow_fixture(project, %{name: "Target", shortcut: "target"})

    source =
      %{
        flow(60, "Source", "source", [
          node(601, "jump", %{}),
          node(602, "subflow", %{}),
          node(603, "exit", %{"exit_mode" => "flow_reference"}),
          node(604, "jump", %{"target_hub_id" => "ghost"}),
          node(605, "subflow", %{"referenced_flow_id" => target.id}),
          node(606, "exit", %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => target.id
          }),
          node(607, "subflow", %{"referenced_flow_id" => -999}),
          node(608, "exit", %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => -999
          }),
          node(609, "jump", %{}),
          node(610, "hub", %{"hub_id" => "connected_hub", "label" => "Connected Hub"}),
          node(611, "jump", %{"referenced_flow_id" => target.id})
        ])
        | connections: [connection(609, 610)]
      }

    rules =
      MapSet.new([
        :missing_jump_target,
        :missing_subflow_reference,
        :missing_exit_flow_reference,
        :stale_jump_target,
        :stale_subflow_reference,
        :stale_exit_flow_reference
      ])

    ink =
      project.id
      |> findings(:ink, [source], [])
      |> Enum.filter(&MapSet.member?(rules, &1.rule))

    unity =
      project.id
      |> findings(:unity, [source], [])
      |> Enum.filter(&MapSet.member?(rules, &1.rule))

    assert MapSet.new(ink, & &1.rule) == rules
    assert Enum.all?(ink, &(&1.level == :error))
    assert MapSet.new(unity, & &1.rule) == rules
    assert Enum.all?(unity, &(&1.level == :warning))

    for format <- [:ink, :unity] do
      external =
        project.id
        |> findings(format, [source], [])
        |> Enum.filter(&(&1.rule == :external_flow_reference))

      assert Enum.map(external, & &1.node_id) == [605, 606, 611]
      assert Enum.all?(external, &(&1.level == :warning))
      assert Enum.all?(external, &(&1.message =~ "outside this partial export"))
    end

    assert Enum.any?(
             findings(project.id, :ink, [source], []),
             &(&1.node_id == 609 and &1.rule == :missing_jump_target)
           )
  end

  test "external targets must have valid non-colliding runtime identifiers", %{
    project: project
  } do
    invalid_target = flow_fixture(project, %{name: "No Shortcut"})
    invalid_target = invalid_target |> Ecto.Changeset.change(shortcut: nil) |> Repo.update!()
    colliding_target = flow_fixture(project, %{name: "External Quest", shortcut: "quest.main"})

    source =
      flow(61, "Selected Quest", "quest-main", [
        node(612, "subflow", %{"referenced_flow_id" => invalid_target.id}),
        node(613, "subflow", %{"referenced_flow_id" => colliding_target.id})
      ])

    result = findings(project.id, :ink, [source], [])

    assert Enum.any?(
             result,
             &(&1.rule == :invalid_flow_identifier and
                 &1.target_flow_id == invalid_target.id and &1.level == :error)
           )

    assert Enum.any?(
             result,
             &(&1.rule == :flow_identifier_collision and
                 MapSet.new(&1.colliding_entity_ids) ==
                   MapSet.new([source.id, colliding_target.id]))
           )
  end

  test "missing references do not bind to an unrelated flow with a nil shortcut", %{
    project: project
  } do
    unrelated = flow_fixture(project, %{name: "No Shortcut"})
    unrelated |> Ecto.Changeset.change(shortcut: nil) |> Repo.update!()
    source = flow(62, "Missing reference", "missing-reference", [node(621, "subflow", %{})])

    result = findings(project.id, :articy, [source], [])

    assert Enum.any?(result, &(&1.rule == :missing_subflow_reference and &1.node_id == 621))

    refute Enum.any?(
             result,
             &(&1.rule == :invalid_flow_identifier and
                 Map.get(&1, :target_flow_id) == unrelated.id)
           )
  end

  test "required shortcuts block consuming formats but only warn for Unity", %{project: project} do
    invalid_flow = flow(90, "No shortcut", nil, [])
    invalid_sheet = %{id: 901, name: "No shortcut", shortcut: nil}

    for format <- [:ink, :yarn, :godot, :unreal, :articy] do
      result = findings(project.id, format, [invalid_flow], [invalid_sheet])

      assert Enum.any?(
               result,
               &(&1.rule == :invalid_flow_identifier and &1.level == :error)
             )

      assert Enum.any?(
               result,
               &(&1.rule == :invalid_sheet_identifier and &1.level == :error)
             )
    end

    unity = findings(project.id, :unity, [invalid_flow], [invalid_sheet])

    assert Enum.any?(unity, &(&1.rule == :invalid_flow_identifier and &1.level == :warning))
    assert Enum.any?(unity, &(&1.rule == :invalid_sheet_identifier and &1.level == :warning))
    refute Enum.any?(unity, &(&1.rule in [:invalid_flow_identifier, :invalid_sheet_identifier] and &1.level == :error))
  end

  test "detects normalized flow and sheet collisions only for formats that use them", %{
    project: project
  } do
    flows = [
      flow(70, "Hyphen flow", "foo-bar", []),
      flow(71, "Dotted flow", "foo.bar", [])
    ]

    sheets = [
      %{id: 701, name: "Hyphen sheet", shortcut: "actor-one"},
      %{id: 702, name: "Dotted sheet", shortcut: "actor.one"}
    ]

    ink = findings(project.id, :ink, flows, sheets)
    unity = findings(project.id, :unity, flows, sheets)
    articy = findings(project.id, :articy, flows, sheets)

    assert Enum.any?(
             ink,
             &(&1.rule == :flow_identifier_collision and &1.identifier == "foo_bar")
           )

    assert Enum.any?(
             ink,
             &(&1.rule == :sheet_identifier_collision and &1.identifier == "actor_one")
           )

    refute Enum.any?(unity, &(&1.rule in [:flow_identifier_collision, :sheet_identifier_collision]))

    assert Enum.count(articy, &(&1.rule == :invalid_flow_identifier)) == 2
    assert Enum.count(articy, &(&1.rule == :invalid_sheet_identifier)) == 2
    refute Enum.any?(articy, &(&1.rule in [:flow_identifier_collision, :sheet_identifier_collision]))
  end

  test "detects normalized variable collisions in the selected artifact", %{project: project} do
    sheet = sheet_fixture(project, %{name: "Variables", shortcut: "variables"})
    first = block_fixture(sheet, %{variable_name: "foo-bar"})
    second = block_fixture(sheet, %{variable_name: "foo.bar"})

    result = findings(project.id, :ink, [], [sheet_brief(sheet)])
    collision = Enum.find(result, &(&1.rule == :variable_identifier_collision))

    assert collision
    assert collision.identifier == "variables_foo_bar"
    assert MapSet.new(collision.colliding_entity_ids) == MapSet.new([first.id, second.id])

    refute Enum.any?(
             findings(project.id, :godot, [], [sheet_brief(sheet)]),
             &(&1.rule == :variable_identifier_collision)
           )
  end

  test "invalid variable identifiers block every format that would emit a mismatched reference", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "Variables", shortcut: "variables"})

    block =
      sheet
      |> block_fixture(%{variable_name: "safe_name"})
      |> Ecto.Changeset.change(variable_name: "bad name")
      |> Repo.update!()

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      finding =
        project.id
        |> findings(format, [], [sheet_brief(sheet)])
        |> Enum.find(&(&1.rule == :invalid_variable_identifier))

      assert finding
      assert finding.level == :error
      assert finding.entity_id == block.id
      assert finding.identifier == "variables.bad name"
    end
  end

  test "Unity tolerates duplicate dialogue IDs but duplicate response IDs corrupt its entry plan", %{
    project: project
  } do
    duplicate_responses = [
      %{"id" => "same_response", "text" => "One"},
      %{"id" => "same_response", "text" => "Two"}
    ]

    flow =
      flow(80, "Runtime IDs", "runtime-ids", [
        node(801, "dialogue", %{
          "localization_id" => "same_dialogue",
          "responses" => duplicate_responses
        }),
        node(802, "dialogue", %{
          "localization_id" => "same_dialogue",
          "responses" => []
        })
      ])

    ink = findings(project.id, :ink, [flow], [])
    unity = findings(project.id, :unity, [flow], [])

    assert Enum.all?([:duplicate_dialogue_runtime_id, :duplicate_response_runtime_id], fn rule ->
             Enum.any?(ink, fn finding -> finding.rule == rule and finding.level == :error end)
           end)

    assert Enum.any?(
             unity,
             &(&1.rule == :duplicate_dialogue_runtime_id and &1.level == :warning)
           )

    assert Enum.any?(
             unity,
             &(&1.rule == :duplicate_response_runtime_id and &1.level == :error)
           )
  end

  test "missing response IDs that share Unity's effective key are blocking", %{project: project} do
    flow =
      flow(81, "Missing response IDs", "missing-response-ids", [
        node(811, "dialogue", %{
          "localization_id" => "dialogue_missing_responses",
          "responses" => [%{"text" => "One"}, %{"text" => "Two"}]
        })
      ])

    unity = findings(project.id, :unity, [flow], [])

    assert Enum.any?(
             unity,
             &(&1.rule == :invalid_response_runtime_id and &1.level == :warning)
           )

    assert Enum.any?(
             unity,
             &(&1.rule == :duplicate_response_runtime_id and &1.level == :error)
           )
  end

  test "mixed empty condition branches preserve runtime semantics without blocking", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "ready"})
    valid = condition(sheet.shortcut, block.variable_name, "equals")

    mixed_condition = %{
      "logic" => "any",
      "blocks" => [
        %{"id" => "empty", "type" => "block", "logic" => "all", "rules" => []}
        | valid["blocks"]
      ]
    }

    flow =
      flow(100, "Mixed condition", "mixed-condition", [
        node(1001, "condition", %{"condition" => mixed_condition})
      ])

    refute Enum.any?(
             findings(project.id, :ink, [flow], [sheet_brief(sheet)]),
             &(&1.rule == :invalid_export_expression)
           )
  end

  test "condition rows without a target or operator are transient no-ops", %{
    project: project
  } do
    draft_rule = %{
      "id" => "draft",
      "sheet" => nil,
      "variable" => nil,
      "operator" => "equals",
      "value" => nil
    }

    valid_rule = %{
      "id" => "valid",
      "sheet" => "state",
      "variable" => "ready",
      "operator" => "equals",
      "value" => true
    }

    missing_operator_rule = %{valid_rule | "id" => "missing-operator", "operator" => nil}

    condition_with = fn rules ->
      %{
        "logic" => "all",
        "blocks" => [
          %{"id" => "block", "type" => "block", "logic" => "all", "rules" => rules}
        ]
      }
    end

    flow =
      flow(105, "Draft conditions", "draft-conditions", [
        node(1051, "condition", %{"condition" => condition_with.([draft_rule])}),
        node(1052, "condition", %{
          "condition" => condition_with.([valid_rule, draft_rule])
        }),
        node(1053, "condition", %{
          "condition" => condition_with.([missing_operator_rule])
        }),
        node(1054, "condition", %{
          "condition" => condition_with.([valid_rule, missing_operator_rule])
        })
      ])

    for format <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
      result = findings(project.id, format, [flow], [])

      refute Enum.any?(
               result,
               &(&1.rule == :invalid_export_expression and
                   &1.node_id in [1051, 1052, 1053, 1054])
             )

      refute Enum.any?(
               result,
               &(&1.rule == :stale_variable_reference and &1.node_id == 1053)
             )
    end
  end

  test "unknown operators, missing values, and impossible values block", %{
    project: project
  } do
    base_rule = %{
      "id" => "rule",
      "sheet" => "state",
      "variable" => "ready",
      "operator" => "equals",
      "value" => "yes"
    }

    condition_with = fn rules ->
      %{
        "logic" => "all",
        "blocks" => [
          %{"id" => "block", "type" => "block", "logic" => "all", "rules" => rules}
        ]
      }
    end

    flow =
      flow(110, "Invalid conditions", "invalid-conditions", [
        node(1102, "condition", %{
          "condition" => condition_with.([%{base_rule | "operator" => "unknown_operator"}])
        }),
        node(1103, "condition", %{
          "condition" => condition_with.([%{base_rule | "value" => nil}])
        }),
        node(1104, "condition", %{
          "condition" => condition_with.([%{base_rule | "value" => %{}}])
        })
      ])

    result = findings(project.id, :ink, [flow], [])
    invalid = Enum.filter(result, &(&1.rule == :invalid_export_expression))

    assert MapSet.new(invalid, & &1.node_id) == MapSet.new([1102, 1103, 1104])
    assert Enum.all?(invalid, &(&1.level == :error))

    assert Enum.any?(
             result,
             &(&1.rule == :stale_variable_reference and &1.node_id == 1103)
           )
  end

  test "malformed dialogue and response data blocks even nil-tolerant formats", %{
    project: project
  } do
    flow =
      flow(120, "Malformed runtime data", "malformed-runtime-data", [
        node(1201, "dialogue", %{"localization_id" => %{}, "responses" => []}),
        node(1202, "dialogue", %{
          "localization_id" => "dialogue_map",
          "responses" => %{}
        }),
        node(1203, "dialogue", %{
          "localization_id" => "dialogue_shape",
          "responses" => [%{"id" => []}]
        })
      ])

    for format <- [:ink, :unity] do
      result = findings(project.id, format, [flow], [])

      assert Enum.any?(
               result,
               &(&1.node_id == 1201 and &1.rule == :invalid_dialogue_data and
                   &1.level == :error)
             )

      assert Enum.all?([1202, 1203], fn node_id ->
               Enum.any?(
                 result,
                 &(&1.node_id == node_id and &1.rule == :invalid_response_data and
                     &1.level == :error)
               )
             end)
    end
  end

  test "stale variable severity follows the target format matrix", %{project: project} do
    flow =
      flow(130, "Stale variable", "stale-variable", [
        node(1301, "condition", %{
          "condition" => condition("missing", "variable", "equals")
        })
      ])

    assert Enum.any?(
             findings(project.id, :ink, [flow], []),
             &(&1.rule == :stale_variable_reference and &1.level == :error)
           )

    for format <- [:yarn, :unity, :godot, :unreal, :articy] do
      assert Enum.any?(
               findings(project.id, format, [flow], []),
               &(&1.rule == :stale_variable_reference and &1.level == :warning)
             )
    end
  end

  test "linear formats warn about unreachable nodes without validating omitted content", %{
    project: project
  } do
    flow =
      135
      |> flow("Reachability", "reachability", [
        node(1351, "entry", %{}),
        node(1352, "exit", %{}),
        node(1353, "dialogue", %{
          "text" => "Detached",
          "condition" => condition("missing", "variable", "equals"),
          "responses" => []
        })
      ])
      |> Map.put(:connections, [connection(1351, 1352)])

    for format <- [:ink, :yarn, :godot] do
      result = findings(project.id, format, [flow], [])

      assert Enum.any?(
               result,
               &(&1.rule == :unreachable_node and &1.node_id == 1353 and
                   &1.level == :warning)
             )

      refute Enum.any?(
               result,
               &(&1.node_id == 1353 and
                   &1.rule in [
                     :invalid_dialogue_runtime_id,
                     :stale_variable_reference,
                     :invalid_export_expression
                   ])
             )
    end

    unity = findings(project.id, :unity, [flow], [])
    refute Enum.any?(unity, &(&1.rule == :unreachable_node))

    assert Enum.any?(
             unity,
             &(&1.rule == :invalid_dialogue_runtime_id and &1.node_id == 1353)
           )
  end

  test "linear formats validate nodes emitted inside hub sections", %{project: project} do
    flow =
      138
      |> flow("Hub section", "hub-section", [
        node(1381, "entry", %{}),
        node(1382, "hub", %{"hub_id" => "meeting-point", "label" => "Meeting point"}),
        node(1383, "dialogue", %{"text" => "Detached runtime id", "responses" => []}),
        node(1384, "exit", %{})
      ])
      |> Map.put(:connections, [
        connection(1381, 1382),
        connection(1382, 1383),
        connection(1383, 1384)
      ])

    for format <- [:ink, :yarn, :godot] do
      result = findings(project.id, format, [flow], [])

      assert Enum.any?(
               result,
               &(&1.rule == :invalid_dialogue_runtime_id and &1.node_id == 1383)
             )

      refute Enum.any?(
               result,
               &(&1.rule == :unreachable_node and &1.node_id == 1383)
             )
    end
  end

  test "Yarn reports unambiguous variable type mismatches without blocking", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "name", type: "text"})

    flow =
      flow(136, "Type mismatch", "type-mismatch", [
        node(1361, "instruction", %{
          "assignments" => [
            assignment(sheet.shortcut, block.variable_name, operator: "add", value: 1)
          ]
        })
      ])

    yarn = findings(project.id, :yarn, [flow], [sheet_brief(sheet)])

    assert Enum.any?(
             yarn,
             &(&1.rule == :variable_type_mismatch and &1.node_id == 1361 and
                 &1.level == :warning)
           )

    refute Enum.any?(
             findings(project.id, :ink, [flow], [sheet_brief(sheet)]),
             &(&1.rule == :variable_type_mismatch)
           )
  end

  test "ambiguous sheet and pin variable types do not create a mismatch verdict", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "Shared", shortcut: "shared"})
    block = block_fixture(sheet, %{variable_name: "hidden", type: "text"})
    scene = scene_fixture(project)
    _pin = pin_fixture(scene, %{"label" => "Shared", "shortcut" => "shared"})

    flow =
      flow(137, "Ambiguous type", "ambiguous-type", [
        node(1371, "instruction", %{
          "assignments" => [
            assignment(sheet.shortcut, block.variable_name, operator: "add", value: 1)
          ]
        })
      ])

    refute Enum.any?(
             findings(project.id, :yarn, [flow], [sheet_brief(sheet)]),
             &(&1.rule == :variable_type_mismatch)
           )
  end

  test "Yarn catches collisions between final dialogue and response line IDs", %{
    project: project
  } do
    flow =
      140
      |> flow("Yarn IDs", "yarn-ids", [
        node(1400, "entry", %{}),
        node(1401, "dialogue", %{
          "localization_id" => "dialogue_a",
          "responses" => [%{"id" => "b", "text" => "Choice"}]
        }),
        node(1402, "dialogue", %{
          "localization_id" => "dialogue_a_response_b",
          "responses" => []
        })
      ])
      |> Map.put(:connections, [
        connection(1400, 1401),
        connection(1401, 1402, "response_b")
      ])

    assert Enum.any?(
             findings(project.id, :yarn, [flow], []),
             &(&1.rule == :yarn_line_id_collision and &1.level == :error)
           )
  end

  test "hub identifiers come from hub_id while human labels remain free-form", %{
    project: project
  } do
    valid_flow =
      flow(150, "Hub labels", "hub-labels", [
        node(1501, "hub", %{"hub_id" => "main-hub", "label" => "Main Hub (Act One)"})
      ])

    refute Enum.any?(
             findings(project.id, :ink, [valid_flow], []),
             &(&1.rule == :invalid_hub_identifier)
           )

    collision_flow =
      flow(151, "Hub collisions", "hub-collisions", [
        node(1511, "hub", %{"hub_id" => "same-hub", "label" => "First"}),
        node(1512, "hub", %{"hub_id" => "same.hub", "label" => "Second"})
      ])

    assert Enum.any?(
             findings(project.id, :ink, [collision_flow], []),
             &(&1.rule == :hub_identifier_collision and &1.identifier == "same_hub")
           )
  end

  test "target-valid normalized shortcuts are accepted without reusing authoring rules", %{
    project: project
  } do
    flow = flow(160, "Mixed Case", "Chapter-One", [])
    sheet = %{id: 1601, name: "Actor", shortcut: "Actor.One"}

    result = findings(project.id, :ink, [flow], [sheet])

    refute Enum.any?(
             result,
             &(&1.rule in [:invalid_flow_identifier, :invalid_sheet_identifier])
           )

    assert Enum.any?(
             findings(project.id, :unreal, [flow], [%{sheet | shortcut: "actor-one"}]),
             &(&1.rule == :invalid_sheet_identifier and &1.level == :error)
           )
  end

  test "linear formats block subflows whose return branches would be concatenated", %{
    project: project
  } do
    target = flow_fixture(project, %{name: "Target", shortcut: "target"})

    source =
      %{
        flow(170, "Subflow branches", "subflow-branches", [
          node(1701, "subflow", %{"referenced_flow_id" => target.id}),
          node(1702, "exit", %{}),
          node(1703, "exit", %{})
        ])
        | connections: [
            connection(1701, 1702, "exit_left"),
            connection(1701, 1703, "exit_right")
          ]
      }

    for format <- [:ink, :yarn, :godot] do
      assert Enum.any?(
               findings(project.id, format, [source], []),
               &(&1.rule == :semantic_loss and &1.level == :error and &1.node_id == 1701)
             )
    end

    refute Enum.any?(
             findings(project.id, :unity, [source], []),
             &(&1.rule == :semantic_loss and &1.node_id == 1701)
           )
  end

  test "format-specific switch losses are blocking while an empty default switch is valid", %{
    project: project
  } do
    explicit =
      node(1801, "condition", %{
        "cases" => [
          %{"id" => "one"},
          %{"id" => "two"},
          %{"id" => "three"}
        ]
      })

    grouped =
      node(1802, "condition", %{
        "switch_mode" => true,
        "condition" => %{
          "logic" => "all",
          "blocks" => [
            %{
              "id" => "group",
              "type" => "group",
              "logic" => "all",
              "blocks" => []
            }
          ]
        }
      })

    empty_default =
      node(1803, "condition", %{
        "switch_mode" => true,
        "condition" => %{"logic" => "all", "blocks" => []}
      })

    flow = flow(180, "Switches", "switches", [explicit, grouped, empty_default])

    for format <- [:ink, :yarn] do
      result = findings(project.id, format, [flow], [])

      assert Enum.any?(
               result,
               &(&1.rule == :semantic_loss and &1.node_id == 1801 and &1.level == :error)
             )

      assert Enum.any?(
               result,
               &(&1.rule == :semantic_loss and &1.node_id == 1802 and &1.level == :error)
             )

      refute Enum.any?(result, &(&1.rule == :semantic_loss and &1.node_id == 1803))
    end

    assert Enum.any?(
             findings(project.id, :godot, [flow], []),
             &(&1.rule == :semantic_loss and &1.node_id == 1801 and &1.level == :error)
           )

    assert Enum.any?(
             findings(project.id, :unity, [flow], []),
             &(&1.rule == :semantic_loss and &1.node_id == 1802 and &1.level == :error)
           )
  end

  test "Articy reports dialogue behavior its serializer omits", %{project: project} do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "ready"})

    flow =
      flow(190, "Articy losses", "articy-losses", [
        node(1901, "dialogue", %{
          "localization_id" => "dialogue_articy",
          "condition" => condition(sheet.shortcut, block.variable_name, "equals"),
          "responses" => [
            %{
              "id" => "response_articy",
              "instruction_assignments" => [
                assignment(sheet.shortcut, block.variable_name)
              ]
            }
          ]
        })
      ])

    semantic =
      project.id
      |> findings(:articy, [flow], [sheet_brief(sheet)])
      |> Enum.filter(&(&1.rule == :semantic_loss and &1.node_id == 1901))

    assert length(semantic) == 2
    assert Enum.all?(semantic, &(&1.level == :warning))
    assert Enum.any?(semantic, &(&1.details.reason =~ "Dialogue conditions"))
    assert Enum.any?(semantic, &(&1.details.reason =~ "Response assignments"))
  end

  test "linear formats block inline dialogue conditions they cannot represent", %{
    project: project
  } do
    sheet = sheet_fixture(project, %{name: "State", shortcut: "state"})
    block = block_fixture(sheet, %{variable_name: "ready"})

    flow =
      flow(191, "Conditional dialogue", "conditional-dialogue", [
        node(1911, "dialogue", %{
          "localization_id" => "conditional_dialogue",
          "condition" => condition(sheet.shortcut, block.variable_name, "equals"),
          "responses" => []
        })
      ])

    for format <- [:ink, :yarn, :godot] do
      assert Enum.any?(
               findings(project.id, format, [flow], [sheet_brief(sheet)]),
               &(&1.rule == :semantic_loss and &1.node_id == 1911 and &1.level == :error)
             )
    end
  end

  test "Unreal and Articy warn when response-specific routing is flattened", %{
    project: project
  } do
    dialogue =
      node(1921, "dialogue", %{
        "localization_id" => "routed_dialogue",
        "responses" => [
          %{"id" => "left", "text" => "Left"},
          %{"id" => "right", "text" => "Right"}
        ]
      })

    routed_flow =
      %{
        flow(192, "Routed dialogue", "routed-dialogue", [
          dialogue,
          node(1922, "exit", %{}),
          node(1923, "exit", %{})
        ])
        | connections: [
            connection(1921, 1922, "response_left"),
            connection(1921, 1923, "response_right")
          ]
      }

    for format <- [:unreal, :articy] do
      assert Enum.any?(
               findings(project.id, format, [routed_flow], []),
               &(&1.rule == :semantic_loss and &1.node_id == 1921 and
                   &1.level == :warning and
                   &1.details.reason =~ "Response-specific routing")
             )
    end
  end

  test "Unreal and Articy report branch routing their graph output flattens", %{
    project: project
  } do
    target = flow_fixture(project, %{name: "Target", shortcut: "target"})

    routed_flow =
      %{
        flow(194, "Branched routing", "branched-routing", [
          node(1941, "condition", %{
            "cases" => [%{"id" => "yes"}, %{"id" => "no"}]
          }),
          node(1942, "subflow", %{"referenced_flow_id" => target.id}),
          node(1943, "exit", %{}),
          node(1944, "exit", %{})
        ])
        | connections: [
            connection(1941, 1943, "yes"),
            connection(1941, 1944, "no"),
            connection(1942, 1943, "left"),
            connection(1942, 1944, "right")
          ]
      }

    for format <- [:unreal, :articy] do
      assert Enum.any?(
               findings(project.id, format, [routed_flow], []),
               &(&1.rule == :semantic_loss and &1.node_id == 1941 and
                   &1.details.reason =~ "Condition branch routing")
             )
    end

    assert Enum.any?(
             findings(project.id, :articy, [routed_flow], []),
             &(&1.rule == :semantic_loss and &1.node_id == 1942 and
                 &1.details.reason =~ "Subflow return routing")
           )
  end

  test "Unreal blocks subflows because the CSV contains no corresponding row", %{
    project: project
  } do
    target = flow_fixture(project, %{name: "Target", shortcut: "target"})
    flow = flow(193, "Caller", "caller", [node(1931, "subflow", %{"referenced_flow_id" => target.id})])

    assert Enum.any?(
             findings(project.id, :unreal, [flow], []),
             &(&1.rule == :semantic_loss and &1.node_id == 1931 and &1.level == :error)
           )
  end

  defp findings(project_id, format, flows, sheets) do
    ArtifactValidator.findings(
      project_id,
      %ExportOptions{format: format},
      flows,
      sheets
    )
  end

  defp flow(id, name, shortcut, nodes) do
    %Flow{
      id: id,
      name: name,
      shortcut: shortcut,
      nodes: nodes,
      connections: []
    }
  end

  defp node(id, type, data), do: %FlowNode{id: id, type: type, data: data}

  defp connection(source_node_id, target_node_id, source_pin \\ "output") do
    %{
      source_node_id: source_node_id,
      target_node_id: target_node_id,
      source_pin: source_pin,
      target_pin: "input"
    }
  end

  defp sheet_brief(sheet), do: %{id: sheet.id, name: sheet.name, shortcut: sheet.shortcut}

  defp condition(sheet, variable, operator) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "block",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule",
              "sheet" => sheet,
              "variable" => variable,
              "operator" => operator,
              "value" => "value"
            }
          ]
        }
      ]
    }
  end

  defp assignment(sheet, variable, opts \\ []) do
    %{
      "sheet" => sheet,
      "variable" => variable,
      "operator" => Keyword.get(opts, :operator, "set"),
      "value" => Keyword.get(opts, :value, "value"),
      "value_type" => Keyword.get(opts, :value_type, "literal"),
      "value_sheet" => Keyword.get(opts, :value_sheet)
    }
  end
end
