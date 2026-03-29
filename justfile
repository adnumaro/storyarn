# Storyarn development commands
# Usage: just <command>

# Default: list available commands
default:
    @just --list

# ─── JS (assets/) ───────────────────────────────────────────────

# Lint JS with Biome
js-lint:
    cd assets && npx biome lint vue/

# Format JS with Biome
js-format:
    cd assets && npx biome format --write vue/

# Check JS (lint + format) with Biome
js-check:
    cd assets && npx biome check vue/

# Check and auto-fix JS with Biome
js-fix:
    cd assets && npx biome check --write vue/

# Build Lezer grammar
js-grammar:
    cd assets && npx lezer-generator js/expression_editor/storyarn_expr.grammar -o js/expression_editor/parser_generated.js

# Run JS tests
js-test:
    cd assets && ./node_modules/.bin/vitest run

# Run JS tests in watch mode
js-test-watch:
    cd assets && ./node_modules/.bin/vitest

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

# Run all quality checks: Biome fix, Credo strict, Elixir tests, JS tests, E2E tests
quality:
    cd assets && npx biome check --write js/
    mix convention.check
    mix credo --strict
    mix test
    mix test.e2e
    cd assets && ./node_modules/.bin/vitest run
