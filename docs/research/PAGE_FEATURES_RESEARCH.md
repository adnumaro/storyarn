# Page Features Research: Media, References, Version Control, Collaboration

> **Date:** February 2024
> **Scope:** Analysis of how creative tools handle media management, reference tracking, version control, history, and collaboration features.

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

### 1.3 Arcweave Media Support

- Asset lists as attribute type
- Cover images per component
- Multimedia support breaks up monotonous text
- "Full audio-visual experience"

### 1.4 World Anvil Media

- Embed images, music, sound effects in articles
- Storage limits on free tiers
- No integrated asset management system

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

**Search & Filter:**
- Backlinks use same syntax as Search plugin
- Complex filtering (e.g., tag:#meeting -task)

### 2.3 Arcweave References

- References panel shows all usages of component
- @mentions create navigable links in rich text
- Component lists allow referencing other components

### 2.4 Notion Backlinks

- Automatic backlinks exist but are hidden/less visible
- Relations between databases
- No automatic bidirectional linking

---

## 3. Version Control & History

### 3.1 Industry Overview

**Why Version Control Matters:**
- Multiple team members work simultaneously without overwriting
- Every modification recorded with history
- Mistakes can be undone by reverting
- Branching and merging for experimentation

**Key Tools in Game Development:**

| Tool                    | Pros                                               | Cons                                |
|-------------------------|----------------------------------------------------|-------------------------------------|
| **Git**                 | Industry standard, free, GitHub/GitLab ecosystem   | Challenging for non-technical users |
| **Perforce Helix Core** | Handles large binary files, trusted by AAA studios | Complex, expensive at scale         |
| **Snowtrack**           | Designed for creative assets, visual diffing       | Less established                    |

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
- Click ⋮ → "Name this version"

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

### 3.5 World Anvil History

**Status:**
- Community requested revision/change history
- Request was DECLINED due to:
  - Complex interconnected data (not flat files)
  - Immutable history impractical
  - Storage costs "extremely expensive"

**Current State:**
- Limited versioning discussed for 5-10 minute backtrack
- Content/vignette only
- CTRL+Z issues with PLATO editor

**Backup:**
- Data backed up on 8 servers multiple times daily
- Export available for guild members

### 3.6 Arcweave History (MAJOR PROBLEM)

**User-Reported Issues:**
- "No official Undo and Redo"
- CTRL+Z/CTRL+Y work "a few times" then "limit reached"
- "Seems rather buggy"

**Loss of Work:**
- Users accidentally delete elements full of information
- "Very frustrating to have to start over"
- Refresh page → lose all undo history

**Feature Requests:**
- Undo/Redo list view
- Import/Export for "snapshots"
- Similar to Google Docs local copies

**Team Response:**
- 50 action undo limit exists
- Interest in "timeline mechanism" for 30-day change log
- Git-style project branches discussed

**Recent Updates (v1.0):**
- "Faster undo/redo"
- Bugfixes for clipboard/undo issues

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

**Key Differences:**

| Aspect              | OT                        | CRDT                                  |
|---------------------|---------------------------|---------------------------------------|
| Server dependency   | Required for coordination | Can work peer-to-peer                 |
| Complex structures  | Requires custom work      | Supports nested data natively         |
| Performance         | Faster for low conflict   | More resilient under messy conditions |
| Network reliability | Needs stable connection   | Handles unreliable networks           |

**Real-World Implementations:**
- Google Docs: OT
- Figma: Server-authoritative, per-property last-writer-wins (CRDT-like)
- Notion: Hybrid (OT for performance, CRDT for sync)
- Teletype for Atom: CRDT
- Apple Notes: CRDT for offline sync
- Yjs: Popular CRDT library

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

### 4.3 Notion Collaboration

- Real-time editing
- User presence visible
- Comments and mentions
- Permission levels (viewer, commenter, editor)

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

| Tool           | Best For                                        |
|----------------|-------------------------------------------------|
| **StreamWork** | Marketing teams, agencies, workflow integration |
| **Markup.io**  | Simple annotation on images, PDFs, websites     |
| **Frame.io**   | Video, frame-accurate commenting                |
| **Filestage**  | Agencies, approval workflows                    |
| **Ruttl**      | Live website feedback                           |

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

---

## 7. Tool-by-Tool Analysis

### 7.1 articy:draft

| Feature          | Status      | Notes                                 |
|------------------|-------------|---------------------------------------|
| Asset Management | ✅ Excellent | Slots, strips, re-import, VO plugin   |
| References       | ✅ Excellent | Automatic tracking, calculated strips |
| Version Control  | ⚠️ Complex  | Requires external VCS (Git, SVN)      |
| Collaboration    | ⚠️ Complex  | Network setup required                |
| Comments         | ❌ None      | No native comment system              |
| Audit Log        | ⚠️ Limited  | Through VCS only                      |

### 7.2 Arcweave

| Feature          | Status      | Notes                       |
|------------------|-------------|-----------------------------|
| Asset Management | ✅ Good      | Asset lists, cover images   |
| References       | ✅ Good      | @mentions, references panel |
| Version Control  | ❌ Poor      | Limited undo, no history    |
| Collaboration    | ✅ Excellent | Real-time, cloud-based      |
| Comments         | ✅ Good      | Commenter role              |
| Audit Log        | ❌ None      | No change tracking          |

### 7.3 Notion

| Feature          | Status      | Notes                       |
|------------------|-------------|-----------------------------|
| Asset Management | ⚠️ Basic    | File embeds, no DAM         |
| References       | ⚠️ Basic    | Backlinks hidden, relations |
| Version Control  | ✅ Good      | Full history (paid only)    |
| Collaboration    | ✅ Excellent | Real-time, presence         |
| Comments         | ✅ Excellent | Inline, threads, mentions   |
| Audit Log        | ⚠️ Limited  | Edit history only           |

### 7.4 Figma

| Feature          | Status      | Notes                      |
|------------------|-------------|----------------------------|
| Asset Management | ✅ Excellent | Components, libraries      |
| References       | ⚠️ Basic    | Component usage tracking   |
| Version Control  | ✅ Excellent | Named versions, restore    |
| Collaboration    | ✅ Excellent | Industry-leading real-time |
| Comments         | ✅ Excellent | Contextual, resolvable     |
| Audit Log        | ⚠️ Limited  | Version history only       |

### 7.5 World Anvil

| Feature          | Status     | Notes                      |
|------------------|------------|----------------------------|
| Asset Management | ⚠️ Basic   | Embed only, storage limits |
| References       | ✅ Good     | Cross-linking articles     |
| Version Control  | ❌ None     | Request declined           |
| Collaboration    | ⚠️ Limited | Share-focused, not co-edit |
| Comments         | ⚠️ Limited | Discussion boards          |
| Audit Log        | ❌ None     | Backups only               |

### 7.6 Obsidian

| Feature          | Status      | Notes                         |
|------------------|-------------|-------------------------------|
| Asset Management | ⚠️ Basic    | Local files only              |
| References       | ✅ Excellent | Backlinks, graph view         |
| Version Control  | ⚠️ External | Git plugins available         |
| Collaboration    | ❌ None      | Local-first, no native collab |
| Comments         | ❌ None      | Plugins only                  |
| Audit Log        | ❌ None      | Git only                      |

### 7.7 Google Docs

| Feature          | Status      | Notes                     |
|------------------|-------------|---------------------------|
| Asset Management | ❌ None      | Not applicable            |
| References       | ❌ None      | Links only                |
| Version Control  | ✅ Excellent | Gold standard for history |
| Collaboration    | ✅ Excellent | Industry pioneer          |
| Comments         | ✅ Excellent | Inline, suggestions       |
| Audit Log        | ✅ Good      | Edit history with authors |

---

## 8. User Pain Points

### 8.1 Version Control

**Arcweave Users:**
> "There is no official Undo and Redo... refreshing the page will inevitably lose all previous Undos"

> "I accidentally deleted a fairly large Element... it never came back"

**World Anvil Users:**
- Requested revision history → DECLINED
- "Immutable history impractical" for complex data

### 8.2 Collaboration Complexity

**articy:draft:**
- Requires version control knowledge
- Local network setup
- Complex for non-technical users

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
- Backlinks exist but are "hidden/less visible"

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
- [DAM in Game Development - Blueberry](https://www.blueberry-ai.com/blog/game-development-digital-asset-management)
- [DAM for Game Developers - PicaJet](https://picajet.com/articles/digital-asset-management-for-game-developers/)
- [DAM in Game Development - Scaleflex](https://blog.scaleflex.com/digital-asset-management-for-gaming-industry/)

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

### Collaboration Technology

- [CRDTs - Medium](https://shambhavishandilya.medium.com/understanding-real-time-collaboration-with-crdts-e764eb65024e)
- [OT vs CRDT - TinyMCE](https://www.tiny.cloud/blog/real-time-collaboration-ot-vs-crdt/)
- [CRDTs vs OT Guide - HackerNoon](https://hackernoon.com/crdts-vs-operational-transformation-a-practical-guide-to-real-time-collaboration)
- [CRDT Wikipedia](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type)

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
