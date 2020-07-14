" musecnav autoload plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{1
"
if exists('g:autoloaded_musecnav')
  finish
endif
let g:autoloaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

let g:musecnav_version = 104
let g:musecnav_home = expand('<sfile>:p:h:h')
" TODO: what is the actual min version for non-popup use?
let g:musecnav_required_vim_version = '800'

if v:version < g:musecnav_required_vim_version
  echoerr printf('musecnav requires Vim %s+', g:musecnav_required_vim_version)
  finish
endif


" Set higher to navigate subtree files, e.g. asciidoc (others?) allows
" inclusion of files containing subtree beginning at (obviously) a level
" higher than 1. (WIP)
let g:musecnav_minlevel_default = 1

" When enabled, try to continue processing document in the face of certain
" non-conforming formats (ie. ignore offending lines). Otherwise, errors are
" thrown in those situations, aborting processing. (WIP - don't expect any
" miracles!)
let g:musecnav_parse_lenient = 0

" In-menu indication of cursor position 
let g:musecnav_place_mark = '▶'

let g:musecnav_popup_title_idx = 1
let g:musecnav_popup_titles = ['Markup Section Headers', 'Up/Down or 1-99 then <Enter>']



" Functions {{{1

" Script-local Functions {{{2

" Function navigate {{{3
"                                                                Navigate {{{4
" Main entry point for normal use. Primary hotkeys call this.
" If optional first param present and has value....
"
"     1: Reinitialize section tree, ie. force a 'soft' reset
"     2: Reset state, ie. force a 'hard' reset
"     3: Initialize section tree using data structure passed in param 2.
"        Param 2 must be a list with same structure as WalkSections returns.
" other: An exception will be thrown.
"                                                                          }}}
func! musecnav#navigate(...) abort
"    call Dfunc("Navigate(numargs: ".string(a:000).")")

    if &ft !=? 'asciidoc' && &ft !=? 'markdown'
"        call Dret("Navigate - Wrong filetype")
        echohl WarningMsg | echo "Not a valid filetype: " . &ft | echohl None
        return
    endif

    let l:force = 0
    if !exists('b:musecnav_data')
        let b:musecnav_data = {}
    endif

    if a:0 == 1 && (a:1 == 1 || a:1 == 2)
        let l:force = a:1
"        call Decho("Reinitializate force=". l:force)
    elseif a:0 == 2 && a:1 == 3
"        call Decho("Initialize with user-supplied tree: ".string(a:2))
        let b:musecnav_data.sections = a:2
    elseif a:0 != 0
"        call Dret("Navigate - fatal MU10")
        throw "MU10: The specified parameters are not valid!"
    endif

    call s:InitSectionTree(l:force)
    let l:numsects = len(b:musecnav_data.sections)
"    call Decho("After section tree init we have ".l:numsects." sections")
    if l:numsects == 0
        call winrestview(l:view)
        echohl WarningMsg | echo "Unrecognized syntax. Aborting." | echohl None
"        call Dret("Navigate - abort")
        return
    endif

    " If cursor has moved since last menu selection determine what section it
    " currently resides in and make that the new "current section" before
    " building the menu.
    let l:currline = getcurpos()[1]
"    call Decho("last line: ".b:musecnav_data.line ." curr line: ".l:currline)

    if b:musecnav_data.line != l:currline
        if l:currline >= b:musecnav_data.sections[0][0] "sver1
            " Search b/w for a section header. First found is current section.
            " First move cursor down a line to more easily handle the corner
            " case of cursor on first section and very close to doc root.
            "+
            " \%^ = start of file
            let l:headerline = search('\n\n^=*\zs=\s', 'bcsW') "sver1
            "let l:headerline = search('\v%(%^|\n\n)\=*\zs\=\s', 'bcsW') "sver2
            if l:headerline == 0
"                call Dret("Navigate - fatal MU20")
                throw "MU20: No section header found above cursor line"
            elseif l:headerline > l:currline
"                call Dret("Navigate - fatal MU21")
                throw "MU21: Backwards search ended up below cursor line!"
            endif

            let b:musecnav_data.level = getcurpos()[2] - 1
"            call Decho("Cursor moved to level ".b:musecnav_data.level." section starting on line ".l:headerline)
            let b:musecnav_data.line = l:headerline
            " move cursor back to starting point (mark ' set by search())
            call cursor(getpos("''")[1:]) | -
        else "sver1
