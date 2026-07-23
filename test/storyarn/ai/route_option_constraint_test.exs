defmodule Storyarn.AI.RouteOptionConstraintTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo

  test "managed route options require non-null price units at the database boundary" do
    assert %{rows: [[definition]]} =
             Repo.query!("""
             SELECT pg_get_constraintdef(oid)
             FROM pg_constraint
             WHERE conname = 'ai_route_options_lane_price'
             """)

    assert definition =~ "price_units IS NOT NULL"
  end
end
