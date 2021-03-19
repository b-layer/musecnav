" musecnav autoload plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{1

if exists('g:autoloaded_musecnav')
  finish
endif
let g:autoloaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

let g:musecnav_version = 108
" TODO: what is the actual min version for non-popup use?
let g:musecnav_required_vim_version = '802'

if v:version < g:musecnav_required_vim_version
  echoerr printf('musecnav requires Vim %s+', g:musecnav_required_vim_version)
  finish
endif

" Functions {{{1

" Script-local Functions {{{2

" Function s:InitHeaderInfo {{{3
" Process title if it exists. Set a document name. Find first section header.
func! s:InitHeaderInfo()
"    call Dfunc("InitHeaderInfo()")
    let b:musecnav_hasdocheader = 0
    let b:musecnav_docname = expand('%')

    if &ft ==? 'asciidoc'
        " If a level 0 header is found that's doc header;
        " note attributes then look for section header.
        " If it's other than level 0 then it's a section
        " header and there's no doc header.
        "
"        call Decho("Searching for AD doc header/title")
        " [line number, header level, is multiline?, title]
        let l:firstheader = musecnav#FindFirstHeader()
        if len(l:firstheader) == 0
            throw "MU16: Can't find opening document or section header"
        endif
        let l:lvl = l:firstheader[1]
        if l:lvl == 0
            " It's a doc header
            let b:musecnav_docheader = l:firstheader
"            call Decho("AD first (doc) header info: " . string(b:musecnav_docheader))
            if b:musecnav_docheader[2]
                throw "MU17: Not currently supporting multi-line headers"
            endif
            let b:musecnav_hasdocheader = 1
            let b:musecnav_docname = b:musecnav_docheader[3]
            " HAS to be one or it's invalid
            let b:musecnav_firstseclevel = 1
        else
            " we're done
            let b:musecnav_firstsecheader = l:firstheader
            let b:musecnav_firstseclevel = l:lvl
"            call Decho("AD first (sec) header info: " . string(b:musecnav_firstsecheader))
            return
        endif
    else
        let b:musecnav_firstseclevel = 1
    endif

    let l:curpos = getcurpos()
    let b:musecnav_firstsecheader = musecnav#FindFirstSecHead()
    call setpos('.', l:curpos)

"    call Decho("Doc's first header: " . string(b:musecnav_firstsecheader))
    if len(b:musecnav_firstsecheader)
        if b:musecnav_firstseclevel != b:musecnav_firstsecheader[1]
            throw "MU18: With doc header first section MUST be level 1"
        endif
    elseif b:musecnav_hasdocheader
        throw "MU19: Didn't find an opening section header!"
    endif
"    call Dret("InitHeaderInfo - normal exit")
endfunction

" Function s:Navigate {{{3
"                                                                Navigate {{{4
" Generates section header hierarchy if necessary then displays the navigation
" menu.
"                                                                          }}}
func! s:Navigate() abort
"    call Dfunc("Navigate()")

    call s:InitSectionTree()
    let l:numsects = len(b:musecnav_data.sections)
"    call Decho("After section tree init we have ".l:numsects." sections")
    if l:numsects == 0
        echohl WarningMsg | echo "Unrecognized syntax. Aborting." | echohl None
"        call Dret("Navigate - abort")
        return
    endif

    " If cursor has moved since last menu selection determine what section it
    " currently resides in and make that the new "current section" before
    " building the menu.
    let l:currline = getcurpos()[1]
"    call Decho("last line: ".b:musecnav_data.selheadline ." curr line: ".l:currline)

    if b:musecnav_data.selheadline != l:currline
        " Search b/w for a section header. First found is current section.
        " First move cursor down a line to more easily handle the corner
        " case of cursor on first section and very close to doc root.
        "+
        " \%^ = start of file
        call s:CurrLineInBkwdSearch()
        let [l:headerline, _, l:level, _] = s:FindNextSection(1, 1)

        if l:headerline == 0
"            call Dret("Navigate - fatal MU20")
            throw "MU20: No section header found above cursor line"
        elseif l:headerline > l:currline
"            call Dret("Navigate - fatal MU21")
            throw "MU21: Backwards search ended up below cursor line!"
        endif

        let b:musecnav_data.level = l:level
