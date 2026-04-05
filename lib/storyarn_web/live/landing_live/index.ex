defmodule StoryarnWeb.LandingLive.Index do
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    peer = get_connect_info(socket, :peer_data)
    ip = if peer, do: peer.address |> :inet.ntoa() |> to_string(), else: "unknown"
    socket = assign(socket, ip: ip)

    case socket.assigns do
      %{current_scope: %{user: %Accounts.User{} = user}} ->
        {:ok, redirect_to_workspace(socket, user)}

      _ ->
        {:ok, assign(socket, :page_title, gettext("Storyarn — Narrative Design Platform"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash} current_scope={@current_scope} theme="dark">
      <.vue
        v-component="pages/landing/index"
        v-socket={@socket}
        id="landing-page"
        is-logged-in={!!@current_scope && !!@current_scope.user}
        translations={translations()}
      />
    </Layouts.public>
    """
  end

  @impl true
  def handle_event("join_waitlist", %{"email" => email}, socket) do
    ip = socket.assigns.ip

    case RateLimiter.check_waitlist(ip) do
      :ok ->
        do_join_waitlist(socket, email, ip)

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many requests. Please try again later."))}
    end
  end

  defp do_join_waitlist(socket, email, ip) do
    case Accounts.join_waitlist(%{"email" => email}) do
      {:ok, _entry} ->
        signup_info = %{
          locale: socket.assigns[:locale] || "en",
          accept_language: "unknown",
          ip: ip,
          country: "unknown"
        }

        Accounts.notify_admin_waitlist_signup(email, signup_info)

        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("You're on the list! We'll reach out when your spot is ready.")
         )}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("You're on the list! We'll reach out when your spot is ready.")
         )}
    end
  end

  defp redirect_to_workspace(socket, user) do
    case Workspaces.get_default_workspace(user) do
      %Workspaces.Workspace{slug: slug} ->
        push_navigate(socket, to: ~p"/workspaces/#{slug}")

      nil ->
        push_navigate(socket, to: ~p"/workspaces/new")
    end
  end

  defp translations do
    %{
      # Hero
      private_beta: gettext("Private beta"),
      hero_title_1: gettext("Craft worlds."),
      hero_title_2: gettext("Weave stories."),
      hero_subtitle:
        gettext(
          "The narrative design platform where characters, dialogue, worlds, and localization live in one connected project — from first draft to engine-ready export."
        ),
      explore_storyarn: gettext("Explore Storyarn"),
      see_workflow: gettext("See workflow"),
      watch_demo: gettext("Watch demo"),
      close_video: gettext("Close video"),
      # Features
      features_title: gettext("One platform, everything connected"),
      features_subtitle:
        gettext(
          "Every tool designed to feed the others — so characters, logic, worlds, and translations stay connected instead of scattered across files."
        ),
      feature_1_title: gettext("Sheets as source of truth"),
      feature_1_desc:
        gettext(
          "Characters, factions, quests, and items live in structured sheets with variables, formulas, and inheritance — your single source of truth."
        ),
      feature_2_title: gettext("Flows you can actually play"),
      feature_2_desc:
        gettext(
          "Build branching dialogue, then play it, debug it, and verify it — without ever leaving the editor."
        ),
      feature_3_title: gettext("Scenes with real exploration"),
      feature_3_desc:
        gettext(
          "Place zones, pins, and triggers on a canvas. Walk through the world before it reaches the engine."
        ),
      feature_4_title: gettext("Play it. Debug it. Ship it."),
      feature_4_desc:
        gettext(
          "Experience the story as a player, or step through it with every variable and condition visible."
        ),
      feature_5_title: gettext("Integrated localization"),
      feature_5_desc:
        gettext(
          "Extract lines, translate with DeepL, manage glossaries, and track coverage per language — all from the same project."
        ),
      feature_6_title: gettext("Export for multiple engines"),
      feature_6_desc:
        gettext(
          "Export to Yarn Spinner, Ink, Godot Dialogic, Unity, or Unreal — your narrative data, ready for production."
        ),
      # Discover
      discover_sheets: gettext("Sheets"),
      discover_flows: gettext("Flows"),
      discover_scenes: gettext("Scenes"),
      discover_sheets_title: gettext("Inheritance keeps your world consistent"),
      discover_sheets_desc:
        gettext(
          "Parent and child sheets let you evolve characters, factions, and locations without duplicating structures."
        ),
      discover_sheets_items: [
        gettext("Shared variables and blocks flow down the hierarchy."),
        gettext("Override only what changes — per variant, episode, or region."),
        gettext("Scale the world model without copy-paste.")
      ],
      discover_flows_title: gettext("Visual graphs that stay readable as scope grows"),
      discover_flows_desc:
        gettext(
          "Dialogue, conditions, instructions, and branches in one graph — designed to stay clear even at production scale."
        ),
      discover_flows_items: [
        gettext("Conversations, state changes, and exits — modeled in one surface."),
        gettext("Logic stays connected to project data instead of living in fragments."),
        gettext("From quick sketches to production-scale dialogue graphs.")
      ],
      discover_scenes_title: gettext("Layers and fog keep complex maps readable"),
      discover_scenes_desc:
        gettext(
          "Layers let you stage progression, visibility, and structure without flattening everything into one image."
        ),
      discover_scenes_items: [
        gettext("Layered visibility instead of one overloaded canvas."),
        gettext("Fog of war to communicate progression and discoverability."),
        gettext("Large spaces stay understandable during review and iteration.")
      ],
      # Spotlights
      exploration_title: gettext("Walk through your world before it ships"),
      exploration_desc:
        gettext(
          "Scene exploration mode lets you experience the world as a player — navigate layers, trigger events, and test spatial logic without leaving the editor."
        ),
      exploration_items: [
        gettext("Move through scenes as if playing the game"),
        gettext("Trigger zone events and transitions in real time"),
        gettext("Validate spatial design before engine integration")
      ],
      version_title: gettext("Every change, always recoverable"),
      version_desc:
        gettext(
          "Automatic version snapshots mean you can always go back. Compare any two versions side by side."
        ),
      version_items: [
        gettext("Automatic snapshots on every save"),
        gettext("Side-by-side visual diff for any version"),
        gettext("Restore any previous state in one click")
      ],
      # Workflow
      workflow_title: gettext("From first draft to engine-ready"),
      workflow_subtitle:
        gettext("Storyarn follows your natural workflow — define, write, test, export."),
      workflow_step_1_title: gettext("Define the world"),
      workflow_step_1_desc:
        gettext(
          "Structure characters, locations, items, and factions in sheets with variables, formulas, and inheritance."
        ),
      workflow_step_2_title: gettext("Write and branch"),
      workflow_step_2_desc:
        gettext(
          "Build dialogue flows with conditions, instructions, and branching — all connected to your project data."
        ),
      workflow_step_3_title: gettext("Explore and debug"),
      workflow_step_3_desc:
        gettext(
          "Play through flows, walk through scenes, and step-debug every variable and condition."
        ),
      workflow_step_4_title: gettext("Localize and export"),
      workflow_step_4_desc:
        gettext(
          "Extract lines, translate, and export to Yarn Spinner, Ink, Godot Dialogic, Unity, or Unreal."
        ),
      # CTA
      cta_title: gettext("Start building your next narrative"),
      cta_desc:
        gettext(
          "We're onboarding a small group of narrative designers and game studios. Join the waitlist — we'll reach out when your spot opens."
        ),
      join_waitlist: gettext("Join the waitlist"),
      email_placeholder: gettext("you@studio.com"),
      no_spam: gettext("No spam. We'll only email you when it's time."),
      # Footer
      features: gettext("Features"),
      discover: gettext("Discover"),
      workflow: gettext("Workflow"),
      docs: gettext("Docs"),
      contact: gettext("Contact"),
      footer_tagline: gettext("Open narrative design platform for game developers"),
      private_beta_badge: gettext("Private beta"),
      realtime_collab: gettext("Realtime collaboration"),
      version_snapshots: gettext("Version snapshots")
    }
  end
end
