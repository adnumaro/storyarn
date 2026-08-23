defmodule Storyarn.Versioning.RestorePolicy do
  @moduledoc """
  Runtime policy for restore operations that mutate persisted data.

  Entity-version restore now lives with each owning tool. Exact full project
  snapshot restore is an always-available recovery primitive and still
  requires its normal authorization, integrity, quota, and concurrency checks.
  """

  @type action :: {:project_snapshot_restore, String.t()}

  @spec enabled?(action()) :: boolean()
  def enabled?({:project_snapshot_restore, "full"}), do: true

  def enabled?(_action), do: false

  @spec ensure_enabled(action()) :: :ok | {:error, :restore_temporarily_disabled}
  def ensure_enabled(action) do
    if enabled?(action), do: :ok, else: {:error, :restore_temporarily_disabled}
  end
end
