defmodule Storyarn.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshotReset

  @app :storyarn
  @snapshot_reset_receipts_migration 20_260_805_125_000
  @snapshot_lifecycle_migration 20_260_805_130_000
  @snapshot_lifecycle_migration_authorization_key {__MODULE__, :snapshot_lifecycle_migration_authorized}

  def migrate do
    load_app()

    for repo <- repos() do
      migrate_repo(repo)
    end
  end

  @doc false
  def ensure_project_snapshot_lifecycle_rollout_ready!(repo, opts \\ []) when is_atom(repo) and is_list(opts) do
    case repo.query(
           "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)",
           [@snapshot_lifecycle_migration]
         ) do
      {:ok, %{rows: [[true]]}} ->
        :ok

      {:ok, %{rows: [[false]]}} ->
        environment = System.fetch_env!("STORYARN_DEPLOYMENT_ENVIRONMENT")
        verification_opts = Keyword.put(opts, :repo, repo)

        ensure_snapshot_reset_runtime_started!()
        ensure_snapshot_rollout_readiness!(environment, verification_opts)

      {:error, reason} ->
        raise "Could not verify snapshot lifecycle migration state: #{inspect(reason)}"

      _invalid ->
        raise "Could not verify snapshot lifecycle migration state"
    end
  end

  @doc false
  def assert_snapshot_lifecycle_migration_authorized! do
    enforced? = Application.get_env(@app, :enforce_snapshot_lifecycle_release_gate, false)
    authorized? = snapshot_lifecycle_migration_authorized?()

    if enforced? and not authorized? do
      raise "Snapshot lifecycle migration must run through Storyarn.Release.migrate/0 after rollout verification"
    end

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp migrate_repo(Storyarn.Repo = repo) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn started_repo ->
        _applied = Ecto.Migrator.run(started_repo, :up, to: @snapshot_reset_receipts_migration)
        :ok = ensure_project_snapshot_lifecycle_rollout_ready!(started_repo)

        _lifecycle =
          with_snapshot_lifecycle_migration_authorization(fn ->
            Ecto.Migrator.run(started_repo, :up, to: @snapshot_lifecycle_migration)
          end)

        Ecto.Migrator.run(started_repo, :up, all: true)
      end)

    :ok
  end

  defp migrate_repo(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    :ok
  end

  @doc """
  Applies only the migrations required to record audited snapshot reset receipts.

  The lifecycle migration remains blocked until every workspace has a completed
  immutable receipt.
  """
  def prepare_project_snapshot_reset_schema do
    load_app()

    with_repo(fn repo ->
      ensure_snapshot_lifecycle_not_applied!(repo)
      _versions = Ecto.Migrator.run(repo, :up, to: @snapshot_reset_receipts_migration)
      ensure_snapshot_reset_receipt_schema!(repo)
      IO.puts("Snapshot reset receipt schema is ready; lifecycle migration remains unapplied")
      :ok
    end)
  end

  @doc """
  Persists a dry-run project snapshot reset plan from a production release.

  The application release must be fenced from serving traffic and the canonical
  snapshot lifecycle migration must not have been applied.
  """
  def prepare_project_snapshot_reset(environment, workspace_id, plan_path)
      when is_binary(environment) and is_integer(workspace_id) and is_binary(plan_path) do
    load_snapshot_reset_runtime!()

    with_repo(fn repo ->
      plan = prepare_snapshot_reset!(repo, workspace_id, environment)
      persist_new_snapshot_reset_plan!(plan_path, plan)
      print_snapshot_reset_plan(plan_path, plan, "DRY RUN")
      plan
    end)
  end

  @doc """
  Executes or resumes a release snapshot reset from its immutable audit plan.

  `authorization_path` must be an owner-only regular file containing the
  one-use secret whose SHA-256 is configured in
  `STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256`.
  """
  def execute_project_snapshot_reset(environment, workspace_id, plan_path, digest, authorization_path)
      when is_binary(environment) and is_integer(workspace_id) and is_binary(plan_path) and is_binary(digest) and
             is_binary(authorization_path) do
    load_snapshot_reset_runtime!()
    authorization = read_snapshot_reset_authorization!(authorization_path)

    with_repo(fn repo ->
      execute_snapshot_reset!(
        repo,
        environment,
        workspace_id,
        plan_path,
        digest,
        authorization
      )
    end)
  end

  @doc """
  Persists the environment-global provider snapshot reset plan.

  Every workspace reset receipt must already be current and both versioning
  tables must be globally empty. The plan contains only strict snapshot-root
  objects discovered by a bounded scan of `projects/`.
  """
  def prepare_project_snapshot_provider_reset(environment, plan_path, max_scanned_objects)
      when is_binary(environment) and is_binary(plan_path) and is_integer(max_scanned_objects) do
    load_snapshot_reset_runtime!()

    with_repo(fn repo ->
      plan = prepare_snapshot_provider_reset!(repo, environment, max_scanned_objects)
      persist_new_snapshot_reset_plan!(plan_path, plan)
      print_snapshot_provider_reset_plan(plan_path, plan, "DRY RUN")
      plan
    end)
  end

  @doc "Executes or resumes the environment-global provider snapshot reset plan."
  def execute_project_snapshot_provider_reset(environment, plan_path, digest, authorization_path)
      when is_binary(environment) and is_binary(plan_path) and is_binary(digest) and is_binary(authorization_path) do
    load_snapshot_reset_runtime!()
    authorization = read_snapshot_reset_authorization!(authorization_path)

    with_repo(fn repo ->
      plan = read_snapshot_reset_plan!(plan_path)
      validate_snapshot_provider_reset_scope!(plan, environment)
      checkpoint = &ProjectSnapshotReset.write_plan_file(plan_path, &1)

      plan
      |> ProjectSnapshotReset.execute(digest,
        repo: repo,
        authorization: authorization,
        checkpoint: checkpoint
      )
      |> handle_snapshot_provider_reset_result!(plan_path)
    end)
  end

  @doc "Verifies the database and immutable receipt boundary for lifecycle rollout."
  def verify_project_snapshot_reset_rollout(environment) when is_binary(environment) do
    load_app()

    with_repo(fn repo ->
      case ProjectSnapshotReset.verify_rollout_readiness(environment, repo: repo) do
        :ok -> :ok
        {:error, reason} -> raise "Snapshot reset rollout is not ready: #{inspect(reason)}"
      end
    end)
  end

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

  defp prepare_snapshot_reset!(repo, workspace_id, environment) do
    case ProjectSnapshotReset.prepare(workspace_id, environment, repo: repo) do
      {:ok, plan} -> plan
      {:error, reason} -> raise "Could not prepare snapshot reset: #{inspect(reason)}"
    end
  end

  defp prepare_snapshot_provider_reset!(repo, environment, max_scanned_objects) do
    case ProjectSnapshotReset.prepare_provider(environment,
           repo: repo,
           max_scanned_objects: max_scanned_objects
         ) do
      {:ok, plan} -> plan
      {:error, reason} -> raise "Could not prepare provider snapshot reset: #{inspect(reason)}"
    end
  end

  defp persist_new_snapshot_reset_plan!(plan_path, plan) do
    case ProjectSnapshotReset.write_new_plan_file(plan_path, plan) do
      :ok -> :ok
      {:error, reason} -> raise "Could not persist snapshot reset plan: #{inspect(reason)}"
    end
  end

  defp execute_snapshot_reset!(repo, environment, workspace_id, plan_path, confirmation_digest, authorization) do
    plan = read_snapshot_reset_plan!(plan_path)
    validate_snapshot_reset_scope!(plan, environment, workspace_id)
    checkpoint = &ProjectSnapshotReset.write_plan_file(plan_path, &1)

    plan
    |> ProjectSnapshotReset.execute(confirmation_digest,
      repo: repo,
      authorization: authorization,
      checkpoint: checkpoint
    )
    |> handle_snapshot_reset_result!(plan_path)
  end

  defp validate_snapshot_reset_scope!(
         %{"environment" => environment, "workspace_id" => workspace_id},
         environment,
         workspace_id
       ), do: :ok

  defp validate_snapshot_reset_scope!(_plan, _environment, _workspace_id) do
    raise "The snapshot reset plan does not match the explicit environment and workspace scope"
  end

  defp validate_snapshot_provider_reset_scope!(%{"scope" => "provider", "environment" => environment}, environment),
    do: :ok

  defp validate_snapshot_provider_reset_scope!(_plan, _environment) do
    raise "The provider snapshot reset plan does not match the explicit environment scope"
  end

  defp handle_snapshot_reset_result!({:ok, completed}, plan_path) do
    print_snapshot_reset_plan(plan_path, completed, "COMPLETED")
    completed
  end

  defp handle_snapshot_reset_result!({:error, reason, failed}, plan_path) do
    persist_failed_snapshot_reset_plan!(plan_path, failed, reason)
  end

  defp handle_snapshot_provider_reset_result!({:ok, completed}, plan_path) do
    print_snapshot_provider_reset_plan(plan_path, completed, "COMPLETED")
    completed
  end

  defp handle_snapshot_provider_reset_result!({:error, reason, failed}, plan_path) do
    persist_failed_snapshot_reset_plan!(plan_path, failed, reason)
  end

  defp persist_failed_snapshot_reset_plan!(plan_path, failed, reason) do
    case ProjectSnapshotReset.write_plan_file(plan_path, failed) do
      :ok ->
        raise "Snapshot reset stopped safely: #{inspect(reason)}; retry with the same plan"

      {:error, checkpoint_reason} ->
        raise "Snapshot reset stopped with #{inspect(reason)} and its final checkpoint failed: #{inspect(checkpoint_reason)}"
    end
  end

  defp with_repo(fun) do
    {:ok, result, _apps} = Ecto.Migrator.with_repo(Storyarn.Repo, fun)
    result
  end

  defp load_snapshot_reset_runtime! do
    load_app()
    ensure_snapshot_reset_runtime_started!()
  end

  defp ensure_snapshot_reset_runtime_started! do
    Enum.each([:req, :ex_aws], &ensure_snapshot_reset_application_started!/1)
  end

  defp ensure_snapshot_rollout_readiness!(environment, opts) do
    case ProjectSnapshotReset.verify_rollout_readiness(environment, opts) do
      :ok ->
        :ok

      {:error, :snapshot_reset_rollout_provider_receipt_missing} ->
        case ProjectSnapshotReset.bootstrap_pristine_provider_receipt(environment, opts) do
          :ok -> :ok
          {:error, reason} -> raise "Snapshot lifecycle rollout is not ready: #{inspect(reason)}"
          _invalid -> raise "Snapshot lifecycle rollout bootstrap returned an invalid response"
        end

      {:error, reason} ->
        raise "Snapshot lifecycle rollout is not ready: #{inspect(reason)}"

      _invalid ->
        raise "Snapshot lifecycle rollout readiness returned an invalid response"
    end
  end

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

  # Ecto.Migrator executes each migration in a linked Task rather than in the
  # process that called `run/3`. Tasks carry their documented `$callers` chain,
  # so the migration can inherit this narrowly scoped authorization without a
  # VM-global flag that could survive a killed release process.
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

  defp ensure_snapshot_reset_application_started!(application) do
    case Application.ensure_all_started(application) do
      {:ok, _applications} ->
        :ok

      {:error, reason} ->
        raise "Could not start snapshot reset application #{application}: #{inspect(reason)}"
    end
  end

  defp ensure_snapshot_lifecycle_not_applied!(repo) do
    case repo.query("SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version >= $1)", [
           @snapshot_lifecycle_migration
         ]) do
      {:ok, %{rows: [[false]]}} -> :ok
      {:ok, %{rows: [[true]]}} -> raise "Snapshot lifecycle migration is already applied"
      {:error, reason} -> raise "Could not verify snapshot lifecycle migration state: #{inspect(reason)}"
      _invalid -> raise "Could not verify snapshot lifecycle migration state"
    end
  end

  defp ensure_snapshot_reset_receipt_schema!(repo) do
    case repo.query(
           """
           SELECT
             to_regclass('public.project_snapshot_reset_receipts') IS NOT NULL AND
             to_regclass('public.project_snapshot_provider_reset_receipts') IS NOT NULL AND
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)
           """,
           [@snapshot_reset_receipts_migration]
         ) do
      {:ok, %{rows: [[true]]}} -> :ok
      {:ok, _result} -> raise "Snapshot reset receipt migration did not create its schema"
      {:error, reason} -> raise "Could not verify snapshot reset receipt schema: #{inspect(reason)}"
    end
  end

  defp read_snapshot_reset_plan!(path) do
    case ProjectSnapshotReset.read_plan_file(path) do
      {:ok, plan} -> plan
      {:error, reason} -> raise "Could not read a valid snapshot reset plan: #{inspect(reason)}"
    end
  end

  defp read_snapshot_reset_authorization!(path) do
    case ProjectSnapshotReset.read_authorization_file(path) do
      {:ok, authorization} ->
        authorization

      {:error, :unsafe_snapshot_reset_authorization_file} ->
        raise "Snapshot reset authorization must be an owner-only regular file containing a 32-512 character token"
    end
  end

  defp print_snapshot_reset_plan(path, plan, label) do
    IO.puts("Snapshot reset #{label}")
    IO.puts("Environment: #{plan["environment"]}")
    IO.puts("Storage namespace: #{plan["storage_namespace_fingerprint"]}")
    IO.puts("Workspace: #{plan["workspace_id"]}")
    IO.puts("Snapshot rows: #{length(plan["snapshot_row_ids"])}")
    IO.puts("Entity-version rows: #{length(plan["entity_version_row_ids"])}")
    IO.puts("Storage objects: #{length(plan["objects"])}")
    IO.puts("Storage bytes: #{Enum.sum(Enum.map(plan["objects"], & &1["size"]))}")
    IO.puts("Remaining objects: #{length(plan["remaining_storage_keys"])}")
    IO.puts("Inventory digest: #{plan["inventory_digest"]}")
    IO.puts("Audit plan: #{Path.expand(path)}")
  end

  defp print_snapshot_provider_reset_plan(path, plan, label) do
    IO.puts("Provider snapshot reset #{label}")
    IO.puts("Environment: #{plan["environment"]}")
    IO.puts("Storage namespace: #{plan["storage_namespace_fingerprint"]}")
    IO.puts("Workspace receipt revisions: #{length(plan["workspace_receipt_ids"])}")
    IO.puts("Storage objects: #{length(plan["objects"])}")
    IO.puts("Provider objects scanned: #{plan["scanned_object_count"]}/#{plan["max_scanned_objects"]}")
    IO.puts("Storage bytes: #{Enum.sum(Enum.map(plan["objects"], & &1["size"]))}")
    IO.puts("Remaining objects: #{length(plan["remaining_storage_keys"])}")
    IO.puts("Inventory digest: #{plan["inventory_digest"]}")
    IO.puts("Audit plan: #{Path.expand(path)}")
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
