defmodule Storyarn.FeatureFlags do
  @moduledoc """
  Thin wrapper around FunWithFlags with per-user targeting.

  Flag names are atoms. The `@known_flags` list is the single source of truth
  for which flags the application understands — the admin UI and audit code
  iterate over it, and any typo in `enabled?/2` is caught by dialyzer via the
  `flag()` type below.

  Flags default to disabled. Enable per-user during beta via:

      iex> user = Storyarn.Accounts.get_user!(1)
      iex> FunWithFlags.enable(:ai_integrations, for_actor: user)

  Or globally (all users) via:

      iex> FunWithFlags.enable(:ai_integrations)
  """

  @known_flags [:ai_integrations]

  @type flag :: :ai_integrations

  @doc "List of flags known to the application."
  @spec known_flags() :: [flag()]
  def known_flags, do: @known_flags

  @doc """
  Returns whether `flag` is enabled, optionally scoped to a target actor.

  When `:for` is `nil`, the global toggle is checked. When `:for` is a struct
  implementing the `FunWithFlags.Actor` protocol (currently
  `Storyarn.Accounts.User`), per-user targeting is applied.
  """
  @spec enabled?(flag(), keyword()) :: boolean()
  def enabled?(flag, opts \\ []) when flag in @known_flags do
    case Keyword.get(opts, :for) do
      nil -> FunWithFlags.enabled?(flag)
      actor -> FunWithFlags.enabled?(flag, for: actor)
    end
  end
end
