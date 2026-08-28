defmodule Storyarn.Workspaces.Invitations.Tokens.Issuer do
  @moduledoc false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Platform.Shared.TokenGenerator
  alias Storyarn.Workspaces.Invitations.Rules.Policy
  alias Storyarn.Workspaces.WorkspaceInvitation

  def issue(parent, invited_by, email, role \\ Policy.default_role()) do
    {encoded_token, hashed_token} = TokenGenerator.build_hashed_token()
    invited_by_id = if invited_by, do: invited_by.id

    invitation = %WorkspaceInvitation{
      workspace_id: parent.id,
      invited_by_id: invited_by_id,
      email: String.downcase(email),
      token: hashed_token,
      role: role,
      expires_at: Policy.expires_at(TimeHelpers.now())
    }

    {encoded_token, invitation}
  end

  defdelegate decode_and_hash(token), to: TokenGenerator
end
