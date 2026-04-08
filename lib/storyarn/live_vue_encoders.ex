defmodule Storyarn.LiveVueEncoders do
  @moduledoc """
  Derive LiveVue.Encoder for all Ecto schemas so they can be passed as
  props to Vue components without protocol errors.
  """

  require Protocol

  # Elixir stdlib structs
  defimpl LiveVue.Encoder, for: MapSet do
    def encode(map_set, _opts), do: MapSet.to_list(map_set)
  end

  # Ecto internals
  Protocol.derive(LiveVue.Encoder, Ecto.Association.NotLoaded)
  Protocol.derive(LiveVue.Encoder, Ecto.Schema.Metadata)

  # Accounts
  Protocol.derive(LiveVue.Encoder, Storyarn.Accounts.User)
  Protocol.derive(LiveVue.Encoder, Storyarn.Accounts.UserIdentity)
  Protocol.derive(LiveVue.Encoder, Storyarn.Accounts.UserToken)

  # Assets
  Protocol.derive(LiveVue.Encoder, Storyarn.Assets.Asset)

  # Billing
  Protocol.derive(LiveVue.Encoder, Storyarn.Billing.Subscription)

  # Flows
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.Flow)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.FlowConnection)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.FlowNode)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.VariableReference)

  # Localization
  Protocol.derive(LiveVue.Encoder, Storyarn.Localization.GlossaryEntry)
  Protocol.derive(LiveVue.Encoder, Storyarn.Localization.LocalizedText)
  Protocol.derive(LiveVue.Encoder, Storyarn.Localization.ProjectLanguage)
  Protocol.derive(LiveVue.Encoder, Storyarn.Localization.ProviderConfig)

  # Projects
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.Project)
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.ProjectMembership)

  # References
  Protocol.derive(LiveVue.Encoder, Storyarn.References.EntityReference)

  # Scenes
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Scene)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneAmbientFlow)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneAnnotation)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneConnection)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneLayer)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.ScenePin)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneZone)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.ExplorationSession)

  # Screenplays
  Protocol.derive(LiveVue.Encoder, Storyarn.Screenplays.Screenplay)
  Protocol.derive(LiveVue.Encoder, Storyarn.Screenplays.ScreenplayElement)

  # Sheets
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Block)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.BlockGalleryImage)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Sheet)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.SheetAvatar)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableColumn)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableRow)

  # Versioning
  Protocol.derive(LiveVue.Encoder, Storyarn.Versioning.EntityVersion)
  Protocol.derive(LiveVue.Encoder, Storyarn.Versioning.ProjectSnapshot)

  # Workspaces
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.Workspace)
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.WorkspaceMembership)

  # Flows (debug evaluator)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.Evaluator.State)
end
