" musecnav plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{1

if exists('b:loaded_musecnav')
  finish
endif
let b:loaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

if !exists('b:musecnav_use_popup')
    " FYI popups introduced in 8.1 patch 1517
    let b:musecnav_use_popup = has('popupwin')
endif

if !exists('b:musecnav_data')
    let b:musecnav_data = {}
endif

if !exists('g:musecnav_popup_fixed_colors')
    " TODO: figure out hi
    " By default popups use PMenu/PMenuSel highlight group. In many themes
    " those aren't set which means the default color: an awful, garish pink.
    " Instead of overwriting PMenu*, though, we can override new-style popup
    " colors using Popup/PopupSelected.
    "hi Popup guifg=#3030ff guibg=black
    "hi PopupSelected guifg=black guibg=#a0a0ff
    hi link Popup Statement
    hi link PopupSelected Todo
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

" TODO: complete undo of config
"
let &cpoptions = s:save_cpo
unlet s:save_cpo

