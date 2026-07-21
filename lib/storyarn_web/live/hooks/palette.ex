defmodule StoryarnWeb.Live.Hooks.Palette do
  @moduledoc """
  Serves the command palette for every LiveView in the authenticated app
  session: navigation search (`palette_nav`), entity creation
  (`palette_create_targets` / `palette_create`), entity deletion
  (`palette_delete_search` / `palette_delete`) and product analytics
  (`palette_opened` / `palette_command_executed` / `palette_search_no_results`).

  Replies are built from `Storyarn.GlobalSearch` — authorization lives in
  the domain layer and derives from the socket's `current_scope` only; ids
  arriving from the client are re-validated against the composed authorized
  sets before any mutation. Mutations go through the same context facades
  the tree sidebars use and broadcast the same shell-topic messages, so
  sidebars and open editors react identically regardless of which surface
  performed the action. Analytics payloads are rebuilt from validated
  params — raw client params never reach the adapter. Malformed events
  (only our own client produces these) fall through like any unknown event.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Analytics
  alias Storyarn.Flows
  alias Storyarn.GlobalSearch
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  # Analytics payloads are allowlist-validated before tracking: a hostile
  # client must not be able to persist free text (story content) through
  # command_id/surface. Surfaces are the finite set of registration owners;
  # command ids must be EXACTLY a known static id or a numeric nav id — a
  # character-shape regex alone would still let forged hyphenated text
  # through. New palette commands must be added here to be tracked.
  @known_surfaces ~w(global project workspace flows sheets scenes localization account)

  @static_command_ids MapSet.new(
                        ~w(account.profile account.security account.tutorials
                           workspace.toggle-sidebar flows.toggle-minimap
                           flows.fit-to-view scenes.fit-to-view
                           create.project create.sheet create.flow create.scene
                           delete.sheet delete.flow delete.scene) ++
                          Enum.map(
                            ~w(dashboard sheets flows scenes assets localization),
                            &"project.go-to.#{&1}"
                          ) ++
                          Enum.map(
                            ~w(general members localization snapshots version_control
                               usage_limits import_export trash),
                            &"project.settings.#{&1}"
                          )
                      )

  @nav_command_id_format ~r/^nav\.(workspace|project|project-settings|workspace-settings|sheet|flow|scene)\.[1-9]\d{0,19}$/

  def on_mount(:setup_palette, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(
       socket,
       :palette,
       :handle_event,
       &handle_palette_event/3
     )}
  end

  defp handle_palette_event("palette_nav", %{"query" => query, "token" => token}, socket)
       when is_binary(query) and is_integer(token) do
    destinations = GlobalSearch.destinations(socket.assigns.current_scope, query)

    reply = %{
      token: token,
      groups:
        Enum.reject(
          [
            %{key: "workspaces", items: Enum.map(destinations.workspaces, &nav_item/1)},
            %{key: "projects", items: Enum.map(destinations.projects, &nav_item/1)},
            %{key: "project_settings", items: Enum.map(destinations.projects, &settings_item/1)},
            %{
              key: "workspace_settings",
              items:
                destinations.workspaces
                |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_settings))
                |> Enum.map(&workspace_settings_item/1)
            },
            %{key: "entities", items: Enum.map(destinations.entities, &nav_item/1)}
          ],
          &(&1.items == [])
        )
    }

    {:halt, reply, socket}
  end

  defp handle_palette_event("palette_create_targets", %{"token" => token}, socket) when is_integer(token) do
    projects =
      socket.assigns.current_scope
      |> GlobalSearch.create_targets()
      |> Enum.map(fn target ->
        %{id: target.id, label: target.name, context: target.workspace_name}
      end)

    {:halt, %{token: token, projects: projects}, socket}
  end

  defp handle_palette_event("palette_create", %{"type" => type, "project_id" => project_id}, socket)
       when type in ~w(sheet flow scene) and is_integer(project_id) do
    scope = socket.assigns.current_scope

    reply =
      with {:ok, %{project: project, workspace: workspace}} <- GlobalSearch.editable_project(scope, project_id),
           {:ok, entity} <- create_entity(type, project) do
        broadcast_tree_changed(project.id, type)

        %{
          url:
            entity_url(%{
              type: entity_type(type),
              id: entity.id,
              project_slug: project.slug,
              workspace_slug: workspace.slug
            })
        }
      else
        {:error, :unauthorized} -> %{error: "unauthorized"}
        {:error, :limit_reached, _} -> %{error: "limit_reached"}
        {:error, _} -> %{error: "create_failed"}
      end

    {:halt, reply, socket}
  end

  defp handle_palette_event("palette_delete_search", %{"query" => query, "token" => token}, socket)
       when is_binary(query) and is_integer(token) do
    items =
      socket.assigns.current_scope
      |> GlobalSearch.deletable_entities(query)
      |> Enum.map(fn dest ->
        %{
          id: dest.id,
          type: Atom.to_string(dest.type),
          label: dest.name,
          context: dest.project_name,
          shortcut: dest.shortcut,
          projectId: dest.project_id
        }
      end)

    {:halt, %{token: token, items: items}, socket}
  end

  defp handle_palette_event("palette_delete", %{"type" => type, "id" => id, "project_id" => project_id}, socket)
       when type in ~w(sheet flow scene) and is_integer(id) and is_integer(project_id) do
    scope = socket.assigns.current_scope

    reply =
      with {:ok, %{entity: entity, project: project}} <-
             GlobalSearch.deletable_entity(scope, entity_type(type), project_id, id),
           {:ok, _} <- delete_entity(type, entity) do
        # Plain broadcast (not broadcast_from): the LV serving this event may
        # itself be showing the deleted entity and must navigate away too.
        broadcast_entity_deleted(project.id, entity.id)
        broadcast_tree_changed(project.id, type)
        %{deleted: true}
      else
        {:error, :unauthorized} -> %{error: "unauthorized"}
        {:error, :not_found} -> %{error: "not_found"}
        {:error, _} -> %{error: "delete_failed"}
      end

    {:halt, reply, socket}
  end

  defp handle_palette_event("palette_opened", %{"surface" => surface}, socket) when surface in @known_surfaces do
    Analytics.track(socket.assigns.current_scope, "palette opened", %{surface: surface})
    {:halt, socket}
  end

  defp handle_palette_event("palette_command_executed", %{"command_id" => command_id, "surface" => surface}, socket)
       when is_binary(command_id) and surface in @known_surfaces do
    if valid_command_id?(command_id) do
      Analytics.track(socket.assigns.current_scope, "palette command executed", %{
        command_id: command_id,
        surface: surface
      })
    end

    {:halt, socket}
  end

  defp handle_palette_event("palette_search_no_results", %{"query_length" => query_length, "surface" => surface}, socket)
       when is_integer(query_length) and surface in @known_surfaces do
    Analytics.track(socket.assigns.current_scope, "palette search no results", %{
      query_length: query_length,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}

  defp valid_command_id?(command_id) do
    MapSet.member?(@static_command_ids, command_id) or
      Regex.match?(@nav_command_id_format, command_id)
  end

  defp nav_item(%{type: :workspace} = dest) do
    %{
      id: "nav.workspace.#{dest.id}",
      type: "workspace",
      label: dest.name,
      url: ~p"/workspaces/#{dest.workspace_slug}"
    }
  end

  defp nav_item(%{type: :project} = dest) do
    %{
      id: "nav.project.#{dest.id}",
      type: "project",
      label: dest.name,
      url: ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}"
    }
  end

  defp nav_item(%{type: entity_type} = dest) when entity_type in [:sheet, :flow, :scene] do
    %{
      id: "nav.#{entity_type}.#{dest.id}",
      type: Atom.to_string(entity_type),
      label: dest.name,
      context: dest.project_name,
      shortcut: dest.shortcut,
      url: entity_url(dest)
    }
  end

  defp settings_item(%{type: :project} = dest) do
    %{
      id: "nav.project-settings.#{dest.id}",
      type: "settings",
      label: dest.name,
      url: ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}/settings"
    }
  end

  defp workspace_settings_item(%{type: :workspace} = dest) do
    %{
      id: "nav.workspace-settings.#{dest.id}",
      type: "settings",
      label: dest.name,
      url: ~p"/users/settings/workspaces/#{dest.workspace_slug}/general"
    }
  end

  defp entity_url(%{type: :sheet} = dest) do
    ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}/sheets/#{dest.id}"
  end

  defp entity_url(%{type: :flow} = dest) do
    ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}/flows/#{dest.id}"
  end

  defp entity_url(%{type: :scene} = dest) do
    ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}/scenes/#{dest.id}"
  end

  defp entity_type("sheet"), do: :sheet
  defp entity_type("flow"), do: :flow
  defp entity_type("scene"), do: :scene

  # Same default names the tree sidebars use — one concept, one name.
  defp create_entity("sheet", project), do: Sheets.create_sheet(project, %{name: dgettext("sheets", "Untitled")})
  defp create_entity("flow", project), do: Flows.create_flow(project, %{name: dgettext("flows", "Untitled")})
  defp create_entity("scene", project), do: Scenes.create_scene(project, %{name: dgettext("scenes", "Untitled")})

  defp delete_entity("sheet", entity), do: Sheets.delete_sheet(entity)
  defp delete_entity("flow", entity), do: Flows.delete_flow(entity)
  defp delete_entity("scene", entity), do: Scenes.delete_scene(entity)

  defp tree_key("sheet"), do: :sheets
  defp tree_key("flow"), do: :flows
  defp tree_key("scene"), do: :scenes

  defp broadcast_tree_changed(project_id, type) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(project_id),
      {:tree_changed, tree_key(type)}
    )
  end

  defp broadcast_entity_deleted(project_id, id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(project_id),
      {:entity_deleted, id}
    )
  end
end
