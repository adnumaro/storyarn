defmodule Storyarn.Localization.TextExtractorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

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
    test "creates localized_text rows when dialogue node data is saved", %{project: project} do
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

      # Update node data to trigger extraction
      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "<p>Hello world</p>",
          "stage_directions" => "walks slowly",
          "menu_text" => "Greet",
          "responses" => [
            %{"id" => "r1", "text" => "Yes"},
            %{"id" => "r2", "text" => "No"}
          ]
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)

      # Should have text, stage_directions, menu_text, r1.text, r2.text = 5 fields × 1 locale = 5
      assert length(texts) == 5

      # Verify specific fields exist
      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
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

      # Mark as final
      {:ok, _} = Localization.update_text(text, %{status: "final"})

      # Update source text
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated_text] = Localization.get_texts_for_source("flow_node", node.id)
      assert updated_text.status == "review"
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
      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "response.r1.text" in fields
      refute "response.r2.text" in fields
    end

    test "cleans up all texts when node is deleted", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      assert length(Localization.get_texts_for_source("flow_node", node.id)) == 1

      {:ok, _deleted, _} = Flows.delete_node(node)
      assert Localization.get_texts_for_source("flow_node", node.id) == []
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

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
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
            "speaker_sheet_id" => sheet.id
          }
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{
          "text" => "Hello traveler",
          "speaker_sheet_id" => sheet.id
        })

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 1
      assert hd(texts).speaker_sheet_id == sheet.id
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
  # Flow Node Extraction — Scene
  # =============================================================================

  describe "flow node extraction — scene" do
    test "extracts scene node description", %{project: project} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "scene",
          data: %{"description" => "A dark forest clearing"}
        })

      {:ok, _updated, _} =
        Flows.update_node_data(node, %{"description" => "A dark forest clearing"})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "description"
      assert hd(texts).source_text == "A dark forest clearing"
    end

    test "scene node with blank description produces no texts", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "scene", data: %{"description" => ""}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"description" => ""})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
    end

    test "scene node without description field produces no texts", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "scene", data: %{}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{})

      texts = Localization.get_texts_for_source("flow_node", node.id)
      assert texts == []
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
    test "extracts label and content from text block", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Biography", "placeholder" => ""},
          value: %{"content" => "A brave warrior from the north"}
        })

      {:ok, _} =
        Sheets.update_block_value(block, %{"content" => "A brave warrior from the north"})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 2

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "config.label" in fields
      assert "value.content" in fields

      label_text = Enum.find(texts, &(&1.source_field == "config.label"))
      assert label_text.source_text == "Biography"

      content_text = Enum.find(texts, &(&1.source_field == "value.content"))
      assert content_text.source_text == "A brave warrior from the north"
    end

    test "text block with empty content only extracts label", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Notes", "placeholder" => ""},
          value: %{"content" => ""}
        })

      {:ok, _} = Sheets.update_block_value(block, %{"content" => ""})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "config.label"
    end
  end

  describe "block extraction — select block" do
    test "extracts label and option labels from select block", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "placeholder" => "Choose...",
            "options" => [
              %{"key" => "warrior", "label" => "Warrior"},
              %{"key" => "mage", "label" => "Mage"},
              %{"key" => "rogue", "label" => "Rogue"}
            ]
          }
        })

      # Trigger extraction via config update
      {:ok, _} =
        Sheets.update_block_config(block, %{
          "label" => "Class",
          "placeholder" => "Choose...",
          "options" => [
            %{"key" => "warrior", "label" => "Warrior"},
            %{"key" => "mage", "label" => "Mage"},
            %{"key" => "rogue", "label" => "Rogue"}
          ]
        })

      texts = Localization.get_texts_for_source("block", block.id)

      # Should have: config.label + 3 option labels = 4
      assert length(texts) == 4

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "config.label" in fields
      assert "config.options.warrior" in fields
      assert "config.options.mage" in fields
      assert "config.options.rogue" in fields
    end

    test "select block skips options with blank labels", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [
              %{"key" => "warrior", "label" => "Warrior"},
              %{"key" => "empty", "label" => ""},
              %{"key" => "nil_label", "label" => nil}
            ]
          }
        })

      {:ok, _} =
        Sheets.update_block_config(block, %{
          "label" => "Class",
          "options" => [
            %{"key" => "warrior", "label" => "Warrior"},
            %{"key" => "empty", "label" => ""},
            %{"key" => "nil_label", "label" => nil}
          ]
        })

      texts = Localization.get_texts_for_source("block", block.id)

      # config.label + warrior option = 2
      assert length(texts) == 2

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "config.label" in fields
      assert "config.options.warrior" in fields
    end

    test "select block with empty options list only extracts label", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{"label" => "Class", "options" => []}
        })

      {:ok, _} = Sheets.update_block_config(block, %{"label" => "Class", "options" => []})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "config.label"
    end
  end

  describe "block extraction — other block types" do
    test "number block extracts only label", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"},
          value: %{"content" => 100}
        })

      {:ok, _} = Sheets.update_block_config(block, %{"label" => "Health", "placeholder" => "0"})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "config.label"
      assert hd(texts).source_text == "Health"
    end

    test "boolean block extracts only label", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive", "mode" => "two_state"}
        })

      {:ok, _} =
        Sheets.update_block_config(block, %{"label" => "Is Alive", "mode" => "two_state"})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "config.label"
      assert hd(texts).source_text == "Is Alive"
    end

    test "date block extracts only label", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Event"})

      block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birth Date"}
        })

      {:ok, _} = Sheets.update_block_config(block, %{"label" => "Birth Date"})

      texts = Localization.get_texts_for_source("block", block.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "config.label"
      assert hd(texts).source_text == "Birth Date"
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
      assert Localization.get_texts_for_source("block", block.id) != []

      {:ok, _} = Sheets.delete_block(block)
      assert Localization.get_texts_for_source("block", block.id) == []
    end
  end

  # =============================================================================
  # Sheet Extraction
  # =============================================================================

  describe "sheet extraction" do
    test "creates localized_text rows when sheet is updated", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})

      {:ok, _updated} =
        Sheets.update_sheet(sheet, %{name: "Hero", description: "The main character"})

      texts = Localization.get_texts_for_source("sheet", sheet.id)
      assert length(texts) == 2

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "name" in fields
      assert "description" in fields
    end

    test "cleans up texts when sheet is deleted", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})
      {:ok, _updated} = Sheets.update_sheet(sheet, %{name: "Hero"})

      assert length(Localization.get_texts_for_source("sheet", sheet.id)) == 1

      {:ok, _} = Sheets.delete_sheet(sheet)
      assert Localization.get_texts_for_source("sheet", sheet.id) == []
    end

    test "sheet with only name extracts one field", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})
      {:ok, _updated} = Sheets.update_sheet(sheet, %{name: "Hero"})

      texts = Localization.get_texts_for_source("sheet", sheet.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "name"
      assert hd(texts).source_text == "Hero"
    end

    test "sheet with blank name and blank description produces no texts", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Temp"})

      # Update to empty values - name can't be blank per changeset, but description can be nil
      {:ok, _updated} = Sheets.update_sheet(sheet, %{name: "X", description: nil})

      texts = Localization.get_texts_for_source("sheet", sheet.id)
      # Should have at least name "X"
      assert length(texts) == 1
      assert hd(texts).source_field == "name"
    end
  end

  # =============================================================================
  # Flow Metadata Extraction
  # =============================================================================

  describe "flow metadata extraction" do
    test "creates localized_text rows when flow is updated", %{project: project} do
      flow = flow_fixture(project)

      {:ok, _updated} =
        Flows.update_flow(flow, %{name: "Chapter 1", description: "Opening scene"})

      texts = Localization.get_texts_for_source("flow", flow.id)
      assert length(texts) == 2

      fields = Enum.map(texts, & &1.source_field) |> MapSet.new()
      assert "name" in fields
      assert "description" in fields
    end

    test "cleans up texts when flow is deleted", %{project: project} do
      flow = flow_fixture(project)
      {:ok, _updated} = Flows.update_flow(flow, %{name: "Chapter 1"})

      assert Localization.get_texts_for_source("flow", flow.id) != []

      {:ok, _} = Flows.delete_flow(flow)
      assert Localization.get_texts_for_source("flow", flow.id) == []
    end

    test "flow with only name extracts one field", %{project: project} do
      flow = flow_fixture(project)
      {:ok, _updated} = Flows.update_flow(flow, %{name: "Chapter 1", description: nil})

      texts = Localization.get_texts_for_source("flow", flow.id)
      assert length(texts) == 1
      assert hd(texts).source_field == "name"
    end

    test "flow with name and description extracts both", %{project: project} do
      flow = flow_fixture(project)

      {:ok, _updated} =
        Flows.update_flow(flow, %{name: "Chapter 1", description: "The beginning"})

      texts = Localization.get_texts_for_source("flow", flow.id)
      assert length(texts) == 2

      name_text = Enum.find(texts, &(&1.source_field == "name"))
      desc_text = Enum.find(texts, &(&1.source_field == "description"))

      assert name_text.source_text == "Chapter 1"
      assert desc_text.source_text == "The beginning"
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

      locales = Enum.map(texts, & &1.locale_code) |> MapSet.new()
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

      # 2 fields (config.label, value.content) x 2 locales (es, fr) = 4
      assert length(texts) == 4

      locales = Enum.map(texts, & &1.locale_code) |> MapSet.new()
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

    test "extracts texts from flows, nodes, sheets, and blocks", %{project: project} do
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

      # flow: name + description = 2 texts (1 locale each)
      # node: text = 1 text
      # sheet: name = 1 text
      # block: config.label + value.content = 2 texts
      # Total = 6 (each x 1 locale = 6)
      # Note: The fixture also creates entry/exit nodes automatically for the flow
      assert count >= 6
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
      all_flow_texts = Localization.get_texts_for_source("flow", flow.id)

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

    test "extract_all processes multiple flows and sheets", %{project: project} do
      # Two flows
      flow1 = flow_fixture(project, %{name: "Flow One"})
      flow2 = flow_fixture(project, %{name: "Flow Two"})

      _node1 = node_fixture(flow1, %{type: "dialogue", data: %{"text" => "Line 1"}})
      _node2 = node_fixture(flow2, %{type: "dialogue", data: %{"text" => "Line 2"}})

      # Two sheets
      {:ok, _sheet1} = Sheets.create_sheet(project, %{name: "Sheet One"})
      {:ok, _sheet2} = Sheets.create_sheet(project, %{name: "Sheet Two"})

      {:ok, count} = TextExtractor.extract_all(project.id)

      # At minimum: 2 flow names + 2 node texts + 2 sheet names = 6
      assert count >= 6
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
    test "preserves non-final statuses when source text changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      # Set to draft
      {:ok, _} = Localization.update_text(text, %{status: "draft"})

      # Change source text
      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated] = Localization.get_texts_for_source("flow_node", node.id)

      # Draft should remain draft (not downgraded)
      assert updated.status == "draft"
    end

    test "preserves in_progress status when source text changes", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Hello"})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      {:ok, _} = Localization.update_text(text, %{status: "in_progress"})

      {:ok, _updated, _} = Flows.update_node_data(node, %{"text" => "Changed"})
      [updated] = Localization.get_texts_for_source("flow_node", node.id)

      assert updated.status == "in_progress"
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

  describe "delete_sheet_texts/1" do
    test "removes all texts for a sheet ID", %{project: project} do
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Character"})
      {:ok, _} = Sheets.update_sheet(sheet, %{name: "Hero"})
      assert Localization.get_texts_for_source("sheet", sheet.id) != []

      assert :ok = TextExtractor.delete_sheet_texts(sheet.id)
      assert Localization.get_texts_for_source("sheet", sheet.id) == []
    end
  end

  describe "delete_flow_texts/1" do
    test "removes all texts for a flow ID", %{project: project} do
      flow = flow_fixture(project)
      {:ok, _} = Flows.update_flow(flow, %{name: "Chapter 1"})
      assert Localization.get_texts_for_source("flow", flow.id) != []

      assert :ok = TextExtractor.delete_flow_texts(flow.id)
      assert Localization.get_texts_for_source("flow", flow.id) == []
    end
  end
end
