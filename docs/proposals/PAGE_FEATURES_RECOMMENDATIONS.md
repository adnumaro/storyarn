# Page Features: Recommendations & Strategy

> **Date:** February 2024
> **Based on:** [Page Features Research](../research/PAGE_FEATURES_RESEARCH.md)

---

## Executive Summary

After researching how creative tools handle media management, references, version control, and collaboration, I've identified significant opportunities for Storyarn. The key finding: **no tool does all of these well together**.

- **articy:draft**: Excellent assets & references, but no comments and complex version control
- **Arcweave**: Great collaboration, but terrible version history (users are frustrated)
- **Notion**: Great collaboration & history, but poor references and no game integration
- **Figma**: Gold standard for collaboration, but not for narrative design

**Storyarn's opportunity**: Combine the best of each into a cohesive experience designed for narrative designers.

---

## 1. Media & Asset Management

### Current Gap in Market

articy:draft is the only tool with professional-grade asset management for narrative design. But it's:
- Desktop-only
- Complex setup
- No real-time collaboration on assets

### My Recommendation

#### 1.1 Centralized Asset Library

```
Project/
├── Assets/
│   ├── Characters/
│   │   ├── jaime_portrait.png
│   │   └── jaime_voice_01.wav
│   ├── Locations/
│   │   └── tavern_bg.jpg
│   └── Items/
│       └── sword_icon.png
```

**Features:**
- Drag & drop upload
- Automatic thumbnails
- Filter by type (image, audio, video, document)
- Search by name, tags
- Usage tracking (where is this asset used?)

#### 1.2 Asset References in Pages

Instead of embedding assets, **reference them**:

```
┌─ Media ─────────────────────────────────────────┐
│                                                 │
│ 📷 Images                                       │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐            │
│ │ [thumb] │ │ [thumb] │ │  [+]    │            │
│ │ portrait│ │ concept │ │  Add    │            │
│ └─────────┘ └─────────┘ └─────────┘            │
│                                                 │
│ 🔊 Audio                                        │
│ ┌───────────────────────────────────────────┐  │
│ │ ▶️ jaime_greeting_01.wav    0:04  [x]     │  │
│ │ ▶️ jaime_angry_01.wav       0:03  [x]     │  │
│ └───────────────────────────────────────────┘  │
│ [+ Add audio]                                   │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Why references, not embeds:**
- Same asset usable across multiple pages
- Update once, reflects everywhere
- Tracks usage automatically
- Better for export to game engines

#### 1.3 VO/Audio Workflow (Differentiator)

articy:draft has a VO plugin. We can do better natively:

**Features:**
- Attach audio files to dialogue nodes
- Track recording status: ⬜ Pending, 🟡 Placeholder, ✅ Recorded
- Export VO script (formatted for voice actors)
- Word count and estimated duration per line
- Batch operations (mark all as recorded, etc.)

**Future:** Integration with text-to-speech for placeholders (like articy's ElevenLabs integration)

---

## 2. Reference & Backlink System

### Current Gap in Market

- **articy:draft**: Automatic references but cannot customize the tab
- **Obsidian**: Excellent backlinks but no game integration
- **Arcweave**: Basic @mentions only
- **Notion**: Backlinks exist but hidden/underutilized

### My Recommendation

#### 2.1 Automatic "Used In" Tab

Every page should automatically show:

```
┌─ References ────────────────────────────────────┐
│                                                 │
│ 📍 Used in Flows                                │
│ ├── Main Quest / Scene 3 (as speaker)          │
│ ├── Side Quest / Merchant Chat (as speaker)    │
│ └── Tutorial / Intro (in condition)            │
│                                                 │
│ 📄 Referenced by Pages                          │
│ ├── House Lannister (as member)                │
│ └── Westeros Guide (mentioned in content)      │
│                                                 │
│ 🖼️ Linked Assets                                │
│ ├── jaime_portrait.png                         │
│ └── jaime_voice_01.wav                         │
│                                                 │
│ 👶 Children (3)                                 │
│ └── [View all children...]                     │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Key insight from research:** This is automatic in articy:draft and highly valued. No one else does it well.

#### 2.2 @Mentions in Rich Text

Like Arcweave and Notion:

```
Type @ to link: @Jaime → creates link to Jaime page
```

