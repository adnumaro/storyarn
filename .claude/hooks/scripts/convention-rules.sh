#!/usr/bin/env bash
# Shared convention rules engine.
# Used by: convention-check.sh (hook), mix convention.check (mix task)
#
# Suppression comments:
#   Line:  # storyarn:disable           (disables all rules for this line)
#   Line:  # storyarn:disable:rule_name (disables specific rule)
#   Block: # storyarn:disable-start     (disables all rules until end)
#          # storyarn:disable-end

VIOLATIONS=()

# Check if a line is suppressed by inline or block disable comments.
# Args: $1=line_text, $2=rule_name, $3=all_lines (newline-separated), $4=line_number
is_suppressed() {
  local line="$1"
  local rule="$2"
  local all_lines="$3"
  local line_num="$4"

  # Check inline disable on same line
  if echo "$line" | grep -qE "storyarn:disable($|[^-])" ; then
    return 0
  fi
  if echo "$line" | grep -q "storyarn:disable:${rule}"; then
    return 0
  fi

  # Check previous line for disable comment
  if [[ "$line_num" -gt 1 ]]; then
    local prev_line
    prev_line=$(echo "$all_lines" | sed -n "$((line_num - 1))p")
    if echo "$prev_line" | grep -qE "storyarn:disable($|[^-])" ; then
      return 0
    fi
    if echo "$prev_line" | grep -q "storyarn:disable:${rule}"; then
      return 0
    fi
  fi

  # Check block disable
  local i=1
  local in_block=false
  while IFS= read -r check_line; do
    if echo "$check_line" | grep -q "storyarn:disable-start"; then
      in_block=true
    fi
    if echo "$check_line" | grep -q "storyarn:disable-end"; then
      in_block=false
    fi
    if [[ "$i" -eq "$line_num" ]] && [[ "$in_block" == true ]]; then
      return 0
    fi
    i=$((i + 1))
  done <<< "$all_lines"

  return 1
}

add_violation() {
  local rule="$1"
  local file="$2"
  local line_num="$3"
  local message="$4"
  VIOLATIONS+=("[$rule] $file:$line_num — $message")
}

