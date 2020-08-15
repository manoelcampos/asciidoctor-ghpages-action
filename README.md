# AsciiDoctor GitHub Pages

A GitHub Action that recursively converts every `adoc` file to `html`, renaming resulting `README.html` to `index.html` then pushing all generated html and existing files to the `gh-pages` branch.

It also keeps only the latest commit on the `gh-pages` branch, stoping it to grow too much.
