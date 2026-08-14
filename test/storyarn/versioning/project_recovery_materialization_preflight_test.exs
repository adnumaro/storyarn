defmodule Storyarn.Versioning.ProjectRecoveryMaterializationPreflightTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Versioning.ProjectRecovery

  setup do
    user = user_fixture()
    project = project_fixture(user)

    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    sheet = sheet_fixture(project, %{name: "Localized Sheet"})

    block =
      block_fixture(sheet, %{
        type: "rich_text",
        value: %{"content" => "A localizable biography"}
      })

    %{project: project, block: block}
  end

  test "rejects an active localization row whose source is absent before materialization", %{
    project: project,
    block: block
  } do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    missing_id = block.id + 1_000_000

    malformed =
      snapshot
      |> update_in(["localization", "texts"], fn texts ->
        Enum.map(texts, fn
          %{"source_type" => "block", "source_id" => source_id} = text when source_id == block.id ->
            Map.put(text, "source_id", missing_id)

          text ->
            text
        end)
      end)
      |> update_in(["sheets"], fn sheets ->
        Enum.map(sheets, fn entry ->
          update_in(entry, ["snapshot", "localization"], fn texts ->
            Enum.map(texts, fn
              %{"source_type" => "block", "source_id" => source_id} = text when source_id == block.id ->
                Map.put(text, "source_id", missing_id)

              text ->
                text
            end)
          end)
        end)
      end)
      |> refresh_localization_manifests()

    assert {:error,
            {:invalid_project_snapshot_entity, :sheet, _sheet_id,
             {:invalid_sheet_localization_snapshot, %{"source_id" => ^missing_id}}}} =
             ProjectRecovery.validate_materialization_snapshot(malformed)
  end

  test "rejects an archived orphan localization row from the active restore contract", %{
    project: project,
    block: block
  } do
    assert [text] = Localization.get_texts_for_source("block", block.id)
    assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Archivada", status: "final"})
    assert {:ok, _block} = Storyarn.Sheets.delete_block(block)

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    # Backup-era project objects are rejected by object format before the
    # active-only localization seam. Isolate the seam by making its nested
    # localization inventory active while keeping the archived global row.
    snapshot =
      update_in(snapshot, ["sheets"], fn sheets ->
        Enum.map(sheets, fn entry ->
          update_in(entry, ["snapshot", "localization"], fn texts ->
            Enum.reject(texts, &(not is_nil(&1["archived_at"])))
          end)
        end)
      end)

    assert Enum.any?(snapshot["localization"]["texts"], fn row ->
             row["source_type"] == "block" and row["source_id"] == block.id and
               not is_nil(row["archived_at"])
           end)

    assert {:error, :archived_project_snapshot_localized_text_not_materializable} =
             ProjectRecovery.validate_materialization_snapshot(snapshot)
  end

  test "rejects malformed localization actor identities without querying materialization state", %{
    project: project
  } do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    for {field, invalid_id} <- [
          {"translated_by_id", 0},
          {"reviewed_by_id", "not-an-id"}
        ] do
      malformed = put_localization_actor(snapshot, field, invalid_id)

      assert {:error,
              {:invalid_project_snapshot_entity, :sheet, _sheet_id,
               {:invalid_sheet_localization_snapshot, %{^field => ^invalid_id}}}} =
               ProjectRecovery.validate_materialization_snapshot(malformed)
    end
  end

  test "rejects missing localization actors before graph writes", %{project: project} do
    snapshot = project.id |> ProjectSnapshotBuilder.build_snapshot() |> Map.put("asset_catalog_refs", %{})
    target_project = project_fixture(user_fixture())
    missing_user_id = 999_999_999

    for field <- ["translated_by_id", "reviewed_by_id"] do
      malformed = put_localization_actor(snapshot, field, missing_user_id)

      counts_before = materialized_graph_counts(target_project.id)

      assert {:error, {:localization_reference_not_materializable, ^field, ^missing_user_id}} =
               ProjectRecovery.validate_materialization_snapshot(malformed)

      assert {:error, {:localization_reference_not_materializable, ^field, ^missing_user_id}} =
               materialize_snapshot_into_project(target_project, malformed)

      assert materialized_graph_counts(target_project.id) == counts_before
      assert Localization.list_all_texts(target_project.id) == []
    end
  end

  defp put_localization_actor(snapshot, field, actor_id) do
    snapshot
    |> update_in(["localization", "texts"], &put_actor_on_rows(&1, field, actor_id))
    |> put_nested_localization_actor("sheets", field, actor_id)
    |> put_nested_localization_actor("flows", field, actor_id)
    |> refresh_localization_manifests()
  end

  defp put_nested_localization_actor(snapshot, collection, field, actor_id) do
    update_in(snapshot, [collection], fn entries ->
      Enum.map(entries, fn entry ->
        update_in(entry, ["snapshot", "localization"], &put_actor_on_rows(&1, field, actor_id))
      end)
    end)
  end

  defp put_actor_on_rows(rows, field, actor_id) do
    Enum.map(rows, &Map.put(&1, field, actor_id))
  end

  defp refresh_localization_manifests(snapshot) do
    Enum.reduce(["sheets", "flows"], snapshot, fn collection, acc ->
      update_in(acc, [collection], &Enum.map(&1, fn entry -> refresh_entity_localization_manifest(entry) end))
    end)
  end

  defp refresh_entity_localization_manifest(entry) do
    entity_snapshot = entry["snapshot"]
    rows = entity_snapshot["localization"]
    target_locales = entity_snapshot["localization_manifest"]["target_locales"]

    put_in(
      entry,
      ["snapshot", "localization_manifest"],
      LocalizationSnapshotCodec.manifest(rows, target_locales)
    )
  end

  defp materialize_snapshot_into_project(project, snapshot) do
    Storyarn.Repo.transaction(fn ->
      case ProjectRecovery.materialize_into_project(
             project,
             snapshot,
             project.owner_id,
             %{},
             localization_scope: :active
           ) do
        {:ok, %{project: materialized_project}} -> materialized_project
        {:error, reason} -> Storyarn.Repo.rollback(reason)
      end
    end)
  end

  defp materialized_graph_counts(project_id) do
    %{
      sheets: length(Storyarn.Sheets.list_all_sheets(project_id)),
      scenes: length(Storyarn.Scenes.list_scenes(project_id)),
      flows: length(Storyarn.Flows.list_flows(project_id))
    }
  end
end
