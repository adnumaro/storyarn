defmodule StoryarnWeb.SheetLive.Helpers.HealthHelpersTest do
  @moduledoc """
  The sheet health popover and the sheets dashboard are read by Spanish authors
  too.

  Every label they render is built on the server, so a hardcoded English word is a
  word Gettext can never reach — and `String.capitalize` on a DB enum is the worst
  version of that, because it LOOKS like a label: the dashboard said
  "Multi select #42" for the block the editor, one click away, calls
  "Selección múltiple".
  """

  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.HealthChecker
  alias StoryarnWeb.SheetLive.Helpers.HealthHelpers

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")
    :ok
  end

  describe "the popover labels an unlabelled block in the reader's language" do
    setup do
      Gettext.put_locale(Storyarn.Gettext, "es")
      on_exit(fn -> Gettext.put_locale(Storyarn.Gettext, "en") end)
      :ok
    end

    test "by its type, not by a capitalized column value" do
      payload = payload([finding(:empty_select_options, 42, "multi_select")], blocks: [block(42, "multi_select", nil)])

      assert label(payload, :warningItems) == "Selección múltiple n.º 42"
    end

    test "down to the row and column of a table cell" do
      finding =
        HealthChecker.finding(:required_table_cell_empty, %{
          sheet_id: 1,
          block_id: 7,
          block_type: "table",
          row_id: 3,
          column_id: 4
        })

      payload =
        payload([finding],
          blocks: [block(7, "table", "   ")],
          table_data: %{7 => %{rows: [%{id: 3, name: nil}], columns: [%{id: 4, name: ""}]}}
        )

      assert label(payload, :warningItems) == "Tabla n.º 7 · Fila n.º 3 · Columna n.º 4"
    end

    test "and names a nameless sheet with the sheet word" do
      payload = payload([HealthChecker.finding(:missing_sheet_shortcut, %{sheet_id: 1})], sheet: %{name: "   "})

      assert label(payload, :errorItems) == "Ficha"
    end

    test "while an author's own label is never translated" do
      payload =
        payload([finding(:empty_select_options, 42, "multi_select")], blocks: [block(42, "multi_select", "Rasgos")])

      assert label(payload, :warningItems) == "Rasgos"
    end

    # The dashboard builds its own flat label and enters through this function.
    # Naming the same block two ways is how the two surfaces came to disagree.
    test "and the dashboard names it identically, through the same function" do
      assert HealthHelpers.block_identifier("multi_select", 42) == "Selección múltiple n.º 42"
    end
  end

  describe "the same labels in English" do
    # The counterpart of the Spanish block: identical output in both locales would
    # mean the catalog is never consulted and every assertion above passes on a
    # hardcoded string.
    test "differ from the Spanish ones" do
      assert HealthHelpers.block_identifier("multi_select", 42) == "Multi Select #42"
      assert HealthHelpers.row_identifier(3) == "Row #3"
      assert HealthHelpers.column_identifier(4) == "Column #4"
    end
  end

  describe "the block-type vocabulary is total" do
    test "every type a block can have has a word" do
      for type <- Block.types() do
        label = HealthHelpers.block_type_label(type)
        assert is_binary(label) and label != ""
      end
    end

    test "a finding with no block type still has one" do
      assert HealthHelpers.block_type_label(nil) == "Block"
    end

    test "an unknown type raises instead of leaking the enum" do
      assert_raise FunctionClauseError, fn -> HealthHelpers.block_type_label("sequence") end
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp finding(code, block_id, block_type) do
    HealthChecker.finding(code, %{sheet_id: 1, block_id: block_id, block_type: block_type})
  end

  defp block(id, type, label), do: %{id: id, type: type, config: %{"label" => label}}

  defp payload(findings, opts) do
    HealthHelpers.health_payload(
      findings,
      Keyword.get(opts, :sheet, %{name: "Héroe"}),
      Keyword.get(opts, :blocks, []),
      Keyword.get(opts, :table_data, %{})
    )
  end

  defp label(payload, key) do
    [item] = Map.fetch!(payload, key)
    item.label
  end
end
