# Dialyzer warning ignores.
#
# Each entry is `{path, warning_type, line}` so the ignore is as tight as we
# can make it — a future warning on a different line of the same file still
# trips the build.
[
  # `Ecto.Multi.new() |> Ecto.Multi.insert(...) |> Ecto.Multi.run(...)` trips
  # `call_without_opaque` because dialyzer can't see through Multi's opaque
  # `t()` when fed by the literal struct returned from `new/0`. The pipeline
  # is the idiomatic Ecto pattern; documented as a known dialyxir noise.
  # See: https://github.com/elixir-ecto/ecto/issues/3825
  {"lib/foyer/recognitions.ex", :call_without_opaque}
]
