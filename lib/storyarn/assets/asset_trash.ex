defmodule Storyarn.Assets.AssetTrash do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @type reference_scope :: :active | :any
  @type reference_check :: ([pos_integer()], reference_scope() -> :ok | {:error, term()})
  @type cleanup_targets :: (Asset.t() -> [String.t()])

  @doc false
  @spec prepare_cleanup_locked([Asset.t()], cleanup_targets()) ::
          {:ok, struct() | nil} | {:error, term()}
  def prepare_cleanup_locked([], cleanup_targets) when is_function(cleanup_targets, 1), do: {:ok, nil}

  def prepare_cleanup_locked(assets, cleanup_targets) when is_list(assets) and is_function(cleanup_targets, 1) do
    cleanup_targets_by_asset = Enum.map(assets, &cleanup_targets.(&1))
    targets = cleanup_targets_by_asset |> List.flatten() |> Enum.uniq()

    with true <-
           Enum.all?(cleanup_targets_by_asset, &(&1 != [])) ||
             {:error, :asset_cleanup_not_authorized},
         {:ok, request} <- persist_cleanup_request(targets),
         true <-
           MapSet.equal?(MapSet.new(request.storage_keys), MapSet.new(targets)) ||
             {:error, :asset_cleanup_not_authorized} do
      {:ok, request}
    end
  end

  defp persist_cleanup_request(targets) do
    case StorageCompensation.persist_planned_cleanup_request(targets) do
      {:error, :no_valid_storage_keys} -> {:error, :asset_cleanup_not_authorized}
      result -> result
    end
  end

  @doc false
  @spec active_family_ids(pos_integer(), pos_integer()) :: [pos_integer()]
  def active_family_ids(project_id, asset_id)
      when is_integer(project_id) and project_id > 0 and is_integer(asset_id) and asset_id > 0 do
    assets =
      Repo.all(
        from(asset in Asset,
          where: asset.project_id == ^project_id,
          order_by: [asc: asset.id]
        )
      )

    case Enum.find(assets, &(&1.id == asset_id)) do
      %Asset{deleted_at: nil} ->
        family_ids = family_component_ids(assets, [asset_id])

        for %Asset{id: id, deleted_at: nil} <- assets,
            MapSet.member?(family_ids, id),
            do: id

      _missing_or_trashed ->
        []
    end
  end

  def active_family_ids(_project_id, _asset_id), do: []

  @spec move_locked(
          pos_integer(),
          pos_integer(),
          [pos_integer()],
          pos_integer() | nil,
          String.t(),
          reference_check(),
          keyword()
        ) :: {:ok, Asset.t()} | {:error, term()}
  def move_locked(project_id, workspace_id, asset_ids, actor_id, reason, reference_check, opts \\ [])
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 and
             is_list(asset_ids) and is_function(reference_check, 2) do
    with :ok <- require_workspace_lock(workspace_id),
         {:ok, _project} <- lock_active_project(project_id, workspace_id),
         {:ok, assets} <- lock_project_assets(project_id),
         {:ok, requested} <- requested_assets(assets, asset_ids, :active),
         {:ok, targets} <- move_targets(assets, requested, Keyword.get(opts, :expand_family, false)),
         :ok <- ensure_metadata_targets_exist(assets, targets),
         :ok <- ensure_no_external_metadata_links(targets),
         :ok <- reference_check.(Enum.map(targets, & &1.id), :active),
         {:ok, updated} <- trash_assets(targets, actor_id, reason) do
      {:ok, updated_asset(updated, hd(requested).id)}
    end
  end

  @spec restore_locked(
          pos_integer(),
          pos_integer(),
          pos_integer(),
          non_neg_integer()
        ) :: {:ok, Asset.t()} | {:error, term()}
  def restore_locked(project_id, workspace_id, asset_id, expected_generation)
      when is_integer(asset_id) and asset_id > 0 and is_integer(expected_generation) and expected_generation >= 0 do
    with :ok <- require_workspace_lock(workspace_id),
         {:ok, _project} <- lock_active_project(project_id, workspace_id),
         {:ok, assets} <- lock_project_assets(project_id),
         {:ok, root} <- requested_asset(assets, asset_id, :trashed),
         :ok <- match_generation(root, expected_generation),
         targets = trashed_family(assets, [root.id]),
         :ok <- ensure_metadata_targets_exist(assets, targets),
         :ok <- ensure_no_external_metadata_links(targets),
         :ok <- ensure_restore_relationships(assets, targets),
         {:ok, updated} <- restore_assets(targets) do
      {:ok, updated_asset(updated, asset_id)}
    end
  end

  @spec purge_locked(
          pos_integer(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          reference_check(),
          cleanup_targets(),
          keyword()
        ) :: {:ok, Asset.t()} | {:error, term()}
  def purge_locked(project_id, workspace_id, asset_id, expected_generation, reference_check, cleanup_targets, opts \\ [])
      when is_integer(asset_id) and asset_id > 0 and is_integer(expected_generation) and expected_generation >= 0 and
             is_function(reference_check, 2) and is_function(cleanup_targets, 1) and is_list(opts) do
    with :ok <- require_workspace_lock(workspace_id),
         {:ok, project} <- lock_active_project(project_id, workspace_id),
         {:ok, assets} <- lock_project_assets(project_id),
         {:ok, root} <- requested_asset(assets, asset_id, :trashed),
         :ok <- match_generation(root, expected_generation),
         :ok <- validate_purge_expectations(project, root, opts),
         targets = trashed_family(assets, [root.id]),
         :ok <- ensure_purge_relationships(assets, targets),
         :ok <- ensure_metadata_targets_exist(assets, targets),
         :ok <- ensure_no_external_metadata_links(targets),
         :ok <- reference_check.(Enum.map(targets, & &1.id), :any),
         {:ok, deleted} <- delete_assets(targets, cleanup_targets) do
      {:ok, updated_asset(deleted, asset_id)}
    end
  end

  @spec purge_many_locked(
          pos_integer(),
          pos_integer(),
          [{pos_integer(), non_neg_integer()}],
          reference_check(),
          cleanup_targets()
        ) :: {:ok, [Asset.t()]} | {:error, term()}
  def purge_many_locked(project_id, workspace_id, candidates, reference_check, cleanup_targets)
      when is_list(candidates) and is_function(reference_check, 2) and is_function(cleanup_targets, 1) do
    with :ok <- require_workspace_lock(workspace_id),
         {:ok, _project} <- lock_active_project(project_id, workspace_id),
         {:ok, assets} <- lock_project_assets(project_id),
         {:ok, requested} <- requested_candidate_assets(assets, candidates),
         targets = trashed_family(assets, Enum.map(requested, & &1.id)),
         :ok <- ensure_purge_relationships(assets, targets),
         :ok <- ensure_metadata_targets_exist(assets, targets),
         :ok <- ensure_no_external_metadata_links(targets),
         :ok <- reference_check.(Enum.map(targets, & &1.id), :any) do
      delete_assets(targets, cleanup_targets)
    end
  end

  defp require_workspace_lock(workspace_id) do
    if Billing.workspace_lock_held?(workspace_id),
      do: :ok,
      else: {:error, :storage_accounting_lock_required}
  end

  defp lock_active_project(project_id, workspace_id) do
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

  defp lock_project_assets(project_id) do
    {:ok,
     Repo.all(
       from(asset in Asset,
         where: asset.project_id == ^project_id,
         order_by: [asc: asset.id],
         lock: "FOR UPDATE"
       )
     )}
  end

  defp requested_assets(_assets, [], _state), do: {:error, :asset_ids_required}

  defp requested_assets(assets, asset_ids, state) do
    valid_ids? = Enum.all?(asset_ids, &(is_integer(&1) and &1 > 0))
    asset_ids = Enum.uniq(asset_ids)
    by_id = Map.new(assets, &{&1.id, &1})

    if valid_ids? and asset_ids != [] and Enum.all?(asset_ids, &Map.has_key?(by_id, &1)) do
      requested = Enum.map(asset_ids, &Map.fetch!(by_id, &1))

      if Enum.all?(requested, &in_state?(&1, state)),
        do: {:ok, requested},
        else: {:error, state_error(state)}
    else
      {:error, :asset_not_found}
    end
  end

  defp requested_asset(assets, asset_id, state) do
    with {:ok, [asset]} <- requested_assets(assets, [asset_id], state) do
      {:ok, asset}
    end
  end

  defp requested_candidate_assets(assets, candidates) do
    valid_candidates? =
      candidates != [] and
        Enum.all?(candidates, fn
          {asset_id, generation} ->
            is_integer(asset_id) and asset_id > 0 and is_integer(generation) and generation >= 0

          _invalid ->
            false
        end)

    if valid_candidates? do
      requested_candidate_assets(assets, candidates, Map.new(candidates))
    else
      {:error, :invalid_asset_trash_request}
    end
  end

  defp requested_candidate_assets(assets, candidates, candidates_by_id) do
    with true <- map_size(candidates_by_id) == length(candidates) || {:error, :invalid_asset_trash_request},
         {:ok, requested} <- requested_assets(assets, Map.keys(candidates_by_id), :trashed),
         true <-
           Enum.all?(requested, &(&1.deletion_generation == Map.fetch!(candidates_by_id, &1.id))) ||
             {:error, :asset_trash_generation_changed} do
      {:ok, requested}
    end
  end

  defp in_state?(%Asset{deleted_at: nil}, :active), do: true
  defp in_state?(%Asset{deleted_at: %DateTime{}}, :trashed), do: true
  defp in_state?(_asset, _state), do: false

  defp state_error(:active), do: :asset_already_trashed
  defp state_error(:trashed), do: :asset_not_trashed

  defp move_targets(assets, requested, true) do
    component_ids = family_component_ids(assets, Enum.map(requested, & &1.id))
    component = Enum.filter(assets, &MapSet.member?(component_ids, &1.id))

    if Enum.all?(component, &is_nil(&1.deleted_at)),
      do: {:ok, component},
      else: {:error, :asset_family_state_conflict}
  end

  defp move_targets(assets, requested, false) do
    requested_ids = MapSet.new(requested, & &1.id)
    component_ids = family_component_ids(assets, MapSet.to_list(requested_ids))

    if MapSet.equal?(requested_ids, component_ids),
      do: {:ok, requested},
      else: {:error, :asset_family_incomplete}
  end

  defp trashed_family(assets, root_ids) do
    component_ids = family_component_ids(assets, root_ids)

    Enum.filter(assets, fn asset ->
      MapSet.member?(component_ids, asset.id) and not is_nil(asset.deleted_at)
    end)
  end

  defp ensure_restore_relationships(assets, targets) do
    target_ids = MapSet.new(targets, & &1.id)
    component_ids = family_component_ids(assets, MapSet.to_list(target_ids))

    if MapSet.equal?(target_ids, component_ids),
      do: :ok,
      else: {:error, :asset_family_incomplete}
  end

  defp ensure_metadata_targets_exist(assets, targets) do
    known_ids = MapSet.new(assets, & &1.id)

    with {:ok, referenced_ids} <- collect_metadata_reference_ids(targets),
         true <- MapSet.subset?(referenced_ids, known_ids) do
      :ok
    else
      _invalid -> {:error, :asset_family_identity_invalid}
    end
  end

  defp ensure_no_external_metadata_links(targets) do
    target_ids = Enum.map(targets, & &1.id)
    encoded_target_ids = Enum.map(target_ids, &Integer.to_string/1)

    external_link? =
      Repo.exists?(
        from(asset in Asset,
          where: asset.id not in ^target_ids,
          where:
            fragment("?->>'web_asset_id' = ANY(?)", asset.metadata, ^encoded_target_ids) or
              fragment("?->>'original_asset_id' = ANY(?)", asset.metadata, ^encoded_target_ids) or
              fragment(
                """
                EXISTS (
                  SELECT 1
                  FROM jsonb_each_text(
                    CASE
                      WHEN jsonb_typeof(?->'variant_asset_ids') = 'object'
                      THEN ?->'variant_asset_ids'
                      ELSE '{}'::jsonb
                    END
                  ) AS variant_link
                  WHERE variant_link.value = ANY(?)
                )
                """,
                asset.metadata,
                asset.metadata,
                ^encoded_target_ids
              )
        )
      )

    if external_link?, do: {:error, :asset_family_identity_invalid}, else: :ok
  end

  defp ensure_purge_relationships(assets, targets) do
    target_ids = MapSet.new(targets, & &1.id)
    component_ids = family_component_ids(assets, MapSet.to_list(target_ids))
    outside_ids = MapSet.difference(component_ids, target_ids)

    if MapSet.size(outside_ids) == 0,
      do: :ok,
      else: {:error, :asset_family_still_referenced}
  end

  defp family_component_ids(assets, root_ids) do
    known_ids = MapSet.new(assets, & &1.id)

    adjacency =
      Enum.reduce(assets, Map.new(assets, &{&1.id, MapSet.new()}), fn asset, graph ->
        asset.metadata
        |> metadata_reference_ids()
        |> Enum.filter(&MapSet.member?(known_ids, &1))
        |> Enum.reduce(graph, fn referenced_id, graph ->
          graph
          |> Map.update!(asset.id, &MapSet.put(&1, referenced_id))
          |> Map.update!(referenced_id, &MapSet.put(&1, asset.id))
        end)
      end)

    walk_component(adjacency, MapSet.new(root_ids), root_ids)
  end

  defp walk_component(_adjacency, visited, []), do: visited

  defp walk_component(adjacency, visited, [id | rest]) do
    unseen = adjacency |> Map.get(id, MapSet.new()) |> MapSet.difference(visited)
    walk_component(adjacency, MapSet.union(visited, unseen), rest ++ MapSet.to_list(unseen))
  end

  defp metadata_reference_ids(metadata) when is_map(metadata) do
    case Asset.family_reference_ids(metadata) do
      {:ok, ids} -> Enum.uniq(ids)
      :error -> []
    end
  end

  defp metadata_reference_ids(_metadata), do: []

  defp collect_metadata_reference_ids(assets) do
    Enum.reduce_while(assets, {:ok, MapSet.new()}, fn asset, {:ok, ids} ->
      case Asset.family_reference_ids(asset.metadata) do
        {:ok, asset_ids} -> {:cont, {:ok, MapSet.union(ids, MapSet.new(asset_ids))}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp match_generation(%Asset{deletion_generation: expected}, expected), do: :ok
  defp match_generation(_asset, _expected), do: {:error, :asset_trash_generation_changed}

  defp validate_purge_expectations(project, asset, opts) do
    with :ok <- match_expected_value(project.settings, opts[:expected_project_settings]),
         :ok <- match_expected_value(asset.deleted_at, opts[:expected_deleted_at]),
         :ok <- ensure_not_before(opts[:not_before]) do
      :ok
    else
      {:error, _reason} -> {:error, :asset_trash_retention_changed}
    end
  end

  defp match_expected_value(_current, nil), do: :ok
  defp match_expected_value(current, current), do: :ok
  defp match_expected_value(_current, _expected), do: {:error, :changed}

  defp ensure_not_before(nil), do: :ok

  defp ensure_not_before(%DateTime{} = not_before) do
    if DateTime.compare(TimeHelpers.now(), not_before) in [:eq, :gt],
      do: :ok,
      else: {:error, :not_expired}
  end

  defp ensure_not_before(_invalid), do: {:error, :invalid_not_before}

  defp trash_assets(assets, actor_id, reason) do
    now = TimeHelpers.now()

    Enum.reduce_while(assets, {:ok, []}, fn asset, {:ok, updated} ->
      case asset |> Asset.trash_changeset(actor_id, reason, now) |> Repo.update() do
        {:ok, asset} -> {:cont, {:ok, [asset | updated]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_assets(assets) do
    Enum.reduce_while(assets, {:ok, []}, fn asset, {:ok, updated} ->
      case asset |> Asset.restore_changeset() |> Repo.update() do
        {:ok, asset} -> {:cont, {:ok, [asset | updated]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_assets(assets, cleanup_targets) do
    with {:ok, _request} <- prepare_cleanup_locked(assets, cleanup_targets) do
      delete_asset_rows(assets)
    end
  end

  defp delete_asset_rows(assets) do
    Enum.reduce_while(assets, {:ok, []}, fn asset, {:ok, deleted} ->
      case Repo.delete(asset) do
        {:ok, asset} -> {:cont, {:ok, [asset | deleted]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp updated_asset(assets, asset_id) do
    Enum.find(assets, &(&1.id == asset_id)) || raise "asset trash result lost requested asset"
  end
end
