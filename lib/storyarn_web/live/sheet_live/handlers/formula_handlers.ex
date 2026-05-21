defmodule StoryarnWeb.SheetLive.Handlers.FormulaHandlers do
  @moduledoc """
  Handles formula sidebar events for the sheet editor.

  The formula sidebar is a mini-editor with its own state: which cell is being
  edited, the current expression/bindings, and paginated variable search results.
  This module encapsulates all that state management.
  """

  import Phoenix.Component, only: [assign: 3]
  import StoryarnWeb.SheetLive.Helpers.FormulaHelpers

  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  def handle_open(params, socket, _helpers) do
    row_id = MapUtils.parse_int(params["row-id"])
    block_id = MapUtils.parse_int(params["block-id"])
    slug = params["column-slug"]

    table_entry = Map.get(socket.assigns.table_data, block_id, %{columns: [], rows: []})
    enriched_row = Enum.find(table_entry.rows, &(&1.id == row_id))
    row = enriched_row || Sheets.get_table_row!(row_id)

    all_blocks =
      socket.assigns.blocks ++
        Enum.flat_map(socket.assigns.inherited_groups, fn g -> g.blocks end)

    table_name =
      case Enum.find(all_blocks, &(&1.id == block_id)) do
        nil -> nil
        block -> block.config["label"]
      end

    column_name =
      case Enum.find(table_entry.columns, &(&1.slug == slug)) do
        nil -> nil
        col -> col.name
      end

    {:noreply,
     assign(socket, :formula_editing, %{
       row_id: row_id,
       column_slug: slug,
       block_id: block_id,
       value: row.cells[slug],
       columns: table_entry.columns,
       table_name: table_name,
       row_name: row.name,
       column_name: column_name
     })}
  end

  def handle_close(_params, socket, _helpers) do
    {:noreply, assign(socket, :formula_editing, nil)}
  end

  def handle_save_expression(%{"value" => expression} = params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      current = socket.assigns.formula_editing
      current_bindings = if is_map(current.value), do: current.value["bindings"] || %{}, else: %{}
      raw_bindings = encode_bindings(current_bindings)

      {:noreply, updated_socket} =
        helpers.handle_formula_cell.(
          %{
            "row-id" => params["row-id"],
            "column-slug" => params["column-slug"],
            "expression" => expression,
            "bindings" => raw_bindings
          },
          socket,
          helpers.table_helpers.(socket)
        )

      {:noreply,
       updated_socket
       |> refresh_formula_editing()
       |> helpers.broadcast.(:block_updated)}
    end)
  end

  def handle_save_binding(params, socket, helpers) do
    %{"binding_value" => value, "symbol" => symbol} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      current = socket.assigns.formula_editing
      current_value = current.value || %{}

      expression = if is_map(current_value), do: current_value["expression"] || "", else: ""
      current_bindings = if is_map(current_value), do: current_value["bindings"] || %{}, else: %{}

      binding = parse_binding_value(value)

      updated_bindings =
        if binding,
          do: Map.put(current_bindings, symbol, binding),
          else: Map.delete(current_bindings, symbol)

      raw_bindings = encode_bindings(updated_bindings)

      {:noreply, updated_socket} =
        helpers.handle_formula_cell.(
          %{
            "row-id" => params["row-id"],
            "column-slug" => params["column-slug"],
            "expression" => expression,
            "bindings" => raw_bindings
          },
          socket,
          helpers.table_helpers.(socket)
        )

      {:noreply,
       updated_socket
       |> refresh_formula_editing()
       |> helpers.broadcast.(:block_updated)}
    end)
  end

  def handle_search(%{"query" => query}, socket, _helpers) do
    {results, has_more} = search_binding_variables(socket.assigns.project.id, query, 0)

    {:noreply,
     socket
     |> assign(:formula_search_results, results)
     |> assign(:formula_search_query, query)
     |> assign(:formula_search_offset, formula_page_size())
     |> assign(:formula_search_has_more, has_more)}
  end

  def handle_load_more(_params, socket, _helpers) do
    query = socket.assigns.formula_search_query
    offset = MapUtils.ensure_integer(socket.assigns.formula_search_offset)

    {new_results, has_more} =
      search_binding_variables(socket.assigns.project.id, query, offset)

    merged = merge_search_results(socket.assigns.formula_search_results, new_results)
    next_offset = offset + formula_page_size()

    {:noreply,
     socket
     |> assign(:formula_search_results, merged)
     |> assign(:formula_search_offset, next_offset)
     |> assign(:formula_search_has_more, has_more)}
  end
end
