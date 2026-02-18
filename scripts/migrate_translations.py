#!/usr/bin/env python3
"""
migrate_translations.py

Reads the backup default.po.bak and populates msgstr entries in the
newly-created per-domain .po files for the `es` locale.

Usage:
    python scripts/migrate_translations.py [--dry-run]

The script:
1. Parses priv/gettext/es/LC_MESSAGES/default.po.bak → {msgid → msgstr} map
2. For every .po file in priv/gettext/es/LC_MESSAGES/ (except default.po and .bak):
   - Fills empty msgstr "" entries with the translation from the backup
3. Also fills default.po for its remaining ~69 entries
4. Reports how many entries were filled per file
"""

import os
import re
import sys
from collections import defaultdict

# ---------------------------------------------------------------------------
# PO parsing helpers
# ---------------------------------------------------------------------------

def parse_po(path: str) -> dict[str, str]:
    """
    Parse a PO file and return a dict mapping msgid → msgstr.
    Handles multi-line strings (continued with ") and plural forms (msgid_plural / msgstr[0]).
    For plural entries the key is (msgid, msgid_plural) tuple → msgstr[0] value.
    For simplicity we store simple msgids as str key and
    plural msgids as tuple key.
    """
    translations: dict = {}

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Split into blocks separated by blank lines
    blocks = re.split(r'\n\n+', content.strip())

    for block in blocks:
        lines = block.strip().splitlines()

        msgid = None
        msgid_plural = None
        msgstr = None
        msgstr_plural: dict[int, str] = {}

        i = 0
        while i < len(lines):
            line = lines[i]

            if line.startswith('msgid '):
                msgid = _read_string(lines, i)
                i = _skip_string(lines, i)
                continue

            if line.startswith('msgid_plural '):
                msgid_plural = _read_string(lines, i)
                i = _skip_string(lines, i)
                continue

            if line.startswith('msgstr "'):
                msgstr = _read_string(lines, i)
                i = _skip_string(lines, i)
                continue

            m = re.match(r'msgstr\[(\d+)\]\s+"(.*)"', line)
            if m:
                idx = int(m.group(1))
                val = m.group(2)
                # collect continuation lines
                j = i + 1
                while j < len(lines) and lines[j].startswith('"'):
                    val += lines[j][1:-1]  # strip surrounding quotes
                    j += 1
                msgstr_plural[idx] = _unescape(val)
                i = j
                continue

            i += 1

        if msgid is None:
            continue

        if msgid == "":  # header block
            continue

        if msgid_plural is not None:
            key = (msgid, msgid_plural)
            translations[key] = msgstr_plural.get(0, "")
        elif msgstr is not None:
            translations[msgid] = msgstr

    return translations


def _read_string(lines: list[str], i: int) -> str:
    """Read a possibly multi-line PO string starting at line i."""
    line = lines[i]
    # Find the first " after the keyword
    first_quote = line.index('"')
    val = line[first_quote + 1 : -1]  # strip leading " and trailing "
    j = i + 1
    while j < len(lines) and lines[j].startswith('"'):
        val += lines[j][1:-1]
        j += 1
    return _unescape(val)


def _skip_string(lines: list[str], i: int) -> int:
    """Return the next line index after a multi-line string."""
    j = i + 1
    while j < len(lines) and lines[j].startswith('"'):
        j += 1
    return j


def _unescape(s: str) -> str:
    return s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')


# ---------------------------------------------------------------------------
# PO writing helpers
# ---------------------------------------------------------------------------

EMPTY_MSGSTR_RE = re.compile(r'^(msgstr "")$', re.MULTILINE)
EMPTY_MSGSTR_PLURAL_RE = re.compile(r'^(msgstr\[0\] "")$', re.MULTILINE)


