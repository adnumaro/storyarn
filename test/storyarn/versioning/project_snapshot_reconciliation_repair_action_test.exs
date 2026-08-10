defmodule Storyarn.Versioning.ProjectSnapshotReconciliationRepairActionTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRepairAction
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun

  @namespace String.duplicate("a", 64)
  @other_namespace String.duplicate("b", 64)
  @migration_path Path.expand(
                    "../../../priv/repo/migrations/20260809120000_create_project_snapshot_reconciliation_repairs.exs",
                    __DIR__
                  )

  test "insert guard binds a pristine action to completed immutable evidence" do
    {run, finding} = completed_finding!()
    attrs = action_attrs(run, finding)

    assert_evidence_rejected(%{attrs | subject_fingerprint: String.duplicate("c", 64)})
    assert_evidence_rejected(%{attrs | provider_namespace_fingerprint_snapshot: @other_namespace})
    assert_evidence_rejected(%{attrs | action_kind: "mark_missing"})

    {pending_run, pending_finding} = pending_finding!()
    assert_evidence_rejected(action_attrs(pending_run, pending_finding))

    action = insert_action!(attrs)

    assert action.source_finding_id == finding.id
    assert action.contract_version == 1
    assert action.provider_namespace_fingerprint_snapshot == @namespace
    assert action.subject_fingerprint == finding.fingerprint
    assert action.action_kind == "report_only"
    assert action.status == "pending"
    assert action.attempt_count == 0
    assert action.inserted_at == action.updated_at

    assert {:error, duplicate} =
             %ProjectSnapshotReconciliationRepairAction{}
             |> ProjectSnapshotReconciliationRepairAction.plan_changeset(attrs)
             |> Repo.insert()

    assert "has already been taken" in errors_on(duplicate).source_finding_id
  end

  test "schema and database exclude temporary cleanup repair authority" do
    {run, finding} = completed_finding!()

    changeset =
      ProjectSnapshotReconciliationRepairAction.plan_changeset(
        %ProjectSnapshotReconciliationRepairAction{},
        action_attrs(run, finding, "cleanup_temporary")
      )

    refute changeset.valid?
    assert "is invalid" in errors_on(changeset).action_kind

    assert_evidence_rejected(action_attrs(run, finding, "replay_cleanup"))
  end

  test "a recurring fingerprint in a later run receives its own one-shot action" do
    fingerprint = unique_fingerprint()
    {first_run, first_finding} = completed_finding!(fingerprint: fingerprint)
    {second_run, second_finding} = completed_finding!(fingerprint: fingerprint)

    first = insert_action!(action_attrs(first_run, first_finding))
    second = insert_action!(action_attrs(second_run, second_finding))

    assert first.source_finding_id != second.source_finding_id
    assert first.subject_fingerprint == second.subject_fingerprint
    assert first.contract_version == second.contract_version
  end

  test "repair evidence fields are category-complete, positive, and immutable" do
    run = insert_run!()

    invalid =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        finding_attrs(run, accounting_generation: 0)
      )

    refute invalid.valid?
    assert "must be greater than 0" in errors_on(invalid).accounting_generation

    assert_raise Postgrex.Error,
                 ~r/project_snapshot_reconciliation_findings_repair_evidence/,
                 fn ->
                   Repo.transaction(fn ->
                     Repo.query!(
                       """
                       INSERT INTO project_snapshot_reconciliation_findings
                         (run_id, fingerprint, category, severity, accounting_generation,
                          details, inserted_at)
                       VALUES ($1, $2, 'ambiguous_storage_object', 'warning', 0,
                               '{}'::jsonb, $3)
                       """,
                       [run.id, unique_fingerprint(), TimeHelpers.now()]
                     )
                   end)
                 end

    ready_without_accounting =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        finding_attrs(run, category: "ready_object_missing")
      )

    refute ready_without_accounting.valid?
    assert "can't be blank" in errors_on(ready_without_accounting).accounting_generation

    assert_raise Postgrex.Error,
                 ~r/project_snapshot_reconciliation_findings_repair_evidence/,
                 fn ->
                   Repo.transaction(fn ->
                     Repo.query!(
                       """
                       INSERT INTO project_snapshot_reconciliation_findings
                         (run_id, fingerprint, category, severity, details, inserted_at)
                       VALUES ($1, $2, 'ready_object_missing', 'critical', '{}'::jsonb, $3)
                       """,
                       [run.id, unique_fingerprint(), TimeHelpers.now()]
                     )
                   end)
                 end

    finding =
      %ProjectSnapshotReconciliationFinding{}
      |> ProjectSnapshotReconciliationFinding.create_changeset(
        finding_attrs(run, accounting_generation: 1, cleanup_intent_id_snapshot: 1)
      )
      |> Repo.insert!()

    assert finding.accounting_generation == 1
    assert finding.cleanup_intent_id_snapshot == 1

    assert_raise Postgrex.Error, ~r/snapshot reconciliation findings are immutable/, fn ->
      Repo.transaction(fn ->
        finding
        |> Ecto.Changeset.change(accounting_generation: 2)
        |> Repo.update!()
      end)
    end
  end

  test "attempt and terminal transitions are exact and terminal evidence is immutable" do
    {run, finding} = completed_finding!()
    action = insert_action!(action_attrs(run, finding))

    premature =
      ProjectSnapshotReconciliationRepairAction.outcome_changeset(action, %{
        status: "manual",
        result_code: "manual_review"
      })

    refute premature.valid?
    assert "must be recorded before an outcome" in errors_on(premature).attempt_count

    assert_raise Postgrex.Error,
                 ~r/pending snapshot reconciliation repair actions may only record one attempt/,
                 fn ->
                   Repo.transaction(fn ->
                     Repo.query!(
                       """
                       UPDATE project_snapshot_reconciliation_repair_actions
                       SET attempt_count = attempt_count + 2
                       WHERE id = $1
                       """,
                       [action.id]
                     )
                   end)
                 end

    attempted =
      action
      |> ProjectSnapshotReconciliationRepairAction.attempt_changeset()
      |> Repo.update!()

    assert attempted.status == "pending"
    assert attempted.attempt_count == 1

    finished =
      attempted
      |> ProjectSnapshotReconciliationRepairAction.outcome_changeset(%{
        status: "manual",
        result_code: "manual_review"
      })
      |> Repo.update!()

    assert finished.status == "manual"
    assert finished.attempt_count == 1
    assert %DateTime{} = finished.finished_at

    assert_raise Postgrex.Error, ~r/terminal snapshot reconciliation repair actions are immutable/, fn ->
      Repo.transaction(fn ->
        Repo.query!(
          "UPDATE project_snapshot_reconciliation_repair_actions SET result_code = 'rewritten' WHERE id = $1",
          [finished.id]
        )
      end)
    end
  end

  test "terminal timestamps cannot precede the recorded attempt or exceed updated_at" do
    {run, finding} = completed_finding!()
    action = insert_action!(action_attrs(run, finding))

    Repo.query!(
      """
      UPDATE project_snapshot_reconciliation_repair_actions
      SET attempt_count = attempt_count + 1,
          updated_at = updated_at + interval '10 seconds'
      WHERE id = $1
      """,
      [action.id]
    )

    assert_raise Postgrex.Error,
                 ~r/snapshot reconciliation repair outcomes require a recorded attempt/,
                 fn ->
                   Repo.transaction(fn ->
                     Repo.query!(
                       """
                       UPDATE project_snapshot_reconciliation_repair_actions
                       SET status = 'manual', result_code = 'manual_review',
                           finished_at = inserted_at + interval '5 seconds'
                       WHERE id = $1
                       """,
                       [action.id]
                     )
                   end)
                 end

    assert_raise Postgrex.Error,
                 ~r/snapshot reconciliation repair outcomes require a recorded attempt/,
                 fn ->
                   Repo.transaction(fn ->
                     Repo.query!(
                       """
                       UPDATE project_snapshot_reconciliation_repair_actions
                       SET status = 'manual', result_code = 'manual_review',
                           finished_at = updated_at + interval '1 second'
                       WHERE id = $1
                       """,
                       [action.id]
                     )
                   end)
                 end

    Repo.query!(
      """
      UPDATE project_snapshot_reconciliation_repair_actions
      SET status = 'manual', result_code = 'manual_review', finished_at = updated_at
      WHERE id = $1
      """,
      [action.id]
    )

    finished = Repo.get!(ProjectSnapshotReconciliationRepairAction, action.id)
    assert finished.status == "manual"
    assert finished.finished_at == finished.updated_at
  end

  test "incremental namespace constraints are validated and preserve compensation ownership" do
    constraint_names = [
      "project_snapshot_reconciliation_findings_repair_evidence",
      "storage_cleanup_requests_provider_namespace",
      "snapshot_cleanup_intents_provider_namespace",
      "storage_cleanup_requests_owner"
    ]

    assert Enum.all?(constraint_names, fn constraint_name ->
             [[true]] =
               Repo.query!(
                 "SELECT convalidated FROM pg_constraint WHERE conname = $1",
                 [constraint_name]
               ).rows

             true
           end)

    nullability =
      Repo.query!("""
      SELECT relation.relname, attribute.attnotnull
      FROM pg_attribute AS attribute
      JOIN pg_class AS relation ON relation.oid = attribute.attrelid
      WHERE relation.relname IN ('storage_cleanup_requests', 'snapshot_cleanup_intents')
        AND attribute.attname = 'provider_namespace_fingerprint'
      """).rows

    assert MapSet.new(nullability) ==
             MapSet.new([
               ["storage_cleanup_requests", false],
               ["snapshot_cleanup_intents", true]
             ])

    insert_cleanup_request!("storage_compensation", nil, nil)
    insert_cleanup_request!("snapshot_lifecycle", test_uuid(), @namespace)

    assert_cleanup_namespace_rejected("storage_compensation", nil, @namespace)
    assert_cleanup_namespace_rejected("snapshot_lifecycle", test_uuid(), nil)
    assert_cleanup_namespace_rejected("snapshot_lifecycle", test_uuid(), "not-a-fingerprint")

    trigger_names =
      Repo.query!("""
      SELECT trigger.tgname
      FROM pg_trigger AS trigger
      WHERE NOT trigger.tgisinternal
        AND trigger.tgname IN (
          'snapshot_cleanup_intents_provider_namespace_guard',
          'storage_cleanup_requests_provider_namespace_guard'
        )
      ORDER BY trigger.tgname
      """).rows

    assert trigger_names == [
             ["snapshot_cleanup_intents_provider_namespace_guard"],
             ["storage_cleanup_requests_provider_namespace_guard"]
           ]
  end

  test "snapshot cleanup request provider namespace is immutable" do
    owner_token = test_uuid()
    %{rows: [[request_id]]} = insert_cleanup_request!("snapshot_lifecycle", owner_token, @namespace)

    assert_raise Postgrex.Error, ~r/snapshot cleanup provider namespace is immutable/, fn ->
      Repo.transaction(fn ->
        Repo.query!(
          """
          UPDATE storage_cleanup_requests
          SET provider_namespace_fingerprint = $2, updated_at = updated_at + interval '1 second'
          WHERE id = $1
          """,
          [request_id, @other_namespace]
        )
      end)
    end

    assert Repo.one(
             from(request in "storage_cleanup_requests",
               where: request.id == ^request_id,
               select: request.provider_namespace_fingerprint
             )
           ) == @namespace
  end

  test "namespace rollout is reset-only and cannot invent historical ownership" do
    source = File.read!(@migration_path)

    assert source =~
             "LOCK TABLE storage_cleanup_requests, snapshot_cleanup_intents"

    assert source =~ "IF EXISTS (SELECT 1 FROM snapshot_cleanup_intents)"
    assert source =~ "WHERE owner_kind = 'snapshot_lifecycle'"

    assert source =~
             "snapshot cleanup provider namespace migration requires reset state"

    refute source =~ "UPDATE snapshot_cleanup_intents"
    refute source =~ "UPDATE storage_cleanup_requests"
  end

  defp pending_finding!(overrides \\ []) do
    run = insert_run!()
    {run, insert_finding!(run, overrides)}
  end

  defp completed_finding!(overrides \\ []) do
    {run, finding} = pending_finding!(overrides)
    {complete_run!(run), finding}
  end

  defp insert_run! do
    %ProjectSnapshotReconciliationRun{}
    |> ProjectSnapshotReconciliationRun.create_changeset(%{
      provider_namespace_fingerprint: @namespace,
      snapshot_high_watermark: 0,
      reservation_high_watermark: 0,
      claim_sequence_high_watermark: 0,
      cleanup_intent_high_watermark: 0,
      max_objects_per_step: 1,
      max_bytes_per_step: 128 * 1024 * 1024,
      max_findings: 10,
      provider_page_size: 10,
      max_provider_objects: 10,
      max_provider_bytes: 1024 * 1024 * 1024
    })
    |> Repo.insert!()
  end

  defp insert_finding!(run, overrides) do
    %ProjectSnapshotReconciliationFinding{}
    |> ProjectSnapshotReconciliationFinding.create_changeset(finding_attrs(run, overrides))
    |> Repo.insert!()
  end

  defp finding_attrs(run, overrides) do
    Map.merge(
      %{
        run_id: run.id,
        fingerprint: unique_fingerprint(),
        category: "ambiguous_storage_object",
        severity: "warning",
        details: %{}
      },
      Map.new(overrides)
    )
  end

  defp complete_run!(run) do
    Enum.reduce(
      ["stale_reservations", "publication_claims", "cleanup_intents", "provider_objects", "completed"],
      run,
      &advance_run!(&2, &1)
    )
  end

  defp advance_run!(run, phase) do
    now = TimeHelpers.now()
    completed? = phase == "completed"

    attrs = %{
      status: if(completed?, do: "completed", else: "running"),
      phase: phase,
      snapshot_after_id: run.snapshot_after_id,
      reservation_after_id: run.reservation_after_id,
      claim_after_sequence: run.claim_after_sequence,
      cleanup_intent_after_id: run.cleanup_intent_after_id,
      provider_scan_completed: completed?,
      cursor_generation: run.cursor_generation + 1,
      inspected_snapshot_count: run.inspected_snapshot_count,
      inspected_object_count: run.inspected_object_count,
      inspected_bytes: run.inspected_bytes,
      provider_object_count: run.provider_object_count,
      provider_bytes: run.provider_bytes,
      finding_count: 1,
      started_at: run.started_at || now,
      finished_at: if(completed?, do: now)
    }

    run
    |> ProjectSnapshotReconciliationRun.progress_changeset(attrs)
    |> Repo.update!()
  end

  defp action_attrs(run, finding, action_kind \\ "report_only") do
    %{
      source_finding_id: finding.id,
      provider_namespace_fingerprint_snapshot: run.provider_namespace_fingerprint,
      subject_fingerprint: finding.fingerprint,
      action_kind: action_kind
    }
  end

  defp insert_action!(attrs) do
    %ProjectSnapshotReconciliationRepairAction{}
    |> ProjectSnapshotReconciliationRepairAction.plan_changeset(attrs)
    |> Repo.insert!()
  end

  defp assert_evidence_rejected(attrs) do
    assert_raise Postgrex.Error, ~r/snapshot reconciliation repair action evidence is invalid/, fn ->
      Repo.transaction(fn -> insert_action!(attrs) end)
    end
  end

  defp assert_cleanup_namespace_rejected(owner_kind, owner_token, namespace) do
    assert_raise Postgrex.Error, ~r/storage_cleanup_requests_provider_namespace/, fn ->
      Repo.transaction(fn -> insert_cleanup_request!(owner_kind, owner_token, namespace) end)
    end
  end

  defp insert_cleanup_request!(owner_kind, owner_token, namespace) do
    now = TimeHelpers.now()
    encoded_owner_token = if owner_token, do: Ecto.UUID.dump!(owner_token)

    Repo.query!(
      """
      INSERT INTO storage_cleanup_requests
        (storage_keys, owner_kind, owner_token, provider_namespace_fingerprint, inserted_at, updated_at)
      VALUES ($1, $2, $3::uuid, $4, $5, $5)
      RETURNING id
      """,
      [["repair-schema-test/object"], owner_kind, encoded_owner_token, namespace, now]
    )
  end

  defp test_uuid, do: "00000000-0000-0000-0000-000000000001"

  defp unique_fingerprint do
    [:positive]
    |> System.unique_integer()
    |> Integer.to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
