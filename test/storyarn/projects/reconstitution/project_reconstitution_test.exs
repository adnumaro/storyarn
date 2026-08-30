defmodule Storyarn.Projects.ProjectReconstitutionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.Materializer
  alias Storyarn.Projects.ProjectReconstitution
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutor

  test "keeps every reviewed callback arity stable" do
    Code.ensure_loaded!(ProjectReconstitution)

    assert function_exported?(ProjectReconstitution, :preview_import, 2)
    assert function_exported?(ProjectReconstitution, :execute_import, 2)
    assert function_exported?(ProjectReconstitution, :execute_import, 3)
    assert function_exported?(ProjectReconstitution, :materialize_locked_import_in_transaction, 2)
    assert function_exported?(ProjectReconstitution, :materialize_locked_import_in_transaction, 3)
    assert function_exported?(ProjectReconstitution, :materialize_template, 3)
    assert function_exported?(ProjectReconstitution, :materialize_template, 4)
    assert function_exported?(ProjectReconstitution, :validate_snapshot_import, 1)
    assert function_exported?(ProjectReconstitution, :materialize_snapshot_import, 3)
    assert function_exported?(ProjectReconstitution, :materialize_snapshot_import, 4)
    assert function_exported?(ProjectReconstitution, :execute_snapshot_restore, 2)
    assert function_exported?(ProjectReconstitution, :settle_snapshot_restore_reservation, 1)
    assert function_exported?(ProjectReconstitution, :settle_snapshot_restore_reservation, 2)
  end

  test "returns import validation failures unchanged" do
    invalid_data = %{}

    assert ProjectReconstitution.preview_import(-1, invalid_data) ==
             Materializer.preview(-1, invalid_data)

    assert ProjectReconstitution.execute_import(%{}, invalid_data, sentinel: :preserved) ==
             Materializer.execute(%{}, invalid_data, sentinel: :preserved)

    assert ProjectReconstitution.materialize_locked_import_in_transaction(
             %{},
             invalid_data,
             sentinel: :preserved
           ) ==
             Materializer.materialize_locked_project_in_transaction(
               %{},
               invalid_data,
               sentinel: :preserved
             )
  end

  test "returns recovery validation failures unchanged" do
    invalid_snapshot = %{}

    assert ProjectReconstitution.validate_snapshot_import(invalid_snapshot) ==
             ProjectRecovery.validate_snapshot_import(invalid_snapshot)

    assert ProjectReconstitution.materialize_template(1, invalid_snapshot, 1, sentinel: :preserved) ==
             ProjectRecovery.materialize_template(1, invalid_snapshot, 1, sentinel: :preserved)

    assert ProjectReconstitution.materialize_snapshot_import(
             1,
             invalid_snapshot,
             1,
             sentinel: :preserved
           ) ==
             ProjectRecovery.materialize_snapshot_import(
               1,
               invalid_snapshot,
               1,
               sentinel: :preserved
             )
  end

  test "returns restore executor failures unchanged" do
    assert ProjectReconstitution.execute_snapshot_restore(:invalid, sentinel: :preserved) ==
             ProjectSnapshotRestoreExecutor.execute(:invalid, sentinel: :preserved)

    assert ProjectReconstitution.settle_snapshot_restore_reservation(
             :invalid,
             sentinel: :preserved
           ) ==
             ProjectSnapshotRestoreExecutor.settle_bound_reservation(
               :invalid,
               sentinel: :preserved
             )
  end
end
