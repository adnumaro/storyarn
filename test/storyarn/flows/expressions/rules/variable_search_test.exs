defmodule Storyarn.Flows.VariableSearchTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  describe "search_variable_suggestions/2" do
    test "owns reference construction, matching and editor projection" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        },
        %{
          sheet_shortcut: "npc.merchant",
          sheet_name: "NPC Merchant",
          variable_name: "gold",
          block_type: "number"
        }
      ]

      assert Flows.search_variable_suggestions(variables, "JAIME") == [
               %{
                 ref: "mc.jaime.health",
                 sheet_name: "MC Jaime",
                 variable_name: "health",
                 block_type: "number"
               }
             ]

      assert [%{ref: "npc.merchant.gold"}] =
               Flows.search_variable_suggestions(variables, "merchant")
    end

    test "retains catalog order and bounds the suggestion contract to twenty items" do
      variables =
        for index <- 1..25 do
          %{
            sheet_shortcut: "hero",
            sheet_name: "Hero",
            variable_name: "stat_#{index}",
            block_type: "number"
          }
        end

      suggestions = Flows.search_variable_suggestions(variables, "stat")

      assert length(suggestions) == 20
      assert hd(suggestions).ref == "hero.stat_1"
      assert List.last(suggestions).ref == "hero.stat_20"
    end
  end

  describe "search_variable_options/2" do
    test "normalizes string-key descriptors and projects the canonical reference" do
      variables = [
        %{
          "sheet_shortcut" => "hero",
          "variable_name" => "health",
          "label" => "Hero health"
        },
        %{"ref" => "world.weather", "label" => "World weather"}
      ]

      assert Flows.search_variable_options(variables, query: " hero ", limit: 10) ==
               {[%{id: "hero.health", name: "Hero health"}], false}
    end

    test "matches picker queries case-insensitively" do
      variables = [
        %{sheet_shortcut: "mc", variable_name: "health", label: "MC Health"},
        %{sheet_shortcut: "world", variable_name: "weather", label: "World weather"}
      ]

      assert Flows.search_variable_options(variables, query: " HEALTH ") ==
               {[%{id: "mc.health", name: "MC Health"}], false}
    end

    test "keeps a matching selected option visible outside the page and reports more results" do
      variables = [
        %{sheet_shortcut: "hero", variable_name: "health", label: "Hero health"},
        %{sheet_shortcut: "hero", variable_name: "mana", label: "Hero mana"},
        %{sheet_shortcut: "hero", variable_name: "armor", label: "Hero armor"}
      ]

      assert Flows.search_variable_options(variables,
               query: "hero",
               limit: 1,
               selected_id: "hero.armor"
             ) ==
               {[
                  %{id: "hero.armor", name: "Hero armor"},
                  %{id: "hero.health", name: "Hero health"}
                ], true}
    end

    test "does not force a selected option into a search it does not match" do
      variables = [
        %{sheet_shortcut: "hero", variable_name: "health", label: "Hero health"},
        %{sheet_shortcut: "world", variable_name: "weather", label: "World weather"}
      ]

      assert Flows.search_variable_options(variables,
               query: "world",
               selected_id: "hero.health"
             ) ==
               {[%{id: "world.weather", name: "World weather"}], false}
    end
  end
end
