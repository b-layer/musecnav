" musecnav autoload plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

let g:musecnav_version = 114

" Function s:ShowMenu {{{1

" Scan the buffer for section headers, as needed, then display the sections in
" a popup or drawer.
func! s:ShowMenu() abort
"    call Dfunc("Navigate()")

    call s:LoadSections()

    if b:musecnav_doc.is_empty()
        echohl WarningMsg | echom "No headers identified! Aborting." | echohl None
"        call Dret("Navigate - abort")
        return
    endif

    " If cursor has moved since last menu selection determine what section it
    " currently resides in and make that the new 'current section' before
    " building the menu.
    let l:currline = getcurpos()[1]
"    call Decho("last line: ".b:musecnav_doc.currsec.line ." curr line: ".l:currline)

    if b:musecnav_doc.currsec.line != l:currline
        call b:musecnav_doc.set_current_section(l:currline)
"        call Decho("Selected section updated, line: " . b:musecnav_doc.currsec.line)
    endif

    " For non-popup menu a continuous draw-menu/get-input/process-input cycle
    " happens here. Loop is exited only upon user entering return alone.
    " For popup menu we break out of the loop immediately after menu is drawn
    " since popups are handled in separate threads and thus there's no reason
    " to maintain this loop. ProcessSelection will be called from the popup
    " callback function.
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
endfunc

" Function s:LoadSections {{{1
"                                                         LoadSections {{{2
" Build the section header hierarchy.
"
" 1. Change in number of buffer lines? Set rebuild flag.
" 2. If not rebuild and we already have data just return.
" 6. document#build()
"
" Optional arg:
"   a:1 - starting line number for scan instead of default 1
"                                                                          }}}
func! s:LoadSections(lineno=1) abort
"    call Dfunc("LoadSections(". a:lineno . ")")
    let l:lastlineno = line('$')
    let l:rebuild = 0

    if exists('b:musecnav_data.buflines') && b:musecnav_data.buflines != l:lastlineno
"        call Decho("Number of buffer lines changed. Rescanning.")
        let l:rebuild = 1
    endif
    let b:musecnav_data.buflines = l:lastlineno

    " Return if tree already built unless forced b/c file contents changed
    " or param flag was set (usually due to Ctrl-F7)
    " REDO: It might be better to expose document.new() and call that early
    " on. Then we'd have musecnav#document#build(document)
    if exists('b:musecnav_doc') && !l:rebuild
"        call Dret("LoadSections - tree already built")
        return 0
    endif

    echom "Processing section headers..."

    if l:rebuild || !exists("b:musecnav_doc")
        " Data from last call to menuizetree function
        let b:musecnav_data.last_menu_data = []
        " Most recent display menu lines. Unused but for a decho msg or two.
        let b:musecnav_data.last_menu_text = []
    endif

  let b:mtime = reltime()
  if !exists('b:mutimes') | let b:mutimes = [] | endif
    let b:musecnav_doc = musecnav#document#build()
  call add(b:mutimes, reltimestr(reltime(b:mtime)))

    echom "done"
    redraws
"    call Dret("LoadSections - result: " . b:musecnav_doc.to_string(1))
    return 1
endfunc

" Function s:DrawMenu {{{1

" Show menu representing current state of navigation either above the command
" line or in a popup window. If not using popups get the user's selection and
" return it.  Otherwise, popups handle user input in a separate thread so this
" will always returns -1 immediately in that case.
func! s:DrawMenu() abort
"    call Dfunc("DrawMenu()")

    let l:menudata = b:musecnav_doc.render()
"    call Decho("Generated menu data: ".musecnav#util#struncate(l:menudata))

    let l:idx = 0
    let l:displaymenu = []
    " the row number to highlight (the selected row)
    let l:hirownum = 0
    let l:maxlen = get(b:, 'musecnav_max_header_len', 0)

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
        if b:musecnav_doc.currsec.line == l:rowitem[1]
            let l:pad = b:musecnav_place_mark . ' '
            let l:hirownum = l:idx + 1
        endif
    
        let l:rowtext = l:rowitem[2]->trim()
        " truncate if necessary
        if l:maxlen > 0 && l:rowtext->len() > l:maxlen
            let l:rowtext = l:rowtext->strcharpart(0, l:maxlen-3) . '...'
        endif
    
        " Add padding proportional to current row's section level
        let l:rowtext = repeat(' ', (l:rowlevel - 1) * 2)
                    \ . l:pad . l:rowtext
        " Prepend menu line numbers and we have one menu item ready to go.
        let l:rowtext = printf("%2s", l:idx+1) . ": " . l:rowtext
