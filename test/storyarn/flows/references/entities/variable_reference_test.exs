defmodule Storyarn.Flows.VariableReferenceTest do
  @moduledoc """
  `@source_types` declared `~w(flow_node map_zone)` while the tracker writes
  `"flow_node"`, `"scene_zone"` and `"scene_pin"` — `"map_zone"` is a name from
  before the Maps→Scenes rename and matches no row.

  Nothing was corrupted, because the Projects reference tracker writes through
  `Repo.insert_all/3`, which builds no changeset. The trap is for whoever adds a
  fourth source and reaches for `changeset/2`: every scene reference would start
  being rejected.
  """
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows.VariableReference

  describe "@source_types matches what is actually written" do
    test "the changeset accepts every source_type the tracker writes" do
      for source_type <- ~w(flow_node scene_zone scene_pin) do
        changeset =
          VariableReference.changeset(%VariableReference{}, %{
            source_type: source_type,
            source_id: 1,
            block_id: 1,
            kind: "read",
            source_sheet: "hero",
            source_variable: "health"
          })

        assert changeset.valid?,
               "source_type #{inspect(source_type)} is written by VariableReferenceTracker " <>
                 "but rejected by the changeset: #{inspect(changeset.errors)}"
      end
    end

    test "the changeset rejects a source_type nothing writes" do
      changeset =
        VariableReference.changeset(%VariableReference{}, %{
          source_type: "map_zone",
          source_id: 1,
          block_id: 1,
          kind: "read",
          source_sheet: "hero",
          source_variable: "health"
        })

      refute changeset.valid?, ~s("map_zone" is a pre-rename name and must not be accepted)
    end
  end
end
