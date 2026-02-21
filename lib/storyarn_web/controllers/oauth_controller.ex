defmodule StoryarnWeb.OAuthController do
  @moduledoc """
  Handles OAuth callbacks from Ueberauth providers (GitHub, Google, Discord).
  """
  use StoryarnWeb, :controller

  alias Storyarn.Accounts
  alias StoryarnWeb.UserAuth

  plug Ueberauth

  @doc """
  Handles the OAuth callback from providers.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    case Accounts.find_or_create_user_from_oauth(provider, auth) do
      {:ok, user} ->
        conn
        |> put_flash(
          :info,
          dgettext("identity", "Successfully authenticated with %{provider}.", provider: provider)
        )
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_flash(
          :error,
          dgettext("identity", "Could not authenticate: %{errors}", errors: errors)
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => provider}) do
    message = Enum.map_join(failure.errors, ", ", & &1.message)

    conn
    |> put_flash(
      :error,
      dgettext("identity", "Failed to authenticate with %{provider}: %{message}",
        provider: provider,
        message: message
      )
    )
    |> redirect(to: ~p"/users/log-in")
  end

  @doc """
  Initiates the OAuth flow - Ueberauth handles this automatically.
  """
  def request(conn, _params) do
    # Ueberauth handles the redirect automatically
    conn
  end

  @doc """
  Links an OAuth provider to the current user's account.
  """
  def link(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    user = conn.assigns.current_scope.user

    case Accounts.link_oauth_identity(user, provider, auth) do
      {:ok, _identity} ->
        conn
        |> put_flash(
          :info,
          dgettext("identity", "Successfully linked %{provider} account.", provider: provider)
        )
        |> redirect(to: ~p"/users/settings")

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_flash(
          :error,
          dgettext("identity", "Could not link account: %{errors}", errors: errors)
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  def link(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => provider}) do
    message = Enum.map_join(failure.errors, ", ", & &1.message)

    conn
    |> put_flash(
      :error,
      dgettext("identity", "Failed to link %{provider}: %{message}",
        provider: provider,
        message: message
      )
    )
    |> redirect(to: ~p"/users/settings")
  end

  @doc """
  Unlinks an OAuth provider from the current user's account.
  """
  def unlink(conn, %{"provider" => provider}) do
    user = conn.assigns.current_scope.user

    case Accounts.unlink_oauth_identity(user, provider) do
      {:ok, _identity} ->
        conn
        |> put_flash(
          :info,
          dgettext("identity", "Successfully unlinked %{provider} account.", provider: provider)
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :not_found} ->
        conn
        |> put_flash(
          :error,
          dgettext("identity", "No %{provider} account linked.", provider: provider)
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :cannot_unlink_only_auth_method} ->
        conn
        |> put_flash(
          :error,
          dgettext(
            "identity",
            "Cannot unlink your only authentication method. Set a password first."
          )
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
