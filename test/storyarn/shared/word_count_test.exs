defmodule Storyarn.Shared.WordCountTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.WordCount

  describe "for_node_data/2" do
    test "counts atom-keyed dialogue data and nested responses" do
      data = %{
        text: "Dialogue words",
        stage_directions: "Walks away",
        menu_text: "Choose wisely",
        responses: [%{id: "response-1", text: "Response words"}]
      }

      assert WordCount.for_node_data("dialogue", data) == 8
    end

    test "counts an atom-keyed exit label" do
      assert WordCount.for_node_data("exit", %{label: "Leave now"}) == 2
    end

    test "counts string-keyed persisted node data" do
      data = %{
        "text" => "Dialogue words",
        "stage_directions" => "Walks away",
        "menu_text" => "Choose wisely",
        "responses" => [%{"id" => "response-1", "text" => "Response words"}]
      }

      assert WordCount.for_node_data("dialogue", data) == 8
      assert WordCount.for_node_data("exit", %{"label" => "Leave now"}) == 2
    end
  end

  describe "for_block_value/1" do
    test "counts atom-keyed rich text content" do
      assert WordCount.for_block_value(%{content: "<p>Runtime text value</p>"}) == 3
    end
  end

  describe "for_block/2" do
    test "counts string-keyed persisted block values" do
      assert WordCount.for_block("rich_text", %{"content" => "<p>Persisted text value</p>"}) == 3
      assert WordCount.for_block("number", %{"content" => "Ignored text"}) == 0
    end
  end
end
