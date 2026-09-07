defmodule StoryarnWeb.IdeationLive.Handlers.IdeaHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.BoardData
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies

  def run("create_idea", scope, project_id, session_id, params) do
    with {:ok, attrs} <- Params.creation(params) do
      scope |> Ideation.create_canvas_idea(project_id, session_id, attrs) |> idea_result()
    end
  end

  def run("delete_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, revision} <- Params.positive(params["revision"]) do
      Ideation.delete_idea(scope, project_id, session_id, id, revision)
    end
  end

  def run("restore_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, revision} <- Params.positive(params["revision"]) do
      scope
      |> Ideation.restore_idea(project_id, session_id, id, revision, params["deleted_at"])
      |> idea_result()
    end
  end

  def run("connect_ideas", scope, project_id, session_id, params) do
    with {:ok, source} <- Params.positive(params["source_id"]),
         {:ok, target} <- Params.positive(params["target_id"]) do
      Ideation.connect_ideas(scope, project_id, session_id, source, target, params["connected"])
    end
  end

  def run("move_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         version when is_integer(version) and version >= 0 <- params["version"] do
      Ideation.update_idea_canvas(scope, project_id, session_id, id, version, params)
    else
      _ -> {:error, :invalid_parameters}
    end
  end

  def run("save_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, revision} <- Params.positive(params["revision"]) do
      attrs = Params.fields(params, [:title, :body, :state, :request_key])

      case Ideation.update_canvas_idea(scope, project_id, session_id, id, revision, attrs) do
        {:error, {:edit_conflict, receipt}} -> conflict(scope, project_id, session_id, id, receipt)
        result -> idea_result(result)
      end
    end
  end

  def run("prepare_reveal", scope, project_id, session_id, params) do
    with {:ok, selection} <- selection(params),
         {:ok, operation} <- Ideation.prepare_idea_reveal(scope, project_id, session_id, params["request_key"], selection) do
      # A manager confirms only a count. Never send opaque private IDs or content
      # to the board; the durable operation owns the frozen manifest.
      {:ok, %{id: operation.id, count: length(operation.manifest), status: operation.status}}
    end
  end

  def run("reveal_ideas", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["operation_id"]),
         {:ok, operation} <- Ideation.reveal_ideas(scope, project_id, session_id, id) do
      {:ok, %{id: operation.id, count: length(operation.manifest), status: operation.status}}
    end
  end

  defp selection(%{"mode" => "eligible"} = params) do
    states = if params["include_discarded"] == true, do: [:active, :parked, :discarded], else: [:active, :parked]
    {:ok, %{states: states}}
  end

  defp selection(%{"targets" => targets}), do: Params.targets(targets)
  defp selection(_), do: {:error, :invalid_parameters}

  defp conflict(scope, project_id, session_id, id, receipt) do
    with {:ok, current} <- Ideation.get_idea(scope, project_id, session_id, id) do
      if Replies.equivalent?(receipt.attempted, current),
        do: {:ok, BoardData.idea(current)},
        else: {:conflict, %{current: BoardData.idea(current), receipt: receipt}}
    end
  end

  defp idea_result({:ok, idea}), do: {:ok, BoardData.idea(idea)}
  defp idea_result(result), do: result
end
