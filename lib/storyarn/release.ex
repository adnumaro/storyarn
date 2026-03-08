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

    # Ensure user account exists (create + confirm if new)
    case ensure_user_exists(email) do
      {:ok, :existing} ->
        IO.puts("User #{email} already exists, sending invite email")

      {:ok, :created} ->
        IO.puts("Created and confirmed account for #{email}")

      {:error, reason} ->
        IO.puts("Failed to create user: #{inspect(reason)}")
        raise "Cannot invite #{email}: user creation failed"
    end

    login_url = StoryarnWeb.Endpoint.url() <> "/users/log-in"
    {subject, html, text} = Storyarn.Emails.Templates.waitlist_invite(email, login_url)

    {sender_name, sender_email} =
      Application.get_env(:storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"})

    email_struct =
      Swoosh.Email.new()
      |> Swoosh.Email.to(email)
      |> Swoosh.Email.from({sender_name, sender_email})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(html)
      |> Swoosh.Email.text_body(text)

    case Storyarn.Mailer.deliver(email_struct) do
      {:ok, _} -> IO.puts("Invitation sent to #{email}")
      {:error, reason} -> IO.puts("Failed to send: #{inspect(reason)}")
    end
  end

  defp ensure_user_exists(email) do
    case Storyarn.Accounts.get_user_by_email(email) do
      %Storyarn.Accounts.User{} ->
        {:ok, :existing}

      nil ->
        case Storyarn.Accounts.register_user(%{"email" => email}) do
          {:ok, user} ->
            # Auto-confirm so magic link login works (not confirmation flow)
            user
            |> Storyarn.Accounts.User.confirm_changeset()
            |> Storyarn.Repo.update!()

            {:ok, :created}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

end
