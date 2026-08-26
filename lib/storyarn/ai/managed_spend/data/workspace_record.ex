defmodule Storyarn.AI.ManagedSpend.Data.WorkspaceRecord do
  @moduledoc "Read model for the workspace identity managed spend needs to enforce foreign keys."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :source_locale, :string, default: "en"
    field :owner_id, :id

    timestamps(type: :utc_datetime)
  end
end
