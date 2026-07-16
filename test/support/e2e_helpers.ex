defmodule StoryarnWeb.E2EHelpers do
  @moduledoc false

  import PhoenixTest.Playwright, only: [add_session_cookie: 3]

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Onboarding

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  def authenticate(conn, user, opts \\ []) do
    prepare_onboarding(user, Keyword.get(opts, :onboarding, :completed))
    token = Accounts.generate_user_session_token(user)

    if authenticated_at = opts[:token_authenticated_at] do
      Storyarn.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
    end

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  defp prepare_onboarding(user, :pending), do: user

  defp prepare_onboarding(user, :completed) do
    scope = Scope.for_user(user)

    Enum.each(Onboarding.tutorials(), fn tutorial ->
      {:ok, _progress} = Onboarding.complete_tutorial(scope, tutorial)
    end)

    user
  end
end
