defmodule Mix.Tasks.Architecture.CheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Architecture.Check, as: ArchitectureCheck
  alias Storyarn.Architecture.DependencyBaseline
  alias Storyarn.Architecture.DependencyPolicy

  @tag :tmp_dir
  test "checks a supplied xref graph and rejects an edge absent from the baseline", %{tmp_dir: tmp_dir} do
    policy = policy()
    policy_path = Path.join(tmp_dir, "policy.exs")
    graph_path = Path.join(tmp_dir, "graph.json")
    baseline_dir = Path.join(tmp_dir, "baselines")
    File.mkdir_p!(baseline_dir)
    File.write!(policy_path, inspect(policy, pretty: true, limit: :infinity))

    known_edge = {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
    graph = graph_with_edges([known_edge])
    File.write!(graph_path, Jason.encode!(graph))

    actual = DependencyPolicy.forbidden_edges(graph, policy)

    Enum.each(actual, fn {consumer, edges} ->
      File.write!(
        Path.join(baseline_dir, "#{consumer}.json"),
        DependencyBaseline.encode(consumer, edges)
      )
    end)

    args = ["--graph", graph_path, "--policy", policy_path, "--baseline-dir", baseline_dir]

    assert capture_io(fn -> ArchitectureCheck.run(args) end) =~
             "Architecture check passed (1 temporary forbidden dependencies remain in the baseline)."

    new_edge = {"lib/storyarn/flows/query.ex", "lib/storyarn/sheets/sheet.ex", "runtime"}
    File.write!(graph_path, Jason.encode!(graph_with_edges([known_edge, new_edge])))

    assert capture_io(:stderr, fn ->
             assert_raise Mix.Error, "Architecture check failed", fn ->
               ArchitectureCheck.run(args)
             end
           end) =~ "new forbidden dependencies"
  end

  defp policy do
    %{
      version: 1,
      boundaries: %{
        flows: ["lib/storyarn/flows/"],
        scenes: ["lib/storyarn/scenes/"],
        sheets: ["lib/storyarn/sheets/"]
      },
      forbidden_dependencies: %{
        flows: [:scenes, :sheets],
        scenes: [:flows, :sheets],
        sheets: [:flows, :scenes]
      },
      always_allowed_targets: ["lib/storyarn/repo.ex"],
      exceptions: []
    }
  end

  defp graph_with_edges(edges) do
    Enum.reduce(edges, %{}, fn {source, target, kind}, graph ->
      update_in(graph, [Access.key(source, %{})], &Map.put(&1, target, kind))
    end)
  end
end
