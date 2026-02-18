#!/usr/bin/env python3
"""
gettext_split.py

Transforms gettext() calls to dgettext("domain", ...) based on file path.
Handles all four forms:
  A) gettext("x")                                    → dgettext("DOMAIN", "x")
  B) ngettext("s", "p", n)                           → dngettext("DOMAIN", "s", "p", n)
  C) Gettext.gettext(StoryarnWeb.Gettext, "x")       → Gettext.dgettext(StoryarnWeb.Gettext, "DOMAIN", "x")
  D) Gettext.ngettext(StoryarnWeb.Gettext, "s","p",n)→ Gettext.dngettext(StoryarnWeb.Gettext, "DOMAIN", "s","p",n)

Files in the `default` domain are NOT modified.
authorize.ex is explicitly skipped (uses module form but stays in default).
"""

import os
import re
import sys

# ---------------------------------------------------------------------------
# Domain routing table
# Keys are path prefix strings (relative to lib/).
# First match wins → order matters (more specific first).
# ---------------------------------------------------------------------------
DOMAIN_RULES = [
    # flows
    ("storyarn_web/live/flow_live/", "flows"),
    ("storyarn_web/components/condition_builder.ex", "flows"),
    ("storyarn_web/components/instruction_builder.ex", "flows"),
    ("storyarn_web/components/sidebar/flow_tree.ex", "flows"),

    # maps
    ("storyarn_web/live/map_live/", "maps"),
    ("storyarn_web/components/sidebar/map_tree.ex", "maps"),

    # sheets
    ("storyarn_web/live/sheet_live/", "sheets"),
    ("storyarn_web/components/block_components.ex", "sheets"),
    ("storyarn_web/components/block_components/", "sheets"),
    ("storyarn_web/components/audio_picker.ex", "sheets"),
    ("storyarn_web/components/sidebar/sheet_tree.ex", "sheets"),
    ("storyarn/sheets/versioning.ex", "sheets"),

    # localization
    ("storyarn_web/live/localization_live/", "localization"),

    # projects
    ("storyarn_web/live/project_live/", "projects"),

    # workspaces
    ("storyarn_web/live/workspace_live/", "workspaces"),
    ("storyarn_web/live/settings_live/workspace_members.ex", "workspaces"),
    ("storyarn_web/live/settings_live/workspace_general.ex", "workspaces"),

    # screenplays
    ("storyarn_web/live/screenplay_live/", "screenplays"),
    ("storyarn_web/controllers/screenplay_export_controller.ex", "screenplays"),
    ("storyarn_web/components/sidebar/screenplay_tree.ex", "screenplays"),

    # identity
    ("storyarn_web/live/user_live/", "identity"),
    ("storyarn_web/controllers/user_session_controller.ex", "identity"),
    ("storyarn_web/controllers/oauth_controller.ex", "identity"),
    ("storyarn_web/user_auth.ex", "identity"),
    ("storyarn/accounts/registration.ex", "identity"),

    # settings (personal settings — profile/security/connections)
    ("storyarn_web/live/settings_live/profile.ex", "settings"),
    ("storyarn_web/live/settings_live/security.ex", "settings"),
    ("storyarn_web/live/settings_live/connections.ex", "settings"),

    # assets
    ("storyarn_web/live/asset_live/", "assets"),
    ("storyarn_web/live/components/asset_upload.ex", "assets"),

    # default — explicitly listed so we can skip them
    ("storyarn_web/components/layouts.ex", "default"),
    ("storyarn_web/components/core_components.ex", "default"),
    ("storyarn_web/components/project_sidebar.ex", "default"),
    ("storyarn_web/components/sidebar.ex", "default"),
    ("storyarn_web/components/collaboration_components.ex", "default"),
    ("storyarn_web/components/member_components.ex", "default"),
    ("storyarn_web/components/save_indicator.ex", "default"),
    ("storyarn_web/components/ui_components.ex", "default"),
    ("storyarn_web/helpers/authorize.ex", "default"),
]

