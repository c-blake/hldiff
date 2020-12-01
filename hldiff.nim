import std/[strutils, os, sets, tables], hldiffpkg/edits,
       cligen/[parseopt3, osUt, textUt, humanUt]
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
  junkDf = false                # Use Python difflib-like junk heuristic
  bskip  = 20                   # Do not char-by-char block pairs > lim*lim

proc emit*(a: varargs[string, `$`]) {.inline.} = stdout.urite(a)

proc parseColor(color: seq[string], plain=false) =
  let plain = plain or existsEnv("NO_COLOR")
  for spec in color:
    let cols = spec.strip.splitWhitespace(1)
    if cols.len < 2:
      raise newException(ValueError, "bad color line: \"" & spec & "\"")
    let key = cols[0].optionNormalize
    if key notin highlights:
      raise newException(ValueError, "unknown color key: \"" & spec & "\"")
    highlights[key] = cols[1]
  for k, v in highlights:
    attr[k] = textAttrOn(v.split, plain)
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

proc rendCommitHd(lines: seq[string]) =
  for ln in lines:
    if ln.startsWith("commit ") or ln.isHeader:
      let ix = ln.find(Whitespace)
      emit hlCommitHdNm , ln[0..<ix], hlReg
      emit hlCommitHdVal, ln[ix..^1], hlReg, '\n'
    else:
      emit hlCommitMsg, ln, hlReg, '\n'

proc rendDiffHd(lines: seq[string]) =
  for ln in lines:
    if   dhl and ln.len > 0 and ln[0] == '-': emit hlDel, ln, hlReg, '\n'
    elif dhl and ln.len > 0 and ln[0] == '+': emit hlIns, ln, hlReg, '\n'
    else: emit hlDiffHdr, ln, hlReg, '\n'

const charJunk  = @[ ' ', '\t' ].toHashSet
const junkEmpty = initHashSet[char]()
proc rendSub(group: seq[string], nDel: int, th=thresh, junk=junkDf, lim=bskip) =
  if nDel * (group.len - nDel) > lim * lim:       # CHAR-BY-CHAR slow & useless
    for i in 0 ..< nDel: emit hlDel, group[i], hlReg, '\n' #..for big blockPairs
    for j in nDel ..< group.len: emit hlIns, group[j], hlReg, '\n'
    return
  type Pair = tuple[i, sim: int; ss: seq[Same]]
  var pairs = initTable[int, Pair](tables.rightSize(nDel))
  var sims  = initTable[int, tuple[sim, j: int]](tables.rightSize(nDel))
  for j in nDel ..< group.len:                    # FIRST PAIR "CLOSE" LINES
    let gJ = group[j][1..^1]
    var c = initCmper("", gJ, if junk: charJunk else: junkEmpty)
    var pairJ: Pair
    for i in 0 ..< nDel:                          # pairJ -> most similar i
      let gI  = group[i][1..^1]
      let sMx = gI.len + gJ.len                   # check upper bounds first
      if min(gI.len, gJ.len)*100 > th * sMx and similUB1(gI, gJ)*100 > th * sMx:
        let ss  = c.sames(gI, gJ)                 # ss = CHAR-BY-CHAR DIFF
        let sim = ss.similarity * 10_000 div sMx
        if sim > 100 * th and sim > pairJ.sim:
          pairJ.i   = i
          pairJ.sim = sim
          pairJ.ss  = ss
    if pairJ.sim > sims.getOrDefault(pairJ.i, (0, 0)).sim:
      sims[pairJ.i] = (pairJ.sim, j)              # Retain only max sim @given i
      pairs[j] = move(pairJ)
  for i in 0 ..< nDel:
    if i in sims and sims[i].j in pairs:          # CHAR-BY-CHAR DIFF => HILITE
      let j = sims[i].j; let gI = group[i][1..^1] # let gJ = group[j][1..^1]
      emit hlDel, '-', hlReg
      for ed in edits(pairs[j].ss):
        case ed.ek
        of ekEql       : emit hlDel    , gI[ed.s], hlReg
        of ekDel, ekSub: emit hlDelEmph, gI[ed.s], hlReg
        else: discard
      emit '\n'
    else:
      emit hlDel, group[i], hlReg, '\n'
  for j in nDel ..< group.len:
    if j in pairs:                                # CHAR-BY-CHAR DIFF => HILITE
      let p = pairs[j]; let gJ = group[j][1..^1]
      emit hlIns, '+', hlReg
      for ed in edits(p.ss):
        case ed.ek
        of ekEql       : emit hlIns    , gJ[ed.t], hlReg
        of ekIns, ekSub: emit hlInsEmph, gJ[ed.t], hlReg
        else: discard
      emit '\n'
    else:
      emit hlIns, group[j], hlReg, '\n'

