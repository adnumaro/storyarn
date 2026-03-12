defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilderTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Hero Sheet"})
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    flow = flow_fixture(project, %{name: "Main Flow"})
    _node = node_fixture(flow, %{type: "dialogue"})
    scene = scene_fixture(project, %{name: "World Map"})

    %{user: user, project: project, sheet: sheet, flow: flow, scene: scene}
  end

  describe "build_snapshot/1" do
    test "includes all entity types", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["format_version"] == 1
      assert is_map(snapshot["entity_counts"])
      assert snapshot["entity_counts"]["sheets"] >= 1
      assert snapshot["entity_counts"]["flows"] >= 1
      assert snapshot["entity_counts"]["scenes"] >= 1
      assert is_list(snapshot["sheets"])
      assert is_list(snapshot["flows"])
      assert is_list(snapshot["scenes"])
    end

    test "each entity entry has id and snapshot", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      for entry <- snapshot["sheets"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end

      for entry <- snapshot["flows"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end

      for entry <- snapshot["scenes"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end
    end

    test "entity counts match actual entity lists", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["entity_counts"]["sheets"] == length(snapshot["sheets"])
      assert snapshot["entity_counts"]["flows"] == length(snapshot["flows"])
      assert snapshot["entity_counts"]["scenes"] == length(snapshot["scenes"])
    end

    test "handles empty project", %{user: user} do
      empty_project = project_fixture(user)
      snapshot = ProjectSnapshotBuilder.build_snapshot(empty_project.id)

      assert snapshot["format_version"] == 1
      assert snapshot["entity_counts"]["sheets"] == 0
      assert snapshot["entity_counts"]["flows"] == 0
      assert snapshot["entity_counts"]["scenes"] == 0
      assert snapshot["entity_counts"]["languages"] == 0
      assert snapshot["entity_counts"]["localized_texts"] == 0
      assert snapshot["entity_counts"]["glossary_entries"] == 0
      assert snapshot["sheets"] == []
      assert snapshot["flows"] == []
      assert snapshot["scenes"] == []
      assert snapshot["localization"]["languages"] == []
      assert snapshot["localization"]["texts"] == []
      assert snapshot["localization"]["glossary"] == []
    end
  end

  describe "restore_snapshot/2" do
    test "restores modified entities", %{project: project, sheet: sheet} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Modify an entity
      {:ok, _} = Storyarn.Sheets.update_sheet(sheet, %{name: "Changed Name"})

      # Restore
      assert {:ok, result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
      assert result.restored >= 1

      # Verify restoration
      restored = Storyarn.Sheets.get_sheet(project.id, sheet.id)
      assert restored.name == "Hero Sheet"
    end

    test "skips soft-deleted entities", %{project: project, sheet: sheet} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Soft-delete an entity
      {:ok, _} = Storyarn.Sheets.delete_sheet(sheet)

      # Restore should skip the deleted entity
      assert {:ok, result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
      assert result.skipped >= 1
    end

    test "leaves entities not in snapshot untouched", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Create a new entity after the snapshot
      new_sheet = sheet_fixture(project, %{name: "New After Snapshot"})

      # Restore
      {:ok, _} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      # New entity should still exist and be unmodified
      restored_new = Storyarn.Sheets.get_sheet(project.id, new_sheet.id)
      assert restored_new != nil
      assert restored_new.name == "New After Snapshot"
    end
  end

  describe "localization in snapshot" do
    test "includes localization data", %{project: project} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_text: "Hello",
        translated_text: "Hola"
      })

      Storyarn.Localization.create_glossary_entry(project, %{
        source_term: "Dragon",
        source_locale: "en",
        target_term: "Dragón",
        target_locale: "es"
      })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["entity_counts"]["languages"] == 2
      assert snapshot["entity_counts"]["localized_texts"] == 1
      assert snapshot["entity_counts"]["glossary_entries"] == 1

      assert length(snapshot["localization"]["languages"]) == 2
      assert length(snapshot["localization"]["texts"]) == 1
      assert length(snapshot["localization"]["glossary"]) == 1

      [text] = snapshot["localization"]["texts"]
      assert text["translated_text"] == "Hola"

      [glossary] = snapshot["localization"]["glossary"]
      assert glossary["source_term"] == "Dragon"
      assert glossary["target_term"] == "Dragón"
    end

    test "restores localization data", %{project: project} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_text: "Hello",
        translated_text: "Hola"
      })

      Storyarn.Localization.create_glossary_entry(project, %{
        source_term: "Dragon",
        source_locale: "en",
        target_term: "Dragón",
        target_locale: "es"
      })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Modify localization data
      [text] = Storyarn.Localization.list_texts_for_export(project.id, ["es"])
      Storyarn.Localization.update_text(text, %{translated_text: "Modified"})

      # Restore
      {:ok, _result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      # Verify localization was restored
      languages = Storyarn.Localization.list_languages(project.id)
      assert length(languages) == 2

      [restored_text] = Storyarn.Localization.list_texts_for_export(project.id, ["es"])
      assert restored_text.translated_text == "Hola"

      glossary = Storyarn.Localization.list_glossary_for_export(project.id)
      assert length(glossary) == 1
      assert hd(glossary).target_term == "Dragón"
    end

  end
end
