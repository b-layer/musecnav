let s:save_cpo = &cpoptions
set cpoptions&vim

" REDO: We should use a stateful object so some of the logic in
" find_ad_section can be eliminated. Some things to initialize only once per
" scan:
"
" * forwards/backwards (so we can have fixed search flags)
" * top section level (won't have to build so much of the regex up each time)
" * header mark (we regressed to only allowing '=' for now)

" Patterns to match markup for AsciiDoc setext headers, levels 0-4
let s:adsetextmarks = ['=', '\-', '~', '\^', '+']
" Same thing without escaping and squashed into a string (for char compares)
let s:adsetextmarkstr = s:adsetextmarks->join("")->substitute('\', '', 'g')

" static pattern string for AD anchors
let s:anchor = '%(\[\[[^[\]]+]])'

let s:adatxmark = '\='

" Function s:find_ad_section {{{1
"
" Find next/previous AsciiDoc(tor) section. See s:find_section() for details
" on the externals.
func! s:find_ad_section(bkwd) abort
"    call Dfunc("find_ad_section(".a:bkwd.")")

    let l:skipflags = 'W'
    if a:bkwd
        let l:skipflags .= 'b'
    endif
    " Do not use l:flags when we have a false positive and want to proceed to
    " the next match. To skip over current match use, naturally, l:skipflags
    let l:flags = l:skipflags . 'cs'

    " Build complex regex to do best match of atx or setext headers
    " TODO: remove first branch
    if get(b:, "musecnav_firstseclevel", 0) && !get(g:, "musecnav_dev_mode", 0)
        let l:hdrmarks_a = repeat(s:adatxmark, b:musecnav_firstseclevel) . '+'
        " Form regex atom from sublist of the AD setext markup patterns.
        " Sublist offset is determined by the lowest header level in the
        " document.
        let l:hdrmarks_s = join(s:adsetextmarks[b:musecnav_firstseclevel:], "")
    else
        let l:hdrmarks_a = s:adatxmark . '*'
        let l:hdrmarks_s = s:adsetextmarks->join("")
    endif
    let l:patt_a = '^' . l:hdrmarks_a . '\zs' . s:adatxmark . '\s+\S'

    let l:patt_s = '^\zs\w.+\ze\n[' . l:hdrmarks_s . ']+$'
    let l:patt = '\v%(' . l:patt_a . '|' . l:patt_s . ')'
"    call Decho("Section header pattern: " . l:patt)

    " Iterate over search results and extracted data points and do some
    " additional checks until we find something matching all our criteria.
    let l:matchline = search(l:patt, l:flags)
    while l:matchline > 0
"        call Decho("Checking candidate header on line " . l:matchline)
        unlet! l:header
        let l:curpos = getcurpos()
        let l:matchcol = l:curpos[2]

        " Determine the header type
        if l:matchcol != 1
            let l:issetext = 0
        else
            let l:setextline = search('\v' . l:patt_s, 'cn')
"            call Decho("setext check: "
                        \ . musecnav#util#struncate(getcurpos()[1:2])
                        \ . " :: " . l:setextline . " => " . l:matchline)
            let l:issetext = (l:setextline == l:matchline)
        endif
"        call Decho("header type: " . (l:issetext ? "setext" : "atx"))

        " Let's make sure we really have a section header...
        try
            " There are multiple things that can precede a regular section header
            " besides a blank line such as a comment '//' or an anchor '[[foo]]'.
            " The one exception is '[discrete]'. This marks a section header
            " outside of the normal flow and we ignore them.
            let l:linem1 = l:matchline - 1
            if prevnonblank(l:linem1) == l:linem1 && getline(l:linem1) =~? '^\[discrete\]\s*$'
                throw "Invalid: [discrete] headers aren't tracked"
            endif

            let l:syn = ""

            " If setext header type make sure the underline has valid length
            if l:issetext
                let l:header = getline(l:matchline)
                let l:line1len = len(l:header)
                let l:line2len = len(getline(l:matchline+1))
                if l:line1len < (l:line2len - 3) || l:line1len > (l:line2len + 3)
                    throw "Invalid: underline length not ±3 title length"
                endif

                " An underline like '----' is highly suspect as it looks more
                " like a block boundary. Even if synhi is not enabled we're
                " checking it here.
                let l:syn = synIDattr(synID(l:matchline, 1, 0), "name")
                if l:line2len == 4 && l:syn && l:syn =~ "asciidoc.*Block"
                    throw "Invalid: it's an Asciidoc block of some kind"
                endif
            endif

            " Check whether syntax highlighting agrees. synID stuff is costly
            " so if it ran in the preceding block don't run it again!
            if b:musecnav_use_ad_synhi
                if !l:syn
                    let l:syn = synIDattr(synID(l:matchline, 1, 0), "name")
                endif
                if l:syn !~ "asciidoc.*Title"
                    throw "Invalid: wrong syntax highlight group"
                endif
            endif

        catch /^Invalid/
