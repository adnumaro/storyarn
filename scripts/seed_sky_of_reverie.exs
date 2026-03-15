Mix.Task.run("app.start")

defmodule Storyarn.Scripts.SeedSkyOfReverie do
  import Ecto.Query, warn: false
  require Logger

  alias Storyarn.Accounts.{Scope, User}
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Workspaces.Workspace

  @project_name "Sky of Reverie"
  @project_slug "sky-of-reverie"
  @project_description """
  Top-down narrative adventure demo starring Storyarn's mascots Nox and Luma.
  The vertical slice focuses on sheets-first worldbuilding, shared state, and table-driven character design.
  """

  def run do
    Logger.configure(level: :warning)

    user = fetch_user!()
    workspace = fetch_workspace!(user)
    scope = Scope.for_user(user)
    project = ensure_project(scope, workspace)
    sheets_by_shortcut = seed_sheet_tree(project)
    seed_sheet_content(project, sheets_by_shortcut)

    IO.puts("")
    IO.puts("Seed complete")
    IO.puts("Project: #{project.name} (##{project.id})")
    IO.puts("Workspace: #{workspace.slug}")
    IO.puts("Sheets: #{map_size(sheets_by_shortcut)}")
  end

  defp fetch_user! do
    case System.get_env("SKY_USER_EMAIL") do
      nil ->
        Repo.one!(
          from u in User,
            where: not like(u.email, "test-%@example.com"),
            order_by: [asc: u.id],
            limit: 1
        )

      email ->
        Repo.get_by!(User, email: email)
    end
  end

  defp fetch_workspace!(%User{} = user) do
    case System.get_env("SKY_WORKSPACE_SLUG") do
      nil ->
        Repo.one!(
          from w in Workspace,
            where: w.owner_id == ^user.id,
            order_by: [asc: w.id],
            limit: 1
        )

      slug ->
        Repo.get_by!(Workspace, slug: slug)
    end
  end

  defp ensure_project(scope, %Workspace{} = workspace) do
    attrs = %{
      name: @project_name,
      description: String.trim(@project_description),
      settings: %{
        "theme" => %{
          "primary" => "#89a8a5",
          "accent" => "#d7b36a"
        }
      },
      workspace_id: workspace.id
    }

    case Projects.get_project_by_slugs(scope, workspace.slug, @project_slug) do
      {:ok, project, _membership} ->
        {:ok, project} =
          Projects.update_project(project, %{
            name: attrs.name,
            description: attrs.description,
            settings: attrs.settings
          })

        IO.puts("Using existing project #{@project_slug} (##{project.id})")
        project

      {:error, :not_found} ->
        {:ok, project} = Projects.create_project(scope, attrs)
        IO.puts("Created project #{@project_slug} (##{project.id})")
        project
    end
  end

  defp seed_sheet_tree(%Project{} = project) do
    sheet_specs()
    |> Enum.reduce(%{}, fn spec, acc ->
      parent_id =
        case spec.parent_shortcut do
          nil -> nil
          parent_shortcut -> Map.fetch!(acc, parent_shortcut).id
        end

      sheet = ensure_sheet(project, spec, parent_id)
      Map.put(acc, spec.shortcut, sheet)
    end)
  end

  defp seed_sheet_content(%Project{} = project, sheets_by_shortcut) do
    Enum.each(sheet_specs(), fn spec ->
      sheet = Map.fetch!(sheets_by_shortcut, spec.shortcut)

      ensure_blocks(
        project,
        sheet,
        Map.get(sheet_block_specs(), spec.shortcut, []),
        sheets_by_shortcut
      )
    end)
  end

  defp ensure_sheet(%Project{} = project, spec, parent_id) do
    attrs = %{
      name: spec.name,
      shortcut: spec.shortcut,
      description: spec.description,
      color: spec.color,
      parent_id: parent_id,
      position: spec.position
    }

    case Sheets.get_sheet_by_shortcut(project.id, spec.shortcut) do
      nil ->
        {:ok, sheet} = Sheets.create_sheet(project, attrs)
        IO.puts("  + sheet #{spec.shortcut}")
        sheet

      %Sheet{} = sheet ->
        {:ok, updated_sheet} = Sheets.update_sheet(sheet, attrs)
        updated_sheet
    end
  end

  defp ensure_blocks(_project, _sheet, [], _sheets_by_shortcut), do: :ok

  defp ensure_blocks(project, %Sheet{} = sheet, specs, sheets_by_shortcut) do
    existing_blocks = list_sheet_blocks(sheet)

    Enum.reduce(specs, existing_blocks, fn spec, blocks ->
      ensured_block = ensure_block(project, sheet, blocks, spec, sheets_by_shortcut)
      upsert_block_in_cache(blocks, ensured_block)
    end)

    :ok
  end

  defp ensure_block(_project, sheet, blocks, %{type: "table"} = spec, sheets_by_shortcut) do
    block =
      blocks
      |> find_block(spec.label, "table")
      |> case do
        nil ->
          attrs = build_block_attrs(spec, sheets_by_shortcut)
          {:ok, block} = Sheets.create_block(sheet, attrs)
          Repo.preload(block, [:table_columns, :table_rows])

        %Block{} = block ->
          {:ok, block} = Sheets.update_block(block, build_block_attrs(spec, sheets_by_shortcut))
          Repo.preload(block, [:table_columns, :table_rows])
      end

    ensure_table_structure(block, spec.columns, spec.rows)
  end

  defp ensure_block(_project, sheet, blocks, spec, sheets_by_shortcut) do
    attrs = build_block_attrs(spec, sheets_by_shortcut)

    case find_block(blocks, spec.label, spec.type) do
      nil ->
        {:ok, block} = Sheets.create_block(sheet, attrs)
        block

      %Block{} = block ->
        {:ok, block} = Sheets.update_block(block, attrs)
        block
    end
  end

  defp ensure_table_structure(%Block{} = block, column_specs, row_specs) do
    ordered_columns = ensure_table_columns(block, column_specs)
    _ordered_rows = ensure_table_rows(block, row_specs, ordered_columns)

    block.id
    |> Sheets.get_block!()
    |> Repo.preload([:table_columns, :table_rows])
  end

  defp ensure_table_columns(%Block{} = block, column_specs) do
    current_columns =
      block.id
      |> Sheets.list_table_columns()
      |> Enum.sort_by(& &1.position)

    current_by_slug = Map.new(current_columns, &{&1.slug, &1})

    {ordered_ids, _used_ids} =
      Enum.map_reduce(column_specs, MapSet.new(), fn spec, used_ids ->
        slug = NameNormalizer.variablify(spec.name)

        attrs = %{
          name: spec.name,
          type: spec.type,
          is_constant: Map.get(spec, :is_constant, false),
          required: Map.get(spec, :required, false),
          config: Map.get(spec, :config, %{})
        }

        column =
          case Map.get(current_by_slug, slug) || next_unused(current_columns, used_ids) do
            nil ->
              {:ok, column} = Sheets.create_table_column(block, attrs)
              column

            %TableColumn{} = column ->
              {:ok, column} = Sheets.update_table_column(column, attrs)
              column
          end

        {column.id, MapSet.put(used_ids, column.id)}
      end)

    extra_ids =
      current_columns
      |> Enum.reject(&(&1.id in ordered_ids))
      |> Enum.map(& &1.id)

    ordered_ids = ordered_ids ++ extra_ids

    if length(ordered_ids) > 1 do
      {:ok, _columns} = Sheets.reorder_table_columns(block.id, ordered_ids)
    end

    Sheets.list_table_columns(block.id)
  end

  defp ensure_table_rows(%Block{} = block, row_specs, columns) do
    current_rows =
      block.id
      |> Sheets.list_table_rows()
      |> Enum.sort_by(& &1.position)

    current_by_slug = Map.new(current_rows, &{&1.slug, &1})

    {ordered_ids, _used_ids} =
      Enum.map_reduce(row_specs, MapSet.new(), fn spec, used_ids ->
        slug = NameNormalizer.variablify(spec.name)
        cell_values = build_row_cells(spec.cells, columns)

        row =
          case Map.get(current_by_slug, slug) || next_unused(current_rows, used_ids) do
            nil ->
              {:ok, row} = Sheets.create_table_row(block, %{name: spec.name, cells: cell_values})
              row

            %TableRow{} = row ->
              {:ok, row} = Sheets.update_table_row(row, %{name: spec.name})
              row
          end

        refreshed_row = Sheets.get_table_row!(row.id)
        {:ok, _row} = Sheets.update_table_cells(refreshed_row, cell_values)

        {row.id, MapSet.put(used_ids, row.id)}
      end)

    extra_ids =
      current_rows
      |> Enum.reject(&(&1.id in ordered_ids))
      |> Enum.map(& &1.id)

    ordered_ids = ordered_ids ++ extra_ids

    if length(ordered_ids) > 1 do
      {:ok, _rows} = Sheets.reorder_table_rows(block.id, ordered_ids)
    end

    Sheets.list_table_rows(block.id)
  end

  defp build_row_cells(cells, columns) do
    Enum.reduce(columns, %{}, fn column, acc ->
      atom_key =
        Enum.find(Map.keys(cells), fn
          key when is_atom(key) -> Atom.to_string(key) == column.slug
          _key -> false
        end)

      value =
        cond do
          Map.has_key?(cells, column.slug) -> Map.get(cells, column.slug)
          atom_key != nil -> Map.get(cells, atom_key)
          true -> nil
        end

      Map.put(acc, column.slug, value)
    end)
  end

  defp list_sheet_blocks(%Sheet{} = sheet) do
    sheet.id
    |> Sheets.list_blocks()
    |> Repo.preload([:table_columns, :table_rows])
  end

  defp find_block(blocks, label, type) do
    Enum.find(blocks, fn block ->
      block.type == type and block_label(block) == label
    end)
  end

  defp block_label(%Block{config: config}), do: Map.get(config || %{}, "label")

  defp upsert_block_in_cache(blocks, %Block{} = block) do
    filtered = Enum.reject(blocks, &(&1.id == block.id))
    [block | filtered]
  end

  defp next_unused(items, used_ids) do
    Enum.find(items, fn item -> not MapSet.member?(used_ids, item.id) end)
  end

  defp build_block_attrs(spec, sheets_by_shortcut) do
    %{
      type: spec.type,
      config: build_block_config(spec),
      value: build_block_value(spec, sheets_by_shortcut),
      is_constant: Map.get(spec, :constant, false),
      required: Map.get(spec, :required, false),
      scope: Map.get(spec, :scope, "self")
    }
  end

  defp build_block_config(%{type: "text", label: label} = spec) do
    %{
      "label" => label,
      "placeholder" => Map.get(spec, :placeholder, "")
    }
  end

  defp build_block_config(%{type: "number", label: label} = spec) do
    %{
      "label" => label,
      "placeholder" => Map.get(spec, :placeholder, "0"),
      "min" => Map.get(spec, :min),
      "max" => Map.get(spec, :max),
      "step" => Map.get(spec, :step)
    }
  end

  defp build_block_config(%{type: "boolean", label: label} = spec) do
    %{
      "label" => label,
      "mode" => Map.get(spec, :mode, "two_state")
    }
  end

  defp build_block_config(%{type: "select", label: label, options: options} = spec) do
    %{
      "label" => label,
      "placeholder" => Map.get(spec, :placeholder, "Select..."),
      "options" => option_maps(options)
    }
  end

  defp build_block_config(%{type: "multi_select", label: label, options: options} = spec) do
    %{
      "label" => label,
      "placeholder" => Map.get(spec, :placeholder, "Select..."),
      "options" => option_maps(options)
    }
  end

  defp build_block_config(%{type: "reference", label: label}) do
    %{
      "label" => label,
      "allowed_types" => ["sheet"]
    }
  end

  defp build_block_config(%{type: "table", label: label} = spec) do
    %{
      "label" => label,
      "collapsed" => Map.get(spec, :collapsed, false)
    }
  end

  defp build_block_config(%{label: label}) do
    %{"label" => label}
  end

  defp build_block_value(%{type: "text", content: content}, _sheets_by_shortcut),
    do: %{"content" => String.trim(content)}

  defp build_block_value(%{type: "number", value: value}, _sheets_by_shortcut),
    do: %{"content" => value}

  defp build_block_value(%{type: "boolean", value: value}, _sheets_by_shortcut),
    do: %{"content" => value}

  defp build_block_value(%{type: "select", value: value}, _sheets_by_shortcut),
    do: %{"content" => value}

  defp build_block_value(%{type: "multi_select", value: value}, _sheets_by_shortcut),
    do: %{"content" => value}

  defp build_block_value(%{type: "reference", target_shortcut: shortcut}, sheets_by_shortcut) do
    target = Map.fetch!(sheets_by_shortcut, shortcut)
    %{"target_type" => "sheet", "target_id" => target.id}
  end

  defp build_block_value(%{type: "table"}, _sheets_by_shortcut), do: %{}
  defp build_block_value(_spec, _sheets_by_shortcut), do: %{"content" => nil}

  defp option_maps(options) do
    Enum.map(options, fn
      %{key: key, value: value} ->
        %{"key" => key, "value" => value}

      option when is_binary(option) ->
        %{"key" => option, "value" => humanize_key(option)}
    end)
  end

  defp humanize_key(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp sheet_specs do
    [
      %{
        name: "Systems",
        shortcut: "group.systems",
        description: "Shared state, inventory, and table-driven demo scaffolding.",
        color: "#73818c",
        position: 0,
        parent_shortcut: nil
      },
      %{
        name: "Cast",
        shortcut: "group.cast",
        description: "Playable leads, mascots, and the supporting world cast.",
        color: "#d2ab64",
        position: 1,
        parent_shortcut: nil
      },
      %{
        name: "Hostiles",
        shortcut: "group.hostiles",
        description: "The Unraveling and the corrupted entities orbiting it.",
        color: "#6d4450",
        position: 2,
        parent_shortcut: nil
      },
      %{
        name: "Locations",
        shortcut: "group.locations",
        description: "Reference sheets for the demo's top-down playable spaces.",
        color: "#7aa097",
        position: 3,
        parent_shortcut: nil
      },
      %{
        name: "Demo State",
        shortcut: "game.demo",
        description: "Global flags and progress variables shared across the demo.",
        color: "#73818c",
        position: 0,
        parent_shortcut: "group.systems"
      },
      %{
        name: "Reverie Inventory",
        shortcut: "inv.reverie",
        description: "Small resource layer for healing, cleansing, and route repair.",
        color: "#8da58f",
        position: 1,
        parent_shortcut: "group.systems"
      },
      %{
        name: "Teo",
        shortcut: "pc.teo",
        description: "Main playable child lead. Stubborn, frightened, and emotionally direct.",
        color: "#c89a63",
        position: 0,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Mina",
        shortcut: "npc.mina",
        description: "Second lead. Controlled, exact, and already moving with purpose.",
        color: "#9ba7c4",
        position: 1,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Nox",
        shortcut: "guardian.nox",
        description: "Guardian of form. Turns need into tools, defenses, and traversal shapes.",
        color: "#404956",
        position: 2,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Luma",
        shortcut: "guardian.luma",
        description: "Guardian of essence. Channels elemental states and purification.",
        color: "#d6dfe7",
        position: 3,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Lantern Keeper",
        shortcut: "npc.lantern-keeper",
        description: "Fragile spirit objective at the demo's ending.",
        color: "#d3c37a",
        position: 4,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Elder Iri",
        shortcut: "npc.iri",
        description: "Absent refuge mender whose care still shapes the house and isle.",
        color: "#b8a18d",
        position: 5,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Bell Rook",
        shortcut: "npc.bell-rook",
        description: "Courier spirit tied to route warnings and missing messages.",
        color: "#b7af99",
        position: 6,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Cloud Shepherd Ren",
        shortcut: "npc.ren",
        description: "Older traveler who tends cloud-flocks between distant islands.",
        color: "#9db5b5",
        position: 7,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Choir of Moths",
        shortcut: "npc.choir-moths",
        description: "Memory-feeding moth collective with ritual social rules.",
        color: "#c9c0a6",
        position: 8,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Orin of the Posts",
        shortcut: "npc.orin",
        description: "Caretaker of post lines and boundary lantern chains.",
        color: "#8f9489",
        position: 9,
        parent_shortcut: "group.cast"
      },
      %{
        name: "Distant Mother",
        shortcut: "npc.mother",
        description: "Teo's emotional anchor, present only through song and trace.",
        color: "#d3c6b6",
        position: 10,
        parent_shortcut: "group.cast"
      },
      %{
        name: "The Unraveling",
        shortcut: "force.unraveling",
        description:
          "Corrupting force that freezes, distorts, and erases what stories could become.",
        color: "#302733",
        position: 0,
        parent_shortcut: "group.hostiles"
      },
      %{
        name: "Feltshade",
        shortcut: "enemy.feltshade",
        description: "Tutorial and patrol threat made from unfinished, deformed spirit matter.",
        color: "#473745",
        position: 1,
        parent_shortcut: "group.hostiles"
      },
      %{
        name: "Threadwound",
        shortcut: "enemy.threadwound",
        description:
          "Tighter, harder corruption entity that suggests escalation beyond the demo.",
        color: "#5d4347",
        position: 2,
        parent_shortcut: "group.hostiles"
      },
      %{
        name: "Hollow Lantern",
        shortcut: "enemy.hollow-lantern",
        description:
          "Corrupted lantern spirit that can still support tragic, saveable encounters.",
        color: "#6c6054",
        position: 3,
        parent_shortcut: "group.hostiles"
      },
      %{
        name: "Broken Threshold",
        shortcut: "loc.threshold",
        description: "Collapsed tunnel between life, dream, and afterlife.",
        color: "#a4adb5",
        position: 0,
        parent_shortcut: "group.locations"
      },
      %{
        name: "Mender's Isle",
        shortcut: "loc.isle",
        description: "First small floating refuge after the fall.",
        color: "#8ead8b",
        position: 1,
        parent_shortcut: "group.locations"
      },
      %{
        name: "House of Thread",
        shortcut: "loc.house",
        description: "Quiet interior refuge shaped by absent, careful hands.",
        color: "#c2ae92",
        position: 2,
        parent_shortcut: "group.locations"
      },
      %{
        name: "Veiled Path",
        shortcut: "loc.path",
        description: "Broken route where gathering, patrols, and gating converge.",
        color: "#87926e",
        position: 3,
        parent_shortcut: "group.locations"
      },
      %{
        name: "Lantern Clearing",
        shortcut: "loc.clearing",
        description: "Damaged sanctuary where Mina, Luma, and the keeper enter the story.",
        color: "#d0c79e",
        position: 4,
        parent_shortcut: "group.locations"
      }
    ]
  end

  defp sheet_block_specs do
    %{
      "game.demo" => [
        text_block(
          "Overview",
          """
          Shared demo state for Sky of Reverie. This sheet is the bridge between scenes, flows, resource loops, and character progress.
          """
        ),
        select_block("Area Current", "threshold", [
          "threshold",
          "isle",
          "house",
          "path",
          "clearing"
        ]),
        boolean_block("Nox Injured", false),
        boolean_block("First Attack Resolved", false),
        boolean_block("Refuge Discovered", false),
        boolean_block("Path Open", false),
        boolean_block("Mina In Party", false),
        boolean_block("Luma Unlocked", false),
        boolean_block("Lantern Keeper Saved", false),
        number_block("Mother Trace", 0),
        number_block("Local Corruption", 0),
        boolean_block("Demo Complete", false),
        table_block(
          "Chapters",
          [
            column("Status", "select", options: ["active", "locked", "complete"]),
            column("Starting Scene", "text"),
            column("Ending Scene", "text"),
            column("Objective", "text")
          ],
          [
            row("Waking", %{
              status: "active",
              starting_scene: "Broken Threshold",
              ending_scene: "Mender's Isle",
              objective: "Escape the tunnel alive."
            }),
            row("Refuge", %{
              status: "locked",
              starting_scene: "Mender's Isle",
              ending_scene: "House of Thread",
              objective: "Stabilize Nox and understand the next route."
            }),
            row("Crossing", %{
              status: "locked",
              starting_scene: "Veiled Path",
              ending_scene: "Veiled Path",
              objective: "Gather enough resources to open the route."
            }),
            row("Meeting", %{
              status: "locked",
              starting_scene: "Lantern Clearing",
              ending_scene: "Lantern Clearing",
              objective: "Form the first four-character team."
            })
          ]
        ),
        table_block(
          "Ambient Flows",
          [
            column("Scene", "text"),
            column("Trigger", "text"),
            column("Enabled", "boolean"),
            column("Note", "text")
          ],
          [
            row("Ambient Threshold Nox", %{
              scene: "Broken Threshold",
              trigger: "on_enter",
              enabled: true,
              note: "First Nox bark if Teo hesitates."
            }),
            row("Ambient Refuge Nox", %{
              scene: "House of Thread",
              trigger: "on_enter",
              enabled: true,
              note: "Pain, dry humor, and the next objective."
            }),
            row("Ambient Clearing Luma", %{
              scene: "Lantern Clearing",
              trigger: "on_enter",
              enabled: true,
              note: "Elemental foreshadowing before the climax."
            })
          ]
        )
      ],
      "inv.reverie" => [
        text_block(
          "Overview",
          """
          Light inventory layer for healing, cleansing, and route repair. The demo should stay readable and reactive, not become an economy sim.
          """
        ),
        number_block("Dew Drops", 0),
        number_block("Cloud Patches", 0),
        number_block("Light Seeds", 0),
        number_block("Warm Fruit", 0),
        boolean_block("White Token", false),
        table_block(
          "Resources",
          [
            column("Category", "select", options: ["healing", "support", "cleansing", "social"]),
            column("Effect", "text"),
            column("Where Found", "text"),
            column("Typical Spend", "text")
          ],
          [
            row("Dew Drop", %{
              category: "healing",
              effect: "Restores calm and energy.",
              where_found: "Isle, Path",
              typical_spend: "Stabilize Nox."
            }),
            row("Cloud Patch", %{
              category: "support",
              effect: "Repairs soft structures and route tears.",
              where_found: "House, Path",
              typical_spend: "Reopen shortcuts."
            }),
            row("Light Seed", %{
              category: "cleansing",
              effect: "Powers lanterns and weak purification.",
              where_found: "Path",
              typical_spend: "Open the clearing."
            }),
            row("Warm Fruit", %{
              category: "social",
              effect: "Calms frightened spirits.",
              where_found: "Isle, Path",
              typical_spend: "Soften or avoid an encounter."
            })
          ]
        ),
        table_block(
          "Collection Zones",
          [
            column("Scene", "text"),
            column("Resource", "text"),
            column("Experience", "text")
          ],
          [
            row("Still Pool", %{
              scene: "Mender's Isle",
              resource: "Dew Drops",
              experience: "First gathering tutorial."
            }),
            row("Sunken Roof", %{
              scene: "House of Thread",
              resource: "Cloud Patches",
              experience: "Short indoor search."
            }),
            row("Smoked Garden", %{
              scene: "Veiled Path",
              resource: "Warm Fruit",
              experience: "Light farming loop."
            }),
            row("Split Lantern", %{
              scene: "Veiled Path",
              resource: "Light Seeds",
              experience: "Risk and reward node."
            })
          ]
        )
      ],
      "pc.teo" => [
        text_block(
          "Overview",
          """
          Teo remembers who he is. What he cannot place is when he crossed into the threshold or why he woke there.
          """
        ),
        reference_block("Companion", "guardian.nox"),
        reference_block("Mother", "npc.mother"),
        number_block("Curiosity", 3),
        number_block("Courage", 2),
        number_block("Empathy", 3),
        number_block("Tenacity", 2),
        number_block("Trusts Nox", 0),
        number_block("Fear Of Falling", 2),
        number_block("Mother Memory", 1),
        boolean_block("Accepts Reverie", false),
        table_block(
          "Aptitudes",
          [
            column("Value", "number"),
            column("Demo Use", "text"),
            column("Tone", "text")
          ],
          [
            row("Curiosity", %{
              value: 3,
              demo_use: "Optional routes, inspection, and extra questions.",
              tone: "Wants to know before he obeys."
            }),
            row("Courage", %{
              value: 2,
              demo_use: "Fleeing, protecting Nox, and facing shadow.",
              tone: "Instinctive bravery."
            }),
            row("Empathy", %{
              value: 3,
              demo_use: "Reading Mina, calming spirits, and saving the keeper.",
              tone: "Quick heart."
            }),
            row("Tenacity", %{
              value: 2,
              demo_use: "Resisting fear and continuing after setbacks.",
              tone: "Does not let go easily."
            })
          ]
        ),
        table_block(
          "Echoes",
          [
            column("Source", "text"),
            column("Active In", "text"),
            column("Effect", "text")
          ],
          [
            row("Song", %{
              source: "Mother",
              active_in: "Broken Threshold",
              effect: "Raises game.demo.mother_trace by 1."
            }),
            row("Hand", %{
              source: "Physical memory",
              active_in: "House of Thread",
              effect: "Softens fear of falling."
            }),
            row("Distant Light", %{
              source: "Intuition",
              active_in: "Lantern Clearing",
              effect: "Prepares the next journey."
            })
          ]
        )
      ],
      "npc.mina" => [
        text_block(
          "Overview",
          """
          Mina is not there to deliver lore. She sharpens the story by being more prepared, more suspicious, and less forgiving than Teo.
          """
        ),
        reference_block("Companion", "guardian.luma"),
        number_block("Prudence", 4),
        number_block("Precision", 4),
        number_block("Distance", 3),
        number_block("Responsibility", 5),
        number_block("Trusts Teo", 0),
        boolean_block("Searching For Nox", true),
        table_block(
          "Aptitudes",
          [
            column("Value", "number"),
            column("Demo Use", "text"),
            column("Tone", "text")
          ],
          [
            row("Prudence", %{
              value: 4,
              demo_use: "Detecting risk and reading bad decisions.",
              tone: "Thinks before acting."
            }),
            row("Precision", %{
              value: 4,
              demo_use: "Elemental cooperation and exact timing.",
              tone: "Clean and exact."
            }),
            row("Distance", %{
              value: 3,
              demo_use: "Sharper, more tense dialogue branches.",
              tone: "Withholds intimacy."
            }),
            row("Responsibility", %{
              value: 5,
              demo_use: "Leadership in crisis and route decisions.",
              tone: "Carries the scene."
            })
          ]
        ),
        table_block(
          "Bonds",
          [
            column("Intensity", "number"),
            column("Notes", "text")
          ],
          [
            row("Luma", %{
              intensity: 5,
              notes: "Travel partner and near-sibling bond."
            }),
            row("Teo", %{
              intensity: 0,
              notes: "Begins as suspicion."
            }),
            row("Nox", %{
              intensity: 1,
              notes: "Relevant because of Luma."
            })
          ]
        )
      ],
      "guardian.nox" => [
        text_block(
          "Overview",
          """
          Nox does not command the world. He becomes what the moment needs. That makes him the clearest mascot-to-gameplay bridge in the demo.
          """
        ),
        reference_block("Bound To", "pc.teo"),
        reference_block("Searching For", "guardian.luma"),
        number_block("Form Energy", 5),
        boolean_block("Injured", false),
        number_block("Trusts Teo", 1),
        boolean_block("Searching For Luma", true),
        select_block("Current Mode", "mist", [
          "mist",
          "lantern",
          "shield",
          "soft_key",
          "grapple",
          "winged_beast"
        ]),
        table_block(
          "Forms",
          [
            column("Category", "select", options: ["object", "tool", "creature"]),
            column("Unlocked", "boolean"),
            column("Cost", "number"),
            column("Use", "text"),
            column("Notes", "text")
          ],
          [
            row("Lantern", %{
              category: "object",
              unlocked: true,
              cost: 1,
              use: "Lights dark spaces.",
              notes: "Immediate utility tutorial."
            }),
            row("Shield", %{
              category: "object",
              unlocked: true,
              cost: 1,
              use: "Blocks a strike or swarm.",
              notes: "Used in the first attack."
            }),
            row("Soft Key", %{
              category: "tool",
              unlocked: false,
              cost: 2,
              use: "Opens sealed cloth or runes.",
              notes: "Recovered after the refuge."
            }),
            row("Grapple", %{
              category: "tool",
              unlocked: false,
              cost: 2,
              use: "Crosses broken gaps.",
              notes: "Path traversal tool."
            }),
            row("Winged Beast", %{
              category: "creature",
              unlocked: true,
              cost: 4,
              use: "Short rescue flight.",
              notes: "Prologue set-piece."
            })
          ]
        ),
        table_block(
          "Synergies",
          [
            column("Luma Element", "text"),
            column("Result", "text")
          ],
          [
            row("Lantern", %{
              luma_element: "Light",
              result: "Cleansing focus."
            }),
            row("Grapple", %{
              luma_element: "Wind",
              result: "Extended reach."
            }),
            row("Shield", %{
              luma_element: "Earth",
              result: "Heavy guard."
            }),
            row("Lantern Bow", %{
              luma_element: "Wind + Light",
              result: "Final clearing payoff."
            })
          ]
        )
      ],
      "guardian.luma" => [
        text_block(
          "Overview",
          """
          Luma channels the states of the world rather than changing shape. He is the companion that makes the sky's internal rules readable.
          """
        ),
        reference_block("Bound To", "npc.mina"),
        reference_block("Brother", "guardian.nox"),
        number_block("Essence Energy", 6),
        boolean_block("In Party", false),
        number_block("Trusts Nox", 2),
        number_block("Trusts Teo", 0),
        select_block("Current Element", "light", ["light", "wind", "water", "earth", "fire"]),
        table_block(
          "Elements",
          [
            column("Unlocked", "boolean"),
            column("Primary Use", "text"),
            column("Counters", "text"),
            column("Tone", "text")
          ],
          [
            row("Light", %{
              unlocked: true,
              primary_use: "Reveal and purify.",
              counters: "Weak shadow.",
              tone: "Clarity."
            }),
            row("Wind", %{
              unlocked: true,
              primary_use: "Push, lift, and disperse.",
              counters: "Mist and swarms.",
              tone: "Motion."
            }),
            row("Water", %{
              unlocked: false,
              primary_use: "Calm unstable zones.",
              counters: "Heated ash.",
              tone: "Comfort."
            }),
            row("Earth", %{
              unlocked: false,
              primary_use: "Anchor and support.",
              counters: "Cracks and collapse.",
              tone: "Weight."
            }),
            row("Fire", %{
              unlocked: false,
              primary_use: "Cut dense corruption.",
              counters: "Hardened knots.",
              tone: "Risk."
            })
          ]
        ),
        table_block(
          "Readings",
          [
            column("Scene", "text"),
            column("What It Detects", "text")
          ],
          [
            row("Broken Trace", %{
              scene: "Lantern Clearing",
              what_it_detects: "Teo arrived through a ruptured threshold."
            }),
            row("Nox Pain", %{
              scene: "Lantern Clearing",
              what_it_detects: "Nox is forcing injured forms."
            }),
            row("Living Shadow", %{
              scene: "Veiled Path",
              what_it_detects: "The Unraveling is learning."
            })
          ]
        )
      ],
      "npc.lantern-keeper" => [
        text_block(
          "Overview",
          """
          Small neutral spirit that makes the ending about saving something fragile rather than only surviving a threat.
          """
        ),
        reference_block("Home", "loc.clearing"),
        boolean_block("Afraid", true),
        boolean_block("Rescued", false),
        boolean_block("Reward Given", false),
        number_block("Light Strength", 2),
        table_block(
          "Duties",
          [
            column("Status", "select", options: ["active", "failing", "lost"]),
            column("Meaning", "text")
          ],
          [
            row("Carry Light", %{
              status: "active",
              meaning: "Keeps the clearing alive."
            }),
            row("Watch Paths", %{
              status: "failing",
              meaning: "Corruption is spreading."
            }),
            row("Remember Names", %{
              status: "active",
              meaning: "Spirits trust the keeper."
            })
          ]
        )
      ],
      "npc.iri" => [
        text_block(
          "Overview",
          """
          Absent mender whose work explains why the refuge feels cared for instead of procedural.
          """
        ),
        reference_block("Linked Refuge", "loc.house"),
        select_block("Alive Status", "missing", ["missing", "alive", "gone"]),
        boolean_block("Left Supplies", true),
        boolean_block("Trusted Nox", true),
        table_block(
          "Legacy",
          [
            column("Where", "text"),
            column("Purpose", "text")
          ],
          [
            row("Repair Notes", %{
              where: "House of Thread",
              purpose: "Future lore collectible."
            }),
            row("Thread Symbols", %{
              where: "Mender's Isle",
              purpose: "Environmental mark."
            }),
            row("Safe Paths", %{
              where: "Veiled Path",
              purpose: "Implied route network."
            })
          ]
        )
      ],
      "npc.bell-rook" => [
        text_block(
          "Overview",
          """
          Messenger spirit that suggests the world used to be more connected than the demo's current crisis allows.
          """
        ),
        boolean_block("Route Known", true),
        number_block("Missing Since", 3),
        boolean_block("Owes Mina A Favor", true),
        table_block(
          "Deliveries",
          [
            column("Destination", "text"),
            column("Status", "select", options: ["late", "lost", "undelivered", "delivered"])
          ],
          [
            row("Warning Bell", %{
              destination: "Lantern Clearing",
              status: "late"
            }),
            row("Repair Notice", %{
              destination: "House of Thread",
              status: "lost"
            }),
            row("Song Fragment", %{
              destination: "Unknown",
              status: "undelivered"
            })
          ]
        )
      ],
      "npc.ren" => [
        text_block(
          "Overview",
          """
          Older traveler who broadens the setting beyond children and mascots by implying labor, weather, and long-distance survival.
          """
        ),
        number_block("Cloud Flock Size", 12),
        boolean_block("Trusts Luma", true),
        boolean_block("Warned About Threshold", false),
        table_block(
          "Routes",
          [
            column("Risk", "select", options: ["low", "medium", "high"]),
            column("Season", "text")
          ],
          [
            row("Isle To Path", %{
              risk: "medium",
              season: "current"
            }),
            row("Path To Hollow Reaches", %{
              risk: "high",
              season: "closed"
            }),
            row("Lantern Chain North", %{
              risk: "high",
              season: "failing"
            })
          ]
        )
      ],
      "npc.choir-moths" => [
        text_block(
          "Overview",
          """
          Strange collective that turns memory into social currency and makes the world feel less human-centered.
          """
        ),
        boolean_block("Remembers Teo Song", false),
        boolean_block("Favors Trade", true),
        boolean_block("Archive Open", false),
        table_block(
          "Customs",
          [column("Meaning", "text")],
          [
            row("Circle Once", %{meaning: "Permission to enter."}),
            row("Leave Thread", %{meaning: "Payment."}),
            row("Repeat Name", %{meaning: "Memory preservation."})
          ]
        )
      ],
      "npc.orin" => [
        text_block(
          "Overview",
          """
          Caretaker of lantern chains and boundary posts. He gives the setting navigational infrastructure with memory behind it.
          """
        ),
        number_block("Post Chain Intact", 4),
        boolean_block("Owes Iri", true),
        boolean_block("Heard Of Teo", false),
        table_block(
          "Post Network",
          [
            column("Status", "select", options: ["strong", "weak", "broken", "lost"]),
            column("Note", "text")
          ],
          [
            row("Clearing Line", %{
              status: "weak",
              note: "Lanterns fading."
            }),
            row("Threshold Line", %{
              status: "broken",
              note: "Unsafe crossing."
            }),
            row("Northern Chain", %{
              status: "lost",
              note: "No reply in weeks."
            })
          ]
        )
      ],
      "npc.mother" => [
        text_block(
          "Overview",
          """
          Teo's mother is a specific absent person, not an abstract goal. Her voice is the most stable memory he still has.
          """
        ),
        reference_block("Linked To", "pc.teo"),
        boolean_block("Voice Recognized", true),
        boolean_block("Location Known", false),
        boolean_block("Linked To Threshold", false),
        table_block(
          "Echoes",
          [
            column("Place", "text"),
            column("Effect", "text")
          ],
          [
            row("Song Line", %{
              place: "Broken Threshold",
              effect: "Starts the chase."
            }),
            row("Lullaby Shape", %{
              place: "House of Thread",
              effect: "Softens Teo."
            }),
            row("Distant Refrain", %{
              place: "Lantern Clearing",
              effect: "Closes the demo."
            })
          ]
        )
      ],
      "force.unraveling" => [
        text_block(
          "Overview",
          """
          The Unraveling does not only destroy. It freezes possibility and hardens story-space into a rigid nightmare.
          """
        ),
        number_block("Intensity", 1),
        boolean_block("Near Threshold", true),
        number_block("Trace On Teo", 1),
        number_block("Active Knot Count", 1),
        boolean_block("Watching Nox", true)
      ],
      "enemy.feltshade" => [
        text_block(
          "Overview",
          """
          Common corruption entity used for the tutorial threat and for patrol pressure on the path.
          """
        ),
        reference_block("Origin Force", "force.unraveling"),
        table_block(
          "Behaviors",
          [
            column("Trigger", "text"),
            column("Suggested Resolution", "text")
          ],
          [
            row("Lunge", %{
              trigger: "Proximity",
              suggested_resolution: "Nox shield or retreat."
            }),
            row("Encircle", %{
              trigger: "Patrol contact",
              suggested_resolution: "Light or warm fruit."
            }),
            row("Cling", %{
              trigger: "Guarding a corruption nest",
              suggested_resolution: "Empathy or cleansing."
            })
          ]
        )
      ],
      "enemy.threadwound" => [
        text_block(
          "Overview",
          """
          Escalated corruption entity wrapped too tightly by the Unraveling. Included to make the threat ladder visible in the sidebar.
          """
        ),
        reference_block("Origin Force", "force.unraveling"),
        number_block("Aggression", 3),
        boolean_block("Anchored", true),
        boolean_block("Breaks Light", true)
      ],
      "enemy.hollow-lantern" => [
        text_block(
          "Overview",
          """
          Corrupted lantern shell whose keeper has already been erased. Better used as a sad encounter than as pure combat fodder.
          """
        ),
        reference_block("Origin Force", "force.unraveling"),
        boolean_block("Flickering", true),
        boolean_block("Recognizes Song", false),
        boolean_block("Can Be Saved", true)
      ],
      "loc.threshold" => [
        text_block(
          "Overview",
          """
          Tunnel suspended above the void. White plates, cracked rails, missing spans, and black tears make it feel like a collapsing passage rather than a place.
          """
        ),
        reference_block("Dominant Force", "force.unraveling"),
        table_block(
          "Interactive Zones",
          [
            column("Type", "text"),
            column("Function", "text")
          ],
          [
            row("Wake Zone", %{
              type: "narrative trigger",
              function: "Teo's opening inner dialogue."
            }),
            row("Nox Pin", %{
              type: "companion pin",
              function: "First direct conversation."
            }),
            row("Mother Echo", %{
              type: "display or lore",
              function: "Raises game.demo.mother_trace."
            }),
            row("Fractured Walkway", %{
              type: "tension landmark",
              function: "Foreshadows collapse."
            }),
            row("Shade Nest", %{
              type: "encounter",
              function: "Starts the first attack flow."
            }),
            row("Great Breach", %{
              type: "set-piece exit",
              function: "Jump into the void."
            })
          ]
        )
      ],
      "loc.isle" => [
        text_block(
          "Overview",
          """
          Small floating island patched together from broken bridgework, soft grass, tilted wood, and repaired edges.
          """
        ),
        reference_block("Refuge", "loc.house"),
        table_block(
          "Interactive Zones",
          [
            column("Type", "text"),
            column("Function", "text")
          ],
          [
            row("Landing Edge", %{
              type: "narrative",
              function: "Crash landing and Nox injury."
            }),
            row("Still Pool", %{
              type: "collection",
              function: "Dew drops."
            }),
            row("Broken Tree", %{
              type: "lore",
              function: "Shows corruption already reached the isle."
            }),
            row("House Door", %{
              type: "target scene",
              function: "Enters House of Thread."
            })
          ]
        )
      ],
      "loc.house" => [
        text_block(
          "Overview",
          """
          First true safe interior of the demo. Wood, waxed cloth, and pale stone make it feel like patience kept it alive.
          """
        ),
        reference_block("Caretaker", "npc.iri"),
        table_block(
          "Interactive Zones",
          [
            column("Type", "text"),
            column("Function", "text")
          ],
          [
            row("Worktable", %{
              type: "flow trigger",
              function: "Main refuge conversation."
            }),
            row("Shelf", %{
              type: "collection",
              function: "Cloud patches."
            }),
            row("Cot", %{
              type: "interaction",
              function: "Short rest beat."
            }),
            row("Window", %{
              type: "display",
              function: "View of the path and distant clearing."
            })
          ]
        )
      ],
      "loc.path" => [
        text_block(
          "Overview",
          """
          Most playable scene in the slice. It combines calm traversal, gathering, patrols, and route gating in a single path space.
          """
        ),
        reference_block("Dominant Force", "force.unraveling"),
        table_block(
          "Interactive Zones",
          [
            column("Type", "text"),
            column("Function", "text")
          ],
          [
            row("Smoked Garden", %{
              type: "collection",
              function: "Warm fruit."
            }),
            row("Split Lantern", %{
              type: "collection or puzzle",
              function: "Light seeds."
            }),
            row("Soft Bridge", %{
              type: "obstacle",
              function: "Needs cloud patches or a Nox form."
            }),
            row("Shade Nest", %{
              type: "encounter",
              function: "Short crisis event."
            }),
            row("Root Gate", %{
              type: "gate",
              function: "Needs light seeds or a workaround."
            })
          ]
        ),
        table_block(
          "Patrols",
          [
            column("Route", "text"),
            column("Notes", "text")
          ],
          [
            row("Feltshade A", %{
              route: "Lantern to nest to gate",
              notes: "Slow patrol."
            }),
            row("Feltshade B", %{
              route: "Garden to bridge to nest",
              notes: "Short patrol."
            })
          ]
        )
      ],
      "loc.clearing" => [
        text_block(
          "Overview",
          """
          Circular sanctuary with damaged lantern posts and thin surviving light. This is the stage for the Mina and Luma reveal.
          """
        ),
        reference_block("Resident Spirit", "npc.lantern-keeper"),
        reference_block("Dominant Force", "force.unraveling"),
        table_block(
          "Interactive Zones",
          [
            column("Type", "text"),
            column("Function", "text")
          ],
          [
            row("Clearing Entry", %{
              type: "trigger",
              function: "Tension before the meeting."
            }),
            row("Central Ring", %{
              type: "flow trigger",
              function: "First conversation with Mina."
            }),
            row("Lantern Keeper", %{
              type: "narrative objective",
              function: "Spirit to rescue."
            }),
            row("Unraveling Knot", %{
              type: "climax",
              function: "Cooperative encounter."
            })
          ]
        )
      ]
    }
  end

  defp text_block(label, content, opts \\ []) do
    opts = Enum.into(opts, %{})

    Map.merge(
      %{
        type: "text",
        label: label,
        content: content,
        constant: true
      },
      opts
    )
  end

  defp number_block(label, value, opts \\ []) do
    opts = Enum.into(opts, %{})
    Map.merge(%{type: "number", label: label, value: value}, opts)
  end

  defp boolean_block(label, value, opts \\ []) do
    opts = Enum.into(opts, %{})
    Map.merge(%{type: "boolean", label: label, value: value}, opts)
  end

  defp select_block(label, value, options, opts \\ []) do
    opts = Enum.into(opts, %{})
    Map.merge(%{type: "select", label: label, value: value, options: options}, opts)
  end

  defp reference_block(label, target_shortcut, opts \\ []) do
    opts = Enum.into(opts, %{})

    Map.merge(
      %{
        type: "reference",
        label: label,
        target_shortcut: target_shortcut,
        constant: true
      },
      opts
    )
  end

  defp table_block(label, columns, rows, opts \\ []) do
    opts = Enum.into(opts, %{})

    Map.merge(
      %{
        type: "table",
        label: label,
        columns: columns,
        rows: rows
      },
      opts
    )
  end

  defp column(name, type, opts \\ []) do
    opts = Enum.into(opts, %{})
    Map.merge(%{name: name, type: type}, opts)
  end

  defp row(name, cells) do
    %{name: name, cells: cells}
  end
end

Storyarn.Scripts.SeedSkyOfReverie.run()
