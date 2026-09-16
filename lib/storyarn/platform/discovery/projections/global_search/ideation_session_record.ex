defmodule Storyarn.Platform.GlobalSearch.Persistence.IdeationSessionRecord do
  @moduledoc "Consumer-owned read-only session metadata projection; excludes creative content."

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          project_id: integer() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ideation_sessions" do
    field :name, :string, source: :title
    field :project_id, :id
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
