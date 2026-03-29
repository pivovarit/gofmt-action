# gofmt-action

> **Work in progress** — not yet published to the GitHub Marketplace.

A GitHub Action that checks Go code formatting and reports issues with **inline PR annotations**, **PR comments**, and **colorized log diffs**.

## Usage

```yaml
- uses: actions/checkout@v6
- uses: actions/setup-go@v6
  with:
    go-version: stable
- uses: pivovarit/gofmt-action@main
```

## Features

- **Inline annotations** — formatting issues appear directly on the affected lines in the PR diff
- **Colorized logs** — the full diff is displayed with syntax highlighting in the action logs

## Inputs

| Input | Description | Default |
|---|---|---|
| `formatter` | Formatter to use: `gofmt` or `goimports` | `gofmt` |
| `working-directory` | Directory to check | `.` |

## Examples

### Basic

```yaml
name: Format

on: pull_request

jobs:
  gofmt:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: stable
      - uses: pivovarit/gofmt-action@main
```

### With goimports

```yaml
- uses: pivovarit/gofmt-action@main
  with:
    formatter: goimports
```

