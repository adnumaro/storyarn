defmodule Storyarn.Flows.Versioning.RestorePolicy do
  @moduledoc """
  Fail-closed runtime policy for in-place Flow version restores.

  This policy deliberately owns its configuration key. During rollout the
  application configuration must set `:flow_version_restore` under this
  module; missing, malformed, or non-boolean values keep restore disabled.
  """

  @type action :: {:entity_version_restore, String.t()}

  @spec enabled?(term()) :: boolean()
  def enabled?({:entity_version_restore, "flow"}) do
    case Application.get_env(:storyarn, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.keyword?(config) and Keyword.get(config, :flow_version_restore, false) == true

      _invalid_config ->
        false
    end
  end

  def enabled?(_action), do: false

  @spec ensure_enabled(term()) :: :ok | {:error, :restore_temporarily_disabled}
  def ensure_enabled(action) do
    if enabled?(action), do: :ok, else: {:error, :restore_temporarily_disabled}
  end
end
