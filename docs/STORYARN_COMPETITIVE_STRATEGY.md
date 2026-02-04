# Storyarn Competitive Strategy & Recommendations

> **Date:** February 2024
> **Based on:** [Narrative Design Tools Research](./research/NARRATIVE_DESIGN_TOOLS_RESEARCH.md)

---

## Executive Summary

After researching the narrative design tools market, I've identified clear opportunities for Storyarn to differentiate itself from articy:draft, Arcweave, and other competitors. The key insight is that **no tool currently excels at all three pillars**: visual authoring, real-time collaboration, and scalable performance.

---

## Market Gaps Identified

### 1. Performance at Scale
articy:draft, the industry standard, has "awful performance on huge projects" (reported by developers who worked on Disco Elysium-scale games). This is a critical weakness that a well-architected web application can exploit.

### 2. Collaboration Without Compromise
- **articy:draft**: Complex setup, requires version control knowledge
- **Arcweave**: Real-time collaboration but cloud-only, loses undo history on refresh
- **Yarn Spinner / Ink**: No collaboration features

There's no tool offering real-time collaboration with self-hosting option.

### 3. Localization as First-Class Citizen
Every tool treats localization as an afterthought. articy:draft can't even import its own exported files. This causes "hourly merge conflicts" in teams.

### 4. Affordable Team Pricing
articy:draft's multi-user licenses cost ~€1,200/user. Arcweave's free tier is limited to 200 items. Indies are forced to choose between inadequate free tools or expensive professional ones.

---

## Strategic Recommendations

### Tier 1: Critical Differentiators

These features would make Storyarn uniquely competitive:

#### 1.1 Real-Time Collaboration (Phoenix LiveView Advantage)

**Why it matters:** Arcweave's main selling point is real-time collaboration, but it requires constant internet and is cloud-only. articy:draft's collaboration is complex to set up.

