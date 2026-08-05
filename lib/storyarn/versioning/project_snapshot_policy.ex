defmodule Storyarn.Versioning.ProjectSnapshotPolicy do
  @moduledoc """
  Product policy for snapshot origins while full snapshots roll out.

  User-created snapshots are full, consume the normal workspace byte quota and
  project snapshot slot, and have no implicit retention deletion. System daily,
  pre-restore, and post-restore snapshots remain disabled until their owning
  lifecycle tickets define retention and failure handling. They must not bypass
  quota or silently fall back to linked mode when later enabled.
  """

  @system_origins [:daily, :pre_restore, :post_restore]

  @doc false
  def policy(:user) do
    {:ok,
     %{
       mode: "full",
       quota: :workspace_and_project_slot,
       retention: :explicit_lifecycle,
       failure: :visible_to_user
     }}
  end

  def policy(origin) when origin in @system_origins, do: {:error, :system_snapshot_policy_not_enabled}

  def policy(_origin), do: {:error, :invalid_snapshot_origin}
end
