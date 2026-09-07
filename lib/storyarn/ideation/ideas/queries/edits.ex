defmodule Storyarn.Ideation.Ideas.Queries.Edits do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def list(scope, project_id, session_id, idea_id, opts) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         {:ok, _idea} <- Visible.owned(session_id, idea_id, actor_id),
         {:ok, limit, before_id} <- Input.page(opts) do
      query =
        from e in Edit,
          where: e.idea_id == ^idea_id and e.actor_id == ^actor_id and e.outcome == :conflict,
          order_by: [desc: e.id],
          limit: ^limit

      query = if before_id, do: where(query, [e], e.id < ^before_id), else: query
      {:ok, query |> Repo.all() |> Enum.map(&View.edit/1)}
    end
  end

  def get(scope, project_id, session_id, idea_id, key) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         {:ok, _idea} <- Visible.owned(session_id, idea_id, actor_id),
         {:ok, key} <- Input.request_key(%{request_key: key}),
         %Edit{} = edit <- Repo.get_by(Edit, idea_id: idea_id, actor_id: actor_id, request_key: key) do
      {:ok, View.edit(edit)}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
