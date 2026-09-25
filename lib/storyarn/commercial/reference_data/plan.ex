defmodule Storyarn.Commercial.Billing.Plan do
  @moduledoc """
  Static plan configuration. Plans change rarely and live in code, not DB.

  A limit is a non-negative integer or `:unlimited`. A resource a plan does
  not define has no limit value, which callers treat as blocked.
  """

  @default_plan "free"
  @gib 1024 * 1024 * 1024

  @plans %{
    "free" => %{
      name: "Free",
      limits: %{
        workspaces_per_user: 1,
        projects_per_workspace: 3,
        members_per_workspace: 2,
        items_per_project: 700,
        storage_bytes_per_workspace: 250 * 1024 * 1024,
        project_templates_per_workspace: 10,
        project_template_versions_per_template: 20,
        named_versions_per_project: 10,
        project_snapshots_per_project: 10,
        # Trash retention for soft-deleted entities (sequences, flows).
        # After this window the retention worker hard-deletes the entity
        # (FK CASCADE drops its trash refs automatically). Free tier = 24h
        # by decision 2026-04-21.
        trash_retention_hours: 24
      }
    },
    # The free beta: Pro's limits with a cap on members, since nobody pays for
    # seats while it lasts. The cap counts every member of the workspace and its
    # projects plus pending invitations, viewers included, until ENG-240 turns
    # it into a count of editor seats.
    "beta" => %{
      name: "Beta",
      limits: %{
        projects_per_workspace: :unlimited,
        members_per_workspace: 10,
        items_per_project: :unlimited,
        storage_bytes_per_workspace: 10 * @gib,
        project_templates_per_workspace: 50,
        project_template_versions_per_template: 100,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 20,
        trash_retention_hours: 30 * 24
      }
    },
    "pro" => %{
      name: "Pro",
      limits: %{
        projects_per_workspace: :unlimited,
        members_per_workspace: :unlimited,
        items_per_project: :unlimited,
        storage_bytes_per_workspace: 10 * @gib,
        project_templates_per_workspace: 50,
        project_template_versions_per_template: 100,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 20,
        trash_retention_hours: 30 * 24
      }
    },
    "studio" => %{
      name: "Studio",
      limits: %{
        projects_per_workspace: :unlimited,
        members_per_workspace: :unlimited,
        items_per_project: :unlimited,
        storage_bytes_per_workspace: 50 * @gib,
        project_templates_per_workspace: :unlimited,
        project_template_versions_per_template: :unlimited,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 100,
        trash_retention_hours: 90 * 24
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
  @spec limit(String.t(), atom()) :: non_neg_integer() | :unlimited | nil
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
