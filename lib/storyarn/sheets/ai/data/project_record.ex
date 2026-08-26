defmodule Storyarn.Sheets.AI.Data.ProjectRecord do
  @moduledoc "AI-context projection used to lock the owning active project."

  use Ecto.Schema

  schema "projects" do
    field :deleted_at, :utc_datetime
  end
end
