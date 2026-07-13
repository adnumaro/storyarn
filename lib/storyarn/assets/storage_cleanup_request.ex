defmodule Storyarn.Assets.StorageCleanupRequest do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          storage_keys: [String.t()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end
end
