" musecnav autoload plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

let g:musecnav_version = 114
" Minimum number of section header title characters to display 
let s:min_title_length = 5

" Function s:LoadSections {{{1
"                                                         LoadSections {{{2
" Scan the buffer and build the section header hierarchy, as needed.
"
" Params:
" lineno - scan starts on this line [default: line 1]
"                                                                          }}}
function! s:LoadSections(lineno=1) abort
"    call Dfunc("LoadSections(". a:lineno . ")")
    let l:lastlineno = line('$')
    let l:rebuild = 0

    " If the number of lines in the buffer has changed then rescan buffer.
    " Note: I thought about checking b:changedtick here as a rescan trigger
    " but that'll almost surely result in too many unnecessary reloads.
    if exists('b:musecnav.buflines') && b:musecnav.buflines != l:lastlineno
"        call Decho("Number of buffer lines changed. Rescanning.")
        let l:rebuild = 1
    endif
    let b:musecnav.buflines = l:lastlineno

    " Initialization of the search object is usually done only once. The
    " exception is if there's a significant structural change, such as removal
    " of a document header. The user can do a hard reset to re-trigger this.
    if !exists('b:musecnav.searchobj') || empty(b:musecnav.searchobj)
        let b:musecnav.searchobj = musecnav#search#init()
    endif

    " Nothing to do if headers are already scanned unless rebuild flag is set.
    if exists('b:musecnav.doc.sections') && !l:rebuild
"        call Dret("LoadSections - sections already scanned")
        return 0
    endif

    echom "Processing section headers..."
    let b:musecnav.doc = musecnav#document#build(b:musecnav.searchobj)
    echom "done"
    redraws

"    call Dret("LoadSections - result: " . b:musecnav.doc.to_string(1))
    return 1
endfunction

" Function s:ShowMenu {{{1
"
" Do a bit of sanity checking on state before calling DrawMenu() to actually
" show the sections in a popup or drawer. Then drawer lifecycle and user
" interaction is handled here. (The popup menu is handled in a more global
" scope due to its dependence on Vim).
"
function! s:ShowMenu() abort
"    call Dfunc("Navigate()")
    if b:musecnav.doc.is_empty()
        echohl WarningMsg | echom "No headers identified! Aborting." | echohl None
"        call Dret("Navigate - abort")
        return
    endif

    " If cursor has moved since last menu selection determine what section it
    " currently resides in and make that the new 'current section' before
    " building the menu.
    let l:currline = getcurpos()[1]
"    call Decho("last line: ".b:musecnav.doc.curr_sec_line() ." curr line: ".l:currline)
    if b:musecnav.doc.curr_sec_line() != l:currline
        call b:musecnav.doc.set_curr_sec(l:currline)
"        call Decho("Selected section updated, line: " . b:musecnav.doc.curr_sec_line())
    endif

    " For non-popup menu a continuous draw-menu/get-input/process-input cycle
    " happens here. Loop is exited only upon user entering return alone.
    " For popup menu we break out of the loop immediately after menu is drawn
    " since popup interaction is handled by Vim (ProcessSelection will be
    " called from the popup callback function.)
    while (1)
        " reset the digit entry 'buffer'
        let s:musecnav_select_buf = -1

        let l:choice = s:DrawMenu()
        if !len(l:choice) || l:choice < 0
            break
        endif
        call s:ProcessSelection(-1, l:choice)
    endwhile

"    call Dret("Navigate - normal exit")
endfunction


" Function s:DrawMenu {{{1
"
" Show menu representing current state of navigation either above the command
" line or in a popup window. If not using popups get the user's selection and
" return it.  Otherwise, popups handle user input in a separate context so
" we'll return -1 immediately in that case.
"
function! s:DrawMenu() abort
"    call Dfunc("DrawMenu()")
    let l:menudata = b:musecnav.doc.render()
"    call Decho("Generated menu data: ".musecnav#util#struncate(l:menudata))

    let l:idx = 0
    let l:displaymenu = []
    " the row number to highlight (the selected row)
    let l:hirownum = 0
    let l:currsecline = b:musecnav.doc.curr_sec_line()
    let l:maxlen = get(b:, 'musecnav_max_title_len', 0)
    if l:maxlen
        let l:maxlen = max([l:maxlen, s:min_title_length])
    endif

    if !b:musecnav_use_popup
        echom '--------'
    endif

    " l:menudata processing loop {{{
    while l:idx < len(l:menudata)
        let l:rowitem = l:menudata[l:idx]
        let l:rowlevel = l:rowitem[0]
"        call Decho("  process rowitem: " . musecnav#util#struncate(l:rowitem))
        let l:pad = '  '
        " For currently selected menu item insert our marker icon
        if l:currsecline == l:rowitem[1]
            let l:pad = b:musecnav_place_mark . ' '
            let l:hirownum = l:idx + 1
        endif

        let l:rowtext = l:rowitem[2]->trim()
        " truncate if necessary
        if l:maxlen && l:rowtext->len() > l:maxlen
            let l:rowtext = l:rowtext->strcharpart(0, l:maxlen) . '..'
        endif

        " Indent row text an amount proportional to the section level
        let l:rowtext = repeat(' ', (l:rowlevel - 1) * 2)
                    \ . l:pad . l:rowtext
        " Prepend menu line numbers
        let l:rowtext = printf("%2s", l:idx+1) . ": " . l:rowtext
