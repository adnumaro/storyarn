defmodule Storyarn.Repo.Migrations.IndexCommentConversationActivity do
  use Ecto.Migration

  def change do
    create index(:comment_threads, [:project_id, :last_activity_at, :id],
             name: :comment_conversation_activity
           )
  end
end
