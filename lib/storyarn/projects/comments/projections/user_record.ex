defmodule Storyarn.Projects.Comments.Projections.UserRecord do
  @moduledoc false
  use Ecto.Schema

  schema "users" do
    field :display_name, :string
    field :avatar_url, :string
  end
end
