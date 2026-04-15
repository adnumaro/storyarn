defmodule StoryarnWeb.LocalizationSidebarLive do
  @moduledoc """
  Localization-specific left sidebar LiveView.

  Rendered as a sticky nested child of `ProjectShell` on localization
  routes. Owns the languages panel (source + target locales) and the
  mutation handlers for adding/removing/selecting languages.

  Pairs with `LocalizationToolbarLive` (rendered via the
  `:top_bar_extras_right` slot of `ProjectShell`) for the `translate_batch`
  button on the Index page.

  Step 3 scaffold: loads languages + handles `tree_panel_*`. Actual
  localization mutations land in step 6.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Localization
  alias Storyarn.Localization.Languages
  alias Storyarn.Projects

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    project_id = session["project_id"]

    project =
      if project_id && current_scope do
        case Projects.get_project(current_scope, project_id) do
          {:ok, project, _membership} -> project
          _ -> nil
        end
      end

    # Auto-create the source language row if missing. Mirrors what the old
    # LocalizationLive.Index mount did.
    if project, do: Localization.ensure_source_language(project)

    {source_language, target_languages} = load_languages(project_id)

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:project, project)
      |> assign(:project_id, project_id)
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:selected_locale, session["selected_locale"])
      |> assign(:can_edit, session["can_edit"] || false)
      |> assign(:active_tool, session["active_tool"] || "localization")
      |> assign(:dashboard_url, session["dashboard_url"])
      |> assign(:tree_panel_open, false)
      |> assign(:tree_panel_pinned, true)
      |> assign(:source_language, source_language)
      |> assign(:target_languages, target_languages)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(project_id))
      Collaboration.subscribe_changes({:project, project_id})
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="layout/TreePanel"
        v-socket={@socket}
        id="localization-sidebar"
        tree-panel-open={@tree_panel_open}
        tree-panel-pinned={@tree_panel_pinned}
        show-pin={false}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={is_nil(@selected_locale)}
        tree-props={build_tree_props(assigns)}
      />
    </div>
    """
  end

  # ── Panel state events from TreePanel.vue ─────────────────────────────────
  @impl true
  def handle_event("tree_panel_init", %{"pinned" => pinned}, socket) do
    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_event("tree_panel_toggle", _params, socket) do
    {:noreply, assign(socket, :tree_panel_open, !socket.assigns.tree_panel_open)}
  end

  def handle_event("tree_panel_pin", _params, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  # ── Localization mutations ────────────────────────────────────────────────

  # Locale selection is URL-driven (target language items in LocalizationSidebar.vue
  # are `data-phx-link="patch"` anchors that navigate to /localization/texts/:locale).
  # `LocalizationLive.Index.handle_params` broadcasts `{:active_locale, locale}` on
  # the shell topic so this sidebar updates its highlight.

  # Empty locale codes — user selected the placeholder. No-op.
  def handle_event("change_source_language", %{"locale_code" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_target_language", %{"locale_code" => ""}, socket), do: {:noreply, socket}

  def handle_event("change_source_language", %{"locale_code" => code}, socket) do
    with_edit(socket, fn socket ->
      case Localization.change_source_language(socket.assigns.project, code) do
        {:ok, _language} ->
          {:noreply,
           socket
           |> reload_and_broadcast()
           |> put_flash(:info, dgettext("localization", "Source language updated."))}

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("localization", "Could not update the source language.")
           )}
      end
    end)
  end

  def handle_event("add_target_language", %{"locale_code" => code}, socket) do
    with_edit(socket, fn socket ->
      name = Localization.language_name(code)

      attrs = %{"locale_code" => code, "name" => name, "is_source" => false}

      case Localization.add_language(socket.assigns.project, attrs) do
        {:ok, _lang} ->
          count =
            case Localization.extract_all(socket.assigns.project.id) do
              {:ok, c} -> c
              {:error, _} -> 0
            end

          msg =
            if count > 0 do
              dngettext(
                "localization",
                "Language added. Extracted %{count} text.",
                "Language added. Extracted %{count} texts.",
                count,
                count: count
              )
            else
              dgettext("localization", "Language added.")
            end

          {:noreply,
           socket
           |> reload_and_broadcast()
           |> put_flash(:info, msg)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("localization", "Failed to add language."))}
      end
    end)
  end

  def handle_event("remove_language", %{"id" => id}, socket) do
    with_edit(socket, fn socket ->
      lang = Localization.get_language(socket.assigns.project.id, id)

      cond do
        is_nil(lang) ->
          {:noreply, socket}

        lang.is_source ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("localization", "Cannot remove the source language.")
           )}

        true ->
          case Localization.remove_language(lang) do
            {:ok, _} ->
              {:noreply,
               socket
               |> reload_and_broadcast()
               |> put_flash(:info, dgettext("localization", "Language removed."))}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, dgettext("localization", "Could not remove language."))}
          end
      end
    end)
  end

  def handle_event("sync_texts", _params, socket) do
    with_edit(socket, fn socket ->
      case Localization.extract_all(socket.assigns.project.id) do
        {:ok, count} ->
          # Texts changed, not the language list, but Index/Report still want
          # to refresh. Use the same broadcast channel to keep things simple.
          broadcast_languages_changed(socket)

          msg =
            dngettext(
              "localization",
              "Synced %{count} text entry.",
              "Synced %{count} text entries.",
              count,
              count: count
            )

          {:noreply, put_flash(socket, :info, msg)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("localization", "Sync failed."))}
      end
    end)
  end

  # ── Shell / Collaboration fan-in ──────────────────────────────────────────
  @impl true
  def handle_info({:active_locale, locale}, socket) do
    {:noreply, assign(socket, :selected_locale, locale)}
  end

  def handle_info({:languages_changed, _payload}, socket) do
    {source_language, target_languages} = load_languages(socket.assigns.project_id)

    {:noreply,
     socket
     |> assign(:source_language, source_language)
     |> assign(:target_languages, target_languages)}
  end

  def handle_info({:remote_change, _action, _payload}, socket), do: {:noreply, socket}

  # Forwarded from ToolbarsLive (LeftToolbar.vue's pushEvent lands there).
  def handle_info({:toolbar_event, "tree_panel_toggle", _params}, socket) do
    {:noreply, assign(socket, :tree_panel_open, !socket.assigns.tree_panel_open)}
  end

  def handle_info({:toolbar_event, "tree_panel_pin", _params}, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_info({:toolbar_event, "tree_panel_init", %{"pinned" => pinned}}, socket) do
    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp with_edit(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
    end
  end

  # Reload local language state and broadcast so Index/Report/Toolbar
  # refresh themselves. Uses broadcast (not broadcast_from) so we also
  # receive it — but our own handle_info is idempotent via load_languages.
  defp reload_and_broadcast(socket) do
    {source, targets} = load_languages(socket.assigns.project_id)

    socket =
      socket
      |> assign(:source_language, source)
      |> assign(:target_languages, targets)

    broadcast_languages_changed(socket)
    socket
  end

  defp broadcast_languages_changed(socket) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:languages_changed, nil}
    )
  end

  defp load_languages(nil), do: {nil, []}

  defp load_languages(project_id) do
    # ensure_source_language takes a Project struct; we don't have it here,
    # but list_languages + filtering by is_source is equivalent enough for
    # the sidebar scaffold. Full wiring (creating source on missing) happens
    # in step 6 when we move the mutation handlers over and need the Project.
    languages = Localization.list_languages(project_id)
    source = Enum.find(languages, & &1.is_source)
    targets = Localization.get_target_languages(project_id)
    {source, targets}
  end

  defp build_tree_props(assigns) do
    existing_codes =
      [
        assigns.source_language && assigns.source_language.locale_code
        | Enum.map(assigns.target_languages, & &1.locale_code)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    source_code = assigns.source_language && assigns.source_language.locale_code

    %{
      sourceLanguage: serialize_language(assigns.source_language),
      targetLanguages: Enum.map(assigns.target_languages, &serialize_language/1),
      selectedLocale: assigns.selected_locale,
      canEdit: assigns.can_edit,
      workspaceSlug: assigns.workspace_slug,
      projectSlug: assigns.project_slug,
      sourceLanguageOptions:
        [exclude: Enum.reject([source_code], &is_nil/1)]
        |> Languages.options_for_select()
        |> Enum.map(fn {label, value} -> %{label: label, value: value} end),
      addLanguageOptions:
        [exclude: MapSet.to_list(existing_codes)]
        |> Languages.options_for_select()
        |> Enum.map(fn {label, value} -> %{label: label, value: value} end)
    }
  end

  defp serialize_language(nil), do: nil

  defp serialize_language(lang) do
    flag_code = Languages.flag_code(lang.locale_code)

    %{
      id: lang.id,
      localeCode: lang.locale_code,
      name: lang.name || Languages.name(lang.locale_code) || lang.locale_code,
      flagUrl: flag_code && "/images/flags/1x1/#{flag_code}.svg",
      shortLabel: Languages.short_label(lang.locale_code)
    }
  end

  @doc """
  Shared shell topic for cross-LV PubSub. Same format as the sheets sidebar
  helper — kept here too so localization LVs don't need to reach into the
  sheets module.
  """
  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
