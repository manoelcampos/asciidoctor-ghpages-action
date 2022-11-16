#!/bin/bash

# Exit if a command fails
set -e

OWNER="$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f 1)"

if [[ "$INPUT_ADOC_FILE_EXT" != .* ]]; then
    INPUT_ADOC_FILE_EXT=".$INPUT_ADOC_FILE_EXT";
fi

echo "Configure git"
git config --global --add safe.directory /github/workspace
git fetch --all

# Checks if the user has provided a specific source dir different from the root.
# Only the files in the source dir are processed.
HAS_SOURCE_DIR=true
if [[ "$INPUT_SOURCE_DIR" == "." || "$INPUT_SOURCE_DIR" == "./" ]]; then
  HAS_SOURCE_DIR=false
fi

# If a source dir was provided, remove all other files and directories and
# keept just the ones in the source dir, moving them to the root dir.
if [[ $HAS_SOURCE_DIR == true ]]; then
  echo "Checking out the gh-pages branch on $INPUT_SOURCE_DIR (without keeping its history) from commit $GITHUB_SHA"
  git branch -D gh-pages 1>/dev/null 2>/dev/null || true
  git checkout -q --orphan gh-pages "$GITHUB_SHA" 1>/dev/null
  mv "$INPUT_SOURCE_DIR" /tmp/source
  #Ignores directories . and .git
  find . -not -path './.git*' -not -name '.' -exec rm -rf {} \; || true
  mv /tmp/source/* .
  git add .
else
  echo "Checking out the gh-pages branch (keeping its history) from commit $GITHUB_SHA"
  git checkout "$GITHUB_SHA" -B gh-pages
fi

# Executes any arbitrary shell command (such as packages installation and environment setup)
# before starting build.
# If no command is provided, the default value is just an echo command.
eval "$INPUT_PRE_BUILD"

if [[ $INPUT_SLIDES_SKIP_ASCIIDOCTOR_BUILD == false ]]; then
    echo "Converting AsciiDoc files to HTML"
    find . -name "*$INPUT_ADOC_FILE_EXT" -exec asciidoctor -b html $INPUT_ASCIIDOCTOR_PARAMS {} \;
    find . -name "README.html" -execdir ln -s "README.html" "index.html" \;
    find . -name "*$INPUT_ADOC_FILE_EXT" -exec git rm -f --cached {} \;
fi

PDF_FILE="ebook.pdf"
if [[ $INPUT_PDF_BUILD == true ]]; then
    INPUT_EBOOK_MAIN_ADOC_FILE="$INPUT_EBOOK_MAIN_ADOC_FILE$INPUT_ADOC_FILE_EXT"
    MSG="Building $PDF_FILE ebook from $INPUT_EBOOK_MAIN_ADOC_FILE"
    echo "$MSG"
    asciidoctor-pdf "$INPUT_EBOOK_MAIN_ADOC_FILE" -o "$PDF_FILE" $INPUT_ASCIIDOCTOR_PARAMS
fi

SLIDES_FILE="slides.html"
if [[ $INPUT_SLIDES_BUILD == true ]]; then
    echo "Build AsciiDoc Reveal.js slides"
    INPUT_SLIDES_MAIN_ADOC_FILE="$INPUT_SLIDES_MAIN_ADOC_FILE$INPUT_ADOC_FILE_EXT"
    MSG="Building $SLIDES_FILE with AsciiDoc Reveal.js from $INPUT_SLIDES_MAIN_ADOC_FILE"
    echo "$MSG"
    asciidoctor-revealjs -a revealjsdir=https://cdnjs.cloudflare.com/ajax/libs/reveal.js/3.9.2 "$INPUT_SLIDES_MAIN_ADOC_FILE" -o "$SLIDES_FILE"
fi

# Executes any post-processing command provided by the user, before changes are committed.
# If no command is provided, the default value is just an echo command.
echo "Running post build command."
eval "$INPUT_POST_BUILD"

echo "Adding output files to gh-pages branch."
if [[ $INPUT_SLIDES_SKIP_ASCIIDOCTOR_BUILD == false ]]; then
    find . -name "*.html" -exec git add -f {} \;
fi

if [[ $INPUT_PDF_BUILD == true ]]; then
    git add -f "$PDF_FILE";
fi

if [[ $INPUT_SLIDES_BUILD == true ]]; then
    git add -f "$SLIDES_FILE";
fi

# Changes in gh-pages branch will be shown as the "GitHub Action" user.
git config --global user.email "action@github.com"
git config --global user.name "GitHub Action"

MSG="Build $INPUT_ADOC_FILE_EXT Files for GitHub Pages from $GITHUB_SHA"
git rm -rf .github/ || true
echo "Committing changes to gh-pages branch"
git commit -m "$MSG" 1>/dev/null

# If the action is being run into the GitHub Servers,
# the checkout action (which is being used)
# automatically authenticates the container using ssh.
# If the action is running locally, for instance using https://github.com/nektos/act,
# we need to push via https with a Personal Access Token
# which should be provided by an env variable.
# We ca run the action locally using act with:
#    act -s GITHUB_TOKEN=my_github_personal_access_token
if ! ssh -T git@github.com > /dev/null 2>/dev/null; then
    URL="https://$GITHUB_TOKEN@github.com/$GITHUB_REPOSITORY.git"
    git remote remove origin
    git remote add origin "$URL"
fi

echo "Pushing changes back to the remote repository"
git push -f --set-upstream origin gh-pages
