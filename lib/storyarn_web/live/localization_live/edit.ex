defmodule StoryarnWeb.LocalizationLive.Edit do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Shared.TimeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus_v2
      socket={@socket}
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:localization}
      has_tree={false}
      can_edit={@can_edit}
    >
      <.vue
        v-component="localization/LocalizationEdit"
        v-socket={@socket}
        id="localization-edit-vue"
        text={serialize_text(@text)}
        form={@form}
        has-provider={@has_provider}
        can-edit={@can_edit}
        back-url={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
      />
    </Layouts.focus_v2>
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
      last_translated_at:
        text.last_translated_at && DateTime.to_iso8601(text.last_translated_at)
    }
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => text_id
        },
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)
        {text_id_int, ""} = Integer.parse(text_id)
        text = Localization.get_text!(project.id, text_id_int)

        form = build_form(text)

        has_provider = Localization.has_active_provider?(project.id)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:text, text)
          |> assign(:form, form)
          |> assign(:has_provider, has_provider)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("localization", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
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
      Storyarn.Localization.change_localized_text(text)

    to_form(changeset, as: "localized_text")
  end
end