"        call Decho("Cursor moved to level ".b:musecnav_data.level." section starting on line ".l:headerline)
        let b:musecnav_data.selheadline = l:headerline

        " move cursor back to starting point (mark ' set by search())
        call cursor(getpos("''")[1:])  " | -
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
" Optional arg:
"   a:1 - starting line number for scan instead of default 1
"                                                                          }}}
func! s:InitSectionTree(...) abort
"    call Dfunc("InitSectionTree(".string(a:000).")")
    let l:lineno = 1
    if a:0 > 0
        let l:lineno = a:1
    endif

    let l:lastlineno = line('$')
    let l:rebuild = 0
    if exists('b:musecnav_data.buflines') && b:musecnav_data.buflines != l:lastlineno
        let l:rebuild = 1
        "if index(split(g:musecnav_refresh_checks, ','), 'buflines') >= 0
        "    let l:rebuild = 1
        "    let b:musecnav_data.buflines = l:lastlineno
        "else
        "    echohl WarningMsg
        "    echo "Number of buffer lines changed. Navigation may be affected."
        "    echohl None
        "endif
    endif
    let b:musecnav_data.buflines = l:lastlineno

    " Return if tree already built unless forced b/c file contents changed
    " or param flag was set (usually due to Ctrl-F7)
    if exists('b:musecnav_data.sections') && !l:rebuild
"        call Dret("InitSectionTree - tree already built")
        return 0
    endif

    echom "Building section header tree..."
    if !exists("b:musecnav_data.selheadline")
        let b:musecnav_data.selheadline = 0
        let b:musecnav_data.level = 0
        " Data from last call to menuizetree function
        let b:musecnav_data.last_menu_data = []
"        " Most recent display menu lines. Unused but for a Decho msg or two.
        let b:musecnav_data.last_menu_text = []
    endif

    " before we move the cursor...
    let l:view = winsaveview()

    call setpos('.', [0, l:lineno, 1])
    let b:musecnav_data.level_map = {}
    let b:musecnav_data.ancestor_map = {}

    let b:musecnav_data.sections = s:WalkSections(b:musecnav_firstseclevel, "")
    let b:musecnav_data.currparent = []
    let b:musecnav_data.filename = expand('%')

    call winrestview(l:view)

    echom "done"
    redraws
"    call Dret("InitSectionTree - result: ".string(b:musecnav_data.sections))
    return 1
endfunc

" Function s:FindNextSection {{{3

" Find next AsciiDoc(tor) section. See s:FindNextSection()
" For reference here are the patterns used by the AD syntax file:
" syn match /^[^. +/].*[^.]\n[-=~^+]\{2,}$/  two line title
"    title underline is above starting after \n
" syn match /^=\{1,5}\s\+\S.*$/  one line title
func! s:NextSection_Asciidoc(bkwd, withroot) abort
"    call Dfunc("NextSect_Asciidoc(".a:bkwd.")")

    let l:flags = 'Wcs'
    if a:bkwd
        let l:flags .= 'b'
    endif

    let l:wildcard = '\+'
    if a:withroot
        let l:wildcard = '*'
    endif

    " Allows illegal markers like ===# and ##= .. I can live with that '
    let l:markers = '\('.repeat('=', b:musecnav_firstseclevel).l:wildcard.'\|'.repeat('#', b:musecnav_firstseclevel).l:wildcard.'\)'
    let l:patt = '^' . l:markers . '\zs' . b:adheadmark . '\s\+\S'
"    call Decho("With first sec level " . b:musecnav_firstseclevel . " patt is " . l:patt)

    let l:matchline = search(l:patt, l:flags)
    while l:matchline > 0
        let l:matchcol = getcurpos()[2]
        let l:matchlevel = l:matchcol - 1
"        call Decho("Match: [".l:matchline.",".l:matchcol.",".l:matchlevel."]")

        " There are multiple valid reasons for having non-blank line
        " before a section header, e.g. comment '//', anchor '[[foo]]'.
        " Look for [discrete] specifically and assume the rest are legit
        let l:linem1 = l:matchline - 1
        if prevnonblank(l:linem1) == l:linem1 && getline(l:linem1) =~? '^\[discrete\]\s*$'
"            call Decho("Match at lineno ".l:matchline." preceded by '[discrete]'...skip")
            call setpos('.', [0, l:matchline + 1, 1])
            let l:matchline = search(l:patt, 'Wc')
            continue
        endif

        let l:ret = [l:matchline, l:matchcol, l:matchlevel, 0]
"        call Dret("NextSect_Asciidoc - ret " . string(l:ret))
        return l:ret
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
func! s:NextSection_Markdown(bkwd) abort
"    call Dfunc("NextSect_Markdown(".a:bkwd.")")

    let l:flags = 'Wc'
    if a:bkwd
        let l:flags .= 'b'
    endif

    " Apparently some implementations don't require a space between the
    " '#'s and the title text. We're not allowing that at this time.
    " Save this pattern in the event we support multi-line headers
    "let l:patt = '\v%(^#*\zs#%(\s\S|[^#])|^.*\n[-=]{2,}$)'
    let l:patt = '\v^#*\zs#\s+\S'
    let l:matchline = search(l:patt, l:flags)
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
            let l:matchlevel = l:matchcol " - b:musecnav_firstseclevel
            let l:multiline = 0
        endif
