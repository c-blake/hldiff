import std/[strutils, os, sets, tables], hldiffpkg/edits,
       cligen/[parseopt3, sysUt, osUt, textUt, humanUt]
when not declared(stdin): import std/syncio
var
  highlights = { #key lower for optionNormalize camelCase kebab-case snake_case
    "regular"           : "plain"      ,
    "commitheadername"  : "blue"       ,
    "commitheadervalue" : "purple"     ,
    "commitmessage"     : "cyan"       ,
    "diffheader"        : "yellow"     ,
    "hunkheader"        : "white"      ,
    "equal"             : "NONE"       ,
    "deleted"           : "red"        ,
    "deletedemph"       : "red inverse",
    "inserted"          : "green"      ,
    "insertedemph"      : "green inverse" }.toTable
  attr: Table[string, string]   # Above table realized post-start up/parseColor
  hlReg, hlCommitHdNm, hlCommitHdVal, hlCommitMsg, hlDiffHdr, hlHunkHdr,
    hlEql, hlDel, hlDelEmph, hlIns, hlInsEmph: string #No-lookup access to above
  dhl    = false                # Highlight diff header ---/+++ lines like edits
  thresh = 30                   # Similarity threshold to do char-by-char diff
  junks: HashSet[char]          # Use Python difflib-like junk heuristic
  bskip  = 20                   # Do not char-by-char block pairs > bskip*bskip

var pt: seq[string]             # Current (p)ar(t)/section being highlighted

template emit(a: varargs[string, `$`]) = outu(a)

proc parseColor(color: seq[string], plain=false) =
  let plain = plain or existsEnv("NO_COLOR")
  for spec in color:
    let cols = spec.strip.splitWhitespace(1)
    if cols.len < 2: Value !! "bad color line: \"" & spec & "\""
    let key = cols[0].optionNormalize
    if key notin highlights: Value !! "unknown color key: \"" & spec & "\""
    highlights[key] = cols[1]
  for k, v in highlights: attr[k] = textAttr(v, plain)
  hlReg         = attr["regular"]
  hlCommitHdNm  = attr["commitheadername"]
  hlCommitHdVal = attr["commitheadervalue"]
  hlCommitMsg   = attr["commitmessage"]
  hlDiffHdr     = attr["diffheader"]
  hlHunkHdr     = attr["hunkheader"]
  hlEql         = attr["equal"]
  hlDel         = attr["deleted"]
  hlDelEmph     = attr["deletedemph"]
  hlIns         = attr["inserted"]
  hlInsEmph     = attr["insertedemph"]

proc isHeader(ln: string): bool {.inline.} =    # Check [A-Za-z]+:<WHITESPC>
  var sawLetter = false
  var sawColon = false
  for c in ln:
    if c in {'A'..'Z', 'a'..'z'}: sawLetter = true; continue
    if sawLetter and not sawColon and c == ':': sawColon = true; continue
    if c in Whitespace: return sawLetter and sawColon
    return false

proc rendCommitHd() =
  for ln in pt:
    if ln.startsWith("commit ") or ln.isHeader:
      let ix = ln.find(Whitespace)
      emit hlCommitHdNm , ln[0..<ix], hlReg
      emit hlCommitHdVal, ln[ix..^1], hlReg, '\n'
    else:
      emit hlCommitMsg, ln, hlReg, '\n'

proc rendDiffHd() =
  for ln in pt:
    if   dhl and ln.len > 0 and ln[0] == '-': emit hlDel, ln, hlReg, '\n'
    elif dhl and ln.len > 0 and ln[0] == '+': emit hlIns, ln, hlReg, '\n'
    else: emit hlDiffHdr, ln, hlReg, '\n'

proc rendSub(a, b: int; nDel: int, th=thresh) =
  let n = b + 1 - a
  var mx = 0
  for i in a..b: mx = max(mx, pt[i].len)
  if mx > 300*bskip or nDel*(n - nDel) > bskip*bskip:     # CHAR-BY-CHAR slow &
    for i in 0 ..< nDel: emit hlDel, pt[a+i], hlReg, '\n' #..useless for giants
    for j in nDel ..< n: emit hlIns, pt[a+j], hlReg, '\n'
    return
  type Pair = tuple[i, sim: uint16; ss: seq[Same]]
  var pairs = newSeq[Pair](b + 1)
  var sims  = newSeq[tuple[sim, j: uint16]](b + 1)
  var pair0: Pair
  for j in nDel ..< n:                            # FIRST PAIR "CLOSE" LINES
    let gJ = pt[a+j][1..^1]
    var c = initCmper("", gJ, junks) # if flg: set1 else: set2 => arc/orc leak
    var pairJ: Pair
    for i in 0 ..< nDel:                          # pairJ -> most similar i
      let gI  = pt[a+i][1..^1]
      let sMx = gI.len + gJ.len                   # check upper bounds first
      if min(gI.len, gJ.len)*100 > th * sMx and similUB1(gI, gJ)*100 > th * sMx:
        let ss  = c.sames(gI, gJ)                 # ss = CHAR-BY-CHAR DIFF
        let sim = uint16(ss.similarity * 10_000 div sMx)
        if sim > uint16(100 * th) and sim > pairJ.sim:
          pairJ.i   = i.uint16
          pairJ.sim = sim
          pairJ.ss  = ss
    if pairJ.sim > sims[pairJ.i].sim:
      sims[pairJ.i] = (pairJ.sim, j.uint16)       # Retain only max sim @given i
      pairs[j] = move(pairJ)
  for i in 0 ..< nDel:
    let j = sims[i].j
    if j > 0 and pairs[sims[i].j] != pair0:       # CHAR-BY-CHAR DIFF => HILITE
      let gI = pt[a+i][1..^1]                     # let gJ = pt[a+j][1..^1]
      emit hlDel, '-', hlReg
      for ed in edits(pairs[j].ss):
        case ed.ek
        of ekEql       : emit hlDel    , gI[ed.s], hlReg
        of ekDel, ekSub: emit hlDelEmph, gI[ed.s], hlReg
        else: discard
      emit '\n'
    else:
      emit hlDel, pt[a+i], hlReg, '\n'
  for j in nDel ..< n:
    if pairs[j] != pair0:                         # CHAR-BY-CHAR DIFF => HILITE
      let p = pairs[j]; let gJ = pt[a+j][1..^1]
      emit hlIns, '+', hlReg
      for ed in edits(p.ss):
        case ed.ek
        of ekEql       : emit hlIns    , gJ[ed.t], hlReg
        of ekIns, ekSub: emit hlInsEmph, gJ[ed.t], hlReg
        else: discard
      emit '\n'
    else:
      emit hlIns, pt[a+j], hlReg, '\n'

