defmodule Storyarn.Scenes.Exploration.Events do
  @moduledoc "Scene exploration business-event vocabulary."

  alias Storyarn.Platform
  alias Storyarn.Scenes.Scene

  @doc "Emits the typed fact that a Scene exploration session started."
  def exploration_started(scope_or_user, %Scene{} = scene, has_saved_session) when is_boolean(has_saved_session) do
    if valid_id?(scene.project_id) and valid_id?(scene.id) do
      Platform.react_to_event(scope_or_user, :scenes, :exploration_started, %{
        has_saved_session: has_saved_session,
        project_id: scene.project_id,
        scene_id: scene.id
      })
    else
      :ok
    end
  end

  def exploration_started(_scope_or_user, _scene, _has_saved_session), do: :ok

  defp valid_id?(id), do: is_integer(id) and id > 0
end
