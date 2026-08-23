defmodule Storyarn.Sheets.Versioning.SnapshotViewer do
  @moduledoc """
  Converts raw Sheet snapshot maps into the read-only shape consumed by the
  legacy Sheet comparison viewer.
  """

  @spec serialize_sheet(map()) :: [map()]
  def serialize_sheet(snapshot) do
    snapshot
    |> Map.get("blocks", [])
    |> Enum.with_index()
    |> Enum.map(&serialize_block/1)
  end

  defp serialize_block({block, index}) do
    block_id = -(index + 1)
    table_data = serialize_table_data(block["table_data"])

    %{
      id: block_id,
      type: block["type"],
      position: block["position"] || index,
      config: block["config"] || %{},
      value: block["value"] || %{},
      is_constant: block["is_constant"] || false,
      variable_name: block["variable_name"],
      scope: block["scope"] || "self",
      required: block["required"] || false,
      table_columns: table_data[:columns] || [],
      table_rows: table_data[:rows] || [],
      inherited_from_block_id: nil,
      detached: nil,
      reference_target: nil
    }
  end

  defp serialize_table_data(nil), do: %{columns: [], rows: []}

  defp serialize_table_data(table_data) do
    columns =
      table_data
      |> Map.get("columns", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_table_column/1)

    rows =
      table_data
      |> Map.get("rows", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_table_row/1)

    %{columns: columns, rows: rows}
  end

  defp serialize_table_column({column, index}) do
    %{
      id: -(index + 1),
      name: column["name"],
      slug: column["slug"],
      type: column["type"],
      is_constant: column["is_constant"] || false,
      required: column["required"] || false,
      position: column["position"] || index,
      config: column["config"] || %{}
    }
  end

  defp serialize_table_row({row, index}) do
    %{
      id: -(index + 1),
      name: row["name"],
      slug: row["slug"],
      position: row["position"] || index,
      cells: row["cells"] || %{}
    }
  end
end
