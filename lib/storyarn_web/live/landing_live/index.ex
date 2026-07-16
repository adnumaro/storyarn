defmodule StoryarnWeb.LandingLive.Index do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Workspaces
  alias StoryarnWeb.PublicSEO
  alias StoryarnWeb.PublicURLs

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns do
      %{current_scope: %{user: %Accounts.User{} = user}} ->
        {:ok, redirect_to_workspace(socket, user)}

      _ ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    title = dgettext("public", "Storyarn — Narrative Design Platform for Video Games")

    description =
      dgettext(
        "public",
        "Storyarn is a narrative design platform and video game design platform for branching dialogue, worldbuilding, scenes, localization, debugging, and engine-ready export."
      )

    {:noreply, assign(socket, PublicSEO.static_page_metadata(socket.assigns.locale, :home, title, description))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      seo_metadata={@seo_metadata}
      current_scope={@current_scope}
      language_links={@language_links}
      theme="dark"
      landing
    >
      <section
        id="landing-seo-summary"
        class="sr-only"
        aria-label={dgettext("public", "Storyarn overview")}
      >
        <h1>{dgettext("public", "Storyarn: narrative design platform for video games")}</h1>
        <p>
          {dgettext(
            "public",
            "Storyarn is a video game design platform for narrative designers, game designers, writers, and small studios. It connects worldbuilding sheets, branching dialogue flows, scenes, localization, debugging, and export in one production-ready workspace."
          )}
        </p>
        <p>
          {dgettext(
            "public",
            "Use Storyarn to design interactive stories, test game narrative logic, manage dialogue and variables, map worlds with scenes, localize content, and export to Yarn Spinner, Ink, Godot Dialogic, Unity, and Unreal."
          )}
        </p>
        <h2>{dgettext("public", "Game design platform features")}</h2>
        <ul>
          <li>{dgettext("public", "Branching dialogue and narrative flow editor")}</li>
          <li>
            {dgettext(
              "public",
              "Worldbuilding sheets for characters, places, items, factions, and quests"
            )}
          </li>
          <li>
            {dgettext("public", "Scene maps for spatial narrative design and exploration")}
          </li>
          <li>
            {dgettext("public", "Localization workflow for game dialogue and story content")}
          </li>
          <li>
            {dgettext("public", "Debugging and player preview for interactive narrative logic")}
          </li>
          <li>{dgettext("public", "Export for common game engines and narrative runtimes")}</li>
        </ul>
        <nav aria-label={dgettext("public", "Storyarn documentation")}>
          <.link navigate={PublicURLs.docs_path(@locale, "welcome", "what-is-storyarn")}>
            {dgettext("public", "What is Storyarn?")}
          </.link>
          <.link navigate={PublicURLs.docs_path(@locale, "narrative-design", "flows-overview")}>
            {dgettext("public", "Narrative design flows")}
          </.link>
          <.link navigate={PublicURLs.docs_path(@locale, "import-export", "import-export-overview")}>
            {dgettext("public", "Game engine export")}
          </.link>
        </nav>
      </section>
      <.vue
        v-component="live/public/landing/PublicLanding"
        v-socket={@socket}
        id="landing-page"
        is-logged-in={!!@current_scope && !!@current_scope.user}
        registration-url={PublicURLs.locale_handoff_path(~p"/users/register", @locale)}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp redirect_to_workspace(socket, user) do
    case Workspaces.get_default_workspace(user) do
      %Workspaces.Workspace{slug: slug} ->
        push_navigate(socket, to: ~p"/workspaces/#{slug}")

      nil ->
        push_navigate(socket, to: ~p"/workspaces/new")
    end
  end
end
