defmodule Storyarn.Versioning.ProjectSnapshotCapture do
  @moduledoc """
  Immutable input materialized at a project snapshot request boundary.

  The two JSON objects are the exact bytes later staged by the worker. Source
  keys are internal build inputs pointing at protected content-addressed blobs;
  they are never included in the ready manifest or used by restore readers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotContentHealth

  @primary_key false
  schema "project_snapshot_captures" do
    belongs_to :project_snapshot, ProjectSnapshot, primary_key: true

    field :capture_boundary, Ecto.UUID
    field :capture_digest, :string
    field :project_json, :binary
    field :manifest_json, :binary
    field :source_keys, :map
    field :content_health, :map
    field :project_size_bytes, :integer
    field :manifest_size_bytes, :integer
    field :asset_blob_size_bytes, :integer
    field :total_size_bytes, :integer
    field :object_count, :integer
    field :asset_count, :integer
    field :blob_count, :integer
    field :captured_at, :utc_datetime
  end

  @doc false
  def create_changeset(capture, attrs) do
    capture
    |> cast(attrs, [
      :project_snapshot_id,
      :capture_boundary,
      :capture_digest,
      :project_json,
      :manifest_json,
      :source_keys,
      :content_health,
      :project_size_bytes,
      :manifest_size_bytes,
      :asset_blob_size_bytes,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :captured_at
    ])
    |> validate_required([
      :project_snapshot_id,
      :capture_boundary,
      :capture_digest,
      :project_json,
      :manifest_json,
      :source_keys,
      :content_health,
      :project_size_bytes,
      :manifest_size_bytes,
      :asset_blob_size_bytes,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :captured_at
    ])
    |> validate_format(:capture_digest, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:project_size_bytes, greater_than: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_number(:asset_blob_size_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:total_size_bytes, greater_than: 0)
    |> validate_number(:object_count, greater_than_or_equal_to: 2)
    |> validate_number(:asset_count, greater_than_or_equal_to: 0)
    |> validate_number(:blob_count, greater_than_or_equal_to: 0)
    |> validate_content_health()
    |> validate_inventory()
    |> foreign_key_constraint(:project_snapshot_id)
    |> unique_constraint(:project_snapshot_id, name: :project_snapshot_captures_pkey)
    |> unique_constraint(:capture_boundary)
    |> check_constraint(:capture_digest, name: :project_snapshot_captures_digest_format)
    |> check_constraint(:content_health, name: :project_snapshot_captures_content_health)
    |> check_constraint(:total_size_bytes, name: :project_snapshot_captures_inventory)
  end

  defp validate_inventory(changeset) do
    project_size = get_field(changeset, :project_size_bytes)
    manifest_size = get_field(changeset, :manifest_size_bytes)
    asset_blob_size = get_field(changeset, :asset_blob_size_bytes)
    total_size = get_field(changeset, :total_size_bytes)
    object_count = get_field(changeset, :object_count)
    asset_count = get_field(changeset, :asset_count)
    blob_count = get_field(changeset, :blob_count)

    cond do
      not Enum.all?(
        [project_size, manifest_size, asset_blob_size, total_size, object_count, asset_count, blob_count],
        &is_integer/1
      ) ->
        changeset

      total_size != project_size + manifest_size + asset_blob_size ->
        add_error(changeset, :total_size_bytes, "must equal project, manifest, and blob bytes")

      object_count != blob_count + 2 ->
        add_error(changeset, :object_count, "must equal blob count plus project and manifest")

      asset_count < blob_count ->
        add_error(changeset, :asset_count, "cannot be smaller than the unique blob count")

      true ->
        changeset
    end
  end

  defp validate_content_health(changeset) do
    case SnapshotContentHealth.validate(get_field(changeset, :content_health)) do
      :ok -> changeset
      {:error, :invalid_snapshot_content_health} -> add_error(changeset, :content_health, "is invalid")
    end
  end
end
