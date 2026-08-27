defmodule Storyarn.Localization.Texts.Projections.AssetRecord do
  @moduledoc """
  Read-only projection of an asset used to validate Texts voice-over references.

  Texts owns no asset lifecycle; this schema intentionally exposes only the
  columns required by localization invariants and associations.
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
