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

" s:musecnav_init_global_vars {{{1
function! s:musecnav_init_global_vars()
    " When enabled, try to continue processing document in the face of certain
    " non-conforming formats (ie. ignore offending lines). Otherwise, errors are
    " thrown in those situations, aborting processing. (WIP - don't expect any
    " miracles!)
    if !exists('g:musecnav_parse_lenient')
        let g:musecnav_parse_lenient = 0
    endif

    " When enabled, only '=' is allowed for designating AsciiDoc section headers.
    if !exists('g:musecnav_strict_headers')
        let g:musecnav_strict_headers = 1
    endif

    " In-menu indication of cursor position
    if !exists('g:musecnav_place_mark')
        let g:musecnav_place_mark = '▶'
    endif

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
    if exists('g:musecnav_initialized') && g:musecnav_initialized
        return
    endif

    call s:musecnav_init_global_vars()
    call s:musecnav_create_mappings()

    if !exists(":Navigate")
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

