# shellcheck shell=bash
# Tooling's own test helpers: run a workflow step's inline run: block as a script, so tests exercise the shipped code.
# Sourced after lib.sh. Needs yq (preinstalled on ubuntu runners) or python3 with PyYAML.

require_yaml_tool() {
  if ! command -v yq > /dev/null && ! python3 -c 'import yaml' 2> /dev/null; then
    echo "skip $(basename "$0"): needs yq or python3 with PyYAML"
    exit 0
  fi
}

# step_field <workflow file> <job> <step name> <field: run | env.NAME>
step_field() {
  local value
  if command -v yq > /dev/null; then
    value=$(yq -r ".jobs.\"$2\".steps[] | select(.name == \"$3\") | .$4" "$1")
  else
    value=$(python3 - "$@" << 'PY'
import sys, yaml
wf, job, step, field = sys.argv[1:]
for s in yaml.safe_load(open(wf))["jobs"][job]["steps"]:
    if s.get("name") == step:
        for key in field.split("."):
            s = s[key]
        print(s)
PY
)
  fi
  if [ -z "$value" ] || [ "$value" = null ]; then
    echo "FAIL $(basename "$0"): no '$4' in step '$3' of job '$2' in $1" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

# step_script <workflow file> <job> <step name>: prints the path of a script holding that step's run: block,
# with the flags GitHub uses for `shell: bash`.
step_script() {
  local script
  script=$(mktemp "$TEST_TMP/step.XXXXXX")
  { echo "set -eo pipefail"; step_field "$1" "$2" "$3" run; } > "$script" || exit 1
  echo "$script"
}