**Recommendation:**
- Leverage Phoenix LiveView's native real-time capabilities
- Offer both cloud-hosted AND self-hosted options
- Implement Google Docs-style presence (see who's editing what)
- You already have cursor tracking and node locking - expand this

**Competitive advantage:** "Figma for narrative design" - real-time collaboration with the option to self-host for studios wanting control.

#### 1.2 Performance at Scale

**Why it matters:** Disco Elysium's developers reported articy:draft's performance was "awful" on their project. This is a known pain point with no solution.

**Recommendation:**
- Implement lazy loading of nodes on canvas (only render visible nodes)
- Use database-level pagination for large flows
- Elixir/Phoenix's concurrency model scales better than desktop apps
- Target: Handle 10,000+ nodes without performance degradation

**Competitive advantage:** "The only narrative tool that scales with your ambition."

#### 1.3 Aggressive Indie Pricing

**Why it matters:** Indies are underserved. articy:draft FREE has 700 object limit, Arcweave FREE has 200 item limit.

**Recommendation:**
- Free tier: 2,000+ objects (4x articy, 10x Arcweave)
- Indie plan: ~$10/month for unlimited objects
- Team plan: Per-seat pricing, not bundled tiers
- Self-hosted: One-time purchase option for studios

**Competitive advantage:** "Professional features at indie prices."

---

### Tier 2: Feature Parity (Important)

These features bring Storyarn to parity with competitors:

#### 2.1 Robust Variable System

**Current state:** Phase 4 adds conditions to connections and dialogue nodes.

**Recommendation for enhancement:**
- Add a dedicated Variables panel/page per project
- Support variable scopes: global, per-character, per-quest
- **Visual debugging** - show variable states during flow preview
- Variable history/changelog (what changed when)
- Type validation (string, number, boolean, enum)

**Why:** Variable debugging is painful in ALL tools. A visual debugger would be a significant differentiator.

#### 2.2 Universal Export

**Recommendation:**
- JSON as primary format (well-documented schema)
- Official plugins for Unity, Unreal, Godot
- Open format specification (unlike articy's proprietary format)
- CSV export for localization strings
- XLIFF support for professional translation workflows

**Why:** Studios fear vendor lock-in. Open formats build trust.

#### 2.3 Localization Integration

**Recommendation:**
- Built-in string extraction to CSV/XLIFF
- Side-by-side translation view
- Progress tracking (X% translated)
- Import translations back without merge conflicts
- Character limits and text expansion warnings

**Why:** Everyone fails at this. Doing it well would be remarkable.

---

### Tier 3: Nice to Have (Polish)

These features add polish and differentiation:

#### 3.1 Audio/VO Workflow

**Current state:** `audio_asset_id` field exists.

**Recommendation for enhancement:**
- Script export view (formatted for voice actors)
- Track recorded vs pending lines
- Word count and estimated VO duration
- Batch audio assignment
- Waveform preview in properties panel

**Why:** VO workflow is manual in most tools. Streamlining it saves hours.

#### 3.2 Simplified Templates (Alternative to Phase 5)

**Current Phase 5 proposal:** Full template system with schema, inheritance, propagation.

**My recommendation:** Simplify to "Node Presets" or "Character Properties"

**Option A - Node Presets (Simplest):**
- Any node can be saved as a preset
- Apply preset to new nodes (copies values)
- No inheritance, no propagation
- Implementation: 1-2 days

**Option B - Character Properties (Recommended):**
- Characters (Pages) can define custom fields
- Those fields appear on all dialogue nodes using that speaker
- Speaker-centric inheritance (more intuitive)
- Implementation: 3-5 days
- Covers 80% of template use cases

**Option C - Full Templates (As proposed):**
- Very powerful but complex
- Risk of over-engineering
- Implementation: 2-3 weeks

**Why I recommend Option B:** Users think about characters, not templates. "When Old Merchant speaks, show his shop inventory" is more intuitive than "Apply ShopDialogue template."

#### 3.3 Flow Preview/Testing

**Recommendation:**
- "Play" button to walk through dialogue
- Show variable changes in real-time
- Branch selection simulation
- Export test scenarios

**Why:** articy:draft has this, Arcweave lacks good simulation. It's expected in professional tools.

#### 3.4 AI Assistant (Future)

**Potential features:**
- Auto-generate `menu_text` from full text
- Detect variable inconsistencies
- Suggest responses based on character tone
- Translation assistance
- Dialogue summarization

**Why:** AI integration is the obvious next frontier. Being early matters.

---

## Prioritized Roadmap Suggestion

### Phase A: Foundation (Current)
- [x] Flow editor with 5 node types
- [x] Conditions on connections
- [x] Multi-output condition nodes
- [x] Dialogue logic fields
- [x] Real-time presence and cursors
- [x] Node locking

### Phase B: Export & Integration
- [ ] JSON export with documented schema
- [ ] Basic Unity integration guide
- [ ] CSV export for localization strings

### Phase C: Variables Enhancement
- [ ] Dedicated Variables page
- [ ] Variable scopes (global, character, quest)
- [ ] Visual variable debugging in preview mode

### Phase D: Collaboration Polish
- [ ] Commenting on nodes
- [ ] Change history/audit log
- [ ] Notification system for changes

### Phase E: Localization
- [ ] XLIFF export/import
- [ ] Side-by-side translation view
- [ ] Progress tracking

### Phase F: Templates (Simplified)
- [ ] Character custom properties (Option B)
- [ ] Node presets (quick save/apply)

### Phase G: Audio/VO Workflow
- [ ] Script export for voice actors
- [ ] Recording status tracking
- [ ] Batch operations

---

## Positioning Statement

> **Storyarn** is the narrative design platform for modern game teams. Unlike articy:draft, it scales to million-word projects without performance issues. Unlike Arcweave, it offers self-hosting for studios wanting control. Unlike free tools, it provides real-time collaboration and professional features. Storyarn is what narrative designers have been waiting for.

---

## Key Messages

### For Indies
"Professional narrative tools without the professional price tag. Start free, scale when you're ready."

### For Studios
"Real-time collaboration with the security of self-hosting. Your narrative data stays yours."

### For Writers
"Focus on your story, not your tools. Visual authoring that gets out of your way."

### Technical
"Built on Phoenix LiveView for native real-time collaboration. Scales from prototype to production."

---

## Competitive Matrix

| Feature                 | articy:draft   | Arcweave   | Yarn Spinner  | Storyarn (Target)   |
|-------------------------|----------------|------------|---------------|---------------------|
| Visual node editor      | ✅              | ✅          | ⚠️ Passive    | ✅                   |
| Real-time collaboration | ⚠️ Complex     | ✅          | ❌             | ✅                   |
| Self-hosting option     | ❌              | ❌          | N/A           | ✅                   |
| Performance at scale    | ❌              | ⚠️         | ✅             | ✅ (Target)          |
| Variable debugging      | ⚠️             | ⚠️         | ❌             | ✅ (Target)          |
| Localization workflow   | ❌              | ⚠️         | ✅             | ✅ (Target)          |
| Free tier generosity    | 700 obj        | 200 items  | Unlimited     | 2000+ obj (Target)  |
| Unity integration       | ✅              | ✅          | ✅             | ⚠️ Planned          |
| Unreal integration      | ✅              | ✅          | ❌             | ⚠️ Planned          |
| Godot integration       | ❌              | ✅          | ❌             | ⚠️ Planned          |

---

## Risks & Mitigations

### Risk: Feature creep
**Mitigation:** Focus on core differentiators first. Templates can wait.

### Risk: Engine integrations are complex
**Mitigation:** Start with well-documented JSON export. Community can build plugins.

### Risk: articy:draft brand recognition
**Mitigation:** Target underserved segments (indies, small studios) first.

### Risk: Arcweave improving collaboration
**Mitigation:** Self-hosting option is a moat they can't easily cross.

---

## Conclusion

Storyarn has a clear path to becoming a serious competitor in the narrative design space. The combination of Phoenix LiveView's real-time capabilities, Elixir's scalability, and a self-hosting option creates a unique value proposition that neither articy:draft nor Arcweave can match.

The key is focus: **don't try to match every articy feature**. Instead, excel at the things that matter most: collaboration, performance, and accessibility. Let the complex template systems be articy's domain while Storyarn becomes the tool that teams actually enjoy using.
