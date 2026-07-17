defmodule Storyarn.ProjectTemplates.PortableImport do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Storage
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.LegacySnapshotRepair
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces.Workspace

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
       when is_binary(checksum) and is_list(blobs) and is_map(audit_report) and is_map(template), do: :ok

  defp validate_manifest(%{"format_version" => version}) when version != 1,
    do: {:error, {:unsupported_bundle_format, version}}

  defp validate_manifest(_manifest), do: {:error, :invalid_bundle_manifest}

  defp build_import_plan(bundle, opts) do
    fields = import_plan_fields(bundle, opts)

    with :ok <- validate_visibility(fields.visibility),
         :ok <- validate_owner(fields.visibility, fields.owner_id),
         :ok <- validate_materialization_inputs(fields.verify_workspace_id, fields.verify_user_id),
         :ok <- validate_user_exists(fields.owner_id, :owner_id),
         :ok <- validate_user_exists(fields.published_by_id, :published_by_id),
         :ok <- validate_workspace_exists(fields.verify_workspace_id),
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
         {:ok, imported_blobs} <- upload_bundle_assets(bundle, plan),
         snapshot = rewrite_snapshot_assets(prepared_snapshot, imported_blobs),
         asset_manifest = rewrite_asset_manifest(bundle.asset_manifest, imported_blobs),
         {:ok, materialization_report} <- verify_import_materialization(snapshot, plan, imported_blobs),
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
    else
      {:error, reason, cleanup_keys} ->
        cleanup_storage_keys(cleanup_keys)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
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

  defp put_repair_preview(manifest, nil), do: manifest
  defp put_repair_preview(manifest, report), do: Map.put(manifest, "legacy_snapshot_repair", report)

  defp upload_bundle_assets(bundle, plan) do
    bundle.files
    |> PortableBundle.asset_files(bundle.manifest)
    |> Enum.reduce_while({:ok, %{}}, fn {blob, data}, {:ok, uploaded} ->
      case upload_bundle_asset(blob, data, plan) do
        {:ok, hash, key} -> {:cont, {:ok, Map.put(uploaded, hash, key)}}
        {:error, reason} -> {:halt, {:error, reason, Map.values(uploaded)}}
      end
    end)
  end

  defp store_import_artifacts(plan, imported_blobs, snapshot, asset_manifest) do
    blob_keys = Map.values(imported_blobs)

    case store_import_artifact(plan, "snapshot", snapshot) do
      {:ok, snapshot_key} ->
        case store_import_artifact(plan, "asset-manifest", asset_manifest) do
          {:ok, asset_manifest_key} -> {:ok, snapshot_key, asset_manifest_key}
          {:error, reason} -> {:error, reason, [snapshot_key | blob_keys]}
        end

      {:error, reason} ->
        {:error, reason, blob_keys}
    end
  end

  defp upload_bundle_asset(blob, nil, _plan), do: {:error, {:missing_asset_blob, blob["path"]}}

  defp upload_bundle_asset(blob, data, plan) do
    hash = blob["sha256"]

    with ^hash <- sha256(data),
         true <- byte_size(data) == blob["size"],
         filename = safe_filename(blob),
         key = "project_templates/imported_blobs/#{plan.slug}/#{plan.import_suffix}/#{hash}/#{filename}",
         {:ok, _url} <- Storage.upload(key, data, blob["content_type"]) do
      {:ok, hash, key}
    else
      false -> {:error, {:asset_size_mismatch, blob["path"]}}
      {:error, reason} -> {:error, {:asset_upload_failed, blob["path"], reason}}
      _hash_mismatch -> {:error, {:asset_checksum_mismatch, blob["path"]}}
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
    key = "project_templates/imports/#{plan.slug}/#{plan.import_suffix}/#{name}.json.gz"

    case SnapshotStorage.store_raw(key, data) do
      {:ok, _size_bytes} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_import(bundle, plan, imported) do
    result =
      Repo.transact(fn ->
        with {:ok, template} <- create_or_update_template(plan),
             {:ok, version} <- create_version(bundle, plan, imported, template),
             {:ok, template} <- set_current_version(template, version) do
          {:ok, Repo.preload(template, [:current_version], force: true)}
        end
      end)

    case result do
      {:ok, template} ->
        {:ok, template}

      {:error, reason} ->
        cleanup_imported_artifacts(imported)
        {:error, reason}
    end
  end

  defp create_or_update_template(%{existing_template: nil} = plan) do
    owner_id = if plan.visibility == "private", do: plan.owner_id

    %ProjectTemplate{owner_id: owner_id}
    |> ProjectTemplate.create_changeset(%{
      "name" => plan.name,
      "slug" => plan.slug,
      "description" => plan.description,
      "visibility" => plan.visibility,
      "status" => "active"
    })
    |> Repo.insert()
  end

  defp create_or_update_template(%{existing_template: %ProjectTemplate{} = template} = plan) do
    if template.visibility == plan.visibility do
      template
      |> ProjectTemplate.update_changeset(%{
        "name" => plan.name,
        "description" => plan.description,
        "status" => "active"
      })
      |> Repo.update()
    else
      {:error, {:template_visibility_mismatch, template.visibility, plan.visibility}}
    end
  end

  defp create_version(bundle, plan, imported, template) do
    now = TimeHelpers.now()

    %ProjectTemplateVersion{
      project_template_id: template.id,
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
    keys
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn key ->
      case Storage.delete(key) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
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
