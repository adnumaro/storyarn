defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilderTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Localization
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.SnapshotContentHealth

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Hero Sheet"})
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    flow = flow_fixture(project, %{name: "Main Flow"})
    _node = node_fixture(flow, %{type: "dialogue"})
    _scene = scene_fixture(project, %{name: "World Map"})

    %{user: user, project: project, flow: flow}
  end

  test "builds the complete active portable project graph", %{project: project} do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert snapshot["format_version"] == 2
    assert snapshot["project"]["name"] == project.name
    assert snapshot["entity_counts"]["sheets"] == length(snapshot["sheets"])
    assert snapshot["entity_counts"]["flows"] == length(snapshot["flows"])
    assert snapshot["entity_counts"]["scenes"] == length(snapshot["scenes"])
    assert snapshot["entity_counts"]["sheets"] >= 1
    assert snapshot["entity_counts"]["flows"] >= 1
    assert snapshot["entity_counts"]["scenes"] >= 1

    for collection <- ~w(sheets flows scenes), entry <- snapshot[collection] do
      assert is_integer(entry["id"])
      assert is_map(entry["snapshot"])
      assert is_binary(entry["snapshot"]["name"])
    end

    assert Enum.sort(Map.keys(snapshot["tree"])) == ~w(flows scenes sheets)
  end

  test "canonical capture exposes the complete issue inventory before the bounded report", %{
    project: project
  } do
    assert {:ok, {raw_snapshot, issues}} =
             Repo.transaction(fn ->
               ProjectSnapshotBuilder.build_canonical_snapshot_with_issues_in_transaction(
                 project.id,
                 localization_scope: :active
               )
             end)

    assert is_list(issues)
    refute Map.has_key?(raw_snapshot, "content_health")

    assert {:ok, wrapped_snapshot} =
             Repo.transaction(fn ->
               ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project.id,
                 localization_scope: :active
               )
             end)

    assert Map.delete(wrapped_snapshot, "content_health") == raw_snapshot
    assert wrapped_snapshot["content_health"] == SnapshotContentHealth.build(issues)
  end

  test "builds an empty portable project graph", %{user: user} do
    empty_project = project_fixture(user)
    snapshot = ProjectSnapshotBuilder.build_snapshot(empty_project.id)

    assert snapshot["entity_counts"] == %{
             "sheets" => 0,
             "flows" => 0,
             "scenes" => 0,
             "languages" => 0,
             "localized_texts" => 0,
             "glossary_entries" => 0
           }

    assert snapshot["sheets"] == []
    assert snapshot["flows"] == []
    assert snapshot["scenes"] == []
    assert snapshot["localization"] == %{"languages" => [], "texts" => [], "glossary" => []}
  end

  test "includes localization data and glossary entries", %{project: project, flow: flow} do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
    text = Localization.get_text_by_source("flow_node", node.id, "text", "es")
    assert {:ok, text} = Localization.update_text(text, %{translated_text: "Hola"})

    Localization.create_glossary_entry(project, %{
      source_term: "Dragon",
      source_locale: "en",
      target_term: "Dragón",
      target_locale: "es"
    })

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert snapshot["entity_counts"]["languages"] == 2
    assert snapshot["entity_counts"]["localized_texts"] == length(snapshot["localization"]["texts"])
    assert snapshot["entity_counts"]["glossary_entries"] == 1

    text_snapshot =
      Enum.find(snapshot["localization"]["texts"], fn entry ->
        entry["source_type"] == text.source_type and entry["source_id"] == text.source_id and
          entry["source_field"] == text.source_field
      end)

    assert text_snapshot["translated_text"] == "Hola"
    assert text_snapshot["content_role"] == "dialogue"
    assert text_snapshot["vo_eligible"]

    assert [%{"source_term" => "Dragon", "target_term" => "Dragón"}] =
             snapshot["localization"]["glossary"]
  end

  test "includes verified localization voice asset metadata", %{project: project, user: user, flow: flow} do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    voice_asset = uploaded_asset(project, user, "localized-line.mp3", "voice-line", "audio/mpeg")

    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Localized voice line", "responses" => []}})
    text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

    assert {:ok, text} =
             Localization.update_text(text, %{
               translated_text: "Línea de voz localizada",
               vo_asset_id: voice_asset.id,
               vo_status: "recorded"
             })

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    asset_id = to_string(voice_asset.id)

    assert snapshot["asset_blob_hashes"][asset_id] == voice_asset.blob_hash
    assert snapshot["asset_metadata"][asset_id]["blob_key"] =~ "projects/#{project.id}/blobs/"

    assert Enum.any?(snapshot["localization"]["texts"], fn entry ->
             entry["source_type"] == text.source_type and entry["source_id"] == text.source_id and
               entry["source_field"] == text.source_field and entry["vo_asset_id"] == voice_asset.id
           end)
  end

  test "rejects localization voice assets owned by another project", %{project: project, user: user, flow: flow} do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    foreign_project = project_fixture(user)
    foreign_voice = uploaded_asset(foreign_project, user, "foreign-line.mp3", "foreign voice", "audio/mpeg")
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Corrupt foreign voice", "responses" => []}})
    text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

    text
    |> Ecto.Changeset.change(vo_asset_id: foreign_voice.id, vo_status: "recorded")
    |> Repo.update!()

    assert_raise ArgumentError, ~r/owned by another project/, fn ->
      ProjectSnapshotBuilder.build_snapshot(project.id)
    end
  end

  test "rejects localization voice assets whose recovery blob is unavailable", %{
    project: project,
    user: user,
    flow: flow
  } do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    voice_asset = uploaded_asset(project, user, "missing-line.mp3", "missing voice", "audio/mpeg")
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Missing voice", "responses" => []}})
    text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

    assert {:ok, _text} =
             Localization.update_text(text, %{vo_asset_id: voice_asset.id, vo_status: "recorded"})

    delete_storage_blob(
      BlobStore.blob_key(
        project.id,
        voice_asset.blob_hash,
        BlobStore.ext_from_content_type(voice_asset.content_type)
      )
    )

    assert_raise ArgumentError, ~r/asset_blob_unavailable/, fn ->
      ProjectSnapshotBuilder.build_snapshot(project.id)
    end
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type)))
    end)

    asset
  end
end
