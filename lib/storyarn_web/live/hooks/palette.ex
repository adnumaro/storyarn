defmodule StoryarnWeb.Live.Hooks.Palette do
  @moduledoc """
  Serves the command palette for every LiveView in the authenticated app
  session: registry-backed parameter completion
  (`palette_operation_options`), authorized advanced project search
  (`palette_advanced_search`), navigation search (`palette_nav`), entity creation
  (`palette_create_targets` / `palette_create`), entity deletion
  (`palette_delete_search` / `palette_delete`) and product analytics
  (`palette_opened`, command/search metrics and operation lifecycle metrics).

  Server-backed completion replies are built from `Storyarn.GlobalSearch` —
  authorization lives in
  the domain layer and derives from the socket's `current_scope` only; ids
  arriving from the client are re-validated against the composed authorized
  sets before any mutation. Mutations go through the same context facades
  the tree sidebars use and broadcast the same shell-topic messages, so
  sidebars and open editors react identically regardless of which surface
  performed the action. Analytics payloads are rebuilt from validated
  params — raw client params never reach the adapter. Known palette events
  fail closed with an `invalid_request` reply when their payload is malformed;
  they are never delegated to the host LiveView.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.AI
  alias Storyarn.Analytics
  alias Storyarn.Collaboration
  alias Storyarn.CommandPalette
  alias Storyarn.Flows
  alias Storyarn.GlobalSearch
  alias Storyarn.Notifications
  alias Storyarn.RateLimiter
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  # Analytics payloads are allowlist-validated before tracking: a hostile
  # client must not be able to persist free text (story content) through
  # command_id/surface. Surfaces are the finite set of registration owners;
  # command ids must be EXACTLY a known static id or a numeric nav id — a
  # character-shape regex alone would still let forged hyphenated text
  # through. Static commands live here; AI command ids come from the canonical
  # TaskRegistry catalog so product execution and analytics cannot drift.
  @known_surfaces ~w(global project workspace flows sheets scenes localization account)

  @static_command_ids MapSet.new(
                        ~w(account.profile account.security account.tutorials account.integrations
                           workspace.toggle-sidebar flows.toggle-minimap
                           flows.fit-to-view flows.analyze scenes.fit-to-view
                           create.project create.sheet create.flow create.scene
                           delete.sheet delete.flow delete.scene advanced-search.open) ++
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
  @operation_analytics_events ~w(palette_operation_selected palette_operation_completed
                                 palette_operation_abandoned)
  @operation_analytics_names %{
    "palette_operation_selected" => "palette operation selected",
    "palette_operation_completed" => "palette operation completed",
    "palette_operation_abandoned" => "palette operation abandoned"
  }
  @palette_events ~w(palette_operation_options palette_advanced_search
                     palette_nav palette_create_targets palette_create
                     palette_delete_search palette_delete palette_opened palette_command_executed
                     palette_search_no_results) ++ @operation_analytics_events
  # Client-supplied ids above the PostgreSQL bigint range would raise on
  # parameter encoding instead of failing closed — bound them at the guard.
  @max_pg_bigint 9_223_372_036_854_775_807
  @deep_search_minimum_interval_ms 750

  defguardp valid_database_id(value)
            when is_integer(value) and value > 0 and value <= @max_pg_bigint

  defguardp valid_execution_id(value)
            when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 64

  def on_mount(:setup_palette, _params, _session, socket) do
    socket =
      socket
      |> assign(:palette_deep_search_last_at, nil)
      |> Phoenix.LiveView.attach_hook(
        :palette,
        :handle_event,
        &handle_palette_event/3
      )

    {:cont, socket}
  end

  defp handle_palette_event(
         "palette_operation_options",
         %{"operation_id" => operation_id, "parameter_id" => parameter_id, "query" => query, "token" => token},
         socket
       )
       when is_binary(operation_id) and byte_size(operation_id) <= 64 and is_binary(parameter_id) and
              byte_size(parameter_id) <= 64 and is_binary(query) and byte_size(query) <= 400 and is_integer(token) do
    with {:ok, %{mode: :server, source: source}} <-
           CommandPalette.parameter_completion(operation_id, parameter_id),
         {:ok, items} <-
           operation_options(
             source,
             socket.assigns.current_scope,
             query
           ) do
      {:halt, %{token: token, items: items}, socket}
    else
      _invalid_or_client_completion ->
        {:halt, %{token: token, error: "invalid_request"}, socket}
    end
  end

  defp handle_palette_event("palette_operation_options", %{"token" => token}, socket) when is_integer(token) do
    {:halt, %{token: token, error: "invalid_request"}, socket}
  end

  defp handle_palette_event(
         "palette_advanced_search",
         %{"query" => query, "submitted" => submitted, "token" => token},
         socket
       )
       when is_binary(query) and byte_size(query) <= 400 and is_boolean(submitted) and is_integer(token) do
    case reserve_deep_search(socket, query, submitted) do
      {:ok, socket} ->
        with project_id when is_integer(project_id) <- current_project_id(socket),
             {:ok, page} <-
               GlobalSearch.advanced_project_search(
                 socket.assigns.current_scope,
                 project_id,
                 query,
                 submitted: submitted
               ) do
          {:halt, advanced_search_reply(page, token, socket), socket}
        else
          {:error, reason} ->
            {:halt, %{token: token, error: advanced_search_error(reason)}, socket}

          _no_project ->
            {:halt, %{token: token, error: "unavailable"}, socket}
        end

      {:error, :rate_limited, socket} ->
        {:halt, %{token: token, error: "rate_limited"}, socket}
    end
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
            %{
              key: "project_settings",
              items:
                destinations.projects
                |> Enum.filter(& &1.can_manage_project)
                |> Enum.map(&settings_item/1)
            },
            %{
              key: "workspace_settings",
              items:
                destinations.workspaces
                |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_general_settings))
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

  defp handle_palette_event(
         "palette_create",
         %{"type" => type, "project_id" => project_id, "execution_id" => execution_id},
         socket
       )
       when type in ~w(sheet flow scene) and valid_database_id(project_id) and valid_execution_id(execution_id) do
    scope = socket.assigns.current_scope

    {reply, post_commit} =
      CommandPalette.run(
        scope,
        "palette_create",
        execution_id,
        fn ->
          case GlobalSearch.editable_project(scope, project_id) do
            {:ok, %{project: project, workspace: workspace}} ->
              {entity, notification_outcome} = create_entity_in_transaction(scope, type, project)

              reply = %{
                url:
                  entity_url(%{
                    type: entity_type(type),
                    id: entity.id,
                    project_slug: project.slug,
                    workspace_slug: workspace.slug
                  })
              }

              {reply, {:entity_created, project.id, type, entity, notification_outcome}}

            {:error, :unauthorized} ->
              {%{error: "unauthorized"}, nil}
          end
        end,
        &create_error_reply/1
      )

    run_post_commit(post_commit)
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
          context: destination_context(dest),
          shortcut: dest.shortcut,
          projectId: dest.project_id
        }
      end)

    {:halt, %{token: token, items: items}, socket}
  end

  defp handle_palette_event(
         "palette_delete",
         %{"type" => type, "id" => id, "project_id" => project_id, "execution_id" => execution_id},
         socket
       )
       when type in ~w(sheet flow scene) and valid_database_id(id) and valid_database_id(project_id) and
              valid_execution_id(execution_id) do
    scope = socket.assigns.current_scope

    {reply, post_commit} =
      CommandPalette.run(
        scope,
        "palette_delete",
        execution_id,
        fn ->
          case GlobalSearch.deletable_entity(scope, entity_type(type), project_id, id) do
            {:ok, %{entity: entity, project: project}} ->
              # The delete itself reports the committed cascade set (collected
              # under its own lock) — never a separate pre-delete traversal.
              delete_result = delete_entity_subtree_in_transaction(scope, type, entity)

              {%{deleted: true}, delete_post_commit(project.id, type, delete_result)}

            {:error, :unauthorized} ->
              {%{error: "unauthorized"}, nil}

            {:error, :not_found} ->
              {%{error: "not_found"}, nil}
          end
        end,
        &delete_error_reply/1
      )

    run_post_commit(post_commit)
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
       when is_integer(query_length) and query_length >= 0 and query_length <= 100 and surface in @known_surfaces do
    Analytics.track(socket.assigns.current_scope, "palette search no results", %{
      query_length: query_length,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event(event, %{"operation_id" => operation_id, "surface" => surface}, socket)
       when event in @operation_analytics_events and is_binary(operation_id) and byte_size(operation_id) <= 64 and
              surface in @known_surfaces do
    if CommandPalette.registered_operation_id?(operation_id) do
      Analytics.track(socket.assigns.current_scope, Map.fetch!(@operation_analytics_names, event), %{
        operation_id: operation_id,
        surface: surface
      })
    end

    {:halt, socket}
  end

  defp handle_palette_event(event, _params, socket) when event in @palette_events do
    {:halt, %{error: "invalid_request"}, socket}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}

  defp operation_options(:navigation, scope, query) do
    destinations = GlobalSearch.destinations(scope, query)

    items =
      (destinations.workspaces ++ destinations.projects ++ destinations.entities)
      |> Enum.map(&nav_item/1)
      |> Enum.map(fn item ->
        put_optional(
          %{
            id: item.id,
            label: item.label,
            value: item.url,
            meta: put_optional(%{type: item.type}, :shortcut, Map.get(item, :shortcut))
          },
          :context,
          Map.get(item, :context)
        )
      end)

    {:ok, items}
  end

  defp operation_options(:deletable_entities, scope, query) do
    items =
      scope
      |> GlobalSearch.deletable_entities(query)
      |> Enum.map(fn destination ->
        type = Atom.to_string(destination.type)

        %{
          id: "#{type}:#{destination.id}",
          label: destination.name,
          context: destination_context(destination),
          value: %{id: destination.id, type: type, projectId: destination.project_id},
          meta: put_optional(%{}, :shortcut, destination.shortcut)
        }
      end)

    {:ok, items}
  end

  defp operation_options(_client_or_unknown_source, _scope, _query), do: :error

  defp current_project_id(%{assigns: %{project: %{id: project_id}}}) when is_integer(project_id), do: project_id

  defp current_project_id(_socket), do: nil

  defp reserve_deep_search(socket, <<"*", _query::binary>>, true) do
    now = System.monotonic_time(:millisecond)

    with :ok <- RateLimiter.check_palette_deep_search(socket.assigns.current_scope.user.id),
         :ok <- check_deep_search_interval(socket.assigns.palette_deep_search_last_at, now) do
      {:ok, assign(socket, :palette_deep_search_last_at, now)}
    else
      {:error, :rate_limited} -> {:error, :rate_limited, socket}
    end
  end

  defp reserve_deep_search(socket, _query, _submitted), do: {:ok, socket}

  defp check_deep_search_interval(last_at, now)
       when is_integer(last_at) and now - last_at < @deep_search_minimum_interval_ms, do: {:error, :rate_limited}

  defp check_deep_search_interval(_last_at, _now), do: :ok

  defp advanced_search_reply(page, token, socket) do
    put_optional(
      %{
        token: token,
        mode: Atom.to_string(page.mode),
        items: Enum.map(page.items, &advanced_search_item(&1, socket)),
        truncated: page.truncated
      },
      :fallback,
      advanced_search_fallback(page)
    )
  end

  defp advanced_search_fallback(%{fallback: fallback}) when is_atom(fallback), do: Atom.to_string(fallback)

  defp advanced_search_fallback(_page), do: nil

  defp advanced_search_item(%{action: %{kind: :complete, value: value}} = hit, _socket) do
    %{
      id: hit.id,
      kind: Atom.to_string(hit.kind),
      group: Atom.to_string(hit.group),
      type: Atom.to_string(hit.type),
      label: hit.label,
      context: hit.context,
      action: %{kind: "complete", value: value},
      meta: stringify_advanced_search_meta(hit.meta)
    }
  end

  defp advanced_search_item(%{action: %{kind: :navigate, destination: destination}} = hit, socket) do
    %{
      id: hit.id,
      kind: Atom.to_string(hit.kind),
      group: Atom.to_string(hit.group),
      type: Atom.to_string(hit.type),
      label: hit.label,
      context: hit.context,
      action: %{kind: "navigate", url: advanced_search_destination_url(destination, socket)},
      meta: stringify_advanced_search_meta(hit.meta)
    }
  end

  defp advanced_search_destination_url(destination, socket) do
    project = socket.assigns.project
    workspace = socket.assigns.workspace

    base =
      entity_url(%{
        type: destination.type,
        id: destination.id,
        project_slug: project.slug,
        workspace_slug: workspace.slug
      })

    append_search_focus(base, Map.get(destination, :focus))
  end

  defp append_search_focus(base, nil), do: base

  defp append_search_focus(base, %{type: :node, id: id}) when valid_database_id(id), do: "#{base}?highlight=node:#{id}"

  defp append_search_focus(base, %{type: type, id: id}) when type in [:pin, :zone] and valid_database_id(id),
    do: "#{base}?highlight=#{type}:#{id}"

  defp append_search_focus(base, %{type: :block, id: id}) when valid_database_id(id), do: "#{base}?highlight=block:#{id}"

  defp append_search_focus(base, %{type: :cell, block_id: block_id, row_id: row_id, column_id: column_id})
       when valid_database_id(block_id) and valid_database_id(row_id) and valid_database_id(column_id),
       do: "#{base}?highlight=cell:#{block_id}:#{row_id}:#{column_id}"

  defp append_search_focus(base, _invalid_focus), do: base

  defp stringify_advanced_search_meta(meta) when is_map(meta) do
    Map.new(meta, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_advanced_search_meta_value(value)}
      {key, value} -> {key, stringify_advanced_search_meta_value(value)}
    end)
  end

  defp stringify_advanced_search_meta(_meta), do: %{}

  defp stringify_advanced_search_meta_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_advanced_search_meta_value(value), do: value

  defp advanced_search_error(:unauthorized), do: "unauthorized"
  defp advanced_search_error(:not_found), do: "not_found"
  defp advanced_search_error(:invalid_request), do: "invalid_request"
  defp advanced_search_error(:not_submitted), do: "not_submitted"
  defp advanced_search_error(:rate_limited), do: "rate_limited"
  defp advanced_search_error(_reason), do: "lookup_failed"

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp valid_command_id?(command_id) do
    MapSet.member?(@static_command_ids, command_id) or
      Regex.match?(@nav_command_id_format, command_id) or
      AI.ai_command_id?(command_id)
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
      context: dest.workspace_name,
      url: ~p"/workspaces/#{dest.workspace_slug}/projects/#{dest.project_slug}"
    }
  end

  defp nav_item(%{type: entity_type} = dest) when entity_type in [:sheet, :flow, :scene] do
    %{
      id: "nav.#{entity_type}.#{dest.id}",
      type: Atom.to_string(entity_type),
      label: dest.name,
      context: destination_context(dest),
      shortcut: dest.shortcut,
      url: entity_url(dest)
    }
  end

  defp settings_item(%{type: :project} = dest) do
    %{
      id: "nav.project-settings.#{dest.id}",
      type: "settings",
      label: dest.name,
      context: dest.workspace_name,
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

  defp destination_context(%{project_name: project_name, workspace_name: workspace_name}) do
    "#{project_name} · #{workspace_name}"
  end

  # Same default names the tree sidebars use — one concept, one name.
  defp create_entity_in_transaction(scope, "sheet", project),
    do: Sheets.create_sheet_in_transaction(scope, project, %{name: dgettext("sheets", "Untitled")})

  defp create_entity_in_transaction(scope, "flow", project),
    do: Flows.create_flow_in_transaction(scope, project, %{name: dgettext("flows", "Untitled")})

  defp create_entity_in_transaction(scope, "scene", project),
    do: Scenes.create_scene_in_transaction(scope, project, %{name: dgettext("scenes", "Untitled")})

  defp delete_entity_subtree_in_transaction(scope, "sheet", entity),
    do: Sheets.delete_sheet_subtree_in_transaction(scope, entity)

  defp delete_entity_subtree_in_transaction(scope, "flow", entity),
    do: Flows.delete_flow_subtree_in_transaction(scope, entity)

  defp delete_entity_subtree_in_transaction(scope, "scene", entity),
    do: Scenes.delete_scene_subtree_in_transaction(scope, entity)

  defp create_error_reply({:limit_reached, _details}), do: %{error: "limit_reached"}
  defp create_error_reply(_reason), do: %{error: "create_failed"}

  defp delete_error_reply(:not_found), do: %{error: "not_found"}
  defp delete_error_reply(_reason), do: %{error: "delete_failed"}

  defp tree_key("sheet"), do: :sheets
  defp tree_key("flow"), do: :flows
  defp tree_key("scene"), do: :scenes

  defp delete_post_commit(project_id, "flow" = type, %{
         deleted_ids: deleted_ids,
         affected_flow_ids: affected_flow_ids,
         notification_outcome: outcome
       }) do
    {:entities_deleted, project_id, type, deleted_ids, affected_flow_ids, outcome}
  end

  defp delete_post_commit(project_id, type, %{deleted_ids: deleted_ids, notification_outcome: outcome}) do
    {:entities_deleted, project_id, type, deleted_ids, [], outcome}
  end

  defp run_post_commit(nil), do: :ok

  defp run_post_commit({:entity_created, project_id, type, entity, notification_outcome}) do
    Notifications.publish_committed(notification_outcome)

    if type == "sheet", do: Sheets.sync_created_sheet_localization(entity)

    Collaboration.broadcast_dashboard_change(project_id, tree_key(type))
    broadcast_tree_changed(project_id, type)
  end

  defp run_post_commit({:entities_deleted, project_id, type, deleted_ids, affected_flow_ids, notification_outcome}) do
    Notifications.publish_committed(notification_outcome)

    # Plain broadcast (not broadcast_from): the LV serving this event may
    # itself be showing a deleted entity and must navigate away too.
    Flows.broadcast_flow_refreshes(affected_flow_ids)
    Collaboration.broadcast_dashboard_change(project_id, tree_key(type))
    broadcast_entities_deleted(project_id, entity_type(type), deleted_ids)
    broadcast_tree_changed(project_id, type)
  end

  defp broadcast_tree_changed(project_id, type) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(project_id),
      {:tree_changed, tree_key(type)}
    )
  end

  defp broadcast_entities_deleted(project_id, type, ids) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(project_id),
      {:entities_deleted, type, ids}
    )
  end
end
