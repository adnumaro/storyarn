defmodule Storyarn.ProjectTemplates.PortableImport do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Projects
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.LegacySnapshotRepair
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @visibilities ~w(private public)

  @spec preview_bundle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def preview_bundle(path, opts \\ []) do
    with {:ok, bundle} <- PortableBundle.read(path),
         :ok <- validate_manifest(bundle.manifest),
         :ok <- verify_bundle_checksum(bundle),
         {:ok, repair_report} <- preview_legacy_repair(bundle.snapshot, opts) do
      {:ok, put_repair_preview(bundle.manifest, repair_report)}
    end
  end

  @spec import_bundle(String.t(), keyword()) :: {:ok, ProjectTemplate.t()} | {:error, term()}
  def import_bundle(path, opts \\ []) do
    with {:ok, bundle} <- PortableBundle.read(path),
         :ok <- validate_manifest(bundle.manifest),
         :ok <- verify_bundle_checksum(bundle),
         {:ok, import_plan} <- build_import_plan(bundle, opts),
         {:ok, imported} <- import_artifacts(bundle, import_plan) do
      persist_import(bundle, import_plan, imported)
    end
  end

  defp validate_manifest(%{
         "format_version" => 1,
         "checksum" => checksum,
         "asset_blobs" => blobs,
         "audit_report" => audit_report,
         "template" => template
       })
       when is_binary(checksum) and is_list(blobs) and is_map(audit_report) and is_map(template) do
    validate_asset_blob_content_types(blobs)
  end

  defp validate_manifest(%{"format_version" => version}) when version != 1,
    do: {:error, {:unsupported_bundle_format, version}}

  defp validate_manifest(_manifest), do: {:error, :invalid_bundle_manifest}

  defp validate_asset_blob_content_types(blobs) do
    blobs
    |> Enum.reduce_while(%{}, fn blob, seen ->
      case asset_blob_metadata(blob) do
        {:ok, hash, content_type} ->
          validate_asset_blob_content_type(seen, hash, content_type)

        :error ->
          {:halt, {:error, :invalid_bundle_manifest}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      _content_types_by_hash -> :ok
    end
  end

  defp asset_blob_metadata(%{
         "sha256" => hash,
         "content_type" => content_type,
         "filename" => filename,
         "path" => path,
         "size" => size
       }) do
    case {
      nonempty_binary(hash),
      nonempty_binary(content_type),
      binary_value(filename),
      nonempty_binary(path),
      nonnegative_integer(size)
    } do
      {{:ok, hash}, {:ok, content_type}, {:ok, _filename}, {:ok, _path}, {:ok, _size}} ->
        {:ok, hash, content_type}

      _invalid ->
        :error
    end
  end

  defp asset_blob_metadata(_blob), do: :error

  defp nonempty_binary(value) when is_binary(value) and value != "", do: {:ok, value}
  defp nonempty_binary(_value), do: :error
  defp binary_value(value) when is_binary(value), do: {:ok, value}
  defp binary_value(_value), do: :error
  defp nonnegative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp nonnegative_integer(_value), do: :error

  defp validate_asset_blob_content_type(seen, hash, content_type) do
    if String.match?(hash, ~r/\A[0-9a-f]{64}\z/) do
      case Map.fetch(seen, hash) do
        :error ->
          {:cont, Map.put(seen, hash, content_type)}

        {:ok, ^content_type} ->
          {:cont, seen}

        {:ok, existing_content_type} ->
          {:halt, {:error, {:duplicate_asset_content_type_mismatch, hash, existing_content_type, content_type}}}
      end
    else
      {:halt, {:error, :invalid_bundle_manifest}}
    end
  end

  defp build_import_plan(bundle, opts) do
    fields = import_plan_fields(bundle, opts)

    with :ok <- validate_visibility(fields.visibility),
         :ok <- validate_owner(fields.visibility, fields.owner_id),
         :ok <- validate_materialization_inputs(fields.verify_workspace_id, fields.verify_user_id),
         :ok <- validate_source_project_owner(fields),
         :ok <- validate_user_exists(fields.owner_id, :owner_id),
         :ok <- validate_user_exists(fields.published_by_id, :published_by_id),
         :ok <- validate_user_exists(fields.source_user_id, :source_user_id),
         :ok <- validate_public_source_manager(fields),
         :ok <- validate_workspace_exists(fields.verify_workspace_id),
         :ok <- validate_source_project_scope(fields),
         {:ok, existing_template} <-
           resolve_existing_template(fields.visibility, fields.owner_id, fields.slug, opts) do
      plan =
        fields
        |> Map.put(:existing_template, existing_template)
        |> Map.put(:import_suffix, SnapshotStorage.unique_key_suffix())

      with :ok <- validate_template_plan(plan) do
        {:ok, plan}
      end
    end
  end

  defp import_plan_fields(bundle, opts) do
    template = Map.get(bundle.manifest, "template", %{})
    name = plan_name(template, opts)
    owner_id = normalize_integer(option(opts, :owner_id))
    verify_user_id = normalize_integer(option(opts, :verify_user_id))

    %{
      name: name,
      slug: plan_slug(template, opts, name),
      description: plan_description(template, opts),
      visibility: plan_visibility(opts),
      owner_id: owner_id,
      source_user_id: source_user_id(plan_visibility(opts), owner_id, verify_user_id),
      published_by_id: plan_published_by_id(opts, owner_id, verify_user_id),
      verify_user_id: verify_user_id,
      verify_workspace_id: normalize_integer(option(opts, :verify_workspace_id)),
      version_notes: plan_version_notes(template, opts),
      repair_legacy_snapshot: truthy?(option(opts, :repair_legacy_snapshot))
    }
  end

  defp plan_name(template, opts), do: option(opts, :name) || template["name"] || "Imported Template"

  defp plan_slug(template, opts, name) do
    normalize_slug(option(opts, :slug) || template["slug"] || name)
  end

  defp plan_description(template, opts), do: option(opts, :description) || template["description"]

  defp plan_visibility(opts), do: normalize_string(option(opts, :visibility) || "private")

  defp plan_published_by_id(opts, owner_id, verify_user_id) do
    normalize_integer(option(opts, :published_by_id)) || owner_id || verify_user_id
  end

  defp plan_version_notes(template, opts), do: option(opts, :version_notes) || template["version_notes"]

  defp normalize_slug(value) do
    value
    |> safe_string()
    |> NameNormalizer.slugify()
  end

  defp validate_visibility(visibility) when visibility in @visibilities, do: :ok
  defp validate_visibility(visibility), do: {:error, {:invalid_visibility, visibility}}

  defp validate_owner("private", owner_id) when is_integer(owner_id), do: :ok
  defp validate_owner("private", _owner_id), do: {:error, :private_template_requires_owner_id}
  defp validate_owner("public", _owner_id), do: :ok

  defp validate_materialization_inputs(workspace_id, user_id) when is_integer(workspace_id) and is_integer(user_id),
    do: :ok

  defp validate_materialization_inputs(_workspace_id, _user_id),
    do: {:error, :template_import_requires_materialization_scope}

  defp validate_source_project_owner(%{visibility: "private", owner_id: owner_id, verify_user_id: owner_id}), do: :ok

  defp validate_source_project_owner(%{visibility: "private"}),
    do: {:error, :private_template_owner_must_match_verify_user}

  defp validate_source_project_owner(%{visibility: "public"}), do: :ok

  defp validate_public_source_manager(%{visibility: "private"}), do: :ok

  defp validate_public_source_manager(%{visibility: "public", source_user_id: source_user_id}) do
    case Repo.get(User, source_user_id) do
      %User{is_super_admin: true} -> :ok
      %User{} -> {:error, :public_template_source_requires_super_admin}
    end
  end

  defp validate_user_exists(nil, _field), do: :ok

  defp validate_user_exists(user_id, field) when is_integer(user_id) do
    if Repo.exists?(from user in User, where: user.id == ^user_id) do
      :ok
    else
      {:error, {:user_not_found, field, user_id}}
    end
  end

  defp validate_user_exists(user_id, field), do: {:error, {:invalid_user_id, field, user_id}}

  defp validate_workspace_exists(workspace_id) when is_integer(workspace_id) do
    if Repo.exists?(from workspace in Workspace, where: workspace.id == ^workspace_id) do
      :ok
    else
      {:error, {:workspace_not_found, workspace_id}}
    end
  end

  defp validate_workspace_exists(workspace_id), do: {:error, {:invalid_workspace_id, workspace_id}}

  defp validate_source_project_scope(%{source_user_id: source_user_id, verify_workspace_id: workspace_id}) do
    case Workspaces.authorize(Scope.for_user(Repo.get!(User, source_user_id)), workspace_id, :create_project) do
      {:ok, _workspace, _membership} -> :ok
      {:error, reason} -> {:error, {:source_project_unauthorized, reason}}
    end
  end

  defp source_user_id("private", owner_id, _verify_user_id), do: owner_id
  defp source_user_id("public", _owner_id, verify_user_id), do: verify_user_id
  defp source_user_id(_visibility, _owner_id, _verify_user_id), do: nil

  defp validate_template_plan(%{existing_template: nil} = plan) do
    owner_id = if plan.visibility == "private", do: plan.owner_id

    %ProjectTemplate{owner_id: owner_id}
    |> ProjectTemplate.create_changeset(%{
      "name" => plan.name,
      "slug" => plan.slug,
      "description" => plan.description,
      "visibility" => plan.visibility,
      "status" => "active"
    })
    |> changeset_result()
  end

  defp validate_template_plan(%{existing_template: %ProjectTemplate{source_project_id: source_project_id}})
       when is_integer(source_project_id), do: {:error, :template_source_already_materialized}

  defp validate_template_plan(%{existing_template: %ProjectTemplate{} = template} = plan) do
    template
    |> ProjectTemplate.update_changeset(%{
      "name" => plan.name,
      "description" => plan.description,
      "status" => "active"
    })
    |> changeset_result()
  end

  defp changeset_result(%Ecto.Changeset{valid?: true}), do: :ok
  defp changeset_result(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp resolve_existing_template("private", owner_id, slug, opts) do
    resolve_existing_template(Repo.get_by(ProjectTemplate, owner_id: owner_id, slug: slug), slug, opts)
  end

  defp resolve_existing_template("public", _owner_id, slug, opts) do
    resolve_existing_template(Repo.get_by(ProjectTemplate, visibility: "public", slug: slug), slug, opts)
  end

  defp resolve_existing_template(existing_template, slug, opts) do
    cond do
      is_nil(existing_template) ->
        {:ok, nil}

      truthy?(option(opts, :update_existing)) ->
        {:ok, existing_template}

      true ->
        {:error, {:template_slug_exists, slug}}
    end
  end

  defp import_artifacts(bundle, plan) do
    with {:ok, prepared_snapshot, repair_report} <- prepare_snapshot(bundle.snapshot, plan),
         {:ok, imported_blobs} <- upload_bundle_assets(bundle, plan) do
      case import_uploaded_artifacts(
             bundle,
             plan,
             prepared_snapshot,
             repair_report,
             imported_blobs
           ) do
        {:error, reason, cleanup_keys} -> cleanup_import_failure(reason, cleanup_keys)
        result -> result
      end
    else
      {:error, reason, cleanup_keys} ->
        cleanup_import_failure(reason, cleanup_keys)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_uploaded_artifacts(bundle, plan, prepared_snapshot, repair_report, imported_blobs) do
    snapshot = rewrite_snapshot_assets(prepared_snapshot, imported_blobs)
    asset_manifest = rewrite_asset_manifest(bundle.asset_manifest, imported_blobs)

    with {:ok, materialization_report} <-
           verify_import_materialization(snapshot, plan, imported_blobs),
         {:ok, snapshot_key, asset_manifest_key} <-
           store_import_artifacts(plan, imported_blobs, snapshot, asset_manifest) do
      {:ok,
       %{
         imported_blob_keys: Map.values(imported_blobs),
         snapshot: snapshot,
         asset_manifest: asset_manifest,
         snapshot_key: snapshot_key,
         asset_manifest_key: asset_manifest_key,
         checksum: Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => asset_manifest}),
         materialization_report: materialization_report,
         repair_report: repair_report,
         preview: Artifact.preview(snapshot, asset_manifest)
       }}
    end
  rescue
    error ->
      cleanup_uploaded_artifacts!(plan, imported_blobs)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      cleanup_uploaded_artifacts!(plan, imported_blobs)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp prepare_snapshot(snapshot, %{repair_legacy_snapshot: true}) do
    LegacySnapshotRepair.repair(snapshot)
  end

  defp prepare_snapshot(snapshot, _plan), do: {:ok, snapshot, nil}

  defp preview_legacy_repair(snapshot, opts) do
    if truthy?(option(opts, :repair_legacy_snapshot)) do
      case LegacySnapshotRepair.repair(snapshot) do
        {:ok, _repaired_snapshot, report} -> {:ok, report}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  defp put_repair_preview(manifest, nil), do: Map.delete(manifest, "legacy_snapshot_repair")

  defp put_repair_preview(manifest, report) do
    manifest
    |> Map.delete("legacy_snapshot_repair")
    |> Map.put("legacy_snapshot_repair", report)
  end

  defp upload_bundle_assets(bundle, plan) do
    cleanup_keys = bundle_asset_cleanup_keys(bundle.manifest["asset_blobs"], plan)

    try do
      bundle.files
      |> PortableBundle.asset_files(bundle.manifest)
      |> Enum.reduce_while({:ok, %{}}, fn {blob, data}, {:ok, uploaded} ->
        case upload_or_reuse_bundle_asset(blob, data, plan, uploaded) do
          {:ok, uploaded} -> {:cont, {:ok, uploaded}}
          {:error, reason, cleanup_keys} -> {:halt, {:error, reason, cleanup_keys}}
        end
      end)
    rescue
      error ->
        cleanup_storage_keys!(cleanup_keys, :template_import_blob_upload_cleanup_failed)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        cleanup_storage_keys!(cleanup_keys, :template_import_blob_upload_cleanup_failed)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp bundle_asset_cleanup_keys(blobs, plan) do
    blobs
    |> Enum.map(&bundle_asset_key(&1, plan))
    |> Enum.uniq()
  end

  defp upload_or_reuse_bundle_asset(blob, data, plan, uploaded) do
    hash = blob["sha256"]

    case Map.fetch(uploaded, hash) do
      {:ok, _existing_key} -> validate_reused_bundle_asset(blob, data, uploaded)
      :error -> upload_new_bundle_asset(blob, data, plan, uploaded, hash)
    end
  end

  defp validate_reused_bundle_asset(blob, data, uploaded) do
    case validate_bundle_asset(blob, data) do
      :ok -> {:ok, uploaded}
      {:error, reason} -> {:error, reason, Map.values(uploaded)}
    end
  end

  defp upload_new_bundle_asset(blob, data, plan, uploaded, hash) do
    case upload_bundle_asset(blob, data, plan) do
      {:ok, ^hash, key} ->
        {:ok, Map.put(uploaded, hash, key)}

      {:error, reason, attempted_key} ->
        {:error, reason, [attempted_key | Map.values(uploaded)]}

      {:error, reason} ->
        {:error, reason, Map.values(uploaded)}
    end
  end

  defp store_import_artifacts(plan, imported_blobs, snapshot, asset_manifest) do
    blob_keys = Map.values(imported_blobs)

    case store_import_artifact(plan, "snapshot", snapshot) do
      {:ok, snapshot_key} ->
        case store_import_artifact(plan, "asset-manifest", asset_manifest) do
          {:ok, asset_manifest_key} ->
            {:ok, snapshot_key, asset_manifest_key}

          {:error, reason, asset_manifest_key} ->
            {:error, reason, [asset_manifest_key, snapshot_key | blob_keys]}
        end

      {:error, reason, snapshot_key} ->
        {:error, reason, [snapshot_key | blob_keys]}
    end
  end

  defp upload_bundle_asset(blob, data, plan) do
    hash = blob["sha256"]

    with :ok <- validate_bundle_asset(blob, data) do
      key = bundle_asset_key(blob, plan)

      case Storage.upload(key, data, blob["content_type"]) do
        {:ok, _url} -> {:ok, hash, key}
        {:error, reason} -> {:error, {:asset_upload_failed, blob["path"], reason}, key}
      end
    end
  end

  defp bundle_asset_key(blob, plan) do
    filename = safe_filename(blob)
    "project_templates/imported_blobs/#{plan.slug}/#{plan.import_suffix}/#{blob["sha256"]}/#{filename}"
  end

  defp validate_bundle_asset(blob, nil), do: {:error, {:missing_asset_blob, blob["path"]}}

  defp validate_bundle_asset(blob, data) do
    hash = blob["sha256"]

    cond do
      sha256(data) != hash -> {:error, {:asset_checksum_mismatch, blob["path"]}}
      byte_size(data) != blob["size"] -> {:error, {:asset_size_mismatch, blob["path"]}}
      true -> :ok
    end
  end

  defp verify_import_materialization(snapshot, plan, imported_blobs) do
    case Audit.verify_snapshot_materialization(snapshot, plan.verify_workspace_id, plan.verify_user_id,
           name: "Template Import #{plan.slug}"
         ) do
      {:ok, report} ->
        {:ok, report}

      {:error, report} ->
        {:error, {:template_materialization_failed, report}, Map.values(imported_blobs)}
    end
  end

  defp verify_bundle_checksum(bundle) do
    checksum = PortableBundle.checksum(bundle.snapshot, bundle.asset_manifest, bundle.manifest["asset_blobs"])

    if checksum == bundle.manifest["checksum"] do
      :ok
    else
      {:error, :bundle_checksum_mismatch}
    end
  end

  defp store_import_artifact(plan, name, data) do
    key = import_artifact_key(plan, name)

    case SnapshotStorage.store_raw(key, data) do
      {:ok, _size_bytes} -> {:ok, key}
      {:error, reason} -> {:error, reason, key}
    end
  end

  defp import_artifact_key(plan, name) do
    "project_templates/imports/#{plan.slug}/#{plan.import_suffix}/#{name}.json.gz"
  end

  defp persist_import(bundle, plan, imported) do
    tracker = StorageCompensation.new()

    try do
      result =
        Repo.transact(
          fn ->
            with_import_storage_locks(imported, fn ->
              with {:ok, plan} <- lock_existing_template(plan),
                   :ok <- lock_source_project_scope(plan),
                   {:ok, source_project} <- materialize_source_project(plan, imported, tracker),
                   {:ok, template} <- create_or_update_template(plan, source_project),
                   {:ok, version} <- create_version(bundle, plan, imported, template, source_project),
                   {:ok, template} <- set_current_version(template, version),
                   :ok <- StorageCompensation.prepare_unretained_cleanup(tracker) do
                {:ok,
                 Repo.preload(
                   template,
                   [:current_version, :source_project],
                   force: true
                 )}
              end
            end)
          end,
          timeout: :infinity
        )

      finalize_persisted_import(result, tracker, imported)
    rescue
      error ->
        cleanup_failed_import!(tracker, imported)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        cleanup_failed_import!(tracker, imported)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp lock_existing_template(%{existing_template: nil} = plan), do: {:ok, plan}

  defp lock_existing_template(%{existing_template: %ProjectTemplate{id: template_id}} = plan) do
    case ProjectTemplate
         |> where([template], template.id == ^template_id)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      %ProjectTemplate{source_project_id: nil} = template ->
        {:ok, %{plan | existing_template: template}}

      %ProjectTemplate{} ->
        {:error, :template_source_already_materialized}

      nil ->
        {:error, :template_not_found}
    end
  end

  defp with_import_storage_locks(imported, fun) do
    imported
    |> import_storage_keys()
    |> Enum.reduce(fun, fn storage_key, continuation ->
      fn -> StorageKeyLock.with_storage_key_lock(storage_key, continuation) end
    end)
    |> then(& &1.())
  end

  defp import_storage_keys(imported) do
    (imported.imported_blob_keys ++ [imported.snapshot_key, imported.asset_manifest_key])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  defp finalize_persisted_import({:ok, template}, tracker, _imported) do
    StorageCompensation.discard(tracker)
    {:ok, template}
  end

  defp finalize_persisted_import({:error, reason}, tracker, imported) do
    cleanup_result = StorageCompensation.cleanup(tracker)
    artifact_cleanup_result = cleanup_imported_artifacts(imported)

    case {cleanup_result, artifact_cleanup_result} do
      {:ok, :ok} ->
        {:error, reason}

      {source_cleanup, artifact_cleanup} ->
        {:error,
         {:template_import_storage_cleanup_failed, reason,
          %{source_project: source_cleanup, import_artifacts: artifact_cleanup}}}
    end
  end

  defp lock_source_project_scope(plan) do
    with %User{} = source_user <- lock_source_user(plan.source_user_id),
         :ok <- authorize_locked_source_manager(plan.visibility, source_user),
         :ok <- Projects.lock_and_check_workspace_capacity(plan.verify_workspace_id),
         %WorkspaceMembership{role: role} <-
           WorkspaceMembership
           |> where(
             [membership],
             membership.workspace_id == ^plan.verify_workspace_id and
               membership.user_id == ^plan.source_user_id
           )
           |> lock("FOR SHARE")
           |> Repo.one(),
         true <- Workspaces.can?(role, :create_project) do
      :ok
    else
      nil -> {:error, :source_project_unauthorized}
      false -> {:error, :source_project_unauthorized}
      {:error, _reason} = error -> error
      {:error, reason, details} -> {:error, {reason, details}}
    end
  end

  defp lock_source_user(source_user_id) do
    User
    |> where([user], user.id == ^source_user_id)
    |> lock("FOR SHARE")
    |> Repo.one()
  end

  defp authorize_locked_source_manager("private", %User{}), do: :ok
  defp authorize_locked_source_manager("public", %User{is_super_admin: true}), do: :ok
  defp authorize_locked_source_manager("public", %User{}), do: {:error, :public_template_source_requires_super_admin}

  defp materialize_source_project(plan, imported, tracker) do
    ProjectRecovery.recover_project(
      plan.verify_workspace_id,
      imported.snapshot,
      plan.source_user_id,
      name: source_project_name(plan, imported.snapshot),
      template_clone: true,
      asset_error_mode: :strict,
      asset_copy_tracker: tracker
    )
  end

  defp source_project_name(plan, snapshot) do
    case get_in(snapshot, ["project", "name"]) do
      name when is_binary(name) and name != "" -> name
      _name -> "#{plan.name} Source"
    end
  end

  defp create_or_update_template(%{existing_template: nil} = plan, source_project) do
    owner_id = if plan.visibility == "private", do: plan.owner_id

    %ProjectTemplate{owner_id: owner_id, source_project_id: source_project.id}
    |> ProjectTemplate.create_changeset(%{
      "name" => plan.name,
      "slug" => plan.slug,
      "description" => plan.description,
      "visibility" => plan.visibility,
      "status" => "active"
    })
    |> Repo.insert()
  end

  defp create_or_update_template(%{existing_template: %ProjectTemplate{} = template} = plan, source_project) do
    if template.visibility == plan.visibility do
      template
      |> ProjectTemplate.update_changeset(%{
        "name" => plan.name,
        "description" => plan.description,
        "status" => "active"
      })
      |> Ecto.Changeset.put_change(:source_project_id, source_project.id)
      |> Repo.update()
    else
      {:error, {:template_visibility_mismatch, template.visibility, plan.visibility}}
    end
  end

  defp create_version(bundle, plan, imported, template, source_project) do
    now = TimeHelpers.now()

    %ProjectTemplateVersion{
      project_template_id: template.id,
      source_project_id: source_project.id,
      published_by_id: plan.published_by_id
    }
    |> ProjectTemplateVersion.create_changeset(%{
      "version_number" => next_version_number(template),
      "snapshot_storage_key" => imported.snapshot_key,
      "asset_manifest_storage_key" => imported.asset_manifest_key,
      "checksum" => imported.checksum,
      "version_notes" => plan.version_notes,
      "entity_counts" => Map.get(imported.snapshot, "entity_counts", %{}),
      "preview" => imported.preview,
      "audit_report" => import_audit_report(bundle, imported),
      "published_at" => now
    })
    |> Repo.insert()
  end

  defp next_version_number(%ProjectTemplate{id: template_id}) do
    max_version =
      Repo.one(
        from(version in ProjectTemplateVersion,
          where: version.project_template_id == ^template_id,
          select: max(version.version_number)
        )
      )

    (max_version || 0) + 1
  end

  defp set_current_version(template, version) do
    template
    |> ProjectTemplate.current_version_changeset(version.id)
    |> Repo.update()
  end

  defp import_audit_report(bundle, imported) do
    report =
      Map.put(bundle.manifest["audit_report"], "import_materialization", imported.materialization_report)

    case imported.repair_report do
      nil -> report
      repair_report -> Map.put(report, "legacy_snapshot_repair", repair_report)
    end
  end

  defp rewrite_snapshot_assets(value, imported_blobs) when is_map(value) do
    value =
      case {value["asset_metadata"], value["asset_blob_hashes"]} do
        {metadata, hashes} when is_map(metadata) and is_map(hashes) ->
          Map.put(value, "asset_metadata", rewrite_asset_metadata(metadata, hashes, imported_blobs))

        _other ->
          value
      end

    Map.new(value, fn {key, nested} -> {key, rewrite_snapshot_assets(nested, imported_blobs)} end)
  end

  defp rewrite_snapshot_assets(value, imported_blobs) when is_list(value) do
    Enum.map(value, &rewrite_snapshot_assets(&1, imported_blobs))
  end

  defp rewrite_snapshot_assets(value, _imported_blobs), do: value

  defp rewrite_asset_metadata(metadata, hashes, imported_blobs) do
    Map.new(metadata, fn {asset_id, asset_metadata} ->
      blob_hash = hashes[to_string(asset_id)]

      asset_metadata =
        if is_map(asset_metadata) and is_binary(blob_hash) and Map.has_key?(imported_blobs, blob_hash) do
          key = imported_blobs[blob_hash]

          asset_metadata
          |> Map.put("blob_key", key)
          |> Map.put("key", key)
          |> Map.put("url", Storage.get_url(key))
        else
          asset_metadata
        end

      {asset_id, asset_metadata}
    end)
  end

  defp rewrite_asset_manifest(asset_manifest, imported_blobs) do
    assets =
      asset_manifest
      |> Map.get("assets", [])
      |> Enum.map(fn asset ->
        case imported_blobs[asset["blob_hash"]] do
          nil ->
            asset

          key ->
            asset
            |> Map.put("key", key)
            |> Map.put("url", Storage.get_url(key))
        end
      end)

    asset_manifest
    |> Map.put("assets", assets)
    |> Map.put("asset_count", length(assets))
  end

  defp cleanup_imported_artifacts(imported) do
    cleanup_storage_keys(imported.imported_blob_keys ++ [imported.snapshot_key, imported.asset_manifest_key])
  end

  defp cleanup_failed_import!(tracker, imported) do
    source_cleanup = StorageCompensation.cleanup(tracker)
    artifact_cleanup = cleanup_imported_artifacts(imported)

    case {source_cleanup, artifact_cleanup} do
      {:ok, :ok} ->
        :ok

      cleanup_results ->
        raise StorageCleanupPersistenceError,
          reason: {:template_import_storage_cleanup_failed, cleanup_results}
    end
  end

  defp safe_filename(blob) do
    filename =
      blob["filename"]
      |> safe_string()
      |> Storyarn.Assets.sanitize_filename()

    if filename == "", do: "#{blob["sha256"]}.bin", else: filename
  end

  defp option(opts, key) do
    cond do
      is_list(opts) ->
        Keyword.get(opts, key) || Enum.find_value(opts, &matching_option(&1, key))

      is_map(opts) ->
        Map.get(opts, key) || Map.get(opts, to_string(key))

      true ->
        nil
    end
  end

  defp matching_option({option_key, value}, key) do
    if to_string(option_key) == to_string(key), do: value
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "yes"], do: true
  defp truthy?(_value), do: false

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp cleanup_storage_keys(keys) do
    failures =
      keys
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reduce([], fn key, failures ->
        case StorageCompensation.delete_or_enqueue(key) do
          :ok -> failures
          {:error, reason} -> [{key, reason} | failures]
        end
      end)

    case Enum.reverse(failures) do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  defp cleanup_import_failure(reason, cleanup_keys) do
    case cleanup_storage_keys(cleanup_keys) do
      :ok -> {:error, reason}
      {:error, cleanup_reason} -> {:error, {:template_import_artifact_cleanup_failed, reason, cleanup_reason}}
    end
  end

  defp cleanup_uploaded_artifacts!(plan, imported_blobs) do
    cleanup_keys =
      Map.values(imported_blobs) ++
        [
          import_artifact_key(plan, "snapshot"),
          import_artifact_key(plan, "asset-manifest")
        ]

    cleanup_storage_keys!(cleanup_keys, :template_import_artifact_cleanup_failed)
  end

  defp cleanup_storage_keys!(cleanup_keys, error_tag) do
    case cleanup_storage_keys(cleanup_keys) do
      :ok ->
        :ok

      {:error, cleanup_reason} ->
        raise StorageCleanupPersistenceError,
          reason: {error_tag, cleanup_reason}
    end
  end

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value), do: safe_string(value)

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> value
    end
  end

  defp normalize_integer(value), do: value

  defp safe_string(nil), do: ""
  defp safe_string(value), do: to_string(value)
end
