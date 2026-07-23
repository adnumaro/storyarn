defmodule Storyarn.AI.CredentialResolver.Composite do
  @moduledoc "Dispatches credential references by lane without allowing cross-lane fallback."
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: kind} = ref, context) do
    case Map.get(adapters(), kind) do
      adapter when is_atom(adapter) -> adapter.resolve(ref, context)
      _missing -> {:error, :credential_unavailable}
    end
  end

  @impl true
  def record_outcome(%ResolvedCredential{kind: kind} = credential, outcome) do
    case Map.get(adapters(), kind) do
      adapter when is_atom(adapter) -> adapter.record_outcome(credential, outcome)
      _missing -> :ok
    end
  end

  defp adapters do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:adapters, %{})
  end
end
