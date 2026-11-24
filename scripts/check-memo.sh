#!/usr/bin/env bash
# Check a resume memo right after writing it.
#
#   check-memo.sh <memo.yml>          load check, list-item check, secret scan
#   check-memo.sh --keys <memo.yml>   print the top-level keys, comma-separated
#
# Exit codes
#   0   loads as YAML, every list item is a string, no secret-like text found
#   1   does not load as YAML, a list item is not a string, or text after a " #" was read as a comment
#   2   secret-like text found (the output names the pattern and the line, not the value)
#   3   neither ruby nor python3 with PyYAML is available: the YAML was NOT checked
#   64  usage error
#
# Notes (printed as "Note: ...", they never change the exit code)
#   An open memo that still has items under "done:" gets a note: finished items
#   belong in the archive (done/<memo file name>), not in the memo a restore reads.
#   The check is line-based, so it also runs when no YAML runtime is available.
#
# The same script checks an archive file (no header keys, no status).
#
# Environment (mainly for the tests)
#   RESUME_MEMO_YAML    ruby | python | none    force the YAML runtime
#   RESUME_MEMO_PYTHON  python executable to use instead of python3

set -u

mode=check
if [ "${1:-}" = "--keys" ]; then
  mode=keys
  shift
fi
file="${1:-}"
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "usage: check-memo.sh [--keys] <memo.yml>" >&2
  exit 64
fi

py="${RESUME_MEMO_PYTHON:-python3}"

# Keys whose value is a list of plain items. The other list keys (decisions,
# observations, failed, refs) hold mappings by design, so they are not checked.
list_keys="done in_progress next open_questions commands user_instructions"

ruby_check() {
  # shellcheck disable=SC2086
  ruby -ryaml -e '
    d = YAML.load_file(ARGV[0])
    unless d.is_a?(Hash)
      puts "top level is not a mapping"
      exit 1
    end
    bad = []
    ARGV[1..-1].each do |k|
      v = d[k]
      next if v.nil?
      unless v.is_a?(Array)
        bad << "#{k}: expected a list, got #{v.class}"
        next
      end
      v.each_with_index do |x, i|
        bad << "#{k}[#{i}] is #{x.class}, not a string (write the item as `- |`)" unless x.is_a?(String)
      end
    end
    # A " #" in a plain value starts a comment: the load succeeds and the rest
    # of the line is dropped. Block scalars and quoted strings keep it, so a
    # "#" preceded by whitespace that is in the file but not in the parsed
    # strings was swallowed.
    seen = []
    walk = lambda do |o|
      case o
      when Hash then o.each { |k, v| walk.call(k); walk.call(v) }
      when Array then o.each { |v| walk.call(v) }
      when String then seen << o
      end
    end
    walk.call(d)
    hash_re = /(?:^|\s)#/
    raw_n = File.read(ARGV[0], encoding: "UTF-8").scan(hash_re).size
    kept_n = seen.join("\n").scan(hash_re).size
    if raw_n > kept_n
      bad << "#{raw_n - kept_n} of #{raw_n} \" #\" in the file were read as a comment: the text after them is missing from the parsed memo. Write those values as `|` block scalars"
    end
    puts bad unless bad.empty?
    exit(bad.empty? ? 0 : 1)
  ' "$file" $list_keys 2>&1
}

python_check() {
  # shellcheck disable=SC2086
  "$py" -c '
import re, sys, yaml
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(e)
    sys.exit(1)
if not isinstance(d, dict):
    print("top level is not a mapping")
    sys.exit(1)
bad = []
for k in sys.argv[2:]:
    v = d.get(k)
    if v is None:
        continue
    if not isinstance(v, list):
        bad.append("%s: expected a list, got %s" % (k, type(v).__name__))
        continue
    for i, x in enumerate(v):
        if not isinstance(x, str):
            bad.append("%s[%d] is %s, not a string (write the item as `- |`)" % (k, i, type(x).__name__))
# A " #" in a plain value starts a comment: the load succeeds and the rest of
# the line is dropped. Block scalars and quoted strings keep it, so a "#"
# preceded by whitespace that is in the file but not in the parsed strings was
# swallowed.
seen = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            walk(k)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
    elif isinstance(o, str):
        seen.append(o)
walk(d)
hash_re = re.compile(r"(?:^|\s)#", re.M)
with open(sys.argv[1], encoding="utf-8") as f:
    raw_n = len(hash_re.findall(f.read()))
kept_n = len(hash_re.findall("\n".join(seen)))
if raw_n > kept_n:
    bad.append("%d of %d \" #\" in the file were read as a comment: the text after them is missing from the parsed memo. Write those values as `|` block scalars" % (raw_n - kept_n, raw_n))
if bad:
    print("\n".join(bad))
sys.exit(1 if bad else 0)
' "$file" $list_keys 2>&1
}

