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

  @tag :tmp_dir
  test "rejects a matching edge from a zero-debt consumer baseline", %{tmp_dir: tmp_dir} do
    policy = %{policy() | zero_debt_consumers: [:flows]}
    policy_path = Path.join(tmp_dir, "policy.exs")
    graph_path = Path.join(tmp_dir, "graph.json")
    baseline_dir = Path.join(tmp_dir, "baselines")
    File.mkdir_p!(baseline_dir)
    File.write!(policy_path, inspect(policy, pretty: true, limit: :infinity))

    edge = {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
    graph = graph_with_edges([edge])
    File.write!(graph_path, Jason.encode!(graph))

    actual = DependencyPolicy.forbidden_edges(graph, policy)

    Enum.each(actual, fn {consumer, edges} ->
      File.write!(
        Path.join(baseline_dir, "#{consumer}.json"),
        DependencyBaseline.encode(consumer, edges)
      )
    end)

    args = ["--graph", graph_path, "--policy", policy_path, "--baseline-dir", baseline_dir]

    assert capture_io(:stderr, fn ->
             assert_raise Mix.Error, "Architecture check failed", fn ->
               ArchitectureCheck.run(args)
             end
           end) =~ "flows: zero-debt baseline must remain empty"
  end

  @tag :tmp_dir
  test "rejects a new backend module that has no declared boundary", %{tmp_dir: tmp_dir} do
    policy = policy()
    policy_path = Path.join(tmp_dir, "policy.exs")
    graph_path = Path.join(tmp_dir, "graph.json")
    baseline_dir = Path.join(tmp_dir, "baselines")
    File.mkdir_p!(baseline_dir)
    File.write!(policy_path, inspect(policy, pretty: true, limit: :infinity))

    graph = %{"lib/storyarn/new_domain/service.ex" => %{}}
    File.write!(graph_path, Jason.encode!(graph))

    policy.forbidden_dependencies
    |> Map.keys()
    |> Enum.each(fn consumer ->
      File.write!(
        Path.join(baseline_dir, "#{consumer}.json"),
        DependencyBaseline.encode(consumer, MapSet.new())
      )
    end)

    args = ["--graph", graph_path, "--policy", policy_path, "--baseline-dir", baseline_dir]

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, "Architecture check failed", fn ->
          ArchitectureCheck.run(args)
        end
      end)

    assert output =~ "unclassified backend or Web paths"
    assert output =~ "lib/storyarn/new_domain/service.ex"
  end

  @tag :tmp_dir
  test "rejects an inbound edge hidden in another baseline for an isolated context", %{tmp_dir: tmp_dir} do
    policy = %{policy() | zero_debt_consumers: [:flows], isolated_contexts: [:flows]}
    policy_path = Path.join(tmp_dir, "policy.exs")
    graph_path = Path.join(tmp_dir, "graph.json")
    baseline_dir = Path.join(tmp_dir, "baselines")
    File.mkdir_p!(baseline_dir)
    File.write!(policy_path, inspect(policy, pretty: true, limit: :infinity))

    edge = {"lib/storyarn/scenes/catalog.ex", "lib/storyarn/flows.ex", "runtime"}
    graph = graph_with_edges([edge])
    File.write!(graph_path, Jason.encode!(graph))

    graph
    |> DependencyPolicy.forbidden_edges(policy)
    |> Enum.each(fn {consumer, edges} ->
      File.write!(
        Path.join(baseline_dir, "#{consumer}.json"),
        DependencyBaseline.encode(consumer, edges)
      )
    end)

    args = ["--graph", graph_path, "--policy", policy_path, "--baseline-dir", baseline_dir]

    assert capture_io(:stderr, fn ->
             assert_raise Mix.Error, "Architecture check failed", fn ->
               ArchitectureCheck.run(args)
             end
           end) =~ "flows: isolated context cannot accept inbound baseline dependencies"
  end

  defp policy do
    %{
      version: 1,
      bounded_contexts: [:flows, :scenes, :sheets],
      classification_roots: classification_roots(),
      boundaries: %{
        flows: ["lib/storyarn/flows.ex", "lib/storyarn/flows/"],
        infrastructure: ["lib/storyarn/repo.ex"],
        presentation_adapters: ["lib/storyarn_web/live_vue_encoders.ex"],
        scenes: ["lib/storyarn/scenes/"],
        sheets: ["lib/storyarn/sheets/"],
        web_infrastructure: ["lib/storyarn_web/endpoint.ex"]
      },
      forbidden_dependencies: protected_dependencies([:flows, :scenes, :sheets]),
      zero_debt_consumers: [],
      isolated_contexts: [],
      always_allowed_targets: ["lib/storyarn/repo.ex"],
      exceptions: []
    }
  end

  defp graph_with_edges(edges) do
    Enum.reduce(edges, %{}, fn {source, target, kind}, graph ->
      update_in(graph, [Access.key(source, %{})], &Map.put(&1, target, kind))
    end)
  end

  defp protected_dependencies(bounded_contexts) do
    context_dependencies =
      Map.new(bounded_contexts, fn context ->
        {context, (bounded_contexts -- [context]) ++ [:infrastructure, :presentation_adapters]}
      end)

    Map.merge(context_dependencies, %{
      infrastructure: bounded_contexts ++ [:presentation_adapters],
      web_infrastructure: bounded_contexts
    })
  end

  defp classification_roots do
    ["lib/storyarn.ex", "lib/storyarn/", "lib/storyarn_web.ex", "lib/storyarn_web/"]
  end
end
