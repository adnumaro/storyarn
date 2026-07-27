defmodule StoryarnWeb.Live.Shared.DashboardSortingTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Live.Shared.DashboardHelpers

  test "sorts DateTime columns chronologically across month and year boundaries" do
    rows = [
      %{id: 1, name: "January", updated_at: ~U[2026-01-01 00:00:00.000000Z]},
      %{id: 2, name: "December", updated_at: ~U[2025-12-31 00:00:00.000000Z]},
      %{id: 3, name: "March", updated_at: ~U[2023-03-01 00:00:00.000000Z]},
      %{id: 4, name: "February", updated_at: ~U[2024-02-28 00:00:00.000000Z]}
    ]

    columns = %{"updated_at" => & &1.updated_at}

    assert rows
           |> DashboardHelpers.sort_table("updated_at", :asc, columns)
           |> Enum.map(& &1.id) == [3, 4, 2, 1]

    assert rows
           |> DashboardHelpers.sort_table("updated_at", :desc, columns)
           |> Enum.map(& &1.id) == [1, 2, 4, 3]
  end
end
