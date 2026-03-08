defmodule Storyarn.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :storyarn

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Send a waitlist invitation email to the given address.

  Usage from Fly SSH (uses rpc to run inside the live node):
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_waitlist_user(\"user@example.com\")"'
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_waitlist_user(\"user@example.com\", \"es\")"'
  """
  def invite_waitlist_user(email, locale \\ "en") when is_binary(email) do
    Gettext.put_locale(StoryarnWeb.Gettext, locale)

    case Storyarn.Accounts.find_or_register_confirmed_user(email) do
      {:ok, _user} ->
        IO.puts("User account ready for #{email}")

      {:error, reason} ->
        IO.puts("Failed to create user: #{inspect(reason)}")
        raise "Cannot invite #{email}: user creation failed"
    end

    login_url = StoryarnWeb.Endpoint.url() <> "/users/log-in"

    case Storyarn.Accounts.UserNotifier.deliver_waitlist_invite(email, login_url) do
      {:ok, _} -> IO.puts("Invitation sent to #{email}")
      {:error, reason} -> IO.puts("Failed to send: #{inspect(reason)}")
    end
  end

  @project_roles ~w(editor viewer)
  @workspace_roles ~w(admin member viewer)

  @doc """
  Approve a member invitation request.

  Creates an invitation record and sends the invitation email to the invitee.
  The invitee must click the acceptance link to create their account and join.

  Usage from Fly SSH (uses rpc to run inside the live node):
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"project\\", 123, \\"editor\\", \\"es\\")"'
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"user@example.com\\", \\"workspace\\", 456, \\"member\\", \\"en\\")"'
  """
  def invite_member(email, type, entity_id, role, locale \\ "en")
      when is_binary(email) and type in ["project", "workspace"] do
    allowed_roles = if type == "project", do: @project_roles, else: @workspace_roles

    unless role in allowed_roles do
      raise ArgumentError,
            "Invalid role #{inspect(role)} for #{type}. Allowed: #{inspect(allowed_roles)}"
    end

    Gettext.put_locale(StoryarnWeb.Gettext, locale)

    email = String.downcase(email)

    {context_module, entity} = invitation_config(type, entity_id)

    case context_module.create_admin_invitation(entity, email, role) do
      {:ok, _invitation} ->
        IO.puts(
          "Invitation created and email sent to #{email} as #{role} to #{type} ##{entity_id}"
        )

      {:error, :already_member} ->
        IO.puts("#{email} is already a member of this #{type}")

      {:error, reason} ->
        IO.puts("Failed to create invitation: #{inspect(reason)}")
        raise "Cannot create invitation: #{inspect(reason)}"
    end
  end

  defp invitation_config("project", id) do
    {Storyarn.Projects, Storyarn.Projects.get_project!(id)}
  end

  defp invitation_config("workspace", id) do
    {Storyarn.Workspaces, Storyarn.Workspaces.get_workspace!(id)}
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
