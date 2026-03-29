#!/usr/bin/env bash
set -euo pipefail

FORMATTER="${FORMATTER:-gofmt}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"
PATH_PREFIX=""
if [[ "$WORKING_DIRECTORY" != "." ]]; then
  PATH_PREFIX="${WORKING_DIRECTORY%/}/"
fi

if [[ "$FORMATTER" != "gofmt" && "$FORMATTER" != "goimports" ]]; then
  echo "::error::Unknown formatter: $FORMATTER (must be gofmt or goimports)"
  exit 1
fi

if ! command -v "$FORMATTER" &>/dev/null; then
  echo "::error::$FORMATTER not found. Make sure Go is installed (actions/setup-go)."
  exit 1
fi

diff_output=$("$FORMATTER" -d . 2>&1) || true

if [[ -z "$diff_output" ]]; then
  echo "All Go files are properly formatted."
  exit 0
fi

current_file=""
current_line=0
hunk_offset=0
in_context=true
annotation_lines=()

emit_annotation() {
  if [[ -n "$current_file" && ${#annotation_lines[@]} -gt 0 ]]; then
    local actual_line=$((current_line + hunk_offset))
    body=$(printf '%s%%0A' "${annotation_lines[@]}")
    body="${body%\%0A}"
    echo "::error file=${PATH_PREFIX}${current_file},line=${actual_line},title=${FORMATTER}::${body}"
  fi
  annotation_lines=()
}

file_count=0
declare -A seen_files

while IFS= read -r line; do
  if [[ "$line" =~ ^diff\ (.+)\.orig\ (.+)$ ]]; then
    emit_annotation
    current_file="${BASH_REMATCH[2]}"
    if [[ -z "${seen_files[$current_file]+_}" ]]; then
      seen_files[$current_file]=1
      file_count=$((file_count + 1))
    fi
  elif [[ "$line" =~ ^@@\ -([0-9]+) ]]; then
    emit_annotation
    current_line="${BASH_REMATCH[1]}"
    hunk_offset=0
    in_context=true
  elif [[ "$line" =~ ^[-+] ]] && [[ ! "$line" =~ ^(---|\+\+\+) ]]; then
    in_context=false
    annotation_lines+=("$line")
  elif [[ "$line" =~ ^\  ]] && [[ "$in_context" == "true" ]]; then
    hunk_offset=$((hunk_offset + 1))
  fi
done <<< "$diff_output"

emit_annotation

RED=$'\033[31m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

echo ""
echo "::group::Formatting diff ($file_count file(s))"
while IFS= read -r line; do
  if [[ "$line" =~ ^diff\ |^---\ |^\+\+\+\  ]]; then
    echo "${BOLD}${line}${RESET}"
  elif [[ "$line" =~ ^@@ ]]; then
    echo "${CYAN}${line}${RESET}"
  elif [[ "$line" =~ ^- ]]; then
    echo "${RED}${line}${RESET}"
  elif [[ "$line" =~ ^\+ ]]; then
    echo "${GREEN}${line}${RESET}"
  else
    echo "$line"
  fi
done <<< "$diff_output"
echo "::endgroup::"

echo ""
echo "Found formatting issues in $file_count file(s)."
echo "Run '$FORMATTER -w .' to fix."

post_pr_comment() {
  if [[ "${POST_COMMENT:-true}" != "true" ]]; then
    return
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "::warning::GITHUB_TOKEN not set, skipping PR comment."
    return
  fi

  local pr_number=""
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    pr_number=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
  fi

  if [[ -z "$pr_number" || "$pr_number" == "null" ]]; then
    return
  fi

  local marker="<!-- gofmt-action -->"
  local comment_body
  comment_body="${marker}
## gofmt-action

Found formatting issues in **${file_count} file(s)**.

<details>
<summary>Diff (click to expand)</summary>

\`\`\`diff
${diff_output}
\`\`\`

</details>

Run \`${FORMATTER} -w .\` to fix."

  local api_url="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments"

  local existing_comment_id
  existing_comment_id=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?per_page=100" \
    | jq -r ".[] | select(.body | startswith(\"${marker}\")) | .id" \
    | head -1) || true

  if [[ -n "$existing_comment_id" ]]; then
    curl -sf \
      -X PATCH \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
      -d "$(jq -n --arg body "$comment_body" '{body: $body}')" > /dev/null
    echo "Updated existing PR comment."
  else
    curl -sf \
      -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "${api_url}" \
      -d "$(jq -n --arg body "$comment_body" '{body: $body}')" > /dev/null
    echo "Posted PR comment."
  fi
}

post_pr_comment

autofix() {
  if [[ "${AUTOFIX:-false}" != "true" ]]; then
    return 1
  fi

  if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
    echo "::warning::Autofix only works on pull_request events."
    return 1
  fi

  local head_ref
  head_ref=$(jq -r '.pull_request.head.ref' "$GITHUB_EVENT_PATH")

  if [[ -z "$head_ref" || "$head_ref" == "null" ]]; then
    echo "::warning::Could not determine PR branch for autofix."
    return 1
  fi

  "$FORMATTER" -w .

  git config user.name "gofmt-action"
  git config user.email "gofmt-action@github.com"
  git checkout "$head_ref"
  git add -A
  git commit -m "style: apply $FORMATTER"
  git push
  echo "Pushed formatting fix to $head_ref."
  return 0
}

if autofix; then
  exit 0
fi

exit 1
