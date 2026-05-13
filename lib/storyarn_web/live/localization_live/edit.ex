defmodule StoryarnWeb.LocalizationLive.Edit do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Shared.TimeHelpers
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:localization}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.LocalizationSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "selected_locale" => @text.locale_code,
          "can_edit" => @can_edit,
          "active_tool" => "localization",
          "dashboard_url" =>
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/localization/texts/LocalizationTextEdit"
        v-socket={@socket}
        v-inject="project-layout"
        id="localization-edit-vue"
        class="contents"
        text={serialize_text(@text)}
        form={@form}
        has-provider={@has_provider}
        can-edit={@can_edit}
        back-url={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/texts/#{@text.locale_code}"
        }
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  defp serialize_text(text) do
    %{
      id: text.id,
      source_type: text.source_type,
      source_field: text.source_field,
      source_text: HtmlSanitizer.sanitize_html(text.source_text || ""),
      word_count: text.word_count,
      locale_code: text.locale_code,
      translated_text: text.translated_text,
      status: text.status,
      translator_notes: text.translator_notes,
      machine_translated: text.machine_translated,
      last_translated_at: text.last_translated_at && DateTime.to_iso8601(text.last_translated_at)
    }
  end

  @impl true
  def mount(%{"id" => text_id}, _session, socket) do
    %{project: project} = socket.assigns
    {text_id_int, ""} = Integer.parse(text_id)
    text = Localization.get_text!(project.id, text_id_int)

    form = build_form(text)
    has_provider = Localization.has_active_provider?(project.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id)
      )

      # Keep the sticky sidebar's highlight in sync when the user lands on
      # a text directly (or navigates back from Report/Index).
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id),
        {:active_locale, text.locale_code}
      )
    end

    socket =
      socket
      |> assign(:text, text)
      |> assign(:form, form)
      |> assign(:has_provider, has_provider)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("main_sidebar_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_main_sidebar(socket, event, params)

  def handle_event("save_translation", %{"localized_text" => params}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      now = TimeHelpers.now()
      params = Map.put(params, "last_translated_at", now)

      case Localization.update_text(socket.assigns.text, params) do
        {:ok, updated_text} ->
          socket =
            socket
            |> assign(:text, updated_text)
            |> assign(:form, build_form(updated_text))
            |> put_flash(:info, dgettext("localization", "Translation saved."))

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset, as: "localized_text"))}
      end
    end)
  end

  def handle_event("translate_with_deepl", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      text = socket.assigns.text

      case Localization.translate_single(socket.assigns.project.id, text.id) do
        {:ok, updated_text} ->
          socket =
            socket
            |> assign(:text, updated_text)
            |> assign(:form, build_form(updated_text))
            |> put_flash(:info, dgettext("localization", "Translation complete."))

          {:noreply, socket}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("localization", "Translation failed: %{reason}", reason: inspect(reason))
           )}
      end
    end)
  end

  defp build_form(text) do
    changeset =
      Localization.change_localized_text(text)

    to_form(changeset, as: "localized_text")
  end
end
