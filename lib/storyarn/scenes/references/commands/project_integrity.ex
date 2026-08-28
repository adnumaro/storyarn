defmodule Storyarn.Scenes.References.Commands.ProjectIntegrity do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.References.Projections.AssetRecord
  alias Storyarn.Scenes.References.Projections.FlowRecord
  alias Storyarn.Scenes.References.Projections.ProjectRecord
  alias Storyarn.Scenes.References.Projections.SheetRecord
  alias Storyarn.Scenes.Scene

  @reference_types [:asset, :flow, :scene, :sheet]
  @project_lock_modes [:key_share, :share, :update]
  @max_pg_bigint 9_223_372_036_854_775_807

  @type reference_type :: :asset | :flow | :scene | :sheet
  @type reference_context :: term()
  @type reference_spec :: {reference_type(), reference_context(), term()}
  @type validation_error :: {:invalid_project_reference, reference_context(), term()}
  @type project_lock_mode :: :key_share | :share | :update

  @spec lock_active_project(term(), project_lock_mode()) ::
          {:ok, ProjectRecord.t()}
          | {:error, :project_not_found | :project_not_active | {:invalid_project_id, term()}}
  def lock_active_project(project_id, lock_mode \\ :share)

  def lock_active_project(project_id, lock_mode) when lock_mode in @project_lock_modes do
    ensure_transaction!()

    with {:ok, normalized_project_id} <- normalize_required_id(project_id) do
      query =
        ProjectRecord
        |> where([project], project.id == ^normalized_project_id)
        |> apply_project_lock(lock_mode)

      case Repo.one(query) do
        %ProjectRecord{deleted_at: nil} = project -> {:ok, project}
        %ProjectRecord{} -> {:error, :project_not_active}
        nil -> {:error, :project_not_found}
      end
    end
  end

  def lock_active_project(project_id, _lock_mode), do: {:error, {:invalid_project_id, project_id}}

  @spec lock_active_references(integer(), [reference_spec()]) ::
          {:ok, [integer() | nil]} | {:error, validation_error()}
  def lock_active_references(project_id, specs) when is_integer(project_id) and project_id > 0 and is_list(specs) do
    ensure_transaction!()

    with {:ok, normalized_specs} <- normalize_specs(specs),
         :ok <- lock_reference_sets(project_id, normalized_specs) do
      {:ok, Enum.map(normalized_specs, &elem(&1, 2))}
    end
  end

  def lock_active_references(_project_id, [{_type, context, value} | _rest]) do
    {:error, {:invalid_project_reference, context, value}}
  end

  def lock_active_references(_project_id, []), do: {:ok, []}

  @doc """
  Locks the specs' targets and returns their ids positionally, mapping
  unresolvable or inactive targets to `nil` instead of returning an error.

  Reference projections drop those rows: pins and zones may legitimately point
  at trashed flows or sheets (surfaced by the stale_* health codes), so
  projection writes must reproduce that state rather than reject it.
  """
  @spec lock_active_reference_ids(integer(), [reference_spec()]) :: [integer() | nil]
  def lock_active_reference_ids(project_id, specs) when is_integer(project_id) and project_id > 0 and is_list(specs) do
    ensure_transaction!()

    normalized =
      Enum.map(specs, fn
        {type, _context, value} when type in @reference_types ->
          case normalize_optional_id(value) do
            {:ok, id} -> {type, id}
            :error -> {type, nil}
          end

        _invalid_spec ->
          {nil, nil}
      end)

    allowed = allowed_reference_set(project_id, normalized)

    Enum.map(normalized, fn {type, id} ->
      if not is_nil(id) and MapSet.member?(allowed, {type, id}), do: id
    end)
  end

  @spec ensure_locked_asset_content_type(integer(), integer() | nil, reference_context(), String.t()) ::
          :ok | {:error, {:invalid_asset_content_type, reference_context(), term()}}
  def ensure_locked_asset_content_type(_project_id, nil, _context, _pattern) do
    ensure_transaction!()
    :ok
  end

  def ensure_locked_asset_content_type(project_id, asset_id, context, pattern)
      when is_integer(project_id) and project_id > 0 and is_integer(asset_id) and asset_id > 0 and is_binary(pattern) do
    ensure_transaction!()

    case Repo.one(active_asset_content_type_query(project_id, asset_id, pattern)) do
      ^asset_id -> :ok
      nil -> {:error, {:invalid_asset_content_type, context, asset_id}}
    end
  end

  def ensure_locked_asset_content_type(_project_id, asset_id, context, _pattern),
    do: {:error, {:invalid_asset_content_type, context, asset_id}}

  @spec normalize_optional_id(term()) :: {:ok, integer() | nil} | :error
  def normalize_optional_id(nil), do: {:ok, nil}
  def normalize_optional_id(""), do: {:ok, nil}

  def normalize_optional_id(id) when is_integer(id) and id > 0 and id <= @max_pg_bigint, do: {:ok, id}

  def normalize_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 and parsed <= @max_pg_bigint -> {:ok, parsed}
      _other -> :error
    end
  end

  def normalize_optional_id(_id), do: :error

  defp active_asset_content_type_query(project_id, asset_id, pattern) do
    from(asset in AssetRecord,
      where:
        asset.id == ^asset_id and asset.project_id == ^project_id and
          is_nil(asset.deleted_at) and like(asset.content_type, ^pattern),
      select: asset.id
    )
  end

  defp normalize_required_id(value) do
    case normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _other -> {:error, {:invalid_project_id, value}}
    end
  end

  defp normalize_specs(specs) do
    specs
    |> Enum.reduce_while({:ok, []}, fn
      {type, context, value}, {:ok, normalized} when type in @reference_types ->
        case normalize_optional_id(value) do
          {:ok, id} -> {:cont, {:ok, [{type, context, id, value} | normalized]}}
          :error -> {:halt, {:error, {:invalid_project_reference, context, value}}}
        end

      {_type, context, value}, _acc ->
        {:halt, {:error, {:invalid_project_reference, context, value}}}

      invalid_spec, _acc ->
        {:halt, {:error, {:invalid_project_reference, :invalid_spec, invalid_spec}}}
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp lock_reference_sets(project_id, specs) do
    allowed = allowed_reference_set(project_id, Enum.map(specs, fn {type, _context, id, _value} -> {type, id} end))

    case Enum.find(specs, fn {type, _context, id, _value} ->
           not is_nil(id) and not MapSet.member?(allowed, {type, id})
         end) do
      nil -> :ok
      {_type, context, _id, value} -> {:error, {:invalid_project_reference, context, value}}
    end
  end

  defp allowed_reference_set(project_id, typed_ids) do
    Enum.reduce(@reference_types, MapSet.new(), fn type, acc ->
      ids =
        typed_ids
        |> Enum.filter(&(elem(&1, 0) == type))
        |> Enum.map(&elem(&1, 1))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      Enum.reduce(lock_reference_ids(type, project_id, ids), acc, fn id, set ->
        MapSet.put(set, {type, id})
      end)
    end)
  end

  defp lock_reference_ids(_type, _project_id, []), do: []

  defp lock_reference_ids(:asset, project_id, ids) do
    Repo.all(
      from(asset in AssetRecord,
        where:
          asset.id in ^ids and asset.project_id == ^project_id and
            is_nil(asset.deleted_at),
        order_by: [asc: asset.id],
        lock: "FOR SHARE",
        select: asset.id
      )
    )
  end

  defp lock_reference_ids(:flow, project_id, ids), do: lock_active_hierarchical_ids(FlowRecord, project_id, ids)

  defp lock_reference_ids(:scene, project_id, ids), do: lock_active_hierarchical_ids(Scene, project_id, ids)

  defp lock_reference_ids(:sheet, project_id, ids), do: lock_active_hierarchical_ids(SheetRecord, project_id, ids)

  defp lock_active_hierarchical_ids(schema, project_id, ids) do
    Repo.all(
      from(target in schema,
        where:
          target.id in ^ids and target.project_id == ^project_id and
            is_nil(target.deleted_at),
        order_by: [asc: target.id],
        lock: "FOR SHARE",
        select: target.id
      )
    )
  end

  defp ensure_transaction! do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "scene project reference integrity checks require an explicit database transaction"
    end
  end

  defp apply_project_lock(query, :key_share), do: lock(query, "FOR KEY SHARE")
  defp apply_project_lock(query, :share), do: lock(query, "FOR SHARE")
  defp apply_project_lock(query, :update), do: lock(query, "FOR UPDATE")
end