"        call Decho("    into rowtext: " . l:rowtext)
        call add(l:displaymenu, l:rowtext)

        if !b:musecnav_use_popup
            echom l:rowtext
        endif
        let l:idx += 1
    endwhile
    " l:menudata processing loop }}}

    let b:musecnav.last_menu_data = l:menudata
    let b:musecnav.last_menu_row = l:hirownum

    " display the menu popup/drawer {{{
    let l:choice = -1
"    call Decho("Display menu len: ".len(l:displaymenu)." data: ".musecnav#util#struncate(l:displaymenu))
    if exists("b:musecnav_batch")
        echom '--------'
    elseif b:musecnav_use_popup
        let l:title = ' j|k|J|K or row # then <Enter> '
        let l:ww = winwidth(0)
        let l:popcol = min([b:musecnav_pop_col+4, l:ww - strlen(l:title)])
        let popid = popup_menu(l:displaymenu, #{
                    \ title: l:title,
                    \ col: l:popcol,
                    \ pos: 'topleft',
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
            " move cursor to most recently selected row, highlighting it
            call win_execute(popid, 'call cursor('.l:hirownum.', 1)')
        endif
    else
        echom '--------'
        let l:choice = input("Enter number of section: ")
        while strlen(l:choice) && type(eval(l:choice)) != v:t_number
            echohl WarningMsg | echom "You must enter a valid number" | echohl None
            let l:choice = input("Enter number of section: ")
        endwhile
        redraw
    endif
    " display the menu popup/drawer }}}

"    call Dret("DrawMenu")
    return l:choice
endfunction

" Function s:ProcessSelection {{{1
"
" Given user selection of a menu row determine what section that represents
" and what line number contains it and move the cursor to that line.
"
" Params:
" id - a popup window id or -1 if we're using non-popup menus
" choice - the user's selection, normally a positive integer
"
function! s:ProcessSelection(id, choice) abort
"    call Dfunc("ProcessSelection(id:".a:id.", choice:".a:choice.")")
    if a:id == -1
        if b:musecnav_use_popup
"            call Dret("ProcessSelection - error 93")
            throw "MU93: Illegal State - non-popup id but popup flag set"
        endif
    endif

    let l:menudata = b:musecnav.last_menu_data[a:choice - 1]
    let l:bufline = l:menudata[1]
    call b:musecnav.doc.set_curr_sec(l:bufline)

"    call Decho("Navigate to line ".l:bufline)
    exe l:bufline
    norm! zz
    " Clear the menu digit buffer
    let s:musecnav_select_buf = -1
"    call Dret("ProcessSelection")
endfunction

" Function s:ProcessMenuDigit {{{1
"                                                        ProcessMenuDigit {{{2
" A bit of a state machine for handling menu row numbers which make it easier
" for the user to jump to a section when there are many.
"
" The total number of headers and whether the user is entering the first or
" second (if applicable) digit of their choice determine what happens. (e.g.
" can/should we move to row 2 after the user enters the first digit of 25)
"                                                                          }}}
function! s:ProcessMenuDigit(rows, entry) abort
"    call Dfunc("ProcessMenuDigit(rows:".a:rows.", entry:".a:entry.")")
    let l:ret = -99
    " non-negative number?
    if !(a:entry >= 0 && a:entry <=9)
"        call Dret("ProcessMenuDigit - invalid entry ".a:entry)
        return -1
    endif

    " empty 'buffer'?
    if s:musecnav_select_buf < 0
        " first entry non-zero?
        if a:entry > 0
            " can entry only be first 10 rows?
            if a:rows < a:entry * 10
                " yep - final selection
                let s:musecnav_select_buf = -1
            else
                " tenative selection
                let s:musecnav_select_buf = a:entry
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
        let l:entry = (10*s:musecnav_select_buf) + a:entry
        if l:entry <= a:rows
            " final selection
            let s:musecnav_select_buf = -1
            let l:ret = l:entry
        else
            " out of range
            let l:ret = -4
        endif
    endif

"    call Dret("ProcessMenuDigit - returning ".l:ret)
    return l:ret
endfunction

" Function musecnav#navigate {{{1
"                                                       musecnav#navigate {{{2
" Main entry point for normal plugin use. Primary hotkeys call this.
"
" Contains some setup and sanity checking before calling menu building
" routines.
"
" Known error types will bubble up to here and get caught and properly
" messaged while anything else, unknown and therefore considered critical, is
" allowed to escape.
"
" An optional first param can be provided to force the clearing of some or all
" of musecnav's data. The allowed values are:
"
"     0: Normal functionalilty. [default]
"     1: 'Soft' reset: clear header data, redo section scan.
"     2: 'Hard' reset: clear all state, do a complete rescan of the buffer.
"
" Any other value will result in an error.
"                                                                          }}}
function! musecnav#navigate(force=0)
"    call Dfunc("musecnav#navigate(" . join(a:000, ", ") . ")")
    if a:force < 0 || a:force > 2
"            call Dret("musecnav#navigate - fatal MU14")
        throw "MU14: force param must have a value between 0 and 2"
    endif

    if &ft !~? '^asciidoc\(tor\)\?' && &ft !=? 'markdown'
        echohl WarningMsg | echom "Not a valid filetype: " . &ft | echohl None
"        call Dret("musecnav#navigate - Wrong filetype")
        return
    endif

    try
        if !exists('b:musecnav')
"            call Decho("Initializing b:musecnav")
            let b:musecnav = {}
        endif

        if a:force == 1
"            call Decho("Clearing section data")
            let b:musecnav.doc = {}
        elseif a:force == 2
"            call Decho("Resetting all state")
            let b:musecnav = {}
        endif

        " Do some file type specific setup and checks
        if &ft ==? 'asciidoc' || &ft ==? 'asciidoctor'
            if b:musecnav_use_ad_synhi && !exists("g:syntax_on")
                " For now just quietly disable the double-check
                let b:musecnav_use_ad_synhi = 0
            endif
            let b:musecnav.adtype = 1
        else  " markdown
            if !exists("g:syntax_on")
                echohl WarningMsg
                echom "Musecnav for Markdown requires that syntax "
                            \ . "highlighting be enabled"
                echohl None
"                call Dret("musecnav#navigate - no synhi")
                return
            endif
            let b:musecnav.adtype = 0
        endif

        if exists('b:musecnav_batch')
"            call Decho("Running in BATCH mode (no popups)")
            let b:musecnav_use_popup = 0
        endif

        if b:musecnav_use_popup && !has('popupwin')
            echohl WarningMsg
            echom 'Vim 8.1.1517 or later required for the popup-style menu'
            echohl None
"            call Dret("musecnav#navigate - no popups")
            return
        endif

        call s:LoadSections()
        call s:ShowMenu()
"        call Dret("musecnav#navigate")
    catch /^MUXX/
        if get(g:, "musecnav_dev_mode", 0)
            throw v:exception
        endif

        echohl WarningMsg
        echom printf("Oops! MuSecNav ran into some trouble: %s", l:errmsg)
        echohl None
    catch /^MU\d\+/
        let l:errmsg = "MuSecNav can't proceed"
        echohl WarningMsg
        if get(g:, "musecnav_dev_mode", 0)
            echom printf("%s: %s [%s]", l:errmsg, v:exception, v:throwpoint)
        else
            echom printf("%s: %s", l:errmsg, v:exception)
        endif
        echohl None
    endtry
endfunction

" Function musecnav#MenuFilter {{{1
"
" As an enhancement to popup menus we number menu elements (section headers)
" and allow the user to enter one of those numbers in order to move the
" selection to that line.
"
" This is the 'filter' function passed to Vim's popup creation routine.
"
function! musecnav#MenuFilter(id, key) abort
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
        let s:musecnav_select_buf = -1
    elseif match(a:key, '\C^K$') == 0
        let l:rownum = 1
        let s:musecnav_select_buf = -1
    elseif match(a:key, '^\d$') == 0
        let l:rownum = s:ProcessMenuDigit(popup_getpos(a:id).core_height, a:key)
    elseif match(a:key, '^j$') == 0
        let l:maxrow = popup_getpos(a:id).core_height
        let l:currow = b:musecnav.last_menu_row
        "let b:musecnav_popup_msg = printf(
        "            \ "Key j received with currow %d and maxrow %d",
        "            \ l:currow, l:maxrow)
        if l:currow == l:maxrow
            let s:test_past_menu_end = 1
        else
            let s:test_past_menu_end = 0
        endif
    endif

    if l:rownum > 0
        call win_execute(a:id, 'call cursor('.l:rownum.', 1)')
        return 1
    endif

    " Not a custom shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
endfunction

" Function musecnav#MenuHandler {{{1
"
" This is the 'callback' function passed to Vim's popup creation routine. It
" updates the section hierarchy in the popup unless an exit key was pressed.
"
" Note that popup menus can't callback into script-local code so this must be
" a global function.
"
function! musecnav#MenuHandler(id, result) abort
"    call Dfunc("MenuHandler(id:".a:id.", result:".a:result.")")
    if a:result < 1
        " FYI -1 indicates user canceled menu while 0 indicates popup_close()
        " was called without the 'result' param (which we do in MenuFilter)
"        call Dret("MenuHandler - exit input loop")
        return
    endif
    call s:ProcessSelection(a:id, a:result)
    call s:DrawMenu()
"    call Dret("MenuHandler")
endfunction
" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdm=marker:fmr={{{,}}}
