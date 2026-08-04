defmodule Storyarn.Versioning.ProjectSnapshot do
  @moduledoc """
  Schema for project-level snapshots.

  Every project snapshot row belongs to the canonical versioned object-set
  format. An object set is ready only through its independently checksummed
  manifest; its project JSON and asset blobs live in the same owned namespace.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotObjectStorage

  @allocated_object_set_fields [
    :project_id,
    :version_number,
    :format_version,
    :object_prefix,
    :project_storage_key,
    :manifest_storage_key
  ]
  @ready_object_set_fields [
    :project_id,
    :version_number,
    :title,
    :description,
    :project_storage_key,
    :project_size_bytes,
    :project_checksum,
    :entity_counts,
    :created_by_id,
    :is_auto,
    :format_version,
    :object_prefix,
    :manifest_storage_key,
    :manifest_size_bytes,
    :manifest_checksum,
    :total_size_bytes,
    :object_count,
    :asset_count,
    :blob_count,
    :mode,
    :lifecycle_state,
    :integrity_state,
    :accounted_size_bytes,
    :asset_blob_size_bytes,
    :accounting_version
  ]
  @linked_conversion_immutable_fields [
    :project_id,
    :version_number,
    :title,
    :description,
    :project_size_bytes,
    :project_checksum,
    :entity_counts,
    :created_by_id,
    :is_auto,
    :format_version,
    :asset_count,
    :accounting_version
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          project_storage_key: String.t(),
          project_size_bytes: integer(),
          project_checksum: String.t() | nil,
          format_version: integer() | nil,
          object_prefix: String.t() | nil,
          manifest_storage_key: String.t() | nil,
          manifest_size_bytes: integer() | nil,
          manifest_checksum: String.t() | nil,
          total_size_bytes: integer() | nil,
          object_count: integer() | nil,
          asset_count: integer() | nil,
          blob_count: integer() | nil,
          mode: String.t() | nil,
          lifecycle_state: String.t() | nil,
          integrity_state: String.t() | nil,
          accounted_size_bytes: integer() | nil,
          asset_blob_size_bytes: integer() | nil,
          accounting_version: integer() | nil,
          accounting_generation: integer() | nil,
          accounting_measured_at: DateTime.t() | nil,
          entity_counts: map(),
          created_by_id: integer() | nil,
          created_by: User.t() | NotLoaded.t() | nil,
          is_auto: boolean(),
          project: Project.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "project_snapshots" do
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :project_storage_key, :string
    field :project_size_bytes, :integer
    field :project_checksum, :string
    field :format_version, :integer
    field :object_prefix, :string
    field :manifest_storage_key, :string
    field :manifest_size_bytes, :integer
    field :manifest_checksum, :string
    field :total_size_bytes, :integer
    field :object_count, :integer
    field :asset_count, :integer
    field :blob_count, :integer
    field :mode, :string
    field :lifecycle_state, :string
    field :integrity_state, :string
    field :accounted_size_bytes, :integer
    field :asset_blob_size_bytes, :integer
    field :accounting_version, :integer
    field :accounting_generation, :integer
    field :accounting_measured_at, :utc_datetime
    field :entity_counts, :map, default: %{}
    field :is_auto, :boolean, default: false

    belongs_to :project, Project
    belongs_to :created_by, User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for persisting a canonical snapshot object set.

  The canonical project fields identify `project.json` so the database keeps
  its independently verified digest alongside the manifest digest. Object-set
  readers still require the ready manifest key and never infer readiness from
  the project object alone.
  """
  def object_set_changeset(snapshot, attrs) do
    object_set_changeset(snapshot, attrs, :finalize_or_remeasure)
  end

  @doc """
  Changeset for the one-way linked-to-full ownership transition.

  Only the new full namespace, manifest inventory, and accounting breakdown
  may change. Portable project bytes and logical snapshot identity remain
  immutable.
  """
  def full_conversion_changeset(snapshot, attrs) do
    object_set_changeset(snapshot, attrs, :linked_to_full)
  end

  defp object_set_changeset(snapshot, attrs, transition) do
    attrs = normalize_object_set_accounting_attrs(attrs)

    derive_accounted_size? = not has_attr?(attrs, :accounted_size_bytes)
    derive_asset_blob_size? = not has_attr?(attrs, :asset_blob_size_bytes)

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :project_storage_key,
      :project_size_bytes,
      :project_checksum,
      :entity_counts,
      :created_by_id,
      :is_auto,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :accounted_size_bytes,
      :asset_blob_size_bytes,
      :accounting_version,
      :accounting_measured_at
    ])
    |> advance_accounting_generation(snapshot)
    |> derive_accounting_sizes(derive_accounted_size?, derive_asset_blob_size?)
    |> validate_required([
      :project_id,
      :version_number,
      :project_storage_key,
      :project_size_bytes,
      :project_checksum,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :accounted_size_bytes,
      :asset_blob_size_bytes,
      :accounting_version,
      :accounting_generation,
      :accounting_measured_at
    ])
    |> validate_inclusion(:format_version, [1])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:lifecycle_state, ["ready"])
    |> validate_inclusion(:integrity_state, ["verified"])
    |> validate_inclusion(:accounting_version, [1])
    |> validate_number(:accounting_generation, greater_than: 0)
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:project_size_bytes, greater_than: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_number(:total_size_bytes, greater_than: 0)
    |> validate_number(:object_count, greater_than_or_equal_to: 2)
    |> validate_number(:asset_count, greater_than_or_equal_to: 0)
    |> validate_number(:blob_count, greater_than_or_equal_to: 0)
    |> validate_number(:accounted_size_bytes, greater_than: 0)
    |> validate_number(:asset_blob_size_bytes, greater_than_or_equal_to: 0)
    |> validate_format(:project_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:manifest_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_ready_object_keys()
    |> validate_object_set_transition(snapshot, transition)
    |> validate_object_counts()
    |> validate_total_size()
    |> validate_accounting_breakdown()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:object_count, name: :project_snapshots_object_counts)
    |> check_constraint(:blob_count, name: :project_snapshots_full_asset_blobs)
    |> check_constraint(:total_size_bytes, name: :project_snapshots_object_sizes)
    |> check_constraint(:project_checksum, name: :project_snapshots_project_checksum_format)
    |> check_constraint(:manifest_checksum, name: :project_snapshots_manifest_checksum_format)
    |> check_constraint(:mode, name: :project_snapshots_mode)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> check_constraint(:mode, name: :project_snapshots_accounting_identity)
    |> check_constraint(:object_prefix, name: :project_snapshots_object_target)
    |> check_constraint(:accounting_version, name: :project_snapshots_accounting_measurement)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_ready_accounting)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_ready_object_set)
    |> check_constraint(:accounted_size_bytes, name: :project_snapshots_full_ready_accounting)
    |> check_constraint(:asset_blob_size_bytes, name: :project_snapshots_linked_asset_bytes)
    |> check_constraint(:accounted_size_bytes, name: :project_snapshots_linked_ready_accounting)
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Creates the durable lifecycle row that an asynchronous snapshot build owns.

  The final object namespace and object keys are allocated up front, but the
  row remains non-ready and unaccounted until a verified manifest is published
  and `object_set_changeset/2` atomically finalizes it.
  """
  def pending_object_set_changeset(snapshot, attrs) do
    attrs =
      attrs
      |> put_default(:format_version, 1)
      |> put_default(:lifecycle_state, "pending")
      |> put_default(:integrity_state, "unknown")
      |> put_pending_object_keys()

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :project_storage_key,
      :project_size_bytes,
      :entity_counts,
      :created_by_id,
      :is_auto,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :mode,
      :lifecycle_state,
      :integrity_state
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :project_storage_key,
      :project_size_bytes,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :mode,
      :lifecycle_state,
      :integrity_state
    ])
    |> validate_inclusion(:format_version, [1])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:lifecycle_state, ["pending"])
    |> validate_inclusion(:integrity_state, ["unknown"])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:project_size_bytes, equal_to: 0)
    |> validate_ready_object_keys()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:mode, name: :project_snapshots_mode)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> check_constraint(:mode, name: :project_snapshots_accounting_identity)
    |> check_constraint(:object_prefix, name: :project_snapshots_object_target)
    |> check_constraint(:accounting_version, name: :project_snapshots_accounting_measurement)
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Changeset for updating title and description on an existing snapshot.
  """
  def update_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:title, :description])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
  end

  defp normalize_object_set_accounting_attrs(attrs) do
    attrs
    |> put_default(:mode, "full")
    |> put_default(:lifecycle_state, "ready")
    |> put_default(:integrity_state, "verified")
    |> put_default(:accounting_version, 1)
    |> put_accounting_measured_at()
  end

  defp advance_accounting_generation(changeset, %__MODULE__{accounting_generation: generation})
       when is_integer(generation) and generation > 0 do
    changeset
    |> optimistic_lock(:accounting_generation, &(&1 + 1))
    |> force_change(:accounting_generation, generation + 1)
  end

  defp advance_accounting_generation(changeset, %__MODULE__{}), do: put_change(changeset, :accounting_generation, 1)

  defp put_default(attrs, field, value) do
    if has_attr?(attrs, field), do: attrs, else: Map.put(attrs, field, value)
  end

  defp put_accounting_measured_at(attrs) do
    if has_attr?(attrs, :accounting_measured_at),
      do: attrs,
      else: Map.put(attrs, :accounting_measured_at, TimeHelpers.now())
  end

  defp put_pending_object_keys(attrs) do
    case Map.get(attrs, :object_prefix, Map.get(attrs, "object_prefix")) do
      prefix when is_binary(prefix) ->
        attrs
        |> put_default(:project_storage_key, prefix <> "/project.json")
        |> put_default(:project_size_bytes, 0)
        |> put_default(:manifest_storage_key, prefix <> "/manifest.json")

      _prefix ->
        attrs
    end
  end

  defp has_attr?(attrs, field) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, to_string(field))
  end

  defp derive_accounting_sizes(changeset, derive_accounted_size?, derive_asset_blob_size?) do
    changeset
    |> maybe_derive_accounted_size(derive_accounted_size?)
    |> maybe_derive_asset_blob_size(derive_asset_blob_size?)
  end

  defp maybe_derive_accounted_size(changeset, true) do
    case get_field(changeset, :total_size_bytes) do
      total_size when is_integer(total_size) -> put_change(changeset, :accounted_size_bytes, total_size)
      _other -> changeset
    end
  end

  defp maybe_derive_accounted_size(changeset, false), do: changeset

  defp maybe_derive_asset_blob_size(changeset, true) do
    total_size = get_field(changeset, :total_size_bytes)
    project_size = get_field(changeset, :project_size_bytes)
    manifest_size = get_field(changeset, :manifest_size_bytes)

    if Enum.all?([total_size, project_size, manifest_size], &is_integer/1) do
      put_change(changeset, :asset_blob_size_bytes, total_size - project_size - manifest_size)
    else
      changeset
    end
  end

  defp maybe_derive_asset_blob_size(changeset, false), do: changeset

  defp validate_object_counts(changeset) do
    object_count = get_field(changeset, :object_count)
    asset_count = get_field(changeset, :asset_count)
    blob_count = get_field(changeset, :blob_count)

    cond do
      not Enum.all?([object_count, asset_count, blob_count], &is_integer/1) ->
        changeset

      object_count != blob_count + 2 ->
        add_error(changeset, :object_count, "must equal blob count plus manifest and project objects")

      blob_count > asset_count ->
        add_error(changeset, :blob_count, "cannot exceed asset count")

      get_field(changeset, :mode) == "full" and asset_count > 0 and blob_count == 0 ->
        add_error(changeset, :blob_count, "must include at least one owned blob when assets are cataloged")

      true ->
        changeset
    end
  end

  defp validate_total_size(changeset) do
    manifest_size = get_field(changeset, :manifest_size_bytes)
    total_size = get_field(changeset, :total_size_bytes)

    if is_integer(manifest_size) and is_integer(total_size) and total_size < manifest_size,
      do: add_error(changeset, :total_size_bytes, "must be at least the manifest size"),
      else: changeset
  end

  defp validate_accounting_breakdown(changeset) do
    total_size = get_field(changeset, :total_size_bytes)
    project_size = get_field(changeset, :project_size_bytes)
    manifest_size = get_field(changeset, :manifest_size_bytes)
    accounted_size = get_field(changeset, :accounted_size_bytes)
    asset_blob_size = get_field(changeset, :asset_blob_size_bytes)

    changeset =
      if is_integer(total_size) and is_integer(accounted_size) and accounted_size != total_size do
        add_error(changeset, :accounted_size_bytes, "must equal the total snapshot size")
      else
        changeset
      end

    if Enum.all?([total_size, project_size, manifest_size, asset_blob_size], &is_integer/1) and
         total_size != project_size + manifest_size + asset_blob_size do
      add_error(
        changeset,
        :asset_blob_size_bytes,
        "must equal total size minus project and manifest sizes"
      )
    else
      changeset
    end
  end

  defp validate_ready_object_keys(changeset) do
    project_id = get_field(changeset, :project_id)
    prefix = get_field(changeset, :object_prefix)
    project_storage_key = get_field(changeset, :project_storage_key)
    manifest_storage_key = get_field(changeset, :manifest_storage_key)

    changeset =
      if SnapshotObjectStorage.ready_prefix_for_project?(project_id, prefix),
        do: changeset,
        else: add_error(changeset, :object_prefix, "must be a canonical ready namespace for the project")

    changeset =
      if is_binary(prefix) and project_storage_key == prefix <> "/project.json",
        do: changeset,
        else: add_error(changeset, :project_storage_key, "must identify project.json in the object namespace")

    if is_binary(prefix) and manifest_storage_key == prefix <> "/manifest.json",
      do: changeset,
      else: add_error(changeset, :manifest_storage_key, "must identify manifest.json in the object namespace")
  end

  defp validate_object_set_transition(changeset, snapshot, :finalize_or_remeasure) do
    fields =
      if is_integer(snapshot.accounting_generation),
        do: @ready_object_set_fields,
        else: @allocated_object_set_fields

    validate_immutable_fields(changeset, snapshot, fields)
  end

  defp validate_object_set_transition(changeset, snapshot, :linked_to_full) do
    changeset
    |> validate_linked_conversion_source(snapshot)
    |> validate_immutable_fields(snapshot, @linked_conversion_immutable_fields)
    |> validate_linked_conversion_growth(snapshot)
  end

  defp validate_linked_conversion_source(changeset, %__MODULE__{
         id: id,
         mode: "linked",
         lifecycle_state: "ready",
         integrity_state: "verified",
         accounting_version: 1,
         accounting_generation: generation
       })
       when is_integer(id) and is_integer(generation) and generation > 0, do: changeset

  defp validate_linked_conversion_source(changeset, %__MODULE__{}),
    do: add_error(changeset, :mode, "must transition from a verified ready linked snapshot")

  defp validate_linked_conversion_growth(changeset, snapshot) do
    accounted_size = get_field(changeset, :accounted_size_bytes)
    asset_blob_size = get_field(changeset, :asset_blob_size_bytes)

    if is_integer(accounted_size) and is_integer(snapshot.accounted_size_bytes) and
         accounted_size >= snapshot.accounted_size_bytes and is_integer(asset_blob_size) and asset_blob_size >= 0,
       do: changeset,
       else: add_error(changeset, :accounted_size_bytes, "cannot reduce verified snapshot accounting")
  end

  defp validate_immutable_fields(changeset, %__MODULE__{id: id} = snapshot, fields) when is_integer(id) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if get_field(changeset, field) == Map.fetch!(snapshot, field),
        do: changeset,
        else: add_error(changeset, field, "cannot change after the snapshot target is allocated")
    end)
  end

  defp validate_immutable_fields(changeset, %__MODULE__{}, _fields), do: changeset
end
