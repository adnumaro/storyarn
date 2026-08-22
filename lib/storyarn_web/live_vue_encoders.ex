defmodule StoryarnWeb.LiveVueEncoders do
  @moduledoc """
  Presentation-owned `LiveVue.Encoder` implementations for values passed to
  Vue components.

  The derives live in `StoryarnWeb` so domain contexts remain independent of
  LiveVue while the Web layer explicitly owns their wire representation.
  """

  require Protocol

  # Ecto internals
  Protocol.derive(LiveVue.Encoder, Ecto.Association.NotLoaded)
  Protocol.derive(LiveVue.Encoder, Ecto.Schema.Metadata)

  # Accounts
  Protocol.derive(LiveVue.Encoder, Storyarn.Accounts.User)
  Protocol.derive(LiveVue.Encoder, Storyarn.Accounts.UserToken)

  # Assets
  Protocol.derive(LiveVue.Encoder, Storyarn.Assets.Asset,
    except: [:deleted_at, :deleted_by_id, :deleted_by, :deletion_reason, :deletion_generation]
  )

  # Billing
  Protocol.derive(LiveVue.Encoder, Storyarn.Billing.Subscription)

  # Flows
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.Flow)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.FlowConnection)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.FlowNode, except: [:derivatives_fingerprint])
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.SequenceConfig)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.SequenceVisualLayer)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.VariableReference)
  Protocol.derive(LiveVue.Encoder, Storyarn.Flows.Evaluator.State)

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
end
