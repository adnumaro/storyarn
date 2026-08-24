defmodule Storyarn.Projects.Assets.StorageCleanupOwnershipReceipt do
  @moduledoc """
  Immutable proof that an exact object inventory was handed to durable cleanup.

  Rows are captured by a database trigger when a mutable cleanup request is
  inserted. They deliberately survive request completion and rotation so a
  storage reservation can verify its original handoff without depending on a
  live queue row.
  """
  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  @primary_key {:cleanup_request_id, :integer, autogenerate: false}
  schema "storage_cleanup_ownership_receipts" do
    field :storage_keys, {:array, :string}
    field :recorded_at, :utc_datetime
  end

  @doc "Returns the immutable inventory captured for a cleanup request."
  @spec storage_keys(pos_integer()) :: {:ok, [String.t()]} | :error
  def storage_keys(cleanup_request_id) when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    case Repo.get(__MODULE__, cleanup_request_id) do
      %__MODULE__{storage_keys: storage_keys} when is_list(storage_keys) -> {:ok, storage_keys}
      _receipt -> :error
    end
  end

  def storage_keys(_cleanup_request_id), do: :error

  @doc "Returns whether any handed-off cleanup inventory owns a key beneath the exact prefix."
  @spec handed_off_for_prefix?(String.t()) :: boolean()
  def handed_off_for_prefix?(prefix) when is_binary(prefix) do
    Repo.exists?(
      from(namespace in "storage_cleanup_ownership_namespaces",
        where: field(namespace, :object_prefix) == ^prefix
      )
    )
  end

  def handed_off_for_prefix?(_prefix), do: false
end
