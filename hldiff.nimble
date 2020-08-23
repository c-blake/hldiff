# Package
version     = "0.2"
author      = "Charles Blake"
description = "A port of Python difflib to compute & (re)highlight diff output intraline"
license     = "MIT/ISC"
srcDir      = "hldiffpkg"
installExt  = @[ "nim" ]
bin         = @[ "hldiff", "edits" ]

# Dependencies
requires "nim >= 0.20.2", "cligen#head"
