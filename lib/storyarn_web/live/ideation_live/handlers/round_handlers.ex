defmodule StoryarnWeb.IdeationLive.Handlers.RoundHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def run(event, scope, project_id, session_id, params) do
    with {:ok, revision} <- Params.positive(params["revision"]),
         {:ok, session} <- execute(event, scope, project_id, session_id, revision, params) do
      {:ok, %{id: session.id}}
    end
  end

  defp execute("create_round", scope, project_id, session_id, revision, params),
    do: Ideation.create_round(scope, project_id, session_id, revision, Params.fields(params, [:prompt]))

  defp execute("update_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.update_round(scope, project_id, session_id, id, revision, Params.fields(params, [:prompt]))
  end

  defp execute("cancel_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.cancel_round(scope, project_id, session_id, id, revision)
  end

  defp execute("start_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.start_round(scope, project_id, session_id, id, revision)
  end

  defp execute("close_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.close_round(scope, project_id, session_id, id, revision)
  end
end
