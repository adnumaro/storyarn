defmodule StoryarnWeb.Live.Shared.OnboardingHelpers do
  @moduledoc """
  Serializes onboarding state for the shared LiveVue layout boundaries.
  """

  alias Storyarn.Onboarding
  alias Storyarn.Onboarding.TutorialProgress

  @spec client_config(Onboarding.summary(), atom() | String.t() | nil, boolean()) :: map() | nil
  def client_config(_summary, nil, _autostart), do: nil

  def client_config(summary, tutorial, autostart) do
    case TutorialProgress.cast_tutorial(tutorial) do
      {:ok, tutorial} ->
        %{
          guide: Atom.to_string(tutorial),
          autoShow: autostart and Onboarding.pending?(summary, tutorial)
        }

      :error ->
        nil
    end
  end
end
