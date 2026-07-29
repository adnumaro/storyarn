defmodule Storyarn.Flows.NodeLabelTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.NodeLabel

  describe "for_node/1" do
    test "prefers technical id, then label, then cleaned text, then the node type" do
      node = %{
        type: "dialogue",
        data: %{
          "technical_id" => "opening_line",
          "label" => "Opening",
          "text" => "<p>Hello <strong>world</strong></p>"
        }
      }

      assert NodeLabel.for_node(node) == "opening_line"
      assert NodeLabel.for_node(put_in(node, [:data, "technical_id"], "")) == "Opening"

      text_node =
        node
        |> put_in([:data, "technical_id"], nil)
        |> put_in([:data, "label"], "")

      assert NodeLabel.for_node(text_node) == "Hello world"

      type_node = put_in(text_node, [:data, "text"], " ")
      assert NodeLabel.for_node(type_node) == "Dialogue"
    end

    test "strips HTML and truncates text labels to 48 characters" do
      text = String.duplicate("x", 60)
      node = %{type: "dialogue", data: %{"text" => "<p>#{text}</p>"}}

      assert NodeLabel.for_node(node) == String.duplicate("x", 48)
    end

    test "uses the type when data is nil" do
      assert NodeLabel.for_node(%{type: "decision_point", data: nil}) == "Decision point"
    end

    test "uses a generic fallback when no node type is available" do
      assert NodeLabel.for_node(%{}) == "Node"
      assert NodeLabel.for_node(nil) == "Node"
    end
  end

  describe "specific_for_node/1" do
    test "returns nil for nil data or a value without node data" do
      assert NodeLabel.specific_for_node(%{data: nil}) == nil
      assert NodeLabel.specific_for_node(%{}) == nil
    end
  end
end
