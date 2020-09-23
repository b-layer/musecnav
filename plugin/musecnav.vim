" musecnav plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{1

if exists('g:loaded_musecnav')
  finish
endif
let g:loaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

"  user-visible (theoretically) global settings {{{2

" When enabled, try to continue processing document in the face of certain
" non-conforming formats (ie. ignore offending lines). Otherwise, errors are
" thrown in those situations, aborting processing. (WIP - don't expect any
" miracles!)
let g:musecnav_parse_lenient = 0

" In-menu indication of cursor position 
let g:musecnav_place_mark = '▶'

let g:musecnav_popup_title_idx = 1
let g:musecnav_popup_titles = ['Markup Section Headers', 'Up/Down or 1-99 then <Enter>']

let g:musecnav_popup_higroups = [
            \ ['Statement', 'Identifier', 'Constant', 'String'],
            \ ['Todo', 'WildMenu', 'Warning']]

let g:musecnav_popup_modifiable = 0

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

let g:musecnav_refresh_checks='bar,buflines,foo'  " headertext, headerloc

" User Commands {{{1

if !exists(":Navigate")
    command! -buffer -nargs=? -complete=function Navigate call musecnav#navigate(<f-args>)
endif

" Mapped Keys {{{1

noremap <script> <Plug>MusecnavNavigate  :call musecnav#navigate()<CR>
" aka soft reset
noremap <script> <Plug>MusecnavReinit    :call musecnav#navigate(1)<CR>
" aka hard reset                        
noremap <script> <Plug>MusecnavReset     :call musecnav#navigate(2)<CR>

if !exists("no_plugin_maps") && !exists("no_musecnav_maps") &&  
    \ exists("musecnav_use_default_keymap") && musecnav_use_default_keymap

    if !hasmapto('<Plug>MusecnavNavigate')
        nmap <unique> <F7> <Plug>MusecnavNavigate
    endif
    if !hasmapto('<Plug>MusecnavReset')
        nmap <unique> <C-F7> <Plug>MusecnavReset
    endif
    if !hasmapto('<Plug>MusecnavReinit')
        nmap <unique> <S-F7> <Plug>MusecnavReinit
    endif
    if !hasmapto('<Plug>MusecnavReset')
    endif
endif

" Activate only for correct file types
augroup musecnav
    autocmd!
    autocmd FileType asciidoc,markdown call musecnav#activate()
augroup END

" Config Undo {{{1
" TODO: complete undo of config
let &cpoptions = s:save_cpo
unlet s:save_cpo

