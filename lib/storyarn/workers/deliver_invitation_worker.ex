defmodule Storyarn.Workers.DeliverInvitationWorker do
  @moduledoc """
  Delivers project and workspace invitations outside the LiveView request cycle.

  The bearer token is encrypted in the Oban payload. Delivery is skipped when
  the invitation has already been accepted, revoked, replaced, or expired.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Storyarn.Projects.Invitations, as: ProjectInvitations
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workspaces.Invitations, as: WorkspaceInvitations

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"context" => context, "encrypted_token" => encrypted_token, "locale" => locale}} = job) do
    opts = inviter_opts(job.args)

    case decrypt_token(encrypted_token) do
      {:ok, token} ->
        context
        |> deliver_safely(token, opts, locale)
        |> normalize_result(job, context, token)

      {:error, reason} ->
        Logger.warning("Invitation token decryption failed reason=#{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp deliver("project", token, opts), do: ProjectInvitations.deliver_invitation_email(token, opts)

  defp deliver("workspace", token, opts), do: WorkspaceInvitations.deliver_invitation_email(token, opts)

  defp deliver(_context, _token, _opts), do: {:cancel, :invalid_invitation_context}

  defp deliver_safely(context, token, opts, locale) do
    Gettext.with_locale(Storyarn.Gettext, locale, fn ->
      deliver(context, token, opts)
    end)
  rescue
    exception ->
      Logger.error("Invitation email delivery raised: #{Exception.message(exception)}")
      {:error, {:delivery_exception, Exception.message(exception)}}
  catch
    kind, reason ->
      Logger.error("Invitation email delivery failed kind=#{kind} reason=#{inspect(reason)}")
      {:error, {:delivery_failure, kind, reason}}
  end

  defp normalize_result({:ok, _email}, _job, _context, _token), do: :ok
  defp normalize_result({:cancel, reason}, _job, _context, _token), do: {:cancel, reason}

  defp normalize_result({:error, reason}, job, context, token) do
    Logger.warning("Invitation email delivery failed reason=#{inspect(reason)}")

    if job.attempt >= job.max_attempts do
      cancel_invitation(context, token)
      {:cancel, reason}
    else
      {:error, reason}
    end
  end

  defp cancel_invitation("project", token), do: ProjectInvitations.cancel_invitation_delivery(token)

  defp cancel_invitation("workspace", token), do: WorkspaceInvitations.cancel_invitation_delivery(token)

  defp cancel_invitation(_context, _token), do: :ok

  defp decrypt_token(encrypted_token) do
    with {:ok, encrypted_binary} <- Base.decode64(encrypted_token),
         {:ok, token} <- EncryptedBinary.load(encrypted_binary) do
      {:ok, token}
    else
      _ -> {:error, :invalid_invitation_token}
    end
  end

  defp inviter_opts(args) do
    case Map.get(args, "inviter_name") do
      inviter_name when is_binary(inviter_name) -> [inviter_name: inviter_name]
      _ -> []
    end
  end
end
