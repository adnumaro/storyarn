defmodule StoryarnWeb.Live.Hooks.Palette do
  @moduledoc """
  Serves the command palette for every LiveView in the authenticated app
  session: navigation search (`palette_nav`) and product analytics
  (`palette_opened` / `palette_command_executed` / `palette_search_no_results`).

  Navigation replies are built from `Storyarn.GlobalSearch` — authorization
  lives in the domain layer and derives from the socket's `current_scope`
  only; this hook merely maps the structured destinations to verified-route
  URLs. Analytics payloads are rebuilt from validated params — raw client
  params never reach the adapter. Malformed events (only our own client
  produces these) fall through like any unknown event.
  """

  use StoryarnWeb, :verified_routes

  alias Storyarn.Analytics
  alias Storyarn.GlobalSearch

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
              items: Enum.map(destinations.workspaces, &workspace_settings_item/1)
            },
            %{key: "entities", items: Enum.map(destinations.entities, &nav_item/1)}
          ],
          &(&1.items == [])
        )
    }

    {:halt, reply, socket}
  end

  defp handle_palette_event("palette_opened", %{"surface" => surface}, socket) when is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette opened", %{surface: surface})
    {:halt, socket}
  end

  defp handle_palette_event("palette_command_executed", %{"command_id" => command_id, "surface" => surface}, socket)
       when is_binary(command_id) and is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette command executed", %{
      command_id: command_id,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event("palette_search_no_results", %{"query_length" => query_length, "surface" => surface}, socket)
       when is_integer(query_length) and is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette search no results", %{
      query_length: query_length,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}

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
end