**Bidirectional:** When you @mention Jaime in Elena's page, Jaime's References tab shows "Referenced by Elena".

#### 2.3 Page References as Property Type

In addition to @mentions in text, allow page references as property values:

```
┌─ Properties ────────────────────────────────────┐
│ Father:    [@Tywin Lannister    ]    (page ref)│
│ Siblings:  [@Cersei] [@Tyrion]       (multi)   │
│ Faction:   [@House Lannister    ]              │
└─────────────────────────────────────────────────┘
```

**This enables:**
- Structured relationships (not just text links)
- Query: "Show all characters where Faction = House Lannister"
- Visualization: Family trees, org charts

#### 2.4 Relationship Types (Future)

Extend page references with relationship types:

```
Jaime → Cersei (relationship: "sibling", "lover")
Jaime → Tywin (relationship: "father")
```

This is a common request in articy:draft forums. No tool does it well.

---

## 3. Version Control & History

### Current Gap in Market

This is where **everyone fails**:

- **Arcweave**: Users literally losing work, undo "buggy", refresh loses history
- **World Anvil**: Declined to implement, "too expensive"
- **articy:draft**: Requires external Git/SVN setup
- **Notion**: Good but paid-only and limited retention

**Figma and Google Docs** are the gold standard. We should match them.

### My Recommendation

#### 3.1 Automatic Version History

Every save creates a version. No manual action required.

```
┌─ History ───────────────────────────────────────┐
│                                                 │
│ 📅 Today                                        │
│ ├── 3:45 PM - You edited properties            │
│ │   Changed: Age (30 → 32), Added: Weapon      │
│ ├── 2:30 PM - Maria edited content             │
│ │   Modified: Description block                │
│ └── 11:00 AM - You created page                │
│                                                 │
│ 📅 Yesterday                                    │
│ ├── 5:00 PM - Carlos edited properties         │
│ │   Added: Faction                             │
│ └── [Load more...]                             │
│                                                 │
│ [Compare versions]  [Restore this version]     │
│                                                 │
└─────────────────────────────────────────────────┘
```

#### 3.2 What to Track

| Change Type | Tracked |
|-------------|---------|
| Property values changed | ✅ Old → New value |
| Property added/removed | ✅ With name |
| Content blocks edited | ✅ Diff available |
| Assets attached/removed | ✅ With asset name |
| Child pages added/moved | ✅ |
| Page renamed | ✅ |
| Page moved | ✅ |

#### 3.3 Version Comparison

Like Google Docs:
- Side-by-side view
- Highlight changes
- Per-collaborator color coding

```
┌─────────────────┬─────────────────┐
│ Version A       │ Version B       │
│ (Yesterday 5PM) │ (Today 3PM)     │
├─────────────────┼─────────────────┤
│ Age: 30         │ Age: [32]       │ ← Changed
│ Faction: -      │ Faction: [+]    │ ← Added
│ Backstory:      │ Backstory:      │
│ "Jaime was..."  │ "Jaime [is]..." │ ← Modified
└─────────────────┴─────────────────┘
```

#### 3.4 Restore Capabilities

**Non-destructive restore** (like Figma):
- Restore creates NEW version with old content
- All history preserved
- Can always go back

**Partial restore:**
- Restore specific properties only
- Restore content but keep current properties
- Copy from old version (manual cherry-pick)

#### 3.5 Named Versions / Milestones

Allow users to mark important versions:

```
┌─ Milestones ────────────────────────────────────┐
│ ★ "Final approved"      - Today 5:00 PM        │
│ ★ "After writer review" - Jan 15               │
│ ★ "Initial draft"       - Jan 10               │
└─────────────────────────────────────────────────┘
```

#### 3.6 Retention Policy

| Plan       | Retention   |
|------------|-------------|
| Free       | 7 days      |
| Pro        | 30 days     |
| Team       | 90 days     |
| Enterprise | Unlimited   |

Export full history for compliance/backup.

---

## 4. Real-Time Collaboration

### Current State

Storyarn already has:
- Phoenix LiveView (native real-time)
- Presence tracking in Flows
- Cursor sharing in canvas
- Node locking

### My Recommendation

#### 4.1 Extend to Pages

Same collaboration features from Flow editor to Pages:

