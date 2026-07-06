defmodule Storyarn.ProjectTemplates.PublicationRunner do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.ProjectTemplates.TemplateQueries
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.PublishProjectTemplateWorker

  def request_template_publication(%Scope{} = scope, %Project{} = source_project, attrs) do
    with :ok <- Authorization.ensure_private_visibility(attrs),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project) do
      source_project
      |> new_template_publication_changeset(scope, attrs)
      |> insert_publication_and_enqueue()
    end
  end

  def request_template_version_publication(
        %Scope{} = scope,
        %ProjectTemplate{} = template,
        %Project{} = source_project,
        attrs
      ) do
    with :ok <- Authorization.ensure_private_visibility(attrs),
         :ok <- Authorization.authorize_template_owner(scope, template),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project),
         :ok <- Authorization.ensure_template_source(template, source_project) do
      template
      |> template_version_publication_changeset(scope, source_project, attrs)
      |> insert_publication_and_enqueue()
    end
  end

  def perform_template_publication(publication_id, opts \\ []) do
    publication =
      ProjectTemplatePublication
      |> Repo.get!(publication_id)
      |> Repo.preload([:requested_by | TemplateQueries.publication_preloads()])

    case publication.status do
      "published" -> {:ok, publication}
      "failed" -> {:ok, publication}
      _status -> run_template_publication(publication, opts)
    end
  end

  def subscribe_template_publications(%Project{id: project_id}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, publication_project_topic(project_id))
  end

  def subscribe_template_publications(%ProjectTemplate{id: template_id}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, publication_template_topic(template_id))
  end

  def create_template_from_project(%Scope{} = scope, %Project{} = source_project, attrs) do
    with :ok <- Authorization.ensure_private_visibility(attrs),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project),
         {:ok, publication} <-
           source_project
           |> new_template_publication_changeset(scope, attrs)
           |> insert_publication(),
         {:ok, publication} <- perform_template_publication(publication.id, attempt: 1, max_attempts: 1) do
      publication_to_template_result(scope, publication)
    end
  end

  def publish_new_version(%Scope{} = scope, %ProjectTemplate{} = template, %Project{} = source_project) do
    with :ok <- Authorization.authorize_template_owner(scope, template),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project),
         :ok <- Authorization.ensure_template_source(template, source_project),
         {:ok, publication} <-
           template
           |> template_version_publication_changeset(scope, source_project, %{
             "name" => template.name,
             "description" => template.description
           })
           |> insert_publication(),
         {:ok, publication} <- perform_template_publication(publication.id, attempt: 1, max_attempts: 1) do
      publication_to_template_result(scope, publication)
    end
  end

  def update_template(%Scope{} = scope, %ProjectTemplate{} = template, attrs) do
    with :ok <- Authorization.authorize_template_owner(scope, template) do
      update_template_metadata(template, attrs)
    end
  end

  def update_template_and_publish_new_version(
        %Scope{} = scope,
        %ProjectTemplate{} = template,
        %Project{} = source_project,
        attrs
      ) do
    with :ok <- Authorization.authorize_template_owner(scope, template),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project),
         :ok <- Authorization.ensure_template_source(template, source_project),
         {:ok, publication} <-
           template
           |> template_version_publication_changeset(scope, source_project, attrs)
           |> insert_publication(),
         {:ok, publication} <- perform_template_publication(publication.id, attempt: 1, max_attempts: 1) do
      publication_to_template_result(scope, publication)
    end
  end

  defp update_template_metadata(template, attrs) do
    template
    |> ProjectTemplate.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, template} -> {:ok, TemplateQueries.preload_template(template)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp insert_publication(changeset) do
    changeset
    |> Repo.insert()
    |> case do
      {:ok, publication} -> {:ok, preload_publication(publication)}
      {:error, %Ecto.Changeset{} = changeset} -> normalize_publication_changeset_error(changeset)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_publication_and_enqueue(changeset) do
    result =
      Repo.transact(fn ->
        with {:ok, publication} <- Repo.insert(changeset),
             {:ok, job} <-
               %{"publication_id" => publication.id}
               |> PublishProjectTemplateWorker.new()
               |> Oban.insert(),
             {:ok, publication} <-
               publication
               |> ProjectTemplatePublication.job_changeset(job.id)
               |> Repo.update() do
          {:ok, preload_publication(publication)}
        end
      end)

    case result do
      {:ok, publication} -> {:ok, publication}
      {:error, %Ecto.Changeset{} = changeset} -> normalize_publication_changeset_error(changeset)
      {:error, reason} -> {:error, reason}
    end
  end

  defp new_template_publication_changeset(source_project, scope, attrs) do
    ProjectTemplatePublication.create_changeset(
      %ProjectTemplatePublication{
        owner_id: scope.user.id,
        requested_by_id: scope.user.id,
        source_project_id: source_project.id
      },
      %{
        "mode" => "new",
        "status" => "queued",
        "name" => template_name(attrs, source_project),
        "description" => template_description(attrs, source_project.description)
      }
    )
  end

  defp template_version_publication_changeset(template, scope, source_project, attrs) do
    ProjectTemplatePublication.create_changeset(
      %ProjectTemplatePublication{
        owner_id: scope.user.id,
        requested_by_id: scope.user.id,
        source_project_id: source_project.id,
        project_template_id: template.id
      },
      %{
        "mode" => "update",
        "status" => "queued",
        "name" => template_name(attrs, template),
        "description" => template_description(attrs, template.description)
      }
    )
  end

  defp publication_to_template_result(scope, %ProjectTemplatePublication{status: "published"} = publication) do
    TemplateQueries.get_template(scope, publication.project_template_id)
  end

  defp publication_to_template_result(_scope, %ProjectTemplatePublication{status: "failed"} = publication) do
    {:error, publication_failure_report(publication)}
  end

  defp publication_to_template_result(_scope, publication),
    do: {:error, {:unexpected_publication_status, publication.status}}

  defp publication_failure_report(%ProjectTemplatePublication{audit_report: %{"status" => _status} = report}), do: report
  defp publication_failure_report(%ProjectTemplatePublication{error_report: report}) when map_size(report) > 0, do: report

  defp publication_failure_report(%ProjectTemplatePublication{error_code: code}) when not is_nil(code) do
    {:publication_failed, code}
  end

  defp publication_failure_report(_publication), do: :publication_failed

  defp normalize_publication_changeset_error(changeset) do
    if active_publication_constraint_error?(changeset) do
      {:error, :publication_already_active}
    else
      {:error, changeset}
    end
  end

  defp active_publication_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      opts[:constraint_name] in [
        "project_template_publications_active_template_unique",
        "project_template_publications_active_new_source_unique"
      ]
    end)
  end

  defp run_template_publication(publication, opts) do
    with {:ok, publication} <- mark_publication_running(publication),
         {:ok, scope, source_project, template} <- authorize_publication_for_worker(publication),
         {:ok, audit_report, snapshot} <- Audit.run_with_snapshot(source_project.id) do
      publish_audited_snapshot(publication, scope, source_project, template, audit_report, snapshot, opts)
    else
      {:error, {:expected, code, message, report}} ->
        fail_publication(publication, code, message, report)

      {:error, %{"status" => "failed"} = audit_report} ->
        fail_publication(publication, :audit_failed, "Template audit failed.", audit_report)

      {:error, reason} ->
        handle_unexpected_publication_error(publication, reason, opts)
    end
  end

  defp publish_audited_snapshot(publication, scope, source_project, template, audit_report, snapshot, opts) do
    asset_manifest = Artifact.build_asset_manifest(source_project.id)
    checksum = Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => asset_manifest})

    with {:ok, artifact} <-
           store_publication_artifacts(publication, snapshot, asset_manifest, checksum, audit_report),
         {:ok, publication} <-
           finalize_publication(
             publication,
             scope,
             source_project,
             template,
             artifact
           ) do
      broadcast_publication(publication)
      {:ok, publication}
    else
      {:error, reason} ->
        handle_unexpected_publication_error(publication, reason, opts)
    end
  end

  defp finalize_publication(publication, scope, source_project, template, artifact) do
    result =
      Repo.transact(fn ->
        with {:ok, template} <-
               publication_template_for_finalize(publication, scope, source_project, template),
             {:ok, version} <-
               create_version_from_artifacts(
                 scope,
                 template,
                 source_project,
                 publication_version_number(publication, template),
                 artifact
               ),
             {:ok, template} <- set_current_version(template, version),
             {:ok, publication} <-
               mark_publication_published(
                 publication,
                 template,
                 version,
                 artifact
               ) do
          {:ok, preload_publication(publication)}
        end
      end)

    case result do
      {:ok, publication} ->
        {:ok, publication}

      {:error, %Ecto.Changeset{} = changeset} ->
        cleanup_publication_artifacts(artifact_keys(artifact))

        fail_publication(
          publication,
          :validation_failed,
          "Template publication could not be saved.",
          changeset_report(changeset)
        )

      {:error, reason} ->
        cleanup_publication_artifacts(artifact_keys(artifact))
        {:error, reason}
    end
  end

  defp publication_template_for_finalize(
         %ProjectTemplatePublication{mode: "new"} = publication,
         scope,
         source_project,
         nil
       ) do
    slug = NameNormalizer.generate_unique_slug(ProjectTemplate, [owner_id: scope.user.id], publication.name)

    insert_template(scope, source_project, %{"description" => publication.description}, publication.name, slug)
  end

  defp publication_template_for_finalize(
         %ProjectTemplatePublication{mode: "update"} = publication,
         _scope,
         _source_project,
         %ProjectTemplate{} = template
       ) do
    update_template_metadata(template, %{
      "name" => publication.name,
      "description" => publication.description
    })
  end

  defp publication_template_for_finalize(_publication, _scope, _source_project, _template) do
    {:error, :invalid_publication_mode}
  end

  defp publication_version_number(%ProjectTemplatePublication{mode: "new"}, _template), do: 1

  defp publication_version_number(%ProjectTemplatePublication{mode: "update"}, template),
    do: TemplateQueries.next_version_number(template.id)

  defp authorize_publication_for_worker(publication) do
    publication = Repo.preload(publication, [:requested_by, :source_project, :project_template], force: true)

    with %User{} = user <- publication.requested_by,
         %Project{} = source_project <- publication.source_project,
         scope = Scope.for_user(user),
         {:ok, source_project} <- Authorization.authorize_source_project(scope, source_project) do
      authorize_publication_template_for_worker(scope, publication, source_project)
    else
      nil ->
        expected_publication_error(:user_not_found, "The user that requested this publication no longer exists.")

      {:error, reason} ->
        expected_publication_error(:unauthorized, "You no longer have permission to publish this project.", %{
          "reason" => inspect(reason)
        })
    end
  end

  defp authorize_publication_template_for_worker(scope, %ProjectTemplatePublication{mode: "new"}, source_project) do
    {:ok, scope, source_project, nil}
  end

  defp authorize_publication_template_for_worker(
         scope,
         %ProjectTemplatePublication{mode: "update"} = publication,
         source_project
       ) do
    template = Repo.get(ProjectTemplate, publication.project_template_id)

    with %ProjectTemplate{status: "active"} = template <- template,
         :ok <- Authorization.authorize_template_owner(scope, template),
         :ok <- Authorization.ensure_template_source(template, source_project) do
      {:ok, scope, source_project, template}
    else
      nil ->
        expected_publication_error(:template_not_found, "The template no longer exists.")

      %ProjectTemplate{} ->
        expected_publication_error(:template_archived, "The template is no longer active.")

      {:error, reason} ->
        expected_publication_error(:unauthorized, "You no longer have permission to publish this template.", %{
          "reason" => inspect(reason)
        })
    end
  end

  defp expected_publication_error(code, message, report \\ %{}) do
    {:error, {:expected, code, message, report}}
  end

  defp mark_publication_running(publication) do
    publication
    |> ProjectTemplatePublication.running_changeset(TimeHelpers.now())
    |> Repo.update()
    |> tap_publication_broadcast()
  end

  defp mark_publication_published(publication, template, version, artifact) do
    publication
    |> ProjectTemplatePublication.published_changeset(%{
      "status" => "published",
      "project_template_id" => template.id,
      "project_template_version_id" => version.id,
      "snapshot_storage_key" => artifact.snapshot_key,
      "asset_manifest_storage_key" => artifact.asset_manifest_key,
      "checksum" => artifact.checksum,
      "entity_counts" => Map.get(artifact.snapshot, "entity_counts", %{}),
      "audit_report" => artifact.audit_report,
      "completed_at" => TimeHelpers.now()
    })
    |> Repo.update()
  end

  defp fail_publication(publication, code, message, report) do
    publication =
      publication
      |> ProjectTemplatePublication.failed_changeset(%{
        "status" => "failed",
        "error_code" => to_string(code),
        "error_message" => message,
        "error_report" => json_safe_report(report),
        "audit_report" => audit_report_from_failure(report),
        "completed_at" => TimeHelpers.now()
      })
      |> Repo.update()
      |> case do
        {:ok, publication} -> preload_publication(publication)
        {:error, changeset} -> raise "Could not mark template publication failed: #{inspect(changeset.errors)}"
      end

    broadcast_publication(publication)
    {:ok, publication}
  end

  defp handle_unexpected_publication_error(publication, reason, opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    report = %{"reason" => inspect(reason), "attempt" => attempt, "max_attempts" => max_attempts}

    if attempt < max_attempts do
      publication =
        publication
        |> ProjectTemplatePublication.retrying_changeset(%{
          "status" => "retrying",
          "error_code" => "unexpected_error",
          "error_message" => "Template publication failed and will be retried.",
          "error_report" => report
        })
        |> Repo.update!()
        |> preload_publication()

      broadcast_publication(publication)
      {:error, reason}
    else
      fail_publication(publication, :unexpected_error, "Template publication failed.", report)
    end
  end

  defp tap_publication_broadcast({:ok, publication}) do
    publication = preload_publication(publication)
    broadcast_publication(publication)
    {:ok, publication}
  end

  defp tap_publication_broadcast(other), do: other

  defp preload_publication(publication) do
    Repo.preload(publication, TemplateQueries.publication_preloads(), force: true)
  end

  defp broadcast_publication(publication) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      publication_project_topic(publication.source_project_id),
      {:project_template_publication_updated, publication}
    )

    if publication.project_template_id do
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        publication_template_topic(publication.project_template_id),
        {:project_template_publication_updated, publication}
      )
    end

    :ok
  end

  defp publication_project_topic(project_id), do: "project_template_publications:project:#{project_id}"
  defp publication_template_topic(template_id), do: "project_template_publications:template:#{template_id}"

  defp insert_template(scope, source_project, attrs, name, slug) do
    %ProjectTemplate{owner_id: scope.user.id, source_project_id: source_project.id}
    |> ProjectTemplate.create_changeset(%{
      name: name,
      slug: slug,
      description: Map.get(attrs, :description) || Map.get(attrs, "description") || source_project.description,
      visibility: "private",
      status: "active"
    })
    |> Repo.insert()
  end

  defp create_version_from_artifacts(scope, template, source_project, version_number, artifact) do
    now = TimeHelpers.now()

    %ProjectTemplateVersion{
      project_template_id: template.id,
      source_project_id: source_project.id,
      published_by_id: scope.user.id
    }
    |> ProjectTemplateVersion.create_changeset(%{
      version_number: version_number,
      snapshot_storage_key: artifact.snapshot_key,
      asset_manifest_storage_key: artifact.asset_manifest_key,
      checksum: artifact.checksum,
      entity_counts: Map.get(artifact.snapshot, "entity_counts", %{}),
      audit_report: artifact.audit_report,
      published_at: now
    })
    |> Repo.insert()
  end

  defp store_publication_artifact(publication, name, data) do
    suffix = SnapshotStorage.unique_key_suffix()
    key = "project_template_publications/#{publication.id}/#{name}-#{suffix}.json.gz"

    case SnapshotStorage.store_raw(key, data) do
      {:ok, _size_bytes} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_publication_artifacts(publication, snapshot, asset_manifest, checksum, audit_report) do
    case store_publication_artifact(publication, "snapshot", snapshot) do
      {:ok, snapshot_key} ->
        case store_publication_artifact(publication, "asset-manifest", asset_manifest) do
          {:ok, asset_manifest_key} ->
            {:ok, publication_artifact(audit_report, snapshot, checksum, snapshot_key, asset_manifest_key)}

          {:error, reason} ->
            cleanup_publication_artifacts([snapshot_key])
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_publication_artifacts(%ProjectTemplatePublication{} = publication) do
    [publication.snapshot_storage_key, publication.asset_manifest_storage_key]
    |> Enum.reject(&is_nil/1)
    |> cleanup_publication_artifacts()
  end

  defp cleanup_publication_artifacts(keys) when is_list(keys) do
    Enum.each(keys, fn key ->
      case SnapshotStorage.delete_snapshot(key) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end

  defp publication_artifact(audit_report, snapshot, checksum, snapshot_key, asset_manifest_key) do
    %{
      audit_report: audit_report,
      snapshot: snapshot,
      checksum: checksum,
      snapshot_key: snapshot_key,
      asset_manifest_key: asset_manifest_key
    }
  end

  defp artifact_keys(artifact), do: [artifact.snapshot_key, artifact.asset_manifest_key]

  defp set_current_version(template, version) do
    template
    |> ProjectTemplate.current_version_changeset(version.id)
    |> Repo.update()
  end

  defp template_name(attrs, source_project) do
    Map.get(attrs, :name) || Map.get(attrs, "name") || source_project.name
  end

  defp template_description(attrs, default_description) do
    Map.get(attrs, :description) || Map.get(attrs, "description") || default_description
  end

  defp changeset_report(changeset) do
    %{
      "valid?" => changeset.valid?,
      "errors" =>
        Enum.map(changeset.errors, fn {field, {message, opts}} ->
          %{
            "field" => to_string(field),
            "message" => message,
            "validation" => opts[:validation] && to_string(opts[:validation]),
            "constraint" => opts[:constraint] && to_string(opts[:constraint]),
            "constraint_name" => opts[:constraint_name]
          }
        end)
    }
  end

  defp audit_report_from_failure(%{"status" => _status} = report), do: report
  defp audit_report_from_failure(_report), do: %{}

  defp json_safe_report(%Ecto.Changeset{} = changeset), do: changeset_report(changeset)
  defp json_safe_report(report) when is_map(report), do: report
  defp json_safe_report(report), do: %{"reason" => inspect(report)}
end
