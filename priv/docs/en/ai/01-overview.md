%{
title: "AI in Storyarn",
category_label: "AI",
order: 1,
description: "How Storyarn's AI features work: connected provider accounts, AI actions in the command palette, and what runs where.",
feature_flag: :ai_integrations
}

---

Storyarn's AI features are being rolled out gradually. This section documents them as they become available.

## AI provider integrations

Connect your own AI provider accounts (API keys) in **Account settings → AI Integrations**. Opening this page and changing a key requires recent authentication. Keys are validated before saving, encrypted at rest, private to their owner, and revocable at any time.

Connecting a key does not automatically send project data or enable it for a workspace. Each connected provider has a workspace list on that page. Enable only the workspaces where Storyarn may offer that connection as an AI route. The same encrypted key remains attached to your account; Storyarn does not copy or share it with the workspace.

## Personal AI keys

A workspace owner can always assign their own personal connections to a workspace they own. In **Workspace settings → General**, the owner can independently allow or disable **Personal AI for other members**. When enabled, eligible members can assign a supported provider they connected themselves. This policy never gives them access to another person's key.

Connection, workspace assignment, and task consent are separate controls:

1. **Connection:** you store and validate your personal provider key.
2. **Workspace assignment:** you choose where that connection may be offered.
3. **Task consent:** before sending project content, Storyarn shows the provider, model, project-data scope, capability, and cost class.

Consent is specific to the workspace and provider connection. It becomes invalid if you remove the workspace assignment, disconnect the key, the workspace policy changes, or Storyarn updates the disclosure text. Re-enabling a connection requires fresh consent; a previous approval is never silently restored.

- The provider bills your own account. Personal runs never consume Storyarn AI allowance.
- Authorized task content leaves Storyarn and is processed in the provider's infrastructure. Processing location, retention, and possible model-training use depend on your provider account and terms. Storyarn cannot guarantee zero retention or no training for personal keys.
- Your key can only run an action you initiate. It is never shared with another member or used by scheduled automation.
- Storyarn never silently switches between your key and Storyarn AI. You choose the payer and route.
- A provider rejection does not normally disconnect a key. An authentication failure does, because the credential is no longer usable.

Disabling a workspace removes that assignment and revokes its active consents. Disconnecting a provider in **Account settings → AI Integrations** removes all of its workspace assignments and revokes every active consent for that connection. You can also revoke a consent without disconnecting the key when a supported AI action presents that control.

## AI actions

AI actions appear as commands in the command palette as they ship. Each action states what data it sends, who pays, and where its result will appear before it runs. Generated previews remain private to the initiating actor until explicitly applied or attached to the project.
