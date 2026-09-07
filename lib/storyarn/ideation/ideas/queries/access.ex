defmodule Storyarn.Ideation.Ideas.Queries.Access do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Sessions

  def authorize(scope, project_id, session_id) when valid_id(project_id) and valid_id(session_id) do
    case Sessions.get_session(scope, project_id, session_id) do
      {:ok, _session} -> {:ok, scope.user.id}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_scope, _project_id, _session_id), do: {:error, :not_found}
end
