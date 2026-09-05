defmodule StoryarnWeb.E2EHelpers do
  @moduledoc false

  import PhoenixTest.Playwright, only: [add_session_cookie: 3, evaluate: 3]

  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page
  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.Onboarding

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

  def right_click(session, selector) do
    {:ok, _} = Frame.click(session.frame_id, selector: selector, button: "right", timeout: 10_000)
    session
  end

  def click_at(session, selector, x, y) do
    {:ok, _} =
      Frame.click(session.frame_id,
        selector: selector,
        position: %{x: x, y: y},
        timeout: 10_000
      )

    session
  end

  def hover_pin(session, selector) do
    {:ok, _} = Frame.hover(session.frame_id, selector: selector, timeout: 10_000)
    session
  end

  def drag_pin(session, selector, dx, dy) do
    session
    |> hover_pin(selector)
    |> evaluate("document.querySelector(#{Jason.encode!(selector)}).getBoundingClientRect().toJSON()", fn box ->
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)

      {:ok, _} =
        Page.mouse_move(session.page_id,
          x: box["x"] + box["width"] / 2 + dx,
          y: box["y"] + box["height"] / 2 + dy,
          steps: 5,
          timeout: 10_000
        )

      {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)
    end)
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
