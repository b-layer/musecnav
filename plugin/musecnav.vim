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

" User Commands {{{1

if !exists(":Navigate")
    command! -buffer -nargs=? -complete=function Navigate call musecnav#navigate(<f-args>)
endif

" Mapped Keys {{{1

noremap <script> <Plug>MuSecNavNavigate  :call musecnav#navigate()<CR>
" aka soft reset
noremap <script> <Plug>MuSecNavReinit    :call musecnav#navigate(1)<CR>
" aka hard reset                        
noremap <script> <Plug>MuSecNavReset     :call musecnav#navigate(2)<CR>

if !exists("no_plugin_maps") && !exists("no_musecnav_maps") &&  
    \ exists("musecnav_use_default_keymap") && musecnav_use_default_keymap

    if !hasmapto('<Plug>MuSecNavNavigate')
        nmap <unique> <F7> <Plug>MuSecNavNavigate
    endif
    if !hasmapto('<Plug>MuSecNavReset')
        nmap <unique> <C-F7> <Plug>MuSecNavReset
    endif
    if !hasmapto('<Plug>MuSecNavReinit')
        nmap <unique> <S-F7> <Plug>MuSecNavReinit
    endif
    if !hasmapto('<Plug>MuSecNavReset')
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

