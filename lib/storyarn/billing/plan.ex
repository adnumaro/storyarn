defmodule Storyarn.Billing.Plan do
  @moduledoc """
  Static plan configuration. Plans change rarely and live in code, not DB.
  """

  @default_plan "free"

  @plans %{
    "free" => %{
      name: "Free",
      limits: %{
        workspaces_per_user: 1,
        projects_per_workspace: 3,
        members_per_workspace: 2,
        items_per_project: 700,
        storage_bytes_per_workspace: 250 * 1024 * 1024,
        named_versions_per_project: 10,
        project_snapshots_per_project: 10,
        snapshot_retention_days: 30,
        # Trash retention for soft-deleted entities (sequences, flows).
        # After this window the retention worker hard-deletes the entity
        # (FK CASCADE drops its trash refs automatically). Free tier = 24h
        # by decision 2026-04-21; paid tiers will extend up to 15-30 days.
        trash_retention_hours: 24
      }
    }
  }

  @doc """
  Returns the plan config for the given plan key.
  """
  def get(key) when is_binary(key), do: Map.get(@plans, key)

  @doc """
  Returns a specific limit for a plan.
  """
  def limit(plan_key, resource) do
    case get(plan_key) do
      nil -> nil
      plan -> get_in(plan, [:limits, resource])
    end
  end

  @doc """
  Returns all plan configs.
  """
  def all, do: @plans

  @doc """
  Returns the default plan key.
  """
  def default_plan, do: @default_plan

  @doc """
  Returns the trash retention window (in hours) for a plan key.
  Falls back to the default plan's value if the key is unknown.
  """
  @spec retention_hours(String.t() | nil) :: pos_integer()
  def retention_hours(plan_key) when is_binary(plan_key) do
    case limit(plan_key, :trash_retention_hours) do
      nil -> limit(@default_plan, :trash_retention_hours)
      hours -> hours
    end
  end

  def retention_hours(_), do: limit(@default_plan, :trash_retention_hours)
end
