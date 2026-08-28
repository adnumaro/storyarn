defmodule Storyarn.Scenes.Versioning.Commands.Tracked do
  @moduledoc """
  Public Scene commands whose successful execution emits Scene-owned facts.

  Keeping event construction here prevents presentation adapters from owning
  either the event vocabulary or its payload contract.
  """

  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.Versioning
  alias Storyarn.Scenes.Versioning.Events

  @spec create_named_version(term(), Scene.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:error, term(), map()}
  def create_named_version(%{user: %{id: user_id}} = scope, %Scene{} = scene, opts)
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with :ok <- validate_named_version_title(opts) do
      scene
      |> Versioning.create_version(user_id, opts)
      |> tap_success(fn _version -> emit_version_event(scope, scene, :version_created) end)
    end
  end

  def create_named_version(_scope, %Scene{}, _opts), do: {:error, :invalid_actor}

  @spec restore_version(term(), Scene.t(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def restore_version(scope, %Scene{} = scene, version, opts) when is_list(opts) do
    scene
    |> Versioning.restore_version(version, opts)
    |> tap_success(fn _restored -> emit_version_event(scope, scene, :version_restored) end)
  end

  @spec record_version_panel_opened(term(), Scene.t()) :: :ok
  def record_version_panel_opened(scope, %Scene{} = scene) do
    emit_version_event(scope, scene, :version_panel_opened)
  end

  @spec record_version_compared(term(), Scene.t()) :: :ok
  def record_version_compared(scope, %Scene{} = scene) do
    emit_version_event(scope, scene, :version_compared)
  end

  defp emit_version_event(scope, scene, event) do
    Events.emit(scope, event, %{entity_type: "scene", project_id: scene.project_id})
  end

  defp tap_success({:ok, value} = result, callback) do
    callback.(value)
    result
  end

  defp tap_success(result, _callback), do: result

  defp validate_named_version_title(opts) do
    case Keyword.get(opts, :title) do
      title when is_binary(title) ->
        if String.trim(title) == "", do: {:error, :title_required}, else: :ok

      _missing ->
        {:error, :title_required}
    end
  end
end
