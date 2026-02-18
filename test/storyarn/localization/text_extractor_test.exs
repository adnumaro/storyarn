defmodule Storyarn.Localization.TextExtractorTest do
  use Storyarn.DataCase

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)

    # Configure source + target languages
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    %{user: user, project: project}
  end

  # =============================================================================
  # Flow Node Extraction
  # =============================================================================

  describe "flow node extraction" do
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
  end
end