"            call Decho("Line and level reset to 0")
            let b:musecnav_data.line = 0 "sver1
            let b:musecnav_data.level = 0 "sver1
        endif "sver1
    endif

    " For non-popup menu a continuous draw-menu/get-input/process-input cycle
    " happens here. Loop is exited only upon user entering return alone.
    " For popup menu we break out of the loop immediately after menu is drawn
    " since popups are handled in separate threads and thus there's no reason
    " to maintain this loop. ProcessSelection will be called from the popup
    " callback function.
    while (1)
        " reset the digit entry 'buffer'
        let b:musecnav_select_buf = -1

        let l:choice = s:DrawMenu()
        if !len(l:choice) || l:choice < 0
            break
        endif
        call s:ProcessSelection(-1, l:choice)
    endwhile

"    call Dret("Navigate - normal exit")
endfunc

" Function s:InitSectionTree {{{3

"                                                         InitSectionTree {{{4
" Build the section header hierarchy.
"
" Optional args: 
"   a:1 - for (re)initialize; 1 indicates 'soft' reset, 2 is 'hard' reset
"         Also, 0 is valid but will be treated same as missing param 1.
"   a:2 - starting line number for scan instead of default 1
"                                                                          }}}
func! s:InitSectionTree(...) abort
"    call Dfunc("InitSectionTree(".string(a:000).")")
    let l:force = 0
    let l:lineno = 1
    if a:0 > 0
        let l:force = a:1
        if a:0 > 1
            let l:lineno = a:2
        endif
    endif

    if l:force < 0 || l:force > 2
"        call Dret("InitSectionTree - fail MU22")
        throw "MU41: Illegal value for force param: " . l:force
    endif

"    call Decho("InitSectionTree processed params: ".l:force.", ".l:lineno.")")

    " XXX read first line (lines?) to try to find first header and
    " set minlevel based on its level (usually 0) (asciidoc only?)
    let l:lastlineno = line('$')
    if exists('b:musecnav_data.num_pages') && b:musecnav_data.num_pages != l:lastlineno
        let l:force = max([1, l:force])
    endif
    let b:musecnav_data.num_pages = l:lastlineno

    " Return if tree already built unless 'force'd b/c file contents changed
    " or param flag was set (usually due to Ctrl-F7)
    if exists('b:musecnav_data.sections') && !l:force
"        call Dret("InitSectionTree - tree already built")
        return 0
    endif

    echom "Building section header tree..."
    if !exists("b:musecnav_data.line") || l:force == 2
        let b:musecnav_data.line = 0
        let b:musecnav_data.level = 0
        " Data from last call to menuizetree function
        let b:musecnav_data.last_menu_data = []
"        " Most recent display menu lines. Unused but for a Decho msg or two.
        let b:musecnav_data.last_menu_text = []
    endif

    if l:force != 2
        " before we move the cursor...
        let l:view = winsaveview()
    endif

    call setpos('.', [0, l:lineno, 1])
    let b:musecnav_data.level_map = {}
    if !exists('b:musecnav_minlevel')
        let b:musecnav_minlevel = g:musecnav_minlevel_default 
    endif

    let b:musecnav_data.sections = s:WalkSections(b:musecnav_minlevel)
    let b:musecnav_data.curr_parent = []
    let b:musecnav_data.filename = expand('%')

    if l:force == 2
        " Hard reset positions cursor at start/
        call setpos('.', [0, l:lineno, 1])
    else
        call winrestview(l:view)
    endif

    echom "done"
    redraws
"    call Dret("InitSectionTree - result: ".string(b:musecnav_data.sections))
    return 1
endfunc

" Function s:FindNextSection {{{3

" Find next AsciiDoc(tor) section. See s:FindNextSection()
func! s:NextSection_Asciidoc() abort
"    call Dfunc("NextSect_Asciidoc()")
    let l:patt = '^=*\zs=\s' "sver1
    let l:matchline = search(l:patt, 'W') "sver1
    "let l:equals = repeat('=', b:musecnav_minlevel + 1) "sver2
    "let l:patt = '^'.l:equals.'*\zs=\s' "sver2
    "let l:matchline = search(l:patt, 'Wc') "sver2
    while l:matchline > 0
        let l:matchcol = getcurpos()[2]
        let l:matchlevel = l:matchcol-1
