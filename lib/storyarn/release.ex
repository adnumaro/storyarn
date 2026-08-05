defmodule Storyarn.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Storyarn.Versioning.ProjectSnapshotReset

  @app :storyarn
  @max_snapshot_reset_authorization_bytes 512
  @snapshot_reset_receipts_migration 20_260_805_125_000
  @snapshot_lifecycle_migration 20_260_805_130_000

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
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
    authorization = read_owner_only_secret!(authorization_path)

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

  defp prepare_snapshot_reset!(repo, workspace_id, environment) do
    case ProjectSnapshotReset.prepare(workspace_id, environment, repo: repo) do
      {:ok, plan} -> plan
      {:error, reason} -> raise "Could not prepare snapshot reset: #{inspect(reason)}"
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

  defp handle_snapshot_reset_result!({:ok, completed}, plan_path) do
    print_snapshot_reset_plan(plan_path, completed, "COMPLETED")
    completed
  end

  defp handle_snapshot_reset_result!({:error, reason, failed}, plan_path) do
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

    Enum.each([:req, :ex_aws], &ensure_snapshot_reset_application_started!/1)
  end

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

  defp read_owner_only_secret!(path) do
    expanded = Path.expand(path)

    with {:ok, %File.Stat{type: :regular, mode: mode, size: size}} <- File.lstat(expanded),
         true <- Bitwise.band(mode, 0o077) == 0,
         true <- size > 0 and size <= @max_snapshot_reset_authorization_bytes + 1,
         {:ok, contents} <- File.read(expanded),
         secret = String.trim(contents),
         true <- String.match?(secret, ~r/\A[A-Za-z0-9_-]{32,512}\z/) do
      secret
    else
      _invalid ->
        raise "Snapshot reset authorization must be an owner-only regular file containing a 32-512 character token"
    end
  end

  defp print_snapshot_reset_plan(path, plan, label) do
    IO.puts("Snapshot reset #{label}")
    IO.puts("Environment: #{plan["environment"]}")
    IO.puts("Workspace: #{plan["workspace_id"]}")
    IO.puts("Snapshot rows: #{length(plan["snapshot_row_ids"])}")
    IO.puts("Entity-version rows: #{length(plan["entity_version_row_ids"])}")
    IO.puts("Storage objects: #{length(plan["objects"])}")
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
