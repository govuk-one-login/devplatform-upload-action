#!/usr/bin/env bash
set -euo pipefail

echo "COMMIT_AUTHOR='$GITHUB_ACTOR'"
echo "MERGE_TIME='$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")'"