"        call Decho("Match: [".l:matchline.",".l:matchcol.",".l:matchlevel."]")
        if l:multiline
            throw "MU17: Not currently supporting multi-line headers"
        endif

        let l:linem1 = l:matchline - 1 - l:multiline
        if prevnonblank(l:linem1) == l:linem1 && l:matchlevel > 1
"            call Decho("Non-empty line precedes header (".l:matchline."). SKIP!")
            call setpos('.', [0, l:matchline + 1, 1])
            let l:matchline = search(l:patt, 'Wc')
            continue
        endif

"        call Dret("NextSect_Markdown - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:multiline]
    endwhile

"    call Dret("NextSect_Markdown - no match")
    return [0, 0, 0, 0]
endfunc

"                                                         FindNexSections {{{4
" Starting at current cursor position find the next section header in
" the document and move the cursor to its location. Returns a list containing
" [matchline, matchcol, matchlevel, multi]. The last value, multi, is a
" boolean indicating whether the matched section was of the two-line variety.
" (Currently markdown only.) If no headers are found all values will be 0.
"                                                                          }}}
func! s:FindNextSection(...) abort
    let l:bkwd = 0
    if a:0 && a:1
        let l:bkwd = 1
    endif
    let l:withroot = 0
    if a:0 == 2 && a:2
        let l:withroot = 1
    endif


    if &ft ==? 'asciidoc'
        let l:ret = s:NextSection_Asciidoc(l:bkwd, l:withroot)
    elseif &ft ==? 'markdown'
        let l:ret = s:NextSection_Markdown(l:bkwd)
    else
        throw "MU21: Unknown or invalid filetype " . &ft
    endif
    call cursor(0, 999)
    return l:ret
endfunc
"let s:NextSecFuncs = #{ asciidoc: function(s:NextSection_AsciiDoc()) }

" Just modifies the cursor column on current line so the next search()
" that occurs will see the entire line.
" Param 'dir' should be set to 1 if next search backward search. Otherwise,
" set it to 0 for forward search.
func! s:CurrLineInSearch(bkwd) abort
    if a:bkwd == 0
        call cursor(0, 1)
    elseif a:bkwd == 1
        call cursor(0, 999)
    else
        throw "MU13: Invalid value for param 'bkwd'"
    endif
endfunc

" Ensures current cursor line will be included in next forward search
func! s:CurrLineInFwdSearch() abort
    call s:CurrLineInSearch(0)
endfunc

" Ensures current cursor line will be included in next backward search
func! s:CurrLineInBkwdSearch() abort
    call s:CurrLineInSearch(1)
endfunc

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
"     Also, update level and ancestor maps
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
" Param 1: level number of the topmost section header
" Param 2: parent ID (name) or empty string if level is topmost
func! s:WalkSections(level, parent) abort
"    call Dfunc("WalkSections(".a:level.")")
    let l:levellist = []

    let [l:matchline, l:matchcol, l:matchlevel, l:multi] = s:FindNextSection()
"        call Decho("LVL".a:level." FINDNEXT: [lineno, col, level, multi] is [".l:matchline.", ".l:matchcol.", ".l:matchlevel.", ".l:multi."]")

    while l:matchline > 0
        " Exclude ID element following section name if present
        let l:line = substitute(getline(l:matchline),
                    \ '\s*\[\[[^[\]]*\]\]\s\?$', '', '')

"        call Decho("Matched line: " . l:line)
        if l:matchlevel != a:level && empty(l:levellist)
            if g:musecnav_parse_lenient
"                call Decho("Skipping header with unexpected level ".l:matchlevel)
            else
"                call Dret("WalkSections - error 91")
                throw "MU91: Illegal State (bad hierarchy)"
            endif
        endif

        if l:matchlevel == a:level
"            call Decho("LVL".a:level.": match type ** SIBLING **")
            let l:map = {'treekey': l:line, l:line: [], 'subtree': function("s:SubTree")}
            call add(l:levellist, [ l:matchline, l:map ])
            call s:UpdateLevelMap(b:musecnav_data.level_map, a:level, [l:matchline, l:map.treekey])
            call s:UpdateAncestorMap(b:musecnav_data.ancestor_map, l:matchline, [l:line, a:parent])
        elseif l:matchlevel < a:level
"            call Decho("LVL".a:level.": match type ** ANCESTOR **")
            call s:CurrLineInFwdSearch()
