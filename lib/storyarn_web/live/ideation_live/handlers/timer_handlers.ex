defmodule StoryarnWeb.IdeationLive.Handlers.TimerHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def run(event, scope, project_id, session_id, params) do
    with {:ok, revision} <- Params.positive(params["revision"]),
         {:ok, session} <- execute(event, scope, project_id, session_id, revision, params) do
      {:ok, %{id: session.id}}
    end
  end

  defp execute("start_timer", scope, project_id, session_id, revision, params) do
    with {:ok, seconds} <- Params.positive(params["seconds"]) do
      attrs =
        params
        |> Params.fields([:reveal_on_expiry, :close_contributions_on_expiry])
        |> Map.put("seconds", seconds)

      Ideation.start_timer(scope, project_id, session_id, revision, attrs)
    end
  end

  defp execute("pause_timer", scope, project_id, session_id, revision, params) do
    with {:ok, version} <- Params.positive(params["timer_version"]),
         do: Ideation.pause_timer(scope, project_id, session_id, revision, version)
  end

  defp execute("resume_timer", scope, project_id, session_id, revision, params) do
    with {:ok, version} <- Params.positive(params["timer_version"]),
         do: Ideation.resume_timer(scope, project_id, session_id, revision, version)
  end

  defp execute("extend_timer", scope, project_id, session_id, revision, params) do
    with {:ok, version} <- Params.positive(params["timer_version"]),
         {:ok, seconds} <- Params.positive(params["seconds"]),
         do: Ideation.extend_timer(scope, project_id, session_id, revision, version, seconds)
  end

  defp execute("cancel_timer", scope, project_id, session_id, revision, params) do
    with {:ok, version} <- Params.positive(params["timer_version"]),
         do: Ideation.cancel_timer(scope, project_id, session_id, revision, version)
  end

  defp execute("set_contributions_open", scope, project_id, session_id, revision, params),
    do: Ideation.set_contributions_open(scope, project_id, session_id, revision, params["open"])
end
