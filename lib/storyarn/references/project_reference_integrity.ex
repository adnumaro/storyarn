defmodule Storyarn.References.ProjectReferenceIntegrity do
  @moduledoc """
  Transactional validation for references that must stay inside one project.

  Foreign keys only prove that a row exists. They cannot express that a target
  belongs to the same project as its source, nor that a soft-deletable target is
  active. Product writers use this module before persisting references.

  Targets are locked with `FOR SHARE`, which conflicts with both hard deletes
  and updates that move a row to trash. Callers must keep the validation and
  write in the same explicit transaction.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets.Sheet

  @reference_types [:asset, :flow, :scene, :sheet]
  @project_lock_modes [:share, :update]

  @type reference_type :: :asset | :flow | :scene | :sheet
  @type reference_context :: term()
  @type reference_spec :: {reference_type(), reference_context(), term()}
  @type validation_error :: {:invalid_project_reference, reference_context(), term()}
  @type project_lock_mode :: :share | :update

  @doc """
  Locks and returns an active project.

  Product writers call this before locking their source row. That common lock
  order makes a project entering trash mutually exclusive with new references
  being committed inside it.
  """
  @spec lock_active_project(term(), project_lock_mode()) ::
          {:ok, Project.t()}
          | {:error, :project_not_found | :project_not_active | {:invalid_project_id, term()}}
  def lock_active_project(project_id, lock_mode \\ :share)

  def lock_active_project(project_id, lock_mode) when lock_mode in @project_lock_modes do
    ensure_transaction!()

    with {:ok, normalized_project_id} <- normalize_required_id(project_id) do
      query =
        Project
        |> where([project], project.id == ^normalized_project_id)
        |> apply_project_lock(lock_mode)

      case Repo.one(query) do
        %Project{deleted_at: nil} = project -> {:ok, project}
        %Project{} -> {:error, :project_not_active}
        nil -> {:error, :project_not_found}
      end
    end
  end

  def lock_active_project(project_id, _lock_mode) do
    {:error, {:invalid_project_id, project_id}}
  end

  @doc """
  Normalizes, validates and locks optional project references.

  Specs are `{type, context, value}` tuples. `nil` and `""` are treated as an
  absent optional reference. On success, normalized IDs are returned in the
  same order as the supplied specs.
  """
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
  Verifies the content type of an asset already locked by
  `lock_active_references/2`.

  Image/audio slots are semantic references: a same-project asset with the
  wrong MIME type is still invalid. Keeping this check in the same transaction
  prevents the asset from being replaced or deleted between validation and the
  source write.
  """
  @spec ensure_locked_asset_content_type(
          integer(),
          integer() | nil,
          reference_context(),
          String.t()
        ) :: :ok | {:error, {:invalid_asset_content_type, reference_context(), term()}}
  def ensure_locked_asset_content_type(_project_id, nil, _context, _pattern) do
    ensure_transaction!()
    :ok
  end

  def ensure_locked_asset_content_type(project_id, asset_id, context, pattern)
      when is_integer(project_id) and project_id > 0 and is_integer(asset_id) and asset_id > 0 and is_binary(pattern) do
    ensure_transaction!()

    case Repo.one(
           from(asset in Asset,
             where:
               asset.id == ^asset_id and asset.project_id == ^project_id and
                 like(asset.content_type, ^pattern),
             select: asset.id
           )
         ) do
      ^asset_id -> :ok
      nil -> {:error, {:invalid_asset_content_type, context, asset_id}}
    end
  end

  def ensure_locked_asset_content_type(_project_id, asset_id, context, _pattern),
    do: {:error, {:invalid_asset_content_type, context, asset_id}}

  @doc "Normalizes an optional positive database ID."
  @spec normalize_optional_id(term()) :: {:ok, integer() | nil} | :error
  def normalize_optional_id(nil), do: {:ok, nil}
  def normalize_optional_id(""), do: {:ok, nil}
  def normalize_optional_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  def normalize_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> :error
    end
  end

  def normalize_optional_id(_id), do: :error

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
    allowed =
      Enum.reduce(@reference_types, MapSet.new(), fn type, acc ->
        ids =
          specs
          |> Enum.filter(&(elem(&1, 0) == type))
          |> Enum.map(&elem(&1, 2))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()

        Enum.reduce(lock_reference_ids(type, project_id, ids), acc, fn id, set ->
          MapSet.put(set, {type, id})
        end)
      end)

    case Enum.find(specs, fn {type, _context, id, _value} ->
           not is_nil(id) and not MapSet.member?(allowed, {type, id})
         end) do
      nil ->
        :ok

      {_type, context, _id, value} ->
        {:error, {:invalid_project_reference, context, value}}
    end
  end

  defp lock_reference_ids(_type, _project_id, []), do: []

  defp lock_reference_ids(:asset, project_id, ids) do
    Repo.all(
      from(asset in Asset,
        where: asset.id in ^ids and asset.project_id == ^project_id,
        order_by: [asc: asset.id],
        lock: "FOR SHARE",
        select: asset.id
      )
    )
  end

  defp lock_reference_ids(:flow, project_id, ids) do
    lock_active_hierarchical_ids(Flow, project_id, ids)
  end

  defp lock_reference_ids(:scene, project_id, ids) do
    lock_active_hierarchical_ids(Scene, project_id, ids)
  end

  defp lock_reference_ids(:sheet, project_id, ids) do
    lock_active_hierarchical_ids(Sheet, project_id, ids)
  end

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
            "project reference integrity checks require an explicit database transaction"
    end
  end

  defp apply_project_lock(query, :share), do: lock(query, "FOR SHARE")
  defp apply_project_lock(query, :update), do: lock(query, "FOR UPDATE")
end
