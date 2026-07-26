defmodule Storyarn.Sheets.DashboardHealthCoverageTest do
  @moduledoc """
  The invariant the sheets health consolidation exists for: **the sheet editor and
  the sheets dashboard cannot disagree about the same sheet, and the dashboard
  cannot hide a kind of problem the editor shows.**

  Before this, `list_dashboard_health_findings/2` hand-wrote three aggregate SQL
  detectors — `missing_sheet_shortcut`, `empty_leaf_sheet` and
  `no_internal_variable_usages`, the last capped at ten rows. That is 3 of the 26
  codes the checker can emit: a project whose sheets had broken inheritance, stale
  reference targets, cyclic formulas or values outside their constraints reported
  none of it outside the one sheet you happened to open. Measured on a real
  34-sheet project: 10 findings reported out of 140.

  Both surfaces now go through `Sheets.HealthChecker.check/1`. What this pins is
  that they also FEED it equivalently: the editor from
  `SheetLive.Helpers.HealthHelpers.sheet_snapshot/1` (live socket assigns), the
  dashboard from `Sheets.HealthSnapshots.load_project/2` (one batched read of
  the whole project). Slicing a project-wide enrichment is not the same as
  re-deriving it per sheet, and a field that drifts silently changes verdicts.
  """

  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.HealthChecker
  alias Storyarn.Sheets.HealthSnapshots
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias StoryarnWeb.SheetLive.Helpers.HealthHelpers

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # Agreement
  # ===========================================================================

  describe "editor and dashboard agree" do
    test "on a sheet carrying a problem of every shape", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})
      unhealthy_value_blocks(sheet)
      unhealthy_select_blocks(sheet)
      unhealthy_table(sheet)

      codes = sheet |> editor_findings(project) |> Enum.map(& &1.code) |> Enum.uniq()

      assert :value_outside_constraints in codes, "block-level detection"
      assert :cyclic_formula_dependency in codes, "cell-level detection"

      assert_agree(sheet, project)
    end

    test "on inherited blocks whose definition drifted", %{project: project} do
      parent = sheet_fixture(project, %{name: "Ancestor"})
      inheritable_block_fixture(parent, label: "Faction")
      child = child_sheet_fixture(project, parent, %{name: "Descendant"})

      instance = Enum.find(Sheets.list_blocks(child.id), &Block.inherited?/1)
      refute is_nil(instance), "the fixture must actually produce an instance"

      # Straight to the DB: `update_block/2` would re-sync the instance, which is
      # the opposite of the drift the audit reports.
      Repo.update_all(from(b in Block, where: b.id == ^instance.id), set: [required: true])

      assert :broken_inheritance in (child |> editor_findings(project) |> Enum.map(& &1.code))
      assert_agree(child, project)
    end

    test "on a stale incoming variable reference", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats", shortcut: "stats"})
      block = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      flow = flow_fixture(project)

      track_variable_reference(flow, "stats", block.variable_name)

      # The reference still points at the block by id, but its text no longer
      # matches the variable: exactly what the tracker flags as stale.
      Repo.update_all(from(b in Block, where: b.id == ^block.id), set: [variable_name: "renamed"])

      assert :stale_incoming_variable_reference in (sheet |> editor_findings(project) |> Enum.map(& &1.code))
      assert_agree(sheet, project)
    end

    test "on a table row that never stored its formula cell", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Sheet With Empty Formulas"})
      table = table_block_fixture(sheet, %{label: "Loot"})
      column = table_column_fixture(table, %{name: "Total", type: "formula"})
      row = hd(table.table_rows)

      # Drop the cell the column created, leaving the row's keys short of the
      # table's slugs. The formula enrichment materializes it again, so neither
      # surface sees a structure problem — a surface that skipped the enrichment
      # would invent an `invalid_table_structure` nobody can act on.
      row = Repo.reload!(row)
      Repo.update_all(from(r in TableRow, where: r.id == ^row.id), set: [cells: Map.delete(row.cells, column.slug)])

      refute :invalid_table_structure in (sheet |> editor_findings(project) |> Enum.map(& &1.code))
      assert_agree(sheet, project)
    end

    test "on a variable used only by a table formula binding", %{project: project} do
      target = sheet_fixture(project, %{name: "Target", shortcut: "target"})
      used = block_fixture(target, %{type: "number", config: %{"label" => "Damage"}})

      source = sheet_fixture(project, %{name: "Calculations"})
      table = table_block_fixture(source, %{label: "Maths"})
      formula = table_column_fixture(table, %{name: "Doubled", type: "formula"})

      {:ok, _row} =
        Sheets.update_table_cell(hd(table.table_rows), formula.slug, %{
          "expression" => "base * 2",
          "bindings" => %{"base" => %{"type" => "variable", "ref" => "target.#{used.variable_name}"}}
        })

      # A formula binding IS a usage. The editor used to consult only tracked
      # variable references, so it claimed "no internal usages" for a block the
      # dashboard correctly counted as used — the two surfaces contradicting each
      # other about the same block.
      refute :no_internal_variable_usages in (target |> editor_findings(project) |> Enum.map(& &1.code))
      assert comparable(editor_findings(target, project)) == comparable(dashboard_findings(target, project))

      # And the sheet that HOLDS the formula, which is where the binding is
      # type-checked against the project's variable set. Comparing only the target
      # would leave both surfaces free to check that binding against different
      # vocabularies: the narrower one calls a valid binding invalid.
      assert :no_internal_variable_usages in (source |> editor_findings(project) |> Enum.map(& &1.code)),
             "the source sheet must have findings, or the comparison below is vacuous"

      assert_agree(source, project)
    end

    test "type-checking formula bindings against one shared vocabulary", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Vocabulary", shortcut: "vocab"})
      plain = block_fixture(sheet, %{type: "number", config: %{"label" => "Plain"}})
      table = table_block_fixture(sheet, %{label: "Grid"})
      column = table_column_fixture(table, %{name: "Amount", type: "number"})
      row = hd(table.table_rows)

      editor = editor_snapshot(sheet, project).project_variable_types
      dashboard = dashboard_snapshot(sheet, project).project_variable_types

      # A binding is valid only if its `ref` is a key here, and a table cell folds
      # its row and column slugs into the reference. That four-segment spelling is
      # what a second copy of this map would get wrong — and if BOTH copies got it
      # wrong the same way, every agreement assertion above would still pass.
      cell_ref = "vocab.#{table.variable_name}.#{row.slug}.#{column.slug}"

      assert Map.get(editor, cell_ref) == "number",
             "the four-segment table-cell reference must be in the vocabulary, keyed by its own format"

      assert Map.get(editor, "vocab.#{plain.variable_name}") == "number"
      assert editor == dashboard
      assert editor == Sheets.health_variable_types(project.id)
    end

    test "attributing every finding to its own sheet", %{project: project} do
      first = sheet_fixture(project, %{name: "First"})
      second = sheet_fixture(project, %{name: "Second"})
      block_fixture(first, %{type: "number", config: %{"label" => "One"}})
      block_fixture(second, %{type: "number", config: %{"label" => "Two"}})

      by_sheet =
        project.id
        |> Sheets.list_dashboard_health_findings()
        |> Enum.group_by(& &1.sheet_id)

      # A nil key means a finding lost its sheet: the dashboard then links every
      # row to the same place and collapses two sheets into one.
      refute Map.has_key?(by_sheet, nil)
      assert Map.has_key?(by_sheet, first.id)
      assert Map.has_key?(by_sheet, second.id)
    end

    test "on an untouched sheet, reporting nothing either side", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Healthy"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Notes"}, value: %{"content" => "Fine"}})
      flow = flow_fixture(project)
      track_variable_reference(flow, sheet.shortcut, block.variable_name)

      # The positive control for every other assertion here: with nothing wrong,
      # both surfaces must say nothing at all.
      assert editor_findings(sheet, project) == []
      assert dashboard_findings(sheet, project) == []
    end
  end

  # ===========================================================================
  # Coverage
  # ===========================================================================

  describe "dashboard coverage of the checker vocabulary" do
    test "every code the checker can emit reaches the dashboard", %{project: project} do
      build_every_finding(project)

      emitted =
        project.id
        |> Sheets.list_dashboard_health_findings()
        |> MapSet.new(& &1.code)

      # No exclusion list: every one of the 26 is reachable from a project-wide
      # sweep. A code that stopped being reachable is a code users would only ever
      # see inside one sheet, which is the discrimination this test exists to
      # prevent — add the state that triggers it, do not shrink the assertion.
      assert MapSet.new(HealthChecker.codes()) == emitted
    end

    test "every finding carries the location a flat cross-sheet list needs", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Located"})
      table = table_block_fixture(sheet, %{label: "Inventory"})
      column = hd(table.table_columns)
      row = hd(table.table_rows)
      Repo.update_all(from(c in TableColumn, where: c.id == ^column.id), set: [name: ""])

      findings = Sheets.list_dashboard_health_findings(project.id)

      assert Enum.all?(findings, &(Map.get(&1.details, :sheet_name) == "Located"))

      axis = Enum.find(findings, &(&1.code == :unnamed_table_axis and &1.column_id == column.id))
      assert axis.details.block_label == "Inventory"
      refute Map.has_key?(axis.details, :column_label), "a blank name must not become a label"

      cell = Enum.find(findings, &(&1.code == :required_table_cell_empty or &1.row_id == row.id))
      assert is_nil(cell) or cell.details.row_label == row.name
    end

    test "the unused-variable rule reports every occurrence, not the first ten", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Many Variables"})
      for index <- 1..12, do: block_fixture(sheet, %{type: "number", config: %{"label" => "Stat #{index}"}})

      unused =
        project.id
        |> Sheets.list_dashboard_health_findings()
        |> Enum.filter(&(&1.code == :no_internal_variable_usages))

      assert length(unused) == 12
    end
  end

  describe "the vocabulary is single-sourced" do
    test "every code the checker can emit has a declared severity" do
      for code <- HealthChecker.codes() do
        assert HealthChecker.severity_for(code) in [:error, :warning, :info]
      end
    end

    test "an unknown code raises instead of defaulting to a severity" do
      assert_raise KeyError, fn -> HealthChecker.severity_for(:not_a_real_code) end
    end
  end

  # ===========================================================================
  # Comparison helpers
  # ===========================================================================

  defp assert_agree(sheet, project) do
    editor = comparable(editor_findings(sheet, project))
    dashboard = comparable(dashboard_findings(sheet, project))

    assert editor != [], "a vacuous comparison proves nothing: this sheet must have findings"
    assert editor == dashboard
  end

  defp comparable(findings) do
    findings
    |> Enum.map(&{&1.severity, &1.code, &1.block_id, &1.row_id, &1.column_id, &1.details})
    |> Enum.sort()
  end

  # The dashboard stamps the location labels a flat list needs; they are not part
  # of what the two surfaces must agree on.
  @location_keys [:sheet_name, :block_label, :row_label, :column_label]

  defp dashboard_findings(sheet, project) do
    project.id
    |> Sheets.list_dashboard_health_findings()
    |> Enum.filter(&(&1.sheet_id == sheet.id))
    |> Enum.map(&%{&1 | details: Map.drop(&1.details, @location_keys)})
  end

  defp editor_findings(sheet, project) do
    sheet |> editor_snapshot(project) |> HealthChecker.check()
  end

  defp dashboard_snapshot(sheet, project) do
    project.id
    |> HealthSnapshots.load_project()
    |> Enum.find(&(&1.sheet.id == sheet.id))
  end

  # Mirrors what `SheetLive.Show` loads before every `assign_sheet_health/1`, then
  # runs the editor's own snapshot builder over it.
  defp editor_snapshot(sheet, project) do
    {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet.id)
    all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

    gallery_ids = for block <- all_blocks, block.type == "gallery", do: block.id
    table_ids = for block <- all_blocks, block.type == "table", do: block.id

    HealthHelpers.sheet_snapshot(%{
      sheet: sheet,
      project: project,
      blocks: own_blocks,
      inherited_groups: inherited_groups,
      gallery_data: if(gallery_ids == [], do: %{}, else: Sheets.batch_load_gallery_data(gallery_ids)),
      table_data:
        if(table_ids == [],
          do: %{},
          else: table_ids |> Sheets.batch_load_table_data() |> Sheets.enrich_table_formulas(project.id)
        )
    })
  end

  # ===========================================================================
  # Unhealthy state builders
  # ===========================================================================

  # One project holding every code the checker can emit.
  defp build_every_finding(project) do
    # :empty_leaf_sheet — no blocks, no children.
    sheet_fixture(project, %{name: "Empty"})

    # :missing_sheet_shortcut
    shortcutless = sheet_fixture(project, %{name: "No Shortcut"})
    Repo.update_all(from(s in Sheet, where: s.id == ^shortcutless.id), set: [shortcut: nil])
    block_fixture(shortcutless, %{type: "text", config: %{"label" => "Any"}})

    values = sheet_fixture(project, %{name: "Values"})
    unhealthy_value_blocks(values)
    unhealthy_select_blocks(values)
    unhealthy_table(values)
    unhealthy_references(project, values)
    unhealthy_inheritance(project)
    unhealthy_variable_reference(project)
  end

  # :invalid_block_value, :required_block_empty, :invalid_constraints,
  # :value_outside_constraints, :missing_variable_name,
  # :no_internal_variable_usages, :invalid_block_layout
  defp unhealthy_value_blocks(sheet) do
    block_fixture(sheet, %{type: "number", config: %{"label" => "Wrong Type"}, value: %{"content" => "not a number"}})
    block_fixture(sheet, %{type: "text", config: %{"label" => "Needed"}, required: true, value: %{"content" => ""}})
    block_fixture(sheet, %{type: "number", config: %{"label" => "Inverted", "min" => 10, "max" => 5}})

    block_fixture(sheet, %{
      type: "number",
      config: %{"label" => "Too Small", "min" => 10},
      value: %{"content" => 1}
    })

    nameless = block_fixture(sheet, %{type: "text", config: %{"label" => "Nameless"}})
    Repo.update_all(from(b in Block, where: b.id == ^nameless.id), set: [variable_name: nil])

    # A column group of one: layouts hold two or three blocks.
    lonely = block_fixture(sheet, %{type: "text", config: %{"label" => "Lonely Column"}})

    Repo.update_all(from(b in Block, where: b.id == ^lonely.id),
      set: [column_group_id: Ecto.UUID.generate(), column_index: 0]
    )
  end

  # :empty_select_options, :invalid_select_option_keys, :blank_option_label,
  # :stale_selected_option
  defp unhealthy_select_blocks(sheet) do
    block_fixture(sheet, %{type: "select", config: %{"label" => "No Options", "options" => []}})

    block_fixture(sheet, %{
      type: "select",
      config: %{"label" => "Keyless", "options" => [%{"key" => "", "value" => "Nameless"}]}
    })

    block_fixture(sheet, %{
      type: "select",
      config: %{"label" => "Unlabelled", "options" => [%{"key" => "a", "value" => ""}]}
    })

    block_fixture(sheet, %{
      type: "select",
      config: %{"label" => "Stale Choice", "options" => [%{"key" => "a", "value" => "A"}]},
      value: %{"content" => "gone"}
    })
  end

  # :invalid_table_structure, :unnamed_table_axis, :required_table_cell_empty,
  # :invalid_formula_expression, :unbound_formula_symbol,
  # :invalid_formula_binding, :cyclic_formula_dependency,
  # :formula_evaluation_failed
  defp unhealthy_table(sheet) do
    structureless = table_block_fixture(sheet, %{label: "No Rows"})
    Repo.delete_all(from(r in TableRow, where: r.block_id == ^structureless.id))

    table = table_block_fixture(sheet, %{label: "Formulas"})
    blank_axis = hd(table.table_columns)
    Repo.update_all(from(c in TableColumn, where: c.id == ^blank_axis.id), set: [name: ""])

    numerator = table_column_fixture(table, %{name: "Numerator", type: "number"})
    divisor = table_column_fixture(table, %{name: "Divisor", type: "number"})
    text = table_column_fixture(table, %{name: "Note", type: "text"})
    required = table_column_fixture(table, %{name: "Required", type: "number", required: true})
    broken = table_column_fixture(table, %{name: "Broken", type: "formula"})
    unbound = table_column_fixture(table, %{name: "Unbound", type: "formula"})
    mistyped = table_column_fixture(table, %{name: "Mistyped", type: "formula"})
    divided = table_column_fixture(table, %{name: "Divided", type: "formula"})
    left = table_column_fixture(table, %{name: "Left", type: "formula"})
    right = table_column_fixture(table, %{name: "Right", type: "formula"})

    row = hd(table.table_rows)

    cells = %{
      blank_axis.slug => nil,
      numerator.slug => 10,
      divisor.slug => 0,
      text.slug => "prose",
      required.slug => nil,
      broken.slug => %{"expression" => "1 +", "bindings" => %{}},
      unbound.slug => %{"expression" => "orphan * 2", "bindings" => %{}},
      mistyped.slug => %{
        "expression" => "note",
        "bindings" => %{"note" => %{"type" => "same_row", "column_slug" => text.slug}}
      },
      divided.slug => %{
        "expression" => "top / bottom",
        "bindings" => %{
          "top" => %{"type" => "same_row", "column_slug" => numerator.slug},
          "bottom" => %{"type" => "same_row", "column_slug" => divisor.slug}
        }
      },
      left.slug => %{
        "expression" => "other",
        "bindings" => %{"other" => %{"type" => "same_row", "column_slug" => right.slug}}
      },
      right.slug => %{
        "expression" => "other",
        "bindings" => %{"other" => %{"type" => "same_row", "column_slug" => left.slug}}
      }
    }

    # `update_table_cells/2` rejects a formula cell whose bindings do not resolve —
    # which is precisely the state the checker reports. Straight to the DB, keeping
    # every column slug present so the row's schema still matches.
    Repo.update_all(from(r in TableRow, where: r.id == ^row.id), set: [cells: cells])
  end

  # :stale_reference_target, :disallowed_reference_target, :stale_inline_reference
  defp unhealthy_references(project, sheet) do
    target = sheet_fixture(project, %{name: "Doomed Target"})
    flow = flow_fixture(project, %{name: "Referenced Flow"})

    block_fixture(sheet, %{
      type: "reference",
      config: %{"label" => "Points Nowhere"},
      value: %{"target_type" => "sheet", "target_id" => target.id}
    })

    block_fixture(sheet, %{
      type: "reference",
      config: %{"label" => "Wrong Kind", "allowed_types" => ["sheet"]},
      value: %{"target_type" => "flow", "target_id" => flow.id}
    })

    block_fixture(sheet, %{
      type: "rich_text",
      config: %{"label" => "Mentions The Doomed"},
      value: %{
        "content" => ~s(<p>See <span class="mention" data-type="sheet" data-id="#{target.id}">Doomed</span>.</p>)
      }
    })

    # Orphaning the references is the point: `delete_sheet/1` would clean them up.
    Repo.update_all(from(s in Sheet, where: s.id == ^target.id), set: [deleted_at: DateTime.utc_now(:second)])
  end

  # :broken_inheritance
  defp unhealthy_inheritance(project) do
    parent = sheet_fixture(project, %{name: "Inheritance Root"})
    inheritable_block_fixture(parent, label: "Cascaded")
    child = child_sheet_fixture(project, parent, %{name: "Inheritance Child"})

    instance = Enum.find(Sheets.list_blocks(child.id), &Block.inherited?/1)
    Repo.update_all(from(b in Block, where: b.id == ^instance.id), set: [required: true])
  end

  # :stale_incoming_variable_reference
  defp unhealthy_variable_reference(project) do
    sheet = sheet_fixture(project, %{name: "Referenced Sheet", shortcut: "referenced"})
    block = block_fixture(sheet, %{type: "number", config: %{"label" => "Tracked"}})
    flow = flow_fixture(project, %{name: "Tracking Flow"})
    track_variable_reference(flow, "referenced", block.variable_name)

    Repo.update_all(from(b in Block, where: b.id == ^block.id), set: [variable_name: "renamed_away"])
  end

  # An instruction node that writes `sheet.variable`, with the reference recorded —
  # the same tracking the flow editor performs when a node is saved.
  defp track_variable_reference(flow, sheet_shortcut, variable_name) do
    assignment = %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "1",
      "value_type" => "literal"
    }

    node = node_fixture(flow, %{type: "instruction", data: %{"assignments" => [assignment]}})
    :ok = VariableReferenceTracker.update_references(node)
    node
  end
end