"            call Dret("WalkSections - return to ancestor")
            return l:levellist

        elseif l:matchlevel == a:level + 1
"            call Decho("LVL".a:level.": match type ** CHILD **")
            call s:CurrLineInFwdSearch()
            let l:descendants = s:WalkSections(a:level + 1, l:levellist[-1][0])
            call l:levellist[-1][1].subtree(l:descendants)
        else
            if g:musecnav_parse_lenient
                echohl WarningMsg | echo "Skipped unexpected level ".l:matchlevel | echohl None
            else
"                call Dret("WalkSections - error 92")
                throw "MU92: Invalid hierarchy. See line ".l:matchline
            endif
        endif

        let [l:matchline, l:matchcol, l:matchlevel, l:multi] = s:FindNextSection()

"        call Decho("LVL".a:level.": iteration end search() ret:".l:matchline)
    endwhile

"    call Decho("LEVELLIST ON RETURN: <<<".string(l:levellist).">>>")
"    call Dret("WalkSections - returning levellist from LVL".a:level.")")
    return l:levellist
endfunc

" Function s:GetSectionAncestry {{{3

"                                                      GetSectionAncestry {{{4
" Build a list of section headers in hierarchical order starting at the top
" section (root) and ending at the section whose start is at the line
" specified in param 1. In other words a complete ancestry for the given
" section.
"
" Param 1: line number of a section header
" Param 2: a recursively traversable ancestor map (dictionary with line number
"          keys and list values: [section header, section parent line num]
" Returns list of lists. Inner list form: [section start line, section header]
"                                                                          }}}
function! s:GetSectionAncestry(line, map)
    let l:res = []
    let l:key = a:line
    while a:map->has_key(l:key)
        let l:val = a:map[l:key]
        call add(l:res, [l:key, l:val[0]])
        let l:key = l:val[1]
    endwhile

    if l:res->empty()
        return l:res
    endif

    return l:res->reverse()
endfunction

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
"      Ancestors between root and selection parent (levels 1 to N-2)
"        Selection parent (at level N-1)
"          All of the selection parent's children (level N)
"            Selected section's subtree (level N+1 and down)
"                                                                          }}}
func! s:DrawMenu() abort
"    call Dfunc("DrawMenu()")

    let l:menudata = s:MenuizeTree(b:musecnav_data.level, b:musecnav_data.selheadline, b:musecnav_data.sections)
"    call Decho("Generated menu data: ".string(l:menudata))
    let l:currlevel = b:musecnav_data.level
    let l:idx = 0

    " build and display the menu
    let l:rownum = 1
    let l:displaymenu = []
    let l:hirownum = 0

    if !b:musecnav_use_popup
        echom '--------'
    endif

    while l:idx < len(l:menudata) - 1
        let l:rowitem = l:menudata[l:idx+1]
