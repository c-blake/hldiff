# Package
version     = "0.1"
author      = "Charles Blake"
description = "A port of Python difflib to (re)highlight diff output intraline"
license     = "MIT/ISC"
srcDir      = "src"
bin         = @[ "hldiff", "edits" ]

# Dependencies
requires "nim >= 0.20.2", "cligen#head"
