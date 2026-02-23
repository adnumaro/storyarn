defmodule StoryarnWeb.LocalizationLive.Edit do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Shared.TimeHelpers
  alias StoryarnWeb.FlowLive.Helpers.HtmlSanitizer

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:localization}
      has_tree={false}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {dgettext("localization", "Edit Translation")}
          <:subtitle>
            <span class="font-mono text-sm">{@text.source_type}/{@text.source_field}</span>
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="arrow-left" class="size-4 mr-1" />
              {dgettext("localization", "Back")}
            </.link>
          </:actions>
        </.header>

        <div class="grid grid-cols-2 gap-6 mt-6">
          <%!-- Source text --%>
          <div>
            <h4 class="font-medium text-sm mb-2 opacity-70">{dgettext("localization", "Source")}</h4>
            <div class="bg-base-200 rounded-lg p-4 min-h-32">
              <div class="prose prose-sm">
                {raw(HtmlSanitizer.sanitize_html(@text.source_text || ""))}
              </div>
            </div>
            <div class="text-xs opacity-50 mt-1">
              {dgettext("localization", "%{count} words", count: @text.word_count || 0)}
            </div>
          </div>

          <%!-- Translation --%>
          <div>
            <h4 class="font-medium text-sm mb-2 opacity-70">
              {dgettext("localization", "Translation")} ({@text.locale_code})
            </h4>
            <.form for={@form} id="translation-form" phx-submit="save_translation">
              <.input
                field={@form[:translated_text]}
                type="textarea"
                rows={6}
                placeholder={dgettext("localization", "Enter translation...")}
              />
              <div class="flex items-center gap-3 mt-3">
                <.input
                  field={@form[:status]}
                  type="select"
                  label={dgettext("localization", "Status")}
                  options={[
                    {dgettext("localization", "Pending"), "pending"},
                    {dgettext("localization", "Draft"), "draft"},
                    {dgettext("localization", "In Progress"), "in_progress"},
                    {dgettext("localization", "Review"), "review"},
                    {dgettext("localization", "Final"), "final"}
                  ]}
                />
              </div>
              <div class="mt-3">
                <.input
                  field={@form[:translator_notes]}
                  type="textarea"
                  label={dgettext("localization", "Translator Notes")}
                  rows={2}
                  placeholder={dgettext("localization", "Add notes for reviewers...")}
                />
              </div>
              <div class="flex items-center gap-3 mt-4">
                <.button variant="primary" phx-disable-with={dgettext("localization", "Saving...")}>
                  {dgettext("localization", "Save")}
                </.button>
                <.button
                  :if={@has_provider}
                  type="button"
                  phx-click="translate_with_deepl"
                  phx-disable-with={dgettext("localization", "Translating...")}
                >
                  <.icon name="sparkles" class="size-4 mr-1" />
                  {dgettext("localization", "Translate with DeepL")}
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Metadata --%>
        <div class="mt-6 text-sm opacity-60">
          <span :if={@text.machine_translated} class="badge badge-sm badge-outline mr-2">
            {dgettext("localization", "Machine translated")}
          </span>
          <span :if={@text.last_translated_at}>
            {dgettext("localization", "Last translated: %{time}",
              time: Calendar.strftime(@text.last_translated_at, "%Y-%m-%d %H:%M")
            )}
          </span>
        </div>
      </div>
    </Layouts.focus>
    """
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
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
        text = Localization.get_text!(String.to_integer(text_id))

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
    with_authorization(socket, :edit_content, fn socket ->
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
    with_authorization(socket, :edit_content, fn socket ->
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
      Storyarn.Localization.LocalizedText.update_changeset(text, %{})

    to_form(changeset, as: "localized_text")
  end
end
