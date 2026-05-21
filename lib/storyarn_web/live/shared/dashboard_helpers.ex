defmodule StoryarnWeb.Live.Shared.DashboardHelpers do
  @moduledoc """
  Shared backend helpers for Vue-backed project dashboards.

  This module intentionally contains no HEEx components. It only keeps the
  table sorting, pagination, and reload coordination used by dashboard
  LiveViews.
  """

  import Phoenix.Component, only: [assign: 3]

  @default_per_page 25

  def paginate(rows, page, per_page \\ @default_per_page) do
    total = length(rows)
    total_pages = max(ceil(total / per_page), 1)
    page = clamp(page, 1, total_pages)

    page_rows =
      rows
      |> Enum.drop((page - 1) * per_page)
      |> Enum.take(per_page)

    {page_rows, total_pages}
  end

  def sort_table(data, sort_by, sort_dir, columns) do
    sorter = Map.get(columns, sort_by, &String.downcase(&1.name))
    Enum.sort_by(data, sorter, sort_dir)
  end

  def handle_sort(socket, column, all_data_key, page_data_key, sort_columns) do
    {sort_by, sort_dir} = toggle_sort(column, socket.assigns.sort_by, socket.assigns.sort_dir)
    sorted = sort_table(socket.assigns[all_data_key], sort_by, sort_dir, sort_columns)
    {page_rows, total_pages} = paginate(sorted, 1)

    socket
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(all_data_key, sorted)
    |> assign(page_data_key, page_rows)
    |> assign(:page, 1)
    |> assign(:total_pages, total_pages)
  end

  def handle_page(socket, page, all_data_key, page_data_key) do
    page = parse_page(page)
    {page_rows, total_pages} = paginate(socket.assigns[all_data_key], page)

    socket
    |> assign(page_data_key, page_rows)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
  end

  def reload_dashboard(socket, entity_key, all_data_key, page_data_key, issues_key, reload_fn) do
    socket
    |> reload_fn.()
    |> assign(:dashboard_stats, nil)
    |> assign(all_data_key, [])
    |> assign(page_data_key, [])
    |> assign(issues_key, [])
    |> assign(:page, 1)
    |> assign(:total_pages, 1)
    |> then(fn socket ->
      if socket.assigns[entity_key] != [], do: send(self(), :load_dashboard_data)
      socket
    end)
  end

  defp toggle_sort(column, current_by, current_dir) do
    if column == current_by do
      {column, if(current_dir == :asc, do: :desc, else: :asc)}
    else
      {column, :asc}
    end
  end

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> page
      _ -> 1
    end
  end

  defp parse_page(page) when is_integer(page), do: page
  defp parse_page(_page), do: 1

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val
end
