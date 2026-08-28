defmodule Storyarn.Flows.RuntimeVariablesUnitTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.RuntimeVariables

  test "owns initial defaults and exact numeric coercion" do
    variables =
      RuntimeVariables.from_descriptors([
        descriptor("hero", "health", "number", %{"content" => "42"}),
        descriptor("hero", "broken", "number", %{"content" => "42px"}),
        descriptor("hero", "name", "text", %{}),
        descriptor("hero", "alive", "boolean", %{})
      ])

    assert variables["hero.health"].value == 42
    assert variables["hero.broken"].value == 0
    assert variables["hero.name"].value == ""
    assert variables["hero.alive"].value == false
  end

  test "recomputes formula descriptors in dependency order" do
    variables =
      RuntimeVariables.from_descriptors([
        descriptor("hero", "stats.row.base", "number", nil, cell_value: "5"),
        descriptor("hero", "stats.row.double", "formula", nil,
          cell_value: %{
            "expression" => "base * 2",
            "bindings" => %{
              "base" => %{"type" => "same_row", "column_slug" => "base"}
            }
          }
        )
      ])

    assert variables["hero.stats.row.base"].value == 5
    assert variables["hero.stats.row.double"].value == 10

    assert variables["hero.stats.row.double"].formula.bindings["base"] ==
             "hero.stats.row.base"
  end

  test "coerces debugger overrides without leaking UI parsing into Web" do
    assert RuntimeVariables.coerce_override("12.5", "number") == {:ok, 12.5}
    assert RuntimeVariables.coerce_override("", "number") == {:ok, 0}

    assert RuntimeVariables.coerce_override("invalid", "number") ==
             {:warning, 0, :invalid_number}

    assert RuntimeVariables.coerce_override("one, two", "multi_select") ==
             {:ok, ["one", "two"]}
  end

  defp descriptor(shortcut, name, type, value, overrides \\ []) do
    Map.merge(
      %{
        sheet_shortcut: shortcut,
        variable_name: name,
        block_type: type,
        block_id: 1,
        value: value,
        constraints: nil,
        options: nil,
        source_type: "sheet",
        source_id: nil
      },
      Map.new(overrides)
    )
  end
end