"        call Decho("Match: [".l:matchline.",".l:matchcol.",".l:matchlevel."]")

        " There are at least two valid reasons for having non-blank line
        " before a section header: comment '//' and anchor '[[foo]]'.
        " Just look for [discrete] specifically and skip over those lines.
        let l:linem1 = l:matchline - 1
        if prevnonblank(l:linem1) == l:linem1 && getline(l:linem1) =~? '^\[discrete\]\s*$'
"            call Decho("Match at lineno ".l:matchline." preceded by '[discrete]'...skip")
            call setpos('.', [0, l:matchline + 1, 1])
            let l:matchline = search(l:patt, 'W') "sver1
            "let l:matchline = search(l:patt, 'Wc') "sver2
            continue
        endif

"        call Dret("NextSect_Asciidoc - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, 0]
    endwhile

"    call Dret("NextSect_Asciidoc - no match")
    return [0, 0, 0, 0]
endfunc

"                                                    NextSection_Markdown {{{4
" Find next Markdown section based on these rules:
"
"    # H1
"    ## H2
"    ### H3
"    #### H4
"    ##### H5
"    ###### H6
"    
"    Alternatively, for H1 and H2, an underline-ish style:
"    
"    Alt-H1
"    ======
"    
"    Alt-H2
"    ------
"
" To handle the latter forms the following needs to happen:
" * Set true for fourth element in returned list.
" * Set matchline to the first of the two lines (the content)
" * Upstream adjust any line reading or increment/decrement to
"   compensate for the double line.
" See also s:FindNextSection()
"                                                                          }}}
func! s:NextSection_Markdown() abort
"    call Dfunc("NextSect_Markdown()")
    " Apparently some implementations don't require a space between the 
    " '#'s and the title text.
    let l:patt = '\v%(^#*\zs#%(\s\S|[^#])|^.*\n[-=]{2,}$)'
    let l:matchline = search(l:patt, 'W') "sver1
    "let l:matchline = search(l:patt, 'Wc') "sver2
    while l:matchline > 0
        let l:multiline = 1
        let l:matchcol = getcurpos()[2]

        " level determination
        let l:text = getline(".")
        if l:text =~? '^='
            let l:matchlevel = 1
        elseif l:text =~? '^-'
            let l:matchlevel = 2
        else
            let l:matchlevel = l:matchcol-1
            let l:multiline = 0
        endif
"        call Decho("Match: [".l:matchline.",".l:matchcol.",".l:matchlevel."]")

        let l:linem1 = l:matchline - 1 - l:multiline
        if prevnonblank(l:linem1) == l:linem1 && l:matchlevel > 1
"            call Decho("Non-empty line precedes header (".l:matchline."). SKIP!")
            call setpos('.', [0, l:matchline + 1, 1])
            let l:matchline = search(l:patt, 'W') "sver1
            "let l:matchline = search(l:patt, 'Wc') "sver2
            continue
        endif

"        call Dret("NextSect_Markdown - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:multiline]
    endwhile

"    call Dret("NextSect_Markdown - no match")
    retur [0, 0, 0, 0]
endfunc

"                                                         FindNexSections {{{4
" Starting at current cursor position find the next section header in
" the document and move the cursor to its location. Returns a list containing
" [matchline, matchcol, matchlevel, multi]. The last value, multi, is a
" boolean indicating whether the matched section was of the two-line variety.
" (Currently markdown only.) If no headers are found all values will be 0.
"                                                                          }}}
func! s:FindNextSection() abort
    "call cursor(0, 999) "sver2
    if &ft ==? 'asciidoc'
        return s:NextSection_Asciidoc() "sver1
        "let l:ret = s:NextSection_Asciidoc() "sver2
    elseif &ft ==? 'markdown'
        return s:NextSection_Markdown() "sver1
        "let l:ret = s:NextSection_Markdown() "sver2
    else
        throw "MU11: Unknown or invalid filetype " . &ft
    endif

    "call cursor(0, 1) "sver2
    "return l:ret "sver2
endfunc
"let s:NextSecFuncs = #{ asciidoc: function(s:NextSection_AsciiDoc()) }

" Function s:WalkSections {{{3

