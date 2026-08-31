defmodule Mix.Tasks.Storyarn.Ownership.Audit do
  @shortdoc "Checks Project and Workspace owner-membership integrity"

  @moduledoc """
  Runs the read-only ENG-108 ownership-integrity deploy preflight.

      mix storyarn.ownership.audit

  The task exits successfully only when every Project and Workspace has exactly
  one `owner` membership and that membership belongs to its canonical
  `owner_id`. It starts only Ecto, Postgrex and `Storyarn.Repo`; it never starts
  `Storyarn.Application`, Oban or the endpoint, and it never repairs data. It
  also does not load `config/runtime.exs`. Production deploys run the audit
  automatically through `/app/bin/migrate`; the release RPC documented in
  `docs/reference/ownership-integrity-preflight.md` remains available for
  ad-hoc diagnosis.
  """

  use Mix.Task

  alias Storyarn.Architecture.OwnershipIntegrityAudit
  alias Storyarn.Repo

  @runtime_applications [:ecto_sql, :postgrex]

  @impl Mix.Task
  def run([]) do
    ensure_runtime_started!()

    case OwnershipIntegrityAudit.audit() do
      {:ok, []} ->
        Mix.shell().info("Ownership integrity preflight passed (0 findings).")

      {:ok, findings} ->
        Enum.each(findings, &print_finding/1)
        Mix.raise("Ownership integrity preflight failed with #{length(findings)} finding(s)")

      {:error, reason} ->
        Mix.raise("Ownership integrity preflight could not query the database: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix storyarn.ownership.audit")

  @doc false
  @spec runtime_applications() :: [atom()]
  def runtime_applications, do: @runtime_applications

  defp print_finding(finding) do
    Mix.shell().error(
      "#{finding.aggregate} #{finding.aggregate_id}: " <>
        "owner_id=#{inspect(finding.canonical_owner_id)} " <>
        "owner_memberships=#{inspect(finding.owner_membership_user_ids)}"
    )
  end

  defp ensure_runtime_started! do
    Enum.each(@runtime_applications, &ensure_application_started!/1)
    ensure_repo_started!()
  end

  defp ensure_application_started!(application) do
    case Application.ensure_all_started(application) do
      {:ok, _started} -> :ok
      {:error, reason} -> Mix.raise("Could not start #{application}: #{inspect(reason)}")
    end
  end

  defp ensure_repo_started! do
    case Process.whereis(Repo) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case Repo.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> Mix.raise("Could not start Storyarn.Repo: #{inspect(reason)}")
        end
    end
  end
end
