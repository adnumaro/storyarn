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
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Data.ProjectMembershipRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Data.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Access.Data.WorkspaceRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Assets.Data.AssetRecord, except: [:deleted_at, :deleted_by_id])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.AssetRecord, except: [:deleted_at, :deleted_by_id])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.BlockRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.EntityVersionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.FlowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.SheetAvatarRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.SheetRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.TableColumnRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.TableRowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.UserRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Editor.Data.WorkspaceRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.AssetRecord, except: [:deleted_at])

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.FlowConnectionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.FlowNodeRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.FlowRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.SheetAvatarRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.SheetRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Exploration.Data.UserRecord)

  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.Data.ProjectRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.Data.UserRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Scenes.Versioning.EntityVersionRecord)

  # Sheets
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Block)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.BlockGalleryImage)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Sheet)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.SheetAvatar)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableColumn)
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.TableRow)
  # Sheet schemas associate to Sheet-owned persistence records; derive them so
  # a preloaded association cannot turn an encodable struct into a crash. The
  # asset record filters deletion metadata exactly like Storyarn.Projects.Assets.Asset.
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Persistence.AssetRecord, except: [:deleted_at])
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Persistence.ProjectRecord)

  # Versioning
  Protocol.derive(LiveVue.Encoder, Storyarn.Sheets.Versioning.EntityVersionRecord)
  Protocol.derive(LiveVue.Encoder, Storyarn.Projects.Versioning.ProjectSnapshot)

  # Workspaces
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.Workspace)
  Protocol.derive(LiveVue.Encoder, Storyarn.Workspaces.WorkspaceMembership)
end