"                                                            WalkSections {{{4
" Scan the file beginning at cursor position (usually line 1) and build a tree
" representing the section hierarchy of the document from that point.
"
" Summary of the walk algorithm:
"
" For a section level n, create a list LL
" Loop on search for header pattern :
"   Header at level n found => sibling
"     append to LL a data structure similar to:
"     [lineno, {treekey:line, line:[], subtree: func}]
"     Also, call UpdateLevelMap(a:level, header)
"   Header at level n+1 found => child
"     move cursor up 1 or 2, recurse this func with n+1 and add returned
"     descendant hierarchy to subtree of last added LL elem
"   Header at level < n found => ancestor
"     move cursor up 1 or 2, return LL
"   TODO Found special pattern => terminator (for skipping eof garbage)
"     same as reaching end of document
"   None of the above => error
"     found level is deeper than 1 level down
"                                                                          }}}
func! s:WalkSections(level) abort
"    call Dfunc("WalkSections(".a:level.")")
    let l:levellist = []

    let [l:matchline, l:matchcol, l:matchlevel, l:multi] = s:FindNextSection()

    while l:matchline > 0
        " Exclude ID element following section name if present
        let l:line = substitute(getline(l:matchline),
                    \ '\s*\[\[[^[\]]*\]\]\s\?$', '', '')
"        call Decho("LVL".a:level.": match [lineno, col, line, multi] is [".l:matchline.", ".l:matchcol.", ".l:line.", ".l:multi."]")

        if l:matchlevel != a:level && empty(l:levellist)
            if g:musecnav_parse_lenient
"                call Decho("Skipping header with unexpected level ".l:matchlevel)
            else
"                call Dret("WalkSections - error")
                throw "MU01: Illegal State (bad hierarchy)"
            endif
        endif

        if l:matchlevel == a:level
"            call Decho("LVL".a:level.": match type ** SIBLING **")
            let l:map = {'treekey': l:line, l:line: [], 'subtree': function("s:SubTree")}
            call add(l:levellist, [ l:matchline, l:map ])
            call s:UpdateLevelMap(b:musecnav_data.level_map, a:level, [l:matchline, l:map.treekey])
        elseif l:matchlevel < a:level
"            call Decho("LVL".a:level.": match type ** ANCESTOR **")
            " move cursor back a line so shallower level sees this header
            call setpos('.', [0, l:matchline - 1 - l:multi, 1]) "sver1
"            call Dret("WalkSections - return to ancestor")
            return l:levellist

        elseif l:matchlevel == a:level + 1
"            call Decho("LVL".a:level.": match type ** CHILD **")
            " move cursor back so deeper level sees this header
            call setpos('.', [0, l:matchline - 1 - l:multi, 1]) "sver1
            let l:descendants = s:WalkSections(a:level + 1)
            call l:levellist[-1][1].subtree(l:descendants)
        else
            if g:musecnav_parse_lenient
                echohl WarningMsg | echo "Skipped unexpected level ".l:matchlevel | echohl None
            else
"                call Dret("WalkSections - error")
                throw "MU01: Invalid hierarchy. See line ".l:matchline
            endif
        endif

        let [l:matchline, l:matchcol, l:matchlevel, l:multi] = s:FindNextSection()

"        call Decho("LVL".a:level.": iteration end search() ret:".l:matchline)
    endwhile

"    call Decho("LEVELLIST ON RETURN: <<<".string(l:levellist).">>>")
"    call Dret("WalkSections - returning levellist from LVL".a:level.")")
    return l:levellist
endfunc

" Function s:DrawMenu {{{3

"                                                                DrawMenu {{{4
" Show menu representing current state of navigation either above the command
" line or in a popup window. If not using popups get the user's selection and
" return it.  Otherwise, popups handle user input in a separate thread so this
" will always returns -1 immediately in that case.
"
" The menu's contents depend on what has been selected by the user prior to
" now. If user hasn't selected anything since start/reset we will display
"
"    Document root (level 0)
"      All level 1 section headers
"
" When a (level 1) section is chosen we show
"
"    Document root (level 0)
"      All level 1 section headers
"        Selected section's subtree
"
" When a section header deeper than level 1 is selected we show
"
"    Document root (level 0)
"      Selection parent (at level N-1)
"        All of the selection parent's children (level N)
"          Selected section's subtree (level N+1 and down)
"                                                                          }}}
func! s:DrawMenu() abort
"    call Dfunc("DrawMenu()")

    let l:menudata = s:MenuizeTree(b:musecnav_data.level, b:musecnav_data.line, b:musecnav_data.sections)
