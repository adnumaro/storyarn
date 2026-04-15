defmodule StoryarnWeb.LocalizationToolbarLive do
  @moduledoc """
  Localization-specific top-right toolbar LiveView.

  Rendered via the `:top_bar_extras_right` slot of `ProjectShell` from
  `LocalizationLive.Index` (the dashboard is the only page with this
  toolbar today; Edit and Report don't fill the slot).

  Owns the `LocalizationToolbar.vue` widget (report link, export CSV/XLSX
  dropdown, "translate all pending" button) and the `translate_batch`
  event.

  Subscribes to the shell topic so it can update its export URLs when
  `LocalizationSidebarLive` broadcasts `{:active_locale, locale}`.

  Step 4 scaffold: renders the toolbar and stubs `translate_batch`.
  Step 6 will wire the real translation logic.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  alias Storyarn.Localization

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:current_scope, session["current_scope"])
      |> assign(:project_id, session["project_id"])
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:selected_locale, session["selected_locale"])
      |> assign(:has_provider, session["has_provider"] || false)
      |> assign(:can_edit, session["can_edit"] || false)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(session["project_id"]))
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"localization-toolbar-wrapper-#{@selected_locale || "none"}"}
      phx-update="ignore"
    >
      <.vue
        v-component="modules/localization/components/LocalizationToolbar"
        v-socket={@socket}
        id="localization-toolbar"
        export-csv-url={export_url(assigns, :csv)}
        export-xlsx-url={export_url(assigns, :xlsx)}
        has-provider={@has_provider}
      />
    </div>
    """
  end

  # ── Translate batch ──────────────────────────────────────────────────────
  @impl true
  def handle_event("translate_batch", _params, socket) do
    if socket.assigns.can_edit do
      do_translate_batch(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
    end
  end

  defp do_translate_batch(socket) do
    locale = socket.assigns.selected_locale
    project_id = socket.assigns.project_id

    case Localization.translate_batch(project_id, locale) do
      {:ok, %{translated: count}} ->
        # Text data changed; piggyback on :languages_changed so Index/Report
        # reload. (Naming is a bit loose but matches how `sync_texts` also
        # broadcasts `:languages_changed` even though only text rows changed.)
        Phoenix.PubSub.broadcast_from(
          Storyarn.PubSub,
          self(),
          shell_topic(project_id),
          {:languages_changed, nil}
        )

        msg =
          dngettext(
            "localization",
            "Translated %{count} string.",
            "Translated %{count} strings.",
            count,
            count: count
          )

        {:noreply, put_flash(socket, :info, msg)}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Rate limited by DeepL. Try again later.")
         )}

      {:error, :quota_exceeded} ->
        {:noreply, put_flash(socket, :error, dgettext("localization", "DeepL quota exceeded."))}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Translation failed: %{reason}", reason: inspect(reason))
         )}
    end
  end

  # ── Shell fan-in ──────────────────────────────────────────────────────────
  @impl true
  def handle_info({:active_locale, locale}, socket) do
    {:noreply, assign(socket, :selected_locale, locale)}
  end

  # Ignore toolbar/tree events we don't care about (tree_panel_* go to the
  # sidebar; other tools' events should never reach us).
  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}
  def handle_info({:languages_changed, _payload}, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── URL helpers ───────────────────────────────────────────────────────────
  defp export_url(%{selected_locale: nil}, _format), do: nil

  defp export_url(%{workspace_slug: ws, project_slug: p, selected_locale: locale}, format)
       when is_binary(ws) and is_binary(p) and is_binary(locale) do
    ~p"/workspaces/#{ws}/projects/#{p}/localization/export/#{format}/#{locale}"
  end

  defp export_url(_, _), do: nil

  @doc """
  Same shell topic format as sidebar LVs. Kept here to avoid cross-module
  coupling.
  """
  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
