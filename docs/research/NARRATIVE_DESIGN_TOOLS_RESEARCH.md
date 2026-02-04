# Narrative Design Tools Research

> **Date:** February 2024
> **Scope:** Analysis of narrative design tools for game development, focusing on dialogue systems, branching narratives, templates, and collaboration features.

---

## Table of Contents

1. [Market Overview](#1-market-overview)
2. [Tool Analysis](#2-tool-analysis)
3. [Common Problems in Dialogue Systems](#3-common-problems-in-dialogue-systems)
4. [Templates and Custom Properties](#4-templates-and-custom-properties)
5. [Collaboration Features](#5-collaboration-features)
6. [Localization Workflows](#6-localization-workflows)
7. [Variable and State Management](#7-variable-and-state-management)
8. [Export and Engine Integration](#8-export-and-engine-integration)
9. [Case Study: Disco Elysium](#9-case-study-disco-elysium)
10. [Pricing Comparison](#10-pricing-comparison)
11. [References](#11-references)

---

## 1. Market Overview

### Main Players

| Tool             | Type                | Price Model                     | Primary Engine Support  |
|------------------|---------------------|---------------------------------|-------------------------|
| articy:draft X   | Visual/Integrated   | Paid (perpetual + subscription) | Unity, Unreal           |
| Arcweave         | Cloud-based Visual  | Freemium                        | Unity, Unreal, Godot    |
| Yarn Spinner     | Text-based + Visual | Free/Open Source                | Unity                   |
| Ink/Inky         | Text-based          | Free/Open Source                | Unity, Unreal           |
| Twine            | Web-based Visual    | Free/Open Source                | Custom export           |
| Chat Mapper      | Desktop Visual      | Subscription                    | Unity                   |
| NarrativeFlow    | Desktop Visual      | Paid                            | Multiple engines        |
| StoryFlow Editor | Desktop Visual      | Paid                            | Unity, Unreal, Godot    |

### Industry Adoption

- **articy:draft** is used in major titles: Disco Elysium, Hogwarts Legacy, Suzerain, SpellForce III
- **Yarn Spinner** powers indie hits: Night in the Woods, DREDGE, A Short Hike, Frog Detective
- **Ink** is behind: 80 Days, Heaven's Vault, Highland Song
- **Arcweave** is gaining traction with indie teams for its real-time collaboration

---

## 2. Tool Analysis

### 2.1 articy:draft X

**Overview:** Professional narrative design tool developed by Articy Software GmbH. Acts as a centralized database for creating, managing, and planning branching stories, dialogues, quests, characters, and other narrative elements.

**Strengths:**
- Comprehensive game development tool with visual flowchart system
- Powerful template system for custom properties
- Global and local variables support
- Built-in flow testing
- Industry standard with proven track record

**Weaknesses:**
- Performance issues on large projects (reported by Disco Elysium developers)
- Collaboration features difficult to set up, requires version control knowledge
- Complex interface overwhelming for beginners
- Template limitations: only one instance per template/object allowed
- Cannot import its own exported XLS files
- Windows only
- articy:draft 3 has been discontinued; X is the successor but no upgrade path from perpetual licenses

**User Complaints (from Steam and forums):**
- Request for default templates for all dialogue fragments
- API documentation is confusing and incomplete
- Limited import system for external assets

### 2.2 Arcweave

**Overview:** Browser-based cloud platform for creating and managing complex branching narratives with real-time collaboration.

**Strengths:**
- Genuine real-time collaboration (multiple users simultaneously)
- Cloud-based, accessible from anywhere
- Free plugins for Unity, Unreal, and Godot
- Built-in scripting language (Arcscript)
- Integrated multimedia support
- Regular updates and active development

**Weaknesses:**
- Requires continuous internet connection
- Limited free version (200 items per project in Basic plan)
- Undo/Redo functionality issues: refreshing page loses all previous undos
- No ability to create local snapshots or backups easily
- Learning curve for new users
- Premium pricing starts at $20/month

**User Feedback (from Arcweave forums):**
- Requests for Import/Export options to create "snapshots"
- Missing Link Elements feature (connecting elements without long lines)
- No story simulation like Chat Mapper/Twine

### 2.3 Yarn Spinner

**Overview:** Dialogue tool originally developed by Secret Lab (Night in the Woods). Uses a simple scripting language called Yarn, inspired by film/theater scripts.

**Strengths:**
- Free and open-source
- Simple scripting language, easy to learn
- Good visualization of dialogue trees
- Seamless Unity integration
- Support for variables and conditional logic
- Active community

**Weaknesses:**
- Locked to Unity engine
- Visualization is passive, not interactive editing
- Still requires writing in linear markup/code
- Not a true visual authoring tool

### 2.4 Ink/Inky

**Overview:** Narrative scripting language developed by Inkle Studios. Powerful and elegant text-based system.

**Strengths:**
- Extremely powerful for complex narratives
- Free and open-source
- Elegant, pure writing experience
- Works with Unity and Unreal
- Lightweight runtime format, portable across platforms

**Weaknesses:**
- Requires programming mindset
- No visual flow representation
- Limited UI, primarily code-based
- Steeper learning curve for non-developers
- Integration setup can be challenging

### 2.5 Other Notable Tools

**Twine:**
- Free, open-source, beginner-friendly
- Web-based, no installation required
- Difficult to collaborate in teams
- No line comments for feedback

**Chat Mapper:**
- Conversation Simulator for testing
- Automatic screenplay script generator
- Built-in localization support
- Expensive subscription ($420-$1,320/year)

**NarrativeFlow:**
- Attach properties (VO files, images, animations) to nodes
- Script view for document-like editing
- Works with multiple engines

---

## 3. Common Problems in Dialogue Systems

### 3.1 Exponential Scaling

> "About 80% of first dialogue system implementations fail because branching narratives scale exponentially while linear code scales linearly—the architecture is doomed before you write the first line."

The mismatch between how developers PLAN narratives (spatially, with flowcharts) and how they IMPLEMENT them (linearly in code) creates bugs.

### 3.2 Labor Intensity

Anticipating player options is "phenomenally labor intensive." Each option and its consequences must be pre-written. If selections have effects outside dialogue, those may need scripting and art assets. Work increases exponentially with each new branch.

**Example:** Disco Elysium contains over 1 million words of dialogue. Writing team members worked "constantly in the nine months leading up to release, regularly skipping sleep and taking stimulants to stay awake."

### 3.3 Consistency and Logic

Major challenges include:
- Maintaining consistency (spelling NPC names the same in every branch)
- Tracking variables (does the game remember the player was rude earlier?)
- Handling logic checks (what happens if the player already bribed the guard?)
- Avoiding plot holes or contradictions that break immersion

### 3.4 Collaboration Friction

Common frustrations:
- Writers asking programmers to make dozens of changes (slow, frustrating)
- Writers learning to edit code (risky, error-prone)
- Localization causing version control to explode with merge conflicts "becoming hourly events"

### 3.5 The "Illusion of Choice" Problem

Game dialogue is "frozen text"—since all dialogue is written before the player makes choices, the story cannot truly be "responding" to decisions. Players are exploring a pre-built narrative tree.

### 3.6 Expert Scarcity

Writing for games requires skills "exclusive to the medium." Branching dialogue trees are "a medium within a medium" requiring additional skillsets. The number of writers who can truly produce great work with dialogue trees is estimated at "less than several dozen" globally.

---

## 4. Templates and Custom Properties

### 4.1 articy:draft Template System

articy:draft offers a comprehensive template system where users can define custom properties for different dialogue types (quest dialogues, shop interactions, tutorials, etc.).

**Reported Limitations:**
- Only allows one template instance per object
- Same input data forced to duplicate templates
- No object instances with customized values in object lists
- No default template assignment for new nodes
- Users requested "default template for all dialogue fragments" functionality

### 4.2 General Industry Approach

Most tools handle custom properties differently:
- **Arcweave:** Components system for reusable property sets
- **Yarn Spinner:** Tags and metadata in script
- **Ink:** Variables and tags inline

### 4.3 User Needs

Based on forum discussions and reviews:
- Ability to define project-specific fields
- Inheritance from character/speaker to their dialogues
- Quick application of presets without complex setup
- Export of custom properties to game engines

---

## 5. Collaboration Features

### 5.1 Real-Time Collaboration

**Arcweave** leads in this area with browser-based real-time editing. Multiple team members can work simultaneously on the same project.

**articy:draft X** offers version control integration but requires:
- Knowledge of version control systems
- Local network setup
- More complex configuration

### 5.2 What Teams Need

According to industry research, creative teams need:
- Real-time text and content editing for multiple collaborators
- Seamless communication through in-project comments and notifications
- Version tracking to prevent lost work
- Multimedia and assets integration
- Project/deadline management

### 5.3 Current Gaps

- **Twine:** Difficult to collaborate or gain feedback through line comments
- **Ink/Inky:** No built-in collaboration
- **Yarn Spinner:** No collaboration features
- **articy:draft:** Collaboration is possible but complex to set up

---

## 6. Localization Workflows

### 6.1 Scale of the Problem

In larger games like Darktide (Fatshark):
- ~11,000 strings for UI
- ~5,000 strings for dialogue
- 12 languages supported
- Results in massive data management challenges

### 6.2 Common Issues

- Localization often treated as an afterthought
- Fragmented data across systems
- Lack of LQA (Linguistic Quality Assurance)
- Manual effort for importing/exporting data sheets
- Missing context for translators (character genders, situations)
- Languages like French, German, Spanish take 30%+ more space than English

### 6.3 Best Practices

- Don't hardcode strings
- Store strings externally from the start
- Internationalize during development, not after
- Provide context (time, setting, characters, environment)
- Use flexible designs that accommodate text expansion
- Keep localizable assets separate from code

### 6.4 Tool-Specific Issues

**articy:draft:** Cannot import its own exported XLS files. Copy-paste is the only viable option for external assets.

**Yarn Spinner:** Has localization support built-in.

**Chat Mapper:** Built-in localization support mentioned as a strength.

---

## 7. Variable and State Management

### 7.1 State Machine Fundamentals

State machines are used to control game behavior including animations, AI, dialogue, and interactions. They define different states and transitions between them.

Best practices:
- Use descriptive names and comments
- Group states into categories or hierarchies
- Consider substates (nested within another state)
- Use parameters to customize state behavior
- Use variables to store values affecting conditions or actions

### 7.2 Local vs Global Variables

- **Local variables:** Accessible only from the given graph/context
- **Global variables:** Accessible from every graph
- Both can be accessed from code or visual graphs

### 7.3 Scalability Warning

> "State machines have a lot of scalability problems. While for short conversations it might be sustainable, it quickly becomes too complex or difficult to author in long-term interactions."

### 7.4 Disco Elysium's Approach

The game uses "micro-reactivity" where it remembers and responds to trivial decisions. Example: shaving off mutton chops flips a boolean that affects all future dialogue mentioning the beard.

This technique has "a tendency to cause ripples—which is a polite way of saying it can break your game."

---

## 8. Export and Engine Integration

### 8.1 Common Formats

- **JSON:** Preferred for nested choices and conditional expressions
- **CSV:** Reserved for flat catalogs (speakers, VO metadata, localization)
- **XML:** Supported by some tools alongside JSON

### 8.2 Integration Challenges

**Unity:**
- Map JSON entries into ScriptableObjects or C# classes
- Many tools focus primarily on Unity

**Unreal:**
- Data Assets or Data Tables for blueprint-friendly access
- Plugin updates can introduce breaking changes

**Godot:**
- Many Unity-focused tools are difficult to implement in Godot
- Arcweave provides official Godot support

### 8.3 Common Problems

- Edge cases when choices reference missing target line_ids
- Cyclic references causing infinite traversal
- Non-deterministic exports causing diff/review issues
- Inconsistent import caching

### 8.4 Best Practices

- Importers should log errors and fallback to safe defaults
- Guard against cyclic references
- Ensure deterministic JSON/CSV exports for reliable version control
- Use JSON for graphs, CSV for flat tables

---

## 9. Case Study: Disco Elysium

### 9.1 Tool Usage

Disco Elysium used articy:draft for its dialogue system. According to writer Helen Hindpere, articy:draft is "definitely responsible for how wordy the game ended up being. There's something very inspiring about those forest green dialogue trees sprawling out on the screen."

### 9.2 Scale

- Over 1 million words of dialogue
- Thousands of micro-reactive moments
- Example: 4 unique call signs required 428 new dialogue cards, all localized and voice acted

### 9.3 Technical Challenges

Other developers noted:
- articy:draft has "its own set of problems specifically awful performance on huge projects"
- "Getting it all debugged, loop-free and free of tons of logical errors is very hard"
- Given the number of variables, developers consider the Disco Elysium team "geniuses"

### 9.4 Micro-Reactivity

ZA/UM's technique where the game remembers trivial decisions:

> "At a certain point you might get the chance to shave off the horrendous mutton chops your character starts with. If you do, the game will flip a boolean switch to tell us, whenever your beard gets mentioned, to check whether you still have it and present you a different dialogue option accordingly."

This approach is avoided by some designers because it "has a tendency to cause ripples."

### 9.5 Writing Philosophy

Writer Justin Keenan believes the system works because "on some level, it's utterly meaningless." The function is "primarily aesthetic or textural, as opposed to instrumental"—differentiating it from typical RPG dialogue systems.

---

## 10. Pricing Comparison

### 10.1 articy:draft X

| Plan                       | Price        | Notes                         |
|----------------------------|--------------|-------------------------------|
| FREE                       | €0           | 700 objects limit per project |
| Single User (perpetual)    | €99 one-time | No collaboration              |
| Single User (subscription) | €5.99/month  | No collaboration              |
| Team Basic                 | €49/month    | 2 users                       |
| Team Professional          | €59/month    | 3 users + 2 viewers           |
| Team Premium               | €99/month    | 4 users + 5 viewers           |
| Multi-user license         | ~€1,200/user | Enterprise                    |

**Note:** No upgrade path from articy:draft 3 perpetual to articy:draft X.

### 10.2 Arcweave

| Plan         | Price      | Limits                     |
|--------------|------------|----------------------------|
| Basic (Free) | €0         | 3 projects, 200 items each |
| Pro          | $20+/month | Unlimited                  |
| Team         | Custom     | Multiple seats             |

### 10.3 Free Options

- **Yarn Spinner:** Completely free, open-source
- **Ink/Inky:** Completely free, open-source
- **Twine:** Completely free, open-source
- **Monologue:** Free, open-source
- **Manuskript:** Free, open-source

### 10.4 Other Paid Options

- **Chat Mapper:** $420 or $1,320/year
- **Dialogue System for Unity:** €78.20 one-time
- **NarrativeFlow:** Paid (pricing varies)

---

## 11. References

### Tool Documentation & Official Sites

- [articy:draft X Official](https://www.articy.com/en/)
- [articy:draft Help - Dialogues](https://www.articy.com/help/adx/Flow_Dialog.html)
- [articy:draft Pricing](https://www.articy.com/shop/pricing/pricing-options/)
- [articy:draft X FREE](https://www.articy.com/en/articydraft/free/)
- [Arcweave Official](https://arcweave.com/)
- [Arcweave Documentation](https://docs.arcweave.com/workspaces/overview)
- [Arcweave Integrations](https://arcweave.com/integrations)
- [Yarn Spinner](https://yarnspinner.dev/)
- [Ink/Inky by Inkle](https://www.inklestudios.com/ink/)

### Reviews & Comparisons

- [Arcweave Blog - Top 10 Tools for Narrative Design](https://blog.arcweave.com/top-10-tools-for-narrative-design)
- [StoryFlow Blog - Best Narrative Design Tools 2025](https://storyflow-editor.com/blog/best-narrative-design-tools-for-game-developers-2025/)
- [NarrativeFlow - Tool Comparison](https://narrativeflow.dev/blog/twine-vs-yarn-spinner-vs-ink-vs-narrativeflow-which-branching-dialogue-tool-is-right-for-your-game/)
- [SaaSHub - Arcweave vs articy:draft](https://www.saashub.com/compare-arcweave-vs-articy-draft)
- [AlternativeTo - articy:draft Alternatives](https://alternativeto.net/software/articy-draft/)
- [G2 - Arcweave Reviews](https://www.g2.com/products/arcweave/reviews)
- [Capterra - articy:draft 3](https://www.capterra.com/p/246158/articydraft3/)
- [SourceForge - articy:draft Reviews](https://sourceforge.net/software/product/articy-draft/)

### Industry Articles

- [Game Developer - Disco Elysium Writing Analysis](https://www.gamedeveloper.com/business/understanding-the-meaningless-micro-reactive-and-marvellous-writing-of-i-disco-elysium-i-)
- [Game Developer - Branching Conversation Systems Part 1](https://www.gamedeveloper.com/design/branching-conversation-systems-and-the-working-writer-part-1-introduction)
- [Game Developer - Branching Conversation Systems Part 2](https://www.gamedeveloper.com/design/branching-conversation-systems-and-the-working-writer-part-2-design-considerations)
- [Game Developer - Building Branching Narrative on a Budget](https://www.gamedeveloper.com/design/how-to-build-branching-narrative-when-you-don-t-have-a-big-budget-)
- [Game Developer - Best Free Tools for Narrative Games](https://www.gamedeveloper.com/game-platforms/the-best-free-tools-for-narrative-games)
- [StoryFlow Blog - The Branching Dialogue Nightmare](https://storyflow-editor.com/blog/branching-dialogue-nightmare-how-to-fix/)
- [Kreonit - Nonlinear Gameplay Mechanics](https://kreonit.com/programming-and-games-development/nonlinear-gameplay/)

### Localization

- [Gridly - Game Localization Guide](https://www.gridly.com/blog/game-localization-guide/)
- [Gridly - Fatshark Localization Best Practices](https://www.gridly.com/blog/fatshark-game-localization-best-practices/)
- [Lokalise - Game Localization](https://lokalise.com/blog/game-localization/)
- [LocalizeDirect - Indie Game Localization](https://www.localizedirect.com/posts/indie-game-localization-best-practices)

### Community Discussions

- [Steam - articy:draft Default Template Discussion](https://steamcommunity.com/app/230780/discussions/0/357286663681344464/)
- [Steam - articy:draft Pricing Discussion](https://steamcommunity.com/app/570090/discussions/0/135509124606371262/)
- [Arcweave Forum - Feature Requests](https://arcweave.com/forum/discussion/feature-requests-suggestions/suggestions-on-improvements)
- [Arcweave Forum - Roadmap](https://arcweave.com/roadmap)
- [Unity Discussions - Story Telling Tools](https://forum.unity.com/threads/story-telling-game-design-tool.147080/)
- [Interactive Fiction Forum - Tools Discussion](https://intfiction.org/t/tools-for-writing-and-narrative-design/69196)

### Technical Resources

- [Game Programming Patterns - State](https://gameprogrammingpatterns.com/state.html)
- [PulseGeek - Export Narrative Data](https://pulsegeek.com/articles/export-narrative-data-to-unity-or-unreal/)
- [Medium - Integrating Ink with Unreal Engine 5](https://medium.com/@Jamesroha/integrating-ink-with-unreal-engine-5-a-comprehensive-guide-be4fd0ec6a3e)
- [Pixel Crushers - Dialogue System for Unity](https://www.pixelcrushers.com/dialogue_system/manual2x/html/articy_draft.html)

### Case Studies

- [Articy Showcase - Disco Elysium](https://www.articy.com/en/showcase/disco-elysium/)
- [Disco Elysium Dialogue Analysis](https://gencguimond.com/blog/f/disco-elysium---an-analysis-of-dialogue)
- [Arcweave Blog - Collaborative Writing Tools](https://blog.arcweave.com/top-5-tools-for-real-time-collaborative-writing)
