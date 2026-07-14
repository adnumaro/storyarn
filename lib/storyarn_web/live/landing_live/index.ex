defmodule StoryarnWeb.LandingLive.Index do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns do
      %{current_scope: %{user: %Accounts.User{} = user}} ->
        {:ok, redirect_to_workspace(socket, user)}

      _ ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Storyarn — Narrative Design Platform for Video Games"))
         |> assign(
           :seo_description,
           gettext(
             "Storyarn is a narrative design platform and video game design platform for branching dialogue, worldbuilding, scenes, localization, debugging, and engine-ready export."
           )
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      theme="dark"
    >
      <section id="landing-seo-summary" class="sr-only" aria-label={gettext("Storyarn overview")}>
        <h1>{gettext("Storyarn: narrative design platform for video games")}</h1>
        <p>
          {gettext(
            "Storyarn is a video game design platform for narrative designers, game designers, writers, and small studios. It connects worldbuilding sheets, branching dialogue flows, scenes, localization, debugging, and export in one production-ready workspace."
          )}
        </p>
        <p>
          {gettext(
            "Use Storyarn to design interactive stories, test game narrative logic, manage dialogue and variables, map worlds with scenes, localize content, and export to Yarn Spinner, Ink, Godot Dialogic, Unity, and Unreal."
          )}
        </p>
        <h2>{gettext("Game design platform features")}</h2>
        <ul>
          <li>{gettext("Branching dialogue and narrative flow editor")}</li>
          <li>
            {gettext("Worldbuilding sheets for characters, places, items, factions, and quests")}
          </li>
          <li>{gettext("Scene maps for spatial narrative design and exploration")}</li>
          <li>{gettext("Localization workflow for game dialogue and story content")}</li>
          <li>{gettext("Debugging and player preview for interactive narrative logic")}</li>
          <li>{gettext("Export for common game engines and narrative runtimes")}</li>
        </ul>
        <nav aria-label={gettext("Storyarn documentation")}>
          <a href={~p"/docs/welcome/what-is-storyarn"}>{gettext("What is Storyarn?")}</a>
          <a href={~p"/docs/narrative-design/flows-overview"}>{gettext("Narrative design flows")}</a>
          <a href={~p"/docs/import-export/import-export-overview"}>{gettext("Game engine export")}</a>
        </nav>
      </section>
      <.vue
        v-component="live/public/landing/PublicLanding"
        v-socket={@socket}
        v-inject="public-layout"
        id="landing-page"
        is-logged-in={!!@current_scope && !!@current_scope.user}
        registration-url={~p"/users/register"}
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
