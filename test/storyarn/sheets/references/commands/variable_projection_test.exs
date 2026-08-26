defmodule Storyarn.Sheets.References.Commands.VariableProjectionTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Sheets.References.Commands.VariableProjection
  alias Storyarn.Sheets.References.Data.VariableReferenceRecord

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    %{project: project, flow: flow, sheet: sheet, block: block}
  end

  test "rebuilds Flow and Scene references through Sheet-owned read models", ctx do
    assignment = assignment(ctx.sheet.shortcut, ctx.block.variable_name)
    condition = condition(ctx.sheet.shortcut, ctx.block.variable_name)

    node =
      node_fixture(ctx.flow, %{
        type: "instruction",
        data: %{"assignments" => [assignment]}
      })

    scene = scene_fixture(ctx.project)
    pin = pin_fixture(scene, %{"condition" => condition})

    zone =
      zone_fixture(scene, %{
        "action_type" => "action",
        "action_data" => %{"assignments" => [assignment]}
      })

    ambient_flow =
      Repo.insert!(%SceneAmbientFlow{
        scene_id: scene.id,
        flow_id: ctx.flow.id,
        trigger_type: "on_event",
        trigger_config: %{
          "variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.block.variable_name}"
        },
        enabled: true,
        priority: 0,
        position: 0
      })

    source_keys = [
      {"flow_node", node.id},
      {"scene_pin", pin.id},
      {"scene_zone", zone.id},
      {"scene_ambient_flow", ambient_flow.id}
    ]

    Enum.each(source_keys, fn {source_type, source_id} ->
      Repo.delete_all(
        from(reference in VariableReferenceRecord,
          where:
            reference.source_type == ^source_type and
              reference.source_id == ^source_id
        )
      )
    end)

    assert :ok = VariableProjection.rebuild_project(ctx.project.id)

    references =
      from(reference in VariableReferenceRecord,
        where: reference.block_id == ^ctx.block.id,
        select: {
          reference.source_type,
          reference.source_id,
          reference.kind,
          reference.source_sheet,
          reference.source_variable,
          reference.flow_node_id
        }
      )
      |> Repo.all()
      |> MapSet.new()

    assert references ==
             MapSet.new([
               {
                 "flow_node",
                 node.id,
                 "write",
                 ctx.sheet.shortcut,
                 ctx.block.variable_name,
                 node.id
               },
               {
                 "scene_pin",
                 pin.id,
                 "read",
                 ctx.sheet.shortcut,
                 ctx.block.variable_name,
                 nil
               },
               {
                 "scene_zone",
                 zone.id,
                 "write",
                 ctx.sheet.shortcut,
                 ctx.block.variable_name,
                 nil
               },
               {
                 "scene_ambient_flow",
                 ambient_flow.id,
                 "read",
                 ctx.sheet.shortcut,
                 ctx.block.variable_name,
                 nil
               }
             ])
  end

  test "is additive and preserves stale rows when source names no longer resolve", ctx do
    node =
      node_fixture(ctx.flow, %{
        type: "instruction",
        data: %{
          "assignments" => [assignment(ctx.sheet.shortcut, ctx.block.variable_name)]
        }
      })

    assert :ok = VariableProjection.rebuild_project(ctx.project.id)

    [before] =
      Repo.all(
        from(reference in VariableReferenceRecord,
          where:
            reference.source_type == "flow_node" and
              reference.source_id == ^node.id
        )
      )

    Repo.update!(Ecto.Changeset.change(ctx.sheet, shortcut: "restored-sheet"))
    Repo.update!(Ecto.Changeset.change(ctx.block, variable_name: "restored-health"))

    assert :ok = VariableProjection.rebuild_project(ctx.project.id)

    assert [%{id: id, block_id: block_id}] =
             Repo.all(
               from(reference in VariableReferenceRecord,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^node.id
               )
             )

    assert id == before.id
    assert block_id == ctx.block.id
  end

  test "keeps the historical parser contract for serialized dialogue conditions", ctx do
    malformed_condition =
      ctx.sheet.shortcut
      |> condition(ctx.block.variable_name)
      |> Map.delete("logic")
      |> Jason.encode!()

    node =
      node_fixture(ctx.flow, %{
        type: "dialogue",
        data: %{
          "responses" => [
            %{
              "id" => Ecto.UUID.generate(),
              "text" => "Continue",
              "condition" => malformed_condition
            }
          ]
        }
      })

    Repo.delete_all(
      from(reference in VariableReferenceRecord,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^node.id
      )
    )

    assert :ok = VariableProjection.rebuild_project(ctx.project.id)

    refute Repo.exists?(
             from(reference in VariableReferenceRecord,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^node.id
             )
           )
  end

  test "resolves table references and qualified Scene display references", ctx do
    table = table_block_fixture(ctx.sheet, %{label: "Stats"})
    row = table_row_fixture(table, %{name: "Strength"})

    column =
      table_column_fixture(table, %{
        name: "Modifier",
        type: "formula",
        is_constant: true
      })

    variable = "#{table.variable_name}.#{row.slug}.#{column.slug}"

    node =
      node_fixture(ctx.flow, %{
        type: "instruction",
        data: %{"assignments" => [assignment(ctx.sheet.shortcut, variable)]}
      })

    scene = scene_fixture(ctx.project)

    zone =
      zone_fixture(scene, %{
        "action_type" => "display",
        "action_data" => %{
          "variable_ref" => "#{ctx.sheet.shortcut}.#{variable}"
        }
      })

    Enum.each([{"flow_node", node.id}, {"scene_zone", zone.id}], fn {source_type, source_id} ->
      Repo.delete_all(
        from(reference in VariableReferenceRecord,
          where:
            reference.source_type == ^source_type and
              reference.source_id == ^source_id
        )
      )
    end)

    assert :ok = VariableProjection.rebuild_project(ctx.project.id)
    source_ids = [node.id, zone.id]

    assert from(reference in VariableReferenceRecord,
             where:
               reference.block_id == ^table.id and
                 reference.source_id in ^source_ids,
             select: {
               reference.source_type,
               reference.kind,
               reference.source_sheet,
               reference.source_variable,
               reference.flow_node_id
             }
           )
           |> Repo.all()
           |> MapSet.new() ==
             MapSet.new([
               {"flow_node", "write", ctx.sheet.shortcut, variable, node.id},
               {"scene_zone", "read", ctx.sheet.shortcut, variable, nil}
             ])
  end

  test "rejects an invalid project scope" do
    assert {:error, {:invalid_project_id, nil}} =
             VariableProjection.rebuild_project(nil)
  end

  defp assignment(sheet, variable) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet,
      "variable" => variable,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }
  end

  defp condition(sheet, variable) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet,
              "variable" => variable,
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        }
      ]
    }
  end
end
