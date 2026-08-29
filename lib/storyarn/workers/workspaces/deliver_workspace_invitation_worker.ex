defmodule Storyarn.Workers.DeliverWorkspaceInvitationWorker do
  @moduledoc """
  Delivers Workspace-owned invitations outside the request cycle.

  The bearer token is encrypted in the Oban payload. Delivery is skipped when
  the invitation has already been accepted, revoked, replaced, or expired.
  """

  use Oban.Worker, queue: :invitation_delivery, max_attempts: 5

  alias Storyarn.Platform.Shared.EncryptedBinary
  alias Storyarn.Workspaces

  require Logger

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"context" => "workspace", "encrypted_token" => encrypted_token, "locale" => locale}} = job
      ) do
    opts = inviter_opts(job.args)

    case decrypt_token(encrypted_token) do
      {:ok, token} ->
        token
        |> deliver_safely(opts, locale)
        |> normalize_result(job, token)

      {:error, reason} ->
        Logger.warning("Workspace invitation token decryption failed reason=#{inspect(reason)}")
        {:cancel, reason}
    end
  end

  def perform(%Oban.Job{args: %{"context" => _context}}), do: {:cancel, :invalid_invitation_context}

  defp deliver_safely(token, opts, locale) do
    Gettext.with_locale(Storyarn.Gettext, locale, fn ->
      Workspaces.deliver_invitation_email(token, opts)
    end)
  rescue
    exception ->
      Logger.error("Workspace invitation email delivery raised: #{Exception.message(exception)}")
      {:error, {:delivery_exception, Exception.message(exception)}}
  catch
    kind, reason ->
      Logger.error("Workspace invitation email delivery failed kind=#{kind} reason=#{inspect(reason)}")
      {:error, {:delivery_failure, kind, reason}}
  end

  defp normalize_result({:ok, _email}, _job, _token), do: :ok
  defp normalize_result({:cancel, reason}, _job, _token), do: {:cancel, reason}

  defp normalize_result({:error, reason}, job, token) do
    Logger.warning("Workspace invitation email delivery failed reason=#{inspect(reason)}")

    if job.attempt >= job.max_attempts do
      Workspaces.cancel_invitation_delivery(token)
      {:cancel, reason}
    else
      {:error, reason}
    end
  end

  defp decrypt_token(encrypted_token) do
    with {:ok, encrypted_binary} <- Base.decode64(encrypted_token),
         {:ok, token} <- EncryptedBinary.load(encrypted_binary) do
      {:ok, token}
    else
      _error -> {:error, :invalid_invitation_token}
    end
  end

  defp inviter_opts(args) do
    case Map.get(args, "inviter_name") do
      inviter_name when is_binary(inviter_name) -> [inviter_name: inviter_name]
      _other -> []
    end
  end
end
