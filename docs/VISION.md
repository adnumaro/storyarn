# Storyarn Vision — Platform Expansion

> Storyarn is the source of truth for game design. It doesn't replace every tool — it connects them. What it owns, it owns completely. What it doesn't, it integrates deeply.

## Platform Identity

```
Storyarn (source of truth)
|
|- OWNS: Narrative, variables, scenes, prototyping,
|        localization, assets, GDD, exploration mode
|
|- INTEGRATES: Jira, Linear, Trello, Asana
|   -> Bidirectional task creation and status sync
|   -> Deep links back to Storyarn entities
|
|- EXPOSES: Public wikis (fandom-style)
|   -> Subdomain: wiki.mygame.storyarn.com
|   -> Community-facing lore, maps, characters
|   -> Ad-supported on free tier
|
|- EXPORTS: Unity, Unreal, Godot
|   -> Designed data used in production builds
```

---

## I. Game Engine Evaluation

### A. 3D Engine — Deferred

Building a 3D engine inside Storyarn is not the goal. The complexity breakdown:

| Component                              | Difficulty  | AI Dependency         |
|----------------------------------------|-------------|-----------------------|
| Image -> 3D pipeline (Tripo/Meshy API) | Medium      | External API          |
| 3D viewer (Three.js/Babylon)           | Medium-High | 0% — pure engineering |
| Player controls                        | Medium      | 0%                    |
| Scene composition                      | Very High   | ~50% automatable      |
| Collisions/navmesh                     | High        | Partially automatable |
| Flow/dialogue integration              | Medium      | Already exists        |

**Verdict:** Not viable as a short-term goal. If pursued later, the approach would be:
1. Integrate with external tools (Spine for 2D animation, Tripo/Meshy for 3D generation)
2. Use the Rust runtime (see section IV) to handle logic
3. Engine plugins handle rendering — Storyarn handles data

### B. 2D Engine in Exploration Mode — Viable

Storyarn already has ~70% of the foundation:
- Scene canvas with zones, pins, layers, background images
- Exploration mode with navigation
- Connections defining transitions between zones/pins
- Flow system for dialogues and logic
- Condition/instruction builders for variables and state
- Asset management with uploaded images

**What's missing for a playable 2D prototype:**

| Component                         | Difficulty   | Notes                            |
|-----------------------------------|--------------|----------------------------------|
| Player sprite + movement          | Low-Medium   | Point & click or WASD            |
| Zone collision (is_solid flag)    | Low          | New field on zone schema         |
| Trigger system (zone/pin -> flow) | Low          | trigger_flow_id on zones/pins    |
| Dialogue overlay during play      | Medium       | Flow player as overlay           |
| Scene transitions                 | Low          | Connections already define these |
| Character animation integration   | Medium       | Spine runtime (see below)        |

**Target quality: Modern adventure games** (Return to Monkey Island, Broken Age).

For high-quality character animation, the approach is **integration, not building**:
- Artists work in **Spine** (industry standard, $70-300 license)
- Export `.json` + `.atlas` + `.png`
- Upload to Storyarn as asset
- Spine JS runtime renders in exploration mode
- Storyarn provides: placement, scale, animation state triggers

**This eliminates the need to build:**
- Spritesheet slicer
- Animation timeline editor
- Rigging editor
- Bone system
- State machine editor

**Storyarn UI needed:**

| Menu                 | Purpose                                    | Complexity     |
|----------------------|--------------------------------------------|----------------|
| Character config     | Upload Spine export, set scale/speed       | Low            |
| Scene placement      | Drag character to scene (like pins)        | Low            |
| Animation mapping    | Link states to flow triggers               | Medium         |
| Walkable area        | Paint walkable zones (zones already exist) | Medium         |
| Interaction hotspots | Already pins/zones with triggers           | Already exists |

---

## II. Configurable Game Mechanics

### The Vision

Users describe game mechanics in natural language. AI configures pre-built systems to match.

### The Approach: AI as Configurator, Not Code Generator

AI does NOT generate arbitrary code. AI configures **pre-built systems** from a catalog.

```
User: "Inventory with 20 slots, max carry weight 50kg"

AI generates configuration:
  { system: "inventory",
    slots: 20,
    weight_limit: 50,
    weight_variable: "player.carry_weight",
    ui_position: "bottom-right" }

AI does NOT generate:
  500 lines of custom JS
```

**Why this wins:**
- Consistent, tested output
- Exportable to Unity/Godot (plugins implement the same systems)
- Users can tweak parameters after generation
- AI accuracy 90%+ because decision space is finite
- Composable — combine inventory + crafting + trading

### Systems Catalog

```
Core Mechanics:
|- inventory         # slots, weight, categories, stacking
|- dialogue          # (already exists — flows)
|- quest_journal     # objectives, tracking, states
|- save_system       # save/load variable state

World Mechanics:
|- day_night_cycle   # time progression, hourly events
|- weather           # states, visual effects
|- minimap           # visited zones, fog of war
|- fast_travel       # discovered waypoints

Combat Mechanics:
|- turn_based        # turns, actions, stats
|- real_time_simple  # cooldowns, basic hitboxes
|- health_system     # HP, damage, death, respawn

Social Mechanics:
|- reputation        # factions, tiers
|- shop              # buy/sell, dynamic pricing
|- crafting          # recipes, materials, results
```

Each system has:
- Configuration schema (JSON Schema)
- Web implementation (preview in exploration mode)
- Export specification (for engine plugins to implement)

### What AI Can Do Well Today

| Mechanic Type                             | AI Viability   | Why                                                |
|-------------------------------------------|----------------|----------------------------------------------------|
| Static UI (inventory, HUD, minimap)       | High           | HTML/CSS/JS, LLMs excel here                       |
| Variable logic (weight, stats, cooldowns) | High           | Variable system already exists, AI just configures |
| Simple state machines (door open/closed)  | High           | Condition + instruction, already exists            |
| Modified movement (speed, jump)           | Medium-High    | Numeric parameters, well-defined                   |
| Dialogue systems with branches            | Already exists | Flow editor                                        |

