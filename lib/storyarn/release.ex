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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

end
