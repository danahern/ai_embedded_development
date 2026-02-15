#!/usr/bin/env python3
"""Migrate learnings/*.md to knowledge/items/*.yml.

Converts YAML-frontmatter markdown learning files into structured
knowledge item YAML files with proper scope, file patterns, and severity.
"""

import os
import re
import sys
import yaml
from pathlib import Path

WORKSPACE = Path(__file__).parent.parent
LEARNINGS_DIR = WORKSPACE / "learnings"
ITEMS_DIR = WORKSPACE / "knowledge" / "items"

# Tag-to-scope mapping: maps tags to applies_to fields
TAG_TO_BOARDS = {
    "nrf54l15": ["nrf54l15dk"],
    "nrf52840": ["nrf52840dk"],
    "esp32": ["esp32_devkitc"],
    "qemu": ["qemu_cortex_m3"],
}

TAG_TO_CHIPS = {
    "nrf54l15": ["nrf54l15"],
    "nrf52840": ["nrf52840"],
    "esp32": ["esp32"],
    "esp32s3": ["esp32s3"],
}

TAG_TO_TOOLS = {
    "probe-rs": ["probe-rs"],
    "twister": ["twister"],
    "size-report": ["size-report"],
    "west": ["west"],
    "nrfjprog": ["nrfjprog"],
    "esptool": ["esptool"],
}

TAG_TO_SUBSYSTEMS = {
    "coredump": ["coredump"],
    "rtt": ["rtt"],
    "shell": ["shell"],
    "bluetooth": ["bluetooth"],
    "ble": ["bluetooth"],
    "logging": ["logging"],
    "kconfig": ["kconfig"],
    "build-system": ["build-system"],
    "cmake": ["build-system"],
    "dts": ["dts"],
    "overlay": ["dts"],
    "testing": ["testing"],
    "git": ["git"],
    "elf-analysis": ["elf-analysis"],
}

# File pattern mapping based on tags/content
TAG_TO_PATTERNS = {
    "coredump": ["**/*crash*", "**/*coredump*", "**/*dump*"],
    "rtt": ["**/*rtt*", "**/*RTT*"],
    "shell": ["**/*shell*"],
    "build-system": ["**/CMakeLists.txt", "**/*.cmake", "**/module.yml", "**/Kconfig*"],
    "cmake": ["**/CMakeLists.txt", "**/*.cmake"],
    "kconfig": ["**/Kconfig*", "**/*.conf"],
    "dts": ["**/*.overlay", "**/*.dts", "**/*.dtsi"],
    "overlay": ["**/*.overlay", "**/*.conf"],
    "nrf54l15": ["**/boards/*nrf54l15*", "**/*nrf54l15*"],
    "nrf52840": ["**/boards/*nrf52840*", "**/*nrf52840*"],
    "testing": ["**/testcase.yaml", "**/tests/**"],
    "git": ["**/.gitignore"],
}

# Severity mapping based on content/title keywords
CRITICAL_KEYWORDS = [
    "fail", "quirk", "conflict", "drop", "linux-only", "break",
    "can't run", "doesn't work",
]

IMPORTANT_KEYWORDS = [
    "return value", "relative to", "qualifier", "env var",
    "auto-discover", "strategy", "exception frame",
]


def parse_learning(path: Path) -> dict:
    """Parse a learning markdown file with YAML frontmatter."""
    content = path.read_text()

    # Split frontmatter and body
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            frontmatter = yaml.safe_load(parts[1])
            body = parts[2].strip()
        else:
            frontmatter = {}
            body = content
    else:
        frontmatter = {}
        body = content

    return {
        "frontmatter": frontmatter or {},
        "body": body,
        "filename": path.stem,
    }


def infer_category(tags: list, body: str) -> str:
    """Infer category from tags and body content."""
    hardware_tags = {"nrf54l15", "nrf52840", "esp32", "rram", "flashing"}
    toolchain_tags = {"build-system", "cmake", "kconfig", "twister", "elf-analysis"}
    pattern_tags = {"architecture", "testing"}

    tag_set = set(tags)

    if tag_set & hardware_tags:
        return "hardware"
    if tag_set & toolchain_tags:
        return "toolchain"
    if tag_set & pattern_tags:
        return "pattern"
    return "operational"


def infer_severity(title: str, body: str) -> str:
    """Infer severity from title and body content."""
    text = (title + " " + body).lower()

    for kw in CRITICAL_KEYWORDS:
        if kw in text:
            return "critical"

    for kw in IMPORTANT_KEYWORDS:
        if kw in text:
            return "important"

    return "informational"


def tags_to_scope(tags: list) -> dict:
    """Convert flat tags to structured applies_to scope."""
    boards = []
    chips = []
    tools = []
    subsystems = []

    for tag in tags:
        if tag in TAG_TO_BOARDS:
            boards.extend(TAG_TO_BOARDS[tag])
        if tag in TAG_TO_CHIPS:
            chips.extend(TAG_TO_CHIPS[tag])
        if tag in TAG_TO_TOOLS:
            tools.extend(TAG_TO_TOOLS[tag])
        if tag in TAG_TO_SUBSYSTEMS:
            subsystems.extend(TAG_TO_SUBSYSTEMS[tag])

    return {
        "boards": sorted(set(boards)),
        "chips": sorted(set(chips)),
        "tools": sorted(set(tools)),
        "subsystems": sorted(set(subsystems)),
    }


