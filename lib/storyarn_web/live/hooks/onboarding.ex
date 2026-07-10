defmodule StoryarnWeb.Live.Hooks.Onboarding do
  @moduledoc """
  Loads per-user onboarding progress and handles tutorial events for every
  authenticated LiveView without duplicating handlers across tools.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Analytics
  alias Storyarn.Onboarding
  alias Storyarn.Onboarding.TutorialProgress

  @interaction_actions ~w(opened snoozed docs_opened)
  @interaction_sources ~w(auto manual settings)

  def on_mount(:load_onboarding, _params, _session, socket) do
    socket =
      socket
      |> assign(:onboarding, Onboarding.summary(socket.assigns.current_scope))
      |> Phoenix.LiveView.attach_hook(
        :onboarding_events,
        :handle_event,
        &handle_onboarding_event/3
      )

    {:cont, socket}
  end

  defp handle_onboarding_event("complete_onboarding_tutorial", %{"tutorial" => tutorial} = params, socket) do
    source = normalize_source(params["source"])

    case Onboarding.complete_tutorial(socket.assigns.current_scope, tutorial) do
      {:ok, _progress} ->
        Analytics.track(socket.assigns.current_scope, "onboarding tutorial interacted", %{
          action: "completed",
          guide: tutorial,
          source: source
        })

        {:halt,
         assign(
           socket,
           :onboarding,
           Onboarding.summary(socket.assigns.current_scope)
         )}

      {:error, _reason} ->
        {:halt, socket}
    end
  end

  defp handle_onboarding_event(
         "onboarding_tutorial_interaction",
         %{"tutorial" => tutorial, "action" => action} = params,
         socket
       )
       when action in @interaction_actions do
    with {:ok, tutorial} <- TutorialProgress.cast_tutorial(tutorial) do
      Analytics.track(socket.assigns.current_scope, "onboarding tutorial interacted", %{
        action: action,
        guide: Atom.to_string(tutorial),
        source: normalize_source(params["source"])
      })
    end

    {:halt, socket}
  end

  defp handle_onboarding_event(_event, _params, socket), do: {:cont, socket}

  defp normalize_source(source) when source in @interaction_sources, do: source
  defp normalize_source(_source), do: "manual"
end
