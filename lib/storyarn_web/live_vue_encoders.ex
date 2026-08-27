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
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.Assets.Asset,
    except: [:deleted_at, :deleted_by_id, :deleted_by, :deletion_reason, :deletion_generation]
  )

  # Billing
  Protocol.derive(LiveVue.Encoder, Storyarn.Platform.Billing.Subscription)

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
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.References.EntityReference)

  # Scenes
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Scene)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneAmbientFlow)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneAnnotation)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneConnection)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneLayer)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.ScenePin)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.SceneZone)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.ExplorationSession)

  # Scenes duplicates consumer-owned read models by capability. Derive every
  # projection that can cross the presentation boundary, including preloaded
  # associations, without coupling StoryarnWeb to a generic persistence layer.
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Projections.ProjectMembershipRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Projections.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Projections.WorkspaceRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Assets.Entities.AssetRecord, except: [:deleted_at, :deleted_by_id])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.AssetRecord, except: [:deleted_at, :deleted_by_id])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.BlockRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.EntityVersionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.FlowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.SheetAvatarRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.SheetRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.TableColumnRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.TableRowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.UserRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Projections.WorkspaceRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.AssetRecord, except: [:deleted_at])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.FlowConnectionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.FlowNodeRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.FlowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.SheetAvatarRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.SheetRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Projections.UserRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.Projections.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.Projections.UserRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.EntityVersionRecord)

  # Sheets
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Block)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.BlockGalleryImage)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Sheet)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.SheetAvatar)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableColumn)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableRow)
  # Sheet schemas associate to Editor-owned read projections; derive them so a
  # preloaded association cannot turn an encodable struct into a crash. The
  # asset projection filters deletion metadata exactly like the owning asset.
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Editor.Projections.AssetRecord, except: [:deleted_at])
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Editor.Projections.ProjectRecord)

  # Versioning
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Versioning.EntityVersionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.Versioning.ProjectSnapshot)

  # Workspaces
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.Workspace)
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.WorkspaceMembership)
end
