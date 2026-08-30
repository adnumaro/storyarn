defmodule Storyarn.Projects.Assets.Commands.AssetRegistration do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.StorageKey
  alias Storyarn.Projects.Persistence.UserRecord
  alias Storyarn.Projects.Persistence.WorkspaceRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References.ProjectReferenceIntegrity
  alias Storyarn.Repo

  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type receipt :: %{asset_id: pos_integer(), project_id: pos_integer()}

  @doc false
  @spec register_uploaded_asset(pos_integer(), pos_integer() | nil, map(), :generic | :sanitized_svg) ::
          {:ok, receipt()} | {:error, term()}
  def register_uploaded_asset(project_id, uploaded_by_id, attrs, upload_kind)
      when is_integer(project_id) and project_id > 0 and
             (is_nil(uploaded_by_id) or (is_integer(uploaded_by_id) and uploaded_by_id > 0)) and is_map(attrs) and
             upload_kind in [:generic, :sanitized_svg] do
    register_asset(project_id, uploaded_by_id, attrs, upload_kind)
  end

  def register_uploaded_asset(_project_id, _uploaded_by_id, _attrs, _upload_kind),
    do: {:error, :invalid_asset_registration}

  @doc false
  @spec register_materialized_asset(pos_integer(), pos_integer() | nil, map()) ::
          {:ok, receipt()} | {:error, term()}
  def register_materialized_asset(project_id, uploaded_by_id, attrs)
      when is_integer(project_id) and project_id > 0 and
             (is_nil(uploaded_by_id) or (is_integer(uploaded_by_id) and uploaded_by_id > 0)) and is_map(attrs) do
    register_asset(project_id, uploaded_by_id, attrs, :snapshot_restore)
  end

  def register_materialized_asset(_project_id, _uploaded_by_id, _attrs), do: {:error, :invalid_asset_registration}

  @doc false
  @spec link_asset_variant(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, receipt()} | {:error, term()}
  def link_asset_variant(project_id, original_id, variant_id)
      when is_integer(project_id) and project_id > 0 and is_integer(original_id) and original_id > 0 and
             is_integer(variant_id) and variant_id > 0 and original_id != variant_id do
    with :ok <- require_transaction(),
         {:ok, _project} <- lock_active_project(project_id),
         {:ok, original, variant} <- lock_variant_pair(project_id, original_id, variant_id),
         {:ok, _updated_original} <- update_variant_link(original, variant) do
      {:ok, receipt(original)}
    end
  end

  def link_asset_variant(_project_id, _original_id, _variant_id), do: {:error, :invalid_asset_variant_link}

  defp register_asset(project_id, uploaded_by_id, attrs, upload_kind) do
    with :ok <- require_transaction(),
         {:ok, _project} <- lock_active_project(project_id),
         :ok <- validate_user(uploaded_by_id),
         :ok <- validate_project_storage_key(project_id, attrs),
         :ok <- validate_blob_hash(attrs),
         :ok <- lock_asset_family_references(project_id, attrs),
         {:ok, asset} <- insert_asset(project_id, uploaded_by_id, attrs, upload_kind) do
      {:ok, receipt(asset)}
    end
  end

  defp require_transaction do
    if Repo.in_transaction?(), do: :ok, else: {:error, :asset_write_transaction_required}
  end

  defp lock_active_project(project_id) do
    with {:ok, workspace_id} <- project_workspace_id(project_id),
         :ok <- lock_workspace(workspace_id) do
      do_lock_active_project(project_id, workspace_id)
    end
  end

  # Asset registration participates in storage-accounted workflows. Every
  # current sealed consumer enters through the canonical Workspace -> Project
  # order, so this lock is reentrant there. A caller must never enter after
  # acquiring Project before Workspace: this command can enforce its own order,
  # but cannot repair locks already taken by its enclosing transaction. The
  # privileged-entrypoint ratchet forces that precondition to be reviewed for
  # every future caller.
  defp lock_workspace(workspace_id) do
    case Repo.one(
           from(workspace in WorkspaceRecord,
             where: workspace.id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %WorkspaceRecord{} -> :ok
      nil -> {:error, :project_not_found}
    end
  end

  defp do_lock_active_project(project_id, workspace_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and project.workspace_id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp project_workspace_id(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, select: project.workspace_id)) do
      workspace_id when is_integer(workspace_id) and workspace_id > 0 -> {:ok, workspace_id}
      nil -> {:error, :project_not_found}
    end
  end

  defp validate_user(nil), do: :ok

  defp validate_user(uploaded_by_id) do
    if Repo.exists?(from(user in UserRecord, where: user.id == ^uploaded_by_id)),
      do: :ok,
      else: {:error, :user_not_found}
  end

  defp validate_project_storage_key(project_id, attrs) do
    if StorageKey.project_asset_route_key?(project_id, attr(attrs, :key)),
      do: :ok,
      else: {:error, :invalid_project_asset_storage_key}
  end

  defp validate_blob_hash(attrs) do
    case attr(attrs, :blob_hash) do
      blob_hash when is_binary(blob_hash) ->
        if Regex.match?(@sha256_regex, blob_hash),
          do: :ok,
          else: {:error, :invalid_asset_blob_hash}

      _blob_hash ->
        {:error, :invalid_asset_blob_hash}
    end
  end

  defp lock_asset_family_references(project_id, attrs) do
    case Asset.family_reference_ids(attr(attrs, :metadata)) do
      {:ok, asset_ids} ->
        specs = Enum.map(asset_ids, &{:asset, {:asset_family, nil}, &1})

        case ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
          {:ok, _locked_ids} -> :ok
          {:error, _reason} = error -> error
        end

      :error ->
        {:error, :invalid_asset_family_metadata}
    end
  end

  defp insert_asset(project_id, uploaded_by_id, attrs, upload_kind) do
    asset = %Asset{project_id: project_id, uploaded_by_id: uploaded_by_id}

    asset
    |> registration_changeset(attrs, upload_kind)
    |> Repo.insert()
    |> normalize_insert_result()
  end

  defp registration_changeset(asset, attrs, :generic), do: Asset.create_changeset(asset, attrs)

  defp registration_changeset(asset, attrs, :sanitized_svg), do: Asset.create_sanitized_svg_changeset(asset, attrs)

  defp registration_changeset(asset, attrs, :snapshot_restore), do: Asset.snapshot_restore_changeset(asset, attrs)

  defp normalize_insert_result({:ok, %Asset{} = asset}), do: {:ok, asset}

  defp normalize_insert_result({:error, changeset}) do
    if unique_key_error?(changeset),
      do: {:error, :asset_storage_key_collision},
      else: {:error, :asset_registration_rejected}
  end

  defp unique_key_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:key, {_message, metadata}} -> metadata[:constraint] == :unique
      _error -> false
    end)
  end

  defp unique_key_error?(_changeset), do: false

  defp lock_variant_pair(project_id, original_id, variant_id) do
    assets =
      Repo.all(
        from(asset in Asset,
          where:
            asset.id in ^Enum.sort([original_id, variant_id]) and
              asset.project_id == ^project_id and is_nil(asset.deleted_at),
          order_by: [asc: asset.id],
          lock: "FOR UPDATE"
        )
      )

    with %Asset{} = original <- Enum.find(assets, &(&1.id == original_id)),
         %Asset{} = variant <- Enum.find(assets, &(&1.id == variant_id)) do
      {:ok, original, variant}
    else
      nil -> {:error, :asset_variant_link_target_not_found}
    end
  end

  defp update_variant_link(original, variant) do
    metadata =
      Map.merge(original.metadata || %{}, %{
        "web_url" => variant.url,
        "web_asset_id" => variant.id
      })

    original
    |> Asset.update_changeset(%{metadata: metadata})
    |> Repo.update()
    |> case do
      {:ok, updated_original} -> {:ok, updated_original}
      {:error, _changeset} -> {:error, :asset_variant_link_rejected}
    end
  end

  defp receipt(%Asset{} = asset), do: %{asset_id: asset.id, project_id: asset.project_id}

  defp attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