ruby_keys() {
  ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).keys.join(",")' "$file"
}

python_keys() {
  "$py" -c '
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as f:
    print(",".join(yaml.safe_load(f).keys()))
' "$file"
}

runtime="${RESUME_MEMO_YAML:-auto}"
if [ "$runtime" = auto ]; then
  if command -v ruby >/dev/null 2>&1; then
    runtime=ruby
  elif command -v "$py" >/dev/null 2>&1 && "$py" -c 'import yaml' >/dev/null 2>&1; then
    runtime=python
  else
    runtime=none
  fi
fi

if [ "$mode" = keys ]; then
  case "$runtime" in
    ruby) ruby_keys ;;
    python) python_keys ;;
    *) echo "no ruby, and no python3 with PyYAML: keys not listed" >&2; exit 3 ;;
  esac
  exit $?
fi

case "$runtime" in
  ruby) yaml_out=$(ruby_check); yaml_status=$?; yaml_label=ruby ;;
  python) yaml_out=$(python_check); yaml_status=$?; yaml_label=python ;;
  *) yaml_out=""; yaml_status=3; yaml_label=none ;;
esac
if [ "$yaml_status" -ne 0 ] && [ "$yaml_status" -ne 3 ]; then
  yaml_status=1
fi

secret_hits=""
# scan <name> <extended regex> [grep flag]; records pattern name and line numbers only.
scan() {
  local lines
  lines=$(LC_ALL=C grep -n -E ${3:+"$3"} -e "$2" "$file" | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
  if [ -n "$lines" ]; then
    secret_hits="${secret_hits}  $1 (line ${lines})"$'\n'
  fi
}
scan "PEM private key" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "GitHub token" '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,})'
scan "Slack token" 'xox[abprs]-[A-Za-z0-9-]{10,}'
scan "AWS access key ID" 'AKIA[0-9A-Z]{16}'
scan "API key (sk- prefix)" 'sk-[A-Za-z0-9_-]{20,}'
scan "URL with embedded credentials" '[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:@]+:[^@[:space:]]+@'
scan "Bearer token" '[Bb]earer [A-Za-z0-9._~+/=-]{20,}'
scan "Secret-like assignment" "(api[_-]?key|secret|passw(or)?d|token)[A-Za-z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9/+_.=-]{12,}" -i

case "$yaml_status" in
  0) echo "YAML: ok ($yaml_label)" ;;
  1) echo "YAML: FAILED ($yaml_label)"; printf '%s\n' "$yaml_out" ;;
  3) echo "YAML: NOT CHECKED (no ruby, and no python3 with PyYAML)" ;;
esac

# Count the top-level items under "done:" in an open memo. An item starts with
# "- " at indent 0 to 2; the text of a block scalar is indented deeper, so a
# "- " inside it is not counted.
if grep -q '^status: open[[:space:]]*$' "$file"; then
  done_count=$(awk '/^done:/ {f=1; next} /^[^[:space:]-]/ {f=0} f && /^ ? ?- / {n++} END {print n+0}' "$file")
  if [ "$done_count" -gt 0 ]; then
    echo "Note: done: holds $done_count item(s). Finished items belong in the archive (done/<memo file name>), not in an open memo."
  fi
fi
if [ -n "$secret_hits" ]; then
  echo "Possible secrets (remove the value, keep only the name):"
  printf '%s' "$secret_hits"
fi

if [ "$yaml_status" -eq 1 ]; then
  exit 1
elif [ -n "$secret_hits" ]; then
  exit 2
elif [ "$yaml_status" -eq 3 ]; then
  exit 3
fi
exit 0
