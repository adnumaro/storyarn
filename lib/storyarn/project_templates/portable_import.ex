defmodule Storyarn.ProjectTemplates.PortableImport do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces.Workspace

  require Logger

  @visibilities ~w(private public)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @max_asset_size 52_428_800

  @spec preview_bundle(String.t()) :: {:ok, map()} | {:error, term()}
  def preview_bundle(path) do
    with {:ok, bundle} <- PortableBundle.read(path),
         :ok <- validate_manifest(bundle.manifest),
         :ok <- validate_bundle_preflight(bundle),
         :ok <- verify_bundle_checksum(bundle) do
      {:ok, bundle.manifest}
    end
  end

  @spec import_bundle(String.t(), keyword()) :: {:ok, ProjectTemplate.t()} | {:error, term()}
  def import_bundle(path, opts \\ []) do
    with {:ok, bundle} <- PortableBundle.read(path),
         :ok <- validate_manifest(bundle.manifest),
         :ok <- validate_bundle_preflight(bundle),
         :ok <- verify_bundle_checksum(bundle),
         {:ok, import_plan} <- build_import_plan(bundle, opts) do
      import_with_compensation(bundle, import_plan)
    end
  end

  defp import_with_compensation(bundle, plan) do
    tracker = StorageCompensation.new()
    success_key = {__MODULE__, :import_succeeded, tracker}

    try do
      result =
        with {:ok, imported} <- import_artifacts(bundle, plan, tracker) do
          persist_import(bundle, plan, imported)
        end

      if match?({:ok, %ProjectTemplate{}}, result), do: Process.put(success_key, true)
      result
    rescue
      error ->
        Logger.error("Portable template import failed: #{Exception.message(error)}")
        {:error, {:template_import_failed, error.__struct__}}
    catch
      kind, reason ->
        Logger.error("Portable template import failed: #{inspect(kind)} #{inspect(reason)}")
        {:error, {:template_import_failed, kind}}
    after
      if Process.get(success_key) do
        StorageCompensation.discard(tracker)
      else
        StorageCompensation.cleanup!(tracker)
      end

      Process.delete(success_key)
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

  defp validate_bundle_preflight(bundle) do
    with :ok <- validate_snapshot_shape(bundle.snapshot),
         :ok <- validate_snapshot_sequence_integrity(bundle.snapshot),
         {:ok, snapshot_assets} <- snapshot_asset_catalog(bundle.snapshot),
         {:ok, manifest_assets} <- asset_manifest_catalog(bundle.asset_manifest),
         {:ok, blobs_by_asset_id} <- blob_catalog(bundle) do
      validate_asset_catalog_consistency(
        snapshot_assets,
        manifest_assets,
        blobs_by_asset_id
      )
    end
  rescue
    _error -> {:error, :invalid_bundle_snapshot}
  catch
    _kind, _reason -> {:error, :invalid_bundle_snapshot}
  end

  defp validate_snapshot_shape(%{
         "format_version" => 2,
         "project" => project,
         "entity_counts" => entity_counts,
         "asset_blob_hashes" => asset_blob_hashes,
         "asset_metadata" => asset_metadata,
         "sheets" => sheets,
         "flows" => flows,
         "scenes" => scenes,
         "tree" => %{"sheets" => tree_sheets, "flows" => tree_flows, "scenes" => tree_scenes},
         "localization" => %{"languages" => languages, "texts" => texts, "glossary" => glossary}
       }) do
    with true <-
           valid_snapshot_root_shape?(
             [project, entity_counts, asset_blob_hashes, asset_metadata],
             [
               sheets,
               flows,
               scenes,
               tree_sheets,
               tree_flows,
               tree_scenes,
               languages,
               texts,
               glossary
             ]
           ),
         :ok <- validate_snapshot_entities(sheets, :sheet),
         :ok <- validate_snapshot_entities(flows, :flow),
         :ok <- validate_snapshot_entities(scenes, :scene),
         true <- Enum.all?(tree_sheets ++ tree_flows ++ tree_scenes, &is_map/1),
         true <- Enum.all?(languages ++ texts ++ glossary, &is_map/1) do
      :ok
    else
      false -> {:error, :invalid_bundle_snapshot}
      {:error, _reason} = error -> error
    end
  end

  defp validate_snapshot_shape(_snapshot), do: {:error, :invalid_bundle_snapshot}

  defp valid_snapshot_root_shape?(maps, lists) do
    Enum.all?(maps, &is_map/1) and Enum.all?(lists, &is_list/1)
  end

  defp validate_snapshot_entities(entries, type) do
    if Enum.all?(entries, fn
         %{"id" => id, "snapshot" => snapshot} ->
           valid_asset_id?(id) and valid_entity_snapshot_shape?(type, snapshot)

         _entry ->
           false
       end) do
      :ok
    else
      {:error, :invalid_bundle_snapshot}
    end
  end

  defp valid_entity_snapshot_shape?(:sheet, %{
         "blocks" => blocks,
         "avatars" => avatars,
         "hidden_inherited_block_ids" => hidden_ids,
         "asset_blob_hashes" => hashes,
         "asset_metadata" => metadata,
         "localization" => localization,
         "localization_manifest" => localization_manifest
       }) do
    is_list(blocks) and is_list(avatars) and is_list(hidden_ids) and is_map(hashes) and
      is_map(metadata) and is_list(localization) and is_map(localization_manifest)
  end

  defp valid_entity_snapshot_shape?(:flow, %{
         "nodes" => nodes,
         "connections" => connections,
         "referenced_sheets" => referenced_sheets,
         "asset_blob_hashes" => hashes,
         "asset_metadata" => metadata,
         "localization" => localization,
         "localization_manifest" => localization_manifest
       }) do
    is_list(nodes) and is_list(connections) and is_map(referenced_sheets) and is_map(hashes) and
      is_map(metadata) and is_list(localization) and is_map(localization_manifest)
  end

  defp valid_entity_snapshot_shape?(:scene, %{
         "layers" => layers,
         "orphan_zones" => orphan_zones,
         "orphan_pins" => orphan_pins,
         "orphan_annotations" => orphan_annotations,
         "connections" => connections,
         "ambient_flows" => ambient_flows,
         "asset_blob_hashes" => hashes,
         "asset_metadata" => metadata
       }) do
    Enum.all?(
      [layers, orphan_zones, orphan_pins, orphan_annotations, connections, ambient_flows],
      &is_list/1
    ) and is_map(hashes) and is_map(metadata)
  end

  defp valid_entity_snapshot_shape?(_type, _snapshot), do: false

  defp validate_snapshot_sequence_integrity(snapshot) do
    case Audit.validate_snapshot_integrity(snapshot) do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_bundle_snapshot, errors}}
    end
  end

  defp snapshot_asset_catalog(snapshot) do
    collect_snapshot_asset_catalog(snapshot, %{})
  end

  defp collect_snapshot_asset_catalog(value, catalog) when is_map(value) do
    with {:ok, catalog} <- merge_local_snapshot_assets(value, catalog) do
      value
      |> Map.drop(["asset_blob_hashes", "asset_metadata"])
      |> Map.values()
      |> collect_snapshot_asset_values(catalog)
    end
  end

  defp collect_snapshot_asset_catalog(value, catalog) when is_list(value) do
    collect_snapshot_asset_values(value, catalog)
  end

  defp collect_snapshot_asset_catalog(_value, catalog), do: {:ok, catalog}

  defp collect_snapshot_asset_values(values, catalog) do
    Enum.reduce_while(values, {:ok, catalog}, &collect_snapshot_asset_value/2)
  end

  defp collect_snapshot_asset_value(nested, {:ok, accumulated}) do
    case collect_snapshot_asset_catalog(nested, accumulated) do
      {:ok, updated} -> {:cont, {:ok, updated}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp merge_local_snapshot_assets(value, catalog) do
    case {Map.fetch(value, "asset_blob_hashes"), Map.fetch(value, "asset_metadata")} do
      {:error, :error} ->
        {:ok, catalog}

      {{:ok, hashes}, {:ok, metadata}} when is_map(hashes) and is_map(metadata) ->
        merge_snapshot_asset_maps(hashes, metadata, catalog)

      _invalid ->
        {:error, :invalid_bundle_snapshot_asset_catalog}
    end
  end

  defp merge_snapshot_asset_maps(hashes, metadata, catalog) do
    hash_ids = hashes |> Map.keys() |> MapSet.new(&to_string/1)
    metadata_ids = metadata |> Map.keys() |> MapSet.new(&to_string/1)

    if MapSet.equal?(hash_ids, metadata_ids) do
      merge_snapshot_asset_entries(hashes, metadata, catalog)
    else
      {:error, :invalid_bundle_snapshot_asset_catalog}
    end
  end

  defp merge_snapshot_asset_entries(hashes, metadata, catalog) do
    Enum.reduce_while(hashes, {:ok, catalog}, fn entry, {:ok, accumulated} ->
      merge_snapshot_asset_entry(entry, metadata, accumulated)
    end)
  end

  defp merge_snapshot_asset_entry({raw_id, blob_hash}, metadata, accumulated) do
    id = to_string(raw_id)
    asset_metadata = Map.get(metadata, id) || Map.get(metadata, raw_id)

    with {:ok, normalized_id} <- normalize_asset_id(id),
         :ok <- validate_blob_hash(blob_hash),
         {:ok, entry} <- snapshot_asset_entry(normalized_id, blob_hash, asset_metadata),
         {:ok, updated} <- put_consistent_asset(accumulated, normalized_id, entry) do
      {:cont, {:ok, updated}}
    else
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp snapshot_asset_entry(id, blob_hash, %{
         "filename" => filename,
         "content_type" => content_type,
         "size" => size,
         "project_id" => project_id
       }) do
    with :ok <- validate_portable_filename(filename),
         :ok <- validate_portable_content_type(content_type, :snapshot),
         :ok <- validate_asset_size(size),
         true <- is_integer(project_id) and project_id > 0 do
      {:ok,
       %{
         id: id,
         blob_hash: blob_hash,
         filename: filename,
         content_type: content_type,
         size: size,
         project_id: project_id
       }}
    else
      false -> {:error, :invalid_bundle_snapshot_asset_catalog}
      {:error, _reason} = error -> error
    end
  end

  defp snapshot_asset_entry(_id, _blob_hash, _metadata), do: {:error, :invalid_bundle_snapshot_asset_catalog}

  defp put_consistent_asset(catalog, id, entry) do
    case Map.fetch(catalog, id) do
      :error -> {:ok, Map.put(catalog, id, entry)}
      {:ok, ^entry} -> {:ok, catalog}
      {:ok, _different_entry} -> {:error, :conflicting_bundle_snapshot_asset}
    end
  end

  defp asset_manifest_catalog(%{"format_version" => 1, "assets" => assets, "asset_count" => asset_count})
       when is_list(assets) and is_integer(asset_count) and asset_count == length(assets) do
    Enum.reduce_while(assets, {:ok, %{}}, fn asset, {:ok, catalog} ->
      with {:ok, entry} <- manifest_asset_entry(asset),
           false <- Map.has_key?(catalog, entry.id) do
        {:cont, {:ok, Map.put(catalog, entry.id, entry)}}
      else
        true -> {:halt, {:error, :duplicate_bundle_asset_id}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp asset_manifest_catalog(_asset_manifest), do: {:error, :invalid_bundle_asset_manifest}

  defp manifest_asset_entry(%{
         "id" => raw_id,
         "blob_hash" => blob_hash,
         "filename" => filename,
         "content_type" => content_type,
         "size" => size
       }) do
    with {:ok, id} <- normalize_asset_id(raw_id),
         :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_portable_filename(filename),
         :ok <- validate_portable_content_type(content_type, :asset_manifest),
         :ok <- validate_asset_size(size) do
      {:ok,
       %{
         id: id,
         blob_hash: blob_hash,
         filename: filename,
         content_type: content_type,
         size: size
       }}
    end
  end

  defp manifest_asset_entry(_asset), do: {:error, :invalid_bundle_asset_manifest}

  defp blob_catalog(%{manifest: manifest, files: files}) do
    blobs = manifest["asset_blobs"]
    asset_count = manifest["asset_count"]

    with true <- is_list(blobs),
         true <- is_integer(asset_count) and asset_count >= 0 and asset_count == length(blobs),
         {:ok, catalog, paths} <- reduce_blob_catalog(blobs, files),
         :ok <- validate_bundle_file_set(files, paths) do
      {:ok, catalog}
    else
      false -> {:error, :invalid_bundle_asset_catalog}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_blob_catalog(blobs, files) do
    Enum.reduce_while(blobs, {:ok, %{}, MapSet.new()}, fn blob, {:ok, catalog, paths} ->
      with {:ok, entry} <- blob_catalog_entry(blob, files),
           false <- Map.has_key?(catalog, entry.asset_id),
           false <- MapSet.member?(paths, entry.path) do
        {:cont, {:ok, Map.put(catalog, entry.asset_id, entry), MapSet.put(paths, entry.path)}}
      else
        true -> {:halt, {:error, :duplicate_bundle_asset_blob}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp blob_catalog_entry(
         %{
           "asset_id" => raw_asset_id,
           "sha256" => blob_hash,
           "size" => size,
           "content_type" => content_type,
           "path" => path,
           "filename" => filename
         },
         files
       )
       when is_binary(filename) do
    with {:ok, asset_id} <- normalize_asset_id(raw_asset_id),
         :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_asset_size(size),
         :ok <- validate_portable_filename(filename),
         :ok <- validate_portable_content_type(content_type, path),
         :ok <- validate_portable_blob_path(path, blob_hash),
         {:ok, data} <- fetch_blob_file(files, path),
         true <- byte_size(data) == size,
         ^blob_hash <- sha256(data) do
      {:ok,
       %{
         asset_id: asset_id,
         sha256: blob_hash,
         size: size,
         content_type: content_type,
         path: path
       }}
    else
      false -> {:error, {:asset_size_mismatch, path}}
      {:error, _reason} = error -> error
      _hash_mismatch -> {:error, {:asset_checksum_mismatch, path}}
    end
  end

  defp blob_catalog_entry(_blob, _files), do: {:error, :invalid_bundle_asset_catalog}

  defp fetch_blob_file(files, path) do
    case Map.fetch(files, path) do
      {:ok, data} when is_binary(data) -> {:ok, data}
      _missing -> {:error, {:missing_asset_blob, path}}
    end
  end

  defp validate_portable_blob_path(path, blob_hash) when is_binary(path) do
    case String.split(path, "/", trim: false) do
      ["assets", ^blob_hash, filename] ->
        if Storage.canonical_key?(path) and valid_storage_segment?(filename),
          do: :ok,
          else: {:error, :invalid_bundle_asset_path}

      _invalid ->
        {:error, :invalid_bundle_asset_path}
    end
  end

  defp validate_portable_blob_path(_path, _blob_hash), do: {:error, :invalid_bundle_asset_path}

  defp validate_bundle_file_set(files, blob_paths) do
    expected_paths =
      blob_paths
      |> MapSet.put(PortableBundle.manifest_path())
      |> MapSet.put(PortableBundle.snapshot_path())
      |> MapSet.put(PortableBundle.asset_manifest_path())

    if MapSet.equal?(MapSet.new(Map.keys(files)), expected_paths),
      do: :ok,
      else: {:error, :unexpected_bundle_files}
  end

  defp validate_asset_catalog_consistency(snapshot_assets, manifest_assets, blobs_by_asset_id) do
    with true <- MapSet.equal?(MapSet.new(Map.keys(snapshot_assets)), MapSet.new(Map.keys(manifest_assets))),
         :ok <- validate_snapshot_manifest_assets(snapshot_assets, manifest_assets),
         true <-
           MapSet.equal?(
             MapSet.new(Map.keys(manifest_assets)),
             MapSet.new(Map.keys(blobs_by_asset_id))
           ),
         :ok <- validate_manifest_blob_assets(manifest_assets, blobs_by_asset_id) do
      :ok
    else
      false -> {:error, :inconsistent_bundle_asset_catalog}
      {:error, _reason} = error -> error
    end
  end

  defp validate_snapshot_manifest_assets(snapshot_assets, manifest_assets) do
    Enum.reduce_while(snapshot_assets, :ok, fn {id, snapshot_asset}, :ok ->
      manifest_asset = manifest_assets[id]

      if Map.take(snapshot_asset, [:blob_hash, :filename, :content_type, :size]) ==
           Map.take(manifest_asset, [:blob_hash, :filename, :content_type, :size]) do
        {:cont, :ok}
      else
        {:halt, {:error, :inconsistent_bundle_asset_catalog}}
      end
    end)
  end

  defp validate_manifest_blob_assets(manifest_assets, blobs_by_asset_id) do
    Enum.reduce_while(manifest_assets, :ok, fn {id, asset}, :ok ->
      case Map.fetch(blobs_by_asset_id, id) do
        {:ok, blob}
        when blob.sha256 == asset.blob_hash and blob.size == asset.size and
               blob.content_type == asset.content_type ->
          {:cont, :ok}

        _missing_or_conflicting ->
          {:halt, {:error, :inconsistent_bundle_asset_catalog}}
      end
    end)
  end

  defp normalize_asset_id(id) when is_integer(id) and id > 0, do: {:ok, to_string(id)}

  defp normalize_asset_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, Integer.to_string(parsed)}
      _invalid -> {:error, :invalid_bundle_asset_id}
    end
  end

  defp normalize_asset_id(_id), do: {:error, :invalid_bundle_asset_id}

  defp valid_asset_id?(id), do: match?({:ok, _normalized}, normalize_asset_id(id))

  defp validate_blob_hash(blob_hash) when is_binary(blob_hash) do
    if Regex.match?(@sha256_regex, blob_hash),
      do: :ok,
      else: {:error, :invalid_bundle_asset_hash}
  end

  defp validate_blob_hash(_blob_hash), do: {:error, :invalid_bundle_asset_hash}

  defp validate_asset_size(size) when is_integer(size) and size > 0 and size <= @max_asset_size, do: :ok

  defp validate_asset_size(_size), do: {:error, :invalid_bundle_asset_size}

  defp validate_portable_filename(filename) when is_binary(filename) do
    sanitized = if String.valid?(filename), do: Assets.sanitize_filename(filename), else: ""

    if String.valid?(filename) and String.trim(filename) != "" and
         valid_storage_segment?(sanitized) do
      :ok
    else
      {:error, :invalid_bundle_asset_filename}
    end
  end

  defp validate_portable_filename(_filename), do: {:error, :invalid_bundle_asset_filename}

  defp valid_storage_segment?(segment) do
    is_binary(segment) and segment not in ["", ".", ".."] and
      not String.contains?(segment, "/") and Storage.canonical_key?(segment)
  end

  defp validate_portable_content_type("image/svg+xml", source) do
    {:error, {:unsupported_portable_asset_content_type, source, "image/svg+xml"}}
  end

  defp validate_portable_content_type(content_type, _source) when is_binary(content_type) do
    if Asset.allowed_content_type?(content_type),
      do: :ok,
      else: {:error, :invalid_bundle_asset_content_type}
  end

  defp validate_portable_content_type(_content_type, _source), do: {:error, :invalid_bundle_asset_content_type}

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
      version_notes: plan_version_notes(template, opts)
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

  defp import_artifacts(bundle, plan, tracker) do
    with {:ok, imported_blobs} <- upload_bundle_assets(bundle, plan, tracker),
         snapshot = rewrite_snapshot_assets(bundle.snapshot, imported_blobs),
         asset_manifest = rewrite_asset_manifest(bundle.asset_manifest, imported_blobs),
         {:ok, materialization_report} <- verify_import_materialization(snapshot, plan, imported_blobs),
         {:ok, snapshot_key, asset_manifest_key} <-
           store_import_artifacts(plan, snapshot, asset_manifest, tracker) do
      {:ok,
       %{
         imported_blob_keys: Map.values(imported_blobs),
         snapshot: snapshot,
         asset_manifest: asset_manifest,
         snapshot_key: snapshot_key,
         asset_manifest_key: asset_manifest_key,
         checksum: Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => asset_manifest}),
         materialization_report: materialization_report,
         preview: Artifact.preview(snapshot, asset_manifest)
       }}
    end
  end

  defp upload_bundle_assets(bundle, plan, tracker) do
    bundle.files
    |> PortableBundle.asset_files(bundle.manifest)
    |> Enum.reduce_while({:ok, %{}}, fn asset, {:ok, uploaded} ->
      upload_bundle_asset_once(asset, uploaded, plan, tracker)
    end)
  end

  defp upload_bundle_asset_once({blob, data}, uploaded, plan, tracker) do
    hash = blob["sha256"]

    case Map.fetch(uploaded, hash) do
      {:ok, _existing_key} -> {:cont, {:ok, uploaded}}
      :error -> upload_new_bundle_asset(blob, data, hash, uploaded, plan, tracker)
    end
  end

  defp upload_new_bundle_asset(blob, data, hash, uploaded, plan, tracker) do
    case upload_bundle_asset(blob, data, plan, tracker) do
      {:ok, ^hash, key} -> {:cont, {:ok, Map.put(uploaded, hash, key)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp store_import_artifacts(plan, snapshot, asset_manifest, tracker) do
    case store_import_artifact(plan, "snapshot", snapshot, tracker) do
      {:ok, snapshot_key} ->
        case store_import_artifact(plan, "asset-manifest", asset_manifest, tracker) do
          {:ok, asset_manifest_key} -> {:ok, snapshot_key, asset_manifest_key}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_bundle_asset(blob, nil, _plan, _tracker), do: {:error, {:missing_asset_blob, blob["path"]}}

  defp upload_bundle_asset(blob, data, plan, tracker) do
    hash = blob["sha256"]
    key = "project_templates/imported_blobs/#{plan.slug}/#{plan.import_suffix}/#{hash}/blob"

    with ^hash <- sha256(data),
         true <- byte_size(data) == blob["size"],
         :ok <- validate_import_storage_key(key),
         {:ok, _url} <- Storage.upload(key, data, blob["content_type"]),
         :ok <- StorageCompensation.track(tracker, key) do
      {:ok, hash, key}
    else
      false -> {:error, {:asset_size_mismatch, blob["path"]}}
      {:error, :invalid_import_storage_key} -> {:error, {:invalid_asset_storage_key, blob["path"]}}
      {:error, reason} -> {:error, {:asset_upload_failed, blob["path"], reason}}
      _hash_mismatch -> {:error, {:asset_checksum_mismatch, blob["path"]}}
    end
  end

  defp validate_import_storage_key(key) do
    if Storage.canonical_key?(key), do: :ok, else: {:error, :invalid_import_storage_key}
  end

  defp verify_import_materialization(snapshot, plan, imported_blobs) do
    case Audit.verify_snapshot_materialization(snapshot, plan.verify_workspace_id, plan.verify_user_id,
           name: "Template Import #{plan.slug}",
           asset_source_keys: imported_blobs
         ) do
      {:ok, report} ->
        {:ok, report}

      {:error, report} ->
        {:error, {:template_materialization_failed, report}}
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

  defp store_import_artifact(plan, name, data, tracker) do
    key = "project_templates/imports/#{plan.slug}/#{plan.import_suffix}/#{name}.json.gz"

    case SnapshotStorage.store_raw(key, data) do
      {:ok, _size_bytes} ->
        :ok = StorageCompensation.track(tracker, key)
        {:ok, key}

      {:error, reason} ->
        {:error, reason}
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
    Map.put(bundle.manifest["audit_report"], "import_materialization", imported.materialization_report)
  end

  defp rewrite_snapshot_assets(%_struct{} = value, _imported_blobs), do: value

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
