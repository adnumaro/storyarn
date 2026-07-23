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

Connect your own AI provider accounts (API keys) in **Account settings → AI Integrations**. The catalog shows connected and available providers; select one to open its configuration. Opening these settings and changing a key requires recent authentication. Keys are validated before saving, encrypted at rest, private to their owner, and revocable at any time.

Connecting a key does not automatically send project data or enable it for a workspace. Each provider's detail screen has a searchable workspace list. Enable only the workspaces where Storyarn may offer that connection as an AI route. The same encrypted key remains attached to your account and can serve several workspaces; Storyarn does not copy or share it with a workspace.

Replacing a key is an in-place rotation: Storyarn validates the candidate before changing the stored credential. A rejected candidate leaves the previous key active. If a valid replacement no longer exposes a selected model, the affected role remains visible as a repair state instead of being silently changed.

## Personal AI keys

A workspace owner can always assign their own personal connections to a workspace they own. In **Workspace settings → General**, the owner can independently allow or disable **Personal AI for other members**. When enabled, eligible members can assign a supported provider they connected themselves. This policy never gives them access to another person's key.

Connection, workspace assignment, role primary, and task consent are separate controls:

1. **Connection:** you store and validate your personal provider key.
2. **Workspace assignment:** you choose where that connection may be offered.
3. **Role primary:** in **Account settings → My AI Team**, you first see all your workspaces and their per-role models; when configuring one, you choose one provider and primary model for each available role in that workspace.
4. **Task consent:** before sending project content, Storyarn shows the provider, model, project-data scope, capability, and cost class.

My AI Team has four roles: **General assistant**, **Writing assistant**,
**Illustrator**, and **Voice**. General assistant is used for explicit, bounded
work such as summaries, analysis explanations, text-to-structure, and supported
command-palette actions. Writing assistant is used for dialogue transformations
and editor suggestions. Choose **Configure** from a workspace row to edit that
workspace. The editor is fixed to that workspace and has no workspace selector;
return to the overview to open another workspace.

The same provider connection may use different primary models for the same role in different workspaces. There is no generic personal default. An unconfigured or broken role asks you to choose or repair it; Storyarn never substitutes another model, provider, payer, or workspace automatically.

Storyarn ships its own reviewed model catalog, so you do not configure model
identifiers through deployment settings. A provider's full model list is not
enabled automatically, and the list available to your key may be smaller
depending on its account, region, or plan.

The catalog distinguishes **Executable** models from **Configuration only**
models. Text models offered for General assistant and Writing assistant have a
validated execution adapter. Current image and speech models may appear so you
can prepare Illustrator and Voice, but they are labelled **Configuration only**
and cannot run, request task consent, or make a generation request with your
provider key until Storyarn ships and validates the image or speech tool.
Selecting one saves only that future preference; it does not make the model
executable.

Consent is specific to the workspace and provider connection. It becomes invalid if you remove the workspace assignment, disconnect the key, the workspace policy changes, or Storyarn updates the disclosure text. Re-enabling a connection requires fresh consent; a previous approval is never silently restored.

- The provider bills your own account. Personal runs never consume Storyarn AI allowance.
- Authorized task content leaves Storyarn and is processed in the provider's infrastructure. Processing location, retention, and possible model-training use depend on your provider account and terms. Storyarn cannot guarantee zero retention or no training for personal keys.
- Your key can only run an action you initiate. It is never shared with another member or used by scheduled automation.
- Storyarn never silently switches between your key and Storyarn AI. You choose the payer and route.
- A provider rejection does not normally disconnect a key. An authentication failure does, because the credential is no longer usable.

Disabling a workspace removes that assignment and revokes its active consents. Disconnecting a provider in **Account settings → AI Integrations** removes all of its workspace assignments and revokes every active consent for that connection. Affected role primaries remain visible in **My AI Team** so you can repair them. You can also revoke a consent without disconnecting the key when a supported AI action presents that control.

## AI actions

AI actions appear as commands in the command palette as they ship. Each action states what data it sends, who pays, and where its result will appear before it runs. Generated previews remain private to the initiating actor until explicitly applied or attached to the project.

If Storyarn AI allowance is exhausted, the managed action does not run. When you
have a compatible personal route, Storyarn may offer **Use my own API key**.
Choosing it opens the personal data and provider-billing disclosure; a separate
personal run starts only after you grant the current task consent. Storyarn
never changes the payer, provider, model, key, or route automatically.
