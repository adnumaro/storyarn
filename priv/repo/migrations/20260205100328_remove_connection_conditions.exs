defmodule Storyarn.Repo.Migrations.RemoveConnectionConditions do
  use Ecto.Migration

  @doc """
  Removes condition and condition_order fields from flow_connections.

  These fields were removed based on research findings that showed
  conditions on connections are not an industry standard practice.
  See docs/research/DIALOGUE_CONDITIONS_RESEARCH.md for details.
  """
  def change do
    alter table(:flow_connections) do
      remove :condition, :string
      remove :condition_order, :integer
    end
  end
end
