defmodule Storyarn.Sheets.Versioning.Data.SheetRecord do
  @moduledoc """
  Versioning-owned read projection used only to prove that an avatar belongs
  to the destination project during snapshot materialization.

  The deliberately narrow shape keeps this cross-capability join explicit and
  prevents versioning from importing the editor's Sheet entity.
  """

  use Ecto.Schema

  schema "sheets" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end
