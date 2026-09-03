defmodule Storyarn.Projects.Assets.StorageCleanupMultipartUpload do
  @moduledoc """
  Durable identity and point-in-time evidence for one exact multipart upload.

  The opaque upload identifier is retained until the owning cleanup request is
  completed. A missing provider response only advances absence evidence for a
  generation; it never deletes this row by itself.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Assets.StorageCleanupRequest

  @digest_pattern ~r/\A[0-9a-f]{64}\z/
  @max_reference_part_bytes 4_096

  @type t :: %__MODULE__{
          id: integer() | nil,
          cleanup_request_id: integer(),
          cleanup_request: StorageCleanupRequest.t() | Ecto.Association.NotLoaded.t(),
          storage_key: String.t(),
          upload_id: String.t(),
          reference_digest: String.t(),
          last_aborted_generation: non_neg_integer() | nil,
          last_absent_generation: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_multipart_uploads" do
    field :storage_key, :string
    field :upload_id, :string
    field :reference_digest, :string
    field :last_aborted_generation, :integer
    field :last_absent_generation, :integer

    belongs_to :cleanup_request, StorageCleanupRequest

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a row for an exact provider reference discovered by a cleanup request."
  @spec create_changeset(t(), pos_integer(), String.t(), String.t()) :: Ecto.Changeset.t()
  def create_changeset(upload, cleanup_request_id, storage_key, upload_id)
      when is_integer(cleanup_request_id) and is_binary(storage_key) and is_binary(upload_id) do
    upload
    |> change(
      cleanup_request_id: cleanup_request_id,
      storage_key: storage_key,
      upload_id: upload_id,
      reference_digest: reference_digest(storage_key, upload_id)
    )
    |> validate_reference()
  end

  def create_changeset(upload, _cleanup_request_id, _storage_key, _upload_id) do
    upload
    |> change()
    |> add_error(:storage_key, "is not an exact multipart upload reference")
  end

  @doc "Advances abort and absence evidence without changing the retained identity."
  @spec evidence_changeset(t(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          Ecto.Changeset.t()
  def evidence_changeset(upload, last_aborted_generation, last_absent_generation) do
    upload
    |> change(
      last_aborted_generation: last_aborted_generation,
      last_absent_generation: last_absent_generation
    )
    |> validate_number(:last_aborted_generation, greater_than_or_equal_to: 0)
    |> validate_number(:last_absent_generation, greater_than_or_equal_to: 0)
    |> check_constraint(:last_aborted_generation,
      name: :storage_cleanup_multipart_uploads_shape
    )
  end

  @doc "Returns the collision-resistant identity used by the per-request unique index."
  @spec reference_digest(String.t(), String.t()) :: String.t()
  def reference_digest(storage_key, upload_id) when is_binary(storage_key) and is_binary(upload_id) do
    payload =
      <<byte_size(storage_key)::unsigned-big-integer-size(64), storage_key::binary,
        byte_size(upload_id)::unsigned-big-integer-size(64), upload_id::binary>>

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end

  defp validate_reference(changeset) do
    changeset
    |> validate_required([:cleanup_request_id, :storage_key, :upload_id, :reference_digest])
    |> validate_number(:cleanup_request_id, greater_than: 0)
    |> validate_length(:storage_key, count: :bytes, min: 1, max: @max_reference_part_bytes)
    |> validate_length(:upload_id, count: :bytes, min: 1, max: @max_reference_part_bytes)
    |> validate_format(:reference_digest, @digest_pattern)
    |> foreign_key_constraint(:cleanup_request_id,
      name: :storage_cleanup_multipart_uploads_request_fkey
    )
    |> unique_constraint(:reference_digest,
      name: :storage_cleanup_multipart_uploads_request_digest_idx
    )
    |> check_constraint(:storage_key, name: :storage_cleanup_multipart_uploads_shape)
  end
end
