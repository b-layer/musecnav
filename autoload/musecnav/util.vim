let s:save_cpo = &cpoptions
set cpoptions&vim

let s:sect_attrs_field_3 = ["Line", "Level", "Text"]
let s:sect_attrs_field_4 = ["Line", "Column", "Level", "Text"]

" Valid menu display modes, associated with musecnav_display_mode
let s:displaymodes = ['anc', 'sel', 'all']
let s:defaultmode = 'anc'

" Function musecnav#util#get_disp_mode {{{1
"
" Returns the currently configured display mode. If not configured the default
" mode is returned.
"
" Long names of the modes are allowed in configuration but this will
" abbreviate to a length of three characters (the form used internally).
"
" Throws an error if the mode is invalid.
function! musecnav#util#get_disp_mode() abort
    let l:mode = get(b:, 'musecnav_display_mode', s:defaultmode)->strcharpart(0, 3)

    if index(s:displaymodes, l:mode) < 0
        throw "MU03: Invalid Display Mode [" . l:mode . "]"
    endif

    return l:mode
endfunction

" Function musecnav#util#rotate_disp_mode {{{1
"
" Set the menu's display mode by cycling forward or back through available
" values.
"
" The associated setting: b:musecnav_display_mode
function! musecnav#util#rotate_disp_mode(diff)
    if !exists('b:displaymodeidx')
        let b:displaymodeidx = index(s:displaymodes, b:musecnav_display_mode)
    endif
    let b:displaymodeidx = (b:displaymodeidx + a:diff) % len(s:displaymodes)
    let b:musecnav_display_mode = s:displaymodes[b:displaymodeidx]
    echom 'musecnav display mode: ' . b:musecnav_display_mode
endfunction

" Function musecnav#util#list_dict_vals {{{1
"
" From a list of dictionariess extract all the values associated with the
" given key. Returns an empty list if no such key-values are found.
function! musecnav#util#list_dict_vals(key, list) abort
    let l:ret = []
    if a:list->empty()
        return l:ret
    endif
    for l:elem in a:list
        call add(l:ret, l:elem[a:key])
    endfor
    return l:ret
endfunction

" Function musecnav#util#struncate {{{1
"
" String truncate, i.e. a wrapper for string() that truncates its result. If
" truncation is necessary ' ...' will be appended to the returned string.
"
" Maximum length of returned strings (not counting the appended marker string)
" can be specified in global 'musecnav_liststr_limit' otherwise a default of
" 160 chars is used.
"
" Setting 'musecnav_struncate_off' to truthy value causes this to act just
" like string().
"
" Note: currently used only with data passed to decho functions.
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
        let l:ret = l:ret[0:l:limit-1] .. " ..."
    endif
    return l:ret
endfunction

" Function musecnav#util#sect_attrs_str {{{1
"
" Returns a string with nicely formatted section header attributes. These have
" one of two forms:
"
"   [line number, column number, header level, header text]
"   [line number, header level, header text]
"
" Based on the length of the list the appropriate names and values will
" be paired together in the returned string.
"
" This function is meant to be used for printing diagnostic messages and the
" like. It should not interrupt program flow and if an error occurs, e.g.
" input is invalid, an error message will be returned instead of normal text.
"
" Param 1: the info list
" Param 2: boolean; if truthy then elements are separated by newlines,
"          otherwise by a comma and space (the default)
function! musecnav#util#sect_attrs_str(infolist, multiline=0)
    let l:len = len(a:infolist)
    if l:len != 3 && l:len != 4
        return "ERROR: Invalid input. 3 or 4 element list required."
    endif

    let l:fields = l:len == 3 ? s:sect_attrs_field_3 : s:sect_attrs_field_4

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

" Function musecnav#util#info {{{1
"
" Prints a bunch of internal state, current settings and the musecnav version.
" For debugging and testing.
function! musecnav#util#info()
    if !exists('b:musecnav.doc')
        echo printf("No data for this buffer! Open the menu yet?")
        return
    elseif empty(b:musecnav.doc)
        echo printf("Main dictionary not currently populated")
        return
    endif

    echo printf("[Sections]\n\n%s\n", b:musecnav.doc.to_string())
    if exists('b:musecnav.last_menu_data')
        echo printf("[Menu]\n\n")
        echo printf("%s\n", b:musecnav.last_menu_data)
    endif

    echo printf("\n[Selection]\n\n")
    let l:vars = ['b:musecnav.last_menu_row',
                \ 'b:musecnav.doc.currsec.level',
                \ 'b:musecnav.doc.currsec.line']
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n", l:var[11:], eval(l:var))
        endif
    endfor

    echo printf("\n[Settings]\n\n")
    for l:var in b:musecnav_config_vars
        if exists(l:var)
            echo printf("%-18s : %s\n", l:var[11:], eval(l:var))
        endif
    endfor

    echo printf("\nMusecnav version: %s\n", g:musecnav_version)
endfunction

" Function musecnav#util#doc_state_to_csv {{{1
"
" Return certain attributes of all current sections in CSV format for testing
" purposes.
function! musecnav#util#doc_state_to_csv() abort
    let l:str = ""
    for sect in b:musecnav.doc.sections
        let l:str .= printf("%s,%d,%d,%d,%s,%s,%s\n",
                \ (sect.visible ? '+' : '-'),
                \ sect.id, sect.line, sect.level, sect.title,
                \ sect.parent->empty() ? '-' : sect.parent.id,
                \ musecnav#util#list_dict_vals('id', sect.children))
    endfor
    return l:str
endfunction
" Function musecnav#util#doc_state_to_csv 1}}}

function! musecnav#util#args_to_json_file(file, ...) abort
    call writefile([json_encode(a:000)], a:file)
endfunction

function! musecnav#util#args_to_file(file, ...) abort
    call writefile(a:000, a:file)
endfunction

function! musecnav#util#str_to_file(file, str, mode='a') abort
    call writefile(a:str, a:file, a:mode)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdm=marker:fmr={{{,}}}
