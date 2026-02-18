#!/usr/bin/env python3
"""
verify_translations.py

Validates that no translations from the default.po.bak were lost
when splitting into per-domain PO files.

Usage:
    python scripts/verify_translations.py

Checks:
1. Every msgid in default.po.bak exists in at least one new PO file
2. Every msgid in default.po.bak has a non-empty msgstr in at least one new PO file
3. Reports any missing or untranslated entries
"""

import os
import re
import sys


def parse_po_entries(path: str) -> dict[str, str]:
    """
    Parse a PO file and return {msgid → msgstr}.
    For plural: {(msgid, msgid_plural) → msgstr[0]}.
    """
    translations = {}

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

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
                msgid, i = _read_str(lines, i)
                continue

            if line.startswith('msgid_plural '):
                msgid_plural, i = _read_str(lines, i)
                continue

            if line.startswith('msgstr "'):
                msgstr, i = _read_str(lines, i)
                continue

            m = re.match(r'msgstr\[(\d+)\]\s+"(.*)"', line)
            if m:
                idx = int(m.group(1))
                val = m.group(2)
                j = i + 1
                while j < len(lines) and lines[j].startswith('"'):
                    val += lines[j][1:-1]
                    j += 1
                msgstr_plural[idx] = _unescape(val)
                i = j
                continue

            i += 1

        if msgid is None or msgid == "":
            continue

        if msgid_plural is not None:
            key = (msgid, msgid_plural)
            translations[key] = msgstr_plural.get(0, "")
        elif msgstr is not None:
            translations[msgid] = msgstr

    return translations


def _read_str(lines: list[str], i: int) -> tuple[str, int]:
    line = lines[i]
    first_quote = line.index('"')
    val = line[first_quote + 1 : -1]
    j = i + 1
    while j < len(lines) and lines[j].startswith('"'):
        val += lines[j][1:-1]
        j += 1
    return _unescape(val), j


def _unescape(s: str) -> str:
    return s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')


def _key_str(key) -> str:
    if isinstance(key, tuple):
        return f"{key[0]!r} / {key[1]!r}"
    return repr(key)


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    es_dir = os.path.join(project_root, "priv", "gettext", "es", "LC_MESSAGES")
    backup_path = os.path.join(es_dir, "default.po.bak")

    if not os.path.isfile(backup_path):
        print(f"ERROR: Backup not found: {backup_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading backup: {backup_path}")
    backup = parse_po_entries(backup_path)
    print(f"  {len(backup)} entries in backup\n")

    # Load all current PO files (including default.po)
    po_files = sorted(
        f for f in os.listdir(es_dir)
        if f.endswith(".po") and not f.endswith(".bak")
    )

    all_translated: dict = {}  # msgid → msgstr (from any domain)
    all_present: set = set()   # msgids that appear in any domain

    per_file_stats = {}

    for po_file in po_files:
        path = os.path.join(es_dir, po_file)
        entries = parse_po_entries(path)
        per_file_stats[po_file] = {
            "total": len(entries),
            "translated": sum(1 for v in entries.values() if v),
        }
        for key, val in entries.items():
            all_present.add(key)
            if val and key not in all_translated:
                all_translated[key] = val

    print("Per-file stats:")
    for f, stats in sorted(per_file_stats.items()):
        pct = (stats["translated"] / stats["total"] * 100) if stats["total"] else 0
        print(f"  {f}: {stats['translated']}/{stats['total']} translated ({pct:.0f}%)")

    print()

    # Check 1: every backup msgid should appear in at least one PO file
    missing_from_any = [k for k in backup if k not in all_present]
    # Check 2: every backup msgid with a translation should be translated in at least one file
    backup_translated = {k: v for k, v in backup.items() if v}
    lost_translations = [k for k in backup_translated if not all_translated.get(k)]

    if missing_from_any:
        print(f"⚠️  {len(missing_from_any)} msgids from backup not found in any PO file:")
        for k in missing_from_any[:20]:
            print(f"  - {_key_str(k)}")
        if len(missing_from_any) > 20:
            print(f"  ... and {len(missing_from_any) - 20} more")
    else:
        print("✅ All backup msgids are present in at least one domain file")

    if lost_translations:
        print(f"\n⚠️  {len(lost_translations)} translations not filled in any domain:")
        for k in lost_translations[:20]:
            print(f"  - {_key_str(k)}: {backup[k]!r}")
        if len(lost_translations) > 20:
            print(f"  ... and {len(lost_translations) - 20} more")
    else:
        print("✅ All backup translations are present in at least one domain file")

    total_backup_translated = len(backup_translated)
    total_now_translated = len(all_translated)
    print(f"\nBackup had {total_backup_translated} translated entries")
    print(f"Total translated across all new files: {total_now_translated}")

    if missing_from_any or lost_translations:
        print("\n❌ Verification FAILED — some translations were lost")
        sys.exit(1)
    else:
        print("\n✅ Verification PASSED — no translations lost")


if __name__ == "__main__":
    main()