"        call Decho("    into rowtext: " . l:rowtext)
        call add(l:displaymenu, l:rowtext)
    
        if !b:musecnav_use_popup
            echom l:rowtext
        endif
        let l:idx += 1
    endwhile
    " l:menudata processing loop }}}

    let b:musecnav_data.last_menu_data = l:menudata
    let b:musecnav_data.last_menu_text = l:displaymenu
    let b:musecnav_data.last_menu_row = l:hirownum

    " display the menu popup/drawer {{{
    let l:choice = -1
"    call Decho("Display menu len: ".len(l:displaymenu)." data: ".musecnav#util#struncate(l:displaymenu))
    let l:title = ' Up/Down or 1-99 then <Enter> '
    if exists("b:musecnav_batch")
        echom '--------'
    elseif b:musecnav_use_popup
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
            " last chosen section will be highlighted row
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
endfunc

" Function s:ProcessSelection {{{1

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
"    call Decho("User selected ".b:musecnav_data.last_menu_text[l:choiceidx])
    let l:chosendata = b:musecnav_data.last_menu_data[l:choiceidx]
"    call Decho("Menu data (".l:choiceidx."): " . musecnav#util#struncate(l:chosendata))

    call b:musecnav_doc.set_current_section(l:chosendata[1])

"    call Decho("Navigate to line ".l:chosendata[1]." (level ".l:chosendata[0].")")
    exe l:chosendata[1]
    norm! zz
    " Clear the menu digit buffer
    let s:musecnav_select_buf = -1
"    call Dret("ProcessSelection")
endfunc

" Function s:ProcessMenuDigit {{{1
"                                                        ProcessMenuDigit {{{2
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
endfunc

" Function musecnav#navigate {{{1
"                                                       musecnav#navigate {{{2
" Main entry point for normal plugin use. Primary hotkeys call this.
"
" Contains some setup and sanity checking before calling the local navigate
" function. Known error types will bubble up to here and get caught and
" properly messaged while anything else, unknown and therefore considered
" critical, is allowed to escape.
"
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
"    call Dfunc("musecnav#navigate(" . join(a:000, ", ") . ")")

    let l:force = 0
    if a:0 == 1
        if a:1 >= 0 && a:1 <= 2
            let l:force = a:1
        else
"    "        call Dret("musecnav#navigate - fatal MU14")
            throw "MU14: force param must have a value between 0 and 2"
        endif
    endif

    if &ft !=? 'asciidoc' && &ft !=? 'markdown'
"        call Dret("musecnav#navigate - Wrong filetype")
        echohl WarningMsg | echom "Not a valid filetype: " . &ft | echohl None
        return
    endif

    try
        " Do some file type specific setup and checks
        if &ft ==? 'asciidoc'
            if b:musecnav_use_ad_synhi && !exists("g:syntax_on")
                " For now just quietly disable the double-check
                let b:musecnav_use_ad_synhi = 0
            endif
        else " markdown
            if !exists("g:syntax_on")
                echohl WarningMsg
                echom "Markdown section header detection requires that syntax highlighting be enabled"
                echohl None
                return
            endif
        endif

        if l:force
"            call Decho("Clearing b:musecnav_doc")
            unlet! b:musecnav_doc
        endif

        " REDO: legacy
        if l:force || !exists('b:musecnav_data')
            let b:musecnav_data = {}
        endif

        if exists('b:musecnav_batch')
"            call Decho("Running in BATCH mode (no popups)")
            let b:musecnav_use_popup = 0
        endif

        if b:musecnav_use_popup && !has('popupwin')
            echohl WarningMsg
            echom 'Vim 8.1.1517 or later required for the popup-style menu'
            echohl None
            return
        endif

        if l:force == 2
            " Hard reset positions cursor at start
            call setpos('.', [0, 1, 1])
        endif

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
endfunc

" Function musecnav#MenuFilter {{{1
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
        let s:musecnav_select_buf = -1
    elseif match(a:key, '\C^K$') == 0
        let l:rownum = 1
        let s:musecnav_select_buf = -1
    elseif match(a:key, '^\d$') == 0
        let l:rownum = s:ProcessMenuDigit(popup_getpos(a:id).core_height, a:key)
    elseif match(a:key, '^j$') == 0
        let l:maxrow = popup_getpos(a:id).core_height
        let l:currow = b:musecnav_data.last_menu_row
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

    " No shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
endfunc

" Function musecnav#MenuHandler {{{1
" Menus can't callback into script-local code so this must be a global
" function. This will spawn an updated menu popup unless result param is -1.
func! musecnav#MenuHandler(id, result) abort
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
endfunc
" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdc=3:fdm=marker:fmr={{{,}}}
