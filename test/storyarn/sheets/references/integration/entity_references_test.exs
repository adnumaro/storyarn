defmodule Storyarn.Sheets.References.Integration.EntityReferencesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.References
  alias Storyarn.Sheets.References.Entities.EntityReferenceRecord

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
               References.extract_block_value_references("reference", %{
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
                 References.extract_block_value_references("reference", %{
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
                 References.extract_block_value_references("reference", value)
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

      References.update_block_references(block)

      # No references should be created since target_id is nil
      backlinks = References.get_backlinks("sheet", 0)
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

      References.update_block_references(block)

      # Should not create any references
      assert References.count_backlinks("sheet", 0) == 0
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

      References.update_block_references(block)

      # Text blocks have no references to track
      # Verify no error occurred and no references were created
      assert References.count_backlinks("sheet", 0) == 0
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

      References.update_block_references(block)

      # Number blocks produce no references
      assert References.count_backlinks("sheet", 0) == 0
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
               References.update_block_references(block,
                 project_id: project.id
               )

      assert References.count_backlinks("sheet", local_target.id) == 1

      block =
        Repo.update!(
          Ecto.Changeset.change(block,
            value: %{"target_type" => "sheet", "target_id" => foreign_target.id}
          )
        )

      assert :ok =
               References.update_block_references(block,
                 project_id: project.id
               )

      assert References.count_backlinks("sheet", local_target.id) == 0
      assert References.count_backlinks("sheet", foreign_target.id) == 0

      {:ok, _deleted_target} = Sheets.delete_sheet(local_target)

      block =
        Repo.update!(
          Ecto.Changeset.change(block,
            value: %{"target_type" => "sheet", "target_id" => local_target.id}
          )
        )

      assert :ok =
               References.update_block_references(block,
                 project_id: project.id
               )

      assert References.count_backlinks("sheet", local_target.id) == 0
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
               References.update_block_references(block,
                 project_id: project.id
               )

      assert References.count_backlinks("sheet", local_target.id) == 1
      assert References.count_backlinks("sheet", foreign_target.id) == 0
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

      assert :ok = References.update_block_references(block, project_id: project.id)

      assert References.list_stale_block_reference_source_ids(project.id, [block.id]) ==
               MapSet.new()

      Repo.update!(Ecto.Changeset.change(target_sheet, deleted_at: TimeHelpers.now()))

      assert References.list_stale_block_reference_source_ids(project.id, [block.id]) ==
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

      assert :ok = References.update_block_references(block, project_id: project.id)
      assert References.count_backlinks("sheet", target_sheet.id) == 1

      assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(target_sheet)

      assert References.count_backlinks("sheet", target_sheet.id) == 1

      assert References.list_stale_block_reference_source_ids(project.id, [block.id]) ==
               MapSet.new([block.id])
    end

    test "returns an empty set without block ids" do
      %{project: project} = setup_project()
      assert References.list_stale_block_reference_source_ids(project.id, []) == MapSet.new()
    end
  end

  describe "Flow-owned entity-reference projection reads" do
    test "resolves Flow-node backlinks through the Sheets-owned read models" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Speaker"})
      flow = flow_fixture(project, %{name: "Local projection", shortcut: "local-projection"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
        })

      assert [backlink] =
               References.get_backlinks_with_sources(
                 "sheet",
                 target_sheet.id,
                 project.id
               )

      assert backlink.source_type == "flow_node"
      assert backlink.source_id == node.id

      assert backlink.source_info == %{
               type: :flow,
               flow_id: flow.id,
               flow_name: "Local projection",
               flow_shortcut: "local-projection",
               node_type: "dialogue"
             }
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

      References.update_block_references(block)
      assert References.count_backlinks("sheet", target_sheet.id) == 1

      {count, nil} = References.delete_target_references("sheet", target_sheet.id)

      assert count == 0
      assert References.count_backlinks("sheet", target_sheet.id) == 1
    end

    test "removes self-references from blocks deleted with their target sheet" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Self-referencing"})

      {:ok, block} =
        Sheets.create_block(target_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      References.update_block_references(block)
      assert References.count_backlinks("sheet", target_sheet.id) == 1

      assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(target_sheet)

      assert References.count_backlinks("sheet", target_sheet.id) == 0

      refute Repo.exists?(
               from(reference in EntityReferenceRecord,
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

      References.update_block_references(block)
      Repo.update!(Ecto.Changeset.change(block, deleted_at: TimeHelpers.now()))

      {count, nil} = References.delete_target_references("sheet", target_sheet.id)

      assert count == 1
      assert References.count_backlinks("sheet", target_sheet.id) == 0
    end

    test "does not delete reference rows owned by another bounded context" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Target"})
      now = DateTime.to_naive(TimeHelpers.now())

      {1, [reference]} =
        Repo.insert_all(
          EntityReferenceRecord,
          [
            %{
              source_type: "scene_zone",
              source_id: 987_654,
              target_type: "sheet",
              target_id: target_sheet.id,
              context: "display",
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: true
        )

      assert {0, nil} =
               References.delete_target_references("sheet", target_sheet.id)

      assert Repo.get!(EntityReferenceRecord, reference.id)
    end

    test "returns zero count when no references exist for target" do
      {count, nil} = References.delete_target_references("sheet", -1)

      assert count == 0
    end
  end

  describe "delete_block_references_for_sources/1" do
    test "deletes only the requested Sheet-owned block sources" do
      [first_id, second_id, foreign_id] =
        Enum.map(1..3, fn _index -> System.unique_integer([:positive]) end)

      now = DateTime.to_naive(TimeHelpers.now())

      {3, nil} =
        Repo.insert_all(EntityReferenceRecord, [
          reference_row("block", first_id, now),
          reference_row("block", second_id, now),
          reference_row("flow_node", foreign_id, now)
        ])

      assert {2, nil} =
               References.delete_block_references_for_sources([first_id, second_id])

      assert Repo.aggregate(
               from(reference in EntityReferenceRecord,
                 where: reference.source_id in ^[first_id, second_id, foreign_id]
               ),
               :count
             ) == 1
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
      References.update_block_references(block)

      backlinks = References.get_backlinks("sheet", target_sheet.id)
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
      References.update_block_references(block)

      # No references should be created since the ID is invalid
      assert References.count_backlinks("sheet", 0) == 0
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

      References.update_block_references(block)

      # No references should be created
      assert References.count_backlinks("sheet", 0) == 0
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
      References.update_block_references(block)

      assert References.count_backlinks("sheet", 0) == 0
    end

    test "handles rich_text with empty content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => ""}
        })

      References.update_block_references(block)

      assert References.count_backlinks("sheet", 0) == 0
    end
  end

  defp reference_row(source_type, source_id, now) do
    %{
      source_type: source_type,
      source_id: source_id,
      target_type: "sheet",
      target_id: System.unique_integer([:positive]),
      context: "test",
      inserted_at: now,
      updated_at: now
    }
  end
end