"        call Decho("  process rowitem: " . l:rowitem)
        if l:rownum == 1 && &ft ==? 'asciidoc'
            let l:rowitem = substitute(l:rowitem, 'ROOT', ' Top of ' . b:musecnav_docname . ' (root)', '')
        endif

        let l:pad = '   '
        if b:musecnav_data.selheadline == l:menudata[l:idx]
            let l:pad = ' ' . g:musecnav_place_mark . ' '
            let l:hirownum = l:rownum
        endif
        let l:rowitem = substitute(l:rowitem, '\([#=]\)\{2} ', l:pad, '')

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
    if exists("b:musecnav_batch")
        echom '--------'
    elseif b:musecnav_use_popup
        let popid = popup_menu(l:displaymenu, #{
                    \ title: l:title,
                    \ resize: 1,
                    \ close: 'button',
                    \ maxheight: 60,
                    \ scrollbar: 1,
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
"            call Dret("ProcessSelection - error 93")
            throw "MU93: Illegal State - non-popup id but popup flag set"
        endif
    endif

    let l:choiceidx = a:choice - 1
    let l:dataidx = l:choiceidx * 2
"    call Decho("User selected ".b:musecnav_data.last_menu_text[l:choiceidx]."(".l:choiceidx." -> data idx: ".l:dataidx.")")
    let l:chosendata = b:musecnav_data.last_menu_data[l:dataidx]
"    call Decho("Menu data (".l:dataidx."): ".l:chosendata)
    let l:chosenitem = b:musecnav_data.last_menu_data[l:dataidx+1]
"    call Decho("Menu choice (".(l:dataidx+1)."): ".l:chosenitem)

    let b:musecnav_data.selheadline = l:chosendata
    let b:musecnav_data.level = max([0, stridx(l:chosenitem, " ") - b:leveladj])

"    call Decho("Navigate to line ".b:musecnav_data.selheadline." (level ".b:musecnav_data.level.")")
    exe b:musecnav_data.selheadline
    norm! zz
    " Clear the menu digit buffer
    let b:musecnav_select_buf = -1
"    call Dret("ProcessSelection")
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
"
" Param 1: current level
" Param 2: number of first line of section that contains cursor
" Param 3: section/sub-section data to be menuized
"                                                                          }}}
func! s:MenuizeTree(level, secline, tree) abort
"    call Dfunc("MenuizeTree(lvl: ".a:level.", line: ".a:secline.", tree: ".string(a:tree).")")

    let b:musecnav_data.currparent = []
    if a:level > 0
        let l:subtree = s:DescendToLine(a:secline, a:tree, [0, "ROOT"])
    else
        let l:subtree = a:tree
    endif

    let l:sibrangestart = 1
    let l:sibrangeend = line('$')
    if &ft ==? 'asciidoc' && b:musecnav_hasdocheader
        " If there's a document header it'll be first menu item (ROOT)
        let l:levellist = [0, "ROOT"]
    else
        let l:levellist = []
    endif

    if !empty(b:musecnav_data.currparent)
"        call Decho("Process parent ".string(b:musecnav_data.currparent))
        " Insert parent and all its ancestors except ROOT (already in list)
        if b:musecnav_data.currparent[0] != 0
            " Build ancestor list of current header and join with menudata
            let l:ancestors = s:GetSectionAncestry(b:musecnav_data.currparent[0], b:musecnav_data.ancestor_map)
            for ancestor in l:ancestors
                call extend(l:levellist, ancestor)
            endfor
        endif

        " beyond first level we need the parent's range of lines to
        " constrain the siblings that will be displayed
        if a:level > b:musecnav_firstseclevel
            " range start is line number of the parent
            let l:sibrangestart = b:musecnav_data.currparent[0]
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

    for l:sibling in b:musecnav_data.level_map[a:level > 0 ? a:level : 1]
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
"   parent : tree's parent represented as [linenum, treekey]
"            Example: [327, '=== Things to Do']
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
            let b:musecnav_data.currparent = a:parent
"            call Dret("DescendToLine - line ".a:line." FOUND, target line reached, currparent: ".string(b:musecnav_data.currparent))
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

"    call Dret("DescendToLine - ERROR (line:".a:line.", parent:".string(a:parent).", tree: ".string(a:tree))
    throw "MUXX: Won't reach this line unless passed non-existent target line"
endfunc

" Function s:FlattenSubTree {{{3

" subtree is list of lists [[l1, ...], [l2, ...]]
func! s:FlattenSubTree(subtree, level, n) abort
"    call Dfunc("FlattenSubTree(level: ".a:level.", subtree: ".string(a:subtree))
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
"
func! s:UpdateLevelMap(map, key, value)
"    call Dfunc("UpdateLevelMap(key: ".a:key.", val: ".string(a:value).", map: ".string(a:map).")")
    if ! has_key(a:map, a:key)
        let a:map[a:key] = []
    endif
    call add(a:map[a:key], a:value)
"    call Dret("UpdateLevelMap - new map: ".string(a:map))
endfunc

" Function s:UpdateAncestorMap {{{3

" The level map is for looking up all the parent of any given section. By
" recursively looking up parents we can determine all ancestors of a section.
" K->V, K is section ID and V is list of [section name, section parent ID]
"
" Param 1: the ancestor map
" Param 2: section line number
" Param 3: list containing parent line number and section name
func! s:UpdateAncestorMap(map, key, value)
"    call Dfunc("UpdateAncestorMap(key: ".a:key.", val: ".string(a:value).", map: ".string(a:map).")")
    if has_key(a:map, a:key)
        throw "Encountered a section (" . a:key . ") level a second time"
    endif
    let a:map[a:key] = a:value
"    call Dret("UpdateAncestorMap - new map: ".string(a:map))
endfunc

" Function s:DebugLog {{{3
"
func! s:DebugLog(...) abort
    if !empty(g:musecnav_log_file)
        call writefile([json_encode(a:000)], g:musecnav_log_file, 'a')
    endif
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

" musecnav#navigate {{{3
"                                                       musecnav#navigate {{{4
" Global, error handling wrapper around primary, local function
" Main entry point for normal plugin use. Primary hotkeys call this.
" An optional first param can be supplied which will trigger a reset
" based on the value. The allowed values and associated effects:
"
"     0: Initialize only. Run normally except return before calling Navigate.
"     1: Reinitialize section tree, ie. force a 'soft' reset
"     2: Reset state, and reinit tree, ie. force a 'hard' reset
"
" Any other value will result in an error.
"                                                                          }}}
func! musecnav#navigate(...)
"    call Dfunc("musecnav#navigate(" . string(a:000) . ")")
    let l:initonly = 0
    let l:force = 0
    if a:0 == 1
        if a:1 == 0
            let l:initonly = 1
        else
            let l:force = a:1
        endif
    endif

    if l:force < 0 || l:force > 2
"        call Dret("musecnav#navigate - fatal MU13")
        throw "MU13: force param must have a value between 0 and 2"
    endif

    try
        if &ft !=? 'asciidoc' && &ft !=? 'markdown'
"            call Dret("musecnav#navigate - Wrong filetype")
            echohl WarningMsg | echo "Not a valid filetype: " . &ft | echohl None
            return
        endif

        let b:leveladj = 0
        if &ft ==? 'asciidoc'
            let b:leveladj = 1
            "TODO
            "let s:asciidoc_header_mark_patts = ('[=#]', '=')
            if g:musecnav_strict_headers
                let b:adheadmark = '='
            else
                let b:adheadmark = '[=#]'
            endif
        endif

        if !exists('b:musecnav_data') || l:force
"            call Decho("Clearing b:musecnav_data")
            let b:musecnav_data = {}
        endif

        if exists('b:musecnav_batch')
"            call Decho("Running in BATCH mode (no popups)")
            let b:musecnav_use_popup = 0
        endif
        if !exists('b:musecnav_use_popup')
            " FYI popups introduced in 8.1 patch 1517
            let b:musecnav_use_popup = has('popupwin')
        endif

        if l:force == 2
            let b:musecnav_initialized = 0
        endif

        if !exists('b:musecnav_initialized') || !b:musecnav_initialized
            call s:InitHeaderInfo()
            let b:musecnav_initialized = 1
        endif

        if l:force == 2
            " Hard reset positions cursor at start/
            call setpos('.', [0, 1, 1])
        endif

        "if !exists("b:musecnav_data.selheadline") || l:force == 2

        if l:initonly
            return
        endif

        call s:Navigate()
    catch /^MU\d\+/
        echohl ErrorMsg
        echom "Error occurred in MuSecNav:" v:exception
        echohl ErrorMsg
        echom "Location:" v:throwpoint
        echohl None
    endtry
endfunc
" }}}

" Popup Functions {{{3

" Function musecnav#MenuFilter {{{4
" As an enhancement to popup menus we number menu elements (section headers)
" and allow the user to enter one of those numbers in order to move the
" selection to that line.  (For large docs with many sections Up/Down just
" doesn't cut it.)
func! musecnav#MenuFilter(id, key) abort
    let l:last_key = getwinvar(a:id, 'last_key')
    call setwinvar(a:id, 'last_key', a:key)

    if match(a:key, '\r') >= 0 && empty(l:last_key)
        " Exit when Enter hit twice in a row
        call popup_close(a:id)
        return 1
    endif

    let l:rownum = 0
    if match(a:key, '\C^J$') == 0
        let l:rownum = popup_getpos(a:id).core_height
        let b:musecnav_select_buf = -1
    elseif match(a:key, '\C^K$') == 0
        let l:rownum = 1
        let b:musecnav_select_buf = -1
    elseif match(a:key, '^\d$') == 0
        let l:rownum = s:ProcessMenuDigit(popup_getpos(a:id).core_height, a:key)
    endif

    if l:rownum > 0
        call win_execute(a:id, 'call cursor('.l:rownum.', 1)')
        return 1
    endif

    " No shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
endfunc

" Function musecnav#MenuHandler {{{4
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
" }}}
" }}}

" Utility Functions {{{3

" Function musecnav#FindFirstSecHead {{{4
"                                                musecnav#FindFirstSecHead {{{5
"
" Search for the opening header in a Markdown document or the first section
" header (not the document header) in an Asciidoc document. Following is an
" excerpt from MD's 'official spec' (really just a blog entry!). Currently
" musecnav only supports 'atx' style headers.
"
""""""""""""""""""""""
" Markdown supports two styles of headers, Setext and atx.
"
" Setext-style headers are “underlined” using equal signs (for first-level
" headers) and dashes (for second-level headers). For example:
"
"     This is an H1
"     =============
"
"     This is an H2
"     -------------
"
" Any number of underlining =’s or -’s will work.
"
" Setext headings are fucking ridiculous. The syntax is too damn squishy; as
" in far too lenient. If you can even find a complete specification. Anyways,
" see the internal notes for plan regarding future implementation of these.
"
" Moving on...
"
" Atx-style headers use 1-6 hash characters at the start of the line,
" corresponding to header levels 1-6. For example:
"
"     # This is an H1
"     ## This is an H2
"     ###### This is an H6
"
" Optionally, you may “close” atx-style headers. The closing hashes don’t need
" to match the number of hashes used to open the header.
"
"     ## This is an H2 ##
"     ### This is an H3 ######
"
""""""""""""""""""""""
"
" Asciidoc headers allows atx-style headers but with '=' instead of '#'.
" It also allows two-line headers as described below.
"
" 11.1. Two line titles
"
" A two line title consists of a title line, starting hard against the left
" margin, and an underline. Section underlines consist a repeated character
" pairs spanning the width of the preceding title (give or take up to two
" characters):
"
" The default title underlines for each of the document levels are:
"
" Level 0 (top level):     ======================
" Level 1:                 ----------------------
" Level 2:                 ~~~~~~~~~~~~~~~~~~~~~~
" Level 3:                 ^^^^^^^^^^^^^^^^^^^^^^
" Level 4 (bottom level):  ++++++++++++++++++++++
"
" Examples:
"
" Level One Section Title
" -----------------------
"
" Level 2 Subsection Title
" ~~~~~~~~~~~~~~~~~~~~~~~~
"
" Note: The Asciidoctor implementation of Asciidoc doesn't allow two line
" headers and neither does musecnav, at least for the time being.
"
" Return value of this function is an array containing information about the
" first header seen. It will look like this:
"
"   [line number, header level, is multiline?, title]
"
"                                                                          }}}
func! musecnav#FindFirstSecHead()
"    call Dfunc("FindFirstSecHead()")
    call cursor(1, 1)

    if &ft ==? 'asciidoc'
        if b:musecnav_hasdocheader
            if b:musecnav_docheader[1]
                " already found it (first header is not a doc header)
"                call Dret("FindFirstSecHead - using doc header")
                return b:musecnav_docheader
            endif
            " find a blank line (to pass over document header lines)
            call cursor(b:musecnav_docheader[0] + 1, 1)
        endif
    endif

    let [l:matchline, l:matchcol, _, _] = s:FindNextSection()
"    call Decho("1st sect: [lineno, col, _, _] is [".l:matchline.", ".l:matchcol.",,]")
"    call Dret("FindFirstSecHead")
    if &ft ==? 'asciidoc'
        let l:level = l:matchcol - 1
    else
        let l:level = l:matchcol
    endif
    return [l:matchline, l:level, 0, getline(l:matchline)[l:matchcol+1:]]
endfunc


" }}} musecnav#FindFirstSecHead

" Function musecnav#FindFirstHeader {{{4
"                                                musecnav#FindFirstHeader {{{5
" Find the first document or section header in the document.
"
" A document header must be at the start of the document. The header is
" optional (first text could be a level-1 section title instead) except in
" case of a manpage which requires it. (Not enforced here.) If not present
" the first thing in the document should be a section header (though our job
" isn't to validate markup so we may be lenient about some junk preceding it
" and let AD/MD worry about the particulars).
"
" The following shows the basic makeup of a document header. All of the lines
" within are optional  .
"
"    ----------------------------
"    blank lines (true?)
"    <header starts>
"    attribute entries and comments (not recommended)
"    ...
"    attribute entries and comments (not recommended)
"    = Level 0 Document Title (# can be used in place of =)
"    author and revision info
"    author and revision info
"    attribute entries and comments
"    ....
"    attribute entries and comments
"    <header ends>
"
"    == Level 1 Section Title (## can be used in place of ==)
"    ----------------------------
"
" Return value of this function is an array containing information about the
" first document or section title seen, if any. For a valid title the array
" will look like this:
"
"   [line number, header level, is multiline?, title]
"
"   (title here is the doc title line minus the leading =/# and space)
"
" Examples:
"   [3, 0, 0, 'Title']  (preceded by 2 lines of comments/attributes/blanks)
"   [1, 0, 1, 'Title']    (a multi-line header)
"   [1, 1, 0, 'Sec Head'] (not a title)
"
" If no title header was found an empty array is returned.
"
" The only content permitted above the document title are blank lines, comment
" lines and document-wide attribute entries. If the document title is present
" no blank lines are allowed in the rest of the header as the first blank line
" signifies the end of the header and beginning of the first section.
"                                                                          }}}
func! musecnav#FindFirstHeader()
    let l:iscomment = 0
    let l:lineno = 1
    " scan up to 50 lines; ignore comment blocks, line comments and blank lines
    while l:lineno < 50
        let l:line = getline(l:lineno)
        let l:lineno += 1
        if l:line =~ '^/\{4,}$'
            let l:iscomment = !l:iscomment
            continue
        endif
        if l:iscomment
            continue
        endif
        if l:line !~ '\(^//\)\|\(^\s*$\)'
            " found something
            break
        endif
    endwhile

    if l:line =~ '^' . b:adheadmark . '\+\s\+\w'
        " title: single-line type
        let l:level = match(l:line, '^' . b:adheadmark . '*\zs' . b:adheadmark . '\s\+\w')
        return [l:lineno-1, l:level, 0, l:line[l:level+2:]]
    endif

    " now it's either a valid multi-liner or failed search (i.e. return [])
    let l:len = len(l:line)
    if l:len < 3
        return []
    endif

    let l:nextline = getline(l:lineno)
    if l:nextline !~ '[-=]\{3,}'
        return []
    endif

    let l:nextlen = len(l:nextline)
    if l:len < (l:nextlen - 3) || l:len > (l:nextlen + 3)
        return []
    endif

    " title: multi-line type
    if l:nextline =~ '^='
        let l:level = 1
    else
        let l:level = 2
    endif
    return [l:lineno-1, l:level, 1, l:line[l:level+2:]]
endfunction

" Function musecnav#InfoDump {{{4

func! musecnav#HeaderInfoDump()
    let l:vars = ['b:musecnav_docname', 'b:musecnav_rootlevel', 'b:musecnav_hasdocheader', 'b:musecnav_docheader', 'b:musecnav_firstsecheader']
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n", split(l:var, '_')[1], eval(l:var))
        endif
    endfor
endfunc

func! musecnav#InfoDump()
    if !exists('b:musecnav_data')
        echo printf("No data for this buffer!")
        return
    elseif empty(b:musecnav_data)
        echo printf("Main dictionary not currently populated")
        return
    endif

    echo printf("Sections: %s\n\n", b:musecnav_data.sections)
    if exists('b:musecnav_data.last_menu_text')
        echo printf("Last Menu: %s\n\n", b:musecnav_data.last_menu_text)
    endif
    echo printf("Level Map: %s\n\n", b:musecnav_data.level_map)
    echo printf("Ancestor Map: %s\n\n", b:musecnav_data.ancestor_map)

    let l:vars = ['b:musecnav_data.level', 'b:musecnav_data.selheadline', 'b:musecnav_data.currparent']
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n", split(l:var, '_')[1], eval(l:var))
        endif
    endfor
    echo printf("\nHeader Info:\n\n")
    call musecnav#HeaderInfoDump()
    echo printf("\nMuSecNav v%s\n\n", g:musecnav_version)
endfunc

" Function musecnav#ShiftPopupHi {{{4
"                                                            ShiftPopupHi {{{5
" Changes the linked highlight group for group Popup or PopupSelected.
" Both of those have a pre-configured list of link targets. This function
" will cycle through the appropriate list (determined by the function param)
" and the value is linked to the associated group (Popup or PopupSelected).
"                                                                          }}}
func! musecnav#ShiftPopupHi(forsel)
    if g:musecnav_popup_modifiable == 0
        return
    endif

    if !exists('b:musecnav_popup_hiidx')
        let b:musecnav_popup_hiidx = [0, 0]
    endif

    let l:type = 0
    let l:group = "Popup"
    if a:forsel
        let l:type = 1
        let l:group .= "Selected"
    endif
    let l:size = len(g:musecnav_popup_higroups[l:type])
    let b:musecnav_popup_hiidx[l:type] =
                \ (b:musecnav_popup_hiidx[l:type]+1)%l:size
    exe 'hi link ' . l:group . ' ' .
        \ g:musecnav_popup_higroups[l:type][b:musecnav_popup_hiidx[l:type]]
endfunc
" }}}
" }}}3

" Other Functions {{{3

" TODO: Used? If not delete it.
func! musecnav#DataReset()
    let b:musecnav_data = {}
    let l:vars = ['b:musecnav_hasdocheader', 'b:musecnav_rootlevel', 'b:musecnav_docname', 'b:musecnav_docheader', 'b:musecnav_firstsecheader']
    for l:var in l:vars
        if exists(l:var)
            exe "unlet " . l:var
        endif
    endfor
endfunc

" FOR TESTING ONLY
func! musecnav#InitHeaderInfo()
    return s:InitHeaderInfo()
endfunc

" Currently using this as a trigger to source this file. Called from autoload
" file for musecnav when a markup file type is indicated.
func! musecnav#activate()
    return
endfunc

" Config Undo {{{1
" TODO: complete undo of config
let &cpoptions = s:save_cpo
unlet s:save_cpo