"    call Decho("Generated menu data: ".string(l:menudata))

    " build and display the menu
    let l:idx = 0
    let l:rownum = 1
    let l:displaymenu = []
    let l:hirownum = 0

    if !b:musecnav_use_popup
        echom '--------'
    endif
    while l:idx < len(l:menudata)-1
        let l:rowitem = l:menudata[l:idx+1]
"        call Decho("  process rowitem: " . l:rowitem)
        if l:rownum == 1
            let l:rowitem = substitute(l:rowitem, 'ROOT', ' Top of ' . b:musecnav_data.filename . ' (root)', '')
        endif

        if b:musecnav_data.line == l:menudata[l:idx]
            let l:rowitem = substitute(l:rowitem, '\([#=]\)\{2} ', g:musecnav_place_mark . ' ', '')
            let l:hirownum = l:rownum
        else
            let l:rowitem = substitute(l:rowitem, '\([#=]\)\{2} ', '  ', '')
        endif


        let l:rowitem = substitute(l:rowitem, '[#=]', '  ', 'g')
        let l:rowtext = printf("%2s", l:rownum) . ": " . l:rowitem
"        call Decho("    into rowtext: " . l:rowtext)
        call add(l:displaymenu, l:rowtext)

        if !b:musecnav_use_popup
            echom l:rowtext
        endif
        let l:idx += 2
        let l:rownum +=1
    endwhile

    let b:musecnav_data.last_menu_data = l:menudata
    let b:musecnav_data.last_menu_text= l:displaymenu

    let l:choice = -1
"    call Decho("Display menu len: ".len(l:displaymenu)." data: ".string(l:displaymenu))
    let l:title = ' ' .g:musecnav_popup_titles[g:musecnav_popup_title_idx] . ' '
    if b:musecnav_use_popup
        let popid = popup_menu(l:displaymenu, #{
                    \ title: l:title,
                    \ highlight: 'Popup',
                    \ padding: [1,2,1,2],
                    \ filter: 'musecnav#MenuFilter',
                    \ callback: 'musecnav#MenuHandler',
                    \ }) 

        if l:hirownum > 0
            " last chosen section will be highlighted row
            call win_execute(popid, 'call cursor('.l:hirownum.', 1)')
        endif
    else
        echom '--------'
        let l:choice = input("Enter number of section: ")
        while strlen(l:choice) && type(eval(l:choice)) != v:t_number
            echohl WarningMsg | echo "You must enter a valid number" | echohl None
            let l:choice = input("Enter number of section: ")
        endwhile
        redraw
    endif

"    call Dret("DrawMenu")
    return l:choice
endfunc

" Function s:ProcessSelection {{{3

" Given user selection of a menu row determine what section that represents
" and what line number contains it and move the cursor to that line.
" Params:
" id - a popup window id or -1 if we're using non-popup menus
" choice - the user's selection, normally a positive integer
func! s:ProcessSelection(id, choice) abort
"    call Dfunc("ProcessSelection(id:".a:id.", choice:".a:choice.")")
    if a:id == -1
        if b:musecnav_use_popup
"            call Dret("ProcessSelection - exception")
            throw "MU02: Illegal State - non-popup id but popup flag set"
        endif
    endif

    let l:choiceidx = a:choice - 1
    let l:dataidx = l:choiceidx * 2
"    call Decho("User selected ".b:musecnav_data.last_menu_text[l:choiceidx]."(".l:choiceidx." -> data idx: ".l:dataidx.")")
    let l:chosendata = b:musecnav_data.last_menu_data[l:dataidx]
"    call Decho("Menu data (".l:dataidx."): ".l:chosendata)
    let l:chosenitem = b:musecnav_data.last_menu_data[l:dataidx+1]
"    call Decho("Menu choice (".(l:dataidx+1)."): ".l:chosenitem)

    let b:musecnav_data.line = l:chosendata
    let b:musecnav_data.level = max([0, stridx(l:chosenitem, " ") - 1])

