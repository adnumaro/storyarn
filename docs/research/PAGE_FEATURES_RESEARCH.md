# Page Features Research: Media, References, Version Control, Collaboration

> **Date:** February 2026 (Updated)
> **Scope:** Analysis of how creative tools handle media management, reference tracking, version control, history, and collaboration features.

> **Changelog:**
> - **February 2026:** Major update across all sections. Added Automerge 3.0, Loro, Eg-walker algorithm, local-first movement coverage. Updated articy:draft (macOS, ElevenLabs VO Extension), Arcweave (Version History beta), Notion (3.0/3.2, offline, agents), Figma (Config 2025, Eg-walker). Added Blueberry AI, P4 DAM, P4 One, StoryFlow Editor, Velt SDK. Updated comparison tables and references throughout.
> - **February 2024:** Initial research document.

---

## Table of Contents

1. [Media & Asset Management](#1-media--asset-management)
2. [Reference & Backlink Systems](#2-reference--backlink-systems)
3. [Version Control & History](#3-version-control--history)
4. [Real-Time Collaboration](#4-real-time-collaboration)
5. [Comments & Feedback](#5-comments--feedback)
6. [Audit Logs & Activity Tracking](#6-audit-logs--activity-tracking)
7. [Tool-by-Tool Analysis](#7-tool-by-tool-analysis)
8. [User Pain Points](#8-user-pain-points)
9. [References](#9-references)

---

## 1. Media & Asset Management

### 1.1 Industry Context

Digital Asset Management (DAM) systems are indispensable tools in the game development industry. Game studios waste 15–20% of their budget on redundant work caused by poor asset management (Source: Gamasutra).

**Common Problems Without Proper DAM:**
- Version control issues
- Lost files
- Duplicated effort
- Disorganized workflows
- Developers working on outdated assets

### 1.2 articy:draft Asset System

**Import Process:**
- Navigate to asset section → choose folder → click import
- Creates copies stored in project folder
- Maintains link to original source files
- Source location visible in property sheet
- Now available on macOS (April 2025) — enabling cross-platform asset management

**Asset Types Supported:**
- Images
- Videos
- Music/Audio files
- Text documents

**Linking Assets to Objects:**
- Drag & drop to reference strips
- Double-click fields to open asset picker dialog
- Preview images for entities, flow fragments, dialogues
- Background maps for locations

**Asset Management Features:**
- Open assets in full-scale viewer
- Edit directly in default program (Photoshop, etc.)
- Re-import from source when edited
- Thumbnail updates after editing

**Template Integration:**
- Slots: Single asset reference, can restrict by type (e.g., "sounds only")
- Strips: Multiple assets/objects at once

**Voice Over Features:**
- Free VO Management Plugin creates placeholder wav files
- Auto-generated text-to-speech placeholders
- Audio review in simulation mode
- Export spoken lines, filenames to Excel
- New ElevenLabs integration for voice synthesis preview

**VO Extension Plugin with ElevenLabs Integration (August 2025):**
- Synthesized voiceovers directly within articy:draft projects
- Tone and pacing fine-tuning controls for generated speech
- Voice library management with persistent voice profiles
- Enables rapid VO prototyping without external recording setup

### 1.3 Arcweave Media Support

- Asset lists as attribute type
- Cover images per component
- Multimedia support breaks up monotonous text
- "Full audio-visual experience"

### 1.4 World Anvil Media

- Embed images, music, sound effects in articles
- Storage limits on free tiers
- No integrated asset management system
- New Image Selector (May 2025)

### 1.5 DAM Best Practices

**Folder Structure:**
- Consistent hierarchy (e.g., "Level1_Audio", "Level1_Textures")
- Standardized naming conventions

**Metadata:**
- Asset type, creation date, artist name, usage rights
- Enables faster retrieval
- Prevents wasteful searches

**Workflow Integration:**
- Connect with game engines (Unreal, Unity, Blender)
- REST APIs for automation
- Approval workflows for asset production

### 1.6 New DAM Tools for Game Development

**Blueberry AI:**
- AI-powered DAM designed specifically for game development
- AI-driven search cuts asset retrieval time by 53%
- Support for 100+ 3D format viewing directly in browser
- Trusted by studios including ByteDance, FunPlus, and Perfect World
- Pricing starts at $9.99/seat/month
- Focuses on reducing time wasted searching for and managing game assets

**P4 DAM (formerly Helix DAM):**
- Part of the rebranded P4 Platform by Perforce
- Sketch and annotate directly on 3D models within the DAM interface
- P4 Search optimization for fast asset discovery across large repositories
- AI-powered tagging for automatic metadata generation
- Native USD (Universal Scene Description) support for modern 3D pipelines
- Integrates tightly with Perforce version control (Helix Core / P4)

### 1.7 AI-Powered Asset Management Trends

The 2025-2026 DAM landscape has seen a significant shift toward AI-assisted workflows:

- **AI metadata tagging** is now standard in modern DAMs — tools like Blueberry AI, P4 DAM, and others automatically classify and tag assets upon upload
- **Auto-generated descriptions** reduce manual cataloguing effort, using computer vision and NLP to describe asset content
- **Intelligent search** across asset libraries uses semantic understanding rather than just keyword matching, enabling searches like "dark forest environment with fog" to surface relevant assets regardless of file naming conventions
- These trends reduce the 15-20% budget waste figure cited in industry studies by automating the most error-prone parts of asset management

---

## 2. Reference & Backlink Systems

### 2.1 articy:draft References

**Automatic Reference Tracking:**
- References tab populated automatically
- Shows where entity is used:
  - In flows
  - By other entities
  - In locations
  - As speaker in dialogues

**Implicit References:**
- Created automatically when entities appear in flows
- Entity sheets show list of fragments they appear in

**Reference Strips:**
- Horizontal lists visualized as icons
- Drop target for all articy:draft objects
- Double-click to navigate to linked objects

**Calculated Strips:**
- Query language for dynamic references
- Example: "Get all DialogueFragments where this entity is speaker"
- Customizable queries for specific relation types

**Multi-User Handling:**
- Powerful referencing system with cross-referencing
- Handles conflicts gracefully
- Safe reference integrity

**Hyperlinks in Text:**
- Select text → set hyperlink via hovering menu
- Links to other objects in project

**Limitation:**
- Cannot customize Reference tab content
- Must use Calculated Strips for custom views

### 2.2 Obsidian Backlinks

**Automatic Backlinks:**
- System automatically tracks all incoming references
- Shows both explicit links and unlinked mentions
- Uses [[wikilink]] syntax
- Now 1.5M+ active monthly users (22% YoY growth as of late 2025)

**Bidirectional Linking:**
- Link page A to page B → Obsidian creates backlink on B to A
- Automatic bidirectional relationship

**Graph View:**
- Visual knowledge graph showing linked pages
- Filter by tags, folders, or specific links
- Graph Link Types plugin shows relationship types

**Automatic Link Maintenance:**
- File moves don't break links
- Background sync of all changes
- Settings → Files & Links → Automatically update internal links

**Plugins:**
- Auto Keyword Linker: converts keywords to wiki-style links
- AutoMOC: imports backlinks into current note
- 96 plugin updates recorded in a single week (late 2025), showing continued vibrant ecosystem

**Search & Filter:**
- Backlinks use same syntax as Search plugin
- Complex filtering (e.g., tag:#meeting -task)

**Collaboration:**
- Collaboration features now on the official Obsidian roadmap (planned, not yet shipped)

### 2.3 Arcweave References

- References panel shows all usages of component
- @mentions create navigable links in rich text
- Component lists allow referencing other components
- Localization features (beta) interact with reference systems, enabling cross-language reference tracking

### 2.4 Notion Backlinks

- Backlinks are now more visible and functional — when pages are mentioned via `@page` references, backlinks appear prominently on the referenced page
- Relations between databases provide structured cross-referencing
- Notion now supports backlinks when pages are mentioned, offering functional bidirectional navigation
- Suggested Edits mode (tracked changes like Google Docs) enables collaborative reference review
- Notion Agent reads comments and version history, providing AI-powered context around linked content

---

## 3. Version Control & History

### 3.1 Industry Overview

**Why Version Control Matters:**
- Multiple team members work simultaneously without overwriting
- Every modification recorded with history
- Mistakes can be undone by reverting
- Branching and merging for experimentation

**Key Tools in Game Development:**

| Tool                        | Pros                                                            | Cons                                |
|-----------------------------|-----------------------------------------------------------------|-------------------------------------|
| **Git**                     | Industry standard, free, GitHub/GitLab ecosystem                | Challenging for non-technical users |
| **Perforce Helix Core**     | Handles large binary files, trusted by AAA studios              | Complex, expensive at scale         |
| **P4 One (formerly Snowtrack)** | Free version control for artists/designers, local versioning 10x faster than Git | Acquired by Perforce March 2025, still maturing |

**Perforce Rebrand (2025):**
- Perforce has rebranded its suite as the "P4 Platform"
- P4 One: free version control for non-technical creatives (formerly Snowtrack)
- P4 DAM: digital asset management (formerly Helix DAM)
- P4 MCP Server: model context protocol integration
- P4 REST API: programmatic access to version control

**Game-Specific Considerations:**
- Not just source code: images, audio, video
- CLI-only tools difficult for artists/designers
- Need visual diffing for creative assets

### 3.2 Google Docs Version History (Gold Standard)

**Access:**
- File > Version history > See version history
- Click save notice at top
- Version history icon (clock)

**Features:**
- Chronological timeline of all edits
- Shows who made changes (color-coded per collaborator)
- Side-by-side comparison view
- "Show changes" toggle for visual diff

**Restore Capabilities:**
- Click version → "Restore this version"
- Non-destructive: newer edits still accessible
- Can copy/paste specific parts from older versions

**Named Versions:**
- Up to 40 named versions per document
- Examples: "Initial Draft", "Final Review"
- Click ... → "Name this version"

**Collaboration:**
- Viewer: read only
- Commenter: add comments, no text changes
- Editor: full editing rights

**Limitations:**
- Cannot delete specific versions
- Edit permission required to browse history

### 3.3 Figma Version History

**Access:**
- Click file name OR Figma > File > Show version history
- Chronological design history

**Features:**
- Non-destructive restore (current version still accessible)
- Comments preserved across all versions
- Custom version names with descriptions
- Duplicate version to new file

**Version Naming:**
- "V1 - Initial concept", "V2 - Feedback incorporated"
- Add title and description explaining changes

**Use Cases:**
- Share specific version with developer
- Starting point for further iteration

**Config 2025 Updates:**
- Four new products announced: Make (AI prompt-to-app), Sites (publish as websites), Buzz (brand assets with GenAI), Draw (vector/illustration)
- Adopted the Eg-walker algorithm for Code Layers (June 2025) — a new approach to collaborative editing with significantly lower memory usage
- Version history extends to the new product areas (Sites, Make, etc.)

### 3.4 Notion Version History

**Availability:**
- Plus, Business, or Enterprise plans only
- Not available on free tier

**Features:**
- Complete edit history per page
- Who made changes and when
- Comparison view
- Version comments for context

**Best Practices:**
- Tag important versions with inline text
- "Draft Version", "Board Review Version"
- Clear record of major updates

**Limitations:**
- Paid feature only
- Limited retention period (30 days on some plans)

**Recent Updates:**
- Offline mode launched August 2025 — changes made offline merge automatically on reconnect, with conflict resolution prompts when needed
- Notion Agent can read version history when answering questions about document evolution
- Performance improvements: pages load 27% faster on Windows, 11% faster on Mac

### 3.5 World Anvil History

**Status:**
- Community requested revision/change history
- Request was DECLINED due to:
  - Complex interconnected data (not flat files)
  - Immutable history impractical
  - Storage costs "extremely expensive"
- Still no version history (confirmed as of early 2026)

**Current State:**
- Limited versioning discussed for 5-10 minute backtrack
- Content/vignette only
- CTRL+Z issues with PLATO editor

**Backup:**
- Data backed up on 8 servers multiple times daily
- Export available for guild members

**Recent Improvements (2025-2026):**
- New Articles & Categories Manager (October 2025) with improved organization
- Folders for organization of world content
- New World Dashboard for overview and navigation
- Manual Save Button returned (January 2026) — addressing user requests for explicit save control
- Inline Article Creation (January 2026) — create new articles without leaving current context

### 3.6 Arcweave History — Significant Improvements

**Historical User-Reported Issues:**
- "No official Undo and Redo"
- CTRL+Z/CTRL+Y work "a few times" then "limit reached"
- "Seems rather buggy"

**Loss of Work (Historical):**
- Users accidentally delete elements full of information
- "Very frustrating to have to start over"
- Refresh page → lose all undo history

**Feature Requests:**
- Undo/Redo list view
- Import/Export for "snapshots"
- Similar to Google Docs local copies

**Team Response & Progress:**
- 50 action undo limit still exists
- Interest in "timeline mechanism" for 30-day change log
- Git-style project branches discussed

**Recent Updates (Gamescom 2025 and beyond):**
- Version History now in beta — users can see previous project changes and revert to earlier states
- "Faster undo/redo" improvements from v1.0
- Bugfixes for clipboard/undo issues
- Embedded Play Mode for testing narratives directly
- Localization features in beta
- AI Drama Manager exploration announced

**Status:** Improving — the addition of Version History beta addresses the most critical user complaint, though the 50-action undo limit remains a constraint.

---

## 4. Real-Time Collaboration

### 4.1 Technical Approaches

**Operational Transformation (OT):**
- Invented late 1980s for real-time co-editors
- Adjusts incoming operations based on history
- Preserves user's original intention
- Used by Google Docs
- Requires single authority for operation ordering
- Works well for linear content (text)

**CRDTs (Conflict-free Replicated Data Types):**
- Formally defined in 2011
- Allow concurrent modifications on different replicas
- Eventually converge to consistent state
- No complex coordination needed
- Two types: state-based and operation-based
- Works peer-to-peer with end-to-end encryption

**Automerge 3.0 (2025):**
- Major rewrite achieving 10x reduction in memory usage (100x in some cases)
- Benchmark: Moby Dick editing trace document went from 700MB → 1.3MB in memory
- Load time for the same document: 17 hours → 9 seconds
- Uses compressed columnar format at runtime instead of expanding full object graph
- Automerge Repo 2.0 (May 2025): batteries-included toolkit providing networking, storage, and sync out of the box
- Makes CRDTs practical for production use at scales previously considered infeasible

**Loro:**
- High-performance CRDT library built in Rust with JavaScript and Swift API bindings
- Implements the Fugue algorithm to reduce text editing interleaving anomalies (a long-standing CRDT pain point)
- v1.10.5 (January 2026) — actively maintained with regular releases
- Optimized specifically for memory, CPU, and loading speed
- Designed for rich text, tree structures, and complex document types

**Eg-walker Algorithm:**
- Adopted by Figma for Code Layers (June 2025)
- Represents edits as a directed acyclic causal event graph
- Temporarily builds a CRDT structure during merging, then discards it — keeping memory low at rest
- Achieves 1-2 orders of magnitude less memory usage than best traditional CRDTs
- Hybrid approach between OT and CRDTs: gets the consistency guarantees of CRDTs without the persistent memory overhead
- Particularly well-suited for text editing where memory efficiency matters

**Local-First Software Movement:**
- FOSDEM 2026: first dedicated devroom for Local First, CRDTs, and sync protocols — signaling mainstream acceptance
- Apps like Linear, Figma, and Notion demonstrate the "0ms latency" premium UX that local-first enables
- Open Local First organization (openlocalfirst.org) established to coordinate standards and tooling
- Apple Notes and Jupyter Notebooks now integrate CRDTs for offline-first editing
- Growing ecosystem of sync engines (ElectricSQL, PowerSync, Liveblocks) making local-first architecture accessible

**Key Differences:**

| Aspect              | OT                        | CRDT                                  | Eg-walker                              |
|---------------------|---------------------------|---------------------------------------|----------------------------------------|
| Server dependency   | Required for coordination | Can work peer-to-peer                 | Optional (works with or without server)|
| Memory usage        | Low                       | High (historically, improving with Automerge 3.0/Loro) | Very low                              |
| Complex structures  | Requires custom work      | Supports nested data natively         | Event graph representation             |
| Performance         | Faster for low conflict   | More resilient under messy conditions | Best of both worlds                    |
| Network reliability | Needs stable connection   | Handles unreliable networks           | Handles unreliable networks            |

**Real-World Implementations:**
- Google Docs: OT
- Figma: Server-authoritative, per-property last-writer-wins (CRDT-like); Eg-walker for Code Layers
- Notion: Hybrid (OT for performance, CRDT for sync)
- Apple Notes: CRDT for offline sync
- Yjs: Popular CRDT library (used by many collaborative editors)
- Automerge 3.0: Production-ready CRDT with dramatically improved performance
- Loro: High-performance Rust-based CRDT library
- Eg-walker: Adopted by Figma for Code Layers (June 2025)

**Sync Engines & Collaboration SDKs:**
- ElectricSQL: Postgres-based sync engine for local-first apps
- PowerSync: Sync layer for offline-first mobile and web apps
- Liveblocks: Real-time collaboration infrastructure with rooms, presence, and storage
- Velt: Y Combinator-backed collaboration SDK with 25+ pre-built features (comments, presence, cursors, notifications) using Yjs/CRDTs under the hood

### 4.2 Figma Real-Time Collaboration

**Features:**
- Multiple users work simultaneously
- Changes visible in real-time
- No version control back-and-forth
- Always working on most up-to-date version

**Specific Capabilities:**
- Simultaneous editing
- Live cursor tracking (see each other's cursors)
- Instant updates across all collaborators

**Config 2025 Updates:**
- Figma Make: AI prompt-to-app prototyping
- Figma Sites: Publish designs as live websites
- Figma Buzz: Brand asset management with GenAI capabilities
- Figma Draw: Vector illustration and drawing tool
- Eg-walker adoption for Code Layers — enabling collaborative code editing with minimal memory overhead
- Unified Seats Model (March 2025): one seat per user covers all Figma products, simplifying licensing
- Code Connect: links Figma components directly to production code, bridging design-dev collaboration

### 4.3 Notion Collaboration

- Real-time editing
- User presence visible
- Comments and mentions
- Permission levels (viewer, commenter, editor)

**Notion 3.0 (September 2025):**
- AI Agents capable of up to 20 minutes of autonomous work per task
- Custom Agents: scheduled or event-triggered AI workers that can edit, organize, and respond to changes
- Deeper integration of AI into collaborative workflows

**Notion 3.2 (January 2026):**
- Mobile AI parity — full agent capabilities available on mobile devices

**Offline Mode (August 2025):**
- View, edit, and create pages while offline
- Auto-download of top 20 most-visited pages for offline access
- Changes merge automatically on reconnect with conflict resolution prompts

**Suggested Edits:**
- Tracked changes mode similar to Google Docs
- Collaborators can propose edits that others review and accept/reject

### 4.4 Arcweave Collaboration

- Real-time in browser
- Multiple simultaneous users
- Editors & commenters roles
- Cloud-based (requires internet)

### 4.5 articy:draft Collaboration

- Possible but requires complex setup
- Network configuration needed
- Version control system integration
- Conflict handling for same object edits
- Now available on macOS (April 2025), enabling cross-platform project compatibility
- SSO for Perforce (August 2025) — simplified authentication for teams using Perforce infrastructure
- articy:server (the collaboration server component) still Windows-only

### 4.6 World Anvil Collaboration

- Co-DMs and player invitations
- Owner maintains control
- More share-focused than co-edit
- "Collaboration features can be difficult to set up"

---

## 5. Comments & Feedback

### 5.1 Best Practices for Design Feedback

**Core Principles:**
- Clear and concise annotations
- Descriptive labels, highlight specific elements
- Provide relevant context
- Focus on actionable feedback
- Suggest specific improvements

**Benefits of Feedback Tools:**
- Centralized comments in one place
- Clearer communication through contextual annotations
- Efficient collaboration (simultaneous review)
- Reduced revision cycles
- Accelerated project workflows

### 5.2 Figma Comments

**Adding Comments:**
- One click to add comment on specific point
- Attach images, files, or links
- @mentions to notify specific team members

**Managing Comments:**
- All comments in right side panel
- Reply button for threads
- "Resolved" status for addressed comments
- "Resolve All" for batch resolution

**Integration with Versions:**
- Discuss specific versions with team
- Comments preserved across version restores

### 5.3 Notion Comments

**Features:**
- Inline comments on any block
- @mentions for notifications
- Comment threads
- Resolution marking

**AI Integration:**
- Notion Agent reads comments when answering questions
- Can "implement Holly's feedback" automatically
- Agent can implement edits from comments autonomously, taking action based on comment content
- Simplified comment review view with grouped notifications for easier triage

**Best Practices:**
- Define roles (editing, commenting, viewing)
- Create editing protocols
- Encourage descriptive commit messages

### 5.4 Google Docs Comments

- Inline comments
- Suggestion mode (tracked changes)
- Comment threads
- Resolution
- @mentions

### 5.5 Popular Feedback Tools

| Tool              | Best For                                        |
|-------------------|-------------------------------------------------|
| **StreamWork**    | Marketing teams, agencies, workflow integration |
| **Markup.io**     | Simple annotation on images, PDFs, websites     |
| **Frame.io**      | Video, frame-accurate commenting                |
| **Filestage**     | Agencies, approval workflows                    |
| **Ruttl**         | Live website feedback                           |
| **ReviewStudio**  | Creative review with markup and approval flows  |
| **BugHerd**       | Visual bug tracking pinned to website elements  |
| **Evercast**      | Real-time streaming review for remote teams     |

**Emerging Trend:** AI transcription and summarization are becoming standard in feedback tools — automatically converting voice/video feedback into actionable text summaries and categorized action items.

---

## 6. Audit Logs & Activity Tracking

### 6.1 What Gets Tracked

**Automatic Data Points:**
- Who (user)
- What (action)
- When (timestamp)

**Manual Additions:**
- Notes explaining why a process step was performed
- Results of actions

### 6.2 Platform Examples

**Salesforce Field History Tracking:**
- Track changes to individual fields
- Maintains clear record of who changed critical fields
- Transparent audit trail

**Dynamics 365:**
- Visibility into who made a change
- What data was modified
- Exactly when change occurred
- High-level record tracking and field-level auditing

**SugarCRM:**
- Detailed history of each change
- Old and new values
- Who made changes
- Source of change

### 6.3 Activity Streams vs. Audit Logs

**Audit Log:**
- Formal record of changes
- Who, what, when
- Old vs new values

**Activity Stream:**
- Focus on collaboration and communication
- Real-time updates across records
- Team discussions
- More informal/conversational

### 6.4 Best Practices

**Performance:**
- Don't use "All Fields" tracking
- Choose "Some Fields" for important ones only
- Tracking affects performance and database size

**Retention:**
- Store logs for compliance period
- Some platforms: 1 year automatic retention
- Export for longer retention needs

### 6.5 AI-Powered Audit Trends (2025-2026)

AI-powered audit anomaly detection is emerging as a significant trend in 2025-2026. Tools are beginning to use machine learning to flag unusual patterns in audit logs — such as bulk deletions, access from unusual locations, or changes outside normal working hours — reducing the manual review burden and catching issues that human reviewers might miss.

---

## 7. Tool-by-Tool Analysis

### 7.1 articy:draft

| Feature          | Status      | Notes                                                     |
|------------------|-------------|-----------------------------------------------------------|
| Asset Management | ✅ Excellent | Slots, strips, re-import, VO plugin, ElevenLabs VO, macOS support |
| References       | ✅ Excellent | Automatic tracking, calculated strips                     |
| Version Control  | ⚠️ Complex  | Requires external VCS (Git, SVN)                          |
| Collaboration    | ⚠️ Complex  | Network setup required, SSO for Perforce, macOS support   |
| Comments         | ❌ None      | No native comment system                                  |
| Audit Log        | ⚠️ Limited  | Through VCS only                                          |

### 7.2 Arcweave

| Feature          | Status         | Notes                                               |
|------------------|----------------|------------------------------------------------------|
| Asset Management | ✅ Good         | Asset lists, cover images                            |
| References       | ✅ Good         | @mentions, references panel                          |
| Version Control  | ⚠️ Improving   | 50-action undo, Version History in beta              |
| Collaboration    | ✅ Excellent    | Real-time, cloud-based                               |
| Comments         | ✅ Good         | Commenter role                                       |
| Audit Log        | ❌ None         | No change tracking                                   |

Additional: Embedded Play Mode, localization beta

### 7.3 Notion

| Feature          | Status      | Notes                                                     |
|------------------|-------------|-----------------------------------------------------------|
| Asset Management | ⚠️ Basic    | File embeds, no DAM                                       |
| References       | ⚠️ Improved | Backlinks now more visible and functional, relations       |
| Version Control  | ✅ Good      | Full history (paid only)                                  |
| Collaboration    | ✅ Excellent | Real-time, presence, offline mode                         |
| Comments         | ✅ Excellent | Inline, threads, mentions, AI agent integration           |
| Audit Log        | ⚠️ Limited  | Edit history only                                         |

Additional: Notion 3.0/3.2 AI agents, offline mode (August 2025), Suggested Edits

### 7.4 Figma

| Feature          | Status      | Notes                                                  |
|------------------|-------------|--------------------------------------------------------|
| Asset Management | ✅ Excellent | Components, libraries                                  |
| References       | ⚠️ Basic    | Component usage tracking, Code Connect                 |
| Version Control  | ✅ Excellent | Named versions, restore, Eg-walker for Code Layers     |
| Collaboration    | ✅ Excellent | Industry-leading real-time                             |
| Comments         | ✅ Excellent | Contextual, resolvable                                 |
| Audit Log        | ⚠️ Limited  | Version history only                                   |

Additional: Config 2025 (Make, Sites, Buzz, Draw), Unified Seats Model

### 7.5 World Anvil

| Feature          | Status     | Notes                                          |
|------------------|------------|-------------------------------------------------|
| Asset Management | ⚠️ Basic   | Embed only, storage limits, New Image Selector (May 2025) |
| References       | ✅ Good     | Cross-linking articles                          |
| Version Control  | ❌ None     | Request declined                                |
| Collaboration    | ⚠️ Limited | Share-focused, not co-edit                      |
| Comments         | ⚠️ Limited | Discussion boards                               |
| Audit Log        | ❌ None     | Backups only                                    |

### 7.6 Obsidian

| Feature          | Status      | Notes                                   |
|------------------|-------------|-----------------------------------------|
| Asset Management | ⚠️ Basic    | Local files only                        |
| References       | ✅ Excellent | Backlinks, graph view                   |
| Version Control  | ⚠️ External | Git plugins available                   |
| Collaboration    | ⚠️ Planned  | On official roadmap, not yet shipped    |
| Comments         | ❌ None      | Plugins only                            |
| Audit Log        | ❌ None      | Git only                                |

### 7.7 Google Docs

| Feature          | Status      | Notes                     |
|------------------|-------------|---------------------------|
| Asset Management | ❌ None      | Not applicable            |
| References       | ❌ None      | Links only                |
| Version Control  | ✅ Excellent | Gold standard for history |
| Collaboration    | ✅ Excellent | Industry pioneer          |
| Comments         | ✅ Excellent | Inline, suggestions       |
| Audit Log        | ✅ Good      | Edit history with authors |

### 7.8 StoryFlow Editor

| Feature          | Status     | Notes                        |
|------------------|------------|------------------------------|
| Asset Management | ⚠️ Basic   | Content Browser              |
| References       | ⚠️ Basic   | Variable references          |
| Version Control  | ⚠️ Local   | Local-first, offline         |
| Collaboration    | ❌ None     | Not available                |
| Comments         | ❌ None     | Not available                |
| Audit Log        | ❌ None     | Not available                |

---

## 8. User Pain Points

### 8.1 Version Control

**Arcweave Users:**
> "There is no official Undo and Redo... refreshing the page will inevitably lose all previous Undos"

> "I accidentally deleted a fairly large Element... it never came back"

*Note: These quotes are from earlier forum posts. The situation has improved with the Version History beta announced at Gamescom 2025, though the 50-action undo limit remains.*

**World Anvil Users:**
- Requested revision history → DECLINED
- "Immutable history impractical" for complex data

### 8.2 Collaboration Complexity

**articy:draft:**
- Requires version control knowledge
- Local network setup
- Complex for non-technical users
- Cross-platform complexity reduced by macOS support (April 2025)

**World Anvil:**
- "Collaboration features can be difficult to set up"

### 8.3 Asset Management

**General Industry:**
- 15-20% of budget wasted on redundant work
- Version control issues with assets
- Lost files
- Working on outdated assets

### 8.4 Reference Tracking

**articy:draft:**
- Cannot customize Reference tab
- Must use Calculated Strips for custom views

**Notion:**
- Backlinks previously "hidden/less visible" — now improved with more prominent display

### 8.5 Comments

**articy:draft:**
- No native comment system
- Must use external tools

---

## 9. References

### Asset Management

- [articy:draft Linking Assets](https://www.articy.com/help/adx/Assets_Linking.html)
- [articy:draft Managing Assets](https://www.articy.com/help/adx/Assets_Managing.html)
- [articy:draft Basics Assets](https://www.articy.com/en/adx_basics_assets/)
- [articy:draft macOS](https://www.articy.com/en/articydraft-x-now-on-mac-os/)
- [DAM in Game Development - Blueberry](https://www.blueberry-ai.com/blog/game-development-digital-asset-management)
- [DAM for Game Developers - PicaJet](https://picajet.com/articles/digital-asset-management-for-game-developers/)
- [DAM in Game Development - Scaleflex](https://blog.scaleflex.com/digital-asset-management-for-gaming-industry/)
- [Blueberry AI DAM](https://www.blueberry-ai.com/gaming)
- [P4 DAM Updates](https://www.perforce.com/products/helix-dam/whats-new-helix-dam)

### References & Backlinks

- [articy:draft Basics Entities](https://www.articy.com/en/adx_basics_entities/)
- [articy:draft References Discussion (Steam)](https://steamcommunity.com/app/388600/discussions/0/3046105389671596320/)
- [articy:draft Connecting Areas](https://www.articy.com/help/adx/ConnectingAreas.html)
- [Obsidian Backlinks](https://help.obsidian.md/plugins/backlinks)
- [Mastering Obsidian Linking Features](https://www.jordanrobison.net/p/mastering-obsidians-linking-features)

### Version Control

- [Version Control for Designers - Perforce](https://www.perforce.com/blog/vcs/version-control-for-designers)
- [5 Version Control Tools - The New Stack](https://thenewstack.io/5-version-control-tools-game-developers-should-know-about/)
- [Version Control in Game Development - Gridly](https://www.gridly.com/blog/version-control-in-game-development/)
- [Google Docs Version History](https://edu.gcfglobal.org/en/googledocuments/version-history/1/)
- [Figma Version History](https://help.figma.com/hc/en-us/articles/360038006754-View-a-file-s-version-history)
- [Notion Version Control Guide](https://ones.com/blog/mastering-version-control-notion-guide/)
- [Perforce P4 One](https://www.perforce.com/press-releases/announcing-p4-one)
- [Arcweave Gamescom 2025](https://blog.arcweave.com/arcweave-goes-to-devcom-gamescom-2025)
- [World Anvil Oct 2025](https://blog.worldanvil.com/worldanvil/dev-news/world-anvil-just-got-even-better/)
- [World Anvil Feb 2026](https://blog.worldanvil.com/newsletter/world-anvil-news-february-2026/)

### Collaboration Technology

- [CRDTs - Medium](https://shambhavishandilya.medium.com/understanding-real-time-collaboration-with-crdts-e764eb65024e)
- [OT vs CRDT - TinyMCE](https://www.tiny.cloud/blog/real-time-collaboration-ot-vs-crdt/)
- [CRDTs vs OT Guide - HackerNoon](https://hackernoon.com/crdts-vs-operational-transformation-a-practical-guide-to-real-time-collaboration)
- [CRDT Wikipedia](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type)
- [Automerge 3.0](https://automerge.org/blog/automerge-3/)
- [Automerge Repo 2.0](https://automerge.org/blog/2025/05/13/automerge-repo-2/)
- [Loro CRDT Library](https://loro.dev/)
- [Eg-walker Paper](https://arxiv.org/html/2409.14252v1)
- [Figma Code Layers / Eg-walker](https://www.figma.com/blog/building-figmas-code-layers/)
- [Figma Config 2025](https://www.figma.com/blog/config-2025-recap/)
- [Notion 3.0 Agents](https://www.notion.com/releases/2025-09-18)
- [Notion 3.2 Mobile AI](https://www.notion.com/releases/2026-01-20)
- [Notion Offline Mode](https://www.notion.com/releases/2025-08-19)
- [FOSDEM 2026 Local-First](https://fosdem.org/2026/schedule/track/local-first/)
- [Open Local First](https://openlocalfirst.org/)
- [Liveblocks](https://liveblocks.io/)
- [Velt Collaboration SDK](https://velt.dev/)
- [ElectricSQL](https://electric-sql.com/)
- [PowerSync](https://www.powersync.com)
- [Smashing Magazine Shadow DOM 2025](https://www.smashingmagazine.com/2025/07/web-components-working-with-shadow-dom/)
- [StoryFlow Editor](https://storyflow-editor.com/)

### Comments & Feedback

- [Figma Collaboration Features - GeeksforGeeks](https://www.geeksforgeeks.org/websites-apps/advanced-collaboration-features-in-figma-comments-annotations-and-more/)
- [Best Design Feedback Tools - StreamWork](https://www.streamwork.com/post/10-best-design-annotation-and-feedback-tools)
- [Design Feedback Tools - Webflow](https://webflow.com/blog/design-feedback-tools)
- [Best Practices for Annotation Tools](https://uicollabo.com/en/blog/best-practices-for-effective-feedback-using-annotation-tools/)

### User Feedback & Issues

- [Arcweave Suggestions Forum](https://arcweave.com/forum/discussion/feature-requests-suggestions/suggestions-on-improvements)
- [Arcweave Undo/Redo Feature Request](https://arcweave.com/forum/discussion/feature-requests-suggestions/undoredo-feature)
- [World Anvil Version History Request (Declined)](https://www.worldanvil.com/community/voting/suggestion/7719c2af-903f-4225-9da5-9c757df43de5/view)
- [World Anvil Export Feature](https://www.worldanvil.com/learn/world/export)
- [World Anvil Backup & Security](https://www.worldanvil.com/features/security-access)
