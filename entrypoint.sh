#!/bin/bash

# Exit if a command fails
set -e

sh -c "echo 'Input Parameters:' $*"

OWNER="$(echo $GITHUB_REPOSITORY| cut -d'/' -f 1)"

if [[ "$INPUT_ADOC_FILE_EXT" != .* ]]; then 
    INPUT_ADOC_FILE_EXT=".$INPUT_ADOC_FILE_EXT"; 
fi

# Steps represent a sequence of tasks that will be executed as part of the job
echo "Configure git"
apk add git -q > /dev/null
apk add openssh-client -q > /dev/null

git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"


# Avoids keeping the commit history for the gh-pages branch, 
# so that such a branch keeps only the last commit. 
# But this slows down the GitHub Pages website build process.
echo "Checking out the gh-pages branch without keeping its history"
git branch -D gh-pages 1>/dev/null 2>/dev/null || true
git log | head -n 1 | cut -d' ' -f2 > /tmp/commit-hash.txt
git checkout -q --orphan gh-pages master 1>/dev/null

#echo "Checking out the gh-pages branch, keeping its history"
#git checkout master -B gh-pages 1>/dev/null


if [[ $INPUT_SLIDES_SKIP_ASCIIDOCTOR_BUILD == false ]]; then 
    echo "Converting AsciiDoc files to HTML"
    find . -name "*$INPUT_ADOC_FILE_EXT" | xargs asciidoctor -b html $INPUT_ASCIIDOCTOR_PARAMS

    for FILE in `find . -name "README.html"`; do 
        mv "$FILE" "`dirname $FILE`/index.html"; 
    done

    for FILE in `find . -name "*.html"`; do 
        git add -f "$FILE"; 
    done

    find . -name "*$INPUT_ADOC_FILE_EXT" | xargs git rm -f --cached
fi

if [[ $INPUT_PDF_BUILD == true ]]; then 
    PDF_FILE="ebook.pdf"
    INPUT_EBOOK_MAIN_ADOC_FILE="$INPUT_EBOOK_MAIN_ADOC_FILE$INPUT_ADOC_FILE_EXT"
    MSG="Building $PDF_FILE ebook from $INPUT_EBOOK_MAIN_ADOC_FILE"
    echo $MSG
    asciidoctor-pdf "$INPUT_EBOOK_MAIN_ADOC_FILE" -o "$PDF_FILE"
    git add -f "$PDF_FILE"; 
fi

if [[ $INPUT_SLIDES_BUILD == true ]]; then 
    echo "Build AsciiDoc Reveal.js slides"
    SLIDES_FILE="slides.html"
    INPUT_SLIDES_MAIN_ADOC_FILE="$INPUT_SLIDES_MAIN_ADOC_FILE$INPUT_ADOC_FILE_EXT"
    MSG="Building $SLIDES_FILE with AsciiDoc Reveal.js from $INPUT_SLIDES_MAIN_ADOC_FILE"
    echo $MSG
    asciidoctor-revealjs "$INPUT_SLIDES_MAIN_ADOC_FILE" -o "$SLIDES_FILE"
    git add -f "$SLIDES_FILE"; 
fi

MSG="Build $INPUT_ADOC_FILE_EXT Files for GitHub Pages from commit `cat /tmp/commit-hash.txt`"
git rm -rf .github/
echo "Commiting changes to gh-pages branch"
git commit -m "$MSG" 1>/dev/null

echo "
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
" > /etc/ssh/ssh_config

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
    git remote add origin $URL
fi

echo "Pushing changes back to the remote repository"
git push -f --set-upstream origin gh-pages 
