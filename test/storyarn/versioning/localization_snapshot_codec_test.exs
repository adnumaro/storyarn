defmodule Storyarn.Versioning.LocalizationSnapshotCodecTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning.LocalizationSnapshotCodec

  test "inventory advisory locks reject callers outside an explicit transaction" do
    task =
      Task.async(fn ->
        assert_raise ArgumentError, ~r/require an explicit database transaction/, fn ->
          LocalizableWords.lock_inventory!(1)
        end
      end)

    Task.await(task)
  end

  test "include_archived snapshots preserve lifecycle metadata" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

    assert :ok = Localization.delete_flow_node_texts(node.id)

    assert [%{"archived_at" => archived_at, "archive_reason" => "source_deleted"} = row] =
             LocalizationSnapshotCodec.capture(
               project.id,
               %{"flow_node" => [node.id]},
               include_archived: true
             )

    assert archived_at
    assert :ok = LocalizationSnapshotCodec.restore(project.id, [row], %{node: %{node.id => node.id}})

    assert [%{archived_at: restored_at, archive_reason: "source_deleted"}] =
             project.id
             |> Localization.list_all_texts(source_type: "flow_node")
             |> Enum.filter(&(&1.source_id == node.id))

    assert restored_at
  end

  test "restore deduplicates rows that remap onto the same runtime source key" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    source_a = node_fixture(flow, %{type: "dialogue", data: %{"text" => "First", "responses" => []}})
    source_b = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Second", "responses" => []}})
    target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Target", "responses" => []}})

    rows = LocalizationSnapshotCodec.capture(project.id, %{"flow_node" => [source_a.id, source_b.id]})

    assert :ok =
             LocalizationSnapshotCodec.restore(project.id, rows, %{
               node: %{source_a.id => target.id, source_b.id => target.id}
             })

    assert [_one_text] = Localization.get_texts_for_source("flow_node", target.id)
  end

  test "restore increments lock_version and invalidates an editor's stale changeset" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

    [current] = Localization.get_texts_for_source("flow_node", node.id)

    version_two =
      current
      |> LocalizedText.update_changeset(%{
        translated_text: "Editor draft",
        status: "draft"
      })
      |> Repo.update!()

    stale_changeset =
      LocalizedText.update_changeset(version_two, %{
        translated_text: "Stale overwrite",
        status: "draft"
      })

    [row] = LocalizationSnapshotCodec.capture(project.id, %{"flow_node" => [node.id]})
    row = Map.put(row, "translated_text", "Snapshot translation")

    assert :ok =
             LocalizationSnapshotCodec.restore(
               project.id,
               [row],
               %{node: %{node.id => node.id}}
             )

    restored = Repo.get!(LocalizedText, version_two.id)

    assert restored.translated_text == "Snapshot translation"
    assert restored.lock_version == version_two.lock_version + 1

    assert_raise Ecto.StaleEntryError, fn ->
      Repo.update!(stale_changeset)
    end
  end

  test "restore rejects a speaker sheet that is already in trash" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    speaker = sheet_fixture(project, %{name: "Speaker"})
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Hello",
          "responses" => [],
          "speaker_sheet_id" => speaker.id
        }
      })

    [row] = LocalizationSnapshotCodec.capture(project.id, %{"flow_node" => [node.id]})
    assert row["speaker_sheet_id"] == speaker.id
    assert {:ok, _deleted_speaker} = Sheets.delete_sheet(speaker)

    assert {:error, {:localization_reference_not_materializable, "speaker_sheet_id", speaker_id}} =
             LocalizationSnapshotCodec.restore(
               project.id,
               [row],
               %{node: %{node.id => node.id}}
             )

    assert speaker_id == speaker.id
  end

  test "capture excludes rows belonging to archived target languages" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    fr = language_fixture(project, %{locale_code: "fr", name: "French"})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

    assert {:ok, _archived_fr} = Localization.remove_language(fr)

    rows = LocalizationSnapshotCodec.capture(project.id, %{"flow_node" => [node.id]})

    assert [%{"locale_code" => "es"}] = rows
  end

  describe "manifest/1" do
    test "is stable across row order, map order, and a JSON round trip" do
      rows = [
        %{
          "source_type" => "flow_node",
          "source_id" => 42,
          "source_field" => "text",
          "translated_text" => "Hola",
          "last_translated_at" => ~U[2026-07-17 12:00:00Z]
        },
        %{
          "source_type" => "flow_node",
          "source_id" => 42,
          "source_field" => "menu_text",
          "translated_text" => nil,
          "last_translated_at" => nil
        }
      ]

      reordered_rows =
        rows
        |> Enum.reverse()
        |> Enum.map(fn row ->
          row
          |> Map.to_list()
          |> Enum.reverse()
          |> Map.new()
        end)

      json_rows = rows |> Jason.encode!() |> Jason.decode!()

      assert LocalizationSnapshotCodec.manifest(rows) ==
               LocalizationSnapshotCodec.manifest(reordered_rows)

      assert LocalizationSnapshotCodec.manifest(rows) ==
               LocalizationSnapshotCodec.manifest(json_rows)
    end

    test "counts rows and changes the digest when any field changes" do
      rows = [
        %{
          "source_id" => 42,
          "source_field" => "text",
          "translated_text" => "Hola"
        }
      ]

      manifest = LocalizationSnapshotCodec.manifest(rows)
      changed_rows = put_in(rows, [Access.at(0), "translated_text"], "Adiós")
      changed_manifest = LocalizationSnapshotCodec.manifest(changed_rows)

      assert manifest["count"] == 1
      assert byte_size(manifest["sha256"]) == 64
      assert manifest["target_locales"] == []
      refute manifest["sha256"] == changed_manifest["sha256"]
      assert :ok = LocalizationSnapshotCodec.validate_manifest(rows, manifest)

      assert {:error, {:localization_manifest_mismatch, ^manifest, ^changed_manifest}} =
               LocalizationSnapshotCodec.validate_manifest(changed_rows, manifest)
    end

    test "binds the historical target-locale inventory even when there are no rows" do
      no_targets = LocalizationSnapshotCodec.manifest([], [])
      spanish_target = LocalizationSnapshotCodec.manifest([], ["es"])

      assert spanish_target["count"] == 0
      assert spanish_target["target_locales"] == ["es"]
      refute spanish_target["sha256"] == no_targets["sha256"]
      assert :ok = LocalizationSnapshotCodec.validate_manifest([], spanish_target)

      corrupt_manifest = Map.put(spanish_target, "target_locales", [])

      assert {:error, {:localization_manifest_mismatch, ^corrupt_manifest, ^no_targets}} =
               LocalizationSnapshotCodec.validate_manifest(
                 [],
                 corrupt_manifest
               )
    end
  end
end
