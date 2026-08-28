defmodule Storyarn.Architecture.PlatformInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/platform"
  @areas %{
    "adapters" => ~w(configuration email rate_limiter security),
    "collaboration" => ~w(adapters rules),
    "commercial" => ~w(commands entities execution projections queries reference_data rules),
    "delivery" => ~w(adapters),
    "discovery" => ~w(adapters commands entities projections queries reference_data),
    "kernel" => [],
    "notifications" => ~w(adapters entities execution projections queries),
    "object_storage" => ~w(adapters),
    "onboarding" => ~w(commands entities projections queries),
    "reactions" => ~w(adapters contracts events execution reference_data)
  }
  @root_files %{
    "adapters" => ~w(clock.ex rate_limiter.ex),
    "collaboration" => ~w(collaboration.ex),
    "commercial" => ~w(billing.ex commercial.ex project_storage_reservations.ex subscription_crud.ex),
    "delivery" => ~w(delivery.ex),
    "discovery" => ~w(command_palette.ex dashboard_cache.ex global_search.ex),
    "kernel" => ~w(html_utils.ex integer_parser.ex map_access.ex search_helpers.ex string_utils.ex),
    "notifications" => ~w(notifications.ex),
    "object_storage" => ~w(hashing.ex key_lock.ex),
    "onboarding" => ~w(onboarding.ex),
    "reactions" => ~w(reactions.ex)
  }
  @private_targets %{
    "commercial" => [
      "billing.ex",
      "project_storage_reservations.ex",
      "subscription_crud.ex",
      "commands/",
      "entities/",
      "execution/",
      "projections/",
      "queries/",
      "reference_data/",
      "rules/"
    ],
    "delivery" => ["adapters/"],
    "notifications" => ["adapters/", "entities/", "execution/", "projections/", "queries/"],
    "object_storage" => ["adapters/", "hashing.ex", "key_lock.ex"],
    "onboarding" => ["commands/", "entities/", "projections/", "queries/"],
    "reactions" => ["events/", "execution/", "reference_data/"]
  }
  @effectful_patterns [
    ~r/\bStoryarn\.Repo\b/,
    ~r/\bRepo\./,
    ~r/\bEcto\.Multi\b/,
    ~r/\bOban\b/,
    ~r/\bPhoenix\.PubSub\b/,
    ~r/\bReq\./,
    ~r/\bApplication\.(?:compile_env|fetch_env|get_env)\b/,
    ~r/\bSystem\.(?:cmd|fetch_env|get_env|monotonic_time|system_time)\b/,
    ~r/\bDateTime\.utc_now\b/,
    ~r/\bFile\./,
    ~r/\b(?:Agent|Finch|GenServer|Swoosh|Task)\b/,
    ~r/:ets\b/
  ]
  @query_forbidden_roles ~w(adapters commands events execution)
  @analytics_transport_target "lib/storyarn/platform/reactions/adapters/analytics.ex"
  @analytics_transport_allowed_source_roots [
    "lib/storyarn/platform/reactions/reactions.ex",
    "lib/storyarn/platform/reactions/events/"
  ]
  @web_application_private_targets %{
    "collaboration" => ["adapters/", "rules/"],
    "discovery" => ["adapters/", "commands/", "entities/", "projections/", "queries/", "reference_data/"]
  }

  test "Platform has exactly the agreed areas and no loose implementation files" do
    assert directories_in(@root) == @areas |> Map.keys() |> Enum.sort()
    assert files_in(@root) == ["README.md", "object_storage.ex"]
  end

  test "every area has only its agreed roles and stable public entry files" do
    Enum.each(@areas, fn {area, expected_roles} ->
      area_root = Path.join(@root, area)

      assert directories_in(area_root) == Enum.sort(expected_roles),
             "#{area} must use its agreed role folders"

      assert files_in(area_root) == Enum.sort(Map.fetch!(@root_files, area)),
             "#{area} has an unclassified implementation file at its root"
    end)
  end

  test "generic persistence and shared folders cannot return" do
    forbidden =
      @root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        File.dir?(path) and Path.basename(path) in ["persistence", "shared"]
      end)

    assert forbidden == [],
           "Platform uses capability-owned data and a closed kernel, not generic folders: #{inspect(forbidden)}"
  end

  test "projections and reference data remain passive" do
    passive_data_sources =
      Enum.flat_map(~w(projections reference_data), fn role ->
        Path.wildcard(Path.join(@root, "*/#{role}/**/*.ex"))
      end)

    violations =
      Enum.filter(passive_data_sources, fn path ->
        source = File.read!(path)
        Enum.any?(@effectful_patterns, &Regex.match?(&1, source))
      end)

    assert violations == [],
           "Platform passive data must not perform persistence, messaging, provider, or clock I/O: #{inspect(violations)}"
  end

  test "the technical kernel is deterministic and business-context neutral" do
    violations =
      @root
      |> Path.join("kernel/**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        effects =
          Enum.flat_map(@effectful_patterns, fn pattern ->
            if Regex.match?(pattern, source), do: [Regex.source(pattern)], else: []
          end)

        context_aliases = storyarn_aliases(source, path)

        Enum.map(effects ++ context_aliases, &"#{path}: #{&1}")
      end)

    assert violations == [],
           "Platform kernel modules must stay deterministic and context neutral: #{inspect(violations)}"
  end

  test "the ratchet keeps private capability roles behind their public facets" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for {source_capability, _source_targets} <- @private_targets,
        {target_capability, target_paths} <- @private_targets,
        source_capability != target_capability,
        target_path <- target_paths do
      assert denial?(
               policy,
               "#{@root}/#{source_capability}/",
               "#{@root}/#{target_capability}/#{target_path}",
               ["runtime", "export", "compile"]
             ),
             "missing private-role denial from #{source_capability} to #{target_capability}/#{target_path}"
    end
  end

  test "Platform queries cannot invoke effectful roles in their capability" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for capability <- Map.keys(@private_targets), target_role <- @query_forbidden_roles do
      assert denial?(
               policy,
               "#{@root}/#{capability}/queries/",
               "#{@root}/#{capability}/#{target_role}/",
               ["runtime", "export", "compile"]
             ),
             "missing query-role denial from #{capability} to #{target_role}"
    end
  end

  test "the root facade and Platform workers cannot execute private capability code" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for {capability, private_paths} <- @private_targets,
        private_path <- private_paths do
      kinds =
        if capability == "commercial" and
             private_path == "project_storage_reservations.ex" do
          ["runtime", "compile"]
        else
          ["runtime", "export", "compile"]
        end

      assert denial?(
               policy,
               "lib/storyarn/platform.ex",
               "#{@root}/#{capability}/#{private_path}",
               kinds
             ),
             "missing root-facade denial to #{capability}/#{private_path}"
    end

    Enum.each(Map.keys(@private_targets), fn capability ->
      assert denial?(
               policy,
               "lib/storyarn/workers/platform/",
               "#{@root}/#{capability}/",
               ["runtime", "export", "compile"]
             ),
             "Platform workers must enter #{capability} through Storyarn.Platform"
    end)
  end

  test "Web can use public application facets but not Collaboration or Discovery internals" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for {area, private_targets} <- @web_application_private_targets,
        private_target <- private_targets do
      assert denial?(
               policy,
               "lib/storyarn_web/",
               "#{@root}/#{area}/#{private_target}",
               ["runtime", "export", "compile"]
             ),
             "missing Web denial to #{area}/#{private_target}"
    end

    graph = %{
      "lib/storyarn_web/live/shared/collaboration_helpers.ex" => %{
        "#{@root}/collaboration/collaboration.ex" => "runtime",
        "#{@root}/collaboration/adapters/presence.ex" => "runtime"
      },
      "lib/storyarn_web/live/hooks/palette.ex" => %{
        "#{@root}/discovery/command_palette.ex" => "runtime",
        "#{@root}/discovery/queries/command_palette.ex" => "runtime"
      }
    }

    forbidden_edges =
      graph
      |> DependencyPolicy.forbidden_edges(policy)
      |> Map.values()
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    assert forbidden_edges ==
             MapSet.new([
               {"lib/storyarn_web/live/hooks/palette.ex", "#{@root}/discovery/queries/command_palette.ex", "runtime"},
               {"lib/storyarn_web/live/shared/collaboration_helpers.ex", "#{@root}/collaboration/adapters/presence.ex",
                "runtime"}
             ])
  end

  test "only the Reactions facade and reaction events can enter the Analytics transport" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert @analytics_transport_target in policy.globally_allowed_technical_targets

    denied_source_roots =
      policy.boundaries
      |> Map.values()
      |> List.flatten()
      |> Enum.reject(&(&1 in @analytics_transport_allowed_source_roots))

    Enum.each(denied_source_roots, fn source_root ->
      assert denial?(
               policy,
               source_root,
               @analytics_transport_target,
               ["runtime", "export", "compile"]
             ),
             "missing Analytics transport denial for #{source_root}"
    end)

    Enum.each(@analytics_transport_allowed_source_roots, fn source_root ->
      refute denial?(
               policy,
               source_root,
               @analytics_transport_target,
               ["runtime", "export", "compile"]
             ),
             "Analytics transport must remain reachable from #{source_root}"
    end)

    graph = %{
      "lib/storyarn/platform/reactions/reactions.ex" => %{
        @analytics_transport_target => "runtime"
      },
      "lib/storyarn/platform/reactions/events/future_reaction.ex" => %{
        @analytics_transport_target => "runtime"
      },
      "lib/storyarn/platform/onboarding/onboarding.ex" => %{
        @analytics_transport_target => "runtime"
      },
      "lib/storyarn/platform/discovery/global_search.ex" => %{
        @analytics_transport_target => "runtime"
      },
      "lib/storyarn/flows/editor/editor.ex" => %{
        @analytics_transport_target => "runtime"
      },
      "lib/storyarn_web/components/layouts.ex" => %{
        @analytics_transport_target => "runtime"
      }
    }

    forbidden_edges =
      graph
      |> DependencyPolicy.forbidden_edges(policy)
      |> Map.values()
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    assert forbidden_edges ==
             MapSet.new([
               {"lib/storyarn/platform/onboarding/onboarding.ex", @analytics_transport_target, "runtime"},
               {"lib/storyarn/platform/discovery/global_search.ex", @analytics_transport_target, "runtime"},
               {"lib/storyarn/flows/editor/editor.ex", @analytics_transport_target, "runtime"},
               {"lib/storyarn_web/components/layouts.ex", @analytics_transport_target, "runtime"}
             ])
  end

  defp directories_in(root) do
    root
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp files_in(root) do
    root
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp storyarn_aliases(source, path) do
    ast = Code.string_to_quoted!(source, file: path)

    own_module =
      case Regex.run(~r/^defmodule\s+([A-Za-z0-9_.]+)/m, source, capture: :all_but_first) do
        [module] -> module
        _missing -> nil
      end

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, [:Storyarn | _rest] = segments} = node, aliases ->
          {node, [Enum.join(segments, ".") | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    aliases
    |> Enum.uniq()
    |> Enum.reject(&(&1 == own_module))
  end

  defp denial?(policy, source_root, target_root, kinds) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and
        denial.kinds == kinds
    end)
  end
end
