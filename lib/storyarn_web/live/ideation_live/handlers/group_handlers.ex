defmodule StoryarnWeb.IdeationLive.Handlers.GroupHandlers do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.Params

  def run("create_group", scope, project_id, session_id, params) do
    attrs = Params.fields(params, [:title, :synthesis, :idea_ids, :canvas, :request_key])
    Ideation.create_group(scope, project_id, session_id, attrs)
  end

  def run(event, scope, project_id, session_id, params) do
    with {:ok, id} <- Params.positive(params["group_id"]),
         {:ok, version} <- Params.positive(params["version"]) do
      execute(event, scope, project_id, session_id, id, version, params)
    end
  end

  defp execute("update_group", scope, project_id, session_id, id, version, params) do
    attrs = Params.fields(params, [:title, :synthesis, :idea_ids, :canvas, :request_key])
    Ideation.update_group(scope, project_id, session_id, id, version, attrs)
  end

  defp execute("move_group", scope, project_id, session_id, id, version, params) do
    attrs = Params.fields(params, [:x, :y, :member_versions, :request_key])
    Ideation.move_group(scope, project_id, session_id, id, version, attrs)
  end

  defp execute("delete_group", scope, project_id, session_id, id, version, params),
    do: Ideation.delete_group(scope, project_id, session_id, id, version, params["request_key"])

  defp execute("restore_group", scope, project_id, session_id, id, version, params) do
    attrs = Params.fields(params, [:deleted_at, :idea_ids, :request_key])
    Ideation.restore_group(scope, project_id, session_id, id, version, attrs)
  end
end
