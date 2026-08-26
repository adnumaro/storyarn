defmodule Storyarn.Localization.Access.Data.AssetRecord do
  @moduledoc """
  Access-owned projection over asset identity used to validate project references.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          content_type: String.t() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "assets" do
    field :project_id, :id
    field :content_type, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
