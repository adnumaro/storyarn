defmodule StoryarnWeb.Live.Shared.PickerSearch do
  @moduledoc """
  Shared bounded search contract for Vue picker components.

  Picker payloads intentionally return only a small page of results plus the
  currently selected item. This keeps LiveVue props and per-keystroke searches
  bounded for projects with large asset/entity lists.
  """

  import Phoenix.LiveView, only: [push_event: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Sheets

  @asset_limit 80
  @entity_limit 100
  @max_limit 100
  @results_event "picker_search_results"

  @type option :: map()

  @spec asset_limit() :: pos_integer()
  def asset_limit, do: @asset_limit

  @spec entity_limit() :: pos_integer()
  def entity_limit, do: @entity_limit

  @spec handle_search(Socket.t(), map()) :: Socket.t()
  def handle_search(socket, params) when is_map(params) do
    project_id = socket.assigns.project.id
    query = string_param(params["query"])
    selected_id = params["selected_id"]

    {results, has_more} =
      case picker_resource(params) do
        {:asset, kind} ->
          asset_options(project_id, kind,
            query: query,
            limit: limit_param(params["limit"], @asset_limit),
            selected_id: selected_id
          )

        {:entity, "sheet"} ->
          sheet_options(project_id,
            query: query,
            limit: limit_param(params["limit"], @entity_limit),
            selected_id: selected_id
          )

        {:entity, "flow"} ->
          flow_options(project_id,
            query: query,
            limit: limit_param(params["limit"], @entity_limit),
            selected_id: selected_id
          )

        {:entity, "variable"} ->
          variable_options(socket.assigns[:project_variables] || [],
            query: query,
            limit: limit_param(params["limit"], @entity_limit),
            selected_id: selected_id
          )

        _ ->
          {[], false}
      end

    push_event(socket, @results_event, %{
      request_id: params["request_id"],
      results: results,
      has_more: has_more
    })
  end

  @spec asset_options(integer(), String.t(), keyword()) :: {[option()], boolean()}
  def asset_options(project_id, kind, opts \\ []) do
    limit = Keyword.get(opts, :limit, @asset_limit)
    query = Keyword.get(opts, :query, "")
    selected_id = Keyword.get(opts, :selected_id)

    list_opts =
      kind
      |> asset_filter_opts()
      |> Keyword.merge(search: query, limit: limit + 1)

    assets = Assets.list_assets(project_id, list_opts)
    {page, has_more} = split_page(assets, limit)

    selected =
      case parse_integer(selected_id) do
        nil -> nil
        id -> Assets.get_asset(project_id, id)
      end

    results =
      page
      |> maybe_include_selected(selected, query, &asset_matches?/2)
      |> Enum.map(&serialize_asset/1)

    {results, has_more}
  end

  @spec sheet_options(integer(), keyword()) :: {[option()], boolean()}
  def sheet_options(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @entity_limit)
    query = Keyword.get(opts, :query, "")
    selected_id = Keyword.get(opts, :selected_id)

    sheets = Sheets.search_sheets(project_id, query, limit: limit + 1)
    {page, has_more} = split_page(sheets, limit)

    selected =
      case parse_integer(selected_id) do
        nil -> nil
        id -> Sheets.get_sheet(project_id, id)
      end

    results =
      page
      |> maybe_include_selected(selected, query, &entity_matches?/2)
      |> Enum.map(&serialize_entity/1)

    {results, has_more}
  end

  @spec flow_options(integer(), keyword()) :: {[option()], boolean()}
  def flow_options(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @entity_limit)
    query = Keyword.get(opts, :query, "")
    selected_id = Keyword.get(opts, :selected_id)

    flows = Flows.search_flows(project_id, query, limit: limit + 1)
    {page, has_more} = split_page(flows, limit)

    selected =
      case parse_integer(selected_id) do
        nil -> nil
        id -> Flows.get_flow(project_id, id)
      end

    results =
      page
      |> maybe_include_selected(selected, query, &entity_matches?/2)
      |> Enum.map(&serialize_entity/1)

    {results, has_more}
  end

  @spec variable_options([map()], keyword()) :: {[option()], boolean()}
  def variable_options(variables, opts \\ []) when is_list(variables) do
    limit = Keyword.get(opts, :limit, @entity_limit)
    query = normalize(Keyword.get(opts, :query, ""))
    selected_id = Keyword.get(opts, :selected_id)

    options = Enum.map(variables, &serialize_variable/1)

    matches =
      if query == "" do
        options
      else
        Enum.filter(options, fn option -> normalize(option.name) =~ query end)
      end

    {page, has_more} = split_page(matches, limit)

    selected =
      Enum.find(options, fn option ->
        selected_id != nil && to_string(option.id) == to_string(selected_id)
      end)

    results = maybe_include_selected(page, selected, Keyword.get(opts, :query, ""), &option_matches?/2)
    {results, has_more}
  end

  @spec initial_asset_options(integer(), String.t(), [term()]) :: [option()]
  def initial_asset_options(project_id, kind, selected_ids) do
    selected_ids = normalize_ids(selected_ids)

    {results, _has_more} =
      asset_options(project_id, kind, query: "", limit: @asset_limit, selected_id: List.first(selected_ids))

    selected_ids
    |> Enum.drop(1)
    |> Enum.reduce(results, fn id, acc ->
      with parsed_id when not is_nil(parsed_id) <- parse_integer(id),
           %Asset{} = asset <- Assets.get_asset(project_id, parsed_id) do
        append_unique(acc, serialize_asset(asset))
      else
        _ -> acc
      end
    end)
  end

  @spec initial_sheet_options(integer(), [term()]) :: [option()]
  def initial_sheet_options(project_id, selected_ids) do
    selected_ids = normalize_ids(selected_ids)

    initial_entity_options(
      fn -> sheet_options(project_id, query: "", limit: @entity_limit, selected_id: List.first(selected_ids)) end,
      selected_ids,
      fn id -> Sheets.get_sheet(project_id, id) end
    )
  end

  @spec initial_flow_options(integer(), [term()]) :: [option()]
  def initial_flow_options(project_id, selected_ids) do
    selected_ids = normalize_ids(selected_ids)

    initial_entity_options(
      fn -> flow_options(project_id, query: "", limit: @entity_limit, selected_id: List.first(selected_ids)) end,
      selected_ids,
      fn id -> Flows.get_flow(project_id, id) end
    )
  end

  defp initial_entity_options(fetch_initial, selected_ids, fetch_selected) do
    {results, _has_more} = fetch_initial.()

    selected_ids
    |> Enum.drop(1)
    |> Enum.reduce(results, fn id, acc ->
      with parsed_id when not is_nil(parsed_id) <- parse_integer(id),
           selected when not is_nil(selected) <- fetch_selected.(parsed_id) do
        append_unique(acc, serialize_entity(selected))
      else
        _ -> acc
      end
    end)
  end

  defp picker_resource(params) do
    resource = params["resource"] || params["type"]
    kind = params["kind"] || params["asset_kind"] || params["entity_kind"]

    case {resource, kind} do
      {"asset", kind} when kind in ["image", "audio"] -> {:asset, kind}
      {"entity", kind} when kind in ["sheet", "flow", "variable"] -> {:entity, kind}
      _ -> :error
    end
  end

  defp asset_filter_opts("image"), do: [images_only: true]
  defp asset_filter_opts("audio"), do: [content_type: "audio/"]
  defp asset_filter_opts(_), do: []

  defp split_page(items, limit) do
    limited = Enum.take(items, limit)
    {limited, length(items) > limit}
  end

  defp maybe_include_selected(items, nil, _query, _matches?), do: items

  defp maybe_include_selected(items, selected, query, matches?) do
    cond do
      not matches?.(selected, query) ->
        items

      Enum.any?(items, &same_id?(&1, selected)) ->
        items

      true ->
        [selected | items]
    end
  end

  defp append_unique(items, item) do
    if Enum.any?(items, &same_id?(&1, item)), do: items, else: items ++ [item]
  end

  defp same_id?(%{id: left}, %{id: right}), do: left == right
  defp same_id?(left, right), do: Map.get(left, :id) == Map.get(right, :id)

  defp asset_matches?(%{filename: filename}, query), do: query_matches?(filename, query)
  defp entity_matches?(%{name: name}, query), do: query_matches?(name, query)
  defp option_matches?(%{name: name}, query), do: query_matches?(name, query)

  defp query_matches?(_text, query) when query in [nil, ""], do: true
  defp query_matches?(text, query), do: normalize(text) =~ normalize(query)

  defp serialize_asset(asset) do
    %{
      id: asset.id,
      filename: asset.filename,
      url: Asset.display_url(asset),
      content_type: asset.content_type
    }
  end

  defp serialize_entity(entity) do
    %{
      id: entity.id,
      name: entity.name
    }
  end

  defp serialize_variable(variable) do
    ref =
      variable[:ref] ||
        variable["ref"] ||
        variable_ref(variable)

    label =
      variable[:label] ||
        variable["label"] ||
        ref

    %{id: ref, name: label}
  end

  defp variable_ref(variable) do
    sheet_shortcut = variable[:sheet_shortcut] || variable["sheet_shortcut"]
    variable_name = variable[:variable_name] || variable["variable_name"]

    [sheet_shortcut, variable_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(".")
  end

  defp string_param(value) when is_binary(value), do: String.trim(value)
  defp string_param(_value), do: ""

  defp limit_param(value, default) do
    case parse_integer(value) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @max_limit)
      _ -> default
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp normalize(value) when is_binary(value), do: String.downcase(value)
  defp normalize(value), do: value |> to_string() |> String.downcase()

  defp normalize_ids(ids) when is_list(ids), do: ids
  defp normalize_ids(nil), do: []
  defp normalize_ids(id), do: [id]
end
