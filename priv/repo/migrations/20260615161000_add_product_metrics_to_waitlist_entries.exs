defmodule Storyarn.Repo.Migrations.AddProductMetricsToWaitlistEntries do
  use Ecto.Migration

  def change do
    alter table(:waitlist_entries) do
      add :profession, :string
      add :primary_interest, :string
      add :discovery_source, :string
      add :current_tool, :string
      add :current_tool_other, :string
    end
  end
end