```
┌─ Page Header ───────────────────────────────────┐
│ 📄 Jaime                     👤 Maria  👤 You   │
│                              ↑ Online now       │
└─────────────────────────────────────────────────┘
```

**Who's viewing:**
- Avatar bubbles of online users
- Click to see what they're editing

#### 4.2 Block-Level Locking

Similar to node locking in Flows:

```
┌─ Content ───────────────────────────────────────┐
│                                                 │
│ ## Description                    [🔒 Maria]   │
│ Jaime is the eldest son...                     │
│ ← Maria is editing this block                  │
│                                                 │
│ ## Backstory                                    │
│ Born in Casterly Rock...                       │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Rules:**
- Auto-lock when user starts editing
- Auto-release after 30 seconds of inactivity
- Visual indicator of who has lock
- Cannot edit locked blocks

#### 4.3 Cursor Presence (Optional)

For content blocks, show collaborator cursors:

```
## Description
Jaime is the eldest son of Tywin|  ← Your cursor
Lannister. He is known as the   [Maria]  ← Maria's cursor
Kingslayer after killing the Mad King.
```

This might be overkill for Pages (unlike canvas where it's essential). Consider making it optional.

#### 4.4 Conflict Resolution

If two users edit same block somehow:

1. Last-writer-wins for simple properties
2. For rich text: merge or prompt user
3. Never lose data - create "conflict version" if needed

---

## 5. Comments & Feedback

### Current Gap in Market

- **articy:draft**: NO native comments
- **Arcweave**: Basic commenter role
- **World Anvil**: Discussion boards (separate from content)

**Notion and Figma** are the standard here.

### My Recommendation

#### 5.1 Inline Comments on Content

Click any content block → Add comment:

```
┌─ Content ───────────────────────────────────────┐
│                                                 │
│ ## Description                                  │
│ Jaime is the eldest son of Tywin Lannister.   │
│ He is known as the Kingslayer.                 │
│                         └──┬──┘                │
│                    ┌──────┴───────┐            │
│                    │ 💬 2 comments │            │
│                    │              │            │
│                    │ Maria: Is this│            │
│                    │ the right     │            │
│                    │ title?        │            │
│                    │              │            │
│                    │ You: Yes,    │            │
│                    │ confirmed.   │            │
│                    │              │            │
│                    │ [Reply] [✓]  │            │
│                    └──────────────┘            │
│                                                 │
└─────────────────────────────────────────────────┘
```

#### 5.2 Comments on Properties

Not just content, but specific fields:

```
┌─ Properties ────────────────────────────────────┐
│ Age:     [32]                          💬 1    │
│          └── Maria: "Should this be 35          │
│              based on the timeline?"            │
└─────────────────────────────────────────────────┘
```

#### 5.3 Comment Features

- **@mentions**: Notify specific users
- **Threads**: Reply chains
- **Resolution**: Mark as resolved (hides but preserves)
- **View modes**: All / Unresolved only
- **Filter**: By author, date, status

#### 5.4 Page-Level Comments

For general feedback not tied to specific content:

```
┌─ Comments (5) ──────────────────────────────────┐
│                                                 │
│ 💬 Maria - 2 hours ago                         │
│ "This character needs more backstory.          │
│ Can you expand the childhood section?"         │
│ [Reply] [Resolve]                              │
│                                                 │
│ 💬 Carlos - Yesterday                          │
│ "Approved for production ✓"                    │
│ [Reply] [Resolve]                              │
│                                                 │
│ [Add comment...]                               │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 6. Activity & Audit Log

### My Recommendation

#### 6.1 Page Activity Feed

Combine history + comments + collaboration into unified feed:

```
┌─ Activity ──────────────────────────────────────┐
│                                                 │
│ 🕐 Today                                        │
│                                                 │
│ 3:45 PM  You                                   │
│ ├── ✏️ Changed Age from 30 to 32               │
│ └── ✏️ Added property "Weapon"                 │
│                                                 │
│ 3:30 PM  Maria                                 │
│ └── 💬 Commented on Description                │
│     "Is this the right title?"                 │
│                                                 │
│ 2:00 PM  Carlos                                │
│ └── 👁️ Viewed this page                        │
│                                                 │
│ 11:00 AM  You                                  │
│ └── 📄 Created this page                       │
│                                                 │
└─────────────────────────────────────────────────┘
```

#### 6.2 Project-Wide Activity