### What AI Does Poorly Today

| Mechanic Type                  | AI Viability  | Why                                            |
|--------------------------------|---------------|------------------------------------------------|
| Complex combat systems         | Low           | Too many emergent interactions, balance issues |
| Custom physics                 | Low           | Subtle bugs, AI can't test the "feel"          |
| NPC AI (pathfinding, behavior) | Medium-Low    | Works in demo, breaks on edge cases            |
| Netcode/multiplayer            | Very Low      | Don't attempt                                  |

### Complexity Assessment

| Piece                                                       | Difficulty   | Timeline                           |
|-------------------------------------------------------------|--------------|------------------------------------|
| 3-5 base systems (inventory, quests, save, shop, health)    | Medium-High  | First milestone                    |
| AI configurator from natural language                       | Medium       | Builds on existing variable system |
| 10-15 systems covering 80% of narrative/adventure/RPG games | High         | Medium-term                        |
| AI composing multiple systems + connecting variables        | High         | Medium-term                        |
| UI editor for tweaking AI-generated config                  | Medium       | After AI configurator              |

---

## III. Export Pipeline & Native Runtime

### Architecture: Three Layers

**Layer 1: Interchange Format (what Storyarn exports)**

```
storyarn_export/
|- manifest.json          # version, metadata
|- flows/                 # dialogue trees + logic
|- variables/             # game state definitions
|- conditions/            # rules
|- instructions/          # mutations
|- characters/            # character sheets
|- scenes/                # scene layouts
|- animations/            # Spine/asset references
|- localization/          # translated texts
|- mechanics/             # system configurations
|- assets/                # or asset references
```

Already have `Exports` context with `DataCollector`, `Serializer`, etc. This extends what exists.

**Layer 2: Native Runtime (Rust)**

A core runtime that:
- Loads Storyarn export
- Evaluates conditions
- Executes instructions (mutates variables)
- Navigates flow graph (next node, responses, branches)
- Manages game state
- Runs configured mechanics

```
storyarn-runtime (Rust)
|- flow_engine.rs        # navigate node graph
|- variable_store.rs     # game state
|- condition_eval.rs     # evaluate conditions
|- instruction_exec.rs   # execute instructions
|- expression_eval.rs    # evaluate formulas
|- localization.rs       # resolve texts by language
|- scene_manager.rs      # scene/character data
|- mechanics/             # pluggable mechanic systems
```

**Layer 3: Engine Plugins (bindings)**

| Engine   | Binding      | Integration                        |
|----------|--------------|------------------------------------|
| Unity    | C# via C FFI | `.dll`/`.so` native + C# wrapper   |
| Unreal   | C++ direct   | Rust -> C FFI -> C++ plugin        |
| Godot    | GDExtension  | Rust with gdext (official support) |
| Bevy     | Native Rust  | Direct crate, trivial              |

**Why Rust:**
- One codebase, all engines — compiles to native library per platform
- Clean C FFI — Unity and Unreal consume C without issues
- Godot has gdext — first-class Rust bindings
- No garbage collector — doesn't fight Unity/Unreal GC
- Free WebAssembly — web preview compiles to WASM

**Critical architecture decision: Rust as single source of truth**

Instead of maintaining logic in both Elixir and Rust:
1. Rust runtime compiles to **WASM**
2. Story player and debug mode in web **use the WASM**
3. Native plugins use the **same Rust compiled natively**
4. **One implementation**, multiple targets

### Complexity Assessment

