defmodule Storyarn.Versioning.SnapshotViewerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotViewer

  describe "serialize_sheet/1" do
    test "produces block list with negative IDs" do
      snapshot = %{
        "blocks" => [
          %{
            "type" => "text",
            "position" => 0,
            "config" => %{"label" => "Name"},
            "value" => %{"content" => "Hello"},
            "variable_name" => "name",
            "is_constant" => false,
            "scope" => "self",
            "required" => true
          },
          %{
            "type" => "number",
            "position" => 1,
            "config" => %{},
            "value" => %{"number" => 42},
            "variable_name" => "health"
          }
        ]
      }

      [first, second] = SnapshotViewer.serialize_sheet(snapshot)

      assert first.id < 0
      assert first.type == "text"
      assert first.value == %{"content" => "Hello"}
      assert first.variable_name == "name"
      assert first.required == true

      assert second.id < 0
      assert second.type == "number"
      assert second.variable_name == "health"
    end

    test "serializes table data" do
      snapshot = %{
        "blocks" => [
          %{
            "type" => "table",
            "config" => %{},
            "value" => %{},
            "table_data" => %{
              "columns" => [%{"name" => "Col1", "slug" => "col1", "type" => "text"}],
              "rows" => [
                %{
                  "name" => "Row1",
                  "slug" => "row1",
                  "cells" => %{"col1" => %{"text" => "hi"}}
                }
              ]
            }
          }
        ]
      }

      [block] = SnapshotViewer.serialize_sheet(snapshot)

      assert length(block.table_columns) == 1
      assert length(block.table_rows) == 1
      assert hd(block.table_columns).name == "Col1"
      assert hd(block.table_rows).cells == %{"col1" => %{"text" => "hi"}}
    end

    test "handles empty sheet" do
      assert SnapshotViewer.serialize_sheet(%{}) == []
    end

    test "applies defaults for missing fields" do
      [block] = SnapshotViewer.serialize_sheet(%{"blocks" => [%{"type" => "text"}]})

      assert block.config == %{}
      assert block.value == %{}
      assert block.is_constant == false
      assert block.scope == "self"
      assert block.required == false
      assert block.table_columns == []
      assert block.table_rows == []
    end
  end
end