"            call Decho(v:exception)
            " Use skipflags only or we'll keep hitting the current match
            let l:matchline = search(l:patt, l:skipflags)
            continue
        endtry

        " Valid header. Clean it up...
        if !exists('l:header')
            let l:header = getline(l:matchline)
        endif
"        call Decho("Valid header raw value: " . l:header)

        " Exclude ID/anchor element preceding or following section name if
        " present. (These are strings enclosed in double square braces.)
        let l:anch1 = '\v^' . s:adatxmark . '*\s*\zs' . s:anchor . '?\ze\S+'
        let l:anch2 = '\v\s*' . s:anchor . '\s?$'
        let l:header = l:header
            \ ->substitute(l:anch1, '', '')->substitute(l:anch2, '', '')
"        call Decho("Header after anchor strip: " . l:header)

        " Extract section level/depth based on header type
        if l:issetext
            let l:setextmark = getline(l:matchline+1)[0]
"            call Decho("l:setextmark is " . l:setextmark)
            let l:matchlevel = stridx(s:adsetextmarkstr, l:setextmark)
"            call Decho("...which gives us l:matchlevel " . l:matchlevel)
        else
            let l:matchlevel = l:matchcol - 1
"            call Decho("l:matchlevel is " . l:matchlevel)
            " Throw out the markup
            let l:header = l:header[l:matchlevel+2:]
"            call Decho("...which gives us l:header " . l:header)
        endif

"        call Decho("Match: [".l:matchline . "," . l:matchcol . ","
                    \ . l:matchlevel . "," . l:header . "]")

"        call Dret("find_ad_section returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:header]
    endwhile

"    call Dret("find_ad_section no match")
    return []
endfunc

" Function s:find_md_section {{{1
"
" Find next/prev Markdown section. See find_section() for details on the
" externals.
"
" Markdown detection starts with regular expressions but those matches are
" rejected if the syntax highlighting disagrees. We recognize both the default
" syntax that comes with Vim and that of the popular plugin 'vim-markdown' The
" relevant part of its highlighting works almost the same as native Vim's. It
" just uses htmlH{1..6} as group names instead of markdownH{1..6}.
func! s:find_md_section(bkwd) abort
"    "    call Dfunc("find_md_section(".a:bkwd.")")

    let l:skipflags = 'W'
    if a:bkwd
        let l:skipflags .= 'b'
    endif
    " Do not use l:flags when we have a false positive and want to proceed to
    " the next match. To skip over current match use, naturally, l:skipflags
    let l:flags = l:skipflags . 'cs'

    let l:patt = '\v^%(\zs.+\ze\n[-=]+|#{1,6}\zs.{-}\ze#*\s*)$'
    let l:matchline = search(l:patt, l:flags)

    while l:matchline > 0
        let l:curpos = getcurpos()
        let l:matchcol = l:curpos[2]
        let l:issetext = l:matchcol == 1

        try
            " try/catch is overkill since we have only one check but this
            " mirrors the AD function
            let l:hiname = synIDattr(synID(l:matchline, l:matchcol, 0), "name")
            if l:hiname !~# '^markdownH\d$' && l:hiname !~# '^htmlH\d$'
                throw "Invalid: wrong syntax highlight group"
            endif
        catch /^Invalid/
"            call Decho(v:exception)
            let l:matchline = search(l:patt, l:skipflags)
            continue
        endtry

        " Valid header. Extract section level/depth from synhi name.
        let l:header = getline(".")
"        call Decho("Valid header in raw form: " . l:header)

        let l:matchlevel = matchstrpos(l:hiname, '\d')[0] + 0
"        call Decho("l:matchlevel is " . l:matchlevel)

        " Extract section level/depth based on header type
        if ! l:issetext
            " Throw out the markup
            let l:header = l:header[l:matchlevel+1:]
"            call Decho("...which gives us l:header " . l:header)
        endif

"        call Decho("Match: [".l:matchline . "," . l:matchcol . ","
                    \ . l:matchlevel . "," . l:header . "]")

"        call Dret("find_md_section - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:header]
    endwhile

"    call Dret("find_md_section - no match")
    return []
endfunc

" Function musecnav#search#find_section {{{1
"
" Find section header closest to the cursor and move the cursor to its
" location. Returns a list containing:
"
"   [matchline, matchcol, matchlevel, header]
"
" If no headers are found the list will be empty.
"
" Optional param
"   bkwd : if set then search before the cursor rather than after
func! musecnav#search#find_section(...) abort
"    call Dfunc("find_section(" . musecnav#util#struncate(a:000) . "), curpos: "
                \ . string(getcurpos()[1:2]))

    let l:bkwd = 0
    if a:0 && a:1
        let l:bkwd = 1
    endif

    let l:ret = get(s:ft_sect_funcs, &ft)(l:bkwd)

    call cursor(0, 999)
"    call Dret("find_section")
    return l:ret
endfunc

" }}}

" maps 'filetype' to the correct section search function
let s:ft_sect_funcs = {
      \ 'asciidoc': function('s:find_ad_section'),
      \ 'markdown': function('s:find_md_section'),
      \ }

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdc=3:fdm=marker:fmr={{{,}}}
