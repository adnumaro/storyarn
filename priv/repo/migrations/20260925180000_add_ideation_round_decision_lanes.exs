defmodule Storyarn.Repo.Migrations.AddIdeationRoundDecisionLanes do
  @moduledoc false
  use Ecto.Migration

  # A round's decision lane can be moved on the board. An empty map keeps the
  # automatic place under the band's content; a moved lane stores its x and y
  # relative to the round header, and a version that fences concurrent moves.
  def change do
    alter table(:ideation_rounds) do
      add :decision_lane, :map, null: false, default: %{}
    end

    create constraint(:ideation_rounds, :ideation_rounds_decision_lane_object,
             check: "jsonb_typeof(decision_lane) = 'object'"
           )
  end
end