In dashboard/sidebar, show recent activity across project:

```
┌─ Recent Activity ───────────────────────────────┐
│                                                 │
│ Maria edited "Cersei"              5 min ago   │
│ You commented on "Main Quest"      1 hour ago  │
│ Carlos created "Tavern"            2 hours ago │
│ Maria resolved comment on "Jaime"  Yesterday   │
│                                                 │
│ [View all activity...]                          │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 7. Tab Organization Strategy

### Recommended Structure

```
┌─────────────────────────────────────────────────┐
│ 📄 Jaime                       👤👤 [Settings] │
├─────────────────────────────────────────────────┤
│ [Content] [Media] [References] [Activity]       │
└─────────────────────────────────────────────────┘
```

**4 Main Tabs:**

| Tab            | Contents                                      |
|----------------|-----------------------------------------------|
| **Content**    | Properties (inherited + own) + Content blocks |
| **Media**      | Images, Audio, Video, Documents attached      |
| **References** | Used in Flows, Referenced by Pages, Children  |
| **Activity**   | History + Comments combined                   |

**Why this organization:**
- Content = what you work on daily
- Media = creative assets
- References = navigation & discovery
- Activity = collaboration & history

**Settings in dropdown** (not a tab):
- Technical ID
- Localization ID
- Permissions
- Export options
- Delete

---

## 8. Implementation Priority

### Phase 1: Foundation

| Feature                      | Priority   | Effort   | Impact             |
|------------------------------|------------|----------|--------------------|
| Automatic version history    | HIGH       | Medium   | Critical for trust |
| Simple restore (full page)   | HIGH       | Low      | Safety net         |
| Activity feed (history view) | HIGH       | Medium   | Transparency       |

**Why first:** Users need to trust they won't lose work. Arcweave's reputation suffers from this.

### Phase 2: References

| Feature                      | Priority   | Effort   | Impact                   |
|------------------------------|------------|----------|--------------------------|
| "Used In" automatic tracking | HIGH       | Medium   | Major differentiator     |
| @mentions in rich text       | HIGH       | Low      | Expected feature         |
| Page reference property type | MEDIUM     | Medium   | Structured relationships |

**Why second:** This is where articy:draft excels and others fail.

### Phase 3: Comments

| Feature                   | Priority  | Effort   | Impact             |
|---------------------------|-----------|----------|--------------------|
| Inline comments on blocks | HIGH      | Medium   | Team collaboration |
| Comment threads           | MEDIUM    | Low      | Conversations      |
| Resolution & filtering    | MEDIUM    | Low      | Workflow           |

**Why third:** Teams need this for review workflows.

### Phase 4: Media

| Feature            | Priority   | Effort   | Impact           |
|--------------------|------------|----------|------------------|
| Asset library      | MEDIUM     | High     | Organization     |
| Media tab per page | MEDIUM     | Medium   | Convenience      |
| Usage tracking     | MEDIUM     | Medium   | Asset management |

**Why fourth:** Existing asset system works, this is enhancement.

### Phase 5: Advanced

| Feature                   | Priority   | Effort  | Impact             |
|---------------------------|------------|---------|--------------------|
| Version comparison (diff) | LOW        | High    | Power user feature |
| Named versions/milestones | LOW        | Low     | Nice to have       |
| Relationship types        | LOW        | High    | Future enhancement |

---

## 9. Competitive Positioning

### vs articy:draft

> "All the power of articy's references and assets, with version history that actually works, and comments that don't require a separate tool."

### vs Arcweave

> "Real-time collaboration PLUS version history you can trust. Never lose work again."

### vs Notion

> "Notion's collaboration meets game development. Your pages connect to flows, export to engines, and track VO status."

### vs World Anvil

> "Wiki-style worldbuilding with proper version control, not just backups."

---

## 10. Key Differentiators Summary

If Storyarn implements these recommendations, it will be:

1. **The only narrative tool with proper version history** (Arcweave fails, articy requires Git)
2. **The only tool with automatic reference tracking + game integration** (articy has it, but no collaboration)
3. **The only tool with inline comments for narrative content** (articy has none)
4. **The only tool combining Figma-style collaboration with narrative design**

**The tagline could be:**

> "Storyarn: Where Figma meets articy:draft. Collaborate in real-time. Never lose your work. Ship to your game engine."
