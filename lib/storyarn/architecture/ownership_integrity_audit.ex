defmodule Storyarn.Architecture.OwnershipIntegrityAudit do
  @moduledoc """
  Read-only deploy preflight for canonical aggregate ownership.

  The audit reports Projects or Workspaces whose `owner_id` is not represented
  by exactly one matching membership with role `owner`. It does not lock,
  repair or otherwise mutate application data.
  """

  alias Storyarn.Repo

  @statement """
  WITH project_drift AS (
    SELECT
      'project'::text AS aggregate,
      project.id AS aggregate_id,
      project.owner_id AS canonical_owner_id,
      COALESCE(
        array_agg(membership.user_id ORDER BY membership.user_id, membership.id)
          FILTER (WHERE membership.role = 'owner'),
        ARRAY[]::bigint[]
      ) AS owner_membership_user_ids
    FROM projects AS project
    LEFT JOIN project_memberships AS membership
      ON membership.project_id = project.id
    GROUP BY project.id, project.owner_id
    HAVING
      count(membership.id) FILTER (WHERE membership.role = 'owner') <> 1
      OR count(membership.id) FILTER (
        WHERE membership.role = 'owner' AND membership.user_id = project.owner_id
      ) <> 1
  ),
  workspace_drift AS (
    SELECT
      'workspace'::text AS aggregate,
      workspace.id AS aggregate_id,
      workspace.owner_id AS canonical_owner_id,
      COALESCE(
        array_agg(membership.user_id ORDER BY membership.user_id, membership.id)
          FILTER (WHERE membership.role = 'owner'),
        ARRAY[]::bigint[]
      ) AS owner_membership_user_ids
    FROM workspaces AS workspace
    LEFT JOIN workspace_memberships AS membership
      ON membership.workspace_id = workspace.id
    GROUP BY workspace.id, workspace.owner_id
    HAVING
      count(membership.id) FILTER (WHERE membership.role = 'owner') <> 1
      OR count(membership.id) FILTER (
        WHERE membership.role = 'owner' AND membership.user_id = workspace.owner_id
      ) <> 1
  )
  SELECT aggregate, aggregate_id, canonical_owner_id, owner_membership_user_ids
  FROM project_drift
  UNION ALL
  SELECT aggregate, aggregate_id, canonical_owner_id, owner_membership_user_ids
  FROM workspace_drift
  ORDER BY aggregate, aggregate_id
  """

  @type aggregate :: :project | :workspace
  @type finding :: %{
          aggregate: aggregate(),
          aggregate_id: pos_integer(),
          canonical_owner_id: pos_integer() | nil,
          owner_membership_user_ids: [pos_integer()]
        }

  @spec audit(module()) :: {:ok, [finding()]} | {:error, term()}
  def audit(repo \\ Repo) do
    case repo.query(@statement, []) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &finding/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs the read-only audit and raises unless the database is clean.

  This is the fail-closed entrypoint for release RPC commands, where returning
  `{:ok, findings}` would otherwise leave the remote command successful.
  """
  @spec audit!(module()) :: :ok
  def audit!(repo \\ Repo) do
    case audit(repo) do
      {:ok, []} ->
        :ok

      {:ok, findings} ->
        raise "Ownership integrity preflight failed: #{inspect(findings)}"

      {:error, reason} ->
        raise "Ownership integrity preflight could not query the database: #{inspect(reason)}"
    end
  end

  @spec clean?([finding()]) :: boolean()
  def clean?(findings) when is_list(findings), do: findings == []

  @doc false
  @spec statement() :: String.t()
  def statement, do: @statement

  defp finding([aggregate, aggregate_id, canonical_owner_id, owner_membership_user_ids]) do
    %{
      aggregate: aggregate(aggregate),
      aggregate_id: aggregate_id,
      canonical_owner_id: canonical_owner_id,
      owner_membership_user_ids: owner_membership_user_ids
    }
  end

  defp aggregate("project"), do: :project
  defp aggregate("workspace"), do: :workspace
end
