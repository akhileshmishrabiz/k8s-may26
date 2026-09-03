#!/usr/bin/env python3

"""Fix a Dockerfile using OpenAI based on container scan results."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

from openai import OpenAI


DEFAULT_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.6-luna")
DEFAULT_REASONING_EFFORT = os.environ.get("OPENAI_REASONING_EFFORT", "medium")

PREFERRED_PYTHON_IMAGE = os.environ.get(
    "PREFERRED_PYTHON_IMAGE",
    "python:3.13-slim-bookworm",
)

SYSTEM_PROMPT = """\
You are a container security expert. Given a Dockerfile and vulnerability scan findings,
produce a corrected Dockerfile that addresses the reported issues.

Decision order (highest impact first):

1. Upgrade the base image to the latest stable Python slim on a current Debian release
   (bookworm or trixie). Do NOT preserve an old Python major version just because the
   current Dockerfile uses it.

2. Remove unnecessary packages and ports that expand the attack surface.

3. Apply package-level fixes from FixedVersion in scan findings when still needed.

4. Harden the Dockerfile (non-root user, minimal layers, no ADD unless required).

What "keep the image functional" means:

- The container must still build and run the same CMD/ENTRYPOINT behavior.
- It does NOT mean keeping python:3.12, old Debian releases (buster/bullseye), or
  every installed package unchanged.
- For a minimal demo app (e.g. python -m http.server), upgrading Python major version
  is expected and preferred.

Base image rules:

- NEVER use @sha256: digests. You cannot look up real digests — invented ones break builds.
- Pin with an explicit version tag only (e.g. python:3.13.13-slim-bookworm).
- Do not use buster, stretch, or other EOL Debian variants.

Dockerfile rules:

- Output ONLY the complete fixed Dockerfile. No markdown fences, no commentary.
- Run as a non-root user.
- Add a HEALTHCHECK only if the image includes a health-check tool (e.g. curl).
- Minimize installed packages; clean apt caches in the same RUN layer.
- Prefer COPY over ADD unless ADD is truly needed.
- Do not expose unnecessary ports.
- Follow Docker and CIS best practices.
"""

FROM_DIGEST_RE = re.compile(
    r"@sha256:[0-9a-f]{64}",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fix a Dockerfile using OpenAI and container scan results."
    )

    parser.add_argument(
        "--dockerfile",
        default=os.environ.get("DOCKERFILE_PATH", "Dockerfile"),
        help="Path to the Dockerfile to fix (default: Dockerfile or DOCKERFILE_PATH env)",
    )

    parser.add_argument(
        "--scan-results",
        default=os.environ.get("SCAN_RESULTS_FILE", "scan-results.json"),
        help="Path to scan results file (default: scan-results.json or SCAN_RESULTS_FILE env)",
    )

    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"OpenAI model to use (default: {DEFAULT_MODEL})",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the fixed Dockerfile to stdout instead of writing it",
    )

    return parser.parse_args()


def read_file(path: Path) -> str:
    if not path.is_file():
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    return path.read_text(encoding="utf-8")


def strip_markdown_fences(content: str) -> str:
    text = content.strip()

    if text.startswith("```"):
        lines = text.splitlines()

        if lines[0].startswith("```"):
            lines = lines[1:]

        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]

        text = "\n".join(lines)

    return text.rstrip() + "\n"


def strip_invented_digests(content: str) -> str:
    """Remove @sha256 pins — models cannot resolve real digests and often hallucinate them."""
    cleaned_lines = []

    for line in content.splitlines():
        if line.strip().upper().startswith("FROM "):
            line = FROM_DIGEST_RE.sub("", line)

        cleaned_lines.append(line)

    return "\n".join(cleaned_lines).rstrip() + "\n"


def fix_dockerfile(
    client: OpenAI,
    dockerfile: str,
    scan_results: str,
    model: str,
    reasoning_effort: str,
    preferred_base: str,
) -> str:

    user_prompt = f"""Fix the Dockerfile below based on these scan findings.

Target base image (use this or a newer patch-level variant): {preferred_base}

## Scan findings

{scan_results}

## Current Dockerfile

{dockerfile}
"""

    response = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "system",
                "content": SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": user_prompt,
            },
        ],
        reasoning_effort=reasoning_effort,
    )

    fixed = response.choices[0].message.content or ""

    if not fixed.strip():
        print(
            "Error: OpenAI returned an empty response.",
            file=sys.stderr,
        )
        sys.exit(1)

    return strip_invented_digests(
        strip_markdown_fences(fixed)
    )


def main() -> None:
    args = parse_args()

    api_key = os.environ.get("OPENAI_API_KEY")

    if not api_key:
        print(
            "Error: OPENAI_API_KEY environment variable is not set.",
            file=sys.stderr,
        )
        sys.exit(1)

    dockerfile_path = Path(args.dockerfile).resolve()
    scan_results_path = Path(args.scan_results).resolve()

    dockerfile = read_file(dockerfile_path)
    scan_results = read_file(scan_results_path)

    client = OpenAI(api_key=api_key)

    fixed_dockerfile = fix_dockerfile(
        client,
        dockerfile,
        scan_results,
        args.model,
        DEFAULT_REASONING_EFFORT,
        PREFERRED_PYTHON_IMAGE,
    )

    if args.dry_run:
        print(fixed_dockerfile, end="")
        return

    if fixed_dockerfile == dockerfile:
        print("Dockerfile unchanged after fix attempt.")
        return

    dockerfile_path.write_text(
        fixed_dockerfile,
        encoding="utf-8",
    )

    print(f"Updated {dockerfile_path}")


if __name__ == "__main__":
    main()