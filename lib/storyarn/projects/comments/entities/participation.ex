defmodule Storyarn.Projects.Comments.Participation do
  @moduledoc "Personal, durable following and monotonic message-read watermark; not content snapshot data."
  use Ecto.Schema

  @primary_key false
  schema "comment_participations" do
    field :thread_id, :integer, primary_key: true
    field :user_id, :integer, primary_key: true
    field :following, :boolean, default: false
    field :last_read_message_id, :integer, default: 0
  end
end
