defmodule StoryarnWeb.Gettext do
  @moduledoc """
  Web-layer Gettext backend.

  Domain-layer code should use `Storyarn.Gettext` instead to avoid
  compile cycles between domain and web layers.
  """
  use Gettext.Backend, otp_app: :storyarn
end
