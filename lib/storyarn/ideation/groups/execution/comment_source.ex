defmodule Storyarn.Ideation.Groups.Execution.CommentSource do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  defguardp valid_id?(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  def get(%{user: %{id: _}} = scope, project_id, session_id, group_id, opts)
      when valid_id?(project_id) and valid_id?(session_id) and valid_id?(group_id) do
    case Sessions.comment_source(scope, project_id, session_id, opts) do
      {:ok, %{private_mode: false}} ->
        source(session_id, group_id, opts)

      _ ->
        {:error, :not_found}
    end
  end

  def get(_, _, _, _, _), do: {:error, :not_found}

  defp source(session_id, group_id, opts) do
    query = from(g in Group, where: g.id == ^group_id and g.session_id == ^session_id and is_nil(g.deleted_at))
    query = if opts[:lock] == :share, do: lock(query, "FOR SHARE"), else: query

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      group ->
        {:ok,
         %{
           id: group.id,
           name: "Group ##{group.id}",
           recovery_identity: group.recovery_identity,
           inserted_at: DateTime.truncate(group.inserted_at, :second)
         }}
    end
  end
end
