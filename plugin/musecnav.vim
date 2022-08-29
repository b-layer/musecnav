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

" user settings {{{1

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
" max_title_len :
"   Section titles longer than this will be truncated when displayed in menu.
"   If the value is unset or 0 no truncation takes place. There is a hard
"   floor of 5 so a minimum of that many characters will be displayed
"   regardless of the value set here.
"
" use_popup :
"   If enabled Vim's popup window feature will be used for menus. Otherwise,
"   you'll get a slide up 'shelf'. If popup feature is available this is
"   enabled by default.
"
" TODO handle nvim. Use `if has('nvim')`

let s:settings_and_defaults = [
         \ ['display_mode', 'anc'],
         \ ['place_mark', '▶'],
         \ ['pop_col', 999],
         \ ['use_ad_synhi', 1],
         \ ['max_title_len', 50],
         \ ['use_popup', has('popupwin')]]

" s:musecnav_init_settings {{{1

function! s:musecnav_init_settings()
    let b:musecnav_config_vars = []

    " Globals are needed only if user wants to use a non-default value. Either
    " way all settings are saved as buffer locals allowing per-buffer
    " overrides and the side benefit of not polluting global namespace.
    for l:entry in s:settings_and_defaults
        let l:varname = 'b:musecnav_' . l:entry[0]
        exe 'let ' . l:varname . ' = "' .
                    \ get(g:, 'musecnav_' . l:entry[0], l:entry[1]) . '"'
        eval b:musecnav_config_vars->add(l:varname)
        "call Decho(printf("%s = %s", 'b:musecnav_' . l:entry[0], eval('b:musecnav_' . l:entry[0])))
    endfor

    if hlID("Popup") == 0
        call s:popup_hi_adjust()
    endif
endfunction

" s:musecnav_create_mappings {{{1
function! s:musecnav_create_mappings()
    nnoremap <script> <silent> <Plug>MusecnavNavigate :call musecnav#navigate()<CR>
    " aka soft reset
    nnoremap <script> <silent> <Plug>MusecnavReinit   :call musecnav#navigate(1)<CR>
    " aka hard reset
    nnoremap <script> <silent> <Plug>MusecnavReset    :call musecnav#navigate(2)<CR>
    " cycle through display modes
    nnoremap <script> <silent> <Plug>MusecnavNextLayout
                \ :call musecnav#util#rotate_disp_mode(1)<CR>
    nnoremap <script> <silent> <Plug>MusecnavPrevLayout
                \ :call musecnav#util#rotate_disp_mode(-1)<CR>

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

" musecnav_initialize {{{1
function! s:musecnav_initialize()
    call s:musecnav_init_settings()

    command! -buffer -nargs=0 MusecnavNextLayout call musecnav#util#rotate_disp_mode(1)
    command! -buffer -nargs=0 MusecnavPrevLayout call musecnav#util#rotate_disp_mode(-1)

    " <plugin> mappings only need to be created once
    if get(g:, 'musecnav_initialized', 0)
        return
    endif

    call s:musecnav_create_mappings()

    let g:musecnav_initialized = 1
endfunction

" s:popup_hi_adjust {{{1
" By default popups use PMenu/PMenuSel highlight group. In many themes
" those aren't set which means the default color: an awful, garish pink.
" Instead of overwriting PMenu*, though, we can override new-style popup
" colors using Popup/PopupSelected.
"
" Rather than assign some arbitrary colors I'm linking to existing  highlight
" groups, thus providing some consistency with the user's colorscheme.
"
function! s:popup_hi_adjust()
    if get(g:, 'musecnav_no_pop_hi', 0)
        return
    endif
    hi link Popup Statement
    hi link PopupSelected Todo
    "let b:temp = strftime('%c', localtime())
endfunction

" auto commands {{{1

" Certain syntax/colorscheme events have a negative impact on our popup menu.
" In particular, the selected row loses it's highlighting leaving the user
" guessing at what they're selecting. This is at least a partial mitigation.
augroup musecnav_syn
    autocmd!
    autocmd ColorScheme,Syntax * call s:popup_hi_adjust()
augroup END

" Activate for appropriate file types
augroup musecnav
    autocmd!
    autocmd FileType asciidoc,asciidoctor,markdown :call s:musecnav_initialize()
augroup END

" Config Undo {{{1
" TODO: complete undo of config
let &cpoptions = s:save_cpo
unlet s:save_cpo

