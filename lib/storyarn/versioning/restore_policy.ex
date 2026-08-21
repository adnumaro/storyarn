defmodule Storyarn.Versioning.RestorePolicy do
  @moduledoc """
  Runtime policy for restore operations that mutate persisted data.

  Entity-version restore paths are fail-closed: a missing or invalid
  configuration value keeps the corresponding operation disabled. Exact full
  project snapshot restore is an always-available recovery primitive and still
  requires its normal authorization, integrity, quota, and concurrency checks.
  """

  @type entity_type :: String.t()
  @type action :: {:entity_version_restore, entity_type()} | {:project_snapshot_restore, String.t()}

  @entity_actions %{
    "sheet" => :sheet_version_restore,
    "flow" => :flow_version_restore,
    "scene" => :scene_version_restore
  }
  @spec enabled?(action()) :: boolean()
  def enabled?({:entity_version_restore, entity_type}) do
    case Map.fetch(@entity_actions, entity_type) do
      {:ok, config_key} -> configured?(config_key)
      :error -> false
    end
  end

  def enabled?({:project_snapshot_restore, "full"}), do: true

  def enabled?(_action), do: false

  @spec ensure_enabled(action()) :: :ok | {:error, :restore_temporarily_disabled}
  def ensure_enabled(action) do
    if enabled?(action), do: :ok, else: {:error, :restore_temporarily_disabled}
  end

  @doc false
  @spec ensure_builder_enabled(entity_type(), term()) ::
          :ok | {:error, :restore_temporarily_disabled}
  def ensure_builder_enabled(entity_type, {:entity_version_restore, action_type} = action)
      when entity_type == action_type do
    ensure_enabled(action)
  end

  def ensure_builder_enabled(_entity_type, _action), do: {:error, :restore_temporarily_disabled}

  defp configured?(key) do
    case Application.get_env(:storyarn, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.keyword?(config) and Keyword.get(config, key, false) == true

      _invalid_config ->
        false
    end
  end
end