# Files that must never be touched regardless of domain match
SKIP_FILES = {
    "storyarn_web/helpers/authorize.ex",
}


def get_domain(rel_path: str) -> str | None:
    """Return the domain for a relative path (relative to lib/), or None to skip."""
    for prefix, domain in DOMAIN_RULES:
        if rel_path.startswith(prefix):
            return domain
    return None


# ---------------------------------------------------------------------------
# Regex patterns
# ---------------------------------------------------------------------------

# Form A: gettext("...") — must NOT be preceded by 'd' (avoid re-matching dgettext)
# Captures the opening quote so we can handle both ' and "
RE_GETTEXT = re.compile(r'(?<![d\w])gettext\(')

# Form B: ngettext(...)  — not preceded by 'd' or 'dg'
RE_NGETTEXT = re.compile(r'(?<![d\w])ngettext\(')

# Form C: Gettext.gettext(StoryarnWeb.Gettext, ...)  — allows whitespace/newline before StoryarnWeb
RE_MOD_GETTEXT = re.compile(r'\bGettext\.gettext\(\s*StoryarnWeb\.Gettext,\s*', re.DOTALL)

# Form D: Gettext.ngettext(StoryarnWeb.Gettext, ...)  — allows whitespace/newline before StoryarnWeb
RE_MOD_NGETTEXT = re.compile(r'\bGettext\.ngettext\(\s*StoryarnWeb\.Gettext,\s*', re.DOTALL)


def transform_content(content: str, domain: str) -> str:
    """Apply all four transformations for the given domain."""
    # Form C (module form — more specific, do before form A)
    content = RE_MOD_GETTEXT.sub(
        f'Gettext.dgettext(StoryarnWeb.Gettext, "{domain}", ',
        content,
    )
    # Form D (module form)
    content = RE_MOD_NGETTEXT.sub(
        f'Gettext.dngettext(StoryarnWeb.Gettext, "{domain}", ',
        content,
    )
    # Form A (macro form)
    content = RE_GETTEXT.sub(f'dgettext("{domain}", ', content)
    # Form B (macro form)
    content = RE_NGETTEXT.sub(f'dngettext("{domain}", ', content)

    return content


def process_file(file_path: str, lib_root: str, dry_run: bool = False) -> bool:
    """Process a single .ex/.exs file. Returns True if changed."""
    # Compute path relative to lib/
    rel = os.path.relpath(file_path, lib_root)

    # Normalise to forward slashes for matching
    rel_norm = rel.replace("\\", "/")

    # Check skip list first
    for skip in SKIP_FILES:
        if rel_norm.endswith(skip) or rel_norm == skip:
            return False

    domain = get_domain(rel_norm)
    if domain is None or domain == "default":
        return False

    with open(file_path, "r", encoding="utf-8") as f:
        original = f.read()

    transformed = transform_content(original, domain)

    if transformed == original:
        return False

    if not dry_run:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(transformed)

    return True


def main():
    dry_run = "--dry-run" in sys.argv
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lib_root = os.path.join(project_root, "lib")

    if not os.path.isdir(lib_root):
        print(f"ERROR: lib/ not found at {lib_root}", file=sys.stderr)
        sys.exit(1)

    changed_files = []
    total_files = 0

    for dirpath, dirnames, filenames in os.walk(lib_root):
        # Skip _build and deps directories
        dirnames[:] = [d for d in dirnames if d not in ("_build", "deps", ".git")]
        for filename in filenames:
            if not (filename.endswith(".ex") or filename.endswith(".exs")):
                continue
            total_files += 1
            fpath = os.path.join(dirpath, filename)
            changed = process_file(fpath, lib_root, dry_run=dry_run)
            if changed:
                rel = os.path.relpath(fpath, lib_root)
                changed_files.append(rel)

    mode = "[DRY RUN] " if dry_run else ""
    print(f"\n{mode}Scanned {total_files} files")
    print(f"{mode}Modified {len(changed_files)} files:")
    for f in sorted(changed_files):
        print(f"  ✓ {f}")

    if not changed_files:
        print("  (none)")


if __name__ == "__main__":
    main()
