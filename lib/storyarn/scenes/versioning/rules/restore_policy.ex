defmodule Storyarn.Scenes.Versioning.RestorePolicy do
  @moduledoc false

  def enabled?, do: enabled?({:entity_version_restore, "scene"})

  def enabled?({:entity_version_restore, "scene"}) do
    case Application.get_env(:storyarn, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.keyword?(config) and Keyword.get(config, :scene_version_restore, false) == true

      _invalid_config ->
        false
    end
  end

  def enabled?(_action), do: false

  def ensure_enabled(action \\ {:entity_version_restore, "scene"}) do
    if enabled?(action), do: :ok, else: {:error, :restore_temporarily_disabled}
  end

  def ensure_builder_enabled("scene", {:entity_version_restore, "scene"} = action), do: ensure_enabled(action)

  def ensure_builder_enabled(_entity_type, _action), do: {:error, :restore_temporarily_disabled}
end
