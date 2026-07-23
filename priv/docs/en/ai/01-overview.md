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

Connecting a key does not automatically send project data or enable it for a workspace.

## Personal AI keys

A workspace owner can independently allow or disable **Personal AI keys** in **Workspace settings → General**. When enabled, eligible members can explicitly choose a supported provider they connected themselves.

Before Storyarn issues a personal route, it shows the provider, model, project-data scope, capability and cost class. You must consent for that workspace and provider connection. The consent becomes invalid if you disconnect the key, the workspace policy changes, or Storyarn updates the disclosure text.

- The provider bills your own account. Personal runs never consume Storyarn AI allowance.
- Authorized task content leaves Storyarn and is processed in the provider's infrastructure. Its location and retention depend on your provider account and terms.
- Your key can only run an action you initiate. It is never shared with another member or used by scheduled automation.
- Storyarn never silently switches between your key and Storyarn AI. You choose the payer and route.
- A provider rejection does not normally disconnect a key. An authentication failure does, because the credential is no longer usable.

Disconnecting a provider in **Account settings → AI Integrations** revokes every active consent for that connection. You can also revoke a consent without disconnecting the key when a supported AI action presents that control.

## AI actions

AI actions appear as commands in the command palette as they ship. Each action states what data it sends, who pays, and where its result will appear before it runs. Generated previews remain private to the initiating actor until explicitly applied or attached to the project.
