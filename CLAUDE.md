# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Docker-based GitHub Action (`manoelcampos/asciidoctor-ghpages-action`) that converts AsciiDoc files to HTML (and optionally a PDF ebook and Reveal.js slides) and force-pushes the result to the `gh-pages` branch. There is no build system, package manager or test suite: the whole action is `action.yml` + `Dockerfile` + `entrypoint.sh`.

## How the pieces connect

- `action.yml` declares the inputs and passes them to the container as **positional** `args`. `entrypoint.sh` does not use those positional args: it reads the `INPUT_<NAME>` env vars that GitHub sets for each input. Still, when adding an input, add it to both `inputs:` and `args:` in `action.yml` (keep the order consistent), then read it as `$INPUT_<UPPERCASE_NAME>` in `entrypoint.sh`.
- `Dockerfile` is based on `asciidoctor/docker-asciidoctor:latest` (provides `asciidoctor`, `asciidoctor-pdf`, `asciidoctor-revealjs`) and adds `openssh-client` and `git-lfs`.
- `entrypoint.sh` flow (runs with `set -e` inside `/github/workspace`):
  1. Checks out `gh-pages` from `$GITHUB_SHA`. With a `source_dir`, it creates an **orphan** branch (no history) holding only that dir's content moved to the root; otherwise it resets `gh-pages` to the commit (keeping history).
  2. `eval "$INPUT_PRE_BUILD"`.
  3. Builds every `*$INPUT_ADOC_FILE_EXT` file to HTML (unless `slides_skip_asciidoctor_build`), symlinks `README.html` → `index.html` in each dir, and removes the adoc sources from the index.
  4. Optional `ebook.pdf` (from `ebook_main_adoc_file`) and `slides.html` (from `slides_main_adoc_file`). Main file inputs are given **without** extension; the script appends `adoc_file_ext`.
  5. `eval "$INPUT_POST_BUILD"`, then force-adds the generated outputs (they may be gitignored) and removes `.github/`.
  6. `publish_only_dir`: if `publish_dir` is set, replaces the git index with the subtree of that dir via `git write-tree --prefix` + `git read-tree`, so only it lands at the `gh-pages` root while the build could use files outside it.
  7. Commits as "GitHub Action" and `git push -f` to `gh-pages`. If SSH auth to GitHub fails (e.g. running locally), it switches `origin` to HTTPS using `$GITHUB_TOKEN`.

## Testing changes

- This repo publishes its own docs (`README.adoc`, `how-action-works.adoc`) with `.github/workflows/asciidoctor-ghpages.yml`. Note that the workflow uses the released `manoelcampos/asciidoctor-ghpages-action@v2`, not the local code, so it does not test changes unless switched to `uses: ./`.
- Test the action locally with [act](https://github.com/nektos/act), which runs the workflow in containers using Docker or Podman:

  ```bash
  act -s GITHUB_TOKEN=<personal_access_token>
  ```

  - The token is needed because the push falls back to HTTPS when SSH auth to GitHub isn't available in the container.
  - With Podman, point act to the Podman socket first, e.g. on macOS: `export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"`.
  - Be aware it really force-pushes to the `gh-pages` branch of the remote repo.
  - Leftover containers from previous runs can be removed with `docker ps -a | grep ghpages-action | awk '{print $1}' | xargs docker rm -f` (use `podman` instead of `docker` when needed).
- Shell lint (not configured in the repo, but useful): `shellcheck entrypoint.sh`.

## Releases and docs

- Users reference the action by major tag (`@v2`), and releases are tagged as `vX.Y.Z`. The `v2` tag does not always point to the latest release, so check it when releasing.
- `README.adoc` is the user documentation and is also published as the site's `index.html`. Document new inputs there (and in the commented example in the workflow file). It uses `ifdef::env-github` / `backend-pdf` conditionals, so content can differ between GitHub, HTML and PDF outputs.
