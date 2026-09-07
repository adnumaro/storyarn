defmodule Storyarn.Ideation.Ideas.Queries.Reveal do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run(scope, project_id, session_id, operation_id) when valid_id(operation_id) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         %Reveal{} = operation <- Repo.get_by(Reveal, session_id: session_id, id: operation_id, actor_id: actor_id) do
      {:ok, View.reveal(operation)}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_scope, _project_id, _session_id, _operation_id), do: {:error, :not_found}
end
