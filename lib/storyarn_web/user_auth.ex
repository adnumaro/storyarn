defmodule StoryarnWeb.UserAuth do
  @moduledoc """
  Plugs and functions for user authentication and session management.
  """
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Controller
  import Plug.Conn

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Workspaces

  @locales Gettext.known_locales(Storyarn.Gettext)
  @default_locale "en"

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_storyarn_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax",
    secure: Application.compile_env(:storyarn, [StoryarnWeb.Endpoint, :force_ssl]) != nil,
    http_only: true
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7
  @sudo_mode_minutes -20
  @sudo_grant_max_age 20 * 60
  @sudo_grant_salt "storyarn sudo access grant"
  @sudo_grant_param "sudo_grant"
  @sudo_handoff_max_age 60
  @sudo_handoff_salt "storyarn sudo session handoff"

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      StoryarnWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: "/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true), do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      StoryarnWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Assigns current_scope and
      redirects authenticated users away from public-only auth pages.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule StoryarnWeb.PageLive do
        use StoryarnWeb, :live_view

        on_mount {StoryarnWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{StoryarnWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          dgettext("identity", "You must log in to access this page.")
        )
        |> Phoenix.LiveView.redirect(to: "/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    case socket.assigns.current_scope do
      %Scope{user: %Accounts.User{} = user} ->
        socket = Phoenix.LiveView.redirect(socket, to: signed_in_path(user))
        {:halt, socket}

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:require_sudo_mode, params, session, socket) do
    on_mount({:require_sudo_mode, "/users/settings"}, params, session, socket)
  end

  def on_mount({:require_sudo_mode, return_to_provider}, params, session, socket) do
    socket = mount_current_scope(socket, session)

    user = socket.assigns.current_scope.user
    session_token = session["user_token"]
    supplied_grant = params[@sudo_grant_param]

    case authorize_sudo(user, session_token, supplied_grant) do
      {:ok, valid_grant} ->
        {:cont,
         Phoenix.Component.assign(socket,
           sudo_grant: valid_grant,
           sudo_session_token: session_token
         )}

      :error ->
        return_to = resolve_sudo_return_to(return_to_provider, params, socket)

        socket =
          Phoenix.LiveView.push_navigate(socket,
            to: sudo_confirmation_path(return_to),
            replace: true
          )

        {:halt, socket}
    end
  end

  # Loads workspaces for the current user into socket assigns.
  # This is used to populate the sidebar with the user's workspaces.
  # Should be called after mount_current_scope.
  def on_mount(:load_workspaces, _params, _session, socket) do
    socket = load_workspaces(socket)
    {:cont, socket}
  end

  defp mount_current_scope(socket, session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn ->
        {user, _} =
          if user_token = session["user_token"] do
            Accounts.get_user_by_session_token(user_token)
          end || {nil, nil}

        Scope.for_user(user)
      end)

    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    locale =
      (user && user.locale) ||
        case session["locale"] do
          l when l in @locales -> l
          _ -> nil
        end ||
        @default_locale

    Gettext.put_locale(Storyarn.Gettext, locale)
    put_error_tracking_context(user)

    Phoenix.Component.assign(socket, :locale, locale)
  end

  defp put_error_tracking_context(%Accounts.User{id: user_id}) do
    PostHog.set_context(%{distinct_id: "user:#{user_id}"})
  end

  defp put_error_tracking_context(_user), do: :ok

  defp load_workspaces(socket) do
    if socket.assigns[:current_scope] && socket.assigns.current_scope.user do
      scope = socket.assigns.current_scope
      workspace_data = Workspaces.list_workspaces(scope)
      workspaces = Enum.map(workspace_data, & &1.workspace)

      managed_slugs =
        workspace_data
        |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_settings))
        |> MapSet.new(& &1.workspace.slug)

      general_slugs =
        workspace_data
        |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_general_settings))
        |> MapSet.new(& &1.workspace.slug)

      socket
      |> Phoenix.Component.assign(:workspaces, workspaces)
      |> Phoenix.Component.assign(:managed_workspace_slugs, managed_slugs)
      |> Phoenix.Component.assign(:general_workspace_slugs, general_slugs)
      |> Phoenix.Component.assign_new(:current_workspace, fn -> nil end)
    else
      socket
      |> Phoenix.Component.assign(:workspaces, [])
      |> Phoenix.Component.assign(:managed_workspace_slugs, MapSet.new())
      |> Phoenix.Component.assign(:general_workspace_slugs, MapSet.new())
      |> Phoenix.Component.assign_new(:current_workspace, fn -> nil end)
    end
  end

  @doc "Returns the path to redirect to after log in."
  def signed_in_path(%Accounts.User{} = user) do
    case Workspaces.get_default_workspace(user) do
      %Workspaces.Workspace{slug: slug} -> "/workspaces/#{slug}"
      nil -> "/workspaces/new"
    end
  end

  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{} = user}}}) do
    signed_in_path(user)
  end

  def signed_in_path(_), do: "/"

  @doc "Returns whether the user's most recent authentication is inside the web sudo window."
  def sudo_mode?(user), do: Accounts.sudo_mode?(user, @sudo_mode_minutes)

  @doc "Issues a 20-minute sudo grant bound to one user and one session token."
  def issue_sudo_grant(%Accounts.User{id: user_id}, session_token, opts \\ []) when is_binary(session_token) do
    payload = {:sudo_grant, user_id, session_fingerprint(session_token)}
    token_opts = [max_age: @sudo_grant_max_age] ++ Keyword.take(opts, [:signed_at])

    Phoenix.Token.sign(StoryarnWeb.Endpoint, @sudo_grant_salt, payload, token_opts)
  end

  @doc "Authorizes sudo mode using either recent authentication or a valid signed grant."
  def authorize_sudo(%Accounts.User{} = user, session_token, grant) when is_binary(session_token) do
    scope = Scope.for_user(user)

    if Accounts.session_token_active?(scope, session_token) do
      cond do
        signed_sudo_grant_matches?(grant, user, session_token) -> {:ok, grant}
        sudo_mode?(user) -> {:ok, nil}
        true -> :error
      end
    else
      :error
    end
  end

  def authorize_sudo(_user, _session_token, _grant), do: :error

  @doc "Returns whether the supplied signed grant is valid for this active session."
  def sudo_grant_valid?(%Accounts.User{} = user, session_token, grant) when is_binary(session_token) do
    Accounts.session_token_active?(Scope.for_user(user), session_token) and
      signed_sudo_grant_matches?(grant, user, session_token)
  end

  def sudo_grant_valid?(_user, _session_token, _grant), do: false

  @doc "Issues a short-lived handoff that may rotate only the current session after password confirmation."
  def issue_sudo_handoff(%Accounts.User{id: user_id} = user, session_token) when is_binary(session_token) do
    nonce = Accounts.generate_sudo_handoff_nonce(user)
    payload = {:sudo_handoff, user_id, session_fingerprint(session_token), nonce}

    Phoenix.Token.sign(StoryarnWeb.Endpoint, @sudo_handoff_salt, payload, max_age: @sudo_handoff_max_age)
  end

  @doc "Returns whether the supplied sudo handoff is valid for this active session."
  def sudo_handoff_valid?(%Accounts.User{} = user, session_token, handoff) when is_binary(session_token) do
    scope = Scope.for_user(user)

    with true <- Accounts.session_token_active?(scope, session_token),
         {:ok, nonce} <- signed_sudo_handoff_nonce(handoff, user, session_token) do
      Accounts.sudo_handoff_nonce_active?(scope, nonce)
    else
      _invalid -> false
    end
  end

  def sudo_handoff_valid?(_user, _session_token, _handoff), do: false

  @doc "Atomically consumes a valid handoff so one password confirmation rotates at most one session."
  def consume_sudo_handoff(%Accounts.User{} = user, session_token, handoff) when is_binary(session_token) do
    scope = Scope.for_user(user)

    with true <- Accounts.session_token_active?(scope, session_token),
         {:ok, nonce} <- signed_sudo_handoff_nonce(handoff, user, session_token),
         :ok <- Accounts.consume_sudo_handoff_nonce(scope, nonce) do
      :ok
    else
      _invalid -> :error
    end
  end

  def consume_sudo_handoff(_user, _session_token, _handoff), do: :error

  @doc "Adds or replaces the sudo grant query parameter on a local settings path."
  def with_sudo_grant(path, grant) when is_binary(path) and is_binary(grant) do
    path = safe_sudo_return_to(path) || "/users/settings"
    put_sudo_grant_query(path, grant)
  rescue
    ArgumentError -> put_sudo_grant_query("/users/settings", grant)
  end

  def with_sudo_grant(path, _grant), do: path

  defp put_sudo_grant_query(path, grant) do
    uri = URI.parse(path)

    query =
      uri.query
      |> decode_query()
      |> Map.put(@sudo_grant_param, grant)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  @doc """
  Returns a settings path when it is safe to use as a sudo-mode return target.

  Sudo re-authentication only accepts local paths inside `/users/settings`.
  """
  def safe_sudo_return_to(return_to) when is_binary(return_to) do
    uri = URI.parse(return_to)

    if safe_sudo_uri?(uri, return_to), do: return_to
  rescue
    ArgumentError -> nil
  end

  def safe_sudo_return_to(_return_to), do: nil

  @doc "Returns the confirm-access path for a validated settings destination."
  def sudo_confirmation_path(return_to) do
    return_to = safe_sudo_return_to(return_to) || "/users/settings"
    "/users/confirm-access?" <> URI.encode_query(%{"return_to" => return_to})
  end

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, dgettext("identity", "You must log in to access this page."))
      |> maybe_store_return_to()
      |> redirect(to: "/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp resolve_sudo_return_to(return_to, _params, _socket) when is_binary(return_to) do
    safe_sudo_return_to(return_to) || "/users/settings"
  end

  defp resolve_sudo_return_to(provider, params, socket) when is_atom(provider) do
    live_action = socket.assigns[:live_action]

    params
    |> provider.sudo_return_to(live_action)
    |> safe_sudo_return_to()
    |> Kernel.||("/users/settings")
  end

  defp safe_sudo_uri?(%URI{scheme: nil, host: nil, userinfo: nil, path: path}, return_to) when is_binary(path) do
    String.starts_with?(return_to, "/") and
      not String.starts_with?(return_to, "//") and
      settings_path?(path) and
      not unsafe_decoded_path?(path)
  end

  defp safe_sudo_uri?(_uri, _return_to), do: false

  defp settings_path?(path) do
    path == "/users/settings" or String.starts_with?(path, "/users/settings/")
  end

  defp unsafe_decoded_path?(path) do
    decoded_path = URI.decode(path)

    String.contains?(decoded_path, ["\\", "\0", "\r", "\n"]) or
      decoded_path
      |> String.split("/", trim: true)
      |> Enum.any?(&(&1 in [".", ".."]))
  end

  defp signed_sudo_grant_matches?(grant, %Accounts.User{id: user_id}, session_token) when is_binary(grant) do
    expected_fingerprint = session_fingerprint(session_token)

    case Phoenix.Token.verify(StoryarnWeb.Endpoint, @sudo_grant_salt, grant, max_age: @sudo_grant_max_age) do
      {:ok, {:sudo_grant, ^user_id, fingerprint}}
      when is_binary(fingerprint) and byte_size(fingerprint) == byte_size(expected_fingerprint) ->
        Plug.Crypto.secure_compare(fingerprint, expected_fingerprint)

      _ ->
        false
    end
  end

  defp signed_sudo_grant_matches?(_grant, _user, _session_token), do: false

  defp signed_sudo_handoff_nonce(handoff, %Accounts.User{id: user_id}, session_token) when is_binary(handoff) do
    expected_fingerprint = session_fingerprint(session_token)

    case Phoenix.Token.verify(StoryarnWeb.Endpoint, @sudo_handoff_salt, handoff, max_age: @sudo_handoff_max_age) do
      {:ok, {:sudo_handoff, ^user_id, fingerprint, nonce}}
      when is_binary(fingerprint) and byte_size(fingerprint) == byte_size(expected_fingerprint) and is_binary(nonce) ->
        if Plug.Crypto.secure_compare(fingerprint, expected_fingerprint),
          do: {:ok, nonce},
          else: :error

      _ ->
        :error
    end
  end

  defp signed_sudo_handoff_nonce(_handoff, _user, _session_token), do: :error

  defp session_fingerprint(session_token), do: :crypto.hash(:sha256, session_token)

  defp decode_query(nil), do: %{}
  defp decode_query(""), do: %{}
  defp decode_query(query), do: URI.decode_query(query)
end
