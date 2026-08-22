defmodule Storyarn.Flows.WordCountTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  test "counts all player-facing dialogue fields for either JSON key shape" do
    atom_data = %{
      text: "Dialogue words",
      stage_directions: "Walks away",
      menu_text: "Choose wisely",
      responses: [%{text: "Response words"}]
    }

    string_data = %{
      "text" => "Dialogue words",
      "stage_directions" => "Walks away",
      "menu_text" => "Choose wisely",
      "responses" => [%{"text" => "Response words"}]
    }

    assert Flows.node_word_count("dialogue", atom_data) == 8
    assert Flows.node_word_count("dialogue", string_data) == 8
  end

  test "counts exit labels and ignores non-localizable node types" do
    assert Flows.node_word_count("exit", %{"label" => "Leave now"}) == 2
    assert Flows.node_word_count("instruction", %{"text" => "not dialogue"}) == 0
    assert Flows.node_word_count("dialogue", nil) == 0
  end
end
