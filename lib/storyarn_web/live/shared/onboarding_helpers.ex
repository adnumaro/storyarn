defmodule StoryarnWeb.Live.Shared.OnboardingHelpers do
  @moduledoc """
  Serializes onboarding state for the shared LiveVue layout boundaries.
  """

  alias Storyarn.Platform

  @spec client_config(Platform.onboarding_summary(), atom() | String.t() | nil, boolean()) :: map() | nil
  def client_config(_summary, nil, _autostart), do: nil

  def client_config(summary, tutorial, autostart) do
    case Platform.cast_onboarding_tutorial(tutorial) do
      {:ok, tutorial} ->
        %{
          guide: Atom.to_string(tutorial),
          autoShow: autostart and Platform.onboarding_pending?(summary, tutorial)
        }

      :error ->
        nil
    end
  end
end
