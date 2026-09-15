defmodule Storyarn.Ideation.Ideas.Queries.List do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id, opts) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         {:ok, limit, before_id} <- Input.page(opts),
         {:ok, query} <- filtered(session_id, actor_id, opts) do
      query = query |> order_by([i], desc: i.id) |> limit(^limit)
      query = if before_id, do: where(query, [i], i.id < ^before_id), else: query

      rows = Repo.all(query)
      link_ids = Enum.flat_map(rows, fn {idea, _, _} -> Map.get(idea.canvas, "links", []) end)

      readable =
        session_id |> Visible.visible_link_ids(actor_id, Enum.uniq(link_ids)) |> MapSet.new()

      {:ok,
       Enum.map(rows, fn {idea, revision, source_published?} ->
         links = Enum.filter(Map.get(idea.canvas, "links", []), &MapSet.member?(readable, &1))
         View.idea(idea, revision, actor_id, source_published?, links)
       end)}
    end
  end

  def counts(scope, project_id, session_id, opts) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         :ok <- count_options(opts),
         {:ok, round_id} <-
           Sessions.validate_round_filter(session_id, Keyword.get(opts, :round_id, :all)) do
      counts =
        session_id
        |> Visible.query(actor_id)
        |> filter_round(round_id)
        |> exclude(:select)
        |> group_by([i], i.state)
        |> select([i], {i.state, count(i.id)})
        |> Repo.all()
        |> Map.new()

      {:ok, Map.merge(%{active: 0, parked: 0, discarded: 0}, counts)}
    end
  end

  # Parked notes of several sessions in one read, for the session tree. Others'
  # notes count only when shared and outside private mode, as on the canvas.
  def parked_counts(scope, project_id, session_ids) when is_list(session_ids) and length(session_ids) <= 200 do
    with :ok <- Sessions.authorize_project_read(scope, project_id),
         true <- Enum.all?(session_ids, &valid_id/1) do
      {:ok, session_ids |> waiting_query(project_id, scope.user.id) |> Repo.all() |> Map.new()}
    else
      false -> {:error, :invalid_options}
      {:error, reason} -> {:error, reason}
    end
  end

  def parked_counts(_scope, _project_id, _session_ids), do: {:error, :invalid_options}

  # Parked notes the reader can see, minus those with a copy brought ahead
  # that the reader can see too: the tree and the board's list must agree.
  defp waiting_query(session_ids, project_id, actor_id) do
    from i in Idea,
      as: :note,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == i.session_id,
      left_join: mask in subquery(Sessions.round_mask_query()),
      as: :mask,
      on: mask.id == i.round_id,
      where: i.session_id in ^session_ids and s.project_id == ^project_id and is_nil(i.deleted_at),
      where: i.state == :parked and not exists(forwarded_query(actor_id)),
      where: ^readable(actor_id),
      group_by: i.session_id,
      select: {i.session_id, count(i.id)}
  end

  defp forwarded_query(actor_id) do
    from d in Idea,
      as: :note,
      left_join: mask in subquery(Sessions.round_mask_query()),
      as: :mask,
      on: mask.id == d.round_id,
      where: d.source_idea_id == parent_as(:note).id and is_nil(d.deleted_at),
      where: ^readable(actor_id)
  end

  # A note the reader can see: their own, or published in a round that is not masked.
  defp readable(actor_id) do
    dynamic(
      [note: i, mask: mask],
      i.author_id == ^actor_id or
        (not fragment("COALESCE(?, false)", mask.private) and not is_nil(i.published_revision))
    )
  end

  defp count_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_options}
  end

  defp count_options(_opts), do: {:error, :invalid_options}

  defp filtered(session_id, actor_id, opts) do
    state = Keyword.get(opts, :state, :active)
    visibility = Keyword.get(opts, :visibility, :all)

    with true <-
           state in [:active, :parked, :discarded, :all] and
             visibility in [:private, :shared, :all],
         {:ok, round_id} <-
           Sessions.validate_round_filter(session_id, Keyword.get(opts, :round_id, :all)) do
      query = Visible.query(session_id, actor_id)
      query = if state == :all, do: query, else: where(query, [i], i.state == ^state)
      {:ok, query |> filter_visibility(visibility) |> filter_round(round_id)}
    else
      false -> {:error, :invalid_options}
      {:error, reason} -> {:error, reason}
    end
  end

  defp filter_visibility(query, :private), do: where(query, [i], is_nil(i.published_revision))
  defp filter_visibility(query, :shared), do: where(query, [i], not is_nil(i.published_revision))
  defp filter_visibility(query, :all), do: query

  defp filter_round(query, :all), do: query
  defp filter_round(query, nil), do: where(query, [i], is_nil(i.round_id))
  defp filter_round(query, round_id), do: where(query, [i], i.round_id == ^round_id)

  # Other people's notes in a private round: where they are and how wide, never
  # what they say or who wrote them. The board draws them as placeholders, and
  # only for what the reveal will show: a draft nobody consented to publish
  # has no place there.
  def masked(scope, project_id, session_id) do
    with {:ok, _} <- Sessions.get_session(scope, project_id, session_id) do
      actor_id = scope.user.id

      rows =
        Repo.all(
          from i in Idea,
            join: mask in subquery(Sessions.round_mask_query()),
            on: mask.id == i.round_id,
            where:
              i.session_id == ^session_id and is_nil(i.deleted_at) and mask.private and
                i.author_id != ^actor_id and i.state != :discarded and
                (i.publication_consent == :facilitator_assisted or not is_nil(i.published_revision)) and
                fragment("jsonb_typeof(? -> 'y') = 'number'", i.canvas),
            order_by: i.id,
            limit: 2000,
            select: %{id: i.id, round_id: i.round_id, canvas: i.canvas}
        )

      {:ok, Enum.map(rows, &%{&1 | canvas: Map.take(&1.canvas, ~w(x y width))})}
    end
  end
end
