defmodule Storyarn.Flows.PlayerTextTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  defp variable(value), do: %{value: value}

  defp render({:value, ref, value}), do: "<resolved ref=#{ref}>#{Flows.format_player_value(value)}</resolved>"
  defp render({:missing, ref}), do: "<missing ref=#{ref}/>"

  describe "interpolate_player_rich_text/3" do
    test "resolves authored brace references" do
      variables = %{"hero.health" => variable(75)}

      assert Flows.interpolate_player_rich_text(
               "Health: {hero.health}",
               variables,
               &render/1
             ) == "Health: <resolved ref=hero.health>75</resolved>"
    end

    test "resolves Tiptap variable spans regardless of attribute order" do
      variables = %{"hero.health" => variable(50)}

      assert Flows.interpolate_player_rich_text(
               ~s(<span class="variable-ref" data-ref="hero.health">$hero.health</span>),
               variables,
               &render/1
             ) == "<resolved ref=hero.health>50</resolved>"

      assert Flows.interpolate_player_rich_text(
               ~s(<span data-ref="hero.health" class="variable-ref">$hero.health</span>),
               variables,
               &render/1
             ) == "<resolved ref=hero.health>50</resolved>"
    end

    test "does not interpret ordinary spans that merely carry data-ref" do
      html = ~s(<span class="mention" data-ref="hero.health">health</span>)

      assert Flows.interpolate_player_rich_text(html, %{}, &render/1) == html
    end

    test "reports unresolved references to the rendering adapter" do
      assert Flows.interpolate_player_rich_text(
               "{hero.missing}",
               %{},
               &render/1
             ) == "<missing ref=hero.missing/>"
    end
  end

  describe "interpolate_player_response_text/2" do
    test "resolves namespaced response references" do
      variables = %{"hero.health" => variable(90)}

      assert Flows.interpolate_player_response_text(
               "Health: $hero.health points",
               variables
             ) == "Health: 90 points"
    end

    test "marks unresolved references without interpreting currency" do
      assert Flows.interpolate_player_response_text(
               "Pay $100; health is $hero.health",
               %{}
             ) == "Pay $100; health is [$hero.health]"
    end
  end

  describe "map_player_rich_text_references/2" do
    test "owns brace and variable-span recognition while leaving rendering to the adapter" do
      renderer = fn reference -> "<preview>#{reference}</preview>" end

      assert Flows.map_player_rich_text_references(
               ~s(Value: {hero.health}; <span class="variable-ref" data-ref="world.day">$world.day</span>),
               renderer
             ) == "Value: <preview>hero.health</preview>; <preview>world.day</preview>"
    end

    test "does not reinterpret ordinary spans" do
      html = ~s(<span class="mention" data-ref="hero.health">Hero</span>)
      renderer = fn reference -> "[#{reference}]" end
      assert Flows.map_player_rich_text_references(html, renderer) == html
    end
  end

  describe "format_player_value/1" do
    test "formats evaluator values without HTML concerns" do
      assert Flows.format_player_value(nil) == "nil"
      assert Flows.format_player_value(true) == "true"
      assert Flows.format_player_value(false) == "false"
      assert Flows.format_player_value(["brave", "kind"]) == "brave, kind"
      assert Flows.format_player_value(42) == "42"
      assert Flows.format_player_value("<b>authored value</b>") == "<b>authored value</b>"
    end
  end
end
