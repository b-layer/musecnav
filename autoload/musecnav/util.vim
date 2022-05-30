let s:save_cpo = &cpoptions
set cpoptions&vim

let s:head_info_field_3 = ["Line", "Level", "Text"]
let s:head_info_field_4 = ["Line", "Column", "Level", "Text"]

" In-menu header display modes, associated with musecnav_display_mode
let s:displaymodes = ['sel', 'anc', 'all']

" Function musecnav#CycleLayouts {{{1
func! musecnav#util#get_viz_mode() abort
    let l:mode = get(b:, 'musecnav_display_mode', 'anc')->strcharpart(0, 3)

    if index(s:displaymodes, l:mode) < 0
        throw "MU03: Invalid Display Mode [" . l:mode . "]"
    endif

    return l:mode
endfunc

" Function musecnav#CycleLayouts {{{1
"                                                 musecnav#CycleLayouts {{{2
" Set the menu's display mode by cycling forward or back through available
" values.
"
" The associated setting: b:musecnav_display_mode
"                                                                          }}}
func! musecnav#util#CycleLayouts(diff)
    if !exists('b:displaymodeidx')
        let b:displaymodeidx = index(s:displaymodes, b:musecnav_display_mode)
    endif
    let b:displaymodeidx = (b:displaymodeidx + a:diff) % len(s:displaymodes)
    let b:musecnav_display_mode = s:displaymodes[b:displaymodeidx]
    echom 'musecnav display mode: ' . b:musecnav_display_mode
endfunc

" plugin info functions {{{1

" Returns a string with nicely formatted header info list values. These have
" one of two forms:
"
"   [line number, column number, header level, header text]
"   [line number, header level, header text]
"
" Based on the length of the list the appropriate names and values will
" be paired together in the returned string ready for display.
"
" This function is meant to be used for printing diagnostic messages and the
" like. It should not interrupt program flow and if an error occurs, e.g.
" input is invalid, an error message will be returned instead of normal text.
"
" Param 1: the info list
" Param 2: boolean; if truthy then elements are separated by newlines,
"          otherwise by a comma and space
function! musecnav#util#head_info_str(infolist, multiline)
    let l:len = len(a:infolist)
    if l:len != 3 && l:len != 4
        return "ERROR: Invalid input. 3 or 4 element list required."
    endif

    let l:fields = l:len == 3 ? s:head_info_field_3 : s:head_info_field_4

    let l:ret = ""
    for l:field in range(l:len)
        let l:ret .= l:fields[l:field] . ": " . a:infolist[l:field]
        if a:multiline
            let l:ret .= "\n"
        else
            let l:ret .= ", "
        endif
    endfor

    " Strip trailing comma and space before returning
    return strcharpart(l:ret, 0, len(l:ret)-2)
endfunction

func! s:setting_info()
    echo printf("\nSettings:\n\n")
    for l:var in g:musecnav_config_vars
        if exists(l:var)
            echo printf("%-18s : %s\n", l:var[11:], eval(l:var))
        endif
    endfor
endfunc

func! musecnav#util#info()
    if !exists('b:musecnav_doc')
        echo printf("No data for this buffer!")
        return
    elseif empty(b:musecnav_doc)
        echo printf("Main dictionary not currently populated")
        return
    endif

    echo printf("Sections:\n%s\n", b:musecnav_doc.to_string())

    if exists('b:musecnav_data.last_menu_text')
        echo printf("Last Menu:\n\n")
        echo printf("Text: %s\n\n", b:musecnav_data.last_menu_text)
        echo printf("Data: %s\n\n", b:musecnav_data.last_menu_data)
    endif

    let l:vars = ['b:musecnav_data.last_menu_row', 'b:musecnav_doc.currsec.level', 'b:musecnav_doc.currsec.line']
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n",
                        \ join(split(l:var, '_')[1:], '_'), eval(l:var))
        endif
    endfor
    call s:setting_info()

    echo printf("\nMusecnav version: %s\n\n", g:musecnav_version)
endfunc

" struncate() {{{1
"
" Wrapper for string() that truncates its result.
"
" Maximum length of returned strings (not counting the added '... <SNIP>'
" suffix) can be specified in global 'musecnav_liststr_limit' otherwise a
" default of 160 chars is used.
"
" Disable with global 'musecnav_struncate_off'.
"
" Currently used only with data passed to decho functions.
function! musecnav#util#struncate(struct)
    if exists("g:musecnav_struncate_off") && g:musecnav_struncate_off
        return string(a:struct)
    endif

    let l:limit = get(g:, "musecnav_liststr_limit", 160)
    let l:ret = string(a:struct)
    let l:len = strlen(l:ret)
    if l:len == 0
        return ""
    elseif l:len > l:limit
        let l:ret = l:ret[0:l:limit-1] .. " ... <SNIP>"
    endif
    return l:ret
endfunc
" struncate() 1}}}

func! musecnav#util#debug_log(...) abort
    if !empty(g:musecnav_log_file)
        call writefile([json_encode(a:000)], g:musecnav_log_file, 'a')
    endif
endfunc

" Currently only used by personal stuff (MSNReload)
func! musecnav#util#data_reset()
    let b:musecnav_data = {}
    unlet! b:musecnav_doc
    let l:vars = ['b:musecnav_hasdocheader', 'b:musecnav_rootlevel', 'b:musecnav_docname', 'b:musecnav_docheader', 'b:musecnav_firstsecheader', 'b:musecnav_hdrs_scanned']
    for l:var in l:vars
        if exists(l:var)
            exe "unlet " . l:var
        endif
    endfor
endfunc

func! musecnav#util#list_dict_vals(key, list) abort
    let l:ret = []
    if a:list->empty()
        return l:ret
    endif
    for l:elem in a:list
        call add(l:ret, l:elem[a:key])
    endfor
    return l:ret
endfunc

" TODO: temp func...remove when done
func! musecnav#util#sec_viz_string(sections) abort
    let l:str = ""
    for l:sec in a:sections
        let l:str .= l:sec.visible ? '+' : '-'
    endfor
    return l:str
endfunc


let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdc=3:fdm=marker:fmr={{{,}}}
