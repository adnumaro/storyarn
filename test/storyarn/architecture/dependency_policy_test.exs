defmodule Storyarn.Architecture.DependencyPolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  test "finds forbidden domain and web edges while allowing same-boundary and unclassified targets" do
    graph = %{
      "lib/storyarn/flows/query.ex" => %{
        "lib/storyarn/flows/flow.ex" => "export",
        "lib/storyarn/repo.ex" => "runtime",
        "lib/storyarn/scenes/scene.ex" => "runtime"
      },
      "lib/storyarn_web/live/flow_live/show.ex" => %{
        "lib/storyarn/sheets.ex" => "runtime",
        "lib/storyarn_web/endpoint.ex" => "runtime"
      }
    }

    assert DependencyPolicy.forbidden_edges(graph, policy()) == %{
             flows:
               MapSet.new([
                 {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "runtime"},
                 {"lib/storyarn_web/live/flow_live/show.ex", "lib/storyarn/sheets.ex", "runtime"}
               ]),
             scenes: MapSet.new(),
             sheets: MapSet.new()
           }
  end

  test "an exact documented exception allows only its listed dependency kind" do
    policy =
      policy([
        %{
          source: "lib/storyarn/flows/query.ex",
          target: "lib/storyarn/scenes/scene.ex",
          kinds: ["runtime"],
          reason: "Stable shared expression contract"
        }
      ])

    runtime_graph = %{
      "lib/storyarn/flows/query.ex" => %{"lib/storyarn/scenes/scene.ex" => "runtime"}
    }

    compile_graph = %{
      "lib/storyarn/flows/query.ex" => %{"lib/storyarn/scenes/scene.ex" => "compile"}
    }

    assert DependencyPolicy.forbidden_edges(runtime_graph, policy).flows == MapSet.new()

    assert DependencyPolicy.forbidden_edges(compile_graph, policy).flows ==
             MapSet.new([
               {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "compile"}
             ])
  end

  test "platform prevents hidden tool bridges while allowing exact public targets" do
    policy = %{
      version: 1,
      boundaries: %{
        flows: ["lib/storyarn/flows/"],
        scenes: ["lib/storyarn/scenes/"],
        platform: ["lib/storyarn/"]
      },
      forbidden_dependencies: %{
        flows: [:platform, :scenes],
        scenes: [:flows, :platform],
        platform: [:flows, :scenes]
      },
      always_allowed_targets: ["lib/storyarn/analytics.ex", "lib/storyarn/repo.ex"],
      exceptions: []
    }

    graph = %{
      "lib/storyarn/flows/query.ex" => %{
        "lib/storyarn/analytics.ex" => "runtime",
        "lib/storyarn/analytics/post_hog_adapter.ex" => "runtime",
        "lib/storyarn/repo.ex" => "runtime"
      },
      "lib/storyarn/analytics/service.ex" => %{
        "lib/storyarn/analytics/post_hog_adapter.ex" => "runtime",
        "lib/storyarn/flows/flow.ex" => "runtime"
      }
    }

    assert DependencyPolicy.forbidden_edges(graph, policy) == %{
             flows:
               MapSet.new([
                 {"lib/storyarn/flows/query.ex", "lib/storyarn/analytics/post_hog_adapter.ex", "runtime"}
               ]),
             platform:
               MapSet.new([
                 {"lib/storyarn/analytics/service.ex", "lib/storyarn/flows/flow.ex", "runtime"}
               ]),
             scenes: MapSet.new()
           }
  end

  test "specific Web roots beat web platform and shared Web cannot bridge into tools" do
    policy = %{
      version: 1,
      boundaries: %{
        flows: ["lib/storyarn/flows/", "lib/storyarn_web/live/flow_live/"],
        sheets: ["lib/storyarn/sheets/"],
        web_platform: ["lib/storyarn_web/"]
      },
      forbidden_dependencies: %{
        flows: [:sheets],
        sheets: [:flows],
        web_platform: [:flows, :sheets]
      },
      always_allowed_targets: [],
      exceptions: []
    }

    graph = %{
      "lib/storyarn_web/helpers/entity_search.ex" => %{
        "lib/storyarn/flows/flow.ex" => "runtime"
      },
      "lib/storyarn_web/live/flow_live/show.ex" => %{
        "lib/storyarn/sheets/sheet.ex" => "runtime",
        "lib/storyarn_web/helpers/entity_search.ex" => "runtime"
      }
    }

    assert DependencyPolicy.forbidden_edges(graph, policy) == %{
             flows:
               MapSet.new([
                 {"lib/storyarn_web/live/flow_live/show.ex", "lib/storyarn/sheets/sheet.ex", "runtime"}
               ]),
             sheets: MapSet.new(),
             web_platform:
               MapSet.new([
                 {"lib/storyarn_web/helpers/entity_search.ex", "lib/storyarn/flows/flow.ex", "runtime"}
               ])
           }
  end

  test "comparison rejects new and stale edges" do
    current =
      MapSet.new([
        {"lib/storyarn/flows/new.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
      ])

    baseline =
      MapSet.new([
        {"lib/storyarn/flows/old.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
      ])

    comparison = DependencyPolicy.compare(current, baseline)

    assert comparison.new == [
             {"lib/storyarn/flows/new.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
           ]

    assert comparison.stale == [
             {"lib/storyarn/flows/old.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
           ]

    refute DependencyPolicy.clean?(comparison)
  end

  test "comparison reports stronger and weaker dependency kinds separately" do
    baseline =
      MapSet.new([
        {"lib/storyarn/flows/stronger.ex", "lib/storyarn/scenes/scene.ex", "runtime"},
        {"lib/storyarn/flows/weaker.ex", "lib/storyarn/sheets/sheet.ex", "compile"}
      ])

    current =
      MapSet.new([
        {"lib/storyarn/flows/stronger.ex", "lib/storyarn/scenes/scene.ex", "compile"},
        {"lib/storyarn/flows/weaker.ex", "lib/storyarn/sheets/sheet.ex", "runtime"}
      ])

    comparison = DependencyPolicy.compare(current, baseline)

    assert comparison.strengthened == [
             %{
               source: "lib/storyarn/flows/stronger.ex",
               target: "lib/storyarn/scenes/scene.ex",
               from: "runtime",
               to: "compile"
             }
           ]

    assert comparison.weakened == [
             %{
               source: "lib/storyarn/flows/weaker.ex",
               target: "lib/storyarn/sheets/sheet.ex",
               from: "compile",
               to: "runtime"
             }
           ]

    assert comparison.new == []
    assert comparison.stale == []
  end

  test "invalid policies and unknown xref kinds fail closed" do
    assert_raise ArgumentError, ~r/unknown target boundary/, fn ->
      policy = put_in(policy(), [:forbidden_dependencies, :flows], [:missing])
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/unknown xref dependency kind/, fn ->
      graph = %{"lib/storyarn/flows/query.ex" => %{"lib/storyarn/scenes/scene.ex" => "unknown"}}
      DependencyPolicy.forbidden_edges(graph, policy())
    end
  end

  defp policy(exceptions \\ []) do
    %{
      version: 1,
      boundaries: %{
        flows: ["lib/storyarn/flows/", "lib/storyarn_web/live/flow_live/"],
        scenes: ["lib/storyarn/scenes/"],
        sheets: ["lib/storyarn/sheets.ex", "lib/storyarn/sheets/"]
      },
      forbidden_dependencies: %{
        flows: [:scenes, :sheets],
        scenes: [:flows, :sheets],
        sheets: [:flows, :scenes]
      },
      always_allowed_targets: ["lib/storyarn/repo.ex"],
      exceptions: exceptions
    }
  end
end
