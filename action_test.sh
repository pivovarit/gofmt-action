#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/action.sh"

passed=0
failed=0

run_test() {
  local name="$1"
  local dir="$2"
  local expected_exit="$3"
  shift 3
  local expected_patterns=("$@")

  local output
  local actual_exit=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || actual_exit=$?

  local test_failed=false

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $name"
    echo "  expected exit code $expected_exit, got $actual_exit"
    test_failed=true
  fi

  for pattern in "${expected_patterns[@]}"; do
    if ! echo "$output" | grep -qF "$pattern"; then
      echo "FAIL: $name"
      echo "  expected output to contain: $pattern"
      echo "  output was:"
      echo "$output" | sed 's/^/    /'
      test_failed=true
      break
    fi
  done

  if [[ "$test_failed" == "true" ]]; then
    failed=$((failed + 1))
  else
    echo "PASS: $name"
    passed=$((passed + 1))
  fi
}

setup_dir() {
  local dir
  dir=$(mktemp -d)
  echo "$dir"
}

test_clean() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello")
}
EOF
  run_test "clean code passes" "$dir" 0 "All Go files are properly formatted."
  rm -rf "$dir"
}

test_misformatted() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

import "fmt"

func main() {
fmt.Println( "hello" )
}
EOF
  run_test "misformatted code fails" "$dir" 1 \
    "::error file=main.go,line=" \
    "Found formatting issues in 1 file(s)." \
    "Run 'gofmt -w .' to fix."
  rm -rf "$dir"
}

test_multiple_files() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/a.go" << 'EOF'
package main

func a(){
}
EOF
  cat > "$dir/b.go" << 'EOF'
package main

func b(){
}
EOF
  run_test "multiple misformatted files" "$dir" 1 \
    "::error file=a.go,line=" \
    "::error file=b.go,line=" \
    "Found formatting issues in 2 file(s)."
  rm -rf "$dir"
}

test_mixed() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/clean.go" << 'EOF'
package main

func clean() {
}
EOF
  cat > "$dir/dirty.go" << 'EOF'
package main

func dirty(){
}
EOF
  run_test "mixed clean and dirty files" "$dir" 1 \
    "::error file=dirty.go,line=" \
    "Found formatting issues in 1 file(s)."
  rm -rf "$dir"
}

test_empty_dir() {
  local dir
  dir=$(setup_dir)
  run_test "empty directory passes" "$dir" 0 "All Go files are properly formatted."
  rm -rf "$dir"
}

test_multiple_hunks() {
  local dir
  dir=$(setup_dir)
  {
    echo 'package main'
    echo ''
    echo 'func a(){}'
    echo ''
    for i in $(seq 1 20); do
      printf 'var x%d = %d\n' "$i" "$i"
    done
    echo ''
    echo 'func b(){}'
  } > "$dir/multi.go"

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  local annotation_count
  annotation_count=$(echo "$output" | grep -c '::error file=multi.go,line=' || true)

  if [[ "$exit_code" -ne 1 ]]; then
    echo "FAIL: multiple hunks produce multiple annotations"
    echo "  expected exit code 1, got $exit_code"
    failed=$((failed + 1))
  elif [[ "$annotation_count" -lt 2 ]]; then
    echo "FAIL: multiple hunks produce multiple annotations"
    echo "  expected at least 2 annotations, got $annotation_count"
    echo "  output was:"
    echo "$output" | sed 's/^/    /'
    failed=$((failed + 1))
  else
    echo "PASS: multiple hunks produce multiple annotations"
    passed=$((passed + 1))
  fi
  rm -rf "$dir"
}

test_invalid_formatter() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main
EOF

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=invalid bash "$CHECK" 2>&1) || exit_code=$?

  if [[ "$exit_code" -ne 1 ]]; then
    echo "FAIL: invalid formatter rejected"
    echo "  expected exit code 1, got $exit_code"
    failed=$((failed + 1))
  elif ! echo "$output" | grep -qF "::error::Unknown formatter: invalid"; then
    echo "FAIL: invalid formatter rejected"
    echo "  expected error about unknown formatter"
    failed=$((failed + 1))
  else
    echo "PASS: invalid formatter rejected"
    passed=$((passed + 1))
  fi
  rm -rf "$dir"
}

test_group_output() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

func main(){
}
EOF
  run_test "collapsible group in output" "$dir" 1 \
    "::group::Formatting diff" \
    "::endgroup::"
  rm -rf "$dir"
}

test_annotation_content() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

func add(a,b int)int{
return a+b
}
EOF

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  if [[ "$exit_code" -ne 1 ]]; then
    echo "FAIL: annotation contains diff content"
    echo "  expected exit code 1, got $exit_code"
    failed=$((failed + 1))
  elif ! echo "$output" | grep '::error file=main.go' | grep -qF 'func add(a, b int) int'; then
    echo "FAIL: annotation contains diff content"
    echo "  expected annotation to contain corrected signature"
    echo "  output was:"
    echo "$output" | sed 's/^/    /'
    failed=$((failed + 1))
  else
    echo "PASS: annotation contains diff content"
    passed=$((passed + 1))
  fi
  rm -rf "$dir"
}

test_clean
test_misformatted
test_multiple_files
test_mixed
test_empty_dir
test_multiple_hunks
test_invalid_formatter
test_group_output
test_annotation_content

echo ""
echo "--- Results: $passed passed, $failed failed ---"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
