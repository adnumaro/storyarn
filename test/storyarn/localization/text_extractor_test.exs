defmodule Storyarn.Localization.TextExtractorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)

    # Configure source + target languages
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    %{user: user, project: project}
  end

  # =============================================================================
  # Flow Node Extraction — Dialogue
  # =============================================================================

  describe "flow node extraction — dialogue" do
    test "creates localized_text rows as soon as a dialogue node is created", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello world</p>",
            "stage_directions" => "walks slowly",
            "menu_text" => "Greet",
            "responses" => [
              %{"id" => "r1", "text" => "Yes"},
              %{"id" => "r2", "text" => "No"}
            ]
          }
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)

      # Should have text, stage_directions, menu_text, r1.text, r2.text = 5 fields × 1 locale = 5
      assert length(texts) == 5

      # Verify specific fields exist
      fields = MapSet.new(texts, & &1.source_field)
      assert "text" in fields
      assert "stage_directions" in fields
      assert "menu_text" in fields
      assert "response.r1.text" in fields
      assert "response.r2.text" in fields

      # Verify all are for Spanish locale
      assert Enum.all?(texts, &(&1.locale_code == "es"))

      # Verify word counts
      text_entry = Enum.find(texts, &(&1.source_field == "text"))
      assert text_entry.source_text == "<p>Hello world</p>"
      assert text_entry.word_count == 2
      assert text_entry.content_role == "dialogue"
      assert text_entry.vo_eligible

      stage_entry = Enum.find(texts, &(&1.source_field == "stage_directions"))
      assert stage_entry.content_role == "stage_direction"
      refute stage_entry.vo_eligible

      response_entry = Enum.find(texts, &(&1.source_field == "response.r1.text"))
      assert response_entry.content_role == "response"
      assert response_entry.vo_eligible
    end

    test "does not create rows when no target languages configured", %{user: user} do
      # Create a project WITHOUT target languages
      project2 = project_fixture(user)
      flow = flow_fixture(project2)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "updates source_text when content changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      # First save
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert text.source_text == "Hello"

      # Update with new text
      {:ok, updated, _} = Flows.update_node_data(node, %{"text" => "Goodbye"})
      [updated_text] = Localization.get_texts_for_source("flow_node", updated.id)
      assert updated_text.source_text == "Goodbye"
    end

    test "downgrades final status to review when source changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      # First save
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      # Translate and mark as final
      {:ok, _} =
        Localization.update_text(text, %{
          translated_text: "Hola",
          status: "final",
          vo_status: "approved"
        })

      # Update source text
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated_text] = Localization.get_texts_for_source("flow_node", node.id)
      assert updated_text.status == "review"
      assert updated_text.vo_status == "needed"
    end

    test "invalidates recorded voice when the translated line changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, voiced} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 status: "final",
                 vo_status: "approved"
               })

      assert {:ok, updated} =
               Localization.update_text(voiced, %{
                 translated_text: "Buenas",
                 status: "draft",
                 vo_status: "approved"
               })

      assert updated.vo_status == "needed"
    end

    test "cleans up removed response fields", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Yes"},
              %{"id" => "r2", "text" => "No"}
            ]
          }
        })

      # First save with 2 responses
      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "Hello",
          "responses" => [
            %{"id" => "r1", "text" => "Yes"},
            %{"id" => "r2", "text" => "No"}
          ]
        })

      assert length(Localization.get_texts_for_source("flow_node", node.id)) == 3

      # Remove one response
      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "Hello",
          "responses" => [%{"id" => "r1", "text" => "Yes"}]
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 2
      fields = MapSet.new(texts, & &1.source_field)
      assert "response.r1.text" in fields
      refute "response.r2.text" in fields
    end

    test "cleans up all texts when node is deleted", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, translated} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 status: "final",
                 translator_notes: "Keep the greeting concise"
               })

      {:ok, _deleted, _} = Flows.delete_node(node)
      assert Localization.get_texts_for_source("flow_node", node.id) == []

      assert [archived] =
               Localization.list_all_texts(project.id,
                 source_type: "flow_node",
                 locale_code: "es"
               )

      assert archived.id == translated.id
      assert archived.archived_at
      assert archived.archive_reason == "source_deleted"

      assert {:ok, _restored} = Flows.restore_node(flow.id, node.id)

      assert [restored] = Localization.get_texts_for_source("flow_node", node.id)
      assert restored.id == translated.id
      assert restored.source_text == "Hello"
      assert restored.translated_text == "Hola"
      assert restored.status == "final"
      assert restored.translator_notes == "Keep the greeting concise"
      assert restored.archived_at == nil
    end

    test "skips blank and whitespace-only text fields", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "",
            "stage_directions" => "   ",
            "menu_text" => nil
          }
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "",
          "stage_directions" => "   ",
          "menu_text" => nil
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "skips responses with blank text", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => ""},
              %{"id" => "r2", "text" => "  "},
              %{"id" => "r3", "text" => nil},
              %{"id" => "r4", "text" => "Actual response"}
            ]
          }
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "Hello",
          "responses" => [
            %{"id" => "r1", "text" => ""},
            %{"id" => "r2", "text" => "  "},
            %{"id" => "r3", "text" => nil},
            %{"id" => "r4", "text" => "Actual response"}
          ]
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 2

      fields = MapSet.new(texts, & &1.source_field)
      assert "text" in fields
      assert "response.r4.text" in fields
    end

    test "extracts dialogue with only text field (no stage_directions, menu_text, responses)", %{
      project: project
    } do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Solo text"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Solo text"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "text"
      assert hd(texts).source_text == "Solo text"
    end

    test "stores speaker_sheet_id for dialogue nodes", %{project: project} do
      flow = flow_fixture(project)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "NPC"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello traveler",
            "speaker_sheet_id" => sheet.id,
            "responses" => [%{"id" => "ask_name", "text" => "Who are you?"}]
          }
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "Hello traveler",
          "speaker_sheet_id" => sheet.id,
          "responses" => [%{"id" => "ask_name", "text" => "Who are you?"}]
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 2
      assert Enum.all?(texts, &(&1.speaker_sheet_id == sheet.id))
    end

    test "handles dialogue with empty responses list", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "No choices",
            "responses" => []
          }
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "No choices",
          "responses" => []
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "text"
    end

    test "word count strips HTML tags before counting", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>One <strong>two</strong> three</p>"}
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{"text" => "<p>One <strong>two</strong> three</p>"})

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert text.word_count == 3
    end
  end

  # =============================================================================
  # Flow Node Extraction — Exit
  # =============================================================================

  describe "flow node extraction — exit" do
    test "extracts exit node label", %{project: project} do
      flow = flow_fixture(project)

      # Flow creates entry/exit nodes automatically, find the exit
      loaded_flow = Flows.get_flow(project.id, flow.id)
      exit_node = Enum.find(loaded_flow.nodes, &(&1.type == "exit"))

      {:ok, _updated, _} = Flows.update_node_data(exit_node, %{"label" => "Success"})

      texts = Localization.get_texts_for_source("flow_node", exit_node.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "label"
      assert hd(texts).source_text == "Success"
    end

    test "exit node with blank label produces no texts", %{project: project} do
      flow = flow_fixture(project)
      loaded_flow = Flows.get_flow(project.id, flow.id)
      exit_node = Enum.find(loaded_flow.nodes, &(&1.type == "exit"))

      {:ok, _updated, _} = Flows.update_node_data(exit_node, %{"label" => ""})

      texts = Localization.get_texts_for_source("flow_node", exit_node.id)
      assert texts == []
    end
  end

  # =============================================================================
  # Flow Node Extraction — Non-extractable Types
  # =============================================================================

  describe "flow node extraction — non-extractable types" do
    test "hub node produces no texts", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{type: "hub", data: %{"hub_id" => "hub-1", "label" => "Central Hub"}})

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{"hub_id" => "hub-1", "label" => "Central Hub"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "condition node produces no texts", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{"expression" => "health > 50"}
        })

      {:ok, _updated, _} = Flows.update_node_data(node, %{"expression" => "health > 50"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "instruction node produces no texts", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{"assignments" => [%{"variable" => "health", "value" => "100"}]}
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "assignments" => [%{"variable" => "health", "value" => "100"}]
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "jump node produces no texts", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => nil}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"target_hub_id" => nil})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "subflow node produces no texts", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "subflow", data: %{"flow_id" => nil}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"flow_id" => nil})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end
  end

  # =============================================================================
  # Block Extraction
  # =============================================================================

  describe "block extraction — text block" do
    test "extracts only the exported runtime value from a text block", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Biography", "placeholder" => ""},
          value: %{"content" => "A brave warrior from the north"}
        })

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1

      fields = MapSet.new(texts, & &1.source_field)
      assert "value.content" in fields

      content_text = Enum.find(texts, &(&1.source_field == "value.content"))
      assert content_text.source_text == "A brave warrior from the north"
      assert content_text.content_role == "runtime_value"
      refute content_text.vo_eligible
    end

    test "tracks only non-constant text blocks emitted as runtime variables", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "biography",
          is_constant: true,
          value: %{"content" => "A hidden editor value"}
        })

      assert Localization.get_texts_for_source("block", block.id) == []

      assert {:ok, runtime_block} = Sheets.update_block(block, %{is_constant: false})
      assert [%{source_text: "A hidden editor value"}] = Localization.get_texts_for_source("block", block.id)

      assert {:ok, _constant_block} = Sheets.update_block(runtime_block, %{is_constant: true})
      assert Localization.get_texts_for_source("block", block.id) == []

      assert [%{archive_reason: "source_not_runtime"}] =
               Localization.list_all_texts(project.id, source_type: "block")
    end

    test "text block with empty content produces no runtime strings", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Notes", "placeholder" => ""},
          value: %{"content" => ""}
        })

      {:ok, _} = Sheets.update_block_value(block, %{"content" => ""})

      texts = Localization.get_texts_for_source("block", block.id)
      assert texts == []
    end
  end

  describe "block extraction — editor-only configuration" do
    test "does not extract labels, placeholders, or select options", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "placeholder" => "Choose...",
            "options" => [%{"key" => "warrior", "label" => "Warrior"}]
          }
        })

      {:ok, _} = Sheets.update_block_config(block, block.config)

      assert Localization.get_texts_for_source("block", block.id) == []
    end
  end

  describe "block deletion cleanup" do
    test "cleans up texts when block is deleted", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Bio", "placeholder" => ""},
          value: %{"content" => "A hero"}
        })

      # Trigger extraction
      {:ok, _} = Sheets.update_block_value(block, %{"content" => "A hero"})
      [text] = Localization.get_texts_for_source("block", block.id)

      assert {:ok, translated} =
               Localization.update_text(text, %{
                 translated_text: "Un héroe",
                 status: "final",
                 reviewer_notes: "Approved terminology"
               })

      {:ok, deleted_block} = Sheets.delete_block(block)
      assert Localization.get_texts_for_source("block", block.id) == []

      assert {:ok, _restored} = Sheets.restore_block(deleted_block)

      assert [restored] = Localization.get_texts_for_source("block", block.id)
      assert restored.id == translated.id
      assert restored.source_text == "A hero"
      assert restored.translated_text == "Un héroe"
      assert restored.status == "final"
      assert restored.reviewer_notes == "Approved terminology"
    end

    test "permanently deleting an archived block purges its localization history", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "A hero"}
        })

      assert Localization.get_texts_for_source("block", block.id) != []
      assert {:ok, deleted} = Sheets.delete_block(block)
      assert Localization.list_all_texts(project.id, source_type: "block") != []

      assert {:ok, _deleted} = Sheets.permanently_delete_block(deleted)
      assert Localization.list_all_texts(project.id, source_type: "block") == []
    end
  end

  describe "tree lifecycle cleanup" do
    test "deleting a flow tree removes all runtime strings and restoring the root re-extracts its nodes", %{
      project: project
    } do
      parent = flow_fixture(project, %{name: "Parent"})
      child = flow_fixture(project, %{name: "Child", parent_id: parent.id})
      parent_node = node_fixture(parent, %{type: "dialogue", data: %{"text" => "Parent line"}})
      child_node = node_fixture(child, %{type: "dialogue", data: %{"text" => "Child line"}})

      assert Localization.get_texts_for_source("flow_node", parent_node.id) != []
      assert Localization.get_texts_for_source("flow_node", child_node.id) != []

      assert {:ok, deleted_parent} = Flows.delete_flow(parent)
      assert Localization.get_texts_for_source("flow_node", parent_node.id) == []
      assert Localization.get_texts_for_source("flow_node", child_node.id) == []

      assert {:ok, _restored_parent} = Flows.restore_flow(deleted_parent)
      assert Localization.get_texts_for_source("flow_node", parent_node.id) != []
      assert Localization.get_texts_for_source("flow_node", child_node.id) == []
    end

    test "deleting a sheet tree removes all runtime strings and restoring the root re-extracts its blocks", %{
      project: project
    } do
      parent = sheet_fixture(project, %{name: "Parent"})
      child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      parent_block = block_fixture(parent, %{type: "text", value: %{"content" => "Parent value"}})
      child_block = block_fixture(child, %{type: "text", value: %{"content" => "Child value"}})

      assert Localization.get_texts_for_source("block", parent_block.id) != []
      assert Localization.get_texts_for_source("block", child_block.id) != []

      assert {:ok, deleted_parent} = Sheets.delete_sheet(parent)
      assert Localization.get_texts_for_source("block", parent_block.id) == []
      assert Localization.get_texts_for_source("block", child_block.id) == []

      assert {:ok, _restored_parent} = Sheets.restore_sheet(deleted_parent)
      assert Localization.get_texts_for_source("block", parent_block.id) != []
      assert Localization.get_texts_for_source("block", child_block.id) == []
    end
  end

  # =============================================================================
  # Sheet Extraction
  # =============================================================================

  describe "sheet actor names and editor metadata exclusion" do
    test "extracts sheet names but not descriptions", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      {:ok, _updated} =
        Sheets.update_sheet(sheet, %{name: "Hero", description: "The main character"})

      assert [%{source_field: "name", source_text: "Hero", content_role: "speaker_name"}] =
               Localization.get_texts_for_source("sheet", sheet.id)
    end

    test "does not extract flow names or descriptions", %{project: project} do
      flow = flow_fixture(project)

      {:ok, _updated} =
        Flows.update_flow(flow, %{name: "Chapter 1", description: "Opening scene"})

      assert Localization.get_texts_for_source("flow", flow.id) == []
    end

    test "does not extract scenes", %{project: project} do
      scene = scene_fixture(project, %{name: "World Map", description: "Main hub"})
      assert Localization.get_texts_for_source("scene", scene.id) == []
    end

    test "does not extract screenplays or screenplay elements", %{project: project} do
      screenplay = screenplay_fixture(project, %{name: "Hidden Draft"})
      element = element_fixture(screenplay, %{type: "dialogue", content: "Not runtime content"})

      assert {:ok, _count} = Localization.extract_all(project.id)
      assert Localization.get_texts_for_source("screenplay", screenplay.id) == []
      assert Localization.get_texts_for_source("screenplay_element", element.id) == []
    end
  end

  # =============================================================================
  # Multi-Language
  # =============================================================================

  describe "multi-language extraction" do
    test "creates rows for all target languages", %{project: project} do
      # Add another target language
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 2

      locales = MapSet.new(texts, & &1.locale_code)
      assert "es" in locales
      assert "fr" in locales
    end

    test "creates rows for all target languages on blocks", %{project: project} do
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name", "placeholder" => ""},
          value: %{"content" => "Arthas"}
        })

      {:ok, _} = Sheets.update_block_value(block, %{"content" => "Arthas"})

      texts = Localization.get_texts_for_source("block", block.id)

      # One exported runtime value x two locales.
      assert length(texts) == 2

      locales = MapSet.new(texts, & &1.locale_code)
      assert "es" in locales
      assert "fr" in locales
    end
  end

  # =============================================================================
  # Bulk Extraction — extract_all
  # =============================================================================

  describe "extract_all/1" do
    test "returns {:ok, 0} when no target languages exist", %{user: user} do
      project_no_langs = project_fixture(user)

      assert {:ok, 0} = TextExtractor.extract_all(project_no_langs.id)
    end

    test "extracts only runtime text from nodes and blocks", %{project: project} do
      # Create a flow with a dialogue node
      flow = flow_fixture(project, %{name: "Main Flow", description: "The main story"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello world"}
        })

      # Create a sheet with a text block
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Hero"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Bio", "placeholder" => ""},
          value: %{"content" => "A brave warrior"}
        })

      {:ok, count} = TextExtractor.extract_all(project.id)

      assert count == 3
    end

    test "is idempotent — running twice does not duplicate entries", %{project: project} do
      flow = flow_fixture(project, %{name: "Chapter", description: "Intro"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello"}
        })

      {:ok, count1} = TextExtractor.extract_all(project.id)
      {:ok, count2} = TextExtractor.extract_all(project.id)

      assert count1 == count2

      # Verify no duplicates in the actual records
      [node] = Enum.filter(Flows.get_flow(project.id, flow.id).nodes, &(&1.type == "dialogue"))
      all_flow_texts = Localization.get_texts_for_source("flow_node", node.id)

      unique_fields =
        all_flow_texts
        |> Enum.map(fn t -> {t.source_field, t.locale_code} end)
        |> Enum.uniq()

      assert length(all_flow_texts) == length(unique_fields)
    end

    test "extract_all with empty project returns {:ok, 0}", %{user: user} do
      empty_project = project_fixture(user)
      _source = source_language_fixture(empty_project, %{locale_code: "en", name: "English"})
      _target = language_fixture(empty_project, %{locale_code: "es", name: "Spanish"})

      {:ok, count} = TextExtractor.extract_all(empty_project.id)
      # Empty project has no flows, sheets, etc.
      assert count == 0
    end

    test "extract_all processes multiple flows and exported sheet actor names", %{project: project} do
      # Two flows
      flow1 = flow_fixture(project, %{name: "Flow One"})
      flow2 = flow_fixture(project, %{name: "Flow Two"})

      _node1 = node_fixture(flow1, %{type: "dialogue", data: %{"text" => "Line 1"}})
      _node2 = node_fixture(flow2, %{type: "dialogue", data: %{"text" => "Line 2"}})

      # Two sheets
      {:ok, _sheet1} = Sheets.create_sheet(project, %{name: "Sheet One"})
      {:ok, _sheet2} = Sheets.create_sheet(project, %{name: "Sheet Two"})

      {:ok, count} = TextExtractor.extract_all(project.id)

      assert count == 4
    end

    test "extract_all removes valid-looking rows whose source no longer exists", %{project: project} do
      orphan_id = System.unique_integer([:positive])

      assert {:ok, _orphan} =
               Localization.create_text(project.id, %{
                 source_type: "flow_node",
                 source_id: orphan_id,
                 source_field: "text",
                 source_text: "Orphaned line",
                 locale_code: "es"
               })

      assert {:ok, 0} = TextExtractor.extract_all(project.id)
      assert Localization.get_texts_for_source("flow_node", orphan_id) == []
    end

    test "bulk reconciliation invalidates voice when source text changed outside normal callbacks", %{
      project: project
    } do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Original line"}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Línea original",
                 status: "final",
                 vo_status: "approved"
               })

      node
      |> Ecto.Changeset.change(data: %{"text" => "Changed outside callback"})
      |> Repo.update!()

      assert {:ok, _count} = TextExtractor.extract_all(project.id)
      [updated] = Localization.get_texts_for_source("flow_node", node.id)
      assert updated.status == "review"
      assert updated.vo_status == "needed"
    end
  end

  # =============================================================================
  # Hash and Word Count
  # =============================================================================

  describe "source text hash" do
    test "hash changes when source text changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text1] = Localization.get_texts_for_source("flow_node", node.id)

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Goodbye"})
      [text2] = Localization.get_texts_for_source("flow_node", node.id)

      assert text1.source_text_hash != text2.source_text_hash
    end

    test "hash remains the same for identical source text", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text1] = Localization.get_texts_for_source("flow_node", node.id)
      hash1 = text1.source_text_hash

      # Update again with same text
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text2] = Localization.get_texts_for_source("flow_node", node.id)
      hash2 = text2.source_text_hash

      assert hash1 == hash2
    end
  end

  describe "word count" do
    test "counts words correctly for plain text", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "one two three four"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "one two three four"})

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert text.word_count == 4
    end

    test "counts words correctly for HTML content", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Hello <em>beautiful</em> world</p><p>Second paragraph</p>"}
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "<p>Hello <em>beautiful</em> world</p><p>Second paragraph</p>"
        })

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert text.word_count == 5
    end

    test "single word has word count of 1", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert text.word_count == 1
    end
  end

  # =============================================================================
  # Status Management
  # =============================================================================

  describe "status management on source change" do
    test "moves translated drafts to review when source text changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      {:ok, _} =
        Localization.update_text(text, %{
          translated_text: "Hola",
          status: "draft"
        })

      # Change source text
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated] = Localization.get_texts_for_source("flow_node", node.id)

      assert updated.status == "review"
      assert Storyarn.Localization.LocalizedText.stale?(updated)
    end

    test "returns untranslated workflow statuses to pending when source text changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      {:ok, _} = Localization.update_text(text, %{status: "in_progress"})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated] = Localization.get_texts_for_source("flow_node", node.id)

      assert updated.status == "pending"
    end
  end

  # =============================================================================
  # Direct TextExtractor function calls (unit-level)
  # =============================================================================

  describe "delete_flow_node_texts/1" do
    test "removes all texts for a node ID", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      assert length(Localization.get_texts_for_source("flow_node", node.id)) == 1

      assert :ok = TextExtractor.delete_flow_node_texts(node.id)
      assert Localization.get_texts_for_source("flow_node", node.id) == []
    end
  end

  describe "delete_block_texts/1" do
    test "removes all texts for a block ID", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Bio", "placeholder" => ""},
          value: %{"content" => "Hero"}
        })

      {:ok, _} = Sheets.update_block_value(block, %{"content" => "Hero"})
      assert Localization.get_texts_for_source("block", block.id) != []

      assert :ok = TextExtractor.delete_block_texts(block.id)
      assert Localization.get_texts_for_source("block", block.id) == []
    end
  end

  describe "delete_block_texts_for_sheets/1" do
    test "removes block texts for a sheet", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          value: %{"content" => "Hero"}
        })

      {:ok, _} = Sheets.update_block_value(block, %{"content" => "Hero"})
      assert Localization.get_texts_for_source("block", block.id) != []

      assert :ok = TextExtractor.delete_block_texts_for_sheets([sheet.id])
      assert Localization.get_texts_for_source("block", block.id) == []
    end
  end

  describe "delete_flow_node_texts_for_flows/1" do
    test "removes all node texts for a flow", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      assert Localization.get_texts_for_source("flow_node", node.id) != []

      assert :ok = TextExtractor.delete_flow_node_texts_for_flows([flow.id])
      assert Localization.get_texts_for_source("flow_node", node.id) == []
    end
  end
end
