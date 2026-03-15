Mix.Task.run("app.start")

defmodule Storyarn.Scripts.SeedSkyOfReverieFlows do
  import Ecto.Query, warn: false
  require Logger

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.{Condition, Flow}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @project_slug "sky-of-reverie"

  @required_sheet_shortcuts [
    "teo",
    "guardian.nox",
    "guardian.luma",
    "npc.mina",
    "npc.lantern-keeper",
    "inv.reverie",
    "state",
    "force.unraveling"
  ]

  @managed_flow_shortcuts [
    "prologue.wake-and-flee",
    "refuge.promise-of-thread",
    "path.roadside-events",
    "event.shade-nest",
    "event.soft-bridge",
    "event.split-lantern",
    "event.root-gate",
    "meeting.lantern-clearing",
    "ambient.threshold-nox",
    "ambient.refuge-nox",
    "ambient.clearing-luma"
  ]

  def run do
    Logger.configure(level: :warning)

    project = fetch_project!()
    sheets = fetch_required_sheets!(project)
    flows = ensure_flows(project)

    sync_prologue(project, flows["prologue.wake-and-flee"], sheets)
    sync_refuge(project, flows["refuge.promise-of-thread"], sheets)
    sync_path_wrapper(project, flows["path.roadside-events"], sheets)
    sync_shade_nest(project, flows["event.shade-nest"], sheets)
    sync_soft_bridge(project, flows["event.soft-bridge"], sheets)
    sync_split_lantern(project, flows["event.split-lantern"], sheets)
    sync_root_gate(project, flows["event.root-gate"], sheets)
    sync_meeting(project, flows["meeting.lantern-clearing"], sheets)
    sync_ambient_threshold(project, flows["ambient.threshold-nox"], sheets)
    sync_ambient_refuge(project, flows["ambient.refuge-nox"], sheets)
    sync_ambient_clearing(project, flows["ambient.clearing-luma"], sheets)

    {:ok, _flow} = Flows.set_main_flow(flows["prologue.wake-and-flee"])

    Enum.each(@managed_flow_shortcuts, fn shortcut ->
      flow = get_flow_by_shortcut!(project.id, shortcut)

      Collaboration.broadcast_change({:flow, flow.id}, :flow_refresh, %{
        user_id: 0,
        user_email: "System",
        user_color: "#666"
      })
    end)

    IO.puts("")
    IO.puts("Flow seed complete")
    IO.puts("Project: #{project.name} (##{project.id})")

    for shortcut <- @managed_flow_shortcuts do
      flow = get_flow_by_shortcut!(project.id, shortcut)
      counts = Flows.count_nodes_by_type(flow.id)
      total_nodes = counts |> Map.values() |> Enum.sum()
      total_connections = length(Flows.list_connections(flow.id))
      IO.puts("  #{flow.shortcut} -> nodes=#{total_nodes}, connections=#{total_connections}")
    end
  end

  defp fetch_project! do
    Repo.one!(
      from p in Project,
        where: p.slug == ^@project_slug
    )
  end

  defp fetch_required_sheets!(%Project{} = project) do
    Map.new(@required_sheet_shortcuts, fn shortcut ->
      case Sheets.get_sheet_by_shortcut(project.id, shortcut) do
        nil -> raise "Missing required sheet #{shortcut} in project #{@project_slug}"
        sheet -> {shortcut, sheet}
      end
    end)
  end

  defp ensure_flows(%Project{} = project) do
    flow_specs()
    |> Enum.reduce(%{}, fn spec, acc ->
      parent_id =
        case spec.parent_shortcut do
          nil -> nil
          parent_shortcut -> Map.fetch!(acc, parent_shortcut).id
        end

      flow = ensure_flow(project, spec, parent_id)
      Map.put(acc, spec.shortcut, flow)
    end)
  end

  defp ensure_flow(%Project{} = project, spec, parent_id) do
    attrs = %{
      name: spec.name,
      shortcut: spec.shortcut,
      description: spec.description,
      parent_id: parent_id,
      position: spec.position,
      is_main: spec.shortcut == "prologue.wake-and-flee"
    }

    case get_flow_by_shortcut(project.id, spec.shortcut) do
      nil ->
        {:ok, flow} = Flows.create_flow(project, attrs)
        flow

      %Flow{} = flow ->
        {:ok, flow} = Flows.update_flow(flow, attrs)
        flow
    end
  end

  defp get_flow_by_shortcut(project_id, shortcut) do
    Repo.one(
      from f in Flow,
        where:
          f.project_id == ^project_id and
            f.shortcut == ^shortcut and
            is_nil(f.deleted_at) and
            is_nil(f.draft_id)
    )
  end

  defp get_flow_by_shortcut!(project_id, shortcut) do
    get_flow_by_shortcut(project_id, shortcut) || raise "Flow #{shortcut} not found"
  end

  defp reset_flow_canvas(%Project{} = project, %Flow{} = flow, exit_label) do
    full_flow = Flows.get_flow!(project.id, flow.id)

    Enum.each(full_flow.connections, fn connection ->
      {:ok, _conn} = Flows.delete_connection(connection)
    end)

    entry =
      Enum.find(full_flow.nodes, &(&1.type == "entry")) ||
        raise "Flow #{flow.shortcut} has no entry"

    exits = Enum.filter(full_flow.nodes, &(&1.type == "exit"))

    if exits == [] do
      raise "Flow #{flow.shortcut} has no exit"
    end

    [primary_exit | extra_exits] = exits

    full_flow.nodes
    |> Enum.reject(&(&1.id in [entry.id, primary_exit.id]))
    |> Enum.each(fn node ->
      {:ok, _node, _meta} = Flows.delete_node(node)
    end)

    Enum.each(extra_exits, fn node ->
      {:ok, _node, _meta} = Flows.delete_node(node)
    end)

    {:ok, entry} =
      Flows.update_node(entry, %{
        position_x: 100.0,
        position_y: 300.0,
        data: %{}
      })

    {:ok, exit_node} =
      Flows.update_node(primary_exit, %{
        position_x: 1600.0,
        position_y: 300.0,
        data: exit_data(exit_label)
      })

    %{flow: flow, entry: entry, exit: exit_node}
  end

  defp exit_data(label) do
    %{
      "label" => label,
      "technical_id" => "",
      "outcome_tags" => [],
      "outcome_color" => "#22c55e",
      "exit_mode" => "terminal",
      "referenced_flow_id" => nil
    }
  end

  defp create_node!(%Flow{} = flow, type, x, y, data) do
    {:ok, node} =
      Flows.create_node(flow, %{
        type: type,
        position_x: x,
        position_y: y,
        data: data
      })

    node
  end

  defp create_dialogue!(%Flow{} = flow, x, y, speaker_sheet_id, text, responses \\ []) do
    create_node!(flow, "dialogue", x, y, %{
      "speaker_sheet_id" => speaker_sheet_id,
      "text" => text,
      "responses" => responses
    })
  end

  defp create_instruction!(%Flow{} = flow, x, y, description, assignments) do
    create_node!(flow, "instruction", x, y, %{
      "description" => description,
      "assignments" => assignments
    })
  end

  defp create_condition!(%Flow{} = flow, x, y, condition, switch_mode \\ false) do
    create_node!(flow, "condition", x, y, %{
      "condition" => condition,
      "switch_mode" => switch_mode
    })
  end

  defp connect!(
         %Flow{} = flow,
         source_node,
         target_node,
         source_pin \\ "output",
         target_pin \\ "input"
       ) do
    {:ok, _connection} =
      Flows.create_connection(flow, source_node, target_node, %{
        source_pin: source_pin,
        target_pin: target_pin
      })
  end

  defp apply_positions!(%Flow{} = flow, nodes_with_positions) do
    positions =
      Enum.map(nodes_with_positions, fn {node, {x, y}} ->
        %{id: node.id, position_x: x, position_y: y}
      end)

    {:ok, _count} = Flows.batch_update_positions(flow.id, positions)
  end

  defp assignment(
         id,
         sheet,
         variable,
         operator,
         value \\ nil,
         value_type \\ "literal",
         value_sheet \\ nil
       ) do
    %{
      "id" => id,
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value,
      "value_type" => value_type,
      "value_sheet" => value_sheet
    }
  end

  defp response(id, text, opts) do
    condition =
      case Keyword.get(opts, :condition) do
        nil -> ""
        condition_map -> Condition.to_json(condition_map)
      end

    %{
      "id" => id,
      "text" => text,
      "condition" => condition,
      "instruction" => nil,
      "instruction_assignments" => Keyword.get(opts, :instruction_assignments, [])
    }
  end

  defp rule(id, sheet, variable, operator, value, label \\ nil) do
    base = %{
      "id" => id,
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value
    }

    if is_nil(label), do: base, else: Map.put(base, "label", label)
  end

  defp boolean_rule(id, sheet, variable, operator, label \\ nil) do
    base = %{
      "id" => id,
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator
    }

    if is_nil(label), do: base, else: Map.put(base, "label", label)
  end

  defp sync_prologue(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Reach Mender's Isle")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    set_threshold =
      create_instruction!(flow, 260.0, 300.0, "Mark the broken threshold as the current area", [
        assignment("prologue_area_threshold", "state", "area_current", "set", "threshold")
      ])

    teo_monologue =
      create_dialogue!(
        flow,
        460.0,
        300.0,
        teo,
        "Teo wakes inside a white tunnel split with cracks and hanging above an endless drop. He knows his name. He does not know when he crossed into this place."
      )

    first_contact =
      create_dialogue!(
        flow,
        700.0,
        300.0,
        nox,
        "Questions later. Move now. The threshold is failing."
      )

    pushes_back =
      create_dialogue!(flow, 940.0, 300.0, teo, "Teo plants his feet instead of running.", [
        response("ask_where", "Tell me where I am first.",
          instruction_assignments: [
            assignment(
              "prologue_curiosity_where",
              "teo",
              "something_here.curiosity.value",
              "add",
              "1"
            )
          ]
        ),
        response("ask_mom", "Have you seen my mom?",
          instruction_assignments: [
            assignment("prologue_mother_trace", "state", "mother_trace", "add", "1"),
            assignment(
              "prologue_mother_empathy",
              "teo",
              "something_here.empathy.value",
              "add",
              "1"
            ),
            assignment("prologue_trace_on_teo", "force.unraveling", "trace_on_teo", "add", "1")
          ]
        ),
        response("ask_what", "What are you?",
          instruction_assignments: [
            assignment(
              "prologue_curiosity_what",
              "teo",
              "something_here.curiosity.value",
              "add",
              "1"
            ),
            assignment(
              "prologue_courage_what",
              "teo",
              "something_here.courage.value",
              "add",
              "1"
            )
          ]
        )
      ])

    shadow_alarm =
      create_instruction!(flow, 1180.0, 300.0, "The tunnel starts reacting to the delay", [
        assignment("prologue_local_corruption", "state", "local_corruption", "add", "1"),
        assignment("prologue_near_threshold", "force.unraveling", "near_threshold", "set_true"),
        assignment("prologue_watching_nox", "force.unraveling", "watching_nox", "set_true"),
        assignment("prologue_intensity", "force.unraveling", "intensity", "add", "1")
      ])

    shades_arrive =
      create_dialogue!(
        flow,
        1420.0,
        300.0,
        nox,
        "Too late. The spirits found us. If they surround you, the tunnel will help them."
      )

    resolve_attack =
      create_condition!(
        flow,
        1660.0,
        300.0,
        %{
          "logic" => "any",
          "rules" => [
            rule(
              "case_steady",
              "teo",
              "something_here.courage.value",
              "greater_than_or_equal",
              "3",
              "Steady"
            ),
            rule(
              "case_hesitates",
              "teo",
              "something_here.tenacity.value",
              "less_than_or_equal",
              "2",
              "Hesitates"
            )
          ]
        },
        true
      )

    block =
      create_dialogue!(
        flow,
        1900.0,
        140.0,
        nox,
        "Hold still. If I take the hit as a shield, you keep moving."
      )

    late_run =
      create_dialogue!(
        flow,
        1900.0,
        300.0,
        teo,
        "Teo hesitates just long enough for the dark to fold around his ankles."
      )

    nox_hit =
      create_instruction!(flow, 1900.0, 460.0, "Nox burns energy to force a gap open", [
        assignment("prologue_nox_energy_hit", "guardian.nox", "form_energy", "subtract", "2"),
        assignment("prologue_nox_injured_guardian", "guardian.nox", "injured", "set_true"),
        assignment("prologue_nox_injured_state", "state", "nox_injured", "set_true"),
        assignment(
          "prologue_nox_shield_unlocked",
          "guardian.nox",
          "forms.shield.unlocked",
          "set_true"
        ),
        assignment("prologue_force_rises", "force.unraveling", "intensity", "add", "1")
      ])

    aftermath =
      create_instruction!(
        flow,
        2140.0,
        300.0,
        "The first attack resolves, but the tunnel keeps collapsing",
        [
          assignment("prologue_attack_resolved", "state", "first_attack_resolved", "set_true"),
          assignment(
            "prologue_tenacity_after_hit",
            "teo",
            "something_here.tenacity.value",
            "add",
            "1"
          )
        ]
      )

    more_shades =
      create_dialogue!(
        flow,
        2380.0,
        300.0,
        nox,
        "More of them. The walls are opening now."
      )

    great_breach =
      create_dialogue!(
        flow,
        2620.0,
        300.0,
        nox,
        "Jump. The floor isn't safer than the fall."
      )

    flight_form =
      create_instruction!(flow, 2860.0, 300.0, "Nox changes shape mid-fall", [
        assignment(
          "prologue_nox_winged_beast",
          "guardian.nox",
          "current_mode",
          "set",
          "winged_beast"
        ),
        assignment(
          "prologue_nox_winged_unlocked",
          "guardian.nox",
          "forms.winged_beast.unlocked",
          "set_true"
        ),
        assignment("prologue_nox_energy_flight", "guardian.nox", "form_energy", "subtract", "1")
      ])

    flight =
      create_dialogue!(
        flow,
        3100.0,
        300.0,
        teo,
        "The drop vanishes under me as Nox turns into a winged beast and catches me in midair."
      )

    impact =
      create_instruction!(flow, 3340.0, 300.0, "The landing hurts, but the island holds", [
        assignment("prologue_nox_mist_mode", "guardian.nox", "current_mode", "set", "mist"),
        assignment("prologue_nox_injured_guardian_final", "guardian.nox", "injured", "set_true"),
        assignment("prologue_nox_injured_state_final", "state", "nox_injured", "set_true"),
        assignment("prologue_refuge_discovered", "state", "refuge_discovered", "set_true"),
        assignment("prologue_area_isle", "state", "area_current", "set", "isle"),
        assignment(
          "prologue_tenacity_landing",
          "teo",
          "something_here.tenacity.value",
          "add",
          "1"
        )
      ])

    landing_line =
      create_dialogue!(
        flow,
        3580.0,
        300.0,
        nox,
        "Inside. Before the dark learns how to land."
      )

    connect!(flow, canvas.entry, set_threshold, "output")
    connect!(flow, set_threshold, teo_monologue)
    connect!(flow, teo_monologue, first_contact)
    connect!(flow, first_contact, pushes_back)
    connect!(flow, pushes_back, shadow_alarm, "ask_where")
    connect!(flow, pushes_back, shadow_alarm, "ask_mom")
    connect!(flow, pushes_back, shadow_alarm, "ask_what")
    connect!(flow, shadow_alarm, shades_arrive)
    connect!(flow, shades_arrive, resolve_attack)
    connect!(flow, resolve_attack, block, "case_steady")
    connect!(flow, resolve_attack, late_run, "case_hesitates")
    connect!(flow, resolve_attack, nox_hit, "default")
    connect!(flow, block, aftermath)
    connect!(flow, late_run, aftermath)
    connect!(flow, nox_hit, aftermath)
    connect!(flow, aftermath, more_shades)
    connect!(flow, more_shades, great_breach)
    connect!(flow, great_breach, flight_form)
    connect!(flow, flight_form, flight)
    connect!(flow, flight, impact)
    connect!(flow, impact, landing_line)
    connect!(flow, landing_line, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {set_threshold, {260, 300}},
      {teo_monologue, {460, 300}},
      {first_contact, {700, 300}},
      {pushes_back, {940, 300}},
      {shadow_alarm, {1180, 300}},
      {shades_arrive, {1420, 300}},
      {resolve_attack, {1660, 300}},
      {block, {1900, 140}},
      {late_run, {1900, 300}},
      {nox_hit, {1900, 460}},
      {aftermath, {2140, 300}},
      {more_shades, {2380, 300}},
      {great_breach, {2620, 300}},
      {flight_form, {2860, 300}},
      {flight, {3100, 300}},
      {impact, {3340, 300}},
      {landing_line, {3580, 300}},
      {canvas.exit, {3820, 300}}
    ])
  end

  defp sync_refuge(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Leave the House of Thread")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    enter_refuge =
      create_instruction!(flow, 260.0, 300.0, "Mark the refuge as the current area", [
        assignment("refuge_area_house", "state", "area_current", "set", "house")
      ])

    teo_offers_help =
      create_dialogue!(
        flow,
        500.0,
        300.0,
        teo,
        "Sit down. You're the one who got hit."
      )

    use_dew =
      create_condition!(flow, 760.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          rule("dew_ready", "inv.reverie", "dew_drops", "greater_than", "0")
        ]
      })

    heal_nox =
      create_instruction!(flow, 1020.0, 180.0, "Spend dew drops to steady Nox", [
        assignment("refuge_spend_dew", "inv.reverie", "dew_drops", "subtract", "1"),
        assignment("refuge_restore_energy", "guardian.nox", "form_energy", "add", "2"),
        assignment("refuge_nox_mode_lantern", "guardian.nox", "current_mode", "set", "lantern"),
        assignment(
          "refuge_nox_lantern_unlocked",
          "guardian.nox",
          "forms.lantern.unlocked",
          "set_true"
        ),
        assignment(
          "refuge_teo_empathy",
          "teo",
          "something_here.empathy.value",
          "add",
          "1"
        ),
        assignment("refuge_lower_corruption", "state", "local_corruption", "subtract", "1")
      ])

    no_heal =
      create_dialogue!(
        flow,
        1020.0,
        420.0,
        nox,
        "Keep the dew. If the road turns mean, you'll want it more than I do."
      )

    nox_admits_limit =
      create_dialogue!(
        flow,
        1280.0,
        300.0,
        nox,
        "I'm not broken. I'm limited. And I still haven't found Luma."
      )

    teo_asks_mother =
      create_dialogue!(flow, 1540.0, 300.0, teo, "Teo does not let the question go.", [
        response("ask_mother_direct", "Then help me find my mother.",
          instruction_assignments: [
            assignment("refuge_mother_trace", "state", "mother_trace", "add", "1"),
            assignment(
              "refuge_mother_empathy",
              "teo",
              "something_here.empathy.value",
              "add",
              "1"
            )
          ]
        ),
        response("ask_world_name", "What is this place, really?",
          instruction_assignments: [
            assignment(
              "refuge_curiosity",
              "teo",
              "something_here.curiosity.value",
              "add",
              "1"
            ),
            assignment("refuge_accepts_hint", "teo", "accepts_reverie", "set_true")
          ]
        )
      ])

    nox_cannot_answer =
      create_dialogue!(
        flow,
        1800.0,
        300.0,
        nox,
        "I don't have your answer. I only have a way forward."
      )

    open_goal =
      create_instruction!(
        flow,
        2060.0,
        300.0,
        "Open the next objective on the road to the clearing",
        [assignment("refuge_path_closed_for_now", "state", "path_open", "set_false")]
      )

    path_objective =
      create_dialogue!(
        flow,
        2320.0,
        300.0,
        nox,
        "Cross the veiled path. If Luma is anywhere near this island, the clearing will know first."
      )

    connect!(flow, canvas.entry, enter_refuge, "output")
    connect!(flow, enter_refuge, teo_offers_help)
    connect!(flow, teo_offers_help, use_dew)
    connect!(flow, use_dew, heal_nox, "true")
    connect!(flow, use_dew, no_heal, "false")
    connect!(flow, heal_nox, nox_admits_limit)
    connect!(flow, no_heal, nox_admits_limit)
    connect!(flow, nox_admits_limit, teo_asks_mother)
    connect!(flow, teo_asks_mother, nox_cannot_answer, "ask_mother_direct")
    connect!(flow, teo_asks_mother, nox_cannot_answer, "ask_world_name")
    connect!(flow, nox_cannot_answer, open_goal)
    connect!(flow, open_goal, path_objective)
    connect!(flow, path_objective, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {enter_refuge, {260, 300}},
      {teo_offers_help, {500, 300}},
      {use_dew, {760, 300}},
      {heal_nox, {1020, 180}},
      {no_heal, {1020, 420}},
      {nox_admits_limit, {1280, 300}},
      {teo_asks_mother, {1540, 300}},
      {nox_cannot_answer, {1800, 300}},
      {open_goal, {2060, 300}},
      {path_objective, {2320, 300}},
      {canvas.exit, {2580, 300}}
    ])
  end

  defp sync_path_wrapper(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Use the nested path events")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    enter_path =
      create_instruction!(flow, 260.0, 300.0, "Mark the veiled path as the current area", [
        assignment("path_area_path", "state", "area_current", "set", "path")
      ])

    path_intro =
      create_dialogue!(
        flow,
        520.0,
        300.0,
        nox,
        "The veiled path doesn't test one thing. It stacks small pressures until the clearing sees what survives the road."
      )

    tutorial_note =
      create_dialogue!(
        flow,
        780.0,
        300.0,
        teo,
        "So every stop on this road changes how we arrive."
      )

    connect!(flow, canvas.entry, enter_path, "output")
    connect!(flow, enter_path, path_intro)
    connect!(flow, path_intro, tutorial_note)
    connect!(flow, tutorial_note, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {enter_path, {260, 300}},
      {path_intro, {520, 300}},
      {tutorial_note, {780, 300}},
      {canvas.exit, {1040, 300}}
    ])
  end

  defp sync_shade_nest(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Resolve the shade nest")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    courage_condition = %{
      "logic" => "all",
      "rules" => [
        rule(
          "nest_courage_gate",
          "teo",
          "something_here.courage.value",
          "greater_than_or_equal",
          "3"
        )
      ]
    }

    fruit_condition = %{
      "logic" => "all",
      "rules" => [
        rule("nest_fruit_gate", "inv.reverie", "warm_fruit", "greater_than", "0")
      ]
    }

    warning =
      create_dialogue!(
        flow,
        320.0,
        300.0,
        nox,
        "A Feltshade is feeding on trapped light. We can drive it off, starve it, or leave the seed where it is."
      )

    resolve =
      create_dialogue!(
        flow,
        620.0,
        300.0,
        nox,
        "Choose fast. Rush it, bait it with fruit, or leave the seed where it is.",
        [
          response("drive_it_off", "Rush it while it turns.",
            condition: courage_condition,
            instruction_assignments: [
              assignment("nest_drive_corruption", "state", "local_corruption", "subtract", "1"),
              assignment("nest_drive_seed", "inv.reverie", "light_seeds", "add", "1"),
              assignment(
                "nest_drive_courage",
                "teo",
                "something_here.courage.value",
                "add",
                "1"
              )
            ]
          ),
          response("bait_it", "Throw warm fruit and pull it away.",
            condition: fruit_condition,
            instruction_assignments: [
              assignment("nest_bait_spend_fruit", "inv.reverie", "warm_fruit", "subtract", "1"),
              assignment("nest_bait_seed", "inv.reverie", "light_seeds", "add", "1"),
              assignment(
                "nest_bait_curiosity",
                "teo",
                "something_here.curiosity.value",
                "add",
                "1"
              )
            ]
          ),
          response("leave_it", "Back away and leave the light trapped.",
            instruction_assignments: [
              assignment("nest_leave_corruption", "state", "local_corruption", "add", "1"),
              assignment("nest_leave_intensity", "force.unraveling", "intensity", "add", "1")
            ]
          )
        ]
      )

    nest_cleared =
      create_dialogue!(
        flow,
        940.0,
        200.0,
        nox,
        "Good. Take the seed before the dark learns the shape of your hands."
      )

    nest_retreat =
      create_dialogue!(
        flow,
        940.0,
        420.0,
        teo,
        "We leave it. Nox says nothing, which lands harder than a lecture."
      )

    connect!(flow, canvas.entry, warning, "output")
    connect!(flow, warning, resolve)
    connect!(flow, resolve, nest_cleared, "drive_it_off")
    connect!(flow, resolve, nest_cleared, "bait_it")
    connect!(flow, resolve, nest_retreat, "leave_it")
    connect!(flow, nest_cleared, canvas.exit)
    connect!(flow, nest_retreat, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {warning, {320, 300}},
      {resolve, {620, 300}},
      {nest_cleared, {940, 200}},
      {nest_retreat, {940, 420}},
      {canvas.exit, {1220, 300}}
    ])
  end

  defp sync_soft_bridge(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Resolve the soft bridge")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    situation =
      create_dialogue!(
        flow,
        320.0,
        300.0,
        nox,
        "The bridge is more memory than road. One wrong step and the cloud matter will pull apart."
      )

    options =
      create_condition!(
        flow,
        620.0,
        300.0,
        %{
          "logic" => "any",
          "rules" => [
            rule("case_patch", "inv.reverie", "cloud_patches", "greater_than", "0", "Use Patch"),
            rule(
              "case_nox",
              "guardian.nox",
              "form_energy",
              "greater_than_or_equal",
              "2",
              "Force Form"
            )
          ]
        },
        true
      )

    repair =
      create_instruction!(flow, 940.0, 180.0, "Use a cloud patch to steady the crossing", [
        assignment("bridge_spend_patch", "inv.reverie", "cloud_patches", "subtract", "1"),
        assignment(
          "bridge_teo_tenacity",
          "teo",
          "something_here.tenacity.value",
          "add",
          "1"
        )
      ])

    repair_line =
      create_dialogue!(
        flow,
        1200.0,
        180.0,
        nox,
        "That will hold. Walk lightly and don't look down."
      )

    improvise =
      create_instruction!(flow, 940.0, 340.0, "Nox forces a form across the gap", [
        assignment("bridge_nox_energy", "guardian.nox", "form_energy", "subtract", "2"),
        assignment("bridge_nox_grapple", "guardian.nox", "current_mode", "set", "grapple"),
        assignment(
          "bridge_nox_grapple_unlocked",
          "guardian.nox",
          "forms.grapple.unlocked",
          "set_true"
        ),
        assignment("bridge_nox_injured", "guardian.nox", "injured", "set_true"),
        assignment("bridge_state_nox_injured", "state", "nox_injured", "set_true"),
        assignment(
          "bridge_teo_courage",
          "teo",
          "something_here.courage.value",
          "add",
          "1"
        )
      ])

    improvise_line =
      create_dialogue!(
        flow,
        1200.0,
        340.0,
        nox,
        "I can carry the shape. I cannot promise I'll like the price."
      )

    turn_back =
      create_dialogue!(
        flow,
        940.0,
        500.0,
        teo,
        "Then we turn back. I won't gamble both of us on one bad step."
      )

    connect!(flow, canvas.entry, situation, "output")
    connect!(flow, situation, options)
    connect!(flow, options, repair, "case_patch")
    connect!(flow, options, improvise, "case_nox")
    connect!(flow, options, turn_back, "default")
    connect!(flow, repair, repair_line)
    connect!(flow, improvise, improvise_line)
    connect!(flow, repair_line, canvas.exit)
    connect!(flow, improvise_line, canvas.exit)
    connect!(flow, turn_back, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {situation, {320, 300}},
      {options, {620, 300}},
      {repair, {940, 180}},
      {repair_line, {1200, 180}},
      {improvise, {940, 340}},
      {improvise_line, {1200, 340}},
      {turn_back, {940, 500}},
      {canvas.exit, {1480, 300}}
    ])
  end

  defp sync_split_lantern(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Inspect the split lantern")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    lantern_find =
      create_dialogue!(
        flow,
        320.0,
        300.0,
        nox,
        "Cracked shell, live core. Even now the lantern is trying to stitch itself back together."
      )

    collect =
      create_instruction!(flow, 620.0, 300.0, "Collect the surviving light seed", [
        assignment("split_lantern_seed", "inv.reverie", "light_seeds", "add", "1")
      ])

    mother_echo =
      create_condition!(flow, 920.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          rule("split_trace_check", "state", "mother_trace", "greater_than_or_equal", "1")
        ]
      })

    echo_line =
      create_dialogue!(
        flow,
        1220.0,
        220.0,
        teo,
        "That warmth... it feels like her. Or close enough to hurt."
      )

    no_echo =
      create_dialogue!(
        flow,
        1220.0,
        380.0,
        nox,
        "Broken or not, it still remembers how to hold a seam."
      )

    connect!(flow, canvas.entry, lantern_find, "output")
    connect!(flow, lantern_find, collect)
    connect!(flow, collect, mother_echo)
    connect!(flow, mother_echo, echo_line, "true")
    connect!(flow, mother_echo, no_echo, "false")
    connect!(flow, echo_line, canvas.exit)
    connect!(flow, no_echo, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {lantern_find, {320, 300}},
      {collect, {620, 300}},
      {mother_echo, {920, 300}},
      {echo_line, {1220, 220}},
      {no_echo, {1220, 380}},
      {canvas.exit, {1480, 300}}
    ])
  end

  defp sync_root_gate(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Resolve the root gate")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id

    roots_block =
      create_dialogue!(
        flow,
        320.0,
        300.0,
        nox,
        "Black roots have laced themselves across the path to the clearing. They twitch when we get close."
      )

    resolve =
      create_condition!(
        flow,
        640.0,
        300.0,
        %{
          "logic" => "any",
          "rules" => [
            rule(
              "case_light_seeds",
              "inv.reverie",
              "light_seeds",
              "greater_than_or_equal",
              "2",
              "Cleanse With Seeds"
            ),
            rule(
              "case_force_gap",
              "guardian.nox",
              "form_energy",
              "greater_than_or_equal",
              "3",
              "Force A Gap"
            )
          ]
        },
        true
      )

    cleanse_gate =
      create_instruction!(flow, 960.0, 180.0, "Spend light seeds to burn a safe opening", [
        assignment("root_gate_spend_seeds", "inv.reverie", "light_seeds", "subtract", "2"),
        assignment("root_gate_open", "state", "path_open", "set_true"),
        assignment("root_gate_cleanse", "state", "local_corruption", "subtract", "1")
      ])

    cleanse_line =
      create_dialogue!(
        flow,
        1260.0,
        180.0,
        nox,
        "The roots hate clean light. Move before they remember us."
      )

    force_gap =
      create_instruction!(flow, 960.0, 340.0, "Nox tears the roots apart by force", [
        assignment("root_gate_nox_energy", "guardian.nox", "form_energy", "subtract", "3"),
        assignment("root_gate_nox_injured", "guardian.nox", "injured", "set_true"),
        assignment("root_gate_state_nox_injured", "state", "nox_injured", "set_true"),
        assignment("root_gate_open_forced", "state", "path_open", "set_true"),
        assignment(
          "root_gate_tenacity",
          "teo",
          "something_here.tenacity.value",
          "add",
          "1"
        )
      ])

    force_line =
      create_dialogue!(
        flow,
        1260.0,
        340.0,
        teo,
        "The gap opens, but the roots take their price from Nox before they let go."
      )

    blocked_gate =
      create_dialogue!(
        flow,
        960.0,
        500.0,
        nox,
        "Not enough fuel. Not enough clean light. The clearing stays shut."
      )

    connect!(flow, canvas.entry, roots_block, "output")
    connect!(flow, roots_block, resolve)
    connect!(flow, resolve, cleanse_gate, "case_light_seeds")
    connect!(flow, resolve, force_gap, "case_force_gap")
    connect!(flow, resolve, blocked_gate, "default")
    connect!(flow, cleanse_gate, cleanse_line)
    connect!(flow, force_gap, force_line)
    connect!(flow, cleanse_line, canvas.exit)
    connect!(flow, force_line, canvas.exit)
    connect!(flow, blocked_gate, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {roots_block, {320, 300}},
      {resolve, {640, 300}},
      {cleanse_gate, {960, 180}},
      {cleanse_line, {1260, 180}},
      {force_gap, {960, 340}},
      {force_line, {1260, 340}},
      {blocked_gate, {960, 500}},
      {canvas.exit, {1540, 300}}
    ])
  end

  defp sync_meeting(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "End the demo at Lantern Clearing")
    teo = sheets["teo"].id
    nox = sheets["guardian.nox"].id
    luma = sheets["guardian.luma"].id
    mina = sheets["npc.mina"].id

    enter_clearing =
      create_instruction!(flow, 260.0, 300.0, "Mark the clearing as the current area", [
        assignment("meeting_area_clearing", "state", "area_current", "set", "clearing")
      ])

    luma_presence =
      create_dialogue!(
        flow,
        520.0,
        300.0,
        nox,
        "The clearing is warmer than the rest of the sky. Something elemental is already listening."
      )

    mina_reveals =
      create_dialogue!(
        flow,
        780.0,
        300.0,
        mina,
        "Stop there. One more step and the lantern ring closes without you."
      )

    suspicion_check =
      create_condition!(flow, 1040.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          rule("meeting_low_trace", "force.unraveling", "trace_on_teo", "less_than_or_equal", "1")
        ]
      })

    mina_hesitates =
      create_dialogue!(
        flow,
        1300.0,
        220.0,
        luma,
        "Wait. That thread beside him is familiar."
      )

    mina_hard =
      create_dialogue!(
        flow,
        1300.0,
        420.0,
        mina,
        "Luma says the dark has marked you. That makes you dangerous."
      )

    nox_reacts =
      create_dialogue!(
        flow,
        1560.0,
        300.0,
        nox,
        "Luma. You're alive."
      )

    keeper_taken =
      create_instruction!(
        flow,
        1820.0,
        300.0,
        "The Unraveling strikes while the party is distracted",
        [
          assignment("meeting_keeper_afraid", "npc.lantern-keeper", "afraid", "set_true"),
          assignment("meeting_force_intensity", "force.unraveling", "intensity", "add", "1"),
          assignment("meeting_active_knot", "force.unraveling", "active_knot_count", "add", "1")
        ]
      )

    keeper_crisis =
      create_dialogue!(
        flow,
        2080.0,
        300.0,
        mina,
        "Keeper! The roots took him!"
      )

    cooperation_check =
      create_condition!(flow, 2340.0, 300.0, %{
        "logic" => "any",
        "rules" => [
          rule("meeting_has_seeds", "inv.reverie", "light_seeds", "greater_than_or_equal", "2"),
          rule("meeting_nox_energy", "guardian.nox", "form_energy", "greater_than_or_equal", "2"),
          rule(
            "meeting_teo_courage",
            "teo",
            "something_here.courage.value",
            "greater_than_or_equal",
            "3"
          )
        ]
      })

    save_keeper =
      create_dialogue!(
        flow,
        2600.0,
        220.0,
        nox,
        "There. Shape and force together. The knot broke clean."
      )

    hard_win =
      create_dialogue!(
        flow,
        2600.0,
        420.0,
        mina,
        "We broke the knot, but not before it thinned the keeper's light."
      )

    reward =
      create_instruction!(flow, 2860.0, 220.0, "Best outcome for the clearing", [
        assignment("meeting_keeper_rescued", "npc.lantern-keeper", "rescued", "set_true"),
        assignment("meeting_keeper_reward", "npc.lantern-keeper", "reward_given", "set_true"),
        assignment("meeting_keeper_afraid_false", "npc.lantern-keeper", "afraid", "set_false"),
        assignment("meeting_keeper_saved_state", "state", "lantern_keeper_saved", "set_true"),
        assignment("meeting_mina_party", "state", "mina_in_party", "set_true"),
        assignment("meeting_luma_unlocked", "state", "luma_unlocked", "set_true"),
        assignment("meeting_luma_party", "guardian.luma", "in_party", "set_true"),
        assignment("meeting_luma_light", "guardian.luma", "current_element", "set", "light"),
        assignment(
          "meeting_luma_light_unlocked",
          "guardian.luma",
          "elements.light.unlocked",
          "set_true"
        ),
        assignment("meeting_accepts_reverie", "teo", "accepts_reverie", "set_true"),
        assignment("meeting_mina_bond_teo", "npc.mina", "bonds.teo.intensity", "add", "1"),
        assignment("meeting_mina_bond_nox", "npc.mina", "bonds.nox.intensity", "add", "1"),
        assignment("meeting_mina_bond_luma", "npc.mina", "bonds.luma.intensity", "add", "1")
      ])

    lesser_reward =
      create_instruction!(flow, 2860.0, 420.0, "The clearing is saved, but at a cost", [
        assignment("meeting_keeper_rescued_hard", "npc.lantern-keeper", "rescued", "set_true"),
        assignment("meeting_mina_party_hard", "state", "mina_in_party", "set_true"),
        assignment("meeting_luma_unlocked_hard", "state", "luma_unlocked", "set_true"),
        assignment("meeting_luma_party_hard", "guardian.luma", "in_party", "set_true"),
        assignment("meeting_luma_light_hard", "guardian.luma", "current_element", "set", "light"),
        assignment(
          "meeting_luma_light_unlocked_hard",
          "guardian.luma",
          "elements.light.unlocked",
          "set_true"
        ),
        assignment("meeting_accepts_reverie_hard", "teo", "accepts_reverie", "set_true"),
        assignment(
          "meeting_mina_bond_teo_hard",
          "npc.mina",
          "bonds.teo.intensity",
          "add",
          "1"
        ),
        assignment(
          "meeting_mina_bond_nox_hard",
          "npc.mina",
          "bonds.nox.intensity",
          "add",
          "1"
        ),
        assignment(
          "meeting_mina_bond_luma_hard",
          "npc.mina",
          "bonds.luma.intensity",
          "add",
          "1"
        )
      ])

    horizon =
      create_dialogue!(
        flow,
        3120.0,
        300.0,
        mina,
        "That was one island. Look up. The others are already starting to fray."
      )

    mother_echo =
      create_condition!(flow, 3380.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          rule("meeting_mother_trace", "state", "mother_trace", "greater_than_or_equal", "2")
        ]
      })

    echo_song =
      create_dialogue!(
        flow,
        3640.0,
        220.0,
        teo,
        "On the wind above the clearing, I hear a melody my mother used to hum."
      )

    next_road =
      create_dialogue!(
        flow,
        3640.0,
        420.0,
        nox,
        "If the Unraveling found this island, it already knows the way to the next one."
      )

    mark_complete =
      create_instruction!(flow, 3900.0, 300.0, "Close the demo slice", [
        assignment("meeting_demo_complete", "state", "demo_complete", "set_true")
      ])

    connect!(flow, canvas.entry, enter_clearing, "output")
    connect!(flow, enter_clearing, luma_presence)
    connect!(flow, luma_presence, mina_reveals)
    connect!(flow, mina_reveals, suspicion_check)
    connect!(flow, suspicion_check, mina_hesitates, "true")
    connect!(flow, suspicion_check, mina_hard, "false")
    connect!(flow, mina_hesitates, nox_reacts)
    connect!(flow, mina_hard, nox_reacts)
    connect!(flow, nox_reacts, keeper_taken)
    connect!(flow, keeper_taken, keeper_crisis)
    connect!(flow, keeper_crisis, cooperation_check)
    connect!(flow, cooperation_check, save_keeper, "true")
    connect!(flow, cooperation_check, hard_win, "false")
    connect!(flow, save_keeper, reward)
    connect!(flow, hard_win, lesser_reward)
    connect!(flow, reward, horizon)
    connect!(flow, lesser_reward, horizon)
    connect!(flow, horizon, mother_echo)
    connect!(flow, mother_echo, echo_song, "true")
    connect!(flow, mother_echo, next_road, "false")
    connect!(flow, echo_song, mark_complete)
    connect!(flow, next_road, mark_complete)
    connect!(flow, mark_complete, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {enter_clearing, {260, 300}},
      {luma_presence, {520, 300}},
      {mina_reveals, {780, 300}},
      {suspicion_check, {1040, 300}},
      {mina_hesitates, {1300, 220}},
      {mina_hard, {1300, 420}},
      {nox_reacts, {1560, 300}},
      {keeper_taken, {1820, 300}},
      {keeper_crisis, {2080, 300}},
      {cooperation_check, {2340, 300}},
      {save_keeper, {2600, 220}},
      {hard_win, {2600, 420}},
      {reward, {2860, 220}},
      {lesser_reward, {2860, 420}},
      {horizon, {3120, 300}},
      {mother_echo, {3380, 300}},
      {echo_song, {3640, 220}},
      {next_road, {3640, 420}},
      {mark_complete, {3900, 300}},
      {canvas.exit, {4160, 300}}
    ])
  end

  defp sync_ambient_threshold(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Threshold ambient complete")
    nox = sheets["guardian.nox"].id

    line =
      create_dialogue!(
        flow,
        360.0,
        300.0,
        nox,
        "Keep your eyes ahead. This place likes answers less than falls."
      )

    connect!(flow, canvas.entry, line, "output")
    connect!(flow, line, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {line, {360, 300}},
      {canvas.exit, {620, 300}}
    ])
  end

  defp sync_ambient_refuge(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Refuge ambient complete")
    nox = sheets["guardian.nox"].id

    injury_check =
      create_condition!(flow, 360.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          boolean_rule("refuge_nox_injured_check", "guardian.nox", "injured", "is_true")
        ]
      })

    hurt_line =
      create_dialogue!(
        flow,
        660.0,
        220.0,
        nox,
        "I'm functional. That is all you need to know."
      )

    steady_line =
      create_dialogue!(
        flow,
        660.0,
        420.0,
        nox,
        "For a house stitched out of scraps, this one still remembers calm."
      )

    connect!(flow, canvas.entry, injury_check, "output")
    connect!(flow, injury_check, hurt_line, "true")
    connect!(flow, injury_check, steady_line, "false")
    connect!(flow, hurt_line, canvas.exit)
    connect!(flow, steady_line, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {injury_check, {360, 300}},
      {hurt_line, {660, 220}},
      {steady_line, {660, 420}},
      {canvas.exit, {940, 300}}
    ])
  end

  defp sync_ambient_clearing(project, flow, sheets) do
    canvas = reset_flow_canvas(project, flow, "Clearing ambient complete")
    luma = sheets["guardian.luma"].id
    mina = sheets["npc.mina"].id

    party_check =
      create_condition!(flow, 360.0, 300.0, %{
        "logic" => "all",
        "rules" => [
          boolean_rule("clearing_luma_joined", "guardian.luma", "in_party", "is_true")
        ]
      })

    joined_line =
      create_dialogue!(
        flow,
        660.0,
        220.0,
        luma,
        "I can read the next islands now. None of them are sleeping well."
      )

    presence_line =
      create_dialogue!(
        flow,
        660.0,
        420.0,
        mina,
        "The lantern ring keeps warming and cooling. Something elemental is still waiting for its name."
      )

    connect!(flow, canvas.entry, party_check, "output")
    connect!(flow, party_check, joined_line, "true")
    connect!(flow, party_check, presence_line, "false")
    connect!(flow, joined_line, canvas.exit)
    connect!(flow, presence_line, canvas.exit)

    apply_positions!(flow, [
      {canvas.entry, {100, 300}},
      {party_check, {360, 300}},
      {joined_line, {660, 220}},
      {presence_line, {660, 420}},
      {canvas.exit, {940, 300}}
    ])
  end

  defp flow_specs do
    [
      %{
        name: "Prologue: Wake and Flee",
        shortcut: "prologue.wake-and-flee",
        parent_shortcut: nil,
        position: 0,
        description:
          "Opening flow for the broken threshold. Teo wakes, meets Nox under pressure, survives the first corrupted spirits, and reaches Mender's Isle."
      },
      %{
        name: "Refuge: Promise of Thread",
        shortcut: "refuge.promise-of-thread",
        parent_shortcut: nil,
        position: 1,
        description:
          "Refuge flow inside the House of Thread. It stabilizes Nox, keeps Teo's mother as the emotional engine, and opens the road toward the clearing."
      },
      %{
        name: "Path: Roadside Events",
        shortcut: "path.roadside-events",
        parent_shortcut: nil,
        position: 2,
        description:
          "Wrapper flow for the Veiled Path. The road itself is split into smaller event flows nested under this parent."
      },
      %{
        name: "Event: Shade Nest",
        shortcut: "event.shade-nest",
        parent_shortcut: "path.roadside-events",
        position: 0,
        description:
          "Short reactive encounter on the Veiled Path where Teo and Nox decide how to deal with a Feltshade feeding on trapped light."
      },
      %{
        name: "Event: Soft Bridge",
        shortcut: "event.soft-bridge",
        parent_shortcut: "path.roadside-events",
        position: 1,
        description:
          "Traversal obstacle on the Veiled Path, resolved with cloud patches or by spending Nox's energy."
      },
      %{
        name: "Event: Split Lantern",
        shortcut: "event.split-lantern",
        parent_shortcut: "path.roadside-events",
        position: 2,
        description:
          "Small collectible encounter around a cracked lantern that still holds one surviving light seed."
      },
      %{
        name: "Event: Root Gate",
        shortcut: "event.root-gate",
        parent_shortcut: "path.roadside-events",
        position: 3,
        description:
          "Route gate event for the clearing exit. It pays off light seeds or Nox form energy and decides whether the path truly opens."
      },
      %{
        name: "Meeting: Lantern Clearing",
        shortcut: "meeting.lantern-clearing",
        parent_shortcut: nil,
        position: 3,
        description:
          "Demo climax at Lantern Clearing. Mina and Luma enter, the keeper is threatened, and the party is formed for the wider adventure."
      },
      %{
        name: "Ambient: Threshold Nox",
        shortcut: "ambient.threshold-nox",
        parent_shortcut: nil,
        position: 4,
        description: "Short one-beat ambient line for the Broken Threshold scene."
      },
      %{
        name: "Ambient: Refuge Nox",
        shortcut: "ambient.refuge-nox",
        parent_shortcut: nil,
        position: 5,
        description:
          "Conditional ambient line for the House of Thread based on Nox's injury state."
      },
      %{
        name: "Ambient: Clearing Luma",
        shortcut: "ambient.clearing-luma",
        parent_shortcut: nil,
        position: 6,
        description:
          "Ambient beat for Lantern Clearing before or after Luma formally joins the party."
      }
    ]
  end
end

Storyarn.Scripts.SeedSkyOfReverieFlows.run()
