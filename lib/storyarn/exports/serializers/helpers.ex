defmodule Storyarn.Exports.Serializers.Helpers do
  @moduledoc """
  Shared utilities for all engine serializers.

  Provides variable collection from sheets, HTML stripping, speaker lookup,
  identifier sanitization, CSV escaping, and flow graph indexing.
  """

  # ---------------------------------------------------------------------------
  # Variable collection from sheets
  # ---------------------------------------------------------------------------

  @doc """
  Extracts all variables from a list of sheets.

  Returns a list of variable maps with:
  - `sheet_shortcut` — the sheet's shortcut (e.g., "mc.jaime")
  - `variable_name` — the block's variable_name (e.g., "health")
  - `full_ref` — combined reference (e.g., "mc.jaime.health")
  - `type` — inferred engine type (number, boolean, string, etc.)
  - `default` — inferred default value
  - `block` — the original block struct
  """
  def collect_variables(sheets) when is_list(sheets) do
    Enum.flat_map(sheets, fn sheet ->
      sheet.blocks
      |> Enum.reject(& &1.is_constant)
      |> Enum.filter(&(is_binary(&1.variable_name) and &1.variable_name != ""))
      |> Enum.map(fn block ->
        %{
          sheet_shortcut: sheet.shortcut,
          variable_name: block.variable_name,
          full_ref: "#{sheet.shortcut}.#{block.variable_name}",
          type: infer_variable_type(block),
          default: infer_default_value(block),
          block: block
        }
      end)
    end)
  end

  def collect_variables(_), do: []

  @doc """
  Maps block type to a generic engine type.
  """
  def infer_variable_type(%{type: "number"}), do: :number
  def infer_variable_type(%{type: "boolean"}), do: :boolean
  def infer_variable_type(%{type: "date"}), do: :string
  def infer_variable_type(%{type: "select"}), do: :string
  def infer_variable_type(%{type: "multi_select"}), do: :string
  def infer_variable_type(%{type: type}) when type in ["text", "rich_text"], do: :string
  def infer_variable_type(_), do: :string

  @doc """
  Extracts a reasonable default value from a block.
  """
  def infer_default_value(%{type: "number", value: %{"number" => val}}) when is_number(val),
    do: val

  def infer_default_value(%{type: "number"}), do: 0

  def infer_default_value(%{type: "boolean", value: %{"boolean" => val}}) when is_boolean(val),
    do: val

  def infer_default_value(%{type: "boolean"}), do: false

  def infer_default_value(%{type: "text", value: %{"text" => val}}) when is_binary(val),
    do: val

  def infer_default_value(%{type: "rich_text", value: %{"rich_text" => val}}) when is_binary(val),
    do: strip_html(val)

  def infer_default_value(%{type: "select", value: %{"select" => val}}) when is_binary(val),
    do: val

  def infer_default_value(%{type: "date", value: %{"date" => val}}) when is_binary(val),
    do: val

  def infer_default_value(_), do: ""

  # ---------------------------------------------------------------------------
  # Speaker lookup
  # ---------------------------------------------------------------------------

  @doc """
  Builds a map from sheet ID to speaker info for dialogue nodes.

  Returns `%{sheet_id => %{name: "Jaime", shortcut: "mc.jaime"}}`.
  """
  def build_speaker_map(sheets) when is_list(sheets) do
    Map.new(sheets, fn sheet ->
      {to_string(sheet.id), %{name: sheet.name, shortcut: sheet.shortcut}}
    end)
  end

  def build_speaker_map(_), do: %{}

  @doc """
  Looks up a speaker name from a dialogue node's data.
  Returns the sheet name or nil.
  """
  def speaker_name(data, speaker_map) do
    case data["speaker_sheet_id"] do
      nil -> nil
      "" -> nil
      id -> get_in(speaker_map, [to_string(id), :name])
    end
  end

  @doc """
  Looks up a speaker shortcut from a dialogue node's data.
  """
  def speaker_shortcut(data, speaker_map) do
    case data["speaker_sheet_id"] do
      nil -> nil
      "" -> nil
      id -> get_in(speaker_map, [to_string(id), :shortcut])
    end
  end

  # ---------------------------------------------------------------------------
  # HTML stripping
  # ---------------------------------------------------------------------------

  @doc """
  Strips HTML tags from text, preserving plain text content.

  Handles Tiptap HTML output (p, em, strong, br, etc.).
  Newlines are inserted between block elements.
  """
  def strip_html(nil), do: ""
  def strip_html(""), do: ""

  def strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<\/p>\s*<p>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # Identifier sanitization
  # ---------------------------------------------------------------------------

  @doc """
  Converts a Storyarn shortcut to an engine-safe identifier.

  Replaces dots and hyphens with underscores.
  """
  def shortcut_to_identifier(nil), do: ""
  def shortcut_to_identifier(""), do: ""

  def shortcut_to_identifier(shortcut) when is_binary(shortcut) do
    String.replace(shortcut, ~r/[.\-]/, "_")
  end

  # ---------------------------------------------------------------------------
  # CSV helpers
  # ---------------------------------------------------------------------------

  @doc """
  Escapes a value for CSV output per RFC 4180.

  Wraps in double quotes if the value contains commas, quotes, or newlines.
  Doubles any existing double quotes.
  """
  def escape_csv_field(nil), do: ""
  def escape_csv_field(value) when is_number(value), do: to_string(value)
  def escape_csv_field(true), do: "true"
  def escape_csv_field(false), do: "false"

  def escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      escaped = String.replace(value, "\"", "\"\"")
      "\"#{escaped}\""
    else
      value
    end
  end

  @doc """
  Builds a CSV string from a list of rows (each row is a list of values).
  """
  def build_csv(headers, rows) do
    header_line = Enum.map_join(headers, ",", &escape_csv_field/1)

    row_lines =
      Enum.map(rows, fn row ->
        Enum.map_join(row, ",", &escape_csv_field/1)
      end)

    [header_line | row_lines]
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  # ---------------------------------------------------------------------------
  # Flow graph indexing
  # ---------------------------------------------------------------------------

  @doc """
  Builds a node lookup map from a flow's nodes.

  Returns `%{node_id => node}` for O(1) access.
  """
  def node_index(flow) do
    Map.new(flow.nodes, fn node -> {node.id, node} end)
  end

  @doc """
  Builds a connection graph (adjacency list) from a flow.

  Returns `%{source_node_id => [{target_node_id, source_pin, connection}]}`.
  """
  def connection_graph(flow) do
    flow.connections
    |> Enum.group_by(& &1.source_node_id)
    |> Map.new(fn {source_id, conns} ->
      targets =
        conns
        |> Enum.sort_by(& &1.source_pin)
        |> Enum.map(fn conn ->
          {conn.target_node_id, conn.source_pin, conn}
        end)

      {source_id, targets}
    end)
  end

  @doc """
  Finds the entry node of a flow.
  """
  def find_entry_node(flow) do
    Enum.find(flow.nodes, &(&1.type == "entry"))
  end

  @doc """
  Gets ordered outgoing targets for a node from the connection graph.
  """
  def outgoing_targets(node_id, conn_graph) do
    Map.get(conn_graph, node_id, [])
  end

  # ---------------------------------------------------------------------------
  # Dialogue data extraction
  # ---------------------------------------------------------------------------

  @doc """
  Extracts dialogue text from a node's data, stripping HTML.
  """
  def dialogue_text(data) do
    strip_html(data["text"] || "")
  end

  @doc """
  Extracts responses from a dialogue node's data.
  Returns a list of response maps with parsed instructions.
  """
  def dialogue_responses(data) do
    (data["responses"] || [])
    |> Enum.map(fn resp ->
      Map.put(resp, "instruction_assignments", parse_instruction_json(resp["instruction"]))
    end)
  end

  defp parse_instruction_json(nil), do: []
  defp parse_instruction_json(""), do: []

  defp parse_instruction_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _ -> []
    end
  end

  defp parse_instruction_json(_), do: []

  @doc """
  Extracts condition data from a condition node, or from inline condition field.
  Handles both JSON strings and maps.
  """
  def extract_condition(nil), do: nil
  def extract_condition(""), do: nil

  def extract_condition(%{"logic" => _} = condition), do: condition

  def extract_condition(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"logic" => _} = condition} -> condition
      _ -> nil
    end
  end

  def extract_condition(_), do: nil

  @doc """
  Extracts instruction assignments from an instruction node's data.
  """
  def extract_assignments(data) do
    data["assignments"] || []
  end

  # ---------------------------------------------------------------------------
  # Default value formatting
  # ---------------------------------------------------------------------------

  @doc """
  Formats a variable default for Ink/Yarn VAR declarations.
  """
  def format_var_declaration_value(%{type: :number, default: val}) when is_number(val),
    do: to_string(val)

  def format_var_declaration_value(%{type: :boolean, default: val}) when is_boolean(val),
    do: to_string(val)

  def format_var_declaration_value(%{type: :string, default: val})
      when is_binary(val) and val != "",
      do: ~s("#{String.replace(val, "\"", "\\\"")}")

  def format_var_declaration_value(%{type: :number}), do: "0"
  def format_var_declaration_value(%{type: :boolean}), do: "false"
  def format_var_declaration_value(_), do: ~s("")
end
