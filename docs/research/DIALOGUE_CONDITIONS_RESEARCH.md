# Research: Condition Placement in Dialogue Systems

> **Date**: February 2026
> **Scope**: Investigation of how professional narrative design tools handle conditions and branching logic
> **Tools analyzed**: articy:draft, Arcweave, Chat Mapper, Ink, Yarn Spinner, Twine, Dialogic

---

## 1. Tool Analysis

### 1.1 articy:draft

**How conditions work:**
- Conditions are placed on **input pins** of flow nodes
- Instructions (side effects) are placed on **output pins**
- Dedicated **Condition nodes** for if/else branching (binary: true/false outputs)
- Pins with conditions/instructions are highlighted in **orange**

**From official documentation:**
> "Conditions can be used at three different places: At input-pins of flow nodes, in dedicated condition nodes and inside script fields of object templates."
>
> "Conditions always go into the input pin, as something is checked to determine if the node will even be accessible. Instructions are placed in the output pin to change some value or state after going through this node."

**Source**: [articy Help - Conditions & Instructions](https://www.articy.com/help/adx/Scripting_Conditions_Instructions.html)

**Notable users**: Disco Elysium, Suzerain, Saint Kotar, SpellForce III, Hogwarts Legacy

---

### 1.2 Arcweave

**How conditions work:**
- Uses **Branch nodes** for all conditional logic
- Branches support if/elseif/else with multiple outputs
- Connections can have arcscript in labels, but primarily for side effects
- One mandatory `if`, optional `elseif` (unlimited), optional `else`

**From official documentation:**
> "Branches are Arcweave items that allow you to direct the story flow according to conditions being true or false. They consist of arcscript expressions in the form of if, elseif, and else."
>
> "Branches are a friendly, visual way to implement logic in your story."

**Source**: [Arcweave Docs - Branches](https://arcweave.com/docs/1.0/branches)

---

### 1.3 Chat Mapper

**How conditions work:**
- Conditions and Scripts are attached to **nodes**, not connections
- **Visual indicators**: Blue dots = conditions, Pink dots = scripts
- **Groups** (branch nodes) evaluate true/false and split conversation
- **Dialog nodes** are the content leaves
- Priority system when multiple nodes are valid

**From documentation:**
> "Scripts are things you want to do — assign or increment a variable. Conditions are evaluated before a node is displayed, and based on the result the node will be visualized, or not."
>
> "Now we have a little pink dot on the node and that shows we have a script attached. Blue dots indicate conditions. So by looking at the tree we can easily see which nodes have conditions."

**Source**: [Chat Mapper Tutorial - Scripting](https://www.chatmapper.com/media/game-design-scripting-class-part1of2/)

---

### 1.4 Ink (Inkle Studios)

**How conditions work:**
- Markup-based, conditions are **inline in the text**
- Uses `{condition}` syntax for conditionals
- Switch-like structure available
- No visual graph - pure text-based

**Design philosophy:**
> "Markup, not programming: Text comes first, code and logic are inserted within."
>
> "The very loose structure means writers can get on and write, branching and rejoining without worrying about the structure they're creating as they go."

**Source**: [Ink Documentation](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md)

**Notable users**: 80 Days, Heaven's Vault, Sorcery! series

---

### 1.5 Yarn Spinner

**How conditions work:**
- Script-based with conditional jumps
- Variables and conditional logic in the script
- Halfway between Ink's scripting and visual tools

**Characteristics:**
> "Its support for variables and conditional logic makes the tool incredibly versatile."
>
> "It uses a simple scripting language called Yarn, inspired by formats like film or theater scripts."

**Source**: [NarrativeFlow Comparison](https://narrativeflow.dev/blog/twine-vs-yarn-spinner-vs-ink-vs-narrativeflow-which-branching-dialogue-tool-is-right-for-your-game/)

**Notable users**: Night in the Woods, A Short Hike, DREDGE, Frog Detective

---

### 1.6 Twine

**How conditions work:**
- Conditions are placed in **passages** (nodes), not links
- Uses `(if:)` macros in Harlowe format
- **Setter links** can execute code: `[[text|passage][$var = value]]`
- Setter links are for side effects, not routing

**Important caveat:**
> "The setter statement is executed with the current values of the variables at the end of the passage - not the values they had when the link statement occurred."

**Source**: [Twine Cookbook](https://twinery.org/cookbook/)

---

### 1.7 Dialogic (Godot)

**How conditions work:**
- Timeline-based with event blocks
- Condition events as blocks in the timeline
- No native node graph view (frequently requested)

**User feedback requesting node view:**
> "A node-based workflow is generally better for those with less development experience (artists and writers). It's also an (arguably) cleaner way to see the different sections of the branching conversations."
>
> "Some users think it would make this the de facto dialog plugin for Godot."

**Source**: [Dialogic GitHub Issue #2081](https://github.com/dialogic-godot/dialogic/issues/2081)

---

## 2. Comparison Table

| Tool | Conditions Location | Branching Method | Side Effects Location | Visual Indicators |
|------|---------------------|------------------|----------------------|-------------------|
| articy:draft | Input pins (nodes) | Condition nodes (binary) | Output pins (nodes) | Orange pins |
| Arcweave | Branch nodes | if/elseif/else in Branch | Code in labels | Branch node icon |
| Chat Mapper | Node properties | Group nodes | Script on nodes | Blue/pink dots |
| Ink | Inline in text | Conditional markup | Inline | N/A (text-based) |
| Yarn Spinner | Script in node | Conditional jumps | Commands in node | N/A (text-based) |
| Twine | Passages | (if:) in passage | Setter links | N/A |
| Dialogic | Timeline events | Condition events | Events | Block colors |

---

## 3. User Feedback & Opinions

### 3.1 articy:draft Users

**Positive:**
> "The software has a bit of a learning curve, but once you're familiar with it, you really can do some amazing organizational stuff with it."
> — Steam Community

> "Make no mistake; there is a learning curve to this tool as with any professional grade software. Once you've learned it, the productivity you'll gain will more than make up the initial learning time."
> — Steam Review

**Pain points:**
> "The API was confusing and not well documented at this time."
> — GameDev.net

> "The docx export is difficult to read, almost to the point of being useless as a general purpose document."
> — Steam Forum

**Source**: [Steam Community articy:draft](https://steamcommunity.com/app/230780/discussions/)

---

### 3.2 Arcweave Users

**Positive:**
> "Easy to use even if you're not a programmer. It's really for everyone."
> — G2 Reviews

> "Most other tools felt overwhelming and overcomplicated. We wanted something intuitive that wouldn't stop the flow of writing. The fact that Arcweave was browser-based was probably the deciding factor."
> — User review

> "Complex narrative organisation and structuring is made much easier with Arcweave by allowing creators to visually map out their story."
> — G2 Reviews

**Historical feedback:**
> "Some users found disappointment in a lack of features, specifically around conditional statements and variables."
> — G2 Reviews (note: arcscript has since been added)

**Source**: [G2 Arcweave Reviews](https://www.g2.com/products/arcweave/reviews)

---

### 3.3 Ink Users

**Positive:**
> "Thanks again for all of your work in designing and polishing Ink—everyone who's used it at Campo is in love with this tool!"
> — GitHub Issues

**Design philosophy feedback:**
> "Some users have requested starting a forum specifically for writers to talk to each other, not just developers."
> — GitHub Discussions

**Source**: [Ink GitHub](https://github.com/inkle/ink)

---

### 3.4 General Dialogue System Feedback

**On visual complexity:**
> "Your if/else statements are getting a little messy, but nothing you can't handle. At 100 nodes, the awful truth hits you: you can't track which conversations affect which outcomes, your choices don't actually change anything meaningful, and every time you add one branch, you somehow break three others."
> — StoryFlow Blog

**On spaghetti patterns:**
> "Once you get to the point of not being able to visualise your dependency graph without crossing lines, you've truly embraced the Spaghetti Pattern."
> — Medium (Unity Architecture)

**On node-based vs text-based:**
> "Some developers find .json the fastest to edit and manipulate, since it's basically a text file - No need for graph nodes or other visual UI that gets cluttered when the game grows large."
> — Dialogic GitHub Discussion

**Sources**:
- [StoryFlow Blog](https://storyflow-editor.com/blog/branching-dialogue-nightmare-how-to-fix/)
- [Medium - Spaghetti Pattern](https://medium.com/@simon.nordon/unity-architecture-spaghetti-pattern-7e995648c7c8)

---

## 4. Case Study: Disco Elysium

**Tool used**: articy:draft

**Technique**: "Micro-reactivity" - thousands of small boolean checks

**How it works:**
> "At a certain point you might get the chance to shave off the horrendous mutton chops your character starts with. If you do, the game will flip a boolean switch to tell us, whenever your beard gets mentioned, to check whether you still have it and present you a different dialogue option accordingly."
>
> "There are probably thousands of these micro-reactive moments in the game."

**Writer perspective:**
> "articy:draft is definitely responsible for how wordy the game ended up being. There's something very inspiring about those forest green dialogue trees sprawling out on the screen."
> — Helen Hindpere, Writer

**Coordination:**
> "The team used the tool to coordinate among writers, ensuring that whenever someone came up with a new idea—like a new voice for one of the skills—it could be reflected across every dialogue."

**Source**: [Game Developer - Disco Elysium Analysis](https://www.gamedeveloper.com/business/understanding-the-meaningless-micro-reactive-and-marvellous-writing-of-i-disco-elysium-i-)

---

## 5. Best Practices from Industry

### 5.1 On Condition Placement

**From The Game Kitchen (Blasphemous developers):**
> "Condition. This is a kind of Action which will check whether the necessary conditions are met to execute the node or not. There are two types of conditions; the 'blocking' and the 'passthrough'."

**Source**: [The Game Kitchen Blog](https://thegamekitchen.com/designing-a-dialog-system-for-chapter-two/)

### 5.2 On Managing Complexity

**From branching narrative guide:**
> "Variables are a very effective way to convince players that the world reacts to their actions. However, be careful not to make too many—while cheaper than branches, they still add complexity that needs to be maintained and tested."

**Source**: [Adam Mirkowski - Branching Narrative](https://adammirkowski.substack.com/p/how-to-write-a-branching-narrative)

### 5.3 On Visual Systems

**From StoryFlow analysis:**
> "Use graph-based editors to visualize conversation flows spatially, making problems immediately apparent and enabling non-programmer collaboration."

**Source**: [StoryFlow Blog](https://storyflow-editor.com/blog/branching-dialogue-nightmare-how-to-fix/)

### 5.4 On State Management

**General principle:**
> "Track relationship values as numeric ranges rather than booleans, providing greater flexibility for conditional dialogue branches."

**Source**: [StoryFlow Blog](https://storyflow-editor.com/blog/branching-dialogue-nightmare-how-to-fix/)

---

## 6. Technical Approaches to Edges vs Nodes

### 6.1 Graph Theory Perspective

> "Edges are connections between nodes. They can be directed, meaning that they have a direction. Dialogues generally are directed graphs, since a choice (an edge) is a connection from one prompt (node) to another in only one direction."

**Source**: [Video Game Dialogues and Graph Theory](https://philipphagenlocher.de/post/video-game-dialogues-and-graph-theory/)

### 6.2 Data-Aware Approaches

**Typed edges concept:**
> "Blue edges designate the timeline of the dialogue (sequence of nodes), while other edges designate data-dependencies between nodes. These are called timeline edges and dependency edges."

**Source**: [Data-Aware Dialogues](https://philipphagenlocher.de/post/data-aware-dialogues-for-video-games/)

### 6.3 The Game Kitchen Implementation

**Both approaches supported:**
> "Select Choice: Given a set of edges, take the destination nodes and check if they meet their condition or in the case they don't, check if they are not blocking conditions."

This suggests checking conditions on the **destination node**, not on the edge itself.

**Source**: [The Game Kitchen Blog](https://thegamekitchen.com/designing-a-dialog-system-for-chapter-two/)

---

## 7. Summary of Findings

### Where tools place conditions:

| Aspect                            | Common Pattern                                 |
|-----------------------------------|------------------------------------------------|
| **Visibility/availability check** | On destination node (input pin, node property) |
| **Branching logic**               | Dedicated condition/branch nodes               |
| **Side effects**                  | Output pins, scripts on nodes, or inline       |
| **Response availability**         | On the response/choice itself                  |

### What was NOT found:

- No major tool uses conditions primarily on edges/connections for routing
- No user feedback praising edge-based conditions
- No documentation recommending edge-based conditions as best practice

### Visual indicators pattern:

- articy: Orange pins
- Chat Mapper: Colored dots (blue = conditions, pink = scripts)
- Arcweave: Branch node icons
- Text-based tools: N/A

---

## 8. Sources Index

1. [articy Help - Conditions & Instructions](https://www.articy.com/help/adx/Scripting_Conditions_Instructions.html)
2. [articy Help - Pins and Connections](https://www.articy.com/help/adx/Flow_PinsConnections.html)
3. [Arcweave Docs - Branches](https://arcweave.com/docs/1.0/branches)
4. [Arcweave Docs - Connections](https://arcweave.com/docs/1.0/connections)
5. [Chat Mapper Tutorial - Scripting](https://www.chatmapper.com/media/game-design-scripting-class-part1of2/)
6. [Ink Documentation](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md)
7. [NarrativeFlow Tool Comparison](https://narrativeflow.dev/blog/twine-vs-yarn-spinner-vs-ink-vs-narrativeflow-which-branching-dialogue-tool-is-right-for-your-game/)
8. [Twine Cookbook](https://twinery.org/cookbook/)
9. [Dialogic GitHub Issue #2081](https://github.com/dialogic-godot/dialogic/issues/2081)
10. [G2 Arcweave Reviews](https://www.g2.com/products/arcweave/reviews)
11. [Steam Community articy:draft](https://steamcommunity.com/app/230780/discussions/)
12. [Game Developer - Disco Elysium](https://www.gamedeveloper.com/business/understanding-the-meaningless-micro-reactive-and-marvellous-writing-of-i-disco-elysium-i-)
13. [StoryFlow - Branching Dialogue](https://storyflow-editor.com/blog/branching-dialogue-nightmare-how-to-fix/)
14. [The Game Kitchen Blog](https://thegamekitchen.com/designing-a-dialog-system-for-chapter-two/)
15. [Video Game Dialogues and Graph Theory](https://philipphagenlocher.de/post/video-game-dialogues-and-graph-theory/)
16. [Data-Aware Dialogues](https://philipphagenlocher.de/post/data-aware-dialogues-for-video-games/)
17. [Adam Mirkowski - Branching Narrative](https://adammirkowski.substack.com/p/how-to-write-a-branching-narrative)
18. [Medium - Spaghetti Pattern](https://medium.com/@simon.nordon/unity-architecture-spaghetti-pattern-7e995648c7c8)
