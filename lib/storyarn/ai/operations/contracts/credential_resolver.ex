defmodule Storyarn.AI.CredentialResolver do
  @moduledoc "Resolves opaque credential references immediately before provider access."

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @callback resolve(CredentialRef.t(), map()) :: {:ok, ResolvedCredential.t()} | {:error, atom()}
  @callback record_outcome(ResolvedCredential.t(), term()) :: :ok

  def resolve(%CredentialRef{} = ref, context), do: adapter().resolve(ref, context)
  def record_outcome(%ResolvedCredential{} = credential, outcome), do: adapter().record_outcome(credential, outcome)

  defp adapter do
    Application.get_env(:storyarn, __MODULE__, Storyarn.AI.CredentialResolver.Unavailable)
  end
end
