# Research: Video Game Mechanics Bank - Feasibility Analysis

> **Date:** February 2026 (updated 2026-02-06)
> **Status:** Research
> **Goal:** Understand why no comprehensive game mechanics database exists and evaluate feasibility

> **Changelog:**
> - **2026-02-06:** Updated patent table (Section 2.3) with verified patent numbers. Added Sections 2.4 (Nintendo/Palworld saga), 2.5 (Monolith closure), 3.6 (new entrants). Updated API status for USPTO and PatentsView. Added Federal Circuit statistics and Alice standard notes. Fixed dialogue wheel patent expiration date. Added 2025-2026 sources.
> - **2026-02-04:** Initial research document.

---

## Executive Summary

**Why doesn't a comprehensive game mechanics bank exist?**

1. **No consensus on definitions** - 49+ academic definitions of "game mechanic"
2. **Context-dependent classification** - Same action can be mechanic or "fluff" depending on game
3. **Legal gray zone** - Mechanics can't be copyrighted but CAN be patented (expensive, complex)
4. **Maintenance burden** - Would require massive ongoing curation effort
5. **Commercial disincentive** - Companies benefit from NOT sharing their innovations

**However, the opportunity exists because:**
- BoardGameGeek has 200+ mechanics cataloged (board games only)
- "Building Blocks of Tabletop Game Design" proves categorization IS possible
- Most game mechanics are NOT patented (< 6% approval rate for game patents)
- Expired patents open up mechanics like loading screen minigames, ATB combat, etc.

**Feasibility verdict:** A mechanics bank for Storyarn is viable IF scoped properly (narrative/RPG focus) and includes patent status awareness.

---

## Part 1: Why No Comprehensive Database Exists

### 1.1 The Definition Problem

> "Through a systematic literature review spanning six academic venues and several prominent books, researchers identified **49 explicit definitions** for the concept of 'game mechanics'—though some are similar, they are all fundamentally distinct."

**Competing definitions include:**

| Source         | Definition                                                 |
|----------------|------------------------------------------------------------|
| Academic       | "Systems of interactions between player and game"          |
| Designer       | "Rules and procedures that guide player and game response" |
| Technical      | "Algorithms and data structures in the game engine"        |
| Player-centric | "Only things that impact the play experience"              |

**The problem:** Without agreement on what a mechanic IS, you can't systematically catalog them.

