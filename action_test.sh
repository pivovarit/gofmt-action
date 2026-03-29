#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/action.sh"

setup_dir() {
  mktemp -d
}

function test_clean_code_passes() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello")
}
EOF

  local output
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1)

  assert_equals 0 $?
  assert_contains "All Go files are properly formatted." "$output"
  rm -rf "$dir"
}

function test_misformatted_code_fails() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

import "fmt"

func main() {
fmt.Println( "hello" )
}
EOF

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  assert_equals 1 "$exit_code"
  assert_contains "::error file=main.go,line=" "$output"
  assert_contains "Found formatting issues in 1 file(s)." "$output"
  assert_contains "Run 'gofmt -w .' to fix." "$output"
  rm -rf "$dir"
}

function test_multiple_misformatted_files() {
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

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  assert_equals 1 "$exit_code"
  assert_contains "::error file=a.go,line=" "$output"
  assert_contains "::error file=b.go,line=" "$output"
  assert_contains "Found formatting issues in 2 file(s)." "$output"
  rm -rf "$dir"
}

function test_mixed_clean_and_dirty_files() {
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

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  assert_equals 1 "$exit_code"
  assert_contains "::error file=dirty.go,line=" "$output"
  assert_contains "Found formatting issues in 1 file(s)." "$output"
  rm -rf "$dir"
}

function test_empty_directory_passes() {
  local dir
  dir=$(setup_dir)

  local output
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1)

  assert_equals 0 $?
  assert_contains "All Go files are properly formatted." "$output"
  rm -rf "$dir"
}

function test_multiple_hunks_produce_multiple_annotations() {
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

  assert_equals 1 "$exit_code"

  local annotation_count
  annotation_count=$(echo "$output" | grep -c '::error file=multi.go,line=' || true)
  assert_greater_or_equal_than "$annotation_count" 2
  rm -rf "$dir"
}

function test_invalid_formatter_rejected() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main
EOF

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=invalid bash "$CHECK" 2>&1) || exit_code=$?

  assert_equals 1 "$exit_code"
  assert_contains "::error::Unknown formatter: invalid" "$output"
  rm -rf "$dir"
}

function test_collapsible_group_in_output() {
  local dir
  dir=$(setup_dir)
  cat > "$dir/main.go" << 'EOF'
package main

func main(){
}
EOF

  local output
  local exit_code=0
  output=$(cd "$dir" && FORMATTER=gofmt bash "$CHECK" 2>&1) || exit_code=$?

  assert_equals 1 "$exit_code"
  assert_contains "::group::Formatting diff" "$output"
  assert_contains "::endgroup::" "$output"
  rm -rf "$dir"
}

function test_annotation_contains_diff_content() {
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

  assert_equals 1 "$exit_code"

  local annotation
  annotation=$(echo "$output" | grep '::error file=main.go')
  assert_contains "func add(a, b int) int" "$annotation"
  rm -rf "$dir"
}