def fill_po_file(path: str, translations: dict, dry_run: bool = False) -> tuple[int, int]:
    """
    Fill empty msgstr entries in a PO file using the translations dict.
    Returns (filled_count, total_entries).
    """
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    blocks = re.split(r'(\n\n+)', content)
    # blocks alternates: text, separator, text, separator, ...
    # We process each text block

    filled = 0
    total = 0
    result_parts = []

    i = 0
    while i < len(blocks):
        part = blocks[i]
        sep = blocks[i + 1] if i + 1 < len(blocks) else ""

        new_part, f_count, t_count = _fill_block(part, translations)
        filled += f_count
        total += t_count
        result_parts.append(new_part)
        result_parts.append(sep)
        i += 2

    new_content = "".join(result_parts)

    if not dry_run and new_content != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)

    return filled, total


def _fill_block(block: str, translations: dict) -> tuple[str, int, int]:
    """Process a single PO block (entry). Returns (new_block, filled, total)."""
    if not block.strip() or not ('msgid' in block):
        return block, 0, 0

    # Extract msgid
    msgid_m = re.search(r'^msgid\s+"((?:[^"\\]|\\.)*)"', block, re.MULTILINE)
    if not msgid_m:
        return block, 0, 0

    msgid = _unescape(msgid_m.group(1))

    # Collect continuation lines for msgid
    full_msgid = msgid
    for cont in re.findall(r'(?m)^"((?:[^"\\]|\\.)*)"', block):
        # continuation lines appear after msgid/msgstr declarations
        pass  # Already handled by _unescape above for simple cases

    if msgid == "":  # header
        return block, 0, 0

    # Check for plural
    msgid_plural_m = re.search(r'^msgid_plural\s+"((?:[^"\\]|\\.)*)"', block, re.MULTILINE)

    filled = 0
    total = 1
    new_block = block

    if msgid_plural_m:
        msgid_plural = _unescape(msgid_plural_m.group(1))
        key = (msgid, msgid_plural)

        # Check if msgstr[0] is empty
        if re.search(r'^msgstr\[0\] ""$', block, re.MULTILINE):
            translation = translations.get(key, "")
            if translation:
                # Replace msgstr[0] "" with filled value
                escaped = _escape(translation)
                new_block = re.sub(
                    r'^(msgstr\[0\] )""$',
                    f'\\1"{escaped}"',
                    new_block,
                    flags=re.MULTILINE,
                )
                filled = 1
    else:
        # Simple msgstr
        if re.search(r'^msgstr ""$', block, re.MULTILINE):
            translation = translations.get(msgid, "")
            if translation:
                escaped = _escape(translation)
                # Replace exactly 'msgstr ""' (whole line)
                new_block = re.sub(
                    r'^msgstr ""$',
                    f'msgstr "{escaped}"',
                    new_block,
                    flags=re.MULTILINE,
                )
                filled = 1

    return new_block, filled, total


def _escape(s: str) -> str:
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    dry_run = "--dry-run" in sys.argv
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    es_dir = os.path.join(project_root, "priv", "gettext", "es", "LC_MESSAGES")
    backup_path = os.path.join(es_dir, "default.po.bak")

    if not os.path.isfile(backup_path):
        print(f"ERROR: Backup not found: {backup_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading backup: {backup_path}")
    translations = parse_po(backup_path)
    print(f"  Loaded {len(translations)} translations from backup\n")

    po_files = sorted(
        f for f in os.listdir(es_dir)
        if f.endswith(".po") and not f.endswith(".bak")
    )

    mode = "[DRY RUN] " if dry_run else ""
    total_filled = 0
    total_entries = 0

    for po_file in po_files:
        path = os.path.join(es_dir, po_file)
        filled, total = fill_po_file(path, translations, dry_run=dry_run)
        total_filled += filled
        total_entries += total
        status = f"{filled}/{total} filled"
        print(f"  {mode}{po_file}: {status}")

    print(f"\n{mode}Total: {total_filled}/{total_entries} entries filled across all files")


if __name__ == "__main__":
    main()
