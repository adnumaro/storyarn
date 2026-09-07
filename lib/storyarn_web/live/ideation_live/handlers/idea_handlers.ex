defmodule StoryarnWeb.IdeationLive.Handlers.IdeaHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.BoardData
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies

  def run("create_idea", scope, project_id, session_id, params) do
    with {:ok, attrs} <- Params.creation(params) do
      scope |> Ideation.create_idea(project_id, session_id, attrs) |> idea_result()
    end
  end

  def run("derive_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, revision} <- Params.positive(params["revision"]),
         {:ok, attrs} <- Params.creation(params) do
      scope |> Ideation.derive_idea(project_id, session_id, id, revision, attrs) |> idea_result()
    end
  end

  def run("save_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, revision} <- Params.positive(params["revision"]) do
      attrs = Params.fields(params, [:title, :body, :state, :request_key])

      case Ideation.update_idea(scope, project_id, session_id, id, revision, attrs) do
        {:error, {:edit_conflict, receipt}} -> conflict(scope, project_id, session_id, id, receipt)
        result -> idea_result(result)
      end
    end
  end

  def run("inspect_idea", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, idea} <- Ideation.get_idea(scope, project_id, session_id, id),
         {:ok, history} <- Ideation.list_idea_revisions(scope, project_id, session_id, id),
         {:ok, conflicts} <- conflict_page(scope, project_id, session_id, idea, nil) do
      {:ok,
       %{
         idea: BoardData.idea(idea),
         history: history,
         history_next: BoardData.page(history).next,
         conflicts: conflicts.entries,
         conflicts_next: conflicts.next
       }}
    end
  end

  def run("idea_history", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, before_id} <- Params.optional_id(params["before_id"]),
         {:ok, rows} <- Ideation.list_idea_revisions(scope, project_id, session_id, id, before_id: before_id) do
      {:ok, BoardData.page(rows)}
    end
  end

  def run("idea_conflicts", scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["idea_id"]),
         {:ok, before_id} <- Params.optional_id(params["before_id"]),
         {:ok, idea} <- Ideation.get_idea(scope, project_id, session_id, id) do
      conflict_page(scope, project_id, session_id, idea, before_id)
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

  defp conflict_page(scope, project_id, session_id, idea, before_id) do
    if idea.author_id == scope.user.id do
      with {:ok, rows} <- Ideation.list_idea_conflicts(scope, project_id, session_id, idea.id, before_id: before_id) do
        page = BoardData.page(rows)
        {:ok, %{page | entries: Enum.reject(rows, &Replies.equivalent?(&1.attempted, idea))}}
      end
    else
      {:ok, BoardData.page([])}
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
