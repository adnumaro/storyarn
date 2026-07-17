defmodule Storyarn.ProjectTemplates.Installation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Analytics
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.InstallProjectTemplateWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  require Logger

  @active_statuses ProjectTemplateInstall.active_statuses()
  @pending_failure_limit 10
  @permanent_errors ~w(
    archived
    checksum_mismatch
    incompatible_template_snapshot
    limit_reached
    missing_asset_manifest
    missing_checksum
    not_found
    unauthorized
  )a

  @spec request_template_instantiation(Scope.t(), ProjectTemplateVersion.t(), Workspace.t(), map()) ::
          {:ok, ProjectTemplateInstall.t()} | {:error, term()}
  def request_template_instantiation(
        %Scope{} = scope,
        %ProjectTemplateVersion{} = version,
        %Workspace{} = workspace,
        attrs
      ) do
    version = Repo.preload(version, [:project_template])

    with :ok <- Authorization.authorize_template_visibility(scope, version.project_template),
         {:ok, workspace, _membership} <- Workspaces.authorize(scope, workspace.id, :create_project),
         :ok <- Billing.can_create_project?(workspace) do
      name = install_name(attrs, version)
      source = install_source(attrs)
      idempotency_key = idempotency_key(scope.user.id, workspace.id, version.id, name)

      result =
        %ProjectTemplateInstall{
          project_template_version_id: version.id,
          user_id: scope.user.id,
          workspace_id: workspace.id
        }
        |> ProjectTemplateInstall.request_changeset(%{
          status: "queued",
          stage: "queued",
          project_name: name,
          source: source,
          idempotency_key: idempotency_key
        })
        |> insert_install_and_enqueue()

      case result do
        {:ok, {install, :created}} ->
          publish_requested(scope, install, version.project_template)
          {:ok, install}

        {:error, %Ecto.Changeset{} = changeset} ->
          existing_install_or_error(changeset, idempotency_key)

        error ->
          error
      end
    end
  end

  @spec perform_template_installation(integer(), keyword()) ::
          {:ok, ProjectTemplateInstall.t()} | {:error, term()}
  def perform_template_installation(install_id, opts \\ []) do
    install = get_install!(install_id)

    case install.status do
      status when status in ["completed", "failed"] -> {:ok, install}
      _status -> run_template_installation(install, opts)
    end
  end

  @spec instantiate_template(Scope.t(), ProjectTemplateVersion.t(), Workspace.t(), map()) ::
          {:ok, Project.t()} | {:error, term()}
  def instantiate_template(%Scope{} = scope, %ProjectTemplateVersion{} = version, %Workspace{} = workspace, attrs) do
    version = Repo.preload(version, [:project_template])

    with :ok <- Authorization.authorize_template_visibility(scope, version.project_template),
         {:ok, workspace, _membership} <- Workspaces.authorize(scope, workspace.id, :create_project),
         :ok <- Billing.can_create_project?(workspace),
         {:ok, snapshot} <- load_verified_template_snapshot(version) do
      instantiate_template_transaction(scope, version, workspace, attrs, snapshot, [])
    end
  end

  @spec list_active_workspace_installations(Scope.t(), Workspace.t()) :: [ProjectTemplateInstall.t()]
  def list_active_workspace_installations(%Scope{} = scope, %Workspace{} = workspace) do
    case Workspaces.authorize(scope, workspace.id, :view) do
      {:ok, _workspace, _membership} ->
        ProjectTemplateInstall
        |> where([install], install.workspace_id == ^workspace.id and install.status in ^@active_statuses)
        |> order_by([install], asc: install.inserted_at, asc: install.id)
        |> preload([:project_template_version])
        |> Repo.all()

      _error ->
        []
    end
  end

  @spec list_pending_workspace_installation_failures(Scope.t(), Workspace.t()) :: [ProjectTemplateInstall.t()]
  def list_pending_workspace_installation_failures(%Scope{user: %{id: user_id}} = scope, %Workspace{} = workspace) do
    case Workspaces.authorize(scope, workspace.id, :view) do
      {:ok, _workspace, _membership} ->
        ProjectTemplateInstall
        |> where(
          [install],
          install.workspace_id == ^workspace.id and install.user_id == ^user_id and
            install.status == "failed" and is_nil(install.feedback_dismissed_at)
        )
        |> order_by([install], desc: install.completed_at, desc: install.id)
        |> limit(^@pending_failure_limit)
        |> preload([:project_template_version])
        |> Repo.all()

      _error ->
        []
    end
  end

  def list_pending_workspace_installation_failures(%Scope{}, %Workspace{}), do: []

  @spec pending_installation_failure?(Scope.t(), Workspace.t(), integer()) :: boolean()
  def pending_installation_failure?(%Scope{user: %{id: user_id}} = scope, %Workspace{} = workspace, installation_id)
      when is_integer(installation_id) do
    case Workspaces.authorize(scope, workspace.id, :view) do
      {:ok, _workspace, _membership} ->
        Repo.exists?(
          from install in ProjectTemplateInstall,
            where:
              install.id == ^installation_id and install.workspace_id == ^workspace.id and
                install.user_id == ^user_id and install.status == "failed" and
                is_nil(install.feedback_dismissed_at)
        )

      _error ->
        false
    end
  end

  def pending_installation_failure?(%Scope{}, %Workspace{}, _installation_id), do: false

  @spec dismiss_installation_failure(Scope.t(), Workspace.t(), integer()) ::
          {:ok, ProjectTemplateInstall.t()}
          | {:error, :not_found | :unauthorized | Ecto.Changeset.t()}
  def dismiss_installation_failure(%Scope{user: %{id: user_id}} = scope, %Workspace{} = workspace, installation_id)
      when is_integer(installation_id) do
    with {:ok, _workspace, _membership} <- Workspaces.authorize(scope, workspace.id, :view),
         {:ok, {install, changed?}} <-
           dismiss_installation_failure_transaction(installation_id, workspace.id, user_id) do
      install = preload_install(install)
      if changed?, do: broadcast_install(install)
      {:ok, install}
    end
  end

  def dismiss_installation_failure(%Scope{}, %Workspace{}, _installation_id), do: {:error, :unauthorized}

  defp dismiss_installation_failure_transaction(installation_id, workspace_id, user_id) do
    Repo.transact(fn ->
      installation_id
      |> lock_failed_installation(workspace_id, user_id)
      |> dismiss_locked_installation()
    end)
  end

  defp lock_failed_installation(installation_id, workspace_id, user_id) do
    ProjectTemplateInstall
    |> where(
      [install],
      install.id == ^installation_id and install.workspace_id == ^workspace_id and
        install.user_id == ^user_id and install.status == "failed"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp dismiss_locked_installation(nil), do: {:error, :not_found}

  defp dismiss_locked_installation(%ProjectTemplateInstall{feedback_dismissed_at: %DateTime{}} = install) do
    {:ok, {install, false}}
  end

  defp dismiss_locked_installation(%ProjectTemplateInstall{} = install) do
    case install
         |> ProjectTemplateInstall.dismiss_failure_changeset(TimeHelpers.now())
         |> Repo.update() do
      {:ok, install} -> {:ok, {install, true}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec list_active_template_installations(Scope.t(), ProjectTemplate.t()) :: [ProjectTemplateInstall.t()]
  def list_active_template_installations(%Scope{user: %{id: user_id}} = scope, %ProjectTemplate{} = template) do
    case Authorization.authorize_template_visibility(scope, template) do
      :ok ->
        ProjectTemplateInstall
        |> join(:inner, [install], version in assoc(install, :project_template_version))
        |> where(
          [install, version],
          install.user_id == ^user_id and version.project_template_id == ^template.id and
            install.status in ^@active_statuses
        )
        |> order_by([install], asc: install.inserted_at, asc: install.id)
        |> preload([_install, version], project_template_version: version)
        |> Repo.all()

      _error ->
        []
    end
  end

  def subscribe_workspace_installations(%Workspace{id: workspace_id}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, workspace_topic(workspace_id))
  end

  def subscribe_user_installations(%Scope{user: %{id: user_id}}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, user_topic(user_id))
  end

  defp run_template_installation(install, opts) do
    started_at = System.monotonic_time()

    try do
      with {:ok, install} <- mark_running(install),
           :ok <- authorize_installation(install),
           {:ok, snapshot} <- load_verified_template_snapshot(install.project_template_version),
           {:ok, install} <- mark_stage(install, "materializing"),
           {:ok, project} <-
             instantiate_template_transaction(
               Scope.for_user(install.user),
               install.project_template_version,
               install.workspace,
               %{name: install.project_name},
               snapshot,
               installation: install
             ) do
        completed = get_install!(install.id)
        publish_finished(completed, project, started_at)
        {:ok, completed}
      else
        {:error, reason} -> handle_installation_error(install, reason, opts, started_at)
      end
    rescue
      error ->
        log_unexpected_exception(install, error, __STACKTRACE__)
        handle_installation_error(install, {:exception, error.__struct__}, opts, started_at)
    catch
      kind, reason ->
        log_unexpected_throw(install, kind, __STACKTRACE__)
        handle_installation_error(install, {kind, safe_reason(reason)}, opts, started_at)
    end
  end

  defp insert_install_and_enqueue(changeset) do
    Repo.transact(fn ->
      with {:ok, install} <- Repo.insert(changeset),
           {:ok, job} <-
             %{"installation_id" => install.id}
             |> InstallProjectTemplateWorker.new()
             |> Oban.insert(),
           {:ok, install} <-
             install
             |> ProjectTemplateInstall.job_changeset(job.id)
             |> Repo.update() do
        {:ok, {preload_install(install), :created}}
      end
    end)
  end

  defp authorize_installation(install) do
    scope = Scope.for_user(install.user)

    with :ok <-
           Authorization.authorize_template_visibility(
             scope,
             install.project_template_version.project_template
           ),
         {:ok, _workspace, _membership} <-
           Workspaces.authorize(scope, install.workspace_id, :create_project) do
      normalize_worker_authorization(Billing.can_create_project?(install.workspace))
    end
  end

  defp normalize_worker_authorization({:error, reason, details}), do: {:error, {reason, details}}
  defp normalize_worker_authorization(result), do: result

  defp existing_install_or_error(changeset, idempotency_key) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      case active_install_by_idempotency_key(idempotency_key) do
        nil -> {:error, changeset}
        install -> {:ok, preload_install(install)}
      end
    else
      {:error, changeset}
    end
  end

  defp active_install_by_idempotency_key(idempotency_key) do
    Repo.one(
      from install in ProjectTemplateInstall,
        where: install.idempotency_key == ^idempotency_key and install.status in ^@active_statuses,
        order_by: [desc: install.id],
        limit: 1
    )
  end

  defp load_verified_template_snapshot(version) do
    with {:ok, snapshot} <- SnapshotStorage.load_snapshot(version.snapshot_storage_key),
         {:ok, asset_manifest} <- load_template_asset_manifest(version),
         :ok <- verify_template_checksum(version, snapshot, asset_manifest),
         :ok <- validate_template_snapshot(snapshot) do
      {:ok, snapshot}
    end
  end

  defp validate_template_snapshot(snapshot) do
    case Audit.validate_snapshot_integrity(snapshot) do
      :ok ->
        :ok

      {:error, errors} ->
        Logger.warning("Rejected incompatible stored template snapshot: #{inspect(errors)}")
        {:error, :incompatible_template_snapshot}
    end
  end

  defp load_template_asset_manifest(%ProjectTemplateVersion{asset_manifest_storage_key: nil}) do
    {:error, :missing_asset_manifest}
  end

  defp load_template_asset_manifest(version) do
    SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)
  end

  defp verify_template_checksum(%ProjectTemplateVersion{checksum: nil}, _snapshot, _asset_manifest) do
    {:error, :missing_checksum}
  end

  defp verify_template_checksum(version, snapshot, asset_manifest) do
    data = %{"snapshot" => snapshot, "asset_manifest" => asset_manifest}

    if version.checksum == Artifact.checksum(data) do
      :ok
    else
      {:error, :checksum_mismatch}
    end
  end

  defp instantiate_template_transaction(scope, version, workspace, attrs, snapshot, opts) do
    tracker = StorageCompensation.new()
    opts = Keyword.put(opts, :asset_copy_tracker, tracker)

    try do
      result =
        Repo.transaction(
          fn -> instantiate_template_under_workspace_lock(scope, version, workspace, attrs, snapshot, opts) end,
          timeout: to_timeout(minute: 5)
        )

      case result do
        {:ok, _project} ->
          StorageCompensation.discard(tracker)
          result

        {:error, _reason} ->
          cleanup_result(tracker, result)
      end
    rescue
      error in AssetCopyError ->
        cleanup_result(tracker, {:error, {:asset_copy_failed, error.reason}})

      error ->
        StorageCompensation.cleanup!(tracker)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        StorageCompensation.cleanup!(tracker)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp cleanup_result(tracker, result) do
    case StorageCompensation.cleanup(tracker) do
      :ok -> result
      {:error, cleanup_reason} -> {:error, cleanup_reason}
    end
  end

  defp instantiate_template_under_workspace_lock(scope, version, workspace, attrs, snapshot, opts) do
    with :ok <- Projects.lock_and_check_workspace_capacity(workspace.id),
         {:ok, project} <- do_instantiate_template(scope, version, workspace, attrs, snapshot, opts) do
      project
    else
      {:error, :limit_reached, details} -> Repo.rollback({:limit_reached, details})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp do_instantiate_template(scope, version, workspace, attrs, snapshot, opts) do
    with {:ok, project} <-
           Versioning.recover_project(workspace.id, snapshot, scope.user.id,
             name: install_name(attrs, version),
             template_clone: true,
             asset_error_mode: :strict,
             asset_copy_tracker: Keyword.fetch!(opts, :asset_copy_tracker)
           ),
         {:ok, project} <- mark_template_origin(project, version),
         {:ok, _install} <- complete_or_record_install(scope, version, workspace, project, attrs, opts) do
      {:ok, project}
    end
  end

  defp mark_template_origin(project, version) do
    project
    |> Ecto.Changeset.change(created_from_template_version_id: version.id)
    |> Ecto.Changeset.foreign_key_constraint(:created_from_template_version_id)
    |> Repo.update()
  end

  defp complete_or_record_install(scope, version, workspace, project, attrs, opts) do
    now = TimeHelpers.now()

    case Keyword.get(opts, :installation) do
      %ProjectTemplateInstall{} = install ->
        install
        |> ProjectTemplateInstall.completed_changeset(project, now)
        |> Repo.update()

      nil ->
        %ProjectTemplateInstall{
          project_template_version_id: version.id,
          user_id: scope.user.id,
          workspace_id: workspace.id,
          project_id: project.id
        }
        |> ProjectTemplateInstall.create_changeset(%{
          status: "completed",
          stage: "completed",
          source: "internal",
          project_name: install_name(attrs, version),
          installed_at: now,
          started_at: now,
          completed_at: now
        })
        |> Repo.insert()
    end
  end

  defp mark_running(install) do
    install
    |> ProjectTemplateInstall.running_changeset(TimeHelpers.now())
    |> Repo.update()
    |> tap_install_broadcast()
  end

  defp mark_stage(install, stage) do
    install
    |> ProjectTemplateInstall.stage_changeset(stage)
    |> Repo.update()
    |> tap_install_broadcast()
  end

  defp handle_installation_error(install, reason, opts, started_at) do
    install = Repo.get!(ProjectTemplateInstall, install.id)
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    {code, message, permanent?} = classify_error(reason)

    if permanent? or attempt >= max_attempts do
      install = fail_install(install, code, message, attempt, max_attempts)

      log_terminal_failure(install, code)

      publish_finished(install, nil, started_at)
      {:ok, install}
    else
      install = retry_install(install, code, attempt, max_attempts)

      Logger.warning(
        "Project template installation will retry installation_id=#{install.id} version_id=#{install.project_template_version_id} workspace_id=#{install.workspace_id} error_code=#{code} attempt=#{attempt} max_attempts=#{max_attempts}"
      )

      broadcast_install(install)
      emit_finished_telemetry(install, started_at)
      {:error, reason}
    end
  end

  defp fail_install(install, code, message, attempt, max_attempts) do
    install
    |> ProjectTemplateInstall.failed_changeset(%{
      status: "failed",
      stage: "failed",
      error_code: code,
      error_message: message,
      error_report: %{attempt: attempt, max_attempts: max_attempts},
      completed_at: TimeHelpers.now()
    })
    |> Repo.update!()
    |> preload_install()
  end

  defp retry_install(install, code, attempt, max_attempts) do
    install
    |> ProjectTemplateInstall.retrying_changeset(%{
      status: "retrying",
      stage: "retrying",
      error_code: code,
      error_message: "The installation will be retried automatically.",
      error_report: %{attempt: attempt, max_attempts: max_attempts}
    })
    |> Repo.update!()
    |> preload_install()
  end

  defp classify_error({:exception, _exception}), do: {"exception", "The installation could not be completed.", false}

  defp classify_error({:asset_copy_failed, _reason}),
    do: {"asset_copy_failed", "A template asset could not be copied.", true}

  defp classify_error({:unremappable_subflow_exit_pin, _details}) do
    {
      "unremappable_subflow_exit_pin",
      permanent_error_message(:unremappable_subflow_exit_pin),
      true
    }
  end

  defp classify_error(reason) when reason in @permanent_errors do
    {to_string(reason), permanent_error_message(reason), true}
  end

  defp classify_error({:limit_reached, _details}), do: {"limit_reached", permanent_error_message(:limit_reached), true}

  defp classify_error(reason), do: {safe_reason(reason), "The installation could not be completed.", false}

  defp permanent_error_message(:archived), do: "This template is no longer available."
  defp permanent_error_message(:checksum_mismatch), do: "The template failed its integrity check."

  defp permanent_error_message(:incompatible_template_snapshot),
    do: "This template version is incompatible and must be republished."

  defp permanent_error_message(:unremappable_subflow_exit_pin),
    do: "This template version contains an invalid subflow exit and must be republished."

  defp permanent_error_message(:limit_reached), do: "The workspace project limit has been reached."
  defp permanent_error_message(:missing_asset_manifest), do: "The template asset manifest is unavailable."
  defp permanent_error_message(:missing_checksum), do: "The template integrity information is unavailable."
  defp permanent_error_message(:not_found), do: "The template or workspace is no longer available."
  defp permanent_error_message(:unauthorized), do: "You no longer have permission to install this template."

  defp publish_requested(scope, install, template) do
    broadcast_install(install)

    Analytics.track(scope, "project template installation requested", %{
      installation_id: install.id,
      template_id: template.id,
      template_version_id: install.project_template_version_id,
      workspace_id: install.workspace_id,
      source: install.source,
      visibility: template.visibility
    })

    :telemetry.execute(
      [:storyarn, :project_template, :installation, :requested],
      %{count: 1},
      %{source: install.source, visibility: template.visibility}
    )
  end

  defp publish_finished(install, project, started_at) do
    broadcast_install(install)

    event =
      if install.status == "completed",
        do: "project template installation completed",
        else: "project template installation failed"

    Analytics.track(install.user, event, analytics_properties(install, project, started_at))

    if project do
      Analytics.track(install.user, "project created", %{
        project_id: project.id,
        workspace_id: project.workspace_id,
        project_type: project.project_type,
        project_subtype: project.project_subtype,
        project_type_other: project.project_type_other
      })
    end

    emit_finished_telemetry(install, started_at)
  end

  defp analytics_properties(install, project, started_at) do
    %{
      installation_id: install.id,
      template_version_id: install.project_template_version_id,
      workspace_id: install.workspace_id,
      project_id: project && project.id,
      source: install.source,
      error_code: install.error_code,
      duration_bucket: duration_bucket(started_at)
    }
  end

  defp emit_finished_telemetry(install, started_at) do
    :telemetry.execute(
      [:storyarn, :project_template, :installation, :stop],
      %{count: 1, duration: System.monotonic_time() - started_at},
      %{status: install.status, source: install.source, error_code: install.error_code || "none"}
    )
  end

  defp duration_bucket(started_at) do
    milliseconds = System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    cond do
      milliseconds < 5_000 -> "under_5s"
      milliseconds < 30_000 -> "5s_to_30s"
      milliseconds < 120_000 -> "30s_to_2m"
      true -> "over_2m"
    end
  end

  defp tap_install_broadcast({:ok, install}) do
    install = preload_install(install)
    broadcast_install(install)
    {:ok, install}
  end

  defp tap_install_broadcast(other), do: other

  defp broadcast_install(install) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      workspace_topic(install.workspace_id),
      {:project_template_installation_updated, install}
    )

    if install.user_id do
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        user_topic(install.user_id),
        {:project_template_installation_updated, install}
      )
    end

    :ok
  end

  defp workspace_topic(workspace_id), do: "project_template_installs:workspace:#{workspace_id}"
  defp user_topic(user_id), do: "project_template_installs:user:#{user_id}"

  defp get_install!(id) do
    ProjectTemplateInstall
    |> Repo.get!(id)
    |> preload_install()
  end

  defp preload_install(install) do
    Repo.preload(
      install,
      [:user, :workspace, :project, project_template_version: [:project_template]],
      force: true
    )
  end

  defp idempotency_key(user_id, workspace_id, version_id, name) do
    normalized_name = name |> String.trim() |> String.downcase()

    :sha256
    |> :crypto.hash("#{user_id}:#{workspace_id}:#{version_id}:#{normalized_name}")
    |> Base.encode16(case: :lower)
  end

  defp install_source(attrs) do
    source = Map.get(attrs, :source) || Map.get(attrs, "source") || "internal"
    if source in ProjectTemplateInstall.sources(), do: source, else: "internal"
  end

  defp install_name(attrs, version) do
    (Map.get(attrs, :name) || Map.get(attrs, "name") || version.project_template.name)
    |> to_string()
    |> String.trim()
  end

  defp safe_reason(reason) when is_atom(reason), do: to_string(reason)
  defp safe_reason({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp safe_reason(_reason), do: "unexpected_error"

  defp log_terminal_failure(install, code)
       when code in ["archived", "limit_reached", "not_found", "unauthorized", "exception"] do
    Logger.warning(terminal_failure_message(install, code))
  end

  defp log_terminal_failure(install, code) do
    Logger.error(terminal_failure_message(install, code))
  end

  defp terminal_failure_message(install, code) do
    "Project template installation failed installation_id=#{install.id} version_id=#{install.project_template_version_id} workspace_id=#{install.workspace_id} error_code=#{code}"
  end

  defp log_unexpected_exception(install, error, stacktrace) do
    Logger.error(
      "Unexpected project template installation exception installation_id=#{install.id} version_id=#{install.project_template_version_id} workspace_id=#{install.workspace_id} exception=#{inspect(error.__struct__)}\n#{Exception.format_stacktrace(stacktrace)}"
    )
  end

  defp log_unexpected_throw(install, kind, stacktrace) do
    Logger.error(
      "Unexpected project template installation catch installation_id=#{install.id} version_id=#{install.project_template_version_id} workspace_id=#{install.workspace_id} kind=#{kind}\n#{Exception.format_stacktrace(stacktrace)}"
    )
  end
end
