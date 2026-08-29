defmodule Storyarn.Projects.Access.Adapters.Jobs.InvitationQueue do
  @moduledoc """
  Project-owned adapter for durable invitation delivery.

  It encrypts the bearer token and persists the owner-specific Oban job inside
  the same transaction that creates the invitation.
  """

  alias Storyarn.Platform.Shared.EncryptedBinary
  alias Storyarn.Workers.DeliverProjectInvitationWorker

  require Logger

  @queue "invitation_delivery"

  @spec enqueue(String.t(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(encoded_token, opts \\ []) do
    with {:ok, encrypted_token} <- encrypt_token(encoded_token) do
      %{
        context: "project",
        encrypted_token: encrypted_token,
        inviter_name: Keyword.get(opts, :inviter_name),
        locale: Gettext.get_locale(Storyarn.Gettext)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> DeliverProjectInvitationWorker.new()
      |> Oban.insert()
    end
  end

  @doc "Wakes the Project invitation queue after its enclosing transaction commits."
  @spec wake_after_commit(Oban.Job.t(), keyword()) :: :ok
  def wake_after_commit(%Oban.Job{} = job, opts \\ []) do
    notifier =
      Keyword.get(opts, :queue_notifier, fn payload ->
        Oban.Notifier.notify(Oban, :insert, payload)
      end)

    case safely_notify(notifier) do
      :ok ->
        :ok

      :error ->
        Logger.warning("Project invitation queue wakeup failed after commit job_id=#{job.id}")
    end
  end

  defp encrypt_token(encoded_token) do
    encryptor =
      Application.get_env(:storyarn, :invitation_token_encryptor, EncryptedBinary)

    case encryptor.dump(encoded_token) do
      {:ok, encrypted_token} ->
        {:ok, Base.encode64(encrypted_token)}

      _error ->
        Logger.error("Project invitation token encryption failed")
        {:error, :encryption_unavailable}
    end
  rescue
    error ->
      Logger.error("Project invitation token encryption failed: #{Exception.message(error)}")
      {:error, :encryption_unavailable}
  end

  defp safely_notify(notifier) when is_function(notifier, 1) do
    case notifier.(%{queue: @queue}) do
      :ok -> :ok
      _failure -> :error
    end
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  defp safely_notify(_invalid_notifier), do: :error
end