| Piece                        | Difficulty                                              |
|------------------------------|---------------------------------------------------------|
| Export format definition     | Medium (extends existing Exports context)               |
| Rust core runtime            | High (replicate conditions/instructions/flows logic)    |
| Expression evaluator in Rust | Medium-High (port FormulaEngine from Elixir)            |
| Godot plugin                 | Medium (gdext is ergonomic) — build first               |
| WASM for web preview         | Medium (Rust compiles to WASM with minimal changes)     |
| Unity plugin                 | High (C FFI + C# wrapper + editor UI)                   |
| Unreal plugin                | Very High (C++ is tedious, UE plugin system is complex) |

### Recommended Build Order

1. Define export format (most important — it's the contract)
2. Rust runtime with flow engine + variables + conditions
3. Godot plugin first (easiest, validates architecture)
4. WASM to replace web story player
5. Unity plugin (largest market)
6. Unreal plugin (last, most complex)

---

## IV. Platform Features

### A. AI Wiki — Conversational Game Wiki & Interactive Guide

**Not a static fandom clone. The first AI-powered wiki for games.**

The user asks questions in natural language and the AI responds using the project's structured data as context, enriched with images, maps, and entity references.

**Core experience:**

```
Player: "Who is Elias?"
AI Wiki: [Elias avatar] Elias is the protagonist of...
         [tavern scene image] He is first encountered in...
         [interactive map highlighting the zone]

Player: "How do I get the castle key?" (spoilers OFF)
AI Wiki: Hint: explore the tavern and talk to all NPCs.

Player: "How do I get the castle key?" (spoilers ON)
AI Wiki: To get the key you need to talk to Mira after...
```

**How it works:**

```
User question
  → Embedding search over project data (RAG)
  → Spoiler filter (if OFF, exclude quest resolutions, endings, etc.)
  → LLM generates response with entity references
  → Renderer enriches with images, maps, links
  → Contextual ads inserted in layout
```

The AI doesn't generate images. It **references** entities that already have images. The LLM emits entity tags (`[character:elias]`, `[scene:tavern]`) that the renderer resolves against project data.

**Spoiler control:**

| Level             | What the AI can use                                           |
|-------------------|---------------------------------------------------------------|
| **No spoilers**   | Names, descriptions, visible locations, early-game characters |
| **Hints**         | Above + vague quest hints without revealing resolution        |
| **Full spoilers** | Everything — including endings, plot twists, solutions        |

Designers mark content as spoiler in Storyarn (toggle `spoiler_level` on flows, nodes, or sheets).

**Interactive game guide with progress tracking:**

The AI wiki doubles as an interactive game guide. Users can save their progress:

```
Player: "Where did I leave off last time?"
AI: Last session you were in the tavern after talking to Mira.
    You haven't visited the northern cave yet.
    [map with cave highlighted]
    That's where you need to go next.
```

Progress data model:

```
WikiUser
  - id
  - game_id (which project)
  - progress_summary (text, AI-updated after each session)
  - last_session_at

WikiConversation
  - wiki_user_id
  - messages (jsonb)
  - session_date
```

The `progress_summary` is key. After each conversation, the AI generates a summary of the player's state. Next session, that summary is injected as context. No need to store full history — just the rolling summary.

Progress is narrative-only, inferred from conversation. No game save sync (avoids complexity explosion).

**SEO strategy — static landing + AI chat:**

```
wiki.mygame.storyarn.com/
├── index.html         ← static landing, SEO-indexable, game intro
├── ask                ← AI chat (main experience)
└── guide              ← interactive guide with login for progress
```

The landing page is auto-generated once from project data: synopsis, main characters (no spoilers), screenshots, world map. Google indexes this. Users arrive via SEO and discover the AI chat.

**Conversational Ads:**

Ads are not banners shoved into the response. They are **contextual recommendations with transparent sponsorship disclosure**, integrated naturally into the conversation flow.

**Market validation (March 2026):**

| Platform | Approach | Result |
|---|---|---|
| **Microsoft Copilot** | Ads below AI response, contextual to full conversation | **73% higher CTR, 16% higher conversion** vs traditional search. Journey shortened 33% |
| **ChatGPT (OpenAI)** | Ads appended to responses, matched by topic + history | Testing on free/Go tiers since Feb 2026. Ad does not alter AI response |
| **Perplexity** | Sponsored follow-up questions in "Related" section | **Abandoned Feb 2026** — execs said ads made users "suspicious of everything" |
| **Character.AI** | Traditional banners/interstitials shoved mid-chat | Community backlash, users leaving |

**Why Perplexity failed but Storyarn won't (same mistake):** Perplexity sells *factual truth* — if users suspect the answer is ad-influenced, the product is worthless. Storyarn wiki sells *game help* — a recommendation of a similar game is orthogonal to "how do I beat the dragon." It doesn't contaminate the answer.

**Why Character.AI's approach is wrong:** They use traditional ad formats (banners, interstitials, video pre-rolls) inside a conversational product. Maximum friction, zero context.

**Storyarn's approach: two ad formats for two distinct moments.**

**Format 1 — Conversational recommendation (after responses, every 3-4 interactions):**

The AI answers the user's question first (fully, no contamination), then adds a contextual recommendation with a genuine hook and transparent disclosure.

```
Player: "How do I defeat the lake dragon?"

AI: To defeat the dragon you need the ice bow from the northern
    cave. Equip it and aim for the wings first so it can't fly.

    By the way, Dragon's Dogma 2 has dragon fights with a
    similar feel — you can actually climb on the dragon while
    it's flying.

    Fun fact: Hideaki Itsuno directed both Devil May Cry and
    Dragon's Dogma. The idea was born from wanting to make a
    western RPG with Japanese action game intensity.

    [game screenshot/banner]

    🏷️ Sponsored recommendation — but genuinely worth checking
    out if you enjoy this kind of combat. Want to know more?
    Just ask.
```

Key design principles:
- **Answer first, recommend second** — the user's question is fully resolved before any ad
- **Genuine hook** — a real, verified anecdote that's interesting independent of the ad. The AI doesn't invent hooks — they come from a curated catalog of verified facts
- **Transparent disclosure** — "Sponsored recommendation" is explicit (legally required, but also builds trust — studies show explicit disclosure increases credibility)
- **Conversational CTA** — "Want to know more? Just ask" instead of a cold link
- **The recommendation is true** — the AI genuinely evaluates relevance, not just slot-filling

**Format 2 — Loading ad (during tool calls, 3-5 seconds):**

When the AI calls tools that require processing time (RAG search, API calls to game databases, complex queries), the wait time is used to show a short sponsored content piece.

```
AI: Let me look that up for you...

    While you wait, this might interest you:
    [3-5 second sponsored video/content]

    🏷️ Sponsored — but I think you'll like it.
    Did you? [👍] [❤️] [👎]
```

Key design principles:
- **Zero intrusión** — the user is already waiting, this fills dead time (like loading screen tips in games)
- **Consistent timing** — if a tool call takes 1s, pad to 3-4s. If it takes 4s, don't pad. The floor is always the same, never feels artificially slow
- **Video format** — higher CPM than text (5-10x), more engaging during a wait
- **Sentiment feedback** — thumbs up/down/heart provides engagement + sentiment data for advertisers (more valuable than raw clicks)

**Frequency control — shared cooldown:**

Both formats share a single global cooldown to prevent ad fatigue:

```
Interaction 1  → normal response
Interaction 2  → tool call → loading ad (3s video)
Interaction 3  → normal response
Interaction 4  → normal response
Interaction 5  → normal response
Interaction 6  → conversational recommendation
Interaction 7  → normal response
Interaction 8  → tool call → NO loading ad (cooldown active)
Interaction 9  → normal response
Interaction 10 → tool call → loading ad
```

Rules:
- Minimum 3-4 interactions between any ad (either format)
- Never two ads in consecutive interactions
- Maximum 1 ad per response
- Never force an ad if no relevant match exists
- When a tool call happens but cooldown isn't met, show a normal spinner

**Legal requirements (validated March 2026):**

| Jurisdiction | Requirement | How Storyarn complies |
|---|---|---|
| **FTC (USA)** | Sponsored content must be "clear, conspicuous, and timely" | 🏷️ "Sponsored recommendation" label on every ad |
| **EU AI Act (Aug 2026)** | Users must know they interact with AI; AI-generated content must be identifiable | Wiki clearly states it's AI-powered; ads labeled |
| **EU DSA** | Transparency in how content is recommended; no targeted ads to minors | Context-based targeting (no profiling); age gate possible |

**Why transparency is a feature, not a tax:**
- 86% of consumers feel deceived by undisclosed native ads (→ trust destroyed forever)
- Explicit disclosure **increases credibility** — users perceive the author as honest
- Native ads with disclosure generate **32% more engagement** than traditional display ads
- 71% lose trust in brands that prioritize profit over transparency (Nielsen)

The format "Sponsored recommendation — but genuinely worth checking out" is radically different from a cold "Sponsored" label. It's what a friend who works at a game store would say: "I get paid to tell you about this, but it's actually good."

**Revenue model — Cost Per Engagement (CPE):**

| Model | What's measured | Conversational equivalent | Relative value |
|---|---|---|---|
| CPM | Ad seen | AI mentions the game | Low |
| CPC | Click on banner | User clicks store link | Medium |
| **CPE** | **User engagement** | **User asks "tell me more"** | **High** |
| CPA | Purchase/install | User buys via affiliate link | Highest |

CPE is the sweet spot. Reference: Microsoft Copilot achieves 73% higher CTR than traditional search with contextual ads. Perplexity reported 40% of users clicked follow-up questions before they abandoned ads.

**Metrics for advertisers:**

```
Dragon's Dogma 2 — Campaign Report
├── Mentions: 12,450 (AI recommended the game)
├── Engagements: 3,200 (users asked "tell me more")       ← leads
├── Deep engagements: 890 (2+ follow-up questions)
├── Click-throughs: 450 (went to Steam/trailer)
├── Engagement rate: 25.7%
├── Avg. questions per engaged user: 2.3
├── Loading ad views: 8,300
├── Loading ad sentiment: 72% 👍, 18% neutral, 10% 👎
└── Loading ad click-throughs: 1,200
```

**How it works technically:**

The LLM prompt includes an active ad catalog with **curated, verified metadata** per game:
- Genre, platform, rating, description
- **Verified anecdotes/hooks** (human-curated, not AI-invented) — development stories, interesting facts, critical reception highlights
- Screenshots, trailer links, store links (with affiliate tags)

The LLM chooses which ad fits the conversation context. Rules:
- Never force an ad if not relevant
- Maximum 1 ad per response
- Respect shared cooldown (3-4 interactions minimum)
- Use real product data only — never invent facts about sponsored games
- Prefer conversational format over loading format when both are possible
- Casual tone: "By the way...", "Fun fact:...", "Speaking of..."

**Why this is different from every existing approach:**

| Character.AI | Perplexity | Copilot | **Storyarn** |
|---|---|---|---|
| Banners mid-chat | Sponsored follow-up question | Ad block below response | Contextual recommendation + loading ad |
| Zero context | Labeled, separate | Labeled, separate, with "ad voice" | Hook + disclosure + conversational CTA |
| User hates it | Users got suspicious | 73% higher CTR | **Untested — but combines best of all** |
| No disclosure design | Cold "Sponsored" label | "Sponsored" + AI explains why | "Sponsored — but genuinely worth it" |

Privacy advantages (unchanged):
- No personal data stored
- No cross-site tracking
- Targeting by session and context, not by profile
- GDPR-compliant by design — no tracking cookies needed
- Transparent: user can see why they see an ad ("Based on your conversation about tactical RPGs")

**Two products, one ecosystem:**

Storyarn operates as two complementary products:

1. **Storyarn Platform** — the design tool (subscriptions)
2. **Storyarn Wiki Ads** — the ad network for wiki monetization

| Product | Revenue source | Customers |
|---|---|---|
| Storyarn Platform | Subscriptions per seat/workspace | Game designers, studios |
| Storyarn Wiki Ads | Advertisers paying for conversational ad placements | Game publishers, related brands |

**Wiki + Ads tier integration:**

| Tier | Wiki | Conversational Ads | Customization | Wiki Metrics |
|---|---|---|---|---|
| **Free/Indie** | **Opt-in** (dev activates it) | Revenue → Storyarn | Storyarn branding | No |
| **Indie + Ads** | Opt-in | Revenue → developer (paid add-on) | Storyarn branding | Basic |
| **Pro** | Optional (on/off) | Revenue → developer (included) | Game branding (colors, logo) | Yes (conversation insights) |
| **Enterprise** | Optional | Revenue → developer (included) | Full branding, custom domain | Yes + API access |

**Wiki is opt-in, not mandatory.** The developer chooses when to activate their wiki (typically at or near launch). Forcing publication of project data during development would be hostile to users who protect their IP. The model mirrors Fandom's: free hosting with Storyarn-controlled ads. If the dev wants to control ads or remove them, they upgrade.

**Upgrade paths:**
- Free indie → activates wiki at launch → sees traffic → buys Ads add-on to own revenue
- Indie + Ads → wants branding + metrics → upgrades to Pro → gets ads included + full control
- The ad revenue ownership is a tangible, measurable incentive to upgrade

**Pro tier wiki features:**
- Custom branding: game logo, color scheme, fonts
- Custom domain: `wiki.mygame.com` pointing to Storyarn-hosted wiki
- Ad revenue goes to developer (Storyarn takes a % cut)
- Conversation insights dashboard:
  - Player sentiment analysis (frustration, confusion, excitement)
  - Content discovery gaps (what players search for but can't find in-game)
  - Narrative feedback (questions revealing unclear plot points, ambiguous relationships)
  - Most asked questions by category

**External wikis — aggregated from legal API sources (not scraped):**

AI wikis for games NOT built with Storyarn, generated by aggregating data from public APIs and open-license sources.

**Data sources with verified legal access (March 2026):**

| Source | API | Content | License/Terms |
|---|---|---|---|
| **StrategyWiki** | MediaWiki API | **10,507 games, 852 complete guides, 56K pages** — walkthroughs, strategies | **CC-BY-SA 4.0** — commercial use allowed with attribution |
| **Wikipedia** | MediaWiki API / REST | Synopsis, mechanics, reception, development history | **CC-BY-SA 4.0** — commercial use allowed with attribution |
| **Wikibooks** | MediaWiki API | Additional game guides | **CC-BY-SA** |
| **RAWG.io** | REST API | 500K+ games, descriptions, screenshots, ratings, genres | Free commercial <20K req/month, <500K pageviews |
| **IGDB (Twitch)** | REST API | Comprehensive game metadata, covers, screenshots | Free non-commercial; **commercial requires partnership** |
| **Steam Store** | Store API | Descriptions, reviews, prices, screenshots, requirements | API key (free) |
| **GiantBomb** | REST API | Exhaustive game database | API key (free) |

**Sources explicitly excluded (legal risk):**

| Source | Reason |
|---|---|
| **Fandom** | CC-BY-SA text but ToS explicitly prohibit scraping with bots. Reddit sued Anthropic and Perplexity for similar violations (2025-2026). 70+ copyright lawsuits against AI companies for scraping. Not worth the risk. |
| **IGN, EliteGuías, GameFAQs, Game8** | Editorial copyright. GameFAQs authors explicitly prohibit redistribution. |
| **MobyGames** | API available but prohibits data redistribution |
| **Metacritic/OpenCritic** | No public API, scraping prohibited |

**How external wikis work — AI as agent with tools:**

```
User: "How do I get to the Crystal Peak in Hollow Knight?"

AI internally:
  1. Tool: StrategyWiki API → query "Hollow Knight" walkthrough → Crystal Peak section
  2. Tool: RAWG/Steam API → game metadata, screenshots for context
  3. LLM synthesizes a conversational response from aggregated data
  4. [If cooldown allows] → Tool: ad catalog → relevant similar game
  5. [If tool calls take time] → loading ad (3-5s video)
```

The AI doesn't store pre-scraped content. It queries APIs at runtime (with caching), functioning as a conversational layer over legitimate data sources. CC-BY-SA attribution is included in responses when sourcing from StrategyWiki/Wikipedia.

**Quality tiers:**

| Wiki type | Data quality | Source |
|---|---|---|
| **Native wiki** (Storyarn project) | Perfect — structured entities, relationships, spoiler tags | Project data via RAG |
| **External wiki** (popular game) | Good — guides + metadata + LLM knowledge | StrategyWiki + APIs + LLM base knowledge |
| **External wiki** (obscure game) | Basic — metadata only, limited guide content | APIs + LLM base knowledge |

- External wikis have no owner — all ad revenue goes to Storyarn
- Lower quality than native wikis (aggregated text vs structured entities)
- Creates audience before customers: players discover Storyarn wikis → developers discover the platform
- If a developer wants the premium wiki experience (structured data, spoiler control, full guide coverage), they use Storyarn to design their game — that's the only path to a native wiki

**Traffic reference points (March 2026):**
- Stardew Valley Wiki (independent): ~110M visits/month (Semrush, March 2024) — an indie game
- Fandom total: ~780M visits/month
- Major wikis are **leaving Fandom** (Minecraft, Hollow Knight, GTA, League of Legends — all migrated 2022-2025) due to aggressive ads
- One successful game wiki with 500K+ active players could justify the entire wiki infrastructure

**Cost model:**

- ~2000-4000 context tokens + ~500-1000 response tokens per question
- With an economical model (Haiku-tier): ~$0.001-0.003 per question
- 1000 questions/day = $1-3/day
- Conversational ad revenue at $5-20 CPM covers the LLM cost significantly
- **Self-funding from day one**

**Cold-start strategy — affiliate programs (validated March 2026):**

Direct advertisers won't pay without traffic volume. Solve the chicken-and-egg with affiliate links from existing gaming storefronts.

**Available affiliate programs:**

| Platform | Commission | Cookie | Access | Notes |
|---|---|---|---|---|
| **GOG.com** | **6%** | 30 days | Open (via CJ Affiliate) | DRM-free games, good indie catalog |
| **Humble Bundle** | **5-8%** (up to 15% on bundles) | 30 days | Open | Bundles are high-conversion |
| **Green Man Gaming** | **0.5-5%** (10% on bundles) | 30 days | Open | 7,000+ games, sells Steam keys |
| **Fanatical** | **2-5%** | — | Open | Steam/Epic keys |
| **Epic Games** | **5%** or $5/referral | — | Support-A-Creator program | Requires "creator" status |
| **Steam** | **No program** | — | — | No public affiliate program. Use GMG/Humble/Fanatical for Steam keys |

**Phase 1 (no advertisers needed):** The AI recommends games using affiliate links from GOG, Humble, GMG. At 6% commission on a $30 game = $1.80 per sale. Low margin, but zero cost to operate — no sales team, no advertiser relationships. Validates the format and builds conversion data.

**Phase 2 (organic growth):** As wiki traffic grows, track metrics (impressions, engagement rate, conversions). Build a case with real data. At this point the two ad formats (conversational + loading) are generating measurable engagement and sentiment data.

**Phase 3 (direct advertisers):** With proven traffic and conversion data, approach game publishers for premium conversational ad placements at CPE rates significantly higher than affiliate commissions.

**Flywheel:**
- Indie uses Storyarn (free) → activates wiki at launch → Storyarn earns affiliate revenue from external recommendations
- Players use the guide → conversational recommendations feel natural → higher engagement → more revenue
- Traffic grows → affiliate data proves conversion rates → attracts direct advertisers
- Indie sees traffic → buys Ads add-on or upgrades to Pro to own revenue
- More games → more wikis → more traffic → more ad inventory → more attractive to advertisers
- External wikis (from legal APIs) attract players → developers discover Storyarn → convert to native wikis

**Complexity:** Medium — RAG over structured data + tool-based API queries + chat UI + entity renderer + conversational ad integration + loading ad system + tier-based wiki config.

### B. Auto-Generated GDD

- Pulls from all existing data: characters, flows, variables, mechanics, scenes
- LaTeX already integrated
- Professional document layout
- Living document — updates as the project evolves
- Exportable as PDF

**Complexity:** Low-Medium — connecting existing data to a document template.

### C. External Tool Integration

**Pattern: Storyarn creates tasks in YOUR tools, doesn't replace them.**

- "Create task" button on any Storyarn entity
- Modal: choose Linear/Jira/Trello project
- Auto-generated description + link back to Storyarn + attached images
- Webhook for bidirectional status sync
- In Storyarn: see task status without leaving

**Deep links bidirectional:** Every Storyarn entity has a stable URL. Linear/Jira comments can link directly to a specific dialogue node. From Storyarn, see all linked tasks for any entity.

**Complexity:** ~1 week for first integration, days for each subsequent one. Same pattern repeated.

### D. Production Pipeline

Once integrations + entity data exist, the pipeline emerges naturally:

```
Character sheet in Storyarn
  -> "Create art task" -> Linear (concept art brief + AI reference images)
  -> Art complete, uploaded to Storyarn assets
  -> "Create 3D modeling task" -> Linear (final designs + notes for 3D artist)
  -> "Create animation task" -> Linear (personality notes + Spine reference)
  -> "Create voice task" -> Linear (voice direction sheets + script)
```

Each step links back to the character in Storyarn. The designer sees the full pipeline status on the entity.

### E. AI Content Generation

- Character concept art from sheet descriptions
- Scene backgrounds from zone/layer descriptions
- Asset variations and iterations
- Brief generation for artists

**Complexity:** Low — API calls to image generation services, similar to existing DeepL integration pattern.

---

## V. Proposed New Features

### 1. Playtesting Analytics — HIGH PRIORITY

Share a link, testers play in exploration mode, Storyarn records everything:

| Metric            | Value                                                                     |
|-------------------|---------------------------------------------------------------------------|
| Narrative funnel  | Of 100 testers, how many reached the end, where they dropped off          |
| Decision heatmap  | What % chooses each dialogue response                                     |
| Time-per-node     | Which dialogues are read fast (boring) vs re-read (confusing/interesting) |
| Branch discovery  | What % of content was seen by at least one tester                         |
| Stuck detection   | Where testers loop or give up                                             |
| Shareable reports | Designer generates a report and shares via link                           |

**Implementation:** Log events during exploration mode (`INSERT` per interaction) + dashboard views.

**Why this is gold:** No narrative design tool offers this. Designers currently playtest by watching over someone's shoulder. This gives them data at scale.

### 2. Branching Visualizer / Story Map

A high-level view showing ALL possible paths through the game. Not individual flows — the meta-flow.

- "If the player does X in chapter 2, this unlocks Y in chapter 5"
- Overlay playtesting data: "73% of testers never saw this branch"
- Identify dead-end paths, unreachable content, narrative bottlenecks

**Why:** articy attempts this and fails. No tool does it well.

### 3. Voice Direction Sheets

For each dialogue line, the designer adds direction for voice actors:
- Emotion, intensity, pacing
- Audio reference clips
- Context (what just happened in the story)
- Technical notes (whisper, shout, crying)

Export as formatted scripts for recording sessions. Actors get full context without playing the game.

**Why:** Already have flows + dialogues + localization + audio assets. Connecting the dots.

### 4. Consistency Checker (AI) — HIGH PRIORITY

AI analyzes the entire project and detects:

| Issue               | Example                                            |
|---------------------|----------------------------------------------------|
| Plot holes          | Character dies in branch A but appears in branch B |
| Dead variables      | Variables set but never read                       |
| Unreachable content | Dialogues that no path leads to                    |
| Missing references  | Characters referenced that don't exist             |
| Tone inconsistency  | Different writing styles between team members      |
| Broken conditions   | Conditions referencing deleted variables           |
| Circular paths      | Flow loops with no exit condition                  |

**Why this is a must-have:** Narrative designers spend weeks manually hunting inconsistencies. This alone justifies the subscription.

### 5. Live Collaboration in Playtesting

Designer and tester in the same session:
- Designer sees what the tester does in real-time
- Designer takes notes anchored to the exact moment in the playtest
- Can pause and ask questions
- Recording of the full session for later review

**Why:** Like Figma's "observe mode" but for game prototypes. Collaboration infrastructure already exists.

### 6. Asset Brief Generator

From a character sheet, AI generates a complete brief for artists:
- Visual description compiled from all sheet fields
- Mood board suggestions
- Color palette based on character traits
- Technical constraints (sprite size, animation count needed)
- Reference images (AI-generated concepts)

The artist receives a professional document, not a Slack message saying "make me an elf."

### 7. Create on Reference — Inline Entity Creation

**Core concept:** The user types a dot-notation path that doesn't exist, and the system creates it. Like `mkdir -p` for game design entities. The designer thinks and the tool follows — no context switching.

**Example 1: Speaker in dialogue node**

```
User types: characters.main-characters.elias

System:
1. Parse path: ["characters", "main-characters", "elias"]
2. Look up sheet with shortcut "characters" → exists?
   - Yes → find child "main-characters" → exists?
     - Yes → find child "elias" → exists?
       - No → create sheet "Elias" inside main-characters
     - No → create folder "Main Characters", then "Elias" inside
   - No → create entire hierarchy
3. Assign created sheet as speaker
```

**Example 2: Variable in condition/instruction builder**

```
User types: elias.has_key

System:
1. Find sheet "elias" → found
2. Find block "has_key" in elias → doesn't exist
3. Infer type from name + context:
   - Name "has_key" → suggests boolean (has_*, is_*, can_*)
   - Used in condition with true/false → boolean confirmed
4. Create block "has_key" type boolean on sheet elias
5. Use it in the condition
```

**Type inference — dual strategy (name + context):**

By name pattern:

| Pattern                                                 | Inferred Type   | Confidence  |
|---------------------------------------------------------|-----------------|-------------|
| `has_*`, `is_*`, `can_*`, `was_*`                       | boolean         | High        |
| `count_*`, `num_*`, `*_count`, `health`, `level`, `age` | number          | Medium      |
| `name`, `title`, `description`, `*_text`                | text            | Medium      |
| Everything else                                         | Unknown         | Show modal  |

By usage context:

| Context                              | Inferred Type          |
|--------------------------------------|------------------------|
| Compared with `true`/`false`         | boolean                |
| Compared with a number               | number                 |
| Operator `greater_than`, `less_than` | number                 |
| Operator `contains`, `starts_with`   | text                   |
| Operator `is_empty`, `is_nil`        | Ambiguous — show modal |

When both agree, create without asking. When they conflict or are ambiguous, show a quick one-click confirmation modal.

**Accidental creation prevention:**

- **Fuzzy matching first.** Before creating, search for similar: "Did you mean `has_key`?"
- **Undo.** Ctrl+Z undoes the creation
- **Visual indicator.** Input changes color or shows a "NEW" badge when about to create

**Hierarchy rules:**
- Intermediate folders are normal sheets without blocks
- User can add blocks to them later
- A "folder" is simply a sheet that has children

**Where it applies:**

| Context                     | What Gets Created       | Example                    |
|-----------------------------|-------------------------|----------------------------|
| Flow → dialogue speaker     | Sheet (character)       | `characters.elias`         |
| Flow → condition variable   | Block on existing sheet | `elias.has_key`            |
| Flow → instruction variable | Block on existing sheet | `elias.gold` → number      |
| Scene → pin reference       | Sheet                   | `items.magic-sword`        |
| Scene → zone trigger        | Flow                    | `chapter1.tavern-dialogue` |
| Condition → sheet reference | Full sheet              | `factions.guild`           |

**Project settings toggle:**

| Mode                   | Behavior                                            | Target                    |
|------------------------|-----------------------------------------------------|---------------------------|
| **Creative** (default) | Create on reference active                          | Indies, rapid prototyping |
| **Strict**             | Only reference existing entities, autocomplete only | AAA, large teams          |

**Technical implementation:**

```elixir
defmodule Storyarn.Shared.InlineCreator do
  @doc """
  Resolves a dot-notation path, creating missing entities as needed.
  Returns {:ok, entity} | {:confirm, type_options} | {:suggest, similar}
  """
  def resolve_or_create(path, project_id, opts \\ [])

  # opts:
  #   context: :speaker | :condition | :instruction
  #   operator: "greater_than" | "is_true" | ...
  #   value: "50" | "true" | ...
  #   enabled: true/false (from project settings)
end
```

JS side: extend existing search inputs (combobox/searchable select):
- Exact match → select
- Fuzzy match → suggest
- No match + creative mode → show "Create `elias.has_key`" option with inferred type
- User confirms with Enter or click

**Assessment:**

| Aspect                     | Rating                                                                               |
|----------------------------|--------------------------------------------------------------------------------------|
| User value                 | **Very high** — eliminates constant friction                                         |
| Implementation complexity  | **Medium** — parsing/creation is simple, fuzzy + confirmation UX is the complex part |
| Risk                       | **Low with toggle** — enterprises disable it, indies enjoy it                        |
| Competitive differentiator | **High** — articy has nothing like this                                              |

### 8. Avatar Gallery — Multi-Avatar System for Sheets

**Core concept:** The sheet avatar evolves from a single image to an ordered list of images. Two management modes: a quick inline film strip (carrete) and a full-size gallery modal for detailed editing.

**Why:** Character portraits with expressions are standard across RPGs, visual novels, adventure games, and tactical RPGs. Persona 5 uses 12-20 per character, Fire Emblem uses 8-12, RPG Maker defaults to 8. articy has AlternatePortraits but with poor UX — no visual preview in flows, no inline editing.

**Mode 1: Film Strip (inline in sheet)**

Quick management: add, reorder, select default. No name editing, no metadata. Pure speed.

```
┌─────────────┐
│    [img]    │
├─────────────┤
│  ★ [img]   │  ← default
├─────────────┤
│    [img]    │
├─────────────┤
│   + Add     │
├─────────────┤
│  Gallery    │  ← opens modal
└─────────────┘
```

Film strip actions: add image, reorder (drag), select default (click), delete (hover → X), open gallery.

**Mode 2: Gallery Modal (full-size)**

Detailed management with two sub-views:

Grid view — all avatars visible, click inline to name, drag to reorder.

Single view — click any image from grid to see full-size, with editable fields below:
- **Name** (optional) — normalized with `variablify` (e.g., "Angry Face" → `angry_face`)
- **Notes** (optional) — free text for art direction, actor notes, context
- Navigation arrows between images
- "Set as default" button
- Delete button

**Editing capabilities per mode:**

| Action              | Film Strip   | Gallery Grid   | Gallery Single   |
|---------------------|--------------|----------------|------------------|
| Add image           | Yes          | Yes            | No               |
| Reorder             | Drag         | Drag           | Arrows ← →       |
| Select default      | Click        | Click          | Button           |
| Delete              | Hover → X    | Hover → X      | Button           |
| Edit name           | No           | Click inline   | Input field      |
| Edit notes/metadata | No           | No             | Yes              |
| View full size      | No           | No             | Yes              |

**In dialogue nodes:**

Click the avatar on the dialogue node → selector shows all avatars from the speaker's gallery:
- Named avatars show name + thumbnail
- Unnamed avatars show thumbnail only
- Default is always labeled "default"
- If no avatar is selected for a node, the sheet's default avatar is used

**Data model:**

```
SheetAvatar (new table)
  - sheet_id (required, belongs_to Sheet)
  - asset_id (required, belongs_to Asset)
  - name (string, optional, variablified)
  - notes (text, optional)
  - position (integer)
  - is_default (boolean, default false)

Dialogue node data:
  - avatar_id (nullable — if null, use sheet default)
```

New table (not JSON field) for: queryability, DB-level ordering, clean schema migration.

**Design principles:**
- **Zero overhead if unused** — single avatar works exactly as today
- **No imposed semantics** — images can represent emotions, costumes, ages, angles — user decides
- **Modal absorbs future complexity** — tags, audio references, or any new fields get added to single view without changing the strip
- **Exportable** — name + notes travel in the export, engine plugins can auto-map expressions

**Assessment:**

| Aspect                     | Rating                                                                       |
|----------------------------|------------------------------------------------------------------------------|
| User value                 | **High** — standard industry need, every narrative game uses portraits       |
| Implementation complexity  | **Medium** — new table, film strip component, gallery modal                  |
| Risk                       | **Very low** — backwards compatible, optional feature                        |
| Competitive differentiator | **High** — articy's AlternatePortraits is clunky, no visual preview in flows |

---

## VI. Monetization Angles

**Two products:**

| Product | Revenue Model | Customers |
|---|---|---|
| **Storyarn Platform** | Subscriptions (per-seat or per-workspace) | Game designers, studios |
| **Storyarn Wiki Ads** | Advertisers pay for conversational ad placements in wikis | Game publishers, brands |

**Platform revenue streams:**

| Revenue Stream        | Source                                                    |
|-----------------------|-----------------------------------------------------------|
| Subscriptions         | Studios paying per-seat or per-workspace                  |
| Ads add-on            | Indies paying to own their wiki ad revenue                |
| Mechanics marketplace | Community-created mechanic configurations (revenue share) |
| AI usage              | Token-based for generation features                       |
| Engine plugins        | Free (drives platform adoption)                           |
| Enterprise            | SSO, audit logs, dedicated support                        |

**Wiki Ads revenue streams:**

| Revenue Stream             | Source                                                              |
|----------------------------|---------------------------------------------------------------------|
| Free-tier wiki ads         | Conversational + loading ads on opt-in wikis → 100% to Storyarn     |
| External wiki ads          | Ads on API-aggregated wikis → 100% to Storyarn                      |
| Pro/Enterprise wiki ads    | Conversational + loading ads → developer gets majority, Storyarn takes % cut  |
| Affiliate commissions      | Cold-start: GOG 6%, Humble 5-8%, GMG 0.5-5% on referred sales      |
| Advertiser partnerships    | Game publishers paying for premium CPE placements in relevant wiki chats |

---

## VII. Strategic Build Order

```
PHASE 1 — Foundation (current)
  Complete and polish: narrative, localization, collaboration, assets
  Exploration mode improvements
  First paying users

PHASE 2 — Wiki & Revenue
  AI Wiki (conversational wiki + interactive guide)
  Conversational ads with affiliate links (cold-start, zero advertiser dependency)
  External wikis (scraped from open sources, builds traffic)
  Playtesting analytics
  AI content generation

PHASE 3 — Differentiation
  Consistency checker (AI)
  Export format definition
  Voice direction sheets
  Branching visualizer
  Avatar gallery

PHASE 4 — Integration
  External tool integrations (Linear, Jira, Trello)
  Auto-generated GDD
  Production pipeline (emerges from integrations)
  Asset brief generator

PHASE 5 — Platform Growth
  Direct advertiser partnerships (with traffic data from phase 2)
  Live collaboration in playtesting
  Interactive maps
  Create on reference

PHASE 6 — Engine Pipeline
  Rust runtime
  Godot plugin (validates architecture)
  WASM web preview
  Unity plugin
  Configurable mechanics (first systems)

PHASE 7 — Ecosystem
  Mechanics marketplace
  Unreal plugin
  Community features
  Enterprise tier
```

---

## VIII. What Makes This Worth Paying For

Today, a 5-15 person indie studio uses:
- articy or Yarn Spinner (narrative): $200-800/year
- Figma (UI/concepts): $15/month/person
- Notion (GDD): $10/month/person
- Jira/Linear (tasks): $10/month/person
- Google Sheets (variables, balance): free but chaotic
- Crowdin (localization): $50-500/month

**Total: $500-2000/month in disconnected tools.**

Storyarn doesn't replace all of them. It replaces the narrative + design tools, integrates the project management tools, and adds capabilities none of them have (playtesting analytics, consistency checking, auto-generated GDD, public wikis).

The character you design is the same one that appears in the flow, in the wiki, in the art task in Linear, in the GDD, in the voice recording script. **That connection is what no competitor can replicate by combining separate tools.**

### Impact Assessment

**Pessimistic:** 500-1000 paying users, $10-30k/month. Viable indie business.

**Optimistic:** 5000-20000 paying users at $50-200/month per studio. $250k-4M/year. Wikis generate organic traffic. Mechanics marketplace creates network effects. Each published game advertises Storyarn through its wiki.

**What separates the two:** Whether the integration between features feels magical or bolted-on.
