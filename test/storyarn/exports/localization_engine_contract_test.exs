defmodule Storyarn.Exports.LocalizationEngineContractTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.SerializerRegistry
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  test "every external catalog key is referenced by the corresponding engine export", %{project: project} do
    sheet = sheet_fixture(project, %{name: "Narrator"})

    block_fixture(sheet, %{
      type: "text",
      variable_name: "motto",
      is_constant: false,
      value: %{"content" => "Never surrender"}
    })

    flow = flow_fixture(project, %{name: "Opening"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Welcome",
          "menu_text" => "Greeting",
          "stage_directions" => "<p>Softly</p>",
          "speaker_sheet_id" => sheet.id,
          "responses" => [%{"id" => "continue", "text" => "Continue"}]
        }
      })

    entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    connection_fixture(flow, entry, dialogue)

    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    project.id
    |> Localization.list_all_texts(locale_code: "es")
    |> Enum.each(fn text ->
      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "ES #{text.source_field}",
                 status: "final"
               })
    end)

    for format <- [:ink, :yarn, :godot, :unreal, :articy] do
      {:ok, opts} =
        ExportOptions.new(%{
          format: format,
          validate_before_export: false,
          localization_policy: :release
        })

      data = DataCollector.collect(project.id, opts)
      {:ok, serializer} = SerializerRegistry.get(format)
      assert {:ok, files} = serializer.serialize(data, opts)

      catalog_keys = catalog_keys(files)
      primary_export = primary_export(files)

      assert catalog_keys != [], "expected #{format} to produce localization rows"

      for key <- catalog_keys do
        assert primary_export =~ key,
               "#{format} catalog key #{inspect(key)} is not referenced by its primary export"
      end
    end
  end

  test "line-oriented formats exclude unsupported metadata from readiness and manifests", %{project: project} do
    sheet = sheet_fixture(project, %{name: "Hero"})

    block_fixture(sheet, %{
      type: "text",
      variable_name: "biography",
      is_constant: false,
      value: %{"content" => "A long story"}
    })

    flow = flow_fixture(project)
    node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    for format <- [:ink, :yarn, :godot] do
      opts = %ExportOptions{format: format}
      data = DataCollector.collect(project.id, opts)

      assert data.localization.strings != []
      assert Enum.all?(data.localization.strings, &(&1.content_role in ["dialogue", "response"]))
    end
  end

  test "rows for non-runtime blocks cannot enter an engine inventory", %{project: project} do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    sheet = sheet_fixture(project)

    block =
      block_fixture(sheet, %{
        type: "text",
        variable_name: "internal_note",
        is_constant: true,
        value: %{"content" => "Editor only"}
      })

    localized_text_fixture(project.id, %{
      source_type: "block",
      source_id: block.id,
      source_field: "value.content",
      source_text: "Editor only",
      locale_code: "es",
      translated_text: "Solo editor",
      status: "final"
    })

    data = DataCollector.collect(project.id, %ExportOptions{format: :unity})

    refute Enum.any?(data.localization.strings, &(&1.source_type == "block" and &1.source_id == block.id))
  end

  test "block runtime keys cannot collide when shortcuts or variables contain separators" do
    refute RuntimeKey.qualified_block_ref!("actor.profile", "name") ==
             RuntimeKey.qualified_block_ref!("actor", "profile.name")

    assert RuntimeKey.qualified_block_ref!("actor.profile", "name") == "actor%2Eprofile.name"
    assert RuntimeKey.qualified_block_ref!("actor", "profile.name") == "actor.profile%2Ename"
  end

  test "only canonical response identifiers can form localization fields" do
    assert SourceContract.field?("flow_node", "response.accept_2.text")

    refute SourceContract.field?("flow_node", "response.bad.id.text")
    refute SourceContract.field?("flow_node", "response.bad id.text")
    refute SourceContract.field?("flow_node", "response..text")
    refute SourceContract.field?("flow_node", "response.#{String.duplicate("a", 101)}.text")
  end

  test "incremental extraction atomically refreshes source state after translator writes", %{project: project} do
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Old source", "responses" => []}})
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    [text] = Localization.get_texts_for_source("flow_node", node.id)
    assert {:ok, finalized} = Localization.update_text(text, %{translated_text: "Traducción", status: "final"})

    updated_node =
      node
      |> FlowNode.data_changeset(%{data: %{"text" => "New source", "responses" => []}})
      |> Repo.update!()

    assert :ok = Localization.extract_flow_node(updated_node)

    [refreshed] = Localization.get_texts_for_source("flow_node", node.id)
    assert refreshed.source_text == "New source"
    assert refreshed.status == "review"
    assert refreshed.translated_text == "Traducción"
    assert refreshed.lock_version > finalized.lock_version
  end

  test "incremental extraction reloads the database instead of trusting a stale caller struct", %{
    project: project
  } do
    flow = flow_fixture(project)
    stale_node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Old source", "responses" => []}})
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    stale_node
    |> FlowNode.data_changeset(%{data: %{"text" => "Current database source", "responses" => []}})
    |> Repo.update!()

    assert :ok = Localization.extract_flow_node(stale_node)

    assert [%{source_text: "Current database source"}] =
             Localization.get_texts_for_source("flow_node", stale_node.id)
  end

  test "markup without runtime-visible text never enters the inventory", %{project: project} do
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "<p><br></p>",
          "menu_text" => "<strong></strong>",
          "stage_directions" => "&nbsp;",
          "responses" => [%{"id" => "empty_response", "text" => "<em></em>"}]
        }
      })

    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    assert Localization.get_texts_for_source("flow_node", node.id) == []
  end

  test "generic node updates keep exit labels in the runtime inventory", %{project: project} do
    flow = flow_fixture(project)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    exit_node = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))

    assert {:ok, updated_exit} = Storyarn.Flows.update_node(exit_node, %{data: %{"label" => "The End"}})

    assert [%{source_field: "label", source_text: "The End"}] =
             Localization.get_texts_for_source("flow_node", updated_exit.id)
  end

  test "dialogue localization ids are unique within a project", %{project: project} do
    first_flow = flow_fixture(project)
    second_flow = flow_fixture(project)

    node_fixture(first_flow, %{
      type: "dialogue",
      data: %{"localization_id" => "shared_dialogue", "text" => "First", "responses" => []}
    })

    assert {:error, changeset} =
             Storyarn.Flows.create_node(second_flow, %{
               type: "dialogue",
               data: %{
                 "localization_id" => "shared_dialogue",
                 "text" => "Second",
                 "responses" => []
               }
             })

    assert "localization_id must be unique within the project" in errors_on(changeset).data
  end

  test "inherited runtime blocks stay empty until authored and then enter the inventory", %{project: project} do
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    first_parent = sheet_fixture(project, %{name: "First Parent"})
    second_parent = sheet_fixture(project, %{name: "Second Parent"})

    block_fixture(first_parent, %{
      type: "text",
      scope: "children",
      variable_name: "first_motto",
      value: %{"content" => "First inherited value"}
    })

    second_source =
      block_fixture(second_parent, %{
        type: "text",
        scope: "children",
        variable_name: "second_motto",
        value: %{"content" => "Second inherited value"}
      })

    assert {:ok, child} =
             Storyarn.Sheets.create_sheet(project, %{name: "Child", parent_id: first_parent.id})

    [first_instance] =
      child.id
      |> Storyarn.Sheets.list_blocks()
      |> Enum.filter(&(&1.inherited_from_block_id != nil))

    assert first_instance.value == %{"content" => ""}
    assert Localization.get_texts_for_source("block", first_instance.id) == []

    assert {:ok, first_instance} =
             Storyarn.Sheets.update_block_value(first_instance, %{"content" => "Child value"})

    assert [%{source_text: "Child value"}] =
             Localization.get_texts_for_source("block", first_instance.id)

    assert {:ok, moved_child} = Storyarn.Sheets.move_sheet_to_position(child, second_parent.id, 0)

    second_instance =
      moved_child.id
      |> Storyarn.Sheets.list_blocks()
      |> Enum.find(&(&1.inherited_from_block_id == second_source.id))

    assert second_instance
    assert second_instance.value == %{"content" => ""}
    assert Localization.get_texts_for_source("block", second_instance.id) == []

    assert {:ok, second_instance} =
             Storyarn.Sheets.update_block_value(second_instance, %{"content" => "Moved child value"})

    assert [%{source_text: "Moved child value"}] =
             Localization.get_texts_for_source("block", second_instance.id)
  end

  test "external catalog keys survive project recovery even though database IDs change", %{
    project: project,
    user: user
  } do
    sheet = sheet_fixture(project, %{name: "Narrator", shortcut: "narrator"})

    block_fixture(sheet, %{
      type: "text",
      variable_name: "motto",
      is_constant: false,
      value: %{"content" => "Never surrender"}
    })

    flow = flow_fixture(project, %{name: "Opening"})

    node_fixture(flow, %{
      type: "dialogue",
      data: %{
        "localization_id" => "opening_welcome",
        "text" => "Welcome",
        "speaker_sheet_id" => sheet.id,
        "responses" => [%{"id" => "continue", "text" => "Continue"}]
      }
    })

    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    project.id
    |> Localization.list_all_texts(locale_code: "es")
    |> Enum.each(fn text ->
      assert {:ok, _text} =
               Localization.update_text(text, %{translated_text: "ES #{text.source_field}", status: "final"})
    end)

    opts = %ExportOptions{format: :unreal, validate_before_export: false, localization_policy: :release}
    original_keys = project.id |> serialize_project(opts) |> catalog_keys()
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, recovered} =
             ProjectRecovery.recover_project(project.workspace_id, snapshot, user.id, name: "Recovered localization keys")

    recovered_keys = recovered.id |> serialize_project(opts) |> catalog_keys()

    [recovered_flow] = Storyarn.Flows.list_flows(recovered.id)
    [recovered_sheet] = Storyarn.Sheets.list_all_sheets(recovered.id)

    assert recovered_flow.id != flow.id
    assert recovered_sheet.id != sheet.id
    assert original_keys != []
    assert recovered_keys == original_keys
  end

  test "native backups and project snapshots retain archived locales", %{project: project} do
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Remember me", "responses" => []}})
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    spanish = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    [text] = Localization.get_texts_for_source("flow_node", node.id)
    assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Recuérdame", status: "final"})
    assert {:ok, archived_language} = Localization.remove_language(spanish)

    data = DataCollector.collect(project.id, %ExportOptions{format: :storyarn})
    archived = Enum.find(data.localization.languages, &(&1.locale_code == "es"))

    assert archived.archived_at == archived_language.archived_at
    assert Enum.any?(data.localization.strings, &(&1.locale_code == "es" and &1.translated_text == "Recuérdame"))

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    snapshot_language = Enum.find(snapshot["localization"]["languages"], &(&1["locale_code"] == "es"))

    assert snapshot_language["archived_at"] == archived_language.archived_at
    assert Enum.any?(snapshot["localization"]["texts"], &(&1["translated_text"] == "Recuérdame"))
  end

  defp catalog_keys(files) do
    files
    |> Enum.filter(fn {filename, _content} -> catalog_file?(filename) end)
    |> Enum.flat_map(fn {_filename, content} ->
      content
      |> String.split("\n", trim: true)
      |> Enum.drop(1)
      |> Enum.map(fn row ->
        row
        |> String.split(",", parts: 2)
        |> List.first()
        |> String.trim(~s("))
      end)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp serialize_project(project_id, opts) do
    data = DataCollector.collect(project_id, opts)
    {:ok, serializer} = SerializerRegistry.get(opts.format)
    {:ok, files} = serializer.serialize(data, opts)
    files
  end

  defp primary_export(files) do
    files
    |> Enum.reject(fn {filename, _content} -> catalog_file?(filename) or filename == "localization-manifest.json" end)
    |> Enum.map_join("\n", &elem(&1, 1))
  end

  defp catalog_file?("translations.csv"), do: true
  defp catalog_file?("localization." <> _rest), do: true
  defp catalog_file?("StringTable." <> _rest), do: true
  defp catalog_file?(_filename), do: false
end
