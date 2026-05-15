# Storyarn development commands
# Usage: just <command>

# Default: list available commands
default:
    @just --list

# ─── JS ─────────────────────────────────────────────────────────

# Lint JS with Oxlint
js-lint:
    pnpm run lint

# Format JS with Oxfmt
js-format:
    pnpm run fmt

# Check JS (lint + format) with Oxlint/Oxfmt
js-check:
    pnpm run fmt:check && pnpm run lint

# Check and auto-fix JS with Oxlint/Oxfmt
js-fix:
    pnpm run fmt && pnpm run lint:fix

# Build Lezer grammar
js-grammar:
    pnpm run build:grammar

# Run JS tests
js-test:
    pnpm run test

# Run JS tests in watch mode
js-test-watch:
    pnpm run test:watch

# ─── Elixir ─────────────────────────────────────────────────────

# Run Elixir tests
test:
    mix test

# Run E2E tests (Playwright)
e2e:
    mix test.e2e

# Run Credo strict
credo:
    mix credo --strict

# Start dev server
server:
    mix phx.server

# ─── Quality ────────────────────────────────────────────────────

# Run all quality checks: Oxlint fix, Credo strict, Elixir tests, JS tests, E2E tests
quality:
    pnpm run fmt && pnpm run lint:fix
    pnpm arch & pnpm knip
    mix format
    mix convention.check
    mix credo --strict
    mix test
    pnpm run test
