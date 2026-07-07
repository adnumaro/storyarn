defmodule StoryarnWeb.LandingLive.Index do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.ProductMetrics.Taxonomy
  alias Storyarn.RateLimiter
  alias Storyarn.Workspaces
  alias StoryarnWeb.ClientIp

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, ip: ClientIp.from_socket(socket))

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
         )
         |> assign(:waitlist_email, nil)}
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
        waitlist-options={Taxonomy.waitlist_options()}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  @impl true
  def handle_event("join_waitlist", %{"email" => _email} = params, socket) do
    ip = socket.assigns.ip

    case RateLimiter.check_waitlist(ip) do
      :ok ->
        do_join_waitlist(socket, params, ip)

      {:error, :rate_limited} ->
        {:reply, %{status: "error", message: gettext("Too many requests. Please try again in about 1 hour.")}, socket}
    end
  end

  def handle_event("save_waitlist_details", params, socket) do
    case socket.assigns[:waitlist_email] do
      email when is_binary(email) ->
        case Accounts.update_waitlist_details(email, params) do
          {:ok, _entry} ->
            {:reply,
             %{
               status: "ok",
               message: gettext("Thanks — this helps us prioritize your invite.")
             }, socket}

          {:error, _reason} ->
            {:reply,
             %{
               status: "error",
               message: gettext("We couldn't save those details. You're still on the waitlist.")
             }, socket}
        end

      _ ->
        {:reply,
         %{
           status: "error",
           message: gettext("Join the waitlist first, then add your details.")
         }, socket}
    end
  end

  defp do_join_waitlist(socket, params, ip) do
    case Accounts.join_waitlist(params) do
      {:ok, entry} ->
        signup_info = %{
          locale: socket.assigns[:locale] || "en",
          accept_language: "unknown",
          ip: ip,
          country: "unknown",
          profession: entry.profession,
          primary_interest: entry.primary_interest,
          discovery_source: entry.discovery_source,
          current_tool: entry.current_tool,
          current_tool_other: entry.current_tool_other
        }

        Accounts.notify_admin_waitlist_signup_async(entry.email, signup_info)

        {:reply, waitlist_success_reply(), assign(socket, :waitlist_email, entry.email)}

      {:error, _changeset} ->
        {:reply, waitlist_success_reply(), socket}
    end
  end

  defp waitlist_success_reply do
    %{status: "ok", message: gettext("You're on the list! We'll reach out when your spot is ready.")}
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
