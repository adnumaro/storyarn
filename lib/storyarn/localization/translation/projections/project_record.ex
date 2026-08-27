defmodule Storyarn.Localization.Translation.Projections.ProjectRecord do
  @moduledoc """
  Translation-owned read projection over the Project identity used by
  translation runs and durable completion notifications.

  It is passive association data and performs no persistence I/O.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "projects" do
  end
end
