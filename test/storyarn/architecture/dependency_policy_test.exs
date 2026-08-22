defmodule Storyarn.Architecture.DependencyPolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  test "finds forbidden domain and Web edges while allowing same-boundary and classified technical targets" do
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

    assert DependencyPolicy.unclassified_paths(graph, policy()) == []

    assert DependencyPolicy.forbidden_edges(graph, policy()) == %{
             flows:
               MapSet.new([
                 {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "runtime"},
                 {"lib/storyarn_web/live/flow_live/show.ex", "lib/storyarn/sheets.ex", "runtime"}
               ]),
             infrastructure: MapSet.new(),
             scenes: MapSet.new(),
             sheets: MapSet.new(),
             web_infrastructure: MapSet.new()
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

  test "directional allowances permit only the declared source root, target, and kind" do
    router = "lib/storyarn_web/router.ex"

    policy =
      policy()
      |> put_in(
        [:boundaries, :presentation_adapters],
        [router, "lib/storyarn_web/live_vue_encoders.ex"]
      )
      |> Map.put(:directional_allowances, [
        %{
          source_root: "lib/storyarn_web/",
          target: router,
          kinds: ["runtime"],
          reason: "Web adapters use verified routes"
        }
      ])

    graph = %{
      "lib/storyarn_web/live/flow_live/show.ex" => %{router => "runtime"},
      "lib/storyarn_web/live/flow_live/index.ex" => %{router => "compile"},
      "lib/storyarn/flows/query.ex" => %{router => "runtime"}
    }

    assert DependencyPolicy.forbidden_edges(graph, policy).flows ==
             MapSet.new([
               {"lib/storyarn/flows/query.ex", router, "runtime"},
               {"lib/storyarn_web/live/flow_live/index.ex", router, "compile"}
             ])
  end

  test "infrastructure prevents hidden tool bridges while allowing exact public targets" do
    policy = %{
      version: 1,
      bounded_contexts: [:flows, :scenes],
      classification_roots: classification_roots(),
      boundaries: %{
        flows: ["lib/storyarn/flows/"],
        infrastructure: ["lib/storyarn/analytics.ex", "lib/storyarn/analytics/", "lib/storyarn/repo.ex"],
        presentation_adapters: [
          "lib/storyarn_web/router.ex",
          "lib/storyarn_web/live_vue_encoders.ex"
        ],
        scenes: ["lib/storyarn/scenes/"],
        web_infrastructure: ["lib/storyarn_web/endpoint.ex"]
      },
      forbidden_dependencies: protected_dependencies([:flows, :scenes]),
      zero_debt_consumers: [],
      isolated_contexts: [],
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
             infrastructure:
               MapSet.new([
                 {"lib/storyarn/analytics/service.ex", "lib/storyarn/flows/flow.ex", "runtime"}
               ]),
             scenes: MapSet.new(),
             web_infrastructure: MapSet.new()
           }
  end

  test "specific Web roots beat Web infrastructure and shared Web cannot bridge into tools" do
    policy = %{
      version: 1,
      bounded_contexts: [:flows, :sheets],
      classification_roots: classification_roots(),
      boundaries: %{
        flows: ["lib/storyarn/flows.ex", "lib/storyarn/flows/", "lib/storyarn_web/live/flow_live/"],
        infrastructure: ["lib/storyarn/repo.ex"],
        presentation_adapters: ["lib/storyarn_web/live_vue_encoders.ex"],
        sheets: ["lib/storyarn/sheets/"],
        web_infrastructure: ["lib/storyarn_web/helpers/"]
      },
      forbidden_dependencies: protected_dependencies([:flows, :sheets]),
      zero_debt_consumers: [],
      isolated_contexts: [],
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
             infrastructure: MapSet.new(),
             sheets: MapSet.new(),
             web_infrastructure:
               MapSet.new([
                 {"lib/storyarn_web/helpers/entity_search.ex", "lib/storyarn/flows/flow.ex", "runtime"}
               ])
           }
  end

  test "presentation adapters may encode domain values but domains cannot import LiveVue adapters" do
    policy = %{
      version: 1,
      bounded_contexts: [:flows],
      classification_roots: classification_roots(),
      boundaries: %{
        flows: ["lib/storyarn/flows/"],
        infrastructure: ["lib/storyarn/repo.ex"],
        presentation_adapters: [
          "lib/storyarn_web/router.ex",
          "lib/storyarn_web/live_vue_encoders.ex"
        ],
        web_infrastructure: ["lib/storyarn_web/endpoint.ex"]
      },
      forbidden_dependencies: protected_dependencies([:flows]),
      zero_debt_consumers: [],
      isolated_contexts: [],
      always_allowed_targets: [],
      exceptions: []
    }

    graph = %{
      "lib/storyarn_web/live_vue_encoders.ex" => %{
        "lib/storyarn/flows/flow.ex" => "compile"
      },
      "lib/storyarn/flows/query.ex" => %{
        "lib/storyarn_web/live_vue_encoders.ex" => "runtime",
        "lib/storyarn_web/router.ex" => "runtime"
      }
    }

    assert DependencyPolicy.forbidden_edges(graph, policy) == %{
             flows:
               MapSet.new([
                 {"lib/storyarn/flows/query.ex", "lib/storyarn_web/live_vue_encoders.ex", "runtime"},
                 {"lib/storyarn/flows/query.ex", "lib/storyarn_web/router.ex", "runtime"}
               ]),
             infrastructure: MapSet.new(),
             web_infrastructure: MapSet.new()
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

  test "reports every unclassified backend and Web source or target" do
    graph = %{
      "lib/storyarn.ex" => %{},
      "lib/storyarn/ai/new_business_rule.ex" => %{},
      "lib/storyarn/shared/new_helper.ex" => %{},
      "lib/storyarn/unowned/service.ex" => %{},
      "lib/storyarn/flows/query.ex" => %{
        "lib/storyarn_web/new_surface.ex" => "runtime"
      },
      "lib/storyarn_web.ex" => %{}
    }

    assert DependencyPolicy.unclassified_paths(graph, policy()) == [
             "lib/storyarn.ex",
             "lib/storyarn/ai/new_business_rule.ex",
             "lib/storyarn/shared/new_helper.ex",
             "lib/storyarn/unowned/service.ex",
             "lib/storyarn_web.ex",
             "lib/storyarn_web/new_surface.ex"
           ]
  end

  test "classification scope cannot be reused as an ownership catch-all" do
    assert_raise ArgumentError, ~r/cannot cover an entire classification root/, fn ->
      policy = put_in(policy(), [:boundaries, :infrastructure], ["lib/storyarn/"])
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/cannot cover an entire classification root/, fn ->
      policy = put_in(policy(), [:boundaries, :web_infrastructure], ["lib/storyarn_web/"])
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "classification scope is exhaustive and cannot be narrowed" do
    assert_raise ArgumentError, ~r/classification roots must match the architecture policy/, fn ->
      policy = update_in(policy(), [:classification_roots], &List.delete(&1, "lib/storyarn_web/"))
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/classification roots must be unique: \["lib\/storyarn\/"\]/, fn ->
      policy = update_in(policy(), [:classification_roots], &["lib/storyarn/" | &1])
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "bounded contexts require an exhaustive cross-context matrix" do
    assert_raise ArgumentError, ~r/protected dependency sources.*missing: \[:flows\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies], &Map.delete(&1, :flows))
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :flows.*missing: \[:scenes\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies, :flows], &List.delete(&1, :scenes))
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/bounded contexts must be unique: \[:flows\]/, fn ->
      policy = %{policy() | bounded_contexts: [:flows, :flows, :scenes, :sheets]}
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "protected sources and infrastructure dependency rules are exact" do
    assert_raise ArgumentError, ~r/protected dependency sources.*unexpected: \[:bridge\]/, fn ->
      policy =
        policy()
        |> put_in([:boundaries, :bridge], ["lib/storyarn/bridge/"])
        |> put_in([:forbidden_dependencies, :bridge], [])

      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :flows.*missing: \[:infrastructure\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies, :flows], &List.delete(&1, :infrastructure))
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :flows.*unexpected: \[:web_infrastructure\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies, :flows], &[:web_infrastructure | &1])
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :infrastructure.*missing: \[:presentation_adapters\]/, fn ->
      policy =
        update_in(
          policy(),
          [:forbidden_dependencies, :infrastructure],
          &List.delete(&1, :presentation_adapters)
        )

      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :web_infrastructure.*missing: \[:sheets\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies, :web_infrastructure], &List.delete(&1, :sheets))
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/forbidden targets for :flows must be unique: \[:infrastructure\]/, fn ->
      policy = update_in(policy(), [:forbidden_dependencies, :flows], &[:infrastructure | &1])
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "always-allowed targets cannot bypass a bounded context" do
    assert_raise ArgumentError, ~r/always-allowed target belongs to bounded context :flows/, fn ->
      policy = %{policy() | always_allowed_targets: ["lib/storyarn/flows/flow.ex"]}
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/always-allowed target is not classified/, fn ->
      policy = %{policy() | always_allowed_targets: ["lib/storyarn/new_technical_helper.ex"]}
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "directional allowances cannot grant domain roots access to presentation adapters" do
    policy =
      policy()
      |> put_in(
        [:boundaries, :presentation_adapters],
        ["lib/storyarn_web/router.ex", "lib/storyarn_web/live_vue_encoders.ex"]
      )
      |> Map.put(:directional_allowances, [
        %{
          source_root: "lib/storyarn/flows/",
          target: "lib/storyarn_web/router.ex",
          kinds: ["runtime"],
          reason: "Invalid broadening"
        }
      ])

    assert_raise ArgumentError, ~r/source_root must stay inside StoryarnWeb/, fn ->
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "committed policy declares the agreed bounded contexts" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert policy.bounded_contexts == [
             :accounts,
             :workspaces,
             :platform,
             :projects,
             :sheets,
             :flows,
             :scenes,
             :localization
           ]

    assert "lib/storyarn.ex" in policy.boundaries.infrastructure
    assert "lib/storyarn_web.ex" in policy.boundaries.web_infrastructure
  end

  test "top-level application modules are covered by explicit technical roots" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    graph = %{
      "lib/storyarn.ex" => %{"lib/storyarn/flows.ex" => "runtime"},
      "lib/storyarn_web.ex" => %{"lib/storyarn/sheets.ex" => "runtime"}
    }

    forbidden = DependencyPolicy.forbidden_edges(graph, policy)

    assert forbidden.infrastructure ==
             MapSet.new([{"lib/storyarn.ex", "lib/storyarn/flows.ex", "runtime"}])

    assert forbidden.web_infrastructure ==
             MapSet.new([{"lib/storyarn_web.ex", "lib/storyarn/sheets.ex", "runtime"}])
  end

  test "Flows may use the storage contract but cannot bind to a concrete storage adapter" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    graph = %{
      "lib/storyarn/flows/versioning/snapshot_storage.ex" => %{
        "lib/storyarn/assets/storage.ex" => "runtime",
        "lib/storyarn/assets/storage/local.ex" => "runtime"
      }
    }

    forbidden = DependencyPolicy.forbidden_edges(graph, policy)

    assert forbidden.flows ==
             MapSet.new([
               {
                 "lib/storyarn/flows/versioning/snapshot_storage.ex",
                 "lib/storyarn/assets/storage/local.ex",
                 "runtime"
               }
             ])
  end

  test "committed policy rejects domain-to-Web dependencies even inside one owning context" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    graph = %{
      "lib/storyarn/flows/flow_crud.ex" => %{
        "lib/storyarn_web/live/flow_live/helpers/socket_helpers.ex" => "runtime"
      },
      "lib/storyarn_web/live/flow_live/show.ex" => %{
        "lib/storyarn_web/helpers/authorize.ex" => "runtime"
      }
    }

    forbidden = DependencyPolicy.forbidden_edges(graph, policy)

    assert forbidden.flows ==
             MapSet.new([
               {
                 "lib/storyarn/flows/flow_crud.ex",
                 "lib/storyarn_web/live/flow_live/helpers/socket_helpers.ex",
                 "runtime"
               }
             ])
  end

  test "zero-debt consumers reject any baseline edge even when it matches the graph" do
    edge = {"lib/storyarn/flows/query.ex", "lib/storyarn/scenes/scene.ex", "runtime"}
    policy = %{policy() | zero_debt_consumers: [:flows]}

    assert DependencyPolicy.zero_debt_baseline_violations(
             %{flows: MapSet.new([edge]), scenes: MapSet.new(), sheets: MapSet.new()},
             policy
           ) == %{flows: [edge]}

    assert DependencyPolicy.zero_debt_baseline_violations(
             %{flows: MapSet.new(), scenes: MapSet.new(), sheets: MapSet.new()},
             policy
           ) == %{}
  end

  test "isolated contexts reject inbound dependencies hidden in another consumer baseline" do
    inbound = {"lib/storyarn/scenes/catalog.ex", "lib/storyarn/flows.ex", "runtime"}
    policy = %{policy() | zero_debt_consumers: [:flows], isolated_contexts: [:flows]}

    assert DependencyPolicy.isolated_context_baseline_violations(
             %{
               flows: MapSet.new(),
               infrastructure: MapSet.new(),
               scenes: MapSet.new([inbound]),
               sheets: MapSet.new(),
               web_infrastructure: MapSet.new()
             },
             policy
           ) == %{flows: [inbound]}
  end

  test "isolated contexts must be unique bounded contexts already sealed as zero-debt" do
    assert_raise ArgumentError, ~r/isolated context must also be a zero-debt consumer: :flows/, fn ->
      policy = %{policy() | isolated_contexts: [:flows]}
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/isolated context is not a bounded context: :missing/, fn ->
      policy = %{policy() | zero_debt_consumers: [:flows], isolated_contexts: [:missing]}
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/isolated contexts must be unique: \[:flows\]/, fn ->
      policy = %{policy() | zero_debt_consumers: [:flows], isolated_contexts: [:flows, :flows]}
      DependencyPolicy.validate_policy!(policy)
    end
  end

  test "zero-debt consumers must be unique protected consumers" do
    assert_raise ArgumentError, ~r/consumer is not protected: :missing/, fn ->
      policy = %{policy() | zero_debt_consumers: [:missing]}
      DependencyPolicy.validate_policy!(policy)
    end

    assert_raise ArgumentError, ~r/consumers must be unique: \[:flows\]/, fn ->
      policy = %{policy() | zero_debt_consumers: [:flows, :flows]}
      DependencyPolicy.validate_policy!(policy)
    end
  end

  defp policy(exceptions \\ []) do
    %{
      version: 1,
      bounded_contexts: [:flows, :scenes, :sheets],
      classification_roots: classification_roots(),
      boundaries: %{
        flows: ["lib/storyarn/flows.ex", "lib/storyarn/flows/", "lib/storyarn_web/live/flow_live/"],
        infrastructure: ["lib/storyarn/repo.ex"],
        presentation_adapters: ["lib/storyarn_web/live_vue_encoders.ex"],
        scenes: ["lib/storyarn/scenes/"],
        sheets: ["lib/storyarn/sheets.ex", "lib/storyarn/sheets/"],
        web_infrastructure: ["lib/storyarn_web/endpoint.ex"]
      },
      forbidden_dependencies: protected_dependencies([:flows, :scenes, :sheets]),
      zero_debt_consumers: [],
      isolated_contexts: [],
      always_allowed_targets: ["lib/storyarn/repo.ex"],
      exceptions: exceptions
    }
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
