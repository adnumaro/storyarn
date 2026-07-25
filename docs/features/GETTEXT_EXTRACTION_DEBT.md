# Gettext extraction debt

**Status:** not done. Deferred out of the Slice 7.2a audit remediation by owner
decision (2026-07-25) because running the fix repo-wide pulls ~88 unrelated new
messages into a feature PR. This file is a specification for a later,
self-contained change.

**Measured against:** `codex/slice7-2a-managed-explanation` at `e2be4da1`, where
the `flows` domain has already been extracted and translated. Every number below
excludes `flows`.

## Objective

Make `priv/gettext/*.pot` reflect the source tree, so the parity guard that
already exists starts protecting Spanish users instead of passing vacuously.

## The actual defect: a guard that cannot fail

`test/storyarn/publication/locales_test.exs` already enforces catalog
completeness. `assert_complete_gettext_catalog/3` (`:70-84`) asserts that each
`priv/gettext/<locale>/LC_MESSAGES/<domain>.po`:

- contains **exactly** the message keys of `priv/gettext/<domain>.pot`
  (`:75` — "must contain exactly the messages from `<domain>.pot`"), and
- has a non-empty `msgstr` for every one of them (`translated?/2` at `:166-173`,
  which also checks every plural index).

That is the right assertion. It does not help, because **nothing checks the
`.pot` against the source code.** A `dgettext` call that was never extracted is
absent from the `.pot` *and* from every `.po`, so the sets match and the test is
green while the string renders in English for Spanish users.

So the work is not "translate some strings". It is:

1. bring every `.pot` up to date with the source,
2. translate what that surfaces,
3. add the one missing guard — that extraction is up to date — so this cannot
   silently accumulate again.

## Current state, measured

Reproduce with:

```bash
mix gettext.extract --merge          # writes .pot and merges into every .po
git status --short priv/gettext/     # scope of the drift
git checkout -- priv/gettext/        # discard, this is a measurement only
```

Unextracted messages per domain (identical counts for `en` and `es` unless
noted):

| Domain         | New messages | Obsolete (removed) | Reworded (fuzzy) |
| -------------- | ------------ | ------------------ | ---------------- |
| `projects`     | **69**       | 13                 | 8                |
| `scenes`       | 8            | 7                  | 4                |
| `integrations` | 4            | 0                  | 0                |
| `sheets`       | 3            | 4                  | 2                |
| `identity`     | 2 (`es`: 1)  | 11 (`es`: 24)      | 2 (`es`: 1)      |
| `localization` | 1            | 2                  | 0                |
| `workspaces`   | 1            | 0                  | 3                |
| `settings`     | 0            | 2                  | 0                |
| `versioning`   | 0            | 2                  | 0                |

**~88 new messages**, plus obsolete entries to drop and fuzzy entries to review.
`projects` is 78% of the work on its own.

Separately, three messages are already extracted but never translated into
Spanish — these are real, user-visible English text today:

- `priv/gettext/es/LC_MESSAGES/identity.po` — 2
- `priv/gettext/es/LC_MESSAGES/versioning.po` — 1

Find them with:

```bash
python3 - <<'PY'
import re, glob
for f in sorted(glob.glob("priv/gettext/es/LC_MESSAGES/*.po")):
    s = open(f).read()
    for m in re.findall(r'msgid "((?:[^"\\]|\\.)+)"\nmsgstr ""\n', s):
        print(f, "->", m)
PY
```

## Proposed change

Land it **per domain, one commit each**, smallest first. `projects` last and
alone — 69 messages is its own review.

For each domain:

1. `mix gettext.extract --merge`, then `git checkout -- priv/gettext/` for every
   domain except the one being done. (There is no per-domain extract flag; this
   selective-revert is the same approach the `flows` commit used.)
2. Translate every new `msgstr` in `es`. `en` msgstrs stay empty by convention —
   Gettext falls back to the msgid, which is already English.
3. Review each `#, fuzzy` entry: the source string changed, so the existing
   translation may be wrong rather than merely stale. Remove the flag only after
   confirming or rewriting the translation.
4. Delete obsolete entries rather than leaving `#~` blocks.
5. `mix test test/storyarn/publication/locales_test.exs` must stay green.

**Translation conventions** (from `docs/conventions/` and existing catalogs):

- Keep English product/technical terms untranslated: *flow*, *sheet*, *scene*,
  *workspace*, *hub*, *jump*, *subflow*, *entry*, *exit*, *sequence*, *API key*.
- Preserve every interpolation exactly, including the `%{name}` form and plural
  indexes. A dropped placeholder is a runtime crash, not a typo.
- Match the register of the surrounding catalog — the existing Spanish uses
  informal second person ("Selecciona…", "Vuelve a…").

## The guard to add

Without this, the debt returns. Add to `test/storyarn/publication/locales_test.exs`
a test that extraction is up to date. Two viable shapes:

- **Preferred:** run the extractor into a temporary directory and assert the
  resulting `.pot` message-key sets equal the committed ones. Pure, no working
  tree mutation. `Gettext.Extractor` is the internal API; check whether the
  installed version exposes a usable entry point before committing to this.
- **Fallback:** a `just` / CI step that runs `mix gettext.extract --merge` and
  fails if `git diff --exit-code priv/gettext/` is non-empty. Simpler and
  certain, but it mutates the working tree, so it belongs in CI rather than in
  `mix test`.

Either way the failure message must name the consequence, following the
precedent at `test/storyarn/flows/finding_dismissals_test.exs:213-232` — that
test says a missing label means "the dismiss form would render the raw i18n key",
which is why it is actionable.

## Verification / Definition of Done

- `mix gettext.extract --merge` produces **no** diff in `priv/gettext/`.
- Zero `msgstr ""` in any `priv/gettext/es/LC_MESSAGES/*.po` (the snippet above
  returns nothing).
- Zero `#, fuzzy` and zero `#~` obsolete blocks.
- `mix test test/storyarn/publication/locales_test.exs` green, now including the
  new extraction guard.
- `mix precommit` and `just quality` green.
- Spot-check two translated flashes in the running app with the locale set to
  `es`, since a green catalog only proves the string exists, not that it reads
  well in context.

## Non-goals

- Adding a locale. Only `en` and `es` are published; this is about completing
  them.
- Touching the Vue JSON catalogs under `assets/app/locales/`. Those are already
  guarded structurally by `assert_complete_vue_catalogs/0`
  (`locales_test.exs:86-107`), which compares catalog files, leaf key paths and
  blank values across locales — a genuinely different mechanism from `.po`.
- Re-translating existing non-fuzzy entries. If a translation is wrong, that is a
  separate report.
- The `flows` domain. Done in `e2be4da1`; if `mix gettext.extract` shows drift
  there again, it is new drift, not this backlog.
