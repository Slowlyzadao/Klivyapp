# Annotate-rb 4.x post-migrate hook is intentionally NOT loaded.
#
# The hook (`annotate_models_migrate.rake`, the only file inside annotaterb's
# `tasks/` folder) unconditionally invokes `AnnotateRb::Runner.run(["models"])`
# after every `db:migrate`, ignoring the `skip_on_db_migrate: true` flag in
# `.annotaterb.yml`. The runner then calls `column_defaults` on every model,
# which crashes for any model that combines `serialize :col, coder: YAML` with
# a `jsonb` column whose default is `{}` — the YAML coder receives a Hash and
# Psych raises `TypeError: no implicit conversion of Hash into String`.
# Existing example: `installation_configs.serialized_value` (jsonb default {})
# + `InstallationConfig.serialize :serialized_value, coder: YAML, ...`.
#
# To run annotations manually, use the CLI shipped with the gem:
#
#     bundle exec annotaterb models
#
# Configuration is read from `.annotaterb.yml` at the project root.
