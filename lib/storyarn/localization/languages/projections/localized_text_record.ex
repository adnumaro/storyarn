defmodule Storyarn.Localization.Languages.Projections.LocalizedTextRecord do
  @moduledoc """
  Languages-owned read projection used only to detect whether a project has
  localization text inventory, including archived rows.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil
        }

  schema "localized_texts" do
    field :project_id, :id
  end
end