"    call Decho("Navigate to line ".b:musecnav_data.line." (level ".b:musecnav_data.level.")")
    exe b:musecnav_data.line
    norm! zz
    " Clear the menu digit buffer
    let b:musecnav_select_buf = -1
"    call Dret("ProcessSelection")
endfunc

" Function s:ProcessMenuDigit {{{3

"                                                        ProcessMenuDigit {{{4
" A bit of a state machine for handling menu row numbers which make it easier
" for the user to jump to a section header when there are many such headers.
" The total number of headers and whether the user is entering the first or
" second (if applicable) digit of their choice determine what happens. (e.g.
" can/should we move to row 2 after the user enters the first digit of 25)
"                                                                          }}}
func! s:ProcessMenuDigit(rows, entry) abort
"    call Dfunc("ProcessMenuDigit(rows:".a:rows.", entry:".a:entry.")")
    let l:ret = -99
    " non-negative number?
    if !(a:entry >= 0 && a:entry <=9)
"    "    call Dret("ProcessMenuDigit - invalid entry ".a:entry)
        return -1
    endif

    " empty 'buffer'?
    if b:musecnav_select_buf < 0
        " first entry non-zero?
        if a:entry > 0
            " can entry only be first 10 rows?
            if a:rows < a:entry * 10
                " yep - final selection
                let b:musecnav_select_buf = -1
            else
                " tenative selection
                let b:musecnav_select_buf = a:entry
            endif

            if a:entry <= a:rows
                let l:ret = a:entry
            else
                let l:ret = -2
            endif

        else " 0 not allowed in first slot, discard
            let l:ret = -3
        endif
    else
        " combine with existing entry
        let l:entry = (10*b:musecnav_select_buf) + a:entry
        if l:entry <= a:rows
            " final selection
            let b:musecnav_select_buf = -1
            let l:ret = l:entry
        else
            " out of range
            let l:ret = -4
        endif
    endif

"    call Dret("ProcessMenuDigit - returning ".l:ret)
    return l:ret
endfunc

" Function s:MenuizeTree {{{3

"                                                             MenuizeTree {{{4
" Build and return a data structure containing everything required to render a
" section header menu.
"
" TODO: Address efficiency. The hierarchy is traversed three times within (two
" recursive descents). 'Tis not ideal. We're talking small trees here and it's
" perfectly performant on my machine but could be an issue on lesser machines.
" Investigate if this is ever shared.
"                                                                          }}}
func! s:MenuizeTree(level, line, tree) abort
"    call Dfunc("MenuizeTree(lvl: ".a:level.", line: ".a:line.", tree: ".string(a:tree).")")

    let b:musecnav_data.curr_parent = []
    if a:line > 0
        let l:subtree = s:DescendToLine(a:line, a:tree, [0, "ROOT"])
    else
        let l:subtree = a:tree
    endif

    let l:sibrangestart = 1
    let l:sibrangeend = line('$')
    " Top of document (ROOT) always first menu item
    let l:levellist = [0, "ROOT"]

    if !empty(b:musecnav_data.curr_parent)
"        call Decho("Process parent ".string(b:musecnav_data.curr_parent))
        " Skip ROOT as we already added it
        if b:musecnav_data.curr_parent[0] != 0
            call extend(l:levellist, b:musecnav_data.curr_parent)
        endif

        " beyond first level we need the parent's range of lines to
        " constrain the siblings that will be displayed
        if a:level > 1
            " range start is line number of the parent
            let l:sibrangestart = b:musecnav_data.curr_parent[0]
            let l:found = 0
"            call Decho("Level is 2+ so find the parent's range")
            " loop through all nodes on parent's level
            for l:parentsibling in b:musecnav_data.level_map[a:level - 1]
"                call Decho("-=> Processing parentsib ".l:parentsibling[1])
                " this is the parent sibling next after the parent and
                " it's line number is our range end (if parent is last in
                " list we already set end of range to last line in file
                if l:found
                    let l:sibrangeend = l:parentsibling[0]
"                    call Decho("DONE - sibling range end is ".l:sibrangeend)
                    break
                endif

                " continue until we find the parent itself
                if l:parentsibling[0] == l:sibrangestart
