defmodule Storyarn.Platform.Billing.Persistence.StorageCleanupOwnershipReceiptRecord do
  @moduledoc """
  Billing-owned read model for immutable cleanup handoff evidence.

  The cleanup pipeline in Projects writes the receipt. Platform reads it to
  prove that releasing reserved capacity cannot orphan provider objects.
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  @primary_key {:cleanup_request_id, :integer, autogenerate: false}
  schema "storage_cleanup_ownership_receipts" do
    field :storage_keys, {:array, :string}
    field :recorded_at, :utc_datetime
  end

  @spec storage_keys(pos_integer()) :: {:ok, [String.t()]} | :error
  def storage_keys(cleanup_request_id) when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    case Repo.get(__MODULE__, cleanup_request_id) do
      %__MODULE__{storage_keys: storage_keys} when is_list(storage_keys) -> {:ok, storage_keys}
      _receipt -> :error
    end
  end

  def storage_keys(_cleanup_request_id), do: :error

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
