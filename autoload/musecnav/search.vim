let s:save_cpo = &cpoptions
set cpoptions&vim

" script local vars {{{1
" Patterns to match markup for AsciiDoc setext headers, levels 0-4
let s:adsetextmarks = ['=', '\-', '~', '\^', '+']
" Same thing without escaping and squashed into a string (for char compares)
let s:adsetextmarkstr = s:adsetextmarks->join("")->substitute('\', '', 'g')

" static pattern string for AD anchors
let s:anchor = '%(\[\[[^[\]]+]])'

" recognized highlight groups for AD section headers
let s:ad_title_hi_patt = '\vasciidoc(tor(H\d|SetextHeader)|...LineTitle)'

let s:search = {}

" s:search.new() {{{1
function! s:search.new(rootlevel, reverse=v:false)
    let newSearch = copy(self)
    let newSearch.rootlevel = a:rootlevel
    let newSearch.reverse = a:reverse

    let newSearch.adatxmark = ''

    " maybe
    " newSearch.line : where search left off

    return newSearch
endfunction

" Function s:search.to_string {{{1
function! s:search.to_string() dict abort
    return printf("header mark: %s, root level: %d, reverse?: %s\n",
                \ self.adatxmark, self.rootlevel, self.reverse)
endfunction

" Function s:search.find_first_ad_header {{{1
"                                                  find_first_ad_header {{{2
" Find the first header/title in an Asciidoc document. It could be a section
" or it could be a document header.
"
" The following shows the basic makeup of a document header. All of the lines
" within are optional except document title (the line beginning with '=').
"
" ----------------------------
"    0 or more blank lines
"    <header start>
"    attribute entries and comments (not recommended)
"    = Level 0 Document Title ('#' also valid if not AD + strict headers)
"    author and revision info
"    attribute entries and comments
"    <header end>
"
"    == Level 1 Section Title ('##' also valid if not AD + strict headers)
" ----------------------------
"
" The only content permitted above the document title are blank lines, comment
" lines and document-wide attribute entries. If the document title is present
" no blank lines are allowed in the rest of the header as the first blank line
" signifies the end of the header and beginning of the first section.
"
" <header start> and <header end> are not included text, just symbols.
"
" Setext format, i.e. title with a series of '='s on the next line, is allowed
" (though highly discouraged by AD folks).
"
" Note that a document header is optional for all doctypes except manpage
" which requires it. (Though we're not enforcing anything here.)
"
"
" Return value of this function is a list containing information about the
" first document or section header seen. The list looks like this:
"
"   [line_number, header_level, header_text, header_mark]
"
" The title will be cleaned of any markup before it's returned.
"
" The header_mark indicates what character was used to mark an atx header, '='
" or '#'. If it is a setext header an empty string will be returned in this
" position.
"
" Examples:
"   [3, 0, 'Title'] - doc header preceded by 2 lines of comments, attributes,
"                     and/or blanks
"   [1, 1, 'Sec Head'] - section header
"                                                                          }}}
function! s:search.find_first_ad_header()
"    call Dfunc("search.find_first_ad_header()")
    let l:iscomment = 0
    let l:lineno = 1
    " scan up to 50 lines; ignore anything allowed by the spec
    while l:lineno < 50
        let l:line = getline(l:lineno)
        let l:lineno += 1
        if l:line =~ '^/\{4,}$'
            let l:iscomment = !l:iscomment
            continue
        endif
        if l:iscomment
            continue
        endif
        " check for NOT comment or attribute or whitespace-only/blank line
        if l:line !~ '\v(^//)|(^\s*$)|(^:[^:]+:\s+\S)'
            " found something
            break
        endif
    endwhile

    if l:lineno == 50
"        call Dret("search.find_first_ad_header :: MU21")
        throw "MU21 - expected a doc/section header in first 50 lines!"
    endif

"    call Decho("First header? " . l:line)
    let l:hdrmark = '[#\=]'
    if l:line =~ '\v^' . l:hdrmark . '+\s+\S'
        " title: single-line type
        let self.adatxmark = '\' . l:line[0]
"        call Decho("AD header mark: " . self.adatxmark)

        let l:level = match(l:line,
                    \ '\v^' . self.adatxmark . '*\zs' . self.adatxmark . '\s+\w')
        let l:ret = [l:lineno-1, l:level, l:line[l:level+2:], self.adatxmark]

        " whatever header char was first used is expected to be used
        " throughout the document
"        call Dret("search.find_first_ad_header :: " . musecnav#util#sect_attrs_str(l:ret))
        return l:ret
    endif

    " now it's either a valid setext header or failed search
    let l:len = len(l:line)
    if l:len < 3
"        call Dret("search.find_first_ad_header :: not found")
        throw "MU21 - no header found"
    endif

    let l:nextline = getline(l:lineno)
    if l:nextline !~ '[-=]\{3,}'
"        call Dret("search.find_first_ad_header :: not found")
        throw "MU22 - no header found [missing setext underline]"
    endif

    let l:nextlen = len(l:nextline)
    if l:len < (l:nextlen - 3) || l:len > (l:nextlen + 3)
"        call Dret("search.find_first_ad_header :: not found")
        throw "MU23 - no header found [underline doesn't match length]"
    endif

    " opening header is setext type
    if l:nextline =~ '^='
        let l:level = 0
    else
        let l:level = 1
    endif

    let l:ret = [l:lineno-1, l:level, l:line, '']
"    call Dret("search.find_first_ad_header :: " . musecnav#util#sect_attrs_str(l:ret))
    return l:ret
endfunction

" Function s:search.find_ad_section {{{1
"
" Find next/previous AsciiDoc(tor) section. See s:find_section() for details
" on the externals.
function! s:search.find_ad_section(reverse=v:false) abort
"    call Dfunc("search.find_ad_section(".a:reverse.")")
    let l:adatxmark = empty(self.adatxmark) ? '[#\=]' : self.adatxmark

    " Build complex regex to do best match of atx or setext headers
    let l:hdrmarks_s = join(s:adsetextmarks[self.rootlevel:], "")
    let l:hdrmarks_a = repeat(l:adatxmark, max([1, self.rootlevel]))
                \ . (self.rootlevel > 0 ? '+' : '*')

    let l:patt_a = '^' . l:hdrmarks_a . '\zs' . l:adatxmark . '\s+\S'
    let l:patt_s = '^\zs\w.+\ze\n[' . l:hdrmarks_s . ']+$'

    let l:patt = '\v%(' . l:patt_a . '|' . l:patt_s . ')'
"    call Decho("Section header pattern: " . l:patt)

    let l:retryflags = a:reverse ? 'Wb' : 'W'
    let l:flags = l:retryflags . 'cs'

    " Iterate over search results and extracted data points and do some
    " additional checks until we find something matching all our criteria.
    let l:matchline = search(l:patt, l:flags)
    while l:matchline > 0
"        call Decho("Check [" . l:matchline . "] " . getline(l:matchline))
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
            " There are multiple things that can precede a regular section
            " header besides a blank line such as a comment '//' or an anchor
            " '[[foo]]'. The one exception is '[discrete]'. This designates a
            " special header, not a regular section, and we ignore them.
            let l:linem1 = l:matchline - 1
            if prevnonblank(l:linem1) == l:linem1 && getline(l:linem1) =~? '^\[discrete\]\s*$'
                throw "Invalid: [discrete] headers aren't tracked"
            endif

            let l:hiname = ""

            " If setext header type make sure the underline has valid length
            " (I don't think this actually complies with current AD rules.)
            if l:issetext
                let l:header = getline(l:matchline)
                let l:line1len = len(l:header)
                let l:line2len = len(getline(l:matchline+1))
                if l:line1len < (l:line2len - 3) || l:line1len > (l:line2len + 3)
                    throw "Invalid: underline length not ±3 title length"
                endif

                " TODO: perhaps we try one more thing before synhi: if length
                " is 4 and preceding line is nowhere near that, reject it.
                " (Note, though, that 4 is the minimum valid length for
                " delimiters. Should we try to detect longer ones with some
                " semi-intelligent algorithm based on preceding line length?)
                " Anything else we can do short of looking backwards and such?

                " An underline like '----' is highly suspect as it looks more
                " like a block boundary.
                if v:false && b:musecnav_use_ad_synhi
                    let l:hiname = synIDattr(synID(l:matchline, 1, 0), "name")
                    if l:line2len == 4 && l:hiname && l:hiname =~ "asciidoc.*Block"
                        throw "Invalid: it's an Asciidoc block of some kind"
                    endif
                endif
            endif

            " Check whether syntax highlighting agrees. synID stuff is costly
            " so if it ran in the preceding block don't run it again!
            if b:musecnav_use_ad_synhi
                if !l:hiname
                    let l:hiname = synIDattr(synID(l:matchline, 1, 0), "name")
                endif
                if l:hiname !~? s:ad_title_hi_patt
                    throw "Invalid: wrong syntax highlight group"
                endif
            endif

        catch /^Invalid/
"            call Decho(v:exception)
            " Use retry flags only or we'll keep hitting the current match
            let l:matchline = search(l:patt, l:retryflags)
            continue
        endtry

        " Valid header. Clean it up...
"        call Decho("Header is valid")
        if !exists('l:header')
            let l:header = getline(l:matchline)
        endif

        " Exclude ID/anchor element preceding or following section name if
        " present. (These are strings enclosed in double square braces.)
        let l:anch1 = '\v^' . l:adatxmark . '*\s*\zs' . s:anchor . '?\ze\S+'
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
            " Do we want to do this? Make it configurable?
            if empty(self.adatxmark)
                let self.adatxmark = '\' . l:header[0]
"                call Decho("Fixed atx header mark as: " . self.adatxmark)
            endif

            let l:matchlevel = l:matchcol - 1
"            call Decho("l:matchlevel is " . l:matchlevel)
            " Throw out the markup
            let l:header = l:header[l:matchlevel+2:]
"            call Decho("...which gives us l:header " . l:header)
        endif

"        call Decho("Match: [".l:matchline . "," . l:matchcol . ","
                    \ . l:matchlevel . "," . l:header . "]")

"        call Dret("search.find_ad_section returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:header]
    endwhile

