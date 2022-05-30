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
" display_mode : 
"   Specifies the rules used to determine whether a section is visible or not
"   in the menu. The three settings from most to least restrictive 'selected'
"   'ancestor', and 'all'. (It's sufficient to use shortened names as long as 
"   the first three letters are present.)
"
"   The associated rules are:
"
"   [sel]
"        * All top level sections
"        * The selected section
"        * The selected section's ancestors, siblings and descendants
"
"   [anc]
"        * All top level sections
"        * The selected section
"        * All descendants of the selected section's top-level ancestor
"
"   [all]
"        * Entire hierarchy is always displayed
"
"   The default setting is 'anc'.
"
" place_mark : 
"   Character that designates the currently selected menu item.
"
" pop_col : 
"   Column number on which the popup menu will be positioned. If not specified
"   the popup will positioned to the far right.
"
" max_header_len : 
"   Section titles longer than this will be truncated. If the value is 0 no
"   truncation takes place.
"
" use_popup : 
"   If enabled Vim's popup window feature will be used for menus. Otherwise,
"   you'll get a slide up 'shelf'. If popup feature is available this is
"   enabled by default.
"
" TODO handle nvim. Use `if has('nvim')`


" TODO: change display_mode to 'anc'
let s:settings_and_defaults = [
         \ ['display_mode', 'anc'],
         \ ['place_mark', '▶'],
         \ ['pop_col', 999],
         \ ['use_ad_synhi', 1],
         \ ['max_header_len', 50],
         \ ['use_popup', has('popupwin')]]

" s:musecnav_init_settings {{{1

function! s:musecnav_init_settings()
    "let g:musecnav_config_vars = []

    " Globals are needed only if user wants to use a non-default value. Either
    " way all settings are saved as buffer locals allowing per-buffer
    " overrides and the side benefit of not polluting global namespace.
    for l:entry in s:settings_and_defaults
        let l:varname = 'b:musecnav_' . l:entry[0]
        exe 'let ' . l:varname . ' = "' .
                    \ get(g:, 'musecnav_' . l:entry[0], l:entry[1]) . '"'
        "eval g:musecnav_config_vars->add(l:varname)
        "call Decho(printf("%s = %s", 'b:musecnav_' . l:entry[0], eval('b:musecnav_' . l:entry[0])))
    endfor

    if !get(g:, 'musecnav_no_pop_hi')
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
        endif
    endif
endfunction

" s:musecnav_create_mappings {{{1
function! s:musecnav_create_mappings()
    nnoremap <script> <Plug>MusecnavNavigate    :call musecnav#navigate()<CR>
    " aka soft reset
    nnoremap <script> <Plug>MusecnavReinit      :call musecnav#navigate(1)<CR>
    " aka hard reset
    nnoremap <script> <Plug>MusecnavReset       :call musecnav#navigate(2)<CR>
    " cycle through display modes
    nnoremap <script> <Plug>MusecnavNextLayout  :call musecnav#CycleLayouts(1)<CR>
    nnoremap <script> <Plug>MusecnavPrevLayout  :call musecnav#CycleLayouts(-1)<CR>

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
        "if !hasmapto('<Plug>MusecnavNextLayout')
            "nmap <unique> <X> <Plug>MusecnavNextLayout
        "endi
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

    "command -buffer -nargs=1 MuSetDisplayMode call musecnav#SetDisplayMode(<f-args>)
    command -buffer -nargs=0 MusecnavNextLayout call musecnav#CycleLayouts(1)
    command -buffer -nargs=0 MusecnavPrevLayout call musecnav#CycleLayouts(-1)

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

