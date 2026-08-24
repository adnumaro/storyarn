defmodule Storyarn.Platform.GlobalSearch.AdvancedSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Platform.GlobalSearch
  alias Storyarn.Platform.GlobalSearch.AdvancedSearch
  alias Storyarn.Projects.References

  setup do
    user = user_fixture()

    %{
      user: user,
      scope: user_scope_fixture(user),
      project: project_fixture(user)
    }
  end

  describe "raw prefix contract" do
    test "rejects normal search text, help syntax, and empty input", %{scope: scope, project: project} do
      for raw_query <- ["", "kael", "?", "/help", "  #kael"] do
        assert {:error, :invalid_request} = AdvancedSearch.parse_prefix(raw_query)

        assert {:error, :invalid_request} =
                 GlobalSearch.advanced_project_search(scope, project.id, raw_query)
      end
    end

    test "rejects recognized prefixes whose body is empty", %{scope: scope, project: project} do
      for raw_query <- ["$", "#", ">", "@"] do
        assert {:ok, _mode, ""} = AdvancedSearch.parse_prefix(raw_query)

        assert {:error, :invalid_request} =
                 GlobalSearch.advanced_project_search(scope, project.id, raw_query)
      end
    end
  end

  describe "authorization and project isolation" do
    test "requires current project visibility and never searches another project", %{
      user: user,
      scope: scope,
      project: project
    } do
      own = sheet_fixture(project, %{name: "Shared Search Name", shortcut: "shared-own"})

      other_user = user_fixture()
      other_project = project_fixture(other_user)
      foreign = sheet_fixture(other_project, %{name: "Shared Search Name", shortcut: "shared-foreign"})

      assert {:error, :unauthorized} =
               GlobalSearch.advanced_project_search(scope, other_project.id, "#shared")

      assert {:ok, own_page} =
               GlobalSearch.advanced_project_search(scope, project.id, "#shared")

      assert Enum.map(own_page.items, & &1.action.destination.id) == [own.id]
      refute Enum.any?(own_page.items, &(&1.action.destination.id == foreign.id))

      membership_fixture(other_project, user, "viewer")

      assert {:ok, foreign_page} =
               GlobalSearch.advanced_project_search(scope, other_project.id, "#shared")

      assert Enum.map(foreign_page.items, & &1.action.destination.id) == [foreign.id]
    end
  end

  describe "hierarchy modes" do
    test "maps #, >, and @ to their hierarchy and completes branches but navigates leaves", %{
      scope: scope,
      project: project
    } do
      cases = [
        %{prefix: "#", mode: :sheets, type: :sheet},
        %{prefix: ">", mode: :flows, type: :flow},
        %{prefix: "@", mode: :scenes, type: :scene}
      ]

      for %{prefix: prefix, mode: mode, type: type} <- cases do
        root =
          hierarchy_fixture(type, project, %{
            name: "#{type} Advanced Root",
            shortcut: "#{type}-advanced-root"
          })

        branch =
          hierarchy_fixture(type, project, %{
            name: "#{type} Branch",
            shortcut: "#{type}-branch",
            parent_id: root.id,
            position: 0
          })

        leaf =
          hierarchy_fixture(type, project, %{
            name: "#{type} Leaf",
            shortcut: "#{type}-leaf",
            parent_id: root.id,
            position: 1
          })

        _grandchild =
          hierarchy_fixture(type, project, %{
            name: "#{type} Grandchild",
            shortcut: "#{type}-grandchild",
            parent_id: branch.id
          })

        assert {:ok, page} =
                 GlobalSearch.advanced_project_search(
                   scope,
                   project.id,
                   "#{prefix}#{root.shortcut}."
                 )

        assert page.mode == mode
        refute page.truncated

        hits_by_id = Map.new(page.items, &{&1.id, &1})
        branch_hit = Map.fetch!(hits_by_id, "#{type}:#{branch.id}")
        leaf_hit = Map.fetch!(hits_by_id, "#{type}:#{leaf.id}")

        assert branch_hit.kind == :hierarchy
        assert branch_hit.type == type

        assert branch_hit.action == %{
                 kind: :complete,
                 value: "#{prefix}#{root.shortcut}.#{branch.shortcut}."
               }

        assert branch_hit.context == "#{root.shortcut} › #{branch.shortcut}"
        assert branch_hit.meta.relation == :children

        assert leaf_hit.kind == :entity
        assert leaf_hit.type == type

        assert leaf_hit.action == %{
                 kind: :navigate,
                 destination: %{type: type, id: leaf.id}
               }

        assert leaf_hit.context == "#{root.shortcut} › #{leaf.shortcut}"
      end
    end
  end

  describe "deep all-mode fence" do
    test "* requires at least three characters and an explicit submit", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Alpha Archive", shortcut: "alpha-archive"})
      flow = flow_fixture(project, %{name: "Alpha Flow", shortcut: "alpha-flow"})
      scene = scene_fixture(project, %{name: "Alpha Scene", shortcut: "alpha-scene"})

      assert {:error, :invalid_request} =
               GlobalSearch.advanced_project_search(scope, project.id, "*al", submitted: true)

      assert {:error, :not_submitted} =
               GlobalSearch.advanced_project_search(scope, project.id, "*alpha")

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "*alpha",
                 submitted: true
               )

      assert page.mode == :all
      assert Enum.all?(page.items, &(&1.action.kind == :navigate))

      assert MapSet.new(Enum.map(page.items, &{&1.type, &1.action.destination.id})) ==
               MapSet.new([{:sheet, sheet.id}, {:flow, flow.id}, {:scene, scene.id}])
    end

    test "* applies one total limit across all entity types", %{scope: scope, project: project} do
      sheet_fixture(project, %{name: "Total Budget Sheet", shortcut: "total-budget-sheet"})
      flow_fixture(project, %{name: "Total Budget Flow", shortcut: "total-budget-flow"})
      scene_fixture(project, %{name: "Total Budget Scene", shortcut: "total-budget-scene"})

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "*total budget",
                 submitted: true,
                 limit: 2
               )

      assert page.mode == :all
      assert length(page.items) == 2
      assert page.truncated
    end
  end

  describe "bounded pages" do
    test "honors the requested bound and reports the extra matching row", %{
      scope: scope,
      project: project
    } do
      for index <- 1..3 do
        sheet_fixture(project, %{
          name: "Bounded Result #{index}",
          shortcut: "bounded-result-#{index}"
        })
      end

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "#bounded-result",
                 limit: 2
               )

      assert page.mode == :sheets
      assert length(page.items) == 2
      assert page.truncated
    end
  end

  describe "variable mode" do
    test "an ambiguous unqualified reference returns completions without expanding usages", %{
      scope: scope,
      project: project
    } do
      hero = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
      rival = sheet_fixture(project, %{name: "Rival", shortcut: "rival"})

      hero_health =
        block_fixture(hero, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 10}
        })

      rival_health =
        block_fixture(rival, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 20}
        })

      flow = flow_fixture(project, %{name: "Hero Health Logic", shortcut: "hero-health-logic"})
      _usage = tracked_write_node(flow, hero.shortcut, hero_health.variable_name)

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(scope, project.id, "$health")

      assert page.mode == :variables

      assert MapSet.new(Enum.map(page.items, & &1.id)) ==
               MapSet.new([
                 "variable-definition:#{hero_health.id}:0:0",
                 "variable-definition:#{rival_health.id}:0:0"
               ])

      assert Enum.all?(page.items, fn hit ->
               hit.kind == :definition and hit.action.kind == :complete
             end)
    end

    test "an unqualified predicate filters every exact definition by its initial value", %{
      scope: scope,
      project: project
    } do
      director = sheet_fixture(project, %{name: "Director Varek", shortcut: "director-varek"})
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      director_faction =
        block_fixture(director, %{
          type: "select",
          config: %{"label" => "Faction"},
          value: %{"content" => "conclave"}
        })

      kael_faction =
        block_fixture(kael, %{
          type: "select",
          config: %{"label" => "Faction"},
          value: %{"content" => "conclave"}
        })

      _nyx_faction =
        block_fixture(nyx, %{
          type: "select",
          config: %{"label" => "Faction"},
          value: %{"content" => "independent"}
        })

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$faction = conclave"
               )

      refute Map.has_key?(page, :fallback)

      assert MapSet.new(Enum.map(page.items, & &1.id)) ==
               MapSet.new([
                 "variable-definition:#{director_faction.id}:0:0",
                 "variable-definition:#{kael_faction.id}:0:0"
               ])

      assert Enum.all?(page.items, fn hit ->
               hit.kind == :definition and hit.group == :initial and
                 hit.action.kind == :navigate
             end)
    end

    test "predicate candidates include a match after 250 homonymous definitions", %{
      scope: scope,
      project: project
    } do
      matching_block =
        Enum.reduce(1..251, nil, fn index, match ->
          suffix = index |> Integer.to_string() |> String.pad_leading(3, "0")
          sheet = sheet_fixture(project, %{name: "Actor #{suffix}", shortcut: "actor-#{suffix}"})

          block =
            block_fixture(sheet, %{
              type: "select",
              config: %{"label" => "Faction"},
              value: %{"content" => if(index == 251, do: "conclave", else: "independent")}
            })

          if index == 251, do: block, else: match
        end)

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$faction = conclave"
               )

      assert Enum.map(page.items, & &1.id) ==
               ["variable-definition:#{matching_block.id}:0:0"]
    end

    test "select equality ignores case and surrounding whitespace in the stored key", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Faction",
            "options" => [%{"key" => "conclave-key", "value" => "The Conclave"}]
          },
          value: %{"content" => "conclave-key"}
        })

      assert_initial_definition(
        scope,
        project.id,
        ~s($faction = "  ConClave-Key  "),
        block.id
      )
    end

    test "select equality accepts the visible option label in addition to its stored key", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Faction",
            "options" => [%{"key" => "conclave-key", "value" => "The Conclave"}]
          },
          value: %{"content" => "conclave-key"}
        })

      assert_initial_definition(
        scope,
        project.id,
        ~s($faction = "  THE CONCLAVE  "),
        block.id
      )
    end

    test "select predicates match authored key occurrences through a normalized visible label", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Faction",
            "options" => [
              %{"key" => "conclave-key", "value" => "The Conclave"},
              %{"key" => "independent-key", "value" => "Independent"}
            ]
          },
          value: %{"content" => "independent-key"}
        })

      flow = flow_fixture(project, %{name: "Faction Gate", shortcut: "faction-gate"})

      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              condition_with_rules([
                variable_rule(sheet, block, "equals", "conclave-key")
              ])
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert_predicate_usage(
        scope,
        project.id,
        ~s($hero.faction = "  THE CONCLAVE  "),
        :condition_equals,
        node.id
      )
    end

    test "an unqualified predicate with no value matches returns qualified suggestions", %{
      scope: scope,
      project: project
    } do
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      block_fixture(kael, %{
        type: "select",
        config: %{"label" => "Faction"},
        value: %{"content" => "spiritbound"}
      })

      block_fixture(nyx, %{
        type: "select",
        config: %{"label" => "Faction"},
        value: %{"content" => "independent"}
      })

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$faction = conclave"
               )

      assert page.fallback == :qualified_references
      assert Enum.map(page.items, & &1.label) == ["kael.faction", "nyx.faction"]

      assert Enum.all?(page.items, fn hit ->
               hit.group == :suggestion and hit.action.kind == :complete and
                 String.ends_with?(hit.action.value, " = conclave")
             end)
    end

    test "unqualified number predicates match the correct table cell", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Characters", shortcut: "characters"})
      table = table_block_fixture(sheet, %{label: "Roster"})
      column = table_column_fixture(table, %{name: "Power Level", type: "number"})

      matching_row =
        table_row_fixture(table, %{
          name: "Kael",
          cells: %{column.slug => 12}
        })

      _non_matching_row =
        table_row_fixture(table, %{
          name: "Nyx",
          cells: %{column.slug => 4}
        })

      assert_table_initial_definition(
        scope,
        project.id,
        "$#{column.slug} >= 10",
        sheet.id,
        table.id,
        matching_row.id,
        column.id
      )
    end

    test "unqualified date predicates match the correct table cell", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Releases", shortcut: "releases"})
      table = table_block_fixture(sheet, %{label: "Schedule"})
      column = table_column_fixture(table, %{name: "Release Date", type: "date"})

      matching_row =
        table_row_fixture(table, %{
          name: "First Chapter",
          cells: %{column.slug => "2025-01-15"}
        })

      _non_matching_row =
        table_row_fixture(table, %{
          name: "Second Chapter",
          cells: %{column.slug => "2026-02-01"}
        })

      assert_table_initial_definition(
        scope,
        project.id,
        ~s($#{column.slug} < "2025-12-31"),
        sheet.id,
        table.id,
        matching_row.id,
        column.id
      )
    end

    test "unqualified select predicates accept the stored key and visible label for table cells", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Characters", shortcut: "characters"})
      table = table_block_fixture(sheet, %{label: "Roster"})

      column =
        table_column_fixture(table, %{
          name: "Faction",
          type: "select",
          config: %{
            "options" => [
              %{"key" => "conclave", "value" => "The Conclave"},
              %{"key" => "independent", "value" => "Independent"}
            ]
          }
        })

      matching_row =
        table_row_fixture(table, %{
          name: "Kael",
          cells: %{column.slug => "conclave"}
        })

      _non_matching_row =
        table_row_fixture(table, %{
          name: "Nyx",
          cells: %{column.slug => "independent"}
        })

      for query <- [
            "$#{column.slug} = CONCLAVE",
            ~s($#{column.slug} = "THE CONCLAVE")
          ] do
        assert_table_initial_definition(
          scope,
          project.id,
          query,
          sheet.id,
          table.id,
          matching_row.id,
          column.id
        )
      end
    end

    test "contains predicates filter regular initial values case-insensitively", %{
      scope: scope,
      project: project
    } do
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      kael_faction =
        block_fixture(kael, %{
          type: "text",
          config: %{"label" => "Faction"},
          value: %{"content" => "Order of the Conclave"}
        })

      nyx_faction =
        block_fixture(nyx, %{
          type: "text",
          config: %{"label" => "Faction"},
          value: %{"content" => "Independent"}
        })

      assert {:ok, contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$faction ~ CLAV"
               )

      assert Enum.map(contains_page.items, & &1.id) ==
               ["variable-definition:#{kael_faction.id}:0:0"]

      assert {:ok, not_contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$faction !~ cLaV"
               )

      assert Enum.map(not_contains_page.items, & &1.id) ==
               ["variable-definition:#{nyx_faction.id}:0:0"]
    end

    test "contains predicates treat SQL wildcard characters as literal search text", %{
      scope: scope,
      project: project
    } do
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      kael_code =
        block_fixture(kael, %{
          type: "text",
          config: %{"label" => "Faction Code"},
          value: %{"content" => "conclave%_elite"}
        })

      _nyx_code =
        block_fixture(nyx, %{
          type: "text",
          config: %{"label" => "Faction Code"},
          value: %{"content" => "conclave-ordinary"}
        })

      assert_initial_definition(
        scope,
        project.id,
        ~s($faction_code ~ "%_"),
        kael_code.id
      )
    end

    test "contains predicates filter authored table-cell values", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Characters", shortcut: "characters"})
      table = table_block_fixture(sheet, %{label: "Roster"})
      column = table_column_fixture(table, %{name: "Faction", type: "text"})

      kael =
        table_row_fixture(table, %{
          name: "Kael",
          cells: %{column.slug => "The CONCLAVE Vanguard"}
        })

      nyx =
        table_row_fixture(table, %{
          name: "Nyx",
          cells: %{column.slug => "Independent"}
        })

      assert_table_initial_definition(
        scope,
        project.id,
        "$#{column.slug} ~ clav",
        sheet.id,
        table.id,
        kael.id,
        column.id
      )

      assert_table_initial_definition(
        scope,
        project.id,
        "$#{column.slug} !~ CLAV",
        sheet.id,
        table.id,
        nyx.id,
        column.id
      )
    end

    test "not-contains excludes missing and malformed textual initial values", %{
      scope: scope,
      project: project
    } do
      valid_sheet = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})
      missing_sheet = sheet_fixture(project, %{name: "Unknown", shortcut: "unknown"})
      malformed_sheet = sheet_fixture(project, %{name: "Broken", shortcut: "broken"})

      valid =
        block_fixture(valid_sheet, %{
          type: "text",
          config: %{"label" => "Faction"},
          value: %{"content" => "Independent"}
        })

      block_fixture(missing_sheet, %{
        type: "text",
        config: %{"label" => "Faction"},
        value: %{"content" => nil}
      })

      block_fixture(malformed_sheet, %{
        type: "text",
        config: %{"label" => "Faction"},
        value: %{"content" => %{"unexpected" => "shape"}}
      })

      assert_initial_definition(scope, project.id, "$faction !~ clav", valid.id)
    end

    test "contains operators do not stringify numeric, boolean, or date values", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Stats", shortcut: "stats"})

      for {type, name, value, literal} <- [
            {"number", "health", 11, "1"},
            {"boolean", "alive", true, "tru"},
            {"date", "joined_at", "2026-07-29", "2026"}
          ] do
        block_fixture(sheet, %{
          type: type,
          variable_name: name,
          config: %{"label" => name},
          value: %{"content" => value}
        })

        assert {:ok, page} =
                 GlobalSearch.advanced_project_search(
                   scope,
                   project.id,
                   "$#{name} ~ #{literal}"
                 )

        refute Enum.any?(page.items, &(&1.group == :initial))
      end
    end

    test "contains predicates match select keys and visible labels for regular definitions", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Faction",
            "options" => [
              %{"key" => "faction-conclave", "value" => "Council of Ashes"},
              %{"key" => "faction-independent", "value" => "Free Agents"}
            ]
          },
          value: %{"content" => "faction-conclave"}
        })

      for query <- [
            "$faction ~ CLAV",
            "$faction ~ ashes"
          ] do
        assert_initial_definition(scope, project.id, query, block.id)
      end
    end

    test "contains predicates match select keys and visible labels for table cells", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Characters", shortcut: "characters"})
      table = table_block_fixture(sheet, %{label: "Roster"})

      column =
        table_column_fixture(table, %{
          name: "Faction",
          type: "select",
          config: %{
            "options" => [
              %{"key" => "faction-conclave", "value" => "Council of Ashes"},
              %{"key" => "faction-independent", "value" => "Free Agents"}
            ]
          }
        })

      row =
        table_row_fixture(table, %{
          name: "Kael",
          cells: %{column.slug => "faction-conclave"}
        })

      for query <- [
            "$#{column.slug} ~ CLAV",
            "$#{column.slug} ~ ashes"
          ] do
        assert_table_initial_definition(
          scope,
          project.id,
          query,
          sheet.id,
          table.id,
          row.id,
          column.id
        )
      end
    end

    test "qualified contains predicates resolve select labels for literal writes", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Faction",
            "options" => [
              %{"key" => "faction-conclave", "value" => "Council of Ashes"},
              %{"key" => "faction-independent", "value" => "Free Agents"}
            ]
          },
          value: %{"content" => "faction-independent"}
        })

      flow = flow_fixture(project, %{name: "Faction Writes", shortcut: "faction-writes"})
      conclave_write = tracked_literal_write_node(flow, sheet, block, "faction-conclave")
      independent_write = tracked_literal_write_node(flow, sheet, block, "faction-independent")

      assert {:ok, contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.faction ~ ashes"
               )

      assert Enum.any?(
               contains_page.items,
               &(&1.kind == :write_set and
                   &1.action.destination.focus == %{type: :node, id: conclave_write.id})
             )

      refute Enum.any?(
               contains_page.items,
               &(&1.action.destination.focus == %{type: :node, id: independent_write.id})
             )

      assert {:ok, not_contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.faction !~ ashes"
               )

      assert Enum.any?(
               not_contains_page.items,
               &(&1.kind == :write_set and
                   &1.action.destination.focus == %{type: :node, id: independent_write.id})
             )

      refute Enum.any?(
               not_contains_page.items,
               &(&1.action.destination.focus == %{type: :node, id: conclave_write.id})
             )
    end

    test "contains predicates return qualified suggestions when no initial value matches", %{
      scope: scope,
      project: project
    } do
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      block_fixture(kael, %{
        type: "text",
        config: %{"label" => "Faction"},
        value: %{"content" => "Conclave"}
      })

      block_fixture(nyx, %{
        type: "text",
        config: %{"label" => "Faction"},
        value: %{"content" => "Concord"}
      })

      for {query, suffix} <- [
            {"$faction ~ absent", " ~ absent"},
            {"$faction !~ con", " !~ con"}
          ] do
        assert {:ok, page} =
                 GlobalSearch.advanced_project_search(
                   scope,
                   project.id,
                   query
                 )

        assert page.fallback == :qualified_references
        assert Enum.map(page.items, & &1.label) == ["kael.faction", "nyx.faction"]

        assert Enum.all?(page.items, fn hit ->
                 hit.group == :suggestion and hit.action.kind == :complete and
                   String.ends_with?(hit.action.value, suffix)
               end)
      end
    end

    test "qualified contains predicates find matching flow conditions and literal writes", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Faction"},
          value: %{"content" => "Conclave resident"}
        })

      flow = flow_fixture(project, %{name: "Faction Logic", shortcut: "faction-logic"})

      contains_condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              condition_with_rules([
                variable_rule(sheet, block, "contains", "The Conclave")
              ])
          }
        })

      not_contains_condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              condition_with_rules([
                variable_rule(sheet, block, "not_contains", "The Conclave")
              ])
          }
        })

      contains_write = tracked_literal_write_node(flow, sheet, block, "Old Conclave")
      not_contains_write = tracked_literal_write_node(flow, sheet, block, "Independent")

      :ok = References.update_flow_node_variable_references(contains_condition)
      :ok = References.update_flow_node_variable_references(not_contains_condition)

      assert {:ok, contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.faction ~ CLAV"
               )

      assert Enum.any?(contains_page.items, fn hit ->
               hit.kind == :condition_contains and
                 hit.action.destination.focus == %{type: :node, id: contains_condition.id}
             end)

      assert Enum.any?(contains_page.items, fn hit ->
               hit.kind == :write_set and
                 hit.action.destination.focus == %{type: :node, id: contains_write.id}
             end)

      refute Enum.any?(contains_page.items, fn hit ->
               hit.action.destination.focus in [
                 %{type: :node, id: not_contains_condition.id},
                 %{type: :node, id: not_contains_write.id}
               ]
             end)

      assert {:ok, not_contains_page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.faction !~ CLAV"
               )

      assert Enum.any?(not_contains_page.items, fn hit ->
               hit.kind == :condition_not_contains and
                 hit.action.destination.focus == %{type: :node, id: not_contains_condition.id}
             end)

      assert Enum.any?(not_contains_page.items, fn hit ->
               hit.kind == :write_set and
                 hit.action.destination.focus == %{type: :node, id: not_contains_write.id}
             end)

      refute Enum.any?(not_contains_page.items, fn hit ->
               hit.action.destination.focus in [
                 %{type: :node, id: contains_condition.id},
                 %{type: :node, id: contains_write.id}
               ]
             end)
    end

    test "plain exact references return their definition plus tracked reads and writes", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 10}
        })

      flow = flow_fixture(project, %{name: "Health Logic", shortcut: "health-logic"})
      write_node = tracked_write_node(flow, sheet.shortcut, block.variable_name)
      read_node = tracked_read_node(flow, sheet.shortcut, block.variable_name)

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.health"
               )

      assert page.mode == :variables
      refute page.truncated

      assert Enum.any?(page.items, fn hit ->
               hit.kind == :definition and hit.group == :owner and
                 hit.action.destination == %{
                   type: :sheet,
                   id: sheet.id,
                   focus: %{type: :block, id: block.id}
                 }
             end)

      assert Enum.any?(page.items, fn hit ->
               hit.kind == :condition_greater_than and hit.group == :condition and
                 hit.action.destination == %{
                   type: :flow,
                   id: flow.id,
                   focus: %{type: :node, id: read_node.id}
                 }
             end)

      assert Enum.any?(page.items, fn hit ->
               hit.kind == :write_set and hit.group == :write and
                 hit.action.destination == %{
                   type: :flow,
                   id: flow.id,
                   focus: %{type: :node, id: write_node.id}
                 }
             end)
    end

    test "one source that reads and writes the same variable emits each semantic once", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 10}
        })

      flow = flow_fixture(project, %{name: "Self Assignment", shortcut: "self-assignment"})

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => Ecto.UUID.generate(),
                "sheet" => sheet.shortcut,
                "variable" => block.variable_name,
                "operator" => "set",
                "value" => block.variable_name,
                "value_type" => "variable_ref",
                "value_sheet" => sheet.shortcut
              }
            ]
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert {:ok, page} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.health"
               )

      usages = Enum.reject(page.items, &(&1.kind == :definition))

      assert length(usages) == 2
      assert MapSet.new(Enum.map(usages, & &1.kind)) == MapSet.new([:read, :write_set])

      assert Enum.all?(usages, fn hit ->
               hit.action.destination == %{
                 type: :flow,
                 id: flow.id,
                 focus: %{type: :node, id: node.id}
               }
             end)
    end

    test "predicates compare typed authored initial values", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      number =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 10}
        })

      boolean =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Active"},
          value: %{"content" => true}
        })

      date =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          value: %{"content" => "2000-01-02"}
        })

      assert_initial_definition(scope, project.id, "$hero.health > 5", number.id)
      assert_initial_definition(scope, project.id, "$hero.is_active = true", boolean.id)
      assert_initial_definition(scope, project.id, ~s($hero.birthday = "2000-01-02"), date.id)

      assert {:ok,
              %{
                mode: :variables,
                fallback: :qualified_references,
                items: [%{label: "hero.health", action: %{kind: :complete}}]
              }} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.health < 5"
               )

      assert {:ok,
              %{
                mode: :variables,
                fallback: :qualified_references,
                items: [%{label: "hero.is_active", action: %{kind: :complete}}]
              }} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.is_active = false"
               )
    end

    test "boolean predicates normalize uppercase literals for authored assignments", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Active"},
          value: %{"content" => false}
        })

      flow = flow_fixture(project, %{name: "Activate Hero", shortcut: "activate-hero"})

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => Ecto.UUID.generate(),
                "sheet" => sheet.shortcut,
                "variable" => block.variable_name,
                "operator" => "set_true"
              }
            ]
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert_predicate_usage(
        scope,
        project.id,
        "$hero.is_active = TRUE",
        :write_set_true,
        node.id
      )
    end

    test "orders date predicates chronologically", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      date =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          value: %{"content" => "2000-01-02"}
        })

      assert_initial_definition(scope, project.id, ~s($hero.birthday < "2001-01-01"), date.id)
    end

    test "ignores malformed map and list operands instead of crashing predicate search", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 0}
        })

      flow = flow_fixture(project, %{name: "Malformed Operands", shortcut: "malformed-operands"})

      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              condition_with_rules([
                variable_rule(sheet, block, "equals", %{"unexpected" => "map"}),
                variable_rule(sheet, block, "equals", ["unexpected", "list"])
              ])
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert {:ok,
              %{
                mode: :variables,
                fallback: :qualified_references,
                items: [%{label: "hero.health", action: %{kind: :complete}}]
              }} =
               GlobalSearch.advanced_project_search(
                 scope,
                 project.id,
                 "$hero.health = 10"
               )
    end

    test "matches authored before and after date conditions", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          value: %{"content" => "2025-01-01"}
        })

      flow = flow_fixture(project, %{name: "Date Conditions", shortcut: "date-conditions"})

      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              condition_with_rules([
                variable_rule(sheet, block, "before", "2025-01-01"),
                variable_rule(sheet, block, "after", "2025-01-01")
              ])
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert_predicate_usage(
        scope,
        project.id,
        ~s($hero.birthday < "2025-01-01"),
        :condition_before,
        node.id
      )

      assert_predicate_usage(
        scope,
        project.id,
        ~s($hero.birthday > "2025-01-01"),
        :condition_after,
        node.id
      )
    end

    test "matches authored set_if_unset assignments for equality predicates", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 0}
        })

      flow = flow_fixture(project, %{name: "Fallback Health", shortcut: "fallback-health"})

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => Ecto.UUID.generate(),
                "sheet" => sheet.shortcut,
                "variable" => block.variable_name,
                "operator" => "set_if_unset",
                "value" => "25",
                "value_type" => "literal"
              }
            ]
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      assert_predicate_usage(
        scope,
        project.id,
        "$hero.health = 25",
        :write_set_if_unset,
        node.id
      )
    end
  end

  defp hierarchy_fixture(:sheet, project, attrs), do: sheet_fixture(project, attrs)
  defp hierarchy_fixture(:flow, project, attrs), do: flow_fixture(project, attrs)
  defp hierarchy_fixture(:scene, project, attrs), do: scene_fixture(project, attrs)

  defp tracked_write_node(flow, sheet_shortcut, variable_name) do
    node =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "set",
              "value" => "1",
              "value_type" => "literal"
            }
          ]
        }
      })

    :ok = References.update_flow_node_variable_references(node)
    node
  end

  defp tracked_literal_write_node(flow, sheet, block, value) do
    node =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet.shortcut,
              "variable" => block.variable_name,
              "operator" => "set",
              "value" => value,
              "value_type" => "literal"
            }
          ]
        }
      })

    :ok = References.update_flow_node_variable_references(node)
    node
  end

  defp tracked_read_node(flow, sheet_shortcut, variable_name) do
    node =
      node_fixture(flow, %{
        type: "condition",
        data: %{
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{
                "id" => Ecto.UUID.generate(),
                "type" => "block",
                "logic" => "all",
                "rules" => [
                  %{
                    "id" => Ecto.UUID.generate(),
                    "sheet" => sheet_shortcut,
                    "variable" => variable_name,
                    "operator" => "greater_than",
                    "value" => "5"
                  }
                ]
              }
            ]
          }
        }
      })

    :ok = References.update_flow_node_variable_references(node)
    node
  end

  defp condition_with_rules(rules) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => rules
        }
      ]
    }
  end

  defp variable_rule(sheet, block, operator, value) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet.shortcut,
      "variable" => block.variable_name,
      "operator" => operator,
      "value" => value
    }
  end

  defp assert_predicate_usage(scope, project_id, query, expected_kind, node_id) do
    assert {:ok, %{mode: :variables, items: [hit]}} =
             GlobalSearch.advanced_project_search(scope, project_id, query)

    assert hit.kind == expected_kind
    assert hit.action.destination.focus == %{type: :node, id: node_id}
  end

  defp assert_initial_definition(scope, project_id, query, block_id) do
    assert {:ok, %{mode: :variables, items: [hit]}} =
             GlobalSearch.advanced_project_search(scope, project_id, query)

    assert hit.kind == :definition
    assert hit.group == :initial
    assert hit.id == "variable-definition:#{block_id}:0:0"
  end

  defp assert_table_initial_definition(scope, project_id, query, sheet_id, block_id, row_id, column_id) do
    assert {:ok, %{mode: :variables, items: [hit]}} =
             GlobalSearch.advanced_project_search(scope, project_id, query)

    assert hit.kind == :definition
    assert hit.group == :initial
    assert hit.id == "variable-definition:#{block_id}:#{row_id}:#{column_id}"

    assert hit.action == %{
             kind: :navigate,
             destination: %{
               type: :sheet,
               id: sheet_id,
               focus: %{
                 type: :cell,
                 block_id: block_id,
                 row_id: row_id,
                 column_id: column_id
               }
             }
           }
  end
end
