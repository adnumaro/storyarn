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

  defp execute("new_round", scope, project_id, session_id, revision, params) do
    with {:ok, attrs} <- new_round_attrs(params),
         do: Ideation.new_round(scope, project_id, session_id, revision, attrs)
  end

  defp execute("update_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.update_round(scope, project_id, session_id, id, revision, Params.fields(params, [:prompt]))
  end

  defp execute("set_round_privacy", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]) do
      attrs = Params.fields(params, [:private, :reveal_on_expiry])
      Ideation.set_round_privacy(scope, project_id, session_id, id, revision, attrs)
    end
  end

  defp execute("reveal_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.reveal_round(scope, project_id, session_id, id, revision)
  end

  defp execute("close_round", scope, project_id, session_id, revision, params) do
    with {:ok, id} <- Params.positive(params["round_id"]),
         do: Ideation.close_round(scope, project_id, session_id, id, revision)
  end

  defp new_round_attrs(params), do: {:ok, Params.fields(params, [:prompt])}
end
