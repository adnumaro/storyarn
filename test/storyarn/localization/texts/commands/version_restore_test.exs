defmodule Storyarn.Localization.Texts.Commands.VersionRestoreTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Current"}})
    sheet = sheet_fixture(project)
    block = block_fixture(sheet, %{type: "text", value: %{"content" => "Current"}})

    %{project: project, node: node, block: block}
  end

  describe "restore_sheet_version_texts/3" do
    test "rejects rows outside the Sheet localization source contract", %{
      project: project,
      block: block
    } do
      row =
        block.id
        |> block_row()
        |> Map.put("source_type", "flow_node")

      assert {:ok, {:error, {:localization_restore_unmaterialized_rows, 1, 0}}} =
               Repo.transaction(fn ->
                 Localization.restore_sheet_version_texts(
                   project.id,
                   [row],
                   %{block: %{block.id => block.id}, node: %{block.id => block.id}}
                 )
               end)
    end
  end

  describe "restore_flow_version_texts/3" do
    test "requires a caller-owned transaction for a non-empty restore", %{
      project: project,
      node: node
    } do
      assert_raise ArgumentError,
                   "localization version restore requires an explicit database transaction",
                   fn ->
                     Localization.restore_flow_version_texts(
                       project.id,
                       [flow_row(node.id)],
                       %{node: %{node.id => node.id}}
                     )
                   end
    end

    test "participates in the caller transaction and rolls back with it", %{
      project: project,
      node: node
    } do
      Localization.purge_flow_node_texts([node.id])
      assert Localization.get_texts_for_source("flow_node", node.id) == []

      assert {:error, :forced_rollback} =
               Repo.transaction(fn ->
                 assert :ok =
                          Localization.restore_flow_version_texts(
                            project.id,
                            [flow_row(node.id)],
                            %{node: %{node.id => node.id}}
                          )

                 assert [_restored] = Localization.get_texts_for_source("flow_node", node.id)
                 Repo.rollback(:forced_rollback)
               end)

      assert Localization.get_texts_for_source("flow_node", node.id) == []
    end

    test "rejects rows outside the Flow localization source contract", %{
      project: project,
      node: node
    } do
      row = node.id |> flow_row() |> Map.put("source_type", "block")

      assert {:ok, {:error, {:localization_restore_unmaterialized_rows, 1, 0}}} =
               Repo.transaction(fn ->
                 Localization.restore_flow_version_texts(
                   project.id,
                   [row],
                   %{node: %{node.id => node.id}, block: %{node.id => node.id}}
                 )
               end)
    end
  end

  defp flow_row(source_id) do
    source_hash = :sha256 |> :crypto.hash("Snapshot text") |> Base.encode16(case: :lower)

    %{
      "source_type" => "flow_node",
      "source_id" => source_id,
      "source_field" => "text",
      "source_text" => "Snapshot text",
      "source_text_hash" => source_hash,
      "translated_source_hash" => source_hash,
      "locale_code" => "es",
      "translated_text" => "Texto de snapshot",
      "status" => "final",
      "vo_status" => "needed",
      "vo_asset_id" => nil,
      "translator_notes" => "Keep on restore",
      "reviewer_notes" => nil,
      "speaker_sheet_id" => nil,
      "word_count" => 2,
      "machine_translated" => false,
      "last_translated_at" => nil,
      "last_reviewed_at" => nil,
      "translated_by_id" => nil,
      "reviewed_by_id" => nil,
      "archived_at" => nil,
      "archive_reason" => nil
    }
  end

  defp block_row(source_id) do
    source_id
    |> flow_row()
    |> Map.merge(%{
      "source_type" => "block",
      "source_field" => "value.content",
      "vo_status" => "none"
    })
  end
end