**Sources:**
- [Redefining the MDA Framework](https://www.mdpi.com/2078-2489/12/10/395)
- [Game Mechanics Taxonomy](https://boxbase.org/entries/2015/aug/31/game-mechanics-taxonomy/)

### 1.2 Context-Dependent Classification

> "What can be considered a mechanic in one game is fluff in another. The key identifier is whether it creates consequences."

**Example:**
- **Flaming arrow in Zelda:** Burns vines → reveals path → **mechanic**
- **Flaming arrow in another game:** Cool VFX but acts like normal arrow → **not a mechanic**

This makes automated or universal classification nearly impossible.

### 1.3 Scope Explosion

The number of potential mechanics is enormous when you consider:
- Core mechanics (movement, combat, resource management)
- Meta mechanics (progression, achievements, saves)
- Social mechanics (trading, alliances, communication)
- Feedback mechanics (visual/audio responses)
- Narrative mechanics (branching, dialogue, reputation)
- Aesthetic mechanics (customization, photo modes)

And each category has dozens of variations.

### 1.4 Commercial Disincentive

Companies have no incentive to:
- Document their innovations publicly
- Make it easier for competitors to copy
- Potentially weaken patent claims by prior disclosure

**The result:** Knowledge stays siloed in studios or locked behind patents.

### 1.5 Academic vs. Practical Divide

> "There have been many attempts to create a widely accepted ontology for games, but most are defined from an analytical perspective and have found little use outside universities, as they are not easily translated to game development."

Academic frameworks like MDA are great for analysis but not for practical "I need a mechanic for X" lookup.

---

## Part 2: Legal Landscape

### 2.1 Copyright: Mechanics Are NOT Protected

> "The United States Copyright Office specifically notes: 'Copyright does not protect the idea for a game, its name or title, or the **method or methods for playing it**.'"

**What copyright DOES protect:**
- Code implementation
- Art assets
- Music and sound
- Specific text/dialogue
- Character designs

**What copyright does NOT protect:**
- Game rules
- Mechanics
- Systems
- Concepts

**This is why clones exist:** You can legally make a "match-3 puzzle game" or a "battle royale" because the mechanic itself isn't copyrightable.

**Alice Corp. v. CLS Bank (2014)** made software patents harder:
> "U.S. courts may reject patents deemed too abstract under the Abstract Idea Doctrine."

As of 2024-2025, the Alice standard has become **more stringent**, not less. The Federal Circuit's 95.5% invalidity rate on appeal shows increasing hostility to abstract software patents.

**Sources:**
- [Columbia Law: Should Game Mechanics Be Copyrightable?](https://journals.library.columbia.edu/index.php/lawandarts/announcement/view/553)
- [Wikipedia: IP Protection of Video Games](https://en.wikipedia.org/wiki/Intellectual_property_protection_of_video_games)

### 2.2 Patents: Mechanics CAN Be Protected (But Rarely Are)

**Key facts:**

| Aspect                     | Reality                               |
|----------------------------|---------------------------------------|
| Can mechanics be patented? | Yes, if novel/non-obvious             |
| Approval rate              | ~6% for game patents (vs 50% average) |
| Cost                       | $10,000-$50,000+ with lawyers         |
| Time                       | 1-3 years                             |
| Duration                   | 20 years from filing                  |
| Enforcement                | Expensive litigation required         |

Note: The 6% figure comes from a 2022 MTTLR analysis and may not reflect current rates. However, the general point — that game patents face high rejection rates — remains valid. In 2024, the Federal Circuit found claims eligible in only 1 of 22 cases on Section 101 grounds (95.5% invalidity rate).

**Alice Corp. v. CLS Bank (2014)** made software patents harder:
> "U.S. courts may reject patents deemed too abstract under the Abstract Idea Doctrine."

**Europe is stricter:**
> "European patent law contains explicit exclusions for 'programs for computers' and 'methods for playing games.'"

**Sources:**
- [The Futility of Patents on AAA Video Game Mechanics](https://mttlr.org/2022/10/the-futility-of-patents-on-aaa-video-game-mechanics/)
- [UpCounsel: Game Patents](https://www.upcounsel.com/game-patents)

### 2.3 Notable Patented Mechanics

| Mechanic                   | Owner        | Patent #                    | Expires                  |
|----------------------------|--------------|-----------------------------|--------------------------|
| Nemesis System             | Warner Bros. | US10926179B2                | 2036                     |
| Pokemon Capture/Storage    | Nintendo     | Multiple (2021-2024 filings)| Various (contested)      |
| Mass Effect Dialogue Wheel | BioWare Corp.| US8082499B2                 | October 2029             |
| Sanity Effects             | Nintendo     | US6935954B2                 | Expired (2021)           |
| Loading Screen Minigames   | Namco        | US5718632                   | Expired (2015)           |
| Crazy Taxi Arrow           | Sega         | US6200138                   | Expired (2018)           |
| Active Time Battle         | Square       | US5390937A                  | Expired (~2012)          |

**Key insight:** Most iconic mechanics are NOT patented, and many patents have expired.

**Sources:**
- [GamesRadar: 9 Video Game Patents](https://www.gamesradar.com/video-game-patents-that-might-surprise-you/)
- [PC Gamer: 5 Legally Protected Mechanics](https://www.pcgamer.com/5-game-mechanics-legally-protected-by-the-companies-that-made-them/)

### 2.4 Nintendo/Palworld Patent Saga (2025)

The most significant game IP development since this document was written:

- **September 2025:** USPTO granted two new Nintendo patents (US12,409,387 and US12,403,397) via Track One prioritized examination, related to the Palworld lawsuit filed September 2024.
- **October 2025:** Japan Patent Office **rejected** Nintendo's patent application 2024-031879, citing prior art from Ark, Craftopia, Monster Hunter 4, and Pokemon GO.
- **November 2025:** USPTO Director John Squires personally ordered re-examination of US12,403,397, citing failure to consider prior art — an extremely rare action.
- IP lawyers called the granted patents "an embarrassing failure of the US patent system."
- The Palworld lawsuit continues into 2026 with no trial date scheduled.

This saga reinforces the document's themes about the difficulty and controversy of game mechanic patents.

### 2.5 Monolith Productions Closure (February 2025)

Warner Bros. Discovery shut down Monolith Productions (creator of the Nemesis System) and cancelled the Wonder Woman game. The Nemesis System patent (US10926179B2) persists despite the studio's closure, creating a "zombie patent" scenario — an active patent with no product utilizing it. Warner Bros. could still license it.

### 2.6 Why Companies Don't Patent More

1. **High rejection rate** (94% for games)
2. **Expensive and slow** ($10K+ and years)
3. **Hard to enforce** (proves infringement is costly)
4. **Risks invalidation** (prior art challenges)
5. **Industry culture** of iteration and "borrowing"
6. **Negative PR** (Warner Bros. was heavily criticized for Nemesis patent)

> "The AAA video game industry is inherently derivative. Entire genres are created out of the unique mechanics seen in older games."

---

## Part 3: Existing Partial Solutions

### 3.1 BoardGameGeek Mechanics Database

**The closest thing to a comprehensive mechanics database.**

- **200+ mechanics** cataloged
- **XML API** available (BGG_XML_API2)
- **Community-curated** over 20+ years
- **Examples** linked to specific games

**Limitations:**
- Board games only (no video games)
- API doesn't expose mechanics list directly (requires workarounds)
- No patent status information

**API Access:**
```
https://boardgamegeek.com/wiki/page/BGG_XML_API2
https://boardgamegeek.com/data_dumps/bg_ranks (CSV dumps)
```

**Sources:**
- [BGG XML API2 Documentation](https://boardgamegeek.com/wiki/page/BGG_XML_API2)

### 3.2 "Building Blocks of Tabletop Game Design"

**The most comprehensive mechanics encyclopedia (500+ pages).**

Authors: Geoffrey Engelstein & Isaac Shalev

**Structure:**
- 13 chapters by category (Auctions, Worker Placement, Area Control, etc.)
- Each mechanic has:
  - Description
  - Pros/cons
  - Implementation notes
  - Example games

**Praise from Richard Garfield (Magic: The Gathering creator):**
> "A much-needed atlas for the explorer—giving a framework of what to look for in a game."

**Limitations:**
- Tabletop focused (though many translate to video games)
- Book format (not queryable database)
- Copyright protected content

**Sources:**
- [Routledge: Building Blocks of Tabletop Game Design](https://www.routledge.com/Building-Blocks-of-Tabletop-Game-Design-An-Encyclopedia-of-Mechanisms/Engelstein-Shalev/p/book/9781032015811)
- [Meeple Mountain Review](https://www.meeplemountain.com/reviews/building-blocks-of-tabletop-game-design/)

### 3.3 Game Design Library (GitHub)

Open-source curated links organized by topic:
- Crafting systems
- Boss design
- Health systems
- Metroidvania design
- Economy design

**URL:** https://nightblade9.github.io/game-design-library/

**Limitations:**
- Links to articles (not structured data)
- No API
- Maintenance dependent on contributors

### 3.4 Game Mechanics Wikia (Fandom)

Community wiki attempting to catalog mechanics.

**Self-acknowledged limitations:**
> "We are not trying to be an academic resource—we do not try to list every mechanic ever, the history of their use, or every game they are in."

**URL:** https://game-mechanics.fandom.com/

### 3.5 Academic Frameworks

| Framework             | Focus                                    | Usability   |
|-----------------------|------------------------------------------|-------------|
| MDA                   | Analysis (Mechanics-Dynamics-Aesthetics) | Theoretical |
| Game Ontology Project | Categorization                           | Academic    |
| ATMSG                 | Serious games                            | Specialized |
| RMDA                  | Improved MDA                             | Academic    |

**Problem:** None are designed for practical game development.

### 3.6 New Entrants (2025-2026)

**katnamag Game Mechanic Database** (itch.io): An open-source, interactive, browser-based game mechanic database built in Godot. Each mechanic has description, controls, and adjustable parameters. MIT-licensed with GitHub repository. A direct competitor to what Storyarn proposes.

**Ludo.ai**: AI-powered game design research platform with a database of "millions of games," market analysis, concept generation, and "Idea Pathfinder" for core mechanic selection. Commercially significant.

**Future of Gaming** (futureofgaming.com): Publishes quarterly reports on gaming patents with detailed analysis. Relevant to the patent-tracking aspect.

---

## Part 4: Patent Search APIs

### 4.1 USPTO Open Data Portal

**Free API access to US patent database.**

```
Base URL: https://data.uspto.gov/
API Catalog: https://developer.uspto.gov/api-catalog
```

**Migration in progress (2025-2026):** The old developer hub (developer.uspto.gov) is being retired. Several legacy APIs were decommissioned in January 2026 (PTAB API v2, Office Action Citations, Enriched Citation). New replacement APIs exist on the ODP platform.

**Capabilities:**
- Search patents by keyword
- Get patent status (active/expired)
- Download full patent documents
- Filter by classification codes

**Limitations:**
- US patents only
- No "game mechanic" classification (must search by description)
- Requires parsing legal language

### 4.2 PatentsView API

**Research-focused patent API.**

**Status update:** The Legacy PatentsView API was discontinued on May 1, 2025. It has been replaced by the **PatentSearch API** (v2.3.2), which requires an API key via the service desk. Data is current through March 2025.

```
URL: https://search.patentsview.org/
```

**Features:**
- 7 query endpoints
- Inventor disambiguation
- Company/assignee data

**Use case:** Find all patents owned by Nintendo, Warner Bros., etc.

### 4.3 Google Patents

**Most accessible for manual searches.**

```
URL: https://patents.google.com/
```

**Example:** Nemesis System patent:
https://patents.google.com/patent/US10926179B2/en

### 4.4 European Patent Office (EPO)

**Espacenet** provides access to European patents.

```
URL: https://worldwide.espacenet.com/
```

**Note:** Europe generally doesn't grant software/game patents, so this is less relevant.

### 4.5 Building a Patent Check System

**Approach:**
1. Maintain list of known game-related patents
2. Cross-reference mechanic keywords with patent claims
3. Track expiration dates
4. Flag potential conflicts

**Challenge:** Patents are written in legal language, not game design terms.

**Example mapping needed:**
```
User searches: "dialogue wheel"
System maps to: US Patent claims mentioning "radial menu",
                "conversation interface", "player choice display"
```

---

## Part 5: Opportunity for Storyarn

### 5.1 Why Storyarn Could Succeed Where Others Haven't

| Challenge             | Storyarn Advantage                        |
|-----------------------|-------------------------------------------|
| Scope explosion       | Focus on **narrative/RPG mechanics only** |
| Definition ambiguity  | Define clearly for Storyarn's context     |
| Maintenance burden    | Community contributions + AI assistance   |
| Legal uncertainty     | Include patent status/expiration info     |
| Practical vs academic | Design for implementation (templates)     |

### 5.2 Proposed Scope: Narrative Game Mechanics

**Categories relevant to Storyarn users:**

1. **Dialogue Systems**
   - Branching dialogue
   - Dialogue wheels
   - Keyword-based
   - Mood/tone selection
   - Timed responses

2. **Choice & Consequence**
   - Binary choices
   - Multi-path branching
   - Delayed consequences
   - Point of no return
   - Hidden tracking

3. **Character Systems**
   - Relationship meters
   - Reputation systems
   - Affinity/affection
   - Trust mechanics
   - Character arcs

4. **Progression**
   - Skill trees
   - Experience points
   - Level gating
   - Unlock systems
   - Achievement tracking

5. **Narrative Structure**
   - Linear narrative
   - Hub and spoke
   - Open world
   - Time loops
   - Multiple endings

6. **Information Revelation**
   - Codex/journal
   - Environmental storytelling
   - Unreliable narrator
   - Mystery/investigation
   - Lore collectibles

7. **Player Expression**
   - Alignment systems
   - Morality tracking
   - Character customization
   - Role-playing freedom
   - Player-named elements

### 5.3 Data Model for Mechanics Bank

```json
{
  "id": "uuid",
  "name": "Dialogue Wheel",
  "slug": "dialogue-wheel",
  "category": "dialogue_systems",
  "subcategory": "selection_interface",

  "description": "Radial menu presenting dialogue options arranged in a circle, typically with tone/intent mapped to position.",

  "variations": [
    {
      "name": "Mass Effect Style",
      "description": "Paraphrase on wheel, full dialogue spoken"
    },
    {
      "name": "Fallout 4 Style",
      "description": "Single word/emotion indicators"
    }
  ],

  "pros": [
    "Intuitive with controller",
    "Quick selection",
    "Can convey tone visually"
  ],

  "cons": [
    "Limited options (typically 4-6)",
    "Can obscure actual dialogue",
    "May feel restrictive"
  ],

  "implementation_notes": "Position typically maps to tone: top=good, bottom=bad, left=question, right=aggressive",

  "examples": [
    {
      "game": "Mass Effect",
      "year": 2007,
      "notes": "Defined the modern dialogue wheel"
    },
    {
      "game": "Fallout 4",
      "year": 2015,
      "notes": "Controversial simplified version"
    }
  ],

  "related_mechanics": ["branching_dialogue", "tone_selection"],

  "patent_status": {
    "known_patents": [
      {
        "holder": "BioWare Corp.",
        "patent_number": "US8082499B2",
        "status": "active",
        "expires": "2029-10-29",
        "scope": "Specific radial implementation with position-based tone"
      }
    ],
    "safe_to_use": "General concept is not patentable. Specific implementation details may be. Avoid exact replication of patented interfaces.",
    "last_checked": "2026-02-06"
  },

  "storyarn_template": {
    "available": true,
    "template_id": "flow-template-dialogue-wheel",
    "nodes_included": ["dialogue", "choice", "condition"]
  },

  "tags": ["dialogue", "choice", "interface", "console-friendly"],

  "sources": [
    {
      "type": "article",
      "title": "The History of Dialogue Wheels",
      "url": "https://..."
    }
  ],

  "created_at": "2026-02-04",
  "updated_at": "2026-02-04",
  "contributors": ["user-uuid"]
}
```

### 5.4 Patent Status Integration

**Approach:**

1. **Known Patents List** (manually curated)
   - Track ~50-100 game-related patents
   - Monitor expiration dates
   - Update annually

2. **Status Categories:**
   - `free` - No known patents, safe to use
   - `expired` - Was patented, now free
   - `patented` - Active patent, include holder and expiration
   - `unclear` - Potential patents, research needed

3. **Disclaimer:**
   > "Patent information is provided for reference only. This is not legal advice. Consult a patent attorney for specific concerns."

4. **Automatic Expiration Alerts:**
   - Track upcoming expirations
   - Notify users when mechanics become free

### 5.5 Community Features

**Contributions:**
- Suggest new mechanics
- Add examples from games
- Report patent information
- Create Storyarn templates

**Curation:**
- Community voting on accuracy
- Staff verification for patent claims
- Regular review cycles
- Track Nintendo/Palworld and other ongoing patent disputes

**Monetization:**
- Free: Browse mechanics, basic info
- Pro: Full details, templates, patent alerts
- Team: Custom mechanics library per workspace

---

## Part 6: Implementation Strategy

### Phase 1: Core Mechanics (50-100)
1. Identify 50-100 most common narrative/RPG mechanics
2. Write descriptions, pros/cons, examples
3. Research patent status for each
4. Create basic templates where applicable

### Phase 2: Database & API
1. Build mechanics database in PostgreSQL
2. Create API endpoints for search/browse
3. Integrate with Storyarn flow editor
4. Add "Use as template" functionality

### Phase 3: Patent Tracking
1. Compile known game patents (manual research)
2. Set up expiration monitoring
3. Add status indicators to UI
4. Create alerts for expiring patents

### Phase 4: Community
1. Submission system for new mechanics
2. Voting/verification workflow
3. Contributor attribution
4. Regular curation passes

### Phase 5: Intelligence
1. Suggest mechanics based on flow content
2. "Similar mechanics" recommendations
3. Patent risk warnings in editor
4. AI-assisted mechanic descriptions

---

## Part 7: Risks & Mitigations

| Risk                          | Mitigation                                        |
|-------------------------------|---------------------------------------------------|
| Patent information accuracy   | Strong disclaimers, "last verified" dates         |
| Legal liability               | Clear "not legal advice" messaging                |
| Maintenance burden            | Start small, community contributions              |
| Definition debates            | Be opinionated, document reasoning                |
| Scope creep                   | Strict narrative/RPG focus                        |
| Existing resource competition | Integration with Storyarn tools is differentiator |

---

## Conclusion

**A video game mechanics bank doesn't exist because:**
1. No definition consensus
2. Context-dependent classification
3. Legal complexity
4. Commercial disincentives
5. Massive maintenance burden

**Storyarn can succeed by:**
1. Limiting scope to narrative/RPG mechanics
2. Being opinionated about definitions
3. Including patent status (unique differentiator)
4. Integrating with flow editor (practical value)
5. Community contributions + curation

**Unique value proposition:**
> "The only mechanics database that tells you if it's safe to use AND gives you a template to start building."

---

## Sources

### Legal & Patents
- [MTLR: Futility of Patents on AAA Game Mechanics](https://mttlr.org/2022/10/the-futility-of-patents-on-aaa-video-game-mechanics/)
- [Columbia Law: Should Game Mechanics Be Copyrightable?](https://journals.library.columbia.edu/index.php/lawandarts/announcement/view/553)
- [UpCounsel: Game Patents](https://www.upcounsel.com/game-patents)
- [Lexology: Catch Me(chanic) if You Can](https://www.lexology.com/library/detail.aspx?g=0335550e-d67a-4044-8e12-86e347c940f1)

### Patent Databases
- [USPTO Open Data Portal](https://data.uspto.gov/)
- [PatentsView API](https://search.patentsview.org/)
- [Google Patents](https://patents.google.com/)

### Mechanics Resources
- [BoardGameGeek API](https://boardgamegeek.com/wiki/page/BGG_XML_API2)
- [Building Blocks of Tabletop Game Design](https://www.routledge.com/Building-Blocks-of-Tabletop-Game-Design-An-Encyclopedia-of-Mechanisms/Engelstein-Shalev/p/book/9781032015811)
- [Game Design Library](https://nightblade9.github.io/game-design-library/)
- [Game Programming Patterns](https://gameprogrammingpatterns.com/)

### Academic
- [Redefining MDA Framework](https://www.mdpi.com/2078-2489/12/10/395)
- [Game Mechanics Taxonomy](https://boxbase.org/entries/2015/aug/31/game-mechanics-taxonomy/)
- [Classification of Game Mechanics (2024)](https://link.springer.com/chapter/10.1007/978-981-97-2977-7_19)

### Patent Examples
- [GamesRadar: 9 Video Game Patents](https://www.gamesradar.com/video-game-patents-that-might-surprise-you/)
- [Workinman: 5 Game Patents Ending Soon](https://workinman.com/5-video-game-patents/)

### Patent Developments (2025-2026)
- [Baker Botts: Patenting Play (Dec 2025)](https://www.bakerbotts.com/thought-leadership/publications/2025/december/patenting-play)
- [Nintendo Patents Challenged at USPTO](https://www.gamesindustry.biz/nintendos-palworld-patents-challenged)
- [Future of Gaming Patent Reports](https://futureofgaming.com/)
- [katnamag Game Mechanic Database](https://katnamag.itch.io/)
- [Ludo.ai](https://ludo.ai/)
- [Dolt MySQL Parity (Dec 2025)](https://www.dolthub.com/blog/2025-12-04-dolt-is-as-fast-as-mysql/)
