defmodule Storyarn.Versioning.ProjectSnapshotPolicy do
  @moduledoc """
  Product policy for canonical full-archive snapshot origins.

  User-created snapshots are full, consume the normal workspace byte quota and
  project snapshot slot, and have no implicit retention deletion. System daily,
  pre-restore, and post-restore capture remains disabled until its owning flow
  exists, but each origin has an explicit TTL for rows created by those flows.
  No origin may bypass quota or use a retired snapshot mode.
  """

  @policies %{
    user: %{
      enabled: true,
      mode: "full",
      quota: :workspace_and_project_slot,
      retention: :explicit_delete,
      failure: :visible_to_user
    },
    daily: %{
      enabled: false,
      mode: "full",
      quota: :workspace_and_project_slot,
      retention: {:ttl, 30 * 24 * 60 * 60},
      failure: :observable_system_failure
    },
    pre_restore: %{
      enabled: false,
      mode: "full",
      quota: :workspace_and_project_slot,
      retention: {:ttl, 14 * 24 * 60 * 60},
      failure: :block_restore
    },
    post_restore: %{
      enabled: false,
      mode: "full",
      quota: :workspace_and_project_slot,
      retention: {:ttl, 30 * 24 * 60 * 60},
      failure: :observable_system_failure
    }
  }

  @doc false
  def policy(:user) do
    {:ok, @policies.user}
  end

  def policy(origin) when origin in [:daily, :pre_restore, :post_restore], do: {:ok, Map.fetch!(@policies, origin)}

  def policy("user"), do: policy(:user)
  def policy("daily"), do: policy(:daily)
  def policy("pre_restore"), do: policy(:pre_restore)
  def policy("post_restore"), do: policy(:post_restore)

  def policy(_origin), do: {:error, :invalid_snapshot_origin}

  @doc false
  def expires_at(origin, %DateTime{} = captured_at) do
    case policy(origin) do
      {:ok, %{retention: :explicit_delete}} -> {:ok, nil}
      {:ok, %{retention: {:ttl, seconds}}} -> {:ok, DateTime.add(captured_at, seconds, :second)}
      {:error, reason} -> {:error, reason}
    end
  end
end
