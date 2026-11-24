#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
out=$(realpath -m "${1:?pass an output directory}")
mkdir -p "$out"
cache=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
if [[ -z ${ZAP_HOME:-} ]]; then
    archive="$cache/ZAP_2.17.0_Linux.tar.gz"
    curl -fsSL --retry 3 -o "$archive" https://github.com/zaproxy/zaproxy/releases/download/v2.17.0/ZAP_2.17.0_Linux.tar.gz
    printf '%s  %s\n' efe799aaa3627db683b43f00c9c210aea0b75c00cc8f0a0f0434d12bb3ddde5a "$archive" | sha256sum -c -
    tar -xzf "$archive" -C "$cache"
    ZAP_HOME="$cache/ZAP_2.17.0"
fi
for i in {1..60}; do
    if [[ $(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8000/login/ || true) == 200 ]]; then break; fi
    sleep 2
done
for path in / /login/ /register; do
    status=$(curl --noproxy '*' --max-time 10 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:8000$path")
    printf '%s\t%s\n' "$path" "$status"
    if [[ $path == / ]]; then [[ $status == 302 ]]; else [[ $status == 200 ]]; fi
done > "$out/http-status.tsv"
cp "$repo/.github/lab5/zap.yaml" "$out/zap.yaml"
cd "$out"
"$ZAP_HOME/zap.sh" -silent -cmd -dir "$out/zap-session" -autorun "$out/zap.yaml" > "$out/zap-console.log" 2>&1 || {
    code=$?
    # The Automation Framework uses 2 for warnings. Preserve reports and inspect them below.
    if [[ $code != 2 ]]; then cat "$out/zap-console.log"; exit "$code"; fi
}
test -s zap-report.html
python3 - <<'PY'
import json
from pathlib import Path
report = json.loads(Path("zap-report.json").read_text())
sites = report.get("site", [])
if len(sites) != 1 or sites[0]["@name"] != "http://127.0.0.1:8000":
    raise SystemExit("Missing loopback site in ZAP report")
alerts = sites[0].get("alerts", [])
print(f"ZAP {report['@version']}, {len(alerts)} alert types")
for alert in alerts:
    print(alert["pluginid"], alert["riskdesc"], alert["name"], alert["count"])
PY
