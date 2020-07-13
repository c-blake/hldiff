I wrote this because I wanted intra-line highlighting of character-level
deltas in my diff reports.  I also wanted a diff highlighter that honored
my `LC\_THEME` light/darkBG set up, colorized consistently between regular
diff, mercurial and git, and was fast enough to not slow down procedures
like `git log -p` at all.  `hldiff` does all that.

Along the way, some things became clear.  A) it was over 30x faster than the
Python difflib-based diff-highlight which I thought interesting and maybe
useful to others.  B) `git diff` supports most of this functionality as a
standalone `diff` program (via e.g. `--color-words`, `--word-diff-regex`,
etc.), but definitely not `LC\_THEME`.  So, it wasn't a total waste of time
for me, personally, since I actually do use daily side-by-side terminals
with varying `LC_THEME`.  On the other hand, in light of B) you might be better
served by learning to use `git diff` better unless you are addicted to Python
difflib "junk" handling or its APIs for other purposes.  { And, yes, I might
have been better served by just hacking LC\_THEME into git diff, though that
is probably a less fun micro-project. ;-) }

`hldiff` performs ok.  It is typically about 2x faster than `git log -p`.  So,
if you have two CPU cores to parallelize over `git log -p|hldiff` should take
no more real time than `git log -p`.  `hldiff` is about 4x faster than the Perl
`diff-so-fancy` and 5-10x faster than the Rust https://github.com/da-x/delta
program which crashes almost immediately for me on a Linux kernel `git log -p`.
Admittedly that `delta` program is doing (or trying to do) more work to syntax
highlight the text on a per programming language basis.  I haven't tried to
time various `git diff --word-diff-regex` configurations, but regexes can get
awfully slow.  So, `hldiff` may be faster, but more work to set up.

If you do want to use it how I do, what you need is to first compile it (`git
clone cligen` + `git clone this` and then `nim c --path:to/cligen -d:danger
hldiff` or else maybe `nimble install --passNim:-d:danger hldiff`).  Then in
your `$HOME/.config/hg/hgrc` add
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