def tags_to_file_patterns(tags: list) -> list:
    """Infer file patterns from tags."""
    patterns = []
    for tag in tags:
        if tag in TAG_TO_PATTERNS:
            patterns.extend(TAG_TO_PATTERNS[tag])
    return sorted(set(patterns))


def generate_id(date_str: str, sequence: int) -> str:
    """Generate a knowledge item ID."""
    compact = date_str.replace("-", "")
    return f"k-{compact[:4]}-{compact[4:]}-{sequence:03d}"


def convert_learning(parsed: dict, sequence: int) -> dict:
    """Convert a parsed learning to a knowledge item."""
    fm = parsed["frontmatter"]
    title = fm.get("title", parsed["filename"])
    date = str(fm.get("date", "2026-02-14"))
    author = fm.get("author", "danahern")
    tags = fm.get("tags", [])
    body = parsed["body"]

    item_id = generate_id(date, sequence)
    scope = tags_to_scope(tags)
    file_patterns = tags_to_file_patterns(tags)
    category = infer_category(tags, body)
    severity = infer_severity(title, body)

    return {
        "id": item_id,
        "title": title,
        "body": body,
        "category": category,
        "severity": severity,
        "applies_to": scope,
        "file_patterns": file_patterns,
        "status": "validated",
        "validated_by": [author],
        "deprecated": False,
        "superseded_by": None,
        "created": date,
        "updated": date,
        "author": author,
        "source_session": date,
        "tags": tags,
    }


def write_item(item: dict, output_dir: Path):
    """Write a knowledge item to YAML."""
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"{item['id']}.yml"

    # Custom YAML output for readability
    with open(path, "w") as f:
        f.write(f"id: {item['id']}\n")
        title_yaml = yaml.dump(item['title'], default_flow_style=True).strip().rstrip('.')
        f.write(f"title: {title_yaml}\n")
        f.write(f"body: |\n")
        for line in item["body"].split("\n"):
            f.write(f"  {line}\n" if line.strip() else "  \n")
        f.write(f"category: {item['category']}\n")
        f.write(f"severity: {item['severity']}\n")
        f.write(f"\napplies_to:\n")
        for key in ["boards", "chips", "tools", "subsystems"]:
            val = item["applies_to"][key]
            if val:
                f.write(f"  {key}: {yaml.dump(val, default_flow_style=True).strip()}\n")
            else:
                f.write(f"  {key}: []\n")
        if item["file_patterns"]:
            f.write(f"\nfile_patterns: {yaml.dump(item['file_patterns'], default_flow_style=True).strip()}\n")
        else:
            f.write(f"\nfile_patterns: []\n")
        f.write(f"\nstatus: {item['status']}\n")
        f.write(f"validated_by: {yaml.dump(item['validated_by'], default_flow_style=True).strip()}\n")
        f.write(f"deprecated: {str(item['deprecated']).lower()}\n")
        if item["superseded_by"]:
            f.write(f"superseded_by: {item['superseded_by']}\n")
        f.write(f"\ncreated: '{item['created']}'\n")
        f.write(f"updated: '{item['updated']}'\n")
        f.write(f"author: {item['author']}\n")
        if item["source_session"]:
            f.write(f"source_session: '{item['source_session']}'\n")
        if item["tags"]:
            f.write(f"\ntags: {yaml.dump(item['tags'], default_flow_style=True).strip()}\n")

    return path


def main():
    # Find all learning files
    learning_files = sorted(LEARNINGS_DIR.rglob("*.md"))
    print(f"Found {len(learning_files)} learning files")

    if not learning_files:
        print("No learning files found!")
        sys.exit(1)

    # Group by date for sequence numbering
    date_sequences = {}
    items = []

    for path in learning_files:
        parsed = parse_learning(path)
        date = str(parsed["frontmatter"].get("date", "2026-02-14"))

        if date not in date_sequences:
            date_sequences[date] = 0
        date_sequences[date] += 1
        seq = date_sequences[date]

        item = convert_learning(parsed, seq)
        items.append((item, path))

    # Write all items
    print(f"\nMigrating {len(items)} items to {ITEMS_DIR}/")
    for item, source_path in items:
        output_path = write_item(item, ITEMS_DIR)
        print(f"  {source_path.name} -> {output_path.name}")
        print(f"    id={item['id']} category={item['category']} severity={item['severity']}")

    print(f"\nDone! {len(items)} knowledge items created in {ITEMS_DIR}/")
    print("\nSeverity breakdown:")
    for sev in ["critical", "important", "informational"]:
        count = sum(1 for i, _ in items if i["severity"] == sev)
        print(f"  {sev}: {count}")


if __name__ == "__main__":
    main()