"    call Dret("search.find_ad_section no match")
    return []
endfunction

" Function s:search.find_md_section {{{1
"
" Find next/prev Markdown section. See find_section() for details on the
" externals.
"
" Markdown detection starts with regular expressions but those matches are
" rejected if the syntax highlighting disagrees. We recognize both the default
" syntax that comes with Vim and that of the popular plugin vim-markdown. The
" relevant part of its highlighting works almost the same as native Vim's. It
" just uses htmlH{1..6} as group names instead of markdownH{1..6}.
function! s:search.find_md_section(reverse=v:false) abort
"    "    call Dfunc("find_md_section(".a:reverse.")")
    let l:retryflags = a:reverse ? 'Wb' : 'W'
    let l:flags = l:retryflags . 'cs'

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
            if l:hiname !~? '^markdownH\d$' && l:hiname !~? '^htmlH\d$'
                throw "Invalid: unrecognized syntax highlight group"
            endif
        catch /^Invalid/
"            call Decho(v:exception)
            let l:matchline = search(l:patt, l:retryflags)
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
endfunction

" Function s:search.find_section {{{1
"
" Find section header closest to the cursor and move the cursor to its
" location. Returns a list containing:
"
"   [matchline, matchcol, matchlevel, header]
"
" If no headers are found the list will be empty.
function! s:search.find_section() abort
"    call Dfunc("find_section(), curpos: " . string(getcurpos()[1:2]))

    if b:musecnav.adtype
        let l:ret = self.find_ad_section()
    else
        let l:ret = self.find_md_section()
    endif

    " Move the cursor to the far right (same line)
    call cursor(0, 999)
"    call Dret("find_section")
    return l:ret
endfunction

" Function musecnav#search#init {{{1
"
" Initializes and returns a search object which is used to scan for sections
" in the buffer.
"
function! musecnav#search#init(reverse=v:false) abort
    let l:pos = getpos('.')

    try
        call setpos('.', [0, 1, 1, 0])

        if b:musecnav.adtype
            let l:first = s:search.find_first_ad_header()
        else
            let l:first = s:search.find_md_section()
        endif

        if empty(l:first)
            throw "MU24 - failed to detect first header"
        endif

        return s:search.new(first[1], a:reverse)
    finally
        call setpos('.', l:pos)
    endtry
endfunction
" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdm=marker:fmr={{{,}}}