proc render(group: seq[string], ek: EdKind, nDel: int) {.inline.} =
  if group.len < 1: return
  case ek
  of ekEql: (for ln in group: emit hlEql, ln, hlReg, '\n')
  of ekDel: (for ln in group: emit hlDel, ln, hlReg, '\n')
  of ekIns: (for ln in group: emit hlIns, ln, hlReg, '\n')
  of ekSub: group.rendSub(nDel)

type PartKind* = enum pkCommitHd, pkDiffHd, pkDiffHunk

iterator parts*(lines: iterator():string): tuple[pk:PartKind, lns:seq[string]] =
  ## A fast, one-pass iterator to classify input lines into blocks.  Note that
  ## an empty ``pkCommitHd`` occurs @start|end of ``diff -ru``|mercurial inputs.
  var res: seq[string]
  var state = pkCommitHd
  for raw in lines():
    let line = raw.stripSGR
    if state == pkDiffHd and line.startsWith("+++"):
      res.add line
      yield (state, res)
      res.setLen 0
      state = pkDiffHunk
    elif state!=pkDiffHd and(line.startsWith("diff") or line.startsWith("---")):
      yield (state, res)                # yield whatever we have & switch
      res = @[ line ]
      state = pkDiffHd                  #..to accumulating diff header
    elif res.len > 0 and line.startsWith("@@"):
      yield (state, res)                # New hunk; yield & reset
      res = @[ line ]
    elif line.len == 0:                 # one+ pure blanks re-enters commit hdr
      yield (state, res)
      res = @[ line ]
      state = pkCommitHd
    else:                               # non-blank; accumulate
      res.add line
  yield (state, res)

const sb = { ' ', '\\' }  # Mercurial emits "^\ No newline at end of file"
proc rendDiffHunk(lines: seq[string]) =
  ## Fancy intra-line diff highlighting of edit hunks.
  emit hlHunkHdr, lines[0], hlReg, '\n' # render "@@" hunk header line.
  var state = ekEql
  var group: seq[string]
  var nDel = 0
  for i in 1 ..< lines.len:
    if lines[i].len < 1:
      raise newException(ValueError, "malformatted diff")
    let c = lines[i][0]
    if (state == ekEql and c in sb) or (state == ekDel and c == '-') or
       (c == '+' and state in {ekIns, ekSub}):  # any->self: accumulate
      group.add lines[i]
    elif c in sb:                               # any->eql
      group.render state, nDel; nDel = 0
      group = @[ lines[i] ]
      state = ekEql
    elif state == ekEql and (c=='-' or c=='+'): # eql->(del|ins)
      group.render state, nDel; nDel = 0
      group = @[ lines[i] ]
      state = if c == '-': ekDel else: ekIns
    elif state == ekDel and c == '+':           # del->sub
      nDel = group.len
      group.add lines[i]
      state = ekSub
  group.render state, nDel

when isMainModule:
  import cligen, cligen/osUt; include cligen/mergeCfgEnv

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
    junkDf = junk
    bskip  = blockSkip
    colors.textAttrRegisterAliases              # colors => registered aliases
    color.parseColor
    for (pk, lns) in parts(fileStrings("/dev/stdin", '\n')):
      case pk # if lns.len > 0: echo $pk, ":\n\t", join(lns, "\n\t")
      of pkCommitHd: (if lns.len > 0: lns.rendCommitHd)
      of pkDiffHd:   lns.rendDiffHd
      of pkDiffHunk: lns.rendDiffHunk

  dispatch(hldiff, cmdName="hldiff", help = { # cmdName needed for right cf file
             "colors"      : "color aliases; Syntax: name = ATTR1 ATTR2..",
             "color"       : "text attrs for syntax elts; Like lc/etc.",
             "plain"       : "turn off ANSI SGR escape colorization",
             "blockSkip"   : "do not char-by-char block pairs > this",
             "simThresh"   : "do not char-by-char less similar than this",
             "dHdLikeEdit" : "colorize diff header ---/+++ like edits",
             "junk"        : "apply Py difflib junk heuristic intra-line" })
