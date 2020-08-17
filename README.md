Overview
========
This package is a port of Python's `difflib` algorithms to compute edits, diffs,
patches in `src/edits.nim`.  There is an example re-implementation of `diff -u`
at the end of `src/edits.nim` installed by default.  `edits`is, in turn, used to
build an engine to (re)highlight intraline the output of `diff -u` or `git diff`
or `hg diff` with user-customizable ANSI/SGR escape sequences.  Configuration of
colorization is similar to
[cligen](https://github.com/c-blake/cligen)/[lc](https://github.com/c-blake/lc)/[procs](https://github.com/c-blake/procs)
using the same internal engine.

Motivation
==========
While writing it, it became clear that `git diff` as a standalone `diff` program
(via e.g. `--color-words`, `--word-diff-regex`, etc.) supports the highlighting
I had wanted.  In spite of this, it wasn't a waste of time for me, personally,
since I use daily side-by-side terminals with varying `LC_THEME` already set up
for `cligen`, `procs`, `lc`, etc.  On the other hand, in light of this, you may
be better served by learning to better use `git diff`.  { And, yes, I may have
been better served by just hacking `LC_THEME` into `git diff`, though that is
probably a less fun micro-project. ;-) }

After writing it, a secondary motivation emerged.  The core difflib part of this
package is over 30x faster than the Python impl.  Applied to highlighting, this
achieves an interesting property.  Since `hldiff` is typically about 2x faster
than `git log -p`, if you have >=1.5 free CPU cores (a common case for me) then
`git log -p|hldiff` should take *no more real time* than `git log -p` (which can
take quite a while in human terms on a large, old repository).  I found no other
package with a similar "no extra time" trait.  Assuming 2 free CPU cores, such a
program would need to be no more than 2x slower than `hldiff`.  E.g., `hldiff`
is about 4x faster than a Perl `diff-so-fancy` & 5-10x faster than a Rust
https://github.com/da-x/delta program which crashes immediately for me on a
Linux kernel `git log -p`. { `delta` does (or tries to do) more work to syntax
highlight the text on a per prog.lang basis. } I've not timed various `git diff
--word-diff-regex` configs, but regexes get awfully slow and git does not go
multi-threaded for highlighting purposes.  So, `hldiff` may be the only way to
highlight diff output that does not make users wait longer on already slow jobs.

Intallation
===========
If you want to use it, what you need is to first compile it (`git clone cligen`
+ `git clone this`, then `nim c --path:to/cligen -d:danger hldiff` or `nimble
install --passNim:-d:danger hldiff`).  Then to `$HOME/.config/hg/hgrc` add
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
256-color xterm attrs are [fb][0..23] for FORE/BACKgrnd grey scale & [fb]RGB
a 6x6x6 color cube; each [RGB] is on [0,5].
xterm/st true colors are [fb]HHHHHH (usual R,G,B mapping).
```
