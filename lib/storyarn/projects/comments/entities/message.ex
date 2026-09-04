defmodule Storyarn.Projects.Comments.Message do
  @moduledoc "An immutable authored message and its idempotent client request."
  use Ecto.Schema

  schema "comment_messages" do
    field :project_id, :integer
    field :thread_id, :integer
    field :author_id, :integer
    field :parent_id, :integer
    field :body, :string
    field :client_request_id, :string
    field :request_hash, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
