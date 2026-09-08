defmodule Storyarn.Ideation.Ideas.Queries.List do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run(scope, project_id, session_id, opts) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         {:ok, limit, before_id} <- Input.page(opts),
         {:ok, query} <- filtered(session_id, actor_id, opts) do
      query = query |> order_by([i], desc: i.id) |> limit(^limit)
      query = if before_id, do: where(query, [i], i.id < ^before_id), else: query

      rows = Repo.all(query)
      link_ids = Enum.flat_map(rows, fn {idea, _, _} -> Map.get(idea.canvas, "links", []) end)
      readable = session_id |> Visible.visible_link_ids(actor_id, Enum.uniq(link_ids)) |> MapSet.new()

      {:ok,
       Enum.map(rows, fn {idea, revision, source_published?} ->
         links = Enum.filter(Map.get(idea.canvas, "links", []), &MapSet.member?(readable, &1))
         View.idea(idea, revision, actor_id, source_published?, links)
       end)}
    end
  end

  def counts(scope, project_id, session_id) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id) do
      counts =
        session_id
        |> Visible.query(actor_id)
        |> exclude(:select)
        |> group_by([i], i.state)
        |> select([i], {i.state, count(i.id)})
        |> Repo.all()
        |> Map.new()

      {:ok, Map.merge(%{active: 0, parked: 0, discarded: 0}, counts)}
    end
  end

  defp filtered(session_id, actor_id, opts) do
    state = Keyword.get(opts, :state, :active)
    visibility = Keyword.get(opts, :visibility, :all)

    if state in [:active, :parked, :discarded, :all] and visibility in [:private, :shared, :all] do
      query = Visible.query(session_id, actor_id)
      query = if state == :all, do: query, else: where(query, [i], i.state == ^state)
      {:ok, filter_visibility(query, visibility)}
    else
      {:error, :invalid_options}
    end
  end

  defp filter_visibility(query, :private), do: where(query, [i], is_nil(i.published_revision))
  defp filter_visibility(query, :shared), do: where(query, [i], not is_nil(i.published_revision))
  defp filter_visibility(query, :all), do: query
end
