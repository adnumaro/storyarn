# Storyarn development commands
# Usage: just <command>

# Default: list available commands
default:
    @just --list

# ─── JS ─────────────────────────────────────────────────────────

# Lint JS with Oxlint
js-lint:
    npm run lint

# Format JS with Oxfmt
js-format:
    npm run fmt

# Check JS (lint + format) with Oxlint/Oxfmt
js-check:
    npm run fmt:check && npm run lint

# Check and auto-fix JS with Oxlint/Oxfmt
js-fix:
    npm run fmt && npm run lint:fix

# Build Lezer grammar
js-grammar:
    npm run build:grammar

# Run JS tests
js-test:
    npm run test

# Run JS tests in watch mode
js-test-watch:
    npm run test:watch

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
    npm run fmt && npm run lint:fix
    mix convention.check
    mix credo --strict
    mix test
    mix test.e2e
    npm run test
