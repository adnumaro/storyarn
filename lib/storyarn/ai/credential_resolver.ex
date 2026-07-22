defmodule Storyarn.AI.CredentialResolver do
  @moduledoc "Resolves opaque credential references immediately before provider access."

  alias Storyarn.AI.CredentialRef

  @callback resolve(CredentialRef.t()) :: {:ok, Storyarn.AI.ResolvedCredential.t()} | {:error, atom()}

  def resolve(%CredentialRef{} = ref), do: adapter().resolve(ref)

  defp adapter do
    Application.get_env(:storyarn, __MODULE__, Storyarn.AI.CredentialResolver.Unavailable)
  end
end
