# Package
version     = "1.0.3"
author      = "Charles Blake"
description = "A port of Python difflib to compute & (re)highlight diff output intraline"
license     = "MIT/ISC"
installExt  = @[ "nim" ]
bin         = @[ "hldiff", "hldiffpkg/edits" ]

# Dependencies
requires "nim >= 0.20.2", "cligen >= 1.8.3", "adix >= 0.6.4"
