# Package
version     = "0.1"
author      = "Charles Blake"
description = "A highlighter for diff -u-like output & port of Python difflib"
license     = "MIT/ISC"
bin         = @[ "hldiff" ]

# Dependencies
requires "nim > 0.20.1", "cligen#head"
