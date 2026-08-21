defmodule Mix.Tasks.Architecture.Check do
  @shortdoc "Rejects new cross-boundary dependencies"

  @moduledoc """
  Checks the current `mix xref` graph against Storyarn's bounded-context policy.

  The committed baselines contain only pre-existing forbidden dependencies. The
  check fails for a new edge, a stronger dependency kind, or a stale baseline
  entry. A migrated edge and its baseline entry must therefore disappear in the
  same change.

      mix architecture.check

  `--graph`, `--policy`, and `--baseline-dir` are intended for deterministic
  tests and diagnostics. There is deliberately no command that expands a
  baseline.
  """

  use Mix.Task

  alias Storyarn.Architecture.DependencyBaseline
  alias Storyarn.Architecture.DependencyPolicy

  @requirements ["compile"]
  @default_policy "config/architecture_boundaries.exs"
  @default_baseline_dir "config/architecture_baselines"

  @impl Mix.Task
  def run(args) do
    opts = parse_args!(args)
    policy = opts |> Keyword.fetch!(:policy) |> DependencyPolicy.load!()
    graph = opts |> load_graph!() |> DependencyPolicy.decode_graph!()
    actual = DependencyPolicy.forbidden_edges(graph, policy)
    consumers = policy.forbidden_dependencies |> Map.keys() |> Enum.sort()
    expected = DependencyBaseline.load_all!(Keyword.fetch!(opts, :baseline_dir), consumers)
    comparisons = DependencyBaseline.compare_all(actual, expected)

    if Enum.all?(comparisons, fn {_consumer, comparison} ->
         DependencyPolicy.clean?(comparison)
       end) do
      count = actual |> Map.values() |> Enum.reduce(0, &(MapSet.size(&1) + &2))

      Mix.shell().info("Architecture check passed (#{count} temporary forbidden dependencies remain in the baseline).")
    else
      print_failures(comparisons)
      Mix.raise("Architecture check failed")
    end
  end

  defp parse_args!(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [graph: :string, policy: :string, baseline_dir: :string]
      )

    if positional != [] do
      Mix.raise("Usage: mix architecture.check [--graph PATH] [--policy PATH] [--baseline-dir PATH]")
    end

    opts
    |> Keyword.put_new(:policy, @default_policy)
    |> Keyword.put_new(:baseline_dir, @default_baseline_dir)
  end

  defp load_graph!(opts) do
    case Keyword.get(opts, :graph) do
      nil -> generate_xref_graph!()
      path -> File.read!(path)
    end
  end

  defp generate_xref_graph! do
    output =
      Path.join(
        System.tmp_dir!(),
        "storyarn-architecture-xref-#{System.unique_integer([:positive, :monotonic])}.json"
      )

    try do
      Mix.Task.reenable("xref")

      Mix.Task.run("xref", [
        "graph",
        "--format",
        "json",
        "--output",
        output,
        "--no-compile"
      ])

      File.read!(output)
    after
      File.rm(output)
    end
  end

  defp print_failures(comparisons) do
    Enum.each(Enum.sort(comparisons), fn {consumer, comparison} ->
      print_edges(consumer, "new forbidden dependencies", comparison.new)
      print_kind_changes(consumer, "stronger dependency kinds", comparison.strengthened)
      print_kind_changes(consumer, "weaker dependency kinds; refresh the reduced baseline", comparison.weakened)
      print_edges(consumer, "stale baseline entries; remove them", comparison.stale)
    end)
  end

  defp print_edges(_consumer, _heading, []), do: :ok

  defp print_edges(consumer, heading, edges) do
    Mix.shell().error("\n#{consumer}: #{heading}")

    Enum.each(edges, fn {source, target, kind} ->
      Mix.shell().error("  #{source} -> #{target} [#{kind}]")
    end)
  end

  defp print_kind_changes(_consumer, _heading, []), do: :ok

  defp print_kind_changes(consumer, heading, changes) do
    Mix.shell().error("\n#{consumer}: #{heading}")

    Enum.each(changes, fn change ->
      Mix.shell().error("  #{change.source} -> #{change.target} [#{change.from} -> #{change.to}]")
    end)
  end
end
