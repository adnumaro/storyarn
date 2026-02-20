# Storyarn development commands
# Usage: just <command>

# Default: list available commands
default:
    @just --list

# ─── JS (assets/) ───────────────────────────────────────────────

# Lint JS with Biome
js-lint:
    cd assets && npx biome lint js/

# Format JS with Biome
js-format:
    cd assets && npx biome format --write js/

# Check JS (lint + format) with Biome
js-check:
    cd assets && npx biome check js/

# Check and auto-fix JS with Biome
js-fix:
    cd assets && npx biome check --write js/

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

# Run Credo strict
credo:
    mix credo --strict

# Start dev server
server:
    mix phx.server

# ─── Quality ────────────────────────────────────────────────────

# Run all quality checks: Biome fix, Credo strict, Elixir tests, JS tests
quality:
    cd assets && npx biome check --write js/
    mix credo --strict
    mix test
    cd assets && ./node_modules/.bin/vitest run
