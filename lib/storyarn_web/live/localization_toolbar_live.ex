defmodule StoryarnWeb.LocalizationToolbarLive do
  @moduledoc """
  Localization-specific top-right toolbar LiveView.

  Rendered by `LocalizationLive.Index`; its Vue boundary can inject into the
  project layout's `top-right` slot while this LiveView keeps owning the
  `translate_batch` event.

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

  alias Storyarn.Localization

  @max_import_bytes 5 * 1024 * 1024

  @impl true
  def mount(_params, session, socket) do
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)

    socket =
      socket
      |> assign(:current_scope, session["current_scope"])
      |> assign(:project_id, session["project_id"])
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:selected_locale, session["selected_locale"])
      |> assign(:has_provider, session["has_provider"] || false)
      |> assign(:can_edit, session["can_edit"] || false)
      |> assign(:filters, session["filters"] || %{})
      |> assign(
        :active_run,
        Localization.get_active_translation_run(session["project_id"], session["selected_locale"])
      )
      |> assign(:inject_target, session["inject_target"])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(session["project_id"]))

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        Storyarn.Localization.TranslationRunCrud.topic(session["project_id"])
      )
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
        v-component="live/localization/toolbar/LocalizationToolbar"
        v-socket={@socket}
        v-inject:top-right={@inject_target}
        id="localization-toolbar"
        export-csv-url={export_url(assigns, :csv)}
        export-xlsx-url={export_url(assigns, :xlsx)}
        glossary-url={glossary_url(assigns)}
        has-provider={@has_provider}
        can-edit={@can_edit}
        active-run={run_props(@active_run)}
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
      {:noreply, put_flash(socket, :error, dgettext("localization", "You don't have permission to edit."))}
    end
  end

  def handle_event("cancel_translation_run", %{"id" => run_id}, socket) do
    with true <- socket.assigns.can_edit,
         {id, ""} <- Integer.parse(to_string(run_id)),
         run when not is_nil(run) <- Localization.get_translation_run(socket.assigns.project_id, id),
         {:ok, cancelled} <- Localization.cancel_translation_run(run) do
      {:reply, %{ok: true}, assign(socket, :active_run, cancelled)}
    else
      _reason -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("import_csv", %{"content" => content}, socket) when is_binary(content) do
    cond do
      not socket.assigns.can_edit ->
        {:reply, %{ok: false, error: "unauthorized"}, socket}

      byte_size(content) > @max_import_bytes ->
        {:reply, %{ok: false, error: "file_too_large"}, socket}

      true ->
        case Localization.import_csv(socket.assigns.project_id, content) do
          {:ok, result} ->
            Phoenix.PubSub.broadcast(
              Storyarn.PubSub,
              shell_topic(socket.assigns.project_id),
              {:languages_changed, nil}
            )

            {:reply,
             %{
               ok: true,
               updated: result.updated,
               skipped: result.skipped,
               errors: Enum.map(result.errors, fn {line, reason} -> %{line: line, error: inspect(reason)} end)
             }, socket}

          {:error, reason} ->
            {:reply, %{ok: false, error: inspect(reason)}, socket}
        end
    end
  end

  defp do_translate_batch(socket) do
    locale = socket.assigns.selected_locale
    project_id = socket.assigns.project_id

    user_id = socket.assigns.current_scope.user.id

    case Localization.enqueue_batch_translation(project_id, locale, user_id) do
      {:ok, run} ->
        {:reply, %{ok: true, runId: run.id}, assign(socket, :active_run, run)}

      {:error, :already_running} ->
        run = Localization.get_active_translation_run(project_id, locale)
        {:reply, %{ok: true, runId: run && run.id}, assign(socket, :active_run, run)}

      {:error, reason} ->
        {:reply, %{ok: false, error: inspect(reason)}, socket}
    end
  end

  # ── Shell fan-in ──────────────────────────────────────────────────────────
  @impl true
  def handle_info({:active_locale, locale}, socket) do
    run = Localization.get_active_translation_run(socket.assigns.project_id, locale)
    {:noreply, assign(socket, selected_locale: locale, active_run: run)}
  end

  def handle_info({:translation_run_updated, run}, socket) do
    socket =
      if run.target_locale == socket.assigns.selected_locale do
        assign(socket, :active_run, run)
      else
        socket
      end

    socket =
      if run.status == "completed" and run.target_locale == socket.assigns.selected_locale do
        Phoenix.PubSub.broadcast(
          Storyarn.PubSub,
          shell_topic(run.project_id),
          {:languages_changed, nil}
        )

        put_flash(
          socket,
          :info,
          dngettext(
            "localization",
            "Translated %{count} string.",
            "Translated %{count} strings.",
            run.translated_count,
            count: run.translated_count
          )
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:localization_filters, filters}, socket) do
    {:noreply, assign(socket, :filters, filters)}
  end

  # Ignore toolbar/tree events we don't care about (main_sidebar_* go to the
  # sidebar; other tools' events should never reach us).
  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}
  def handle_info({:languages_changed, _payload}, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── URL helpers ───────────────────────────────────────────────────────────
  defp export_url(%{selected_locale: nil}, _format), do: nil

  defp export_url(%{workspace_slug: ws, project_slug: p, selected_locale: locale, filters: filters}, format)
       when is_binary(ws) and is_binary(p) and is_binary(locale) do
    query =
      filters
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()

    ~p"/workspaces/#{ws}/projects/#{p}/localization/export/#{format}/#{locale}?#{query}"
  end

  defp export_url(_, _), do: nil

  defp glossary_url(%{selected_locale: nil}), do: nil

  defp glossary_url(%{workspace_slug: ws, project_slug: project, selected_locale: locale}) do
    ~p"/workspaces/#{ws}/projects/#{project}/localization/glossary/#{locale}"
  end

  defp run_props(nil), do: nil

  defp run_props(run) do
    %{
      id: run.id,
      status: run.status,
      total: run.total_count,
      processed: run.processed_count,
      translated: run.translated_count,
      failed: run.failed_count,
      error: run.error
    }
  end

  @doc """
  Same shell topic format as sidebar LVs. Kept here to avoid cross-module
  coupling.
  """
  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
