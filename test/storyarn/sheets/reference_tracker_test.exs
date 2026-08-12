defmodule Storyarn.Sheets.ReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Multi
  alias Storyarn.Flows
  alias Storyarn.References.EntityReference
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.ReferenceTracker

  @max_pg_bigint 9_223_372_036_854_775_807

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # Block references with nil target / unknown type
  # =============================================================================

  describe "extract_block_value_references/2 for reference blocks" do
    test "accepts a valid numeric target ID without rewriting it" do
      assert {:ok, [%{type: "sheet", id: "42", context: "value"}]} =
               ReferenceTracker.extract_block_value_references("reference", %{
                 "target_type" => "sheet",
                 "target_id" => "42"
               })
    end

    test "rejects nonnumeric, nonscalar, nonpositive and oversized target IDs with the original diagnostic" do
      invalid_ids = [
        "not-an-id",
        [1],
        %{"id" => 1},
        0,
        -1,
        "0",
        "-1",
        @max_pg_bigint + 1,
        to_string(@max_pg_bigint + 1)
      ]

      for invalid_id <- invalid_ids do
        assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, ^invalid_id}} =
                 ReferenceTracker.extract_block_value_references("reference", %{
                   "target_type" => "sheet",
                   "target_id" => invalid_id
                 })
      end
    end

    test "rejects false target fields for string- and atom-keyed values without losing their diagnostic shape" do
      invalid_values = [
        {%{"target_type" => "sheet", "target_id" => false}, "sheet", false},
        {%{target_type: "sheet", target_id: false}, "sheet", false},
        {%{"target_type" => false, "target_id" => nil}, false, nil},
        {%{target_type: false, target_id: nil}, false, nil}
      ]

      for {value, target_type, target_id} <- invalid_values do
        assert {:error, {:invalid_project_reference, {:block, :value, ^target_type}, ^target_id}} =
                 ReferenceTracker.extract_block_value_references("reference", value)
      end
    end
  end

  describe "update_block_references/1 with nil reference target" do
    test "creates no references when a reference block has no target" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          value: %{"target_type" => nil, "target_id" => nil}
        })

      ReferenceTracker.update_block_references(block)

      # No references should be created since target_id is nil
      backlinks = ReferenceTracker.get_backlinks("sheet", 0)
      assert backlinks == []
    end

    test "creates no references when reference block has no target fields" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          value: %{}
        })

      ReferenceTracker.update_block_references(block)

      # Should not create any references
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  describe "update_block_references/1 with unknown block type" do
    test "creates no references for text block (non-rich_text, non-reference)" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "text",
          config: %{"label" => "Simple Field"},
          value: %{"content" => "plain text"}
        })

      ReferenceTracker.update_block_references(block)

      # Text blocks have no references to track
      # Verify no error occurred and no references were created
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "creates no references for number block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 42}
        })

      ReferenceTracker.update_block_references(block)

      # Number blocks produce no references
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  describe "project-scoped reference rebuilding" do
    test "keeps only active targets owned by the requested project" do
      %{user: user, project: project} = setup_project()
      other_project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source"})
      local_target = sheet_fixture(project, %{name: "Local"})
      foreign_target = sheet_fixture(other_project, %{name: "Foreign"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => local_target.id}
        })

      assert :ok =
               ReferenceTracker.update_block_references(block,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", local_target.id) == 1

      block =
        Repo.update!(
          Ecto.Changeset.change(block,
            value: %{"target_type" => "sheet", "target_id" => foreign_target.id}
          )
        )

      assert :ok =
               ReferenceTracker.update_block_references(block,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", local_target.id) == 0
      assert ReferenceTracker.count_backlinks("sheet", foreign_target.id) == 0

      {:ok, _deleted_target} = Sheets.delete_sheet(local_target)

      block =
        Repo.update!(
          Ecto.Changeset.change(block,
            value: %{"target_type" => "sheet", "target_id" => local_target.id}
          )
        )

      assert :ok =
               ReferenceTracker.update_block_references(block,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", local_target.id) == 0
    end

    test "filters foreign mentions while retaining valid local mentions" do
      %{user: user, project: project} = setup_project()
      other_project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source"})
      local_target = sheet_fixture(project, %{name: "Local"})
      foreign_target = sheet_fixture(other_project, %{name: "Foreign"})

      content =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{local_target.id}">Local</span><span class="mention" data-type="sheet" data-id="#{foreign_target.id}">Foreign</span></p>)

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "rich_text",
          value: %{"content" => ""}
        })

      # Simulate pre-guard legacy/corrupt storage so the repair tracker itself
      # remains project-scoped without weakening the productive writer.
      block = Repo.update!(Ecto.Changeset.change(block, value: %{"content" => content}))

      assert :ok =
               ReferenceTracker.update_block_references(block,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", local_target.id) == 1
      assert ReferenceTracker.count_backlinks("sheet", foreign_target.id) == 0
    end
  end

  describe "list_stale_block_reference_source_ids/2" do
    test "returns source blocks whose tracked target is no longer active" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      assert :ok = ReferenceTracker.update_block_references(block, project_id: project.id)

      assert ReferenceTracker.list_stale_block_reference_source_ids(project.id, [block.id]) ==
               MapSet.new()

      Repo.update!(Ecto.Changeset.change(target_sheet, deleted_at: TimeHelpers.now()))

      assert ReferenceTracker.list_stale_block_reference_source_ids(project.id, [block.id]) ==
               MapSet.new([block.id])
    end

    test "retains live rich-text mentions after the target is permanently deleted" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      content =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Target</span></p>)

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "rich_text",
          value: %{"content" => content}
        })

      assert :ok = ReferenceTracker.update_block_references(block, project_id: project.id)
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

      assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(target_sheet)

      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

      assert ReferenceTracker.list_stale_block_reference_source_ids(project.id, [block.id]) ==
               MapSet.new([block.id])
    end

    test "returns an empty set without block ids" do
      %{project: project} = setup_project()
      assert ReferenceTracker.list_stale_block_reference_source_ids(project.id, []) == MapSet.new()
    end
  end

  # =============================================================================
  # Flow node references
  # =============================================================================

  describe "update_flow_node_references/1" do
    test "creates speaker reference from dialogue node" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Speaker"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
        })

      ReferenceTracker.update_flow_node_references(node)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks != []

      speaker_ref = Enum.find(backlinks, &(&1.context == "speaker"))
      assert speaker_ref
      assert speaker_ref.source_type == "flow_node"
      assert speaker_ref.source_id == node.id
    end

    test "creates mention references from dialogue text" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Mentioned"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      mention_html =
        ~s(<p>Meet <span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Mentioned</span></p>)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => mention_html}
        })

      ReferenceTracker.update_flow_node_references(node)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks != []

      dialogue_ref = Enum.find(backlinks, &(&1.context == "dialogue"))
      assert dialogue_ref
    end

    test "indexes valid mentions nested outside the top-level dialogue text" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Nested mention"})
      flow = flow_fixture(project, %{name: "Nested rich text"})

      mention_html =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Nested</span></p>)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Top-level text",
            "responses" => [%{"id" => "response_nested", "text" => mention_html}]
          }
        })

      assert :ok = ReferenceTracker.update_flow_node_references(node)

      assert Enum.any?(
               ReferenceTracker.get_backlinks("sheet", target_sheet.id),
               &(&1.source_type == "flow_node" and &1.source_id == node.id and
                   &1.context == "dialogue")
             )
    end

    test "infers the source project and rejects cross-project targets without opts" do
      %{user: user, project: project} = setup_project()
      other_project = project_fixture(user)
      foreign_target = sheet_fixture(other_project, %{name: "Foreign target"})
      flow = flow_fixture(project, %{name: "Implicit project scope"})

      valid_node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Do not cross projects"}
        })

      node =
        Repo.update!(
          Ecto.Changeset.change(valid_node,
            data: %{
              "speaker_sheet_id" => foreign_target.id,
              "text" => "Do not cross projects"
            }
          )
        )

      assert :ok = ReferenceTracker.update_flow_node_references(node)
      assert ReferenceTracker.count_backlinks("sheet", foreign_target.id) == 0
    end

    test "returns :ok for node without data map" do
      assert :ok == ReferenceTracker.update_flow_node_references(%{id: 999, data: nil})
    end

    test "returns :ok for non-map input" do
      assert :ok == ReferenceTracker.update_flow_node_references("not a map")
    end

    test "returns a tagged error for an invalid project-scoped write" do
      %{project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Invalid project scope"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello"}
        })

      assert {:error, {:invalid_project_id, :invalid}} =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: :invalid
               )
    end

    test "rolls back replacement when the project does not own the flow node" do
      %{project: project} = setup_project()
      other_project = project_fixture()
      target_sheet = sheet_fixture(project, %{name: "Existing target"})
      flow = flow_fixture(project, %{name: "Project scope rollback"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
        })

      assert :ok =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: project.id
               )

      existing_references = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert Enum.any?(existing_references, &(&1.source_id == node.id))

      assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: other_project.id
               )

      assert node_id == node.id
      assert project_id == other_project.id
      assert ReferenceTracker.get_backlinks("sheet", target_sheet.id) == existing_references
    end

    test "rejects a deleted flow node when rebuilding references directly" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Deleted node target"})
      flow = flow_fixture(project, %{name: "Deleted node source"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
        })

      assert :ok =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1
      assert {:ok, _deleted_node, _meta} = Flows.delete_node(node)
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0

      assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: project.id
               )

      assert node_id == node.id
      assert project_id == project.id
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0
    end

    test "rejects a node whose owning flow is in trash when rebuilding references directly" do
      %{project: project} = setup_project()
      original_target = sheet_fixture(project, %{name: "Deleted flow original target"})
      replacement_target = sheet_fixture(project, %{name: "Deleted flow replacement target"})
      flow = flow_fixture(project, %{name: "Deleted flow source"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => original_target.id, "text" => "Hello"}
        })

      assert :ok =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: project.id
               )

      assert ReferenceTracker.count_backlinks("sheet", original_target.id) == 1
      assert {:ok, _deleted_flow} = Flows.delete_flow(flow)
      assert ReferenceTracker.count_backlinks("sheet", original_target.id) == 1

      node =
        Repo.update!(
          Ecto.Changeset.change(node,
            data: %{
              "speaker_sheet_id" => replacement_target.id,
              "text" => "Changed while in trash"
            }
          )
        )

      assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
               ReferenceTracker.update_flow_node_references(node,
                 project_id: project.id
               )

      assert node_id == node.id
      assert project_id == project.id
      assert ReferenceTracker.count_backlinks("sheet", original_target.id) == 1
      assert ReferenceTracker.count_backlinks("sheet", replacement_target.id) == 0
    end

    test "returns an error from Ecto.Multi and rolls back preceding operations" do
      %{project: project} = setup_project()
      other_project = project_fixture()
      target_sheet = sheet_fixture(project, %{name: "Original name"})
      flow = flow_fixture(project, %{name: "Outer transaction rollback"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      result =
        Multi.new()
        |> Multi.update(
          :rename_target,
          Ecto.Changeset.change(target_sheet, name: "Sentinel name")
        )
        |> Multi.run(:rebuild_references, fn _repo, _changes ->
          ReferenceTracker.update_flow_node_references(node,
            project_id: other_project.id
          )
        end)
        |> Repo.transaction()

      assert {:error, :rebuild_references, {:flow_node_project_mismatch, node_id, project_id},
              %{rename_target: _renamed_sheet}} = result

      assert node_id == node.id
      assert project_id == other_project.id
      assert Repo.reload!(target_sheet).name == "Original name"
    end

    test "lets an outer transaction explicitly propagate a project ownership error" do
      %{project: project} = setup_project()
      other_project = project_fixture()
      target_sheet = sheet_fixture(project, %{name: "Original name"})
      flow = flow_fixture(project, %{name: "Explicit outer rollback"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      result =
        Repo.transaction(fn ->
          Repo.update!(Ecto.Changeset.change(target_sheet, name: "Sentinel name"))

          case ReferenceTracker.update_flow_node_references(node,
                 project_id: other_project.id
               ) do
            :ok ->
              :ok

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)

      assert {:error, {:flow_node_project_mismatch, node_id, project_id}} = result
      assert node_id == node.id
      assert project_id == other_project.id
      assert Repo.reload!(target_sheet).name == "Original name"
    end
  end

  # =============================================================================
  # Delete target references
  # =============================================================================

  describe "delete_target_references/2" do
    test "retains references from live blocks so missing targets remain detectable" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

      {count, nil} = ReferenceTracker.delete_target_references("sheet", target_sheet.id)

      assert count == 0
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1
    end

    test "removes self-references from blocks deleted with their target sheet" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Self-referencing"})

      {:ok, block} =
        Sheets.create_block(target_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

      assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(target_sheet)

      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0

      refute Repo.exists?(
               from(reference in EntityReference,
                 where: reference.source_type == "block" and reference.source_id == ^block.id
               )
             )
    end

    test "removes target references whose block source is no longer live" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)
      Repo.update!(Ecto.Changeset.change(block, deleted_at: TimeHelpers.now()))

      {count, nil} = ReferenceTracker.delete_target_references("sheet", target_sheet.id)

      assert count == 1
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0
    end

    test "returns zero count when no references exist for target" do
      {count, nil} = ReferenceTracker.delete_target_references("sheet", -1)

      assert count == 0
    end
  end

  # =============================================================================
  # parse_id/1 with non-integer inputs
  # =============================================================================

  describe "parse_id edge cases via batch_insert_references" do
    test "handles string IDs in reference targets" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      # Create a reference block with target_id as a string
      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => "#{target_sheet.id}"}
        })

      # This exercises parse_id/1 with a valid integer string
      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert length(backlinks) == 1
    end

    test "skips references with non-integer string IDs" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => nil, "target_id" => nil}
        })

      # Deliberately bypass the productive writer to exercise repair parsing.
      block =
        Repo.update!(
          Ecto.Changeset.change(block,
            value: %{"target_type" => "sheet", "target_id" => "not-a-number"}
          )
        )

      # This exercises parse_id/1 returning nil for non-integer strings
      ReferenceTracker.update_block_references(block)

      # No references should be created since the ID is invalid
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  # =============================================================================
  # Scene pin/zone references (fallback clauses)
  # =============================================================================

  describe "update_scene_pin_references/1" do
    test "returns :ok for non-matching input" do
      assert :ok == ReferenceTracker.update_scene_pin_references("not a map")
    end
  end

  describe "update_scene_zone_references/1" do
    test "returns :ok for non-matching input" do
      assert :ok == ReferenceTracker.update_scene_zone_references("not a map")
    end
  end

  # =============================================================================
  # Rich text mention extraction edge cases
  # =============================================================================

  describe "update_block_references/1 with rich_text mentions" do
    test "handles rich_text with no mention spans" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => "<p>Just plain text, no mentions.</p>"}
        })

      ReferenceTracker.update_block_references(block)

      # No references should be created
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "handles rich_text with nil content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => nil}
        })

      assert block.value["content"] == ""
      ReferenceTracker.update_block_references(block)

      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "handles rich_text with empty content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => ""}
        })

      ReferenceTracker.update_block_references(block)

      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  # =============================================================================
  # Flow node with empty speaker_sheet_id
  # =============================================================================

  describe "update_flow_node_references/1 with empty speaker" do
    test "ignores empty string speaker_sheet_id" do
      %{project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => "", "text" => "Hello"}
        })

      # This exercises the maybe_add_sheet_ref(refs, "", _context) clause
      ReferenceTracker.update_flow_node_references(node)

      # No speaker reference should be created
      # (empty string should be treated like nil)
      refs = ReferenceTracker.get_backlinks("sheet", 0)
      assert refs == []
    end
  end
end
