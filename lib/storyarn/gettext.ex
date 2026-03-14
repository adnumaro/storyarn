defmodule Storyarn.Gettext do
  @moduledoc """
  Gettext backend for the Storyarn application.

  Lives in the domain layer so both `lib/storyarn` and `lib/storyarn_web`
  can depend on it without creating a compile cycle.

      use Gettext, backend: Storyarn.Gettext
  """
  use Gettext.Backend, otp_app: :storyarn
end
