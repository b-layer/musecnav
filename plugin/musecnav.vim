" musecnav plugin file
" Language:    Asciidoc and Markdown markup

" Guard {{{1

if exists('g:loaded_musecnav')
  finish
endif
let g:loaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

" With this settings_and_defaults list of lists, the first element in each
" sub-list will be used with 'g:musecnav_' and 'b:musecnav_' prepended and
" we'll assign the global var to the buffer var if the former exists.
" Otherwise we'll assign the default value found in the second element of the
" same sub-list to the buffer variable.
"
" Some details about the settings...
"
" strict_headers : 
"   When enabled only '=' is allowed for designating AsciiDoc section headers.
"   (Normally, '#' is also allowed.)
"
" parse_lenient
"   When enabled, try to continue processing document in the face of certain
"   non-conforming formats (ie. ignore offending lines). Otherwise, errors are
"   thrown, aborting processing. (WIP. Don't expect any miracles!)
"
" place_mark : 
"   Character that designates the currently selected menu item.
"
" show_topsects_always : 
"   If enabled all of the current section's sibling sections will be shown in
"   the menu when it is opened. Otherwise, this only happens when the current
"   section is a top-level section.
"
" use_popup : 
"   If enabled Vim's popup window feature will be used for menus. Otherwise,
"   you'll get a slide up 'shelf'.
"
let s:settings_and_defaults = [
         \ ['parse_lenient', 0],
         \ ['strict_headers', 1],
         \ ['place_mark', '▶'],
         \ ['show_topsects_always', 1],
         \ ['use_popup', has('popupwin')]]

" s:musecnav_init_settings {{{1

function! s:musecnav_init_settings()
    " My way of avoiding an explosion of global variables. With these you only
    " need a global if you want to override the default value. Either way a
    " buffer local is used in the actual code.
    for l:entry in s:settings_and_defaults
        if exists('g:musecnav_' . l:entry[0])
            exe 'let b:musecnav_' . l:entry[0] '=' eval('g:musecnav_' . l:entry[0])
        else
            exe 'let b:musecnav_' . l:entry[0] '= "' . l:entry[1] . '"'
        endif
        "call Decho(printf("%s = %s", 'b:musecnav_' . l:entry[0], eval('b:musecnav_' . l:entry[0])))
    endfor

    " TODO: clean the rest of this up (use the preceding loop if possible)

    let g:musecnav_popup_title_idx = 1
    let g:musecnav_popup_titles = ['Markup Section Headers', 'Up/Down or 1-99 then <Enter>']

    let g:musecnav_popup_higroups = [
                \ ['Statement', 'Identifier', 'Constant', 'String'],
                \ ['Todo', 'WildMenu', 'Warning']]

    let g:musecnav_popup_modifiable = 0
    let g:musecnav_refresh_checks='bar,buflines,foo'  " headertext, headerloc

    if !exists('g:musecnav_popup_fixed_colors')
        " TODO: figure out hi
        " By default popups use PMenu/PMenuSel highlight group. In many themes
        " those aren't set which means the default color: an awful, garish pink.
        " Instead of overwriting PMenu*, though, we can override new-style popup
        " colors using Popup/PopupSelected.
        "hi Popup guifg=#3030ff guibg=black
        "hi PopupSelected guifg=black guibg=#a0a0ff
        if hlID("Popup") == 0
            hi link Popup Statement
            hi link PopupSelected Todo
            let g:musecnav_popup_modifiable = 1
        endif
    endif
endfunction

" s:musecnav_create_mappings {{{1
function! s:musecnav_create_mappings()
    noremap <script> <Plug>MusecnavNavigate  :call musecnav#navigate()<CR>
    " aka soft reset
    noremap <script> <Plug>MusecnavReinit    :call musecnav#navigate(1)<CR>
    " aka hard reset
    noremap <script> <Plug>MusecnavReset     :call musecnav#navigate(2)<CR>

    if !exists("g:no_plugin_maps") && !exists("g:no_musecnav_maps") &&
        \ exists("g:musecnav_use_default_keymap") && g:musecnav_use_default_keymap

        let s:musecnav_f_key = 'F7'
        if exists("g:musecnav_alt_fun_key")
            if g:musecnav_alt_fun_key =~? '^f\d\+$'
                let s:musecnav_f_key = g:musecnav_alt_fun_key
            else
                echoerr "Invalid value for g:musecnav_alt_fun_key:" g:musecnav_alt_fun_key
            endif
        endif

        if !hasmapto('<Plug>MusecnavNavigate')
            exe "nmap <unique> <" . s:musecnav_f_key . "> <Plug>MusecnavNavigate"
        endi
        if !hasmapto('<Plug>MusecnavReset')
            exe "nmap <unique> <C-" . s:musecnav_f_key . "> <Plug>MusecnavReset"
        endif
        if !hasmapto('<Plug>MusecnavReinit')
            exe "nmap <unique> <S-" . s:musecnav_f_key . "> <Plug>MusecnavReinit"
        endif
    endif
endfunction
" }}}

" musecnav_initialize and autocommand {{{1
function! s:musecnav_initialize()
    call s:musecnav_init_settings()

    " The remainder is mappings and commands so only needs to be run once
    if exists('g:musecnav_initialized') && g:musecnav_initialized
        return
    endif

    call s:musecnav_create_mappings()

    if !exists(":Navigate")
        " TODO: either document this or get rid of it
        command! -buffer -nargs=? -complete=function Navigate call musecnav#navigate(<f-args>)
    endif

    let g:musecnav_initialized = 1
endfunction

" Activate for appropriate file types
augroup musecnav
    autocmd!
    autocmd FileType asciidoc,asciidoctor,markdown call s:musecnav_initialize()
augroup END

" Config Undo {{{1
" TODO: complete undo of config
let &cpoptions = s:save_cpo
unlet s:save_cpo

