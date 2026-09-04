defmodule Storyarn.Repo.Migrations.CreateProjectComments do
  use Ecto.Migration

  def change do
    create table(:comment_threads) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :source_type, :string, null: false
      add :source_id, :bigint, null: false
      add :flow_node_id, references(:flow_nodes, on_delete: :nilify_all)
      add :container_id, :bigint, null: false
      add :source_inserted_at, :utc_datetime, null: false
      add :source_label, :string, null: false
      add :status, :string, null: false, default: "open"
      add :revision, :integer, null: false, default: 1
      add :message_count, :integer, null: false, default: 0
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:users, on_delete: :nilify_all)
      add :last_activity_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create constraint(:comment_threads, :comment_threads_status,
             check: "status IN ('open', 'resolved')"
           )

    create constraint(:comment_threads, :comment_threads_source_type,
             check: "source_type = 'flow_node'"
           )

    create constraint(:comment_threads, :comment_threads_positive_revision,
             check: "revision > 0 AND message_count >= 0"
           )

    create index(:comment_threads, [:project_id, :container_id, :id])
    create index(:comment_threads, [:project_id, :source_type, :source_id, :status])
    create index(:comment_threads, [:flow_node_id])

    create table(:comment_messages) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :thread_id, references(:comment_threads, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :parent_id, references(:comment_messages, on_delete: :nilify_all)
      add :body, :text, null: false
      add :client_request_id, :string, null: false
      add :request_hash, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:comment_messages, [:thread_id, :id])
    create unique_index(:comment_messages, [:project_id, :author_id, :client_request_id])

    create constraint(:comment_messages, :comment_messages_body_length,
             check: "char_length(body) BETWEEN 1 AND 10000"
           )

    create table(:comment_mentions) do
      add :message_id, references(:comment_messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create unique_index(:comment_mentions, [:message_id, :user_id])
  end
end
