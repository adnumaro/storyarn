defmodule Storyarn.Localization.Providers.Projections.ProjectRecord do
  @moduledoc """
  Providers-owned read projection over the Project identity needed by provider
  configuration associations.

  It deliberately models only the shared-table identity and is not a
  `Storyarn.Projects.Project` dependency.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "projects" do
  end
end
