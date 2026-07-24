defmodule Storyarn.Flows.FindingDismissals do
  @moduledoc """
  Dismiss/restore lifecycle for structural-analysis findings.

  All reads and writes are scoped by the caller-authorized project and flow —
  ids are never trusted from the client. Dismiss and restore are idempotent
  under concurrency: dismiss relies on the active partial unique index,
  restore on a guarded update.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.FindingDismissal
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.StructuralAnalysis.Finding
  alias Storyarn.Flows.StructuralAnalysis.Rules
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Dismisses a canonical finding occurrence for the given flow.

  The finding identity comes from a server-computed `%Finding{}` — the
  client can only select which current finding to dismiss, never author its
  content. Returns `{:ok, dismissal}`; a concurrent duplicate resolves to
  the already-active row (idempotent).
  """
  @spec dismiss(Flow.t(), Finding.t(), map()) ::
          {:ok, FindingDismissal.t()} | {:error, Ecto.Changeset.t()}
  def dismiss(%Flow{} = flow, %Finding{} = finding, attrs) do
    true = Rules.known?(finding.rule_id)

    changeset =
      FindingDismissal.create_changeset(%{
        project_id: flow.project_id,
        flow_id: flow.id,
        finding_key: finding.finding_key,
        rule_id: finding.rule_id,
        rule_version: finding.rule_version,
        evidence_fingerprint: finding.evidence_fingerprint,
        reason_code: attrs["reason_code"] || attrs[:reason_code],
        note: normalize_note(attrs["note"] || attrs[:note]),
        dismissed_by_id: attrs["dismissed_by_id"] || attrs[:dismissed_by_id]
      })

    case Repo.insert(changeset) do
      {:ok, dismissal} ->
        {:ok, dismissal}

      {:error, %Ecto.Changeset{errors: errors} = error_changeset} ->
        if Keyword.has_key?(errors, :flow_id) and active_exists?(flow, finding) do
          {:ok, fetch_active!(flow, finding)}
        else
          {:error, error_changeset}
        end
    end
  end

  @doc """
  Restores (un-dismisses) an active dismissal of the given flow.

  Idempotent: restoring an already-restored dismissal returns it unchanged.
  Returns `{:error, :not_found}` when the id does not belong to the flow.
  """
  @spec restore(Flow.t(), integer(), integer()) ::
          {:ok, FindingDismissal.t()} | {:error, :not_found}
  def restore(%Flow{} = flow, dismissal_id, restored_by_id) do
    case Repo.get_by(FindingDismissal, id: dismissal_id, flow_id: flow.id, project_id: flow.project_id) do
      nil ->
        {:error, :not_found}

      %FindingDismissal{restored_at: nil} = dismissal ->
        now = TimeHelpers.now()

        {_updated, _} =
          Repo.update_all(from(d in FindingDismissal, where: d.id == ^dismissal.id and is_nil(d.restored_at)),
            set: [restored_at: now, restored_by_id: restored_by_id, updated_at: now]
          )

        {:ok, Repo.get!(FindingDismissal, dismissal.id)}

      %FindingDismissal{} = already_restored ->
        {:ok, already_restored}
    end
  end

  @doc "Active dismissals for a flow, keyed for suppression lookups."
  @spec list_active(Flow.t()) :: [FindingDismissal.t()]
  def list_active(%Flow{} = flow) do
    Repo.all(
      from(d in FindingDismissal,
        where: d.flow_id == ^flow.id and d.project_id == ^flow.project_id and is_nil(d.restored_at),
        order_by: [asc: d.finding_key, asc: d.id],
        preload: [:dismissed_by]
      )
    )
  end

  @doc """
  Splits an analysis' findings into `{active, dismissed}` against the flow's
  active dismissals. A dismissal matches only the exact
  `finding_key + rule_version + evidence_fingerprint` occurrence.
  """
  @spec split_findings([Finding.t()], [FindingDismissal.t()]) ::
          {[Finding.t()], [{Finding.t(), FindingDismissal.t()}]}
  def split_findings(findings, active_dismissals) do
    by_identity =
      Map.new(
        active_dismissals,
        &{{&1.finding_key, &1.rule_version, &1.evidence_fingerprint}, &1}
      )

    findings
    |> Enum.reduce({[], []}, fn finding, {active, dismissed} ->
      case Map.get(by_identity, {finding.finding_key, finding.rule_version, finding.evidence_fingerprint}) do
        nil -> {[finding | active], dismissed}
        dismissal -> {active, [{finding, dismissal} | dismissed]}
      end
    end)
    |> then(fn {active, dismissed} -> {Enum.reverse(active), Enum.reverse(dismissed)} end)
  end

  defp normalize_note(nil), do: nil

  defp normalize_note(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp active_exists?(flow, finding) do
    Repo.exists?(
      from(d in FindingDismissal,
        where:
          d.flow_id == ^flow.id and d.finding_key == ^finding.finding_key and d.rule_version == ^finding.rule_version and
            d.evidence_fingerprint == ^finding.evidence_fingerprint and is_nil(d.restored_at)
      )
    )
  end

  defp fetch_active!(flow, finding) do
    Repo.one!(
      from(d in FindingDismissal,
        where:
          d.flow_id == ^flow.id and d.finding_key == ^finding.finding_key and d.rule_version == ^finding.rule_version and
            d.evidence_fingerprint == ^finding.evidence_fingerprint and is_nil(d.restored_at),
        preload: [:dismissed_by]
      )
    )
  end
end
