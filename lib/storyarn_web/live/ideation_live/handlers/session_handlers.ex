defmodule StoryarnWeb.IdeationLive.Handlers.SessionHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def run("create_session", scope, project_id, params) do
    attrs = Params.fields(params, [:title, :objective, :context])

    configuration =
      case params["preset"] do
        "openPreset" -> %{default_visibility: :shared}
        "assisted" -> %{default_visibility: :private, publication_policy: :facilitator_assisted}
        _ -> %{}
      end

    scope
    |> Ideation.create_session(project_id, Map.put(attrs, "configuration", configuration))
    |> summarize()
  end

  def run(event, scope, project_id, params) do
    with {:ok, id} <- Params.positive(params["session_id"]),
         {:ok, revision} <- Params.positive(params["revision"]) do
      event |> execute(scope, project_id, id, revision, params) |> summarize()
    end
  end

  defp execute("update_session", scope, project_id, id, revision, params) do
    attrs = Params.fields(params, [:title, :objective, :context])

    attrs =
      if is_map(params["configuration"]),
        do: Map.put(attrs, "configuration", Map.take(params["configuration"], ~w(default_visibility publication_policy))),
        else: attrs

    Ideation.update_session(scope, project_id, id, revision, attrs)
  end

  defp execute("assign_responsibilities", scope, project_id, id, revision, params) do
    attrs = Params.fields(params, [:facilitator_id, :decision_owner_id])

    with {:ok, parsed} <- parse_responsibilities(attrs) do
      Ideation.assign_session_responsibilities(scope, project_id, id, revision, parsed)
    end
  end

  defp execute("archive_session", scope, project_id, id, revision, _),
    do: Ideation.archive_session(scope, project_id, id, revision)

  defp execute("reopen_session", scope, project_id, id, revision, _),
    do: Ideation.reopen_session(scope, project_id, id, revision)

  defp execute("recover_session", scope, project_id, id, revision, _),
    do: Ideation.recover_session(scope, project_id, id, revision)

  defp execute("purge_session", scope, project_id, id, revision, _),
    do: Ideation.purge_replaced_session(scope, project_id, id, revision)

  defp summarize({:ok, %{id: id}}), do: {:ok, %{id: id}}
  defp summarize(result), do: result

  defp parse_responsibilities(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, parsed} ->
      case Params.positive(value) do
        {:ok, id} -> {:cont, {:ok, Map.put(parsed, key, id)}}
        error -> {:halt, error}
      end
    end)
  end
end
