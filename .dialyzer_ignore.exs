# Dialyzer ignore patterns
# This file contains patterns for warnings that should be ignored.
# These are typically false positives or known issues in dependencies.

[
  # Gettext plural handling generates code that Dialyzer doesn't understand
  # properly with opaque types. This is a known false positive.
  # See: https://github.com/elixir-gettext/gettext/issues/308
  {"lib/storyarn_web/gettext.ex", :call_without_opaque}
]
