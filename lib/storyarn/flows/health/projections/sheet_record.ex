defmodule Storyarn.Flows.Health.Projections.SheetRecord do
  @moduledoc "Health-local Sheet-name projection used in speaker statistics."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
  end
end
