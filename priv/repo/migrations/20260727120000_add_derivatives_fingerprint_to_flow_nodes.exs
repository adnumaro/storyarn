defmodule Storyarn.Repo.Migrations.AddDerivativesFingerprintToFlowNodes do
  use Ecto.Migration

  def change do
    alter table(:flow_nodes) do
      add :derivatives_fingerprint, :string
    end
  end
end