"                    call Decho("-=> Found the parent")
                    let l:found = 1
                endif
            endfor
        endif
    endif

    let l:sibpre = []
    let l:sibpost = []
    let l:recursed = 0
    let l:targetline = l:subtree[0]

    for l:sibling in b:musecnav_data.level_map[a:level > 0 ? a:level : b:musecnav_minlevel]
        let l:siblineno = l:sibling[0]
        if l:siblineno < l:sibrangestart
            continue
        elseif l:siblineno > l:sibrangeend
            if ! l:recursed
                echohl WarningMsg | echo "sib range end before recurse" | echohl None
            endif
            break
        endif
"        call Decho("Adding to menu lineno: ".l:siblineno)
        call extend(l:levellist, l:sibling)
        if a:level > 0 && l:siblineno == l:targetline
"            call Decho("Recurse and flatten selected subtree with ".len(l:subtree[1].subtree())." children")
            let l:ret = s:FlattenSubTree(l:subtree[1].subtree(), 1, 9)
            call extend(l:levellist, l:ret)
            let l:recursed = 1
        endif
    endfor

"    call Dret("MenuizeTree")
    return l:levellist
endfunc

" Function s:DescendToLine {{{3

"                                                           DescendToLine {{{4
" Navigates a (sub)tree looking for the specified line.
"
" Each level is traversed 'laterally' until we reach the node that we
" determine contains the target line. We make a recursive call, passing the
" subtree attached to that node. This continues until we reach the node with
" line number equal to our target line number.
"
" Params:
"   line   : target line that cause descent to end and this function to return
"   tree   : section header tree or a subtree thereof
"   parent : node that contains the (sub)tree we are currently navigating
"
" Returns: the node with the line number we are targeting
"                                                                          }}}
func! s:DescendToLine(line, tree, parent) abort
"    call Dfunc("DescendToLine(line: ".a:line.", tree: ".string(a:tree)." parent: ".string(a:parent).")")
    let l:levellen = len(a:tree)

    let l:curridx = 0
    for l:sect in a:tree
        if l:sect[0] == a:line
            " We've reached the target level
"            call Decho("Descent reached target. Final tree: ".string(l:sect))
            let b:musecnav_data.curr_parent = a:parent
"            call Dret("DescendToLine - line ".a:line." FOUND, target line reached, currparent: ".string(b:musecnav_data.curr_parent))
            return l:sect
        endif

        " If there is a next elem check whether a:line is between lines of
        " current and next elems. If so then we need to descend
        if l:sect[0] < a:line
            if l:curridx + 1 == l:levellen || a:line < a:tree[l:curridx+1][0]
                let l:parent = [ l:sect[0], l:sect[1].treekey ]
"                call Dret("DescendToLine - recursive descent")
                return s:DescendToLine(a:line, l:sect[1].subtree(), l:parent)
            endif
        endif
        let l:curridx += 1
    endfor

"    call Dret("DescendToLine - ERROR ("line:".a:line.", parent:".a:parent.", tree: ".string(a:tree))
    throw "MUXX: Won't reach this line unless passed non-existent target line"
endfunc

" Function s:FlattenSubTree {{{3

