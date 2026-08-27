defmodule Storyarn.Sheets.References.Projections.AssetRecord do
  @moduledoc """
  References-local projection of an asset that may be linked from Sheet data.

  It carries only identity, project ownership, MIME type, and deletion state;
  asset lifecycle and storage behavior remain outside this capability.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :content_type, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
