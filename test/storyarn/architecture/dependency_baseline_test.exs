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

  @tag :tmp_dir
  test "rejects missing and unexpected baseline partitions", %{tmp_dir: tmp_dir} do
    File.write!(
      Path.join(tmp_dir, "flows.json"),
      DependencyBaseline.encode(:flows, MapSet.new())
    )

    File.write!(
      Path.join(tmp_dir, "orphan.json"),
      DependencyBaseline.encode(:orphan, MapSet.new())
    )

    assert_raise ArgumentError,
                 ~r/baseline file set mismatch.*missing: \["scenes.json"\].*unexpected: \["orphan.json"\]/,
                 fn ->
                   DependencyBaseline.load_all!(tmp_dir, [:flows, :scenes])
                 end
  end

  @tag :tmp_dir
  test "rejects multiple dependency kinds for the same source-target pair", %{tmp_dir: tmp_dir} do
    source = "lib/storyarn/flows/query.ex"
    target = "lib/storyarn/scenes/scene.ex"
    path = Path.join(tmp_dir, "flows.json")

    File.write!(
      path,
      Jason.encode!(%{
        "version" => 1,
        "consumer" => "flows",
        "edges" => [
          [source, target, "compile"],
          [source, target, "runtime"]
        ]
      })
    )

    assert_raise ArgumentError, ~r/multiple dependency kinds for the same source-target pair/, fn ->
      DependencyBaseline.load!(path, :flows)
    end

    edges = MapSet.new([{source, target, "compile"}, {source, target, "runtime"}])

    assert_raise ArgumentError, ~r/multiple dependency kinds for the same source-target pair/, fn ->
      DependencyBaseline.encode(:flows, edges)
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
