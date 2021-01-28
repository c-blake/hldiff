Overview
========
This package is a port of Python's `difflib` algorithms to compute edits, diffs,
patches on pairs of `seq[T]` (lines, chars, etc.) in `hldiffpkg/edits.nim`.
An example re-implementation of `diff -u` ends `hldiffpkg/edits.nim`.  `edits`
is also the engine to (re)highlight intraline the output of `diff -u`, `git
diff`, or `hg diff` with user-customizable ANSI/SGR escapes. Color configuration
is similar to
[cligen](https://github.com/c-blake/cligen)/[lc](https://github.com/c-blake/lc)/[procs](https://github.com/c-blake/procs)
using the same internal engine.  `edits` also provides/exports an edit distance
based on the algorithm (from Ratcliff1988), here called `similarity` and a
common-needs API `closeTo` that gives "nearby suggestions" for Nim `string`s.

Motivation
==========
While writing it, it became clear that `git diff` as a standalone `diff` program
(via e.g. `--color-words`, `--word-diff-regex`, etc.) supports the highlighting
I had wanted.  In spite of this, it wasn't a waste of time for me, personally,
since I use side-by-side terminals with varying `LC_THEME` already set up for
`cligen`, `procs`, `lc`, etc.  On the other hand, in light of this, many may be
better served by learning to better use `git diff`.  { And, yes, I may have been
better served by just hacking `LC_THEME` into `git diff`, though that is a less
fun micro-project. ;-) }

After writing it, a secondary motivation emerged.  The core difflib part of this
package is ~90x faster than the Python impl.  Applied to highlighting, this
yields a useful trait.  Since `hldiff` is typically 2-6x faster than `git log
-p`, if you have >=1.5 free CPU cores (a common case for me) then `git log -p |
hldiff` should take *no more real time* than `git log -p` (which can take an
annoyingly long time itself).  I found no other package with a similar "no extra
time" trait.

Assuming 2 free CPU cores, such a program would need to be no more than 2x
slower than `hldiff`.  E.g., Perl `diff-so-fancy` is 9..12x slower.  Meanwhile
`hldiff` is 15-30x faster than Rust https://github.com/da-x/delta program which
crashes immediately for me on a Linux kernel `git log -p`. { `delta` does (or
tries to do) more work to syntax highlight the text on a per prog.lang basis. }
I've not timed various `git diff --word-diff-regex` configs, but regexes get
awfully slow and git does not go multi-threaded for highlighting purposes.  So,
as far as I can tell, `hldiff` may be the only way (at present) to highlight
diff output that does not make users wait longer on already slow jobs.

Performance Evaluation
======================
Here is a table of timing results from reproducible logs.  Times are in seconds.
Input is from the mentioned newest commit to the beginning of time saved to a
RAM FS (Linux tmpfs) on an Intel i6700k.  `git log -p` is also off of a tmpfs
`.git`.  `hldiff` is PGO-gcc compiled highlighting its own history as a test
program.  `diff-so-fancy-1.3.0` runs under gcc-10.2-compiled perl-5.32.
| Source  | Newest Commit |      Bytes | log -p | hldiff | diff-so-fancy |
| :------ | :-----------: | ---------: | -----: | -----: | ------------: |
| Nim-dev | ..db6b1e5769b |  176119650 |   8.73 |   4.36 |         45.82 |
| CPython | ..d3277048ac6 | 1032265657 |  69.58 |  31.33 |        289.10 |
| Linux   | ..71d8e5ff763 | 5124372488 | 731.48 | 100.58 |       1325.12 |

`git log -p` varies from 7..20 MB/s, `hldiff` hits 33..51 MB/s, `diff-so-fancy`
does 3.57..3.87 MB/s.  Chances are default `hldiff` is fast enough, but you can
speed it up with, e.g., `hldiff -b10` to lower abort thresholds for char-by-char
highlights of substitution hunks.  For the above 3 e.g.s times become 3.5,
22.0, 85.5 seconds.

Installation
============
First compile it (`git clone <CLIGEN>`, `git clone <THIS>`, and then
`nim c --path:to/cligen --gc:orc -d:danger hldiff`.  Alternatively, you can
`nimble install hldiff`).  A profile-guided optimization (PGO) build is a
user-exercise but only about 10% faster in this case.

Then to `$HOME/.config/hg/hgrc` add
```
[pager]
pager = hldiff|less -R
```
and in your `$HOME/.config/git/config` add
```
[pager]
  log  = "hldiff|less -R"
  diff = "hldiff|less -R"
```
You may also want a wrapper script/shell function `diffu` to do `diff -u
"$@"|hldiff` or similar.

You will also want to `cp example.cf $HOME/.config/hldiff` and edit it to your
liking.  ANSI SGR escape names are the usual suspects from `cligen/humanUt.nim`:
```
plain, bold, italic, underline, blink, inverse, struck, NONE,
black, red, green, yellow, blue, purple, cyan, white;
UPPERCASE =>HIGH intensity; "on_" prefix => BACKGROUND color
256-color attrs are [fb][0..23] for FORE/BACK grey scl & [fb]RGB
a 6x6x6 color cube; each [RGB] is on [0,5].
xterm/st/kitty/alacrity true color: [fb]HHHHHH (usual RGB order).
```
