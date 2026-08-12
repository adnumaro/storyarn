defmodule Storyarn.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Storyarn.Versioning

  @app :storyarn
  @snapshot_storage_accounting_migration 20_260_804_120_000
  @snapshot_lifecycle_migration 20_260_805_130_000
  @snapshot_v2_cutover_barrier_migration 20_260_810_130_000
  @snapshot_v2_only_migration 20_260_811_180_000
  # Frozen migrations consume this process-local key directly so they can
  # enforce the release gate without calling application code. Keep the atom
  # stable even if this module or its helper functions are renamed.
  @snapshot_lifecycle_migration_authorization_key :storyarn_snapshot_cutover_authorized_v1

  def migrate do
    load_app()

    for repo <- repos() do
      migrate_repo(repo)
    end
  end

  @doc false
  def assert_snapshot_lifecycle_migration_authorized! do
    enforced? = Application.get_env(@app, :enforce_snapshot_lifecycle_release_gate, false)
    authorized? = snapshot_lifecycle_migration_authorized?()

    if enforced? and not authorized? do
      raise "Snapshot lifecycle migration must run through Storyarn.Release.migrate/0 after the v2-only cutover preflight"
    end

    :ok
  end

  @doc false
  def ensure_project_snapshot_v2_cutover_barriers!(repo, prefix) when is_atom(repo) do
    assert_snapshot_lifecycle_migration_authorized!()
    prefix = assert_project_snapshot_cutover_prefix!(repo, prefix)

    with_snapshot_cutover_transaction(repo, fn ->
      install_project_snapshot_v2_cutover_barriers!(repo, prefix)
    end)
  end

  defp install_project_snapshot_v2_cutover_barriers!(repo, prefix) do
    snapshots = qualified_snapshot_cutover_table(prefix, "project_snapshots")
    jobs = qualified_snapshot_cutover_table(prefix, "oban_jobs")
    entity_versions = qualified_snapshot_cutover_table(prefix, "entity_versions")

    storage_accounting_pending? =
      not snapshot_migration_applied_in_prefix?(
        repo,
        prefix,
        @snapshot_storage_accounting_migration
      )

    lock_tables =
      if storage_accounting_pending?,
        do: [snapshots, jobs, entity_versions],
        else: [snapshots, jobs]

    repo.query!("LOCK TABLE #{Enum.join(lock_tables, ", ")} IN ACCESS EXCLUSIVE MODE", [])

    case repo.query!(
           """
           SELECT
             EXISTS (SELECT 1 FROM #{snapshots}) OR
             EXISTS (
               SELECT 1
               FROM #{jobs}
               WHERE worker IN (
                 'Storyarn.Workers.BuildProjectSnapshotWorker',
                 'Storyarn.Workers.DailySnapshotWorker',
                 'Storyarn.Workers.SnapshotRetentionWorker',
                 'Storyarn.Workers.RestoreProjectWorker',
                 'Storyarn.Workers.RecoverProjectWorker'
               )
               AND state IN ('available', 'scheduled', 'executing', 'retryable')
             )
           """,
           []
         ).rows do
      [[false]] -> :ok
      [[true]] -> raise_snapshot_cutover_not_quiescent!()
      invalid -> raise "Invalid snapshot cutover barrier precondition: #{inspect(invalid)}"
    end

    storage_accounting_pending? =
      not snapshot_migration_applied_in_prefix?(
        repo,
        prefix,
        @snapshot_storage_accounting_migration
      )

    if storage_accounting_pending? do
      assert_entity_versions_empty!(repo, entity_versions)

      ensure_snapshot_cutover_constraint!(
        repo,
        prefix,
        "entity_versions",
        "entity_versions_cutover_quiescent",
        "CHECK (FALSE)"
      )
    end

    ensure_snapshot_cutover_constraint!(
      repo,
      prefix,
      "project_snapshots",
      "project_snapshots_cutover_quiescent",
      "CHECK (FALSE)"
    )

    ensure_snapshot_cutover_constraint!(
      repo,
      prefix,
      "oban_jobs",
      "oban_jobs_snapshot_cutover_quiescent",
      """
      CHECK (
        state NOT IN ('available', 'scheduled', 'executing', 'retryable') OR
        worker NOT IN (
          'Storyarn.Workers.BuildProjectSnapshotWorker',
          'Storyarn.Workers.DailySnapshotWorker',
          'Storyarn.Workers.SnapshotRetentionWorker',
          'Storyarn.Workers.RestoreProjectWorker',
          'Storyarn.Workers.RecoverProjectWorker'
        )
      )
      """
    )

    :ok
  end

  def rollback(repo, version) do
    load_app()
    rollback_repo(repo, version)
  end

  defp migrate_repo(Storyarn.Repo = repo) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn started_repo ->
        run_project_snapshot_migrations(started_repo, fn ->
          Ecto.Migrator.run(started_repo, :up, all: true)
        end)
      end)

    :ok
  end

  defp migrate_repo(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    :ok
  end

  defp rollback_repo(Storyarn.Repo = repo, version) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn started_repo ->
        with_snapshot_lifecycle_migration_authorization(fn ->
          Ecto.Migrator.run(started_repo, :down, to: version)
        end)
      end)

    :ok
  end

  defp rollback_repo(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc false
  def run_project_snapshot_migrations(repo, migrate) when is_atom(repo) and is_function(migrate, 0) do
    ensure_project_snapshot_v2_cutover_ready!(repo)

    with_snapshot_lifecycle_migration_authorization(fn ->
      maybe_install_project_snapshot_v2_cutover_barriers!(repo)
      migrate.()
    end)
  end

  @doc false
  def ensure_project_snapshot_v2_cutover_ready!(repo) when is_atom(repo) do
    with {:ok, state} <- snapshot_cutover_schema_state(repo),
         {:ok, applied?} <- snapshot_v2_only_migration_applied?(repo, state.schema_migrations?),
         {:ok, storage_accounting_applied?} <-
           snapshot_storage_accounting_migration_applied?(repo, state.schema_migrations?) do
      if applied? do
        :ok
      else
        assert_no_live_legacy_snapshot_ownership!(repo, state, storage_accounting_applied?)
      end
    else
      {:error, reason} ->
        raise "Could not verify the project snapshot v2-only cutover preflight: #{inspect(reason)}"
    end
  end

  defp snapshot_cutover_schema_state(repo) do
    case repo.query(
           """
           SELECT
             to_regclass('schema_migrations') IS NOT NULL,
             to_regclass('project_snapshots') IS NOT NULL,
             to_regclass('snapshot_object_publication_claims') IS NOT NULL,
             to_regclass('workspace_storage_reservations') IS NOT NULL,
             to_regclass('snapshot_cleanup_intents') IS NOT NULL,
             to_regclass('storage_cleanup_requests') IS NOT NULL,
             to_regclass('oban_jobs') IS NOT NULL,
             to_regclass('entity_versions') IS NOT NULL
           """,
           []
         ) do
      {:ok, %{rows: [row]}} ->
        parse_snapshot_cutover_schema_state(row)

      {:ok, invalid} ->
        {:error, {:invalid_snapshot_cutover_schema_state, invalid}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_snapshot_cutover_schema_state(
         [
           schema_migrations?,
           project_snapshots?,
           publication_claims?,
           storage_reservations?,
           cleanup_intents?,
           cleanup_requests?,
           oban_jobs?,
           entity_versions?
         ] = row
       ) do
    if Enum.all?(row, &is_boolean/1) do
      {:ok,
       %{
         schema_migrations?: schema_migrations?,
         project_snapshots?: project_snapshots?,
         publication_claims?: publication_claims?,
         storage_reservations?: storage_reservations?,
         cleanup_intents?: cleanup_intents?,
         cleanup_requests?: cleanup_requests?,
         oban_jobs?: oban_jobs?,
         entity_versions?: entity_versions?
       }}
    else
      {:error, {:invalid_snapshot_cutover_schema_state, row}}
    end
  end

  defp parse_snapshot_cutover_schema_state(invalid) do
    {:error, {:invalid_snapshot_cutover_schema_state, invalid}}
  end

  defp snapshot_storage_accounting_migration_applied?(_repo, false), do: {:ok, false}

  defp snapshot_storage_accounting_migration_applied?(repo, true) do
    case repo.query(
           "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)",
           [@snapshot_storage_accounting_migration]
         ) do
      {:ok, %{rows: [[applied?]]}} when is_boolean(applied?) ->
        {:ok, applied?}

      {:ok, invalid} ->
        {:error, {:invalid_snapshot_storage_accounting_migration_state, invalid}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp snapshot_v2_only_migration_applied?(_repo, false), do: {:ok, false}

  defp snapshot_v2_only_migration_applied?(repo, true) do
    case repo.query(
           """
           SELECT
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1),
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $2),
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $3),
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $4)
           """,
           [
             @snapshot_v2_only_migration,
             @snapshot_storage_accounting_migration,
             @snapshot_lifecycle_migration,
             @snapshot_v2_cutover_barrier_migration
           ]
         ) do
      {:ok, %{rows: [history]}} ->
        parse_snapshot_cutover_migration_history(history)

      {:ok, invalid} ->
        {:error, {:invalid_snapshot_cutover_migration_state, invalid}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_snapshot_cutover_migration_history([true, true, true, true]), do: {:ok, true}

  defp parse_snapshot_cutover_migration_history([true, storage_accounting?, lifecycle?, barrier?] = history) do
    if Enum.all?(history, &is_boolean/1) do
      {:error,
       {:inconsistent_snapshot_v2_migration_history,
        storage_accounting: storage_accounting?, lifecycle: lifecycle?, barrier: barrier?}}
    else
      {:error, {:invalid_snapshot_cutover_migration_state, history}}
    end
  end

  defp parse_snapshot_cutover_migration_history([false, _, _, _] = history) do
    if Enum.all?(history, &is_boolean/1),
      do: {:ok, false},
      else: {:error, {:invalid_snapshot_cutover_migration_state, history}}
  end

  defp parse_snapshot_cutover_migration_history(invalid) do
    {:error, {:invalid_snapshot_cutover_migration_state, invalid}}
  end

  defp assert_no_live_legacy_snapshot_ownership!(repo, state, storage_accounting_applied?) do
    checks = legacy_snapshot_ownership_checks(state, storage_accounting_applied?)

    if checks == [] do
      :ok
    else
      case repo.query("SELECT NOT (#{Enum.join(checks, " OR ")})", []) do
        {:ok, %{rows: [[true]]}} ->
          :ok

        {:ok, %{rows: [[false]]}} ->
          raise "Project snapshot v2-only cutover requires an empty snapshot table, no legacy entity-version history before the storage-accounting reset, retired v1/linked ownership, and no active snapshot jobs before running any pending migration"

        {:ok, invalid} ->
          raise "Project snapshot v2-only cutover preflight returned an invalid response: #{inspect(invalid)}"

        {:error, reason} ->
          raise "Could not inspect project snapshot v2-only cutover ownership: #{inspect(reason)}"
      end
    end
  end

  defp legacy_snapshot_ownership_checks(state, storage_accounting_applied?) do
    []
    |> maybe_add_check(
      state.entity_versions? and not storage_accounting_applied?,
      "EXISTS (SELECT 1 FROM entity_versions)"
    )
    |> maybe_add_check(
      state.project_snapshots?,
      "EXISTS (SELECT 1 FROM project_snapshots)"
    )
    |> maybe_add_check(
      state.publication_claims?,
      "EXISTS (SELECT 1 FROM snapshot_object_publication_claims WHERE object_prefix ~ '/snapshots/object-sets/v1/')"
    )
    |> maybe_add_check(
      state.storage_reservations?,
      "EXISTS (SELECT 1 FROM workspace_storage_reservations WHERE kind = 'linked_to_full_conversion' OR cleanup_object_prefix ~ '/snapshots/object-sets/v1/')"
    )
    |> maybe_add_check(
      state.cleanup_intents?,
      "EXISTS (SELECT 1 FROM snapshot_cleanup_intents WHERE mode IS DISTINCT FROM 'full' OR ready_prefix ~ '/snapshots/object-sets/v1/' OR staging_prefix ~ '/snapshots/object-sets/v1/')"
    )
    |> maybe_add_check(
      state.cleanup_requests?,
      "EXISTS (SELECT 1 FROM storage_cleanup_requests AS request, unnest(request.storage_keys) AS storage_key WHERE storage_key ~ '/snapshots/object-sets/v1/' OR storage_key ~ '/storage-reservations/v1/linked-to-full-conversion/')"
    )
    |> maybe_add_check(
      state.oban_jobs?,
      "EXISTS (SELECT 1 FROM oban_jobs WHERE worker = 'Storyarn.Workers.BuildProjectSnapshotWorker' AND state IN ('available', 'scheduled', 'executing', 'retryable'))"
    )
    |> maybe_add_check(
      state.oban_jobs?,
      "EXISTS (SELECT 1 FROM oban_jobs AS job CROSS JOIN LATERAL jsonb_array_elements_text(CASE WHEN jsonb_typeof(job.args -> 'storage_keys') = 'array' THEN job.args -> 'storage_keys' ELSE '[]'::jsonb END) AS cleanup_key(storage_key) WHERE job.state IN ('available', 'scheduled', 'executing', 'retryable') AND (cleanup_key.storage_key ~ '/snapshots/object-sets/v1/' OR cleanup_key.storage_key ~ '/storage-reservations/v1/linked-to-full-conversion/'))"
    )
  end

  defp maybe_add_check(checks, true, check), do: [check | checks]
  defp maybe_add_check(checks, false, _check), do: checks

  defp ensure_snapshot_cutover_constraint!(repo, prefix, table, constraint, definition) do
    case repo.query!(
           """
           SELECT EXISTS (
             SELECT 1
             FROM pg_constraint AS constraint_row
             JOIN pg_class AS table_row ON table_row.oid = constraint_row.conrelid
             JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
             WHERE namespace_row.nspname = $1
               AND table_row.relname = $2
               AND constraint_row.conname = $3
           )
           """,
           [prefix, table, constraint]
         ).rows do
      [[true]] ->
        :ok

      [[false]] ->
        qualified_table = qualified_snapshot_cutover_table(prefix, table)
        repo.query!("ALTER TABLE #{qualified_table} ADD CONSTRAINT #{constraint} #{definition}", [])
        :ok

      invalid ->
        raise "Invalid snapshot cutover constraint state: #{inspect(invalid)}"
    end
  end

  defp raise_snapshot_cutover_not_quiescent! do
    raise "Project snapshot v2-only cutover requires an empty snapshot table and no active pre-cutover snapshot worker"
  end

  defp assert_entity_versions_empty!(repo, entity_versions) do
    case repo.query!("SELECT NOT EXISTS (SELECT 1 FROM #{entity_versions})", []).rows do
      [[true]] ->
        :ok

      [[false]] ->
        raise "Project snapshot v2-only cutover requires legacy entity-version history to be empty before the storage-accounting reset"

      invalid ->
        raise "Invalid entity-version cutover precondition: #{inspect(invalid)}"
    end
  end

  defp maybe_install_project_snapshot_v2_cutover_barriers!(repo) do
    prefix = assert_project_snapshot_cutover_prefix!(repo, nil)

    if snapshot_cutover_tables_exist?(repo, prefix) and
         not snapshot_migration_applied_in_prefix?(repo, prefix, @snapshot_v2_only_migration) do
      ensure_project_snapshot_v2_cutover_barriers!(repo, prefix)
    else
      :ok
    end
  end

  defp snapshot_cutover_tables_exist?(repo, prefix) do
    snapshots = qualified_snapshot_cutover_table(prefix, "project_snapshots")
    jobs = qualified_snapshot_cutover_table(prefix, "oban_jobs")

    case repo.query!(
           "SELECT to_regclass($1) IS NOT NULL AND to_regclass($2) IS NOT NULL",
           [snapshots, jobs]
         ).rows do
      [[exists?]] when is_boolean(exists?) -> exists?
      invalid -> raise "Invalid snapshot cutover table state: #{inspect(invalid)}"
    end
  end

  defp snapshot_migration_applied_in_prefix?(repo, prefix, version) do
    migrations = qualified_snapshot_cutover_table(prefix, "schema_migrations")

    case repo.query!(
           "SELECT to_regclass($1) IS NOT NULL",
           [migrations]
         ).rows do
      [[false]] ->
        false

      [[true]] ->
        repo.query!(
          "SELECT EXISTS (SELECT 1 FROM #{migrations} WHERE version = $1)",
          [version]
        ).rows == [[true]]

      invalid ->
        raise "Invalid snapshot cutover migration table state: #{inspect(invalid)}"
    end
  end

  defp with_snapshot_cutover_transaction(repo, fun) when is_function(fun, 0) do
    if repo.in_transaction?() do
      fun.()
    else
      transact_snapshot_cutover(repo, fun)
    end
  end

  defp transact_snapshot_cutover(repo, fun) do
    case repo.transact(fn -> {:ok, fun.()} end) do
      {:ok, result} -> result
      {:error, reason} -> raise "Could not install snapshot cutover barriers: #{inspect(reason)}"
    end
  end

  @doc false
  def assert_project_snapshot_cutover_prefix!(repo, requested_prefix) when is_atom(repo) do
    current_prefix = current_snapshot_cutover_prefix!(repo)
    requested_prefix = requested_prefix || current_prefix
    requested_prefix = validate_snapshot_cutover_prefix!(requested_prefix)

    if requested_prefix == current_prefix do
      requested_prefix
    else
      raise "Project snapshot migrations require their explicit prefix to match current_schema(); requested #{inspect(requested_prefix)}, current #{inspect(current_prefix)}"
    end
  end

  defp current_snapshot_cutover_prefix!(repo) do
    case repo.query!("SELECT current_schema()", []).rows do
      [[prefix]] -> validate_snapshot_cutover_prefix!(prefix)
      invalid -> raise "Invalid current snapshot migration prefix: #{inspect(invalid)}"
    end
  end

  defp validate_snapshot_cutover_prefix!(prefix) when is_binary(prefix) and byte_size(prefix) > 0 do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/, prefix) do
      prefix
    else
      raise "Unsafe project snapshot migration prefix: #{inspect(prefix)}"
    end
  end

  defp validate_snapshot_cutover_prefix!(invalid) do
    raise "Invalid project snapshot migration prefix: #{inspect(invalid)}"
  end

  defp qualified_snapshot_cutover_table(prefix, table), do: ~s("#{prefix}"."#{table}")

  defp with_snapshot_lifecycle_migration_authorization(fun) when is_function(fun, 0) do
    previous = Process.get(@snapshot_lifecycle_migration_authorization_key, :missing)
    Process.put(@snapshot_lifecycle_migration_authorization_key, true)

    try do
      fun.()
    after
      restore_snapshot_lifecycle_migration_authorization(previous)
    end
  end

  defp restore_snapshot_lifecycle_migration_authorization(:missing) do
    Process.delete(@snapshot_lifecycle_migration_authorization_key)
  end

  defp restore_snapshot_lifecycle_migration_authorization(previous) do
    Process.put(@snapshot_lifecycle_migration_authorization_key, previous)
  end

  # Ecto executes each migration in a linked task. The documented `$callers`
  # chain carries this narrowly scoped authorization into that task without a
  # VM-global switch that could survive a killed release process.
  defp snapshot_lifecycle_migration_authorized? do
    Process.get(@snapshot_lifecycle_migration_authorization_key, false) == true or
      Enum.any?(
        List.wrap(Process.get(:"$callers")),
        &snapshot_lifecycle_migration_authorized_caller?/1
      )
  end

  defp snapshot_lifecycle_migration_authorized_caller?(pid) when is_pid(pid) and node(pid) == node() do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, @snapshot_lifecycle_migration_authorization_key, 0) ==
          {@snapshot_lifecycle_migration_authorization_key, true}

      nil ->
        false
    end
  end

  defp snapshot_lifecycle_migration_authorized_caller?(_pid), do: false

  @doc """
  Starts the bounded, observation-only snapshot reconciliation inspection.

  The inspection is a dry-run: it persists immutable findings but never changes
  snapshots, quota records, ownership records, or provider objects. Starting it
  again while the same provider namespace has an active run returns that run.
  """
  def start_project_snapshot_reconciliation do
    load_app()

    case Versioning.start_project_snapshot_reconciliation() do
      {:ok, run} ->
        IO.puts("Snapshot reconciliation dry-run ##{run.id}")
        IO.puts("Status: #{run.status}; phase: #{run.phase}; cursor generation: #{run.cursor_generation}")

        IO.puts(
          "Multipart inventory: #{run.multipart_inventory_state}; physical inventory complete: #{run.physical_inventory_complete}"
        )

        run

      {:error, reason} ->
        raise "Could not start snapshot reconciliation dry-run: #{inspect(reason)}"
    end
  end

  @doc """
  Prints one reconciliation run and a bounded page of its immutable findings.

  Pass the last finding ID as `after_id` to fetch the next page.
  """
  def inspect_project_snapshot_reconciliation(run_id, after_id \\ 0, limit \\ 100)
      when is_integer(run_id) and run_id > 0 and is_integer(after_id) and after_id >= 0 and is_integer(limit) and
             limit > 0 do
    load_app()

    case Versioning.get_project_snapshot_reconciliation_run(run_id) do
      nil ->
        raise "Snapshot reconciliation run ##{run_id} was not found"

      run ->
        findings =
          Versioning.list_project_snapshot_reconciliation_findings(run_id,
            after_id: after_id,
            limit: min(limit, 500)
          )

        IO.puts("Snapshot reconciliation dry-run ##{run.id}")
        IO.puts("Status: #{run.status}; phase: #{run.phase}; cursor generation: #{run.cursor_generation}")
        IO.puts("Snapshots: #{run.inspected_snapshot_count}; objects: #{run.inspected_object_count}")
        IO.puts("Provider objects: #{run.provider_object_count}; findings: #{run.finding_count}")

        IO.puts(
          "Multipart inventory: #{run.multipart_inventory_state}; physical inventory complete: #{run.physical_inventory_complete}"
        )

        IO.puts("Returned findings after ##{after_id}: #{length(findings)}")

        %{run: run, findings: findings}
    end
  end

  @doc """
  Persists and enqueues one bounded page of fenced repairs from a completed
  reconciliation run.

  Pass the returned `next_after_id` to continue. Ambiguous or unsupported
  findings are recorded as manual outcomes; they are never deleted or guessed.
  """
  def repair_project_snapshot_reconciliation(run_id, after_id \\ 0, limit \\ 50)
      when is_integer(run_id) and run_id > 0 and is_integer(after_id) and after_id >= 0 and is_integer(limit) and
             limit > 0 do
    load_app()
    limit = min(limit, Versioning.project_snapshot_reconciliation_repair_page_limit())

    case Versioning.plan_project_snapshot_reconciliation_repairs(run_id,
           after_id: after_id,
           limit: limit
         ) do
      {:ok, plan} ->
        IO.puts("Planned #{length(plan.actions)} snapshot reconciliation actions")
        IO.puts("Next finding ID: #{plan.next_after_id}; complete: #{plan.complete?}")
        plan

      {:error, reason} ->
        raise "Could not plan snapshot reconciliation repairs: #{inspect(reason)}"
    end
  end

  @doc """
  Prints one bounded page of durable reconciliation repair outcomes.

  Pass the returned action ID as `after_id` to continue.
  """
  def inspect_project_snapshot_reconciliation_repairs(run_id, after_id \\ 0, limit \\ 100)
      when is_integer(run_id) and run_id > 0 and is_integer(after_id) and after_id >= 0 and is_integer(limit) and
             limit > 0 do
    load_app()
    limit = min(limit, Versioning.project_snapshot_reconciliation_repair_page_limit())

    if is_nil(Versioning.get_project_snapshot_reconciliation_run(run_id)) do
      raise "Snapshot reconciliation run ##{run_id} was not found"
    end

    actions =
      Versioning.list_project_snapshot_reconciliation_repairs(run_id,
        after_id: after_id,
        limit: limit
      )

    next_after_id = if action = List.last(actions), do: action.id, else: after_id
    complete? = length(actions) < limit

    IO.puts("Snapshot reconciliation repair outcomes for run ##{run_id}")
    IO.puts("Returned actions after ##{after_id}: #{length(actions)}")
    IO.puts("Next action ID: #{next_after_id}; complete: #{complete?}")

    %{actions: actions, complete?: complete?, next_after_id: next_after_id}
  end

  @project_roles ~w(editor viewer)
  @workspace_roles ~w(admin member viewer)

  @template_import_option_keys %{
    "description" => :description,
    "name" => :name,
    "owner_id" => :owner_id,
    "published_by_id" => :published_by_id,
    "slug" => :slug,
    "update_existing" => :update_existing,
    "verify_user_id" => :verify_user_id,
    "verify_workspace_id" => :verify_workspace_id,
    "version_notes" => :version_notes,
    "visibility" => :visibility,
    description: :description,
    name: :name,
    owner_id: :owner_id,
    published_by_id: :published_by_id,
    slug: :slug,
    update_existing: :update_existing,
    verify_user_id: :verify_user_id,
    verify_workspace_id: :verify_workspace_id,
    version_notes: :version_notes,
    visibility: :visibility
  }

  @doc """
  Create a member invitation from a release node.

  Creates an invitation record and queues the invitation email for delivery.
  The invitee must click the acceptance link to create their account and join.

  Usage from Fly SSH (uses rpc to run inside the live node):
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"project\\", 123, \\"editor\\", \\"es\\", \\"requester@example.com\\")"'
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"workspace\\", 456, \\"member\\", \\"en\\", \\"requester@example.com\\")"'
  """
  def invite_member(email, type, entity_id, role, locale \\ "en", inviter_name \\ "Storyarn")
      when is_binary(email) and type in ["project", "workspace"] do
    allowed_roles = if type == "project", do: @project_roles, else: @workspace_roles

    if role not in allowed_roles do
      raise ArgumentError,
            "Invalid role #{inspect(role)} for #{type}. Allowed: #{inspect(allowed_roles)}"
    end

    Gettext.put_locale(Storyarn.Gettext, locale)

    email = String.downcase(email)

    {context_module, entity} = invitation_config(type, entity_id)

    case context_module.create_admin_invitation(entity, email, role, inviter_name: inviter_name) do
      {:ok, _invitation} ->
        IO.puts("Invitation created and email queued for #{email} as #{role} to #{type} ##{entity_id}")

      {:error, :already_member} ->
        IO.puts("#{email} is already a member of this #{type}")

      {:error, :already_invited} ->
        IO.puts("#{email} already has a pending invitation for this #{type}")

      {:error, :limit_reached, details} ->
        IO.puts("Failed to create invitation: member limit reached (#{inspect(details)})")
        raise "Cannot create invitation: member limit reached"

      {:error, reason} ->
        IO.puts("Failed to create invitation: #{inspect(reason)}")
        raise "Cannot create invitation: #{inspect(reason)}"
    end
  end

  @doc """
  Preview a portable project template bundle from a release node.

  Usage from Fly SSH after the bundle is present on the machine:

      fly ssh console -a storyarn -C '/app/bin/storyarn rpc "Storyarn.Release.preview_template_bundle(\\"/tmp/veilbreak.storyarn-template.tar.gz\\")"'
  """
  def preview_template_bundle(path) when is_binary(path) do
    load_app()

    case Storyarn.ProjectTemplates.preview_portable_template(path) do
      {:ok, manifest} ->
        print_template_bundle_preview(path, manifest, [])
        manifest

      {:error, reason} ->
        raise "Could not read template bundle: #{inspect(reason)}"
    end
  end

  @doc """
  Import a portable project template bundle from a release node.

  `opts` must be a map with only known import options. For a public demo import,
  pass at least `visibility`, `verify_user_id`, and `verify_workspace_id`.

  Usage from Fly SSH after the bundle is present on the machine:

      fly ssh console -a storyarn -C '/app/bin/storyarn rpc "Storyarn.Release.import_template_bundle(\\"/tmp/veilbreak.storyarn-template.tar.gz\\", %{visibility: \\"public\\", verify_user_id: 123, verify_workspace_id: 456, update_existing: true})"'
  """
  def import_template_bundle(path, opts \\ %{}) when is_binary(path) and is_map(opts) do
    load_app()

    with {:ok, keyword_opts} <- template_import_options(opts),
         {:ok, manifest} <- Storyarn.ProjectTemplates.preview_portable_template(path, keyword_opts) do
      print_template_bundle_preview(path, manifest, keyword_opts)

      case Storyarn.ProjectTemplates.import_portable_template(path, keyword_opts) do
        {:ok, template} ->
          IO.puts("Imported template ##{template.id}: #{template.name}")
          IO.puts("Visibility: #{template.visibility}")
          IO.puts("Current version: #{template.current_version_id}")
          IO.puts("Editable source project: #{template.source_project_id}")
          template

        {:error, reason} ->
          raise "Could not import template bundle: #{inspect(reason)}"
      end
    else
      {:error, reason} ->
        raise "Could not import template bundle: #{inspect(reason)}"
    end
  end

  defp invitation_config("project", id) do
    {Storyarn.Projects, Storyarn.Projects.get_project!(id)}
  end

  defp invitation_config("workspace", id) do
    {Storyarn.Workspaces, Storyarn.Workspaces.get_workspace!(id)}
  end

  defp template_import_options(opts) do
    Enum.reduce_while(opts, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case Map.fetch(@template_import_option_keys, key) do
        {:ok, option_key} -> {:cont, {:ok, Keyword.put(acc, option_key, value)}}
        :error -> {:halt, {:error, {:invalid_template_import_option, key}}}
      end
    end)
  end

  defp print_template_bundle_preview(path, manifest, opts) do
    template = manifest["template"] || %{}

    IO.puts("Template bundle: #{path}")
    IO.puts("Name: #{Keyword.get(opts, :name) || template["name"]}")
    IO.puts("Slug: #{Keyword.get(opts, :slug) || template["slug"]}")
    IO.puts("Visibility: #{Keyword.get(opts, :visibility, "private")}")
    IO.puts("Verify user ID: #{Keyword.get(opts, :verify_user_id) || "missing"}")
    IO.puts("Verify workspace ID: #{Keyword.get(opts, :verify_workspace_id) || "missing"}")
    IO.puts("Assets: #{manifest["asset_count"]}")
    IO.puts("Checksum: #{manifest["checksum"]}")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
