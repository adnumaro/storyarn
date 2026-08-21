defmodule Storyarn.Architecture.DependencyBaselineTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyBaseline
  alias Storyarn.Architecture.DependencyPolicy

  @tag :tmp_dir
  test "round-trips a sorted, partitioned baseline", %{tmp_dir: tmp_dir} do
    edges =
      MapSet.new([
        {"lib/storyarn/flows/z.ex", "lib/storyarn/scenes/scene.ex", "runtime"},
        {"lib/storyarn/flows/a.ex", "lib/storyarn/sheets/sheet.ex", "export"}
      ])

    path = Path.join(tmp_dir, "flows.json")
    File.write!(path, DependencyBaseline.encode(:flows, edges))

    assert DependencyBaseline.load!(path, :flows) == edges
  end

  @tag :tmp_dir
  test "accepts an empty partition when a consumer reaches zero debt", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "flows.json")
    File.write!(path, DependencyBaseline.encode(:flows, MapSet.new()))

    assert DependencyBaseline.load!(path, :flows) == MapSet.new()
  end

  @tag :tmp_dir
  test "rejects stale hand-edited ordering and duplicate entries", %{tmp_dir: tmp_dir} do
    edge = ["lib/storyarn/flows/z.ex", "lib/storyarn/scenes/scene.ex", "runtime"]
    earlier = ["lib/storyarn/flows/a.ex", "lib/storyarn/scenes/scene.ex", "runtime"]
    path = Path.join(tmp_dir, "flows.json")

    File.write!(
      path,
      Jason.encode!(%{"version" => 1, "consumer" => "flows", "edges" => [edge, earlier]})
    )

    assert_raise ArgumentError, ~r/must be sorted/, fn ->
      DependencyBaseline.load!(path, :flows)
    end

    File.write!(
      path,
      Jason.encode!(%{"version" => 1, "consumer" => "flows", "edges" => [edge, edge]})
    )

    assert_raise ArgumentError, ~r/duplicate edges/, fn ->
      DependencyBaseline.load!(path, :flows)
    end
  end

  test "the committed policy has one valid baseline partition per protected consumer" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")
    consumers = policy.forbidden_dependencies |> Map.keys() |> Enum.sort()

    baselines =
      DependencyBaseline.load_all!("config/architecture_baselines", consumers)

    assert baselines |> Map.keys() |> Enum.sort() == consumers
    assert Enum.all?(baselines, fn {_consumer, edges} -> match?(%MapSet{}, edges) end)
  end
end
