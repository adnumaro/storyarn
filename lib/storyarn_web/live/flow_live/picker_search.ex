defmodule StoryarnWeb.FlowLive.PickerSearch do
  @moduledoc """
  Flow-editor picker adapter.

  The Flow Web boundary consumes only `Storyarn.Flows` read contracts. It owns
  the small browser-facing serialization layer, including private media URLs,
  so the shared Scene/Sheet picker utility cannot become a transitive domain
  bridge back into Flows.
  """

  alias Storyarn.Flows
  alias StoryarnWeb.PrivateMedia

  @asset_limit 80
  @entity_limit 100
  @max_limit 100

  @type option :: map()

  @spec asset_limit() :: pos_integer()
  def asset_limit, do: @asset_limit

  @spec entity_limit() :: pos_integer()
  def entity_limit, do: @entity_limit

  @spec asset_options(integer(), String.t(), keyword()) :: {[option()], boolean()}
  def asset_options(project_id, kind, opts \\ []) do
    opts = normalize_limit(opts, @asset_limit)
    {assets, has_more} = Flows.search_asset_options(project_id, kind, opts)
    {Enum.map(assets, &serialize_asset/1), has_more}
  end

  @spec initial_asset_options(integer(), String.t(), [term()]) :: [option()]
  def initial_asset_options(project_id, kind, selected_ids) do
    project_id
    |> Flows.initial_asset_options(kind, normalize_ids(selected_ids))
    |> Enum.map(&serialize_asset/1)
  end

  @spec flow_options(integer(), keyword()) :: {[option()], boolean()}
  def flow_options(project_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @entity_limit) |> bounded_limit(@entity_limit)
    query = opts |> Keyword.get(:query, "") |> normalize_query()
    selected_id = opts |> Keyword.get(:selected_id) |> parse_integer()

    flows = Flows.search_flows(project_id, query, limit: limit + 1)
    page = Enum.take(flows, limit)
    has_more = length(flows) > limit
    selected = selected_id && Flows.get_flow(project_id, selected_id)

    results =
      page
      |> maybe_include_selected(selected, query, &entity_matches?/2)
      |> Enum.map(&serialize_entity/1)

    {results, has_more}
  end

  @spec variable_options([map()], keyword()) :: {[option()], boolean()}
  def variable_options(variables, opts \\ []) when is_list(variables) do
    Flows.search_variable_options(variables, opts)
  end

  defp serialize_asset(asset) do
    %{
      id: asset.id,
      filename: asset.filename,
      url: PrivateMedia.asset_url(asset),
      content_type: asset.content_type
    }
  end

  defp serialize_entity(entity), do: %{id: entity.id, name: entity.name}

  defp maybe_include_selected(items, nil, _query, _matches?), do: items

  defp maybe_include_selected(items, selected, query, matches?) do
    cond do
      not matches?.(selected, query) -> items
      Enum.any?(items, &same_id?(&1, selected)) -> items
      true -> [selected | items]
    end
  end

  defp same_id?(%{id: left}, %{id: right}), do: left == right

  defp entity_matches?(%{name: name}, query), do: query_matches?(name, query)
  defp query_matches?(_text, query) when query in [nil, ""], do: true
  defp query_matches?(text, query), do: normalize(text) =~ normalize(query)

  defp normalize_limit(opts, default) do
    Keyword.update(opts, :limit, default, &bounded_limit(&1, default))
  end

  defp bounded_limit(limit, _default) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp bounded_limit(_limit, default), do: default

  defp normalize_query(query) when is_binary(query), do: String.trim(query)
  defp normalize_query(_query), do: ""

  defp normalize(value) when is_binary(value), do: String.downcase(value)
  defp normalize(value), do: value |> to_string() |> String.downcase()

  defp normalize_ids(ids) when is_list(ids), do: ids
  defp normalize_ids(nil), do: []
  defp normalize_ids(id), do: [id]

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _invalid -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
