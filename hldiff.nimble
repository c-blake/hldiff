# Package
version     = "0.1"
author      = "Charles Blake"
description = "A highlighter for diff -u-like output & port of Python difflib"
license     = "MIT/ISC"
srcDir      = "src"
bin         = @[ "hldiff", "edits" ]

# Dependencies
requires "nim >= 0.20.2", "cligen#head"