proc render(a, b: int; ek: EdKind, nDel: int) {.inline.} =
  if b < a: return
  case ek
  of ekEql: (for i in a..b: emit hlEql, pt[i], hlReg, '\n')
  of ekDel: (for i in a..b: emit hlDel, pt[i], hlReg, '\n')
  of ekIns: (for i in a..b: emit hlIns, pt[i], hlReg, '\n')
  of ekSub: rendSub a, b, nDel

type PartKind = enum pkCommitHd, pkDiffHd, pkDiffHunk

iterator stdinParts(): PartKind =
  ## A fast, one-pass iterator to classify input lines into blocks.  Note that
  ## an empty ``pkCommitHd`` occurs @start|end of ``diff -ru``|mercurial inputs.
  var state = pkCommitHd
  for raw in stdin.lines:               #NOTE: this strips either \r\n or \n
    let ln = raw.stripSGR
    if state == pkDiffHd and ln.startsWith("+++"):
      pt.add ln
      yield state
      pt.setLen 0
      state = pkDiffHunk
    elif state != pkDiffHd and (ln.startsWith("diff") or ln.startsWith("---")):
      yield state                       # yield whatever we have & switch
      pt = @[ ln ]
      state = pkDiffHd                  #..to accumulating diff header
    elif pt.len > 0 and ln.startsWith("@@"):
      yield state                       # New hunk; yield & reset
      pt = @[ ln ]
    elif ln.len == 0:                   # one+ pure blanks re-enters commit hdr
      yield state
      pt = @[ ln ]
      state = pkCommitHd
    else:                               # non-blank; accumulate
      pt.add ln
  yield state

const sb = { ' ', '\\' }  # Mercurial emits "^\ No newline at end of file"
proc rendDiffHunk() =
  ## Fancy intra-line diff highlighting of edit hunks.
  emit hlHunkHdr, pt[0], hlReg, '\n'    # render "@@" hunk header line.
  var state = ekEql
  var a = 1; var b = 0
  var nDel = 0
  for i in 1 ..< pt.len:
    if pt[i].len < 1: Value !! "malformatted diff"
    let c = pt[i][0]
    if (state == ekEql and c in sb) or (state == ekDel and c == '-') or
       (c == '+' and state in {ekIns, ekSub}):  # any->self: accumulate
      b = i
    elif c in sb:                               # any->eql
      render a, b, state, nDel; nDel = 0
      a = i; b = a
      state = ekEql
    elif state == ekEql and (c=='-' or c=='+'): # eql->(del|ins)
      render a, b, state, nDel; nDel = 0
      a = i; b = a
      state = if c == '-': ekDel else: ekIns
    elif state == ekDel and c == '+':           # del->sub
      nDel = b + 1 - a
      b = i
      state = ekSub
  render a, b, state, nDel

when isMainModule:
  import cligen; include cligen/mergeCfgEnv

  proc hldiff(color: seq[string] = @[], colors: seq[string] = @[], plain=false,
              simThresh=30, dHdLikeEdit=true, junk=false, blockSkip=20) =
    ## This is a stdin/stdout filter to (re-)highlight unidiff output, e.g.
    ## ``git log -p``, ``hg log -p``, or ``diff -ru A/ B/`` with intra-line
    ## character-by-character deltas.  Highlightble syntax elements are:
    ##   regular, commitHeaderName, commitHeaderValue, commitMessage,
    ##   diffHeader, hunkHeader,
    ##   equal, deleted, deletedEmph, inserted, insertedEmph
    ## Use in ``--color`` is case/style/kebab-insensitive.
    thresh = simThresh
    dhl    = dHdLikeEdit
    junks  = if junk: @[ ' ', '\t' ].toHashSet else: initHashSet[char]()
    bskip  = blockSkip
    colors.textAttrRegisterAliases              # colors => registered aliases
    color.parseColor plain
    for pk in stdinParts():
      case pk # if pt.len > 0: echo $pk, ":\n\t", join(pt, "\n\t")
      of pkCommitHd: (if pt.len > 0: rendCommitHd())
      of pkDiffHd:   rendDiffHd()
      of pkDiffHunk: rendDiffHunk()

  dispatch(hldiff, help = {
             "colors"      : "color aliases; Syntax: name = ATTR1 ATTR2..",
             "color"       : "text attrs for syntax elts; Like lc/etc.",
             "plain"       : "turn off ANSI SGR escape colorization",
             "blockSkip"   : "do not char-by-char block pairs > this",
             "simThresh"   : "do not char-by-char less similar than this",
             "dHdLikeEdit" : "colorize diff header ---/+++ like edits",
             "junk"        : "apply Py difflib junk heuristic intra-line" })