# Run all convention checks.
# Args: $1=code_text, $2=file_path, $3=mode (hook|project)
check_conventions() {
  local code="$1"
  local file="$2"
  local mode="$3"
  VIOLATIONS=()

  local is_web=false
  [[ "$file" == *storyarn_web* ]] && is_web=true

  local is_js=false
  [[ "$file" == *.js ]] && is_js=true

  # === RULE: raw_without_sanitizer ===
  # raw() must be wrapped with HtmlSanitizer.sanitize_html/1
  if [[ "$is_web" == true ]]; then
    local line_num=0
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      if echo "$line" | grep -qE '\braw\(' && \
         ! echo "$line" | grep -qi 'sanitize_html' && \
         ! echo "$line" | grep -qi 'sanitize_and_interpolate' && \
         ! echo "$line" | grep -q '^\s*#'; then
        if ! is_suppressed "$line" "raw_without_sanitizer" "$code" "$line_num"; then
          add_violation "raw_without_sanitizer" "$file" "$line_num" \
            "raw() without HtmlSanitizer.sanitize_html/1 — XSS risk"
        fi
      fi
    done <<< "$code"
  fi

  # === RULE: datetime_utc_now ===
  # Use TimeHelpers.now/0 instead of DateTime.utc_now() |> DateTime.truncate(:second)
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -qE 'DateTime\.utc_now' && \
       ! echo "$line" | grep -q 'time_helpers\|TimeHelpers' && \
       ! echo "$file" | grep -q 'time_helpers\.ex' && \
       ! echo "$line" | grep -qE 'DateTime\.(diff|compare|after|before)\b' && \
       ! echo "$line" | grep -qE '\^DateTime\.utc_now' && \
       ! echo "$line" | grep -q '^\s*#'; then
      if ! is_suppressed "$line" "datetime_utc_now" "$code" "$line_num"; then
        add_violation "datetime_utc_now" "$file" "$line_num" \
          "Use TimeHelpers.now/0 instead of DateTime.utc_now()"
      fi
    fi
  done <<< "$code"

  # === RULE: facade_bypass ===
  # Web layer must not call context submodules directly
  if [[ "$is_web" == true ]]; then
    local submodules="SheetCrud\|SheetQueries\|BlockCrud\|TableCrud\|FlowCrud\|NodeCreate\|NodeUpdate\|NodeDelete\|ConnectionCrud\|SceneCrud\|LayerCrud\|ZoneCrud\|PinCrud\|AnnotationCrud\|ScreenplayCrud\|ElementCrud\|ScreenplayQueries\|LanguageCrud\|TextCrud\|GlossaryCrud\|BatchTranslator\|ProjectCrud\|WorkspaceCrud"
    local line_num=0
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      if echo "$line" | grep -qE "\b($submodules)\." && \
         ! echo "$line" | grep -q '^\s*#'; then
        if ! is_suppressed "$line" "facade_bypass" "$code" "$line_num"; then
          add_violation "facade_bypass" "$file" "$line_num" \
            "Call through context facade, not submodule directly"
        fi
      fi
    done <<< "$code"
  fi

  # === RULE: string_to_atom ===
  # String.to_atom with potentially user-controlled input
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -qE 'String\.to_atom\b' && \
       ! echo "$line" | grep -q '^\s*#'; then
      if ! is_suppressed "$line" "string_to_atom" "$code" "$line_num"; then
        add_violation "string_to_atom" "$file" "$line_num" \
          "String.to_atom/1 — prefer String.to_existing_atom/1 with allowlist guard"
      fi
    fi
  done <<< "$code"

  # === RULE: sql_interpolation ===
  # No string interpolation in Ecto queries
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if { echo "$line" | grep -qE 'from\s+\w+\s+in\b.*#\{' || \
         echo "$line" | grep -qE 'Repo\.(query|query!)\s*[\(]?.*#\{'; } && \
       ! echo "$line" | grep -q '^\s*#'; then
      if ! is_suppressed "$line" "sql_interpolation" "$code" "$line_num"; then
        add_violation "sql_interpolation" "$file" "$line_num" \
          "String interpolation in Ecto query — SQL injection risk. Use ^variable pinning."
      fi
    fi
  done <<< "$code"

  # === RULE: put_flash_without_gettext ===
  # All put_flash messages must use gettext/dgettext
  if [[ "$is_web" == true ]]; then
    local line_num=0
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      if echo "$line" | grep -qE 'put_flash\(.*,\s*"[A-Za-z]' && \
         ! echo "$line" | grep -qE 'gettext|dgettext|ngettext' && \
         ! echo "$line" | grep -q '^\s*#'; then
        if ! is_suppressed "$line" "put_flash_without_gettext" "$code" "$line_num"; then
          add_violation "put_flash_without_gettext" "$file" "$line_num" \
            "put_flash with hardcoded string — use gettext/dgettext"
        fi
      fi
    done <<< "$code"
  fi

  # === RULE: native_dialog ===
  # No browser-native confirm/alert/prompt
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -qE 'window\.(confirm|alert|prompt)\b|data-confirm' && \
       ! echo "$line" | grep -q '^\s*#\|^\s*//\|^\s*\*'; then
      if ! is_suppressed "$line" "native_dialog" "$code" "$line_num"; then
        add_violation "native_dialog" "$file" "$line_num" \
          "No browser-native dialogs — use <.confirm_modal>"
      fi
    fi
  done <<< "$code"

  # === RULE: inline_slugify ===
  # Don't define private slugify/normalize functions — use NameNormalizer
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -qE 'defp\s+(slugify|variablify|normalize_name)\b' && \
       ! echo "$file" | grep -q 'name_normalizer'; then
      if ! is_suppressed "$line" "inline_slugify" "$code" "$line_num"; then
        add_violation "inline_slugify" "$file" "$line_num" \
          "Use NameNormalizer.slugify/1 or variablify/1 instead of private function"
      fi
    fi
  done <<< "$code"

  # Output results
  if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "CONVENTION VIOLATIONS found:"
    for v in "${VIOLATIONS[@]}"; do
      echo "  $v"
    done

    if [[ "$mode" == "hook" ]]; then
      echo ""
      echo "Suppress with: # storyarn:disable:rule_name"
    fi
    return 1
  fi

  return 0
}
