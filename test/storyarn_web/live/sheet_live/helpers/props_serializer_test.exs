defmodule StoryarnWeb.SheetLive.Helpers.PropsSerializerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.SheetLive.Helpers.PropsSerializer

  describe "prepare_blocks_for_vue/5" do
    test "marks reattachable blocks and groups adjacent column blocks" do
      source_block_id = 42

      detached_block =
        block(%{
          id: 1,
          position: 0,
          detached: true,
          inherited_from_block_id: source_block_id
        })

      right_column = block(%{id: 2, position: 1, column_group_id: "group-1", column_index: 1})
      left_column = block(%{id: 3, position: 2, column_group_id: "group-1", column_index: 0})
      inherited_groups = [%{blocks: [%{inherited_from_block_id: source_block_id}]}]

      result =
        PropsSerializer.prepare_blocks_for_vue(
          [right_column, detached_block, left_column],
          %{},
          %{},
          nil,
          inherited_groups
        )

      assert [
               %{type: "full_width", block: %{id: 1, can_reattach: true}},
               %{type: "column_group", blocks: [%{id: 3}, %{id: 2}], column_count: 2}
             ] = result
    end

    test "serializes gallery and table block props" do
      gallery_block = block(%{id: 10, type: "gallery", position: 0})
      table_block = block(%{id: 20, type: "table", position: 1, config: %{"collapsed" => true}})

      gallery_data = %{
        10 => [
          %{
            id: 100,
            asset: %{id: 501, url: "/uploads/hero.png"},
            label: "Hero",
            description: "Portrait"
          }
        ]
      }

      table_data = %{
        20 => %{
          columns: [
            %{
              id: 200,
              name: "Name",
              slug: "name",
              type: "text",
              position: 0,
              is_constant: false,
              required: true,
              config: %{"placeholder" => "Name"}
            }
          ],
          rows: [
            %{
              id: 300,
              name: "Row",
              slug: "row",
              position: 0,
              cells: %{"name" => %{"content" => "Kael"}}
            }
          ]
        }
      }

      result =
        PropsSerializer.prepare_blocks_for_vue(
          [gallery_block, table_block],
          gallery_data,
          table_data,
          nil,
          []
        )

      assert [
               %{
                 block: %{
                   gallery_images: [
                     %{
                       id: 100,
                       url: "/media/assets/501",
                       label: "Hero",
                       description: "Portrait"
                     }
                   ]
                 }
               },
               %{
                 block: %{
                   collapsed: true,
                   columns: [%{id: 200, name: "Name", config: %{"placeholder" => "Name"}}],
                   rows: [%{id: 300, name: "Row", cells: %{"name" => %{"content" => "Kael"}}}]
                 }
               }
             ] = result
    end

    test "resolves reference block targets when project context is available" do
      project = Repo.preload(project_fixture(), :workspace)
      target_sheet = sheet_fixture(project, %{name: "Target Sheet", shortcut: "target-sheet"})

      reference_block =
        block(%{
          id: 30,
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      [%{block: serialized_block}] =
        PropsSerializer.prepare_blocks_for_vue([reference_block], %{}, %{}, project.id, [])

      assert serialized_block.reference_target == %{
               type: "sheet",
               id: target_sheet.id,
               name: "Target Sheet",
               shortcut: "target-sheet"
             }
    end
  end

  defp block(attrs) do
    Map.merge(
      %{
        id: System.unique_integer([:positive]),
        type: "text",
        position: 0,
        is_constant: false,
        variable_name: nil,
        scope: nil,
        inherited_from_block_id: nil,
        detached: false,
        required: false,
        column_group_id: nil,
        column_index: nil,
        config: %{},
        value: %{}
      },
      attrs
    )
  end
end
