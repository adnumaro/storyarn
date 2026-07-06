defmodule StoryarnWeb.TemplateLive.Index do
  @moduledoc """
  Lists project templates visible to the authenticated user.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.TemplateLive.Helpers

  alias Storyarn.ProjectTemplates

  @impl true
  def mount(_params, _session, socket) do
    templates = ProjectTemplates.list_templates(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign_new(:current_workspace, fn -> nil end)
     |> assign_new(:workspaces, fn -> [] end)
     |> assign(:page_title, dgettext("projects", "Templates"))
     |> assign(:templates, templates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
    >
      <main id="templates-index" class="min-h-dvh bg-base-100 px-6 py-8 lg:px-10">
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-8">
          <header class="flex flex-col gap-3 border-b border-base-300 pb-6 md:flex-row md:items-end md:justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">
                {dgettext("projects", "Project templates")}
              </p>
              <h1 class="text-3xl font-semibold tracking-normal text-base-content">
                {dgettext("projects", "Templates")}
              </h1>
            </div>

            <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">
              {dgettext("workspaces", "Workspaces")}
            </.link>
          </header>

          <section id="my-templates-section" class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {dgettext("projects", "My templates")}
              </h2>
              <span class="badge badge-neutral">{length(private_templates(@templates))}</span>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <%= for template <- private_templates(@templates) do %>
                <.template_card template={template} />
              <% end %>
              <div
                :if={private_templates(@templates) == []}
                id="my-templates-empty"
                class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/60"
              >
                {dgettext("projects", "No private templates yet.")}
              </div>
            </div>
          </section>

          <section id="public-templates-section" class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {dgettext("projects", "Storyarn demos")}
              </h2>
              <span class="badge badge-neutral">{length(public_templates(@templates))}</span>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <%= for template <- public_templates(@templates) do %>
                <.template_card template={template} />
              <% end %>
              <div
                :if={public_templates(@templates) == []}
                id="public-templates-empty"
                class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/60"
              >
                {dgettext("projects", "No public demos available.")}
              </div>
            </div>
          </section>
        </div>
      </main>
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  attr :template, :map, required: true

  defp template_card(assigns) do
    ~H"""
    <article
      id={"template-card-#{@template.id}"}
      class="card border border-base-300 bg-base-100 shadow-sm transition hover:border-base-content/20"
    >
      <div class="card-body gap-4 p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h3 class="truncate text-base font-semibold text-base-content">{@template.name}</h3>
            <p class="mt-1 line-clamp-2 text-sm text-base-content/60">
              {template_description(@template)}
            </p>
          </div>
          <span class={["badge shrink-0", visibility_badge_class(@template.visibility)]}>
            {visibility_label(@template.visibility)}
          </span>
        </div>

        <div class="flex items-center justify-between text-xs text-base-content/60">
          <span>{version_label(@template.current_version)}</span>
          <span>{format_datetime(@template.updated_at)}</span>
        </div>

        <div class="card-actions justify-end">
          <.link navigate={~p"/templates/#{@template.id}"} class="btn btn-primary btn-sm">
            {dgettext("projects", "Open")}
          </.link>
        </div>
      </div>
    </article>
    """
  end

  defp private_templates(templates), do: Enum.filter(templates, &(&1.visibility == "private"))
  defp public_templates(templates), do: Enum.filter(templates, &(&1.visibility == "public"))
end
