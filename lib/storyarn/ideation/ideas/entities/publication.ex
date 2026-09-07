defmodule Storyarn.Ideation.Ideas.Publication do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_idea_publications" do
    field :idea_id, :id
    field :revision, :integer
    field :operation_id, :id
    field :actor_id, :id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
