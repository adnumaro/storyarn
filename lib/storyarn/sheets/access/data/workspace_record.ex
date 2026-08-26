defmodule Storyarn.Sheets.Access.Data.WorkspaceRecord do
  @moduledoc "Access-owned workspace identity used by project slug lookups."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
