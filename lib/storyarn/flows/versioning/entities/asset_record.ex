defmodule Storyarn.Flows.Versioning.Entities.AssetRecord do
  @moduledoc """
  Versioning-owned projection of assets used to capture, validate, and materialize Flow snapshots.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @snapshot_content_types ~w(
    image/jpeg image/png image/gif image/webp image/svg+xml
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf application/octet-stream
  )
  @max_asset_size 52_428_800
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type t :: %__MODULE__{}

  schema "assets" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :key, :string
    field :url, :string
    field :metadata, :map, default: %{}
    field :blob_hash, :string
    field :project_id, :id
    field :uploaded_by_id, :id
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :id
    field :deletion_reason, :string
    field :deletion_generation, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def snapshot_restore_changeset(asset, attrs) do
    asset
    |> cast(attrs, [:filename, :content_type, :size, :key, :url, :metadata, :blob_hash])
    |> require_non_nil([:filename, :content_type, :size, :key, :blob_hash])
    |> validate_inclusion(:content_type, @snapshot_content_types)
    |> validate_number(:size, greater_than_or_equal_to: 0, less_than_or_equal_to: @max_asset_size)
    |> validate_format(:blob_hash, @sha256_regex)
    |> unique_constraint(:key, name: :assets_project_id_key_index)
  end

  defp require_non_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if is_nil(get_field(changeset, field)),
        do: add_error(changeset, field, "can't be nil"),
        else: changeset
    end)
  end
end
