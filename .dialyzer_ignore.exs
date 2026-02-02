# Dialyzer ignore patterns
# This file contains patterns for warnings that should be ignored.
# These are typically false positives or known issues in dependencies.

[
  # Gettext plural handling generates code that Dialyzer doesn't understand
  # properly with opaque types. This is a known false positive.
  # See: https://github.com/elixir-gettext/gettext/issues/308
  {"lib/storyarn_web/gettext.ex", :call_without_opaque},

  # Defensive catch-all pattern in get_email_name/1 - the function is always
  # called with binaries from lock_info.user_email, but the catch-all provides
  # safety in case the data is ever nil/malformed. This is intentional.
  {"lib/storyarn_web/live/flow_live/show.ex", :pattern_match_cov}
]
