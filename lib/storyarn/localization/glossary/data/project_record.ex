defmodule Storyarn.Localization.Glossary.Data.ProjectRecord do
  @moduledoc """
  Glossary-owned read projection over the Project identity referenced by
  glossary entries.

  It is passive association data and performs no persistence I/O.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "projects" do
  end
end
