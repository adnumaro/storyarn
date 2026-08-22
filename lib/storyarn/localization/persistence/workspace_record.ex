defmodule Storyarn.Localization.Persistence.WorkspaceRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          slug: String.t() | nil,
          source_locale: String.t() | nil
        }

  schema "workspaces" do
    field :slug, :string
    field :source_locale, :string

    timestamps(type: :utc_datetime)
  end
end
