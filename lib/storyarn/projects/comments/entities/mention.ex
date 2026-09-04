defmodule Storyarn.Projects.Comments.Mention do
  @moduledoc "An explicit member mention in a project comment."
  use Ecto.Schema

  schema "comment_mentions" do
    field :message_id, :integer
    field :user_id, :integer
  end
end