" subtree is list of lists [[l1, ...], [l2, ...]]
func! s:FlattenSubTree(subtree, level, n) abort
"    call Dfunc("FlattenSubTree(subtree, ".a:level.", subtree: ".string(a:subtree))
    if a:level == a:n
"        call Decho("Max depth reached at level ".a:level.". Recursion terminating")
"        call Dret("FlattenSubTree")
        return []
    endif

    "let l:accum = {lineno: -1, header: ""}
    let l:accum = []
    for l:sect in a:subtree
"        call Decho("processing section ".string(l:sect))
        let l:currlineno = l:sect[0]
        let l:treekey = l:sect[1].treekey
"        call Decho("Elem lineno: ".l:currlineno.", sect: ".l:treekey)
        call extend(l:accum, [l:currlineno, l:treekey])
        let l:nested = l:sect[1].subtree()
        if ! empty(l:nested)
"            call Decho("FlattenSubTree - Recurse on subtree with ".len(l:nested)." children")
            call extend(l:accum, s:FlattenSubTree(l:nested, a:level+1, a:n))
        endif
    endfor

"    call Decho("LVL".a:level." returning : <<<".string(l:accum).">>>")
"    call Dret("FlattenSubTree")
    return l:accum
endfunc

" Function s:Subtree {{{3

" Returns the embedded list whose key is the value stored in 'treekey'
" If a param is given and it is a list it is first concatenated (extend()) to
" the existing list. Non-lists are added (add()) to the list.
func! s:SubTree(...) dict
    if a:0 == 0
        return self[self.treekey]
    endif

    if type(a:1) == v:t_list
        return extend(self[self.treekey], a:1)
    else
        return add(self[self.treekey], a:1)
    endif
endf

" Function s:UpdateLevelMap {{{3

" The level map is for looking up all the sections at a specified level.
" K->V where K is level number, V is list of [lineno, { lineno->hierarchy }]
" Currently used while collecting data needed to construct menu. Ie. to get a
" section's siblings or siblings of a section parent.
func! s:UpdateLevelMap(map, key, value)
"    call Dfunc("UpdateLevelMap(key: ".a:key.", val: ".string(a:value).", map: ".string(a:map).")")
    if ! has_key(a:map, a:key)
        let a:map[a:key] = []
    endif
    call add(a:map[a:key], a:value)
"    call Dret("UpdateLevelMap - new map: ".string(a:map))
endfunc

" Function s:DebugLog {{{3
"
func! s:DebugLog(...) abort
    if !empty(g:musecnav_log_file)
        call writefile([json_encode(a:000)], g:musecnav_log_file, 'a')
    endif
endfunc

" Function s:function {{{3

" Returns a funcref to the script-local function with given name
function! s:getfuncref(name)
    "return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
    return function(s:resolvefname(a:name))
endfunction
"
" Return resolved name of script-local function with given unresolved name
function! s:resolvefname(unresolved)
    return substitute(a:unresolved,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),'')
endfunction

" Global Functions {{{2

" Popup Functions {{{3

" As an enhancement to popup menus we number menu elements (section headers)
" and allow the user to enter one of those numbers in order to move the
" selection to that line.  (For large docs with many sections Up/Down just
" doesn't cut it.)
func! musecnav#MenuFilter(id, key) abort
    let l:last_key = getwinvar(a:id, 'last_key')
    call setwinvar(a:id, 'last_key', a:key)

    if match(a:key, '^\d$') == 0
        let l:rownum = s:ProcessMenuDigit(popup_getpos(a:id).core_height, a:key)
        if l:rownum > 0
            call win_execute(a:id, 'call cursor('.l:rownum.', 1)')
        endif
        return 1
    elseif match(a:key, '\r') >= 0 && empty(l:last_key)
        " Exit when Enter hit twice in a row
        call popup_close(a:id)
        echohl WarningMsg | echo "Exiting due to Enter after submission" | echohl None
        return 1
    endif

    " No shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
endfunc

" Menus can't callback into script-local code so this must be a global
" function. This will spawn an updated menu popup unless result param is -1.
func! musecnav#MenuHandler(id, result) abort
"    call Dfunc("MenuHandler(id:".a:id.", result:".a:result.")")
    if a:result < 1
        " FYI -1 indicates user canceled menu while 0 indicates popup_close()
        " was called without the 'result' param. Latter shouldn't happen here.
"        call Dret("MenuHandler - exit input loop")
        return
    endif
    call s:ProcessSelection(a:id, a:result)
    call s:DrawMenu()
"    call Dret("MenuHandler")
endfunc

" Utility Functions {{{3
"
func! musecnav#InfoDump()
    if !exists('b:musecnav_data')
        echo printf("No data for this buffer!")
        return
    elseif empty(b:musecnav_data)
        echo printf("Main dictionary not currently populated")
        return
    endif

    echo printf("Level: %s, ", b:musecnav_data.level)
    echo printf("Line: %s, ", b:musecnav_data.line)
    echo printf("Curr Parent: %s\n\n", b:musecnav_data.curr_parent)
    echo printf("Last Menu: %s\n\n", b:musecnav_data.last_menu_text
    echo printf("Level Map: %s\n\n", b:musecnav_data.level_map)
    echo printf("Sections: %s\n\n", b:musecnav_data.sections)
    echo printf("version: %s\n\n", g:musecnav_vers)
endfunc

func! musecnav#DataReset()
    let b:musecnav_data = {}
endfunc

" Currently using this as a trigger to source this file. Called from autoload
" file for musecnav when a markup file type is indicated.
func! musecnav#activate()
    return
endfunc

let &cpoptions = s:save_cpo
unlet s:save_cpo

