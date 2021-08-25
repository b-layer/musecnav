" musecnav autoload plugin file
" Language:    Asciidoc and Markdown markup

" Initialization {{{1

if exists('g:autoloaded_musecnav')
  finish
endif
let g:autoloaded_musecnav = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

scriptencoding utf-8

let g:musecnav_version = 111

" 1: saves menu text in a variable (b:musecnav_menu_dump)
let s:debugmode = 0

" Patterns to match markup for AsciiDoc setext headers, levels 0-4
let s:adsetextmarks = ['=', '\-', '~', '\^', '+']
" Same thing without escaping and squashed into a string (for char compares)
let s:adsetextmarkstr = s:adsetextmarks->join("")->substitute('\', '', 'g')

" In-menu header display modes, associated with musecnav_display_mode
let s:displaymodes = ['all', 'top', 'none']

" static pattern string for AD anchors
let s:anchor = '%(\[\[[^[\]]+]])'

" Functions {{{1

" Script-local Functions {{{2

" Function s:InitHeaderInfo {{{3
"
" Process title if it exists. Set a document name. Find first section header.
func! s:InitHeaderInfo()
"    call Dfunc("InitHeaderInfo()")
    let b:musecnav_firstsecheader = 0
    let b:musecnav_hasdocheader = 0
    let b:musecnav_docname = expand('%')

    let l:curpos = getcurpos()

    if &ft ==? 'asciidoc'
        " Look for a doc header (level 0)
"        call Decho("Searching for AD doc header/title")
        " [line number, header level, title]
        let l:firstheader = s:FindFirstHeader()
        if len(l:firstheader) == 0
            throw "MU16: Can't find opening document or section header"
        endif
        let l:lvl = l:firstheader[1]
        if l:lvl == 0
            " It's a doc header
            let b:musecnav_docheader = l:firstheader
"            call Decho("AD first (doc) header info: " . s:Struncate(b:musecnav_docheader))
            let b:musecnav_hasdocheader = 1
            let b:musecnav_docname = b:musecnav_docheader[2]
            " HAS to be 1 or it's invalid
            let b:musecnav_firstseclevel = 1
        else
            " section header
            let b:musecnav_firstsecheader = l:firstheader
            let b:musecnav_firstseclevel = l:lvl
"            call Decho("AD first (sec) header info: " . s:Struncate(b:musecnav_firstsecheader))
        endif
    endif

    if !b:musecnav_firstsecheader
        let b:musecnav_firstsecheader = s:FindFirstSecHeader()
        let b:musecnav_firstseclevel = b:musecnav_firstsecheader[1]
    endif

    call setpos('.', l:curpos)

    if b:musecnav_firstsecheader == [0, 0, 0, 0]
        throw "MU19: Couldn't find a section header!"
    endif

"    call Decho("Doc's first header: " . s:headInfoStr(b:musecnav_firstsecheader, 0))
    if &ft ==? 'asciidoc'
        if b:musecnav_hasdocheader && b:musecnav_firstseclevel != 1
            throw "MU18: book doctype initial section must be level 1"
        endif
    endif
"    call Dret("InitHeaderInfo - normal exit")
endfunction

" Function s:Navigate {{{3
"                                                                Navigate {{{4
" Generates section header hierarchy if necessary then displays the navigation
" menu.
"                                                                          }}}
func! s:Navigate() abort
"    call Dfunc("Navigate()")

    call s:InitSectionTree()
    let l:numsects = len(b:musecnav_data.sections)
"    call Decho("After section tree init we have ".l:numsects." sections")
    if l:numsects == 0
        echohl WarningMsg | echo "No headers identified! Aborting." | echohl None
"        call Dret("Navigate - abort")
        return
    endif

    " If cursor has moved since last menu selection determine what section it
    " currently resides in and make that the new "current section" before
    " building the menu.
    let l:currline = getcurpos()[1]
"    call Decho("last line: ".b:musecnav_data.selheadline ." curr line: ".l:currline)

    if b:musecnav_data.selheadline != l:currline
        if l:currline <= b:musecnav_firstsecheader[0]
            " Move cursor to documents first doc or section header
            if b:musecnav_hasdocheader
"                call Decho("Cursor precedes first sec head. Use doc header.")
                let b:musecnav_data.level = b:musecnav_docheader[1]
                let b:musecnav_data.selheadline = b:musecnav_docheader[0]
            else
"                call Decho("Cursor precedes first sec head. Use it.")
                let b:musecnav_data.level = b:musecnav_firstsecheader[1]
                let b:musecnav_data.selheadline = b:musecnav_firstsecheader[0]
            endif
        else
            " Search b/w for a sec header. First found is current section.
            call cursor(0, 999)
            let [l:headerline, _, l:level, _] = s:FindPrevSection()
    
            if l:headerline == 0
"                call Dret("Navigate - fatal MU20")
                throw "MU20: No section header found above cursor line"
            elseif l:headerline > l:currline
"                call Dret("Navigate - fatal MU21")
                throw "MU21: Backwards search ended up below cursor line!"
            endif
    
            let b:musecnav_data.level = l:level
"            call Decho("Cursor moved to level ".b:musecnav_data.level." section starting on line ".l:headerline)
            let b:musecnav_data.selheadline = l:headerline

            " move cursor back to starting point (mark ' set by search())
            call cursor(getpos("''")[1:])
        endif
    endif

    " For non-popup menu a continuous draw-menu/get-input/process-input cycle
    " happens here. Loop is exited only upon user entering return alone.
    " For popup menu we break out of the loop immediately after menu is drawn
    " since popups are handled in separate threads and thus there's no reason
    " to maintain this loop. ProcessSelection will be called from the popup
    " callback function.
    while (1)
        " reset the digit entry 'buffer'
        let b:musecnav_select_buf = -1

        let l:choice = s:DrawMenu()
        if !len(l:choice) || l:choice < 0
            break
        endif
        call s:ProcessSelection(-1, l:choice)
    endwhile

"    call Dret("Navigate - normal exit")
endfunc

" Function s:InitSectionTree {{{3
"                                                         InitSectionTree {{{4
" Build the section header hierarchy.
"
" 1. Change in number of buffer lines? Set rebuild flag.
" 2. If not rebuild and we already have data just return.
" 3. Initialize the primary data structure. (incl. selheadline & level to 0)
" 4. winsaveview()
" 5. Move cursor to beginning of file (or line specified in optional param)
" 6. WalkSections(firstseclevel, '')
" 7. winrestview()
"
" Optional arg:
"   a:1 - starting line number for scan instead of default 1
"                                                                          }}}
func! s:InitSectionTree(...) abort
"    call Dfunc("InitSectionTree(".s:Struncate(a:000).")")
    let l:lineno = 1
    if a:0 > 0
        let l:lineno = a:1
    endif

    let l:lastlineno = line('$')
    let l:rebuild = 0
    if exists('b:musecnav_data.buflines') && b:musecnav_data.buflines != l:lastlineno
"        call Decho("Number of buffer lines changed. Rescanning.")
        let l:rebuild = 1
        "if index(split(b:musecnav_refresh_checks, ','), 'buflines') >= 0
        "    let l:rebuild = 1
        "    let b:musecnav_data.buflines = l:lastlineno
        "else
        "    echohl WarningMsg
        "    echo "Number of buffer lines changed. Navigation may be affected."
        "    echohl None
        "endif
    endif
    let b:musecnav_data.buflines = l:lastlineno

    " Return if tree already built unless forced b/c file contents changed
    " or param flag was set (usually due to Ctrl-F7)
    if exists('b:musecnav_data.sections') && !l:rebuild
"        call Dret("InitSectionTree - tree already built")
        return 0
    endif

    echom "Building section header tree..."
    if l:rebuild || !exists("b:musecnav_data.selheadline")
        let b:musecnav_data.selheadline = 0
        let b:musecnav_data.level = 0
        " Data from last call to menuizetree function
        let b:musecnav_data.last_menu_data = []
"        " Most recent display menu lines. Unused but for a Decho msg or two.
        let b:musecnav_data.last_menu_text = []
    endif

    " before we move the cursor...
    let l:view = winsaveview()

    call setpos('.', [0, l:lineno, 1])
    let b:musecnav_data.level_map = {}
    let b:musecnav_data.ancestor_map = {}

    let b:musecnav_data.sections = s:WalkSections(b:musecnav_firstseclevel, "")
    let b:musecnav_data.currparent = []
    let b:musecnav_data.filename = expand('%')

    call winrestview(l:view)

    echom "done"
    redraws
"    call Dret("InitSectionTree - result: ".s:Struncate(b:musecnav_data.sections))
    return 1
endfunc

" Function s:FindNextSection (and supporting) {{{3

"                                                    NextSection_Asciidoc {{{4
"
" Find next AsciiDoc(tor) section. Also see s:FindNextSection()
"
" Asciidoc allows atx-style headers. The preferred character for designating
" such headers is '=' but Asciidoc also supports Markdown-style '#'...
"
"     == Valid header in Asciidoc
"     ## Valid header in Asciidoc and Markdown
"
" These are known as asymmetric headers. Also allowed are symmetric atx
" headers which repeat the opening marker characters at the end of the line.
"
"     == Valid symmetric atx header in Asciidoc ==
"
" Two-line or 'setext' headers are also supported as described in this excerpt
" from Asciidoc's documentation.
"
" BEGIN excerpt
"
" 11.1. Two line titles
"
" A two line title consists of a title line, starting hard against the left
" margin, and an underline. Section underlines consist a repeated character
" pairs spanning the width of the preceding title (give or take up to two
" characters):
"
" The default title underlines for each of the document levels are:
"
" Level 0 (top level):     ======================
" Level 1:                 ----------------------
" Level 2:                 ~~~~~~~~~~~~~~~~~~~~~~
" Level 3:                 ^^^^^^^^^^^^^^^^^^^^^^
" Level 4 (bottom level):  ++++++++++++++++++++++
"
" Examples:
"
" Level One Section Title
" -----------------------
"
" Level 2 Subsection Title
" ~~~~~~~~~~~~~~~~~~~~~~~~
"
" END excerpt
"
" """""""""""""""""""""
" QUESTIONS/ISSUES
"
" I haven't yet found a spec for AD support ofsetext headers only the
" recommended practices doc that doesn't have in depth details. As a temporary
" (I hope) fallback here are details from CommonMark MD:
"
"   A setext heading consists of one or more lines of text, not interrupted by
"   a blank line, of which the first line does not have more than 3 spaces of
"   indentation, followed by a setext heading underline. The lines of text
"   must be such that, were they not followed by the setext heading underline,
"   they would be interpreted as a paragraph: they cannot be interpretable as
"   a code fence, ATX heading, block quote, thematic break, list item, or HTML
"   block.
"
" It's that last part that I'm focused on as right now my pattern allows the
" first line to start with shit like '*'. Wonder if I should just use \w
"
" TODO: is "give or take two characters" accurate? Do we care? 
"
" According to the rb asciidoctor parser the title cannot begin with '.'
"
" """""""""""""""""""""
"
" For reference here are the patterns used by the AD syntax file:
" syn match /^[^. +/].*[^.]\n[-=~^+]\{2,}$/  two line title
"    title underline is above starting after \n
" syn match /^=\{1,5}\s\+\S.*$/  one line title
"                                                                          }}}
func! s:NextSection_Asciidoc(bkwd) abort
"    call Dfunc("NextSect_Asciidoc(".a:bkwd.")")

    let l:skipflags = 'W'
    if a:bkwd
        let l:skipflags .= 'b'
    endif
    " Do not use l:flags when we have a false positive and want to proceed to
    " the next match. To skip over current match use, naturally, l:skipflags
    let l:flags = l:skipflags . 'cs'

    let l:wildcard = '+'

    " Build complex regex to do best match of atx or setext headers
    let l:hdrmarks_a = repeat(b:headermark, b:musecnav_firstseclevel)
                \ . l:wildcard
    let l:patt_a = '^' . l:hdrmarks_a . '\zs' . b:headermark . '\s+\S'

    " Form regex atom from sublist of the AD setext markup patterns. Sublist
    " offset is determined by the lowest header level in the document. (Second
    " param determines whether that should include document header level)
    let l:hdrmarks_s = join(s:adsetextmarks[b:musecnav_firstseclevel:], "")
    let l:patt_s = '^\zs\w.+\ze\n[' . l:hdrmarks_s . ']+$'

    if b:musecnav_header_type =~? 'a\(ny\|ll\)'
        let l:patt = '\v%(' . l:patt_a . '|' . l:patt_s . ')'
    elseif b:musecnav_header_type ==? 'atx'
        let l:patt = '\v' . l:patt_a
    elseif b:musecnav_header_type ==? 'setext'
        let l:patt = '\v' . l:patt_s
    else
        throw "MU01: Initialization error - b:musecnav_header_type"
    let l:curpos = getcurpos()
    endif

"    call Decho("With first sec level " . b:musecnav_firstseclevel . " patt is " . l:patt)

    " Iterate over search results and extracted data points and do some
    " additional checks until we find something matching all our criteria.
    let l:matchline = search(l:patt, l:flags)
    while l:matchline > 0
"        call Decho("Checking candidate header on line " . l:matchline)
        unlet! l:header
        let l:curpos = getcurpos()
        let l:matchcol = l:curpos[2]

        if b:musecnav_header_type =~? 'a\(ny\|ll\)'
            if l:matchcol != 1
                let l:issetext = 0
            else
                let l:xxxx = search('\v' . l:patt_s, 'cn')
"                call Decho("XX1: " . s:Struncate(getcurpos()[1:2]) . " :: " . l:xxxx . " => " . l:matchline)
                let l:issetext = (l:xxxx == l:matchline)
            endif
        else
            let l:issetext = b:musecnav_header_type ==? 'setext'
        endif
"        call Decho("Header type is " . (l:issetext ? "setext" : "atx"))

        if b:musecnav_header_type =~? "any"
            let b:musecnav_header_type = (l:issetext ? "setext" : "atx")
"            call Decho("header_type: any => " .  b:musecnav_header_type)
        endif

        " Let's make sure we really have a section header...
        try
            " Check whether syntax highlighting agrees
            " TODO: disable if synhi feature is disabled?
            if b:musecnav_use_ad_synhi && !(synIDattr(synID(l:matchline, 1, 0), "name") =~ "asciidoc.*Title")
                throw "Invalid: wrong syntax highlight group"
            endif
            
            " There are multiple things that can precede a regular section header
            " besides a blank line such as a comment '//' or an anchor '[[foo]]'.
            " The one exception is '[discrete]'. This marks a section header
            " outside of the normal flow and we ignore them.
            let l:linem1 = l:matchline - 1
            if prevnonblank(l:linem1) == l:linem1 && getline(l:linem1) =~? '^\[discrete\]\s*$'
                throw "Invalid: [discrete] headers aren't tracked"
            endif
            
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
                if l:line2len == 4 && (synIDattr(synID(l:matchline, 1, 0), "name") =~ "asciidoc.*Block")
                    throw "Invalid: it's an Asciidoc block of some kind"
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
        let l:anch1 = '\v^' . b:headermark . '*\s*\zs' . s:anchor . '?\ze\S+'
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

"        call Dret("NextSect_Asciidoc - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:header]
    endwhile

"    call Dret("NextSect_Asciidoc - no match")
    return [0, 0, 0, 0]
endfunc

"                                                    NextSection_Markdown {{{4
"
" header defined {{{5
" Find the Markdown section header preceding or following the cursor position.
"
" Following is an excerpt from MD's 'official spec' (really just a blog
" entry!).
"
""""""""""""""""""""""
" Markdown supports two styles of headers, Setext and atx.
"
" Setext-style headers are “underlined” using equal signs (for first-level
" headers) and dashes (for second-level headers). For example:
"
"     This is an H1
"     =============
"
"     This is an H2
"     -------------
"
" Any number of underlining =’s or -’s will work.
"
" Setext headings are fucking ridiculous. The syntax is too damn squishy; as
" in far too lenient. If you can even find a complete specification. Anyways,
" see the internal notes for plan regarding future implementation of these.
"
" Moving on...
"
" Atx-style headers use 1-6 hash characters at the start of the line,
" corresponding to header levels 1-6. For example:
"
"     # This is an H1
"     ## This is an H2
"     ###### This is an H6
"
" Optionally, you may “close” atx-style headers. The closing hashes don’t need
" to match the number of hashes used to open the header.
"
"     ## This is an H2 ##
"     ### This is an H3 ######
"
" It seems some implementations don't require a space between the leading
" and/or trailing '#'s and the title text, though GitHub does and, for the
" leaders at least, so does the original definition. Github allows spaces
" after the trailers but anything else makes the '#'s part of the header name.
" For all of this we'll be doing whatever the syntax highlighting allows:
"
" * No space separation required anywhere
" * Non-space after trailing '#' pulls the latter into header name
"
"
" For reference here's the GitHub spec
" https://github.github.com/gfm/#atx-headings
"
" header defined 5}}}
"
""""""""""""""""""""""
" TODO: Currently musecnav only supports 'atx' style headers.
"
" To handle setext headers the following would need to happen:
" * Set true for fourth element in returned list.
" * Set matchline to the first of the two lines (the content)
" * Upstream adjust any line reading or increment/decrement to
"   compensate for the double line.
""""""""""""""""""""""
" Vim's syntax highlighting match patterns
"
" syn match markdownH1 "^.\+\n=\+$" contained 
" contains=@markdownInline,markdownHeadingRule,markdownAutomaticLink
"
" syn match markdownH2 "^.\+\n-\+$" 
" contained contains=@markdownInline,markdownHeadingRule,markdownAutomaticLink
"
" syn match markdownHeadingRule "^[=-]\+$" contained
"
" syn region markdownH1 matchgroup=markdownH1Delimiter start="##\@!"      end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained
" [snipped the H2 through H5 regions as they're obvious]
" syn region markdownH6 matchgroup=markdownH6Delimiter start="#######\@!" end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained
"
" From those definitions I have:
"
"      setext: \v^\zs.+\ze\n[-=]+
"      atx: \v^#{1,6}#@!\zs.{-}\ze#*\s*$
"
" The \zs and \ze atoms mark the actual text to match which is that which
" belongs to the syntax highlighting designated 'markdownH{1..6}' and not the
" adjoining 'markdownH{1..6}Delimiter'.
"
" 
" I don't think the '#@!' is necessary, though, so...
"
"      atx: \v^#{1,6}\zs.{-}\ze#*\s*$
"
" Combined: \v^%(\zs.+\ze\n[-=]+|#{1,6}\zs.{-}\ze#*\s*)$
"
" See also s:FindNextSection()
"                                                                          }}}
func! s:NextSection_Markdown(bkwd) abort
"    call Dfunc("NextSect_Markdown(".a:bkwd.")")

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
            if l:hiname !~# '^markdownH\d$'
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

"        call Dret("NextSect_Markdown - returning match")
        return [l:matchline, l:matchcol, l:matchlevel, l:header]
    endwhile

"    call Dret("NextSect_Markdown - no match")
    return [0, 0, 0, 0]
endfunc

"                                                         FindNextSection {{{4
" Starting at current cursor position find the next section header in
" the document and move the cursor to its location. Returns a list containing
"
"   [matchline, matchcol, matchlevel, header]
"
" If no headers are found all values will be 0.
"
" Optional params
"   bkwd : if truthy search backwards
"                                                                          }}}
func! s:FindNextSection(...) abort
"    call Dfunc("s:FindNextSection(" . s:Struncate(a:000) . "), curpos: "
                \ . string(getcurpos()[1:2]))

    let l:bkwd = 0
    if a:0 && a:1
        let l:bkwd = 1
    endif

    " Note: file type check is done earlier so if..else is fine here
    if &ft ==? 'asciidoc'
        let l:ret = s:NextSection_Asciidoc(l:bkwd)
    else
        let l:ret = s:NextSection_Markdown(l:bkwd)
    endif
    call cursor(0, 999)
"    call Dret("s:FindNextSection")
    return l:ret
endfunc

func! s:FindPrevSection() abort
    return s:FindNextSection(1)
endfunc

" Function s:FindFirstHeader {{{3
"                                                s:FindFirstHeader {{{4
" Find the first document or section header in the Asciidoc document.
"
" A document header must be at the start of the document. The header is
" optional except in the case of a manpage which requires it. (Not enforced
" here.) If not present the first thing in the document should be a section
" header (though our job isn't to validate markup so we may be lenient about
" some junk preceding it and let AD/MD worry about the particulars).
"
" The following shows the basic makeup of a document header. All of the lines
" within are optional except document title (the line beginning with '=').
"
"    ----------------------------
"    blank lines (true?)
"    <header start>
"    attribute entries and comments (not recommended)
"    ...
"    attribute entries and comments (not recommended)
"    = Level 0 Document Title ('#' also valid if not AD + strict headers)
"    author and revision info
"    author and revision info
"    attribute entries and comments
"    ....
"    attribute entries and comments
"    <header end>
"
"    == Level 1 Section Title ('##' also valid if not AD + strict headers)
"    ----------------------------
"
" <header start> and <header end> are not included text, just markup here.
"
" Setext format is also allowed (underlined with '='s) though highly
" discouraged.
"
" Return value of this function is an array containing information about the
" first document or section title seen, if any. For a valid title the array
" will look like this:
"
"   [line number, header level, header text]
"
"   (title here is the doc title line minus the leading =/# and space)
"
" Examples:
"   [3, 0, 'Title']  (preceded by 2 lines of comments/attributes/blanks)
"   [1, 1, 'Sec Head'] (not a title)
"
" If no title header was found an empty array is returned.
"
" The only content permitted above the document title are blank lines, comment
" lines and document-wide attribute entries. If the document title is present
" no blank lines are allowed in the rest of the header as the first blank line
" signifies the end of the header and beginning of the first section.
"                                                                          }}}
func! s:FindFirstHeader()
"    call Dfunc("FindFirstADHeader()")
    let l:iscomment = 0
    let l:lineno = 1
    " scan up to 50 lines; ignore comment blocks, line comments and blank lines
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
        if l:line !~ '\(^//\)\|\(^\s*$\)'
            " found something
            break
        endif
    endwhile

    if b:musecnav_strict_headers
        let b:headermark = '\='
    else
        let b:headermark = '[#\=]'
        if b:musecnav_use_ad_synhi
            " this setting is valid only with strict headers enabled
            let b:musecnav_use_ad_synhi = 0
        endif
    endif

    if l:line =~ '\v^' . b:headermark . '+\s+\S'
        " title: single-line type

        " whatever header char is used must be used consistently throughout
        let b:headermark = '\' . l:line[0]

        let l:level = match(l:line,
                    \ '\v^' . b:headermark . '*\zs' . b:headermark . '\s+\w')
        let l:ret = [l:lineno-1, l:level, l:line[l:level+2:]]
"        call Dret("FindFirstADHeader :: " . s:headInfoStr(l:ret, 0))
        return l:ret
    endif

    " now it's either a valid setext header or failed search (i.e. return [])
    let l:len = len(l:line)
    if l:len < 3
"        call Dret("FindFirstADHeader :: not found")
        return []
    endif

    let l:nextline = getline(l:lineno)
    " TODO: if we (obstensibly) allow first section header (in absence of
    " document header) to be any level for one-liners why not for two-liners?
    if l:nextline !~ '[-=]\{3,}'
"        call Dret("FindFirstADHeader :: not found")
        return []
    endif

    let l:nextlen = len(l:nextline)
    if l:len < (l:nextlen - 3) || l:len > (l:nextlen + 3)
"        call Dret("FindFirstADHeader :: not found")
        return []
    endif

    " opening header is setext type
    if l:nextline =~ '^='
        let l:level = 0
    else
        let l:level = 1
    endif

    let l:ret = [l:lineno-1, l:level, l:line]
"    call Dret("FindFirstADHeader :: " . s:headInfoStr(l:ret, 0))
    return l:ret
endfunction

" Function s:FindFirstSecHeader {{{3
"                                                s:FindFirstSecHeader {{{4
"
" Search for the first section header in a Markdown or Asciidoc document
" (Note: that doesn't include an Asciidoc document header.)
"
" Most of the work is done in s:FindNextSection() and supporting functions so
" look for further details there.
"
" Return value of this function is an array containing information about the
" first header seen. It will look like this:
"
"   [line number, header level, header text]
"
"                                                                          }}}
func! s:FindFirstSecHeader()
"    call Dfunc("FindFirstSecHead()")
    call cursor(1, 1)

    if &ft ==? 'asciidoc'
        if b:musecnav_hasdocheader
            if b:musecnav_docheader[1]
                " already found it (first header is not a doc header)
"                call Dret("FindFirstSecHead - using doc header")
                return b:musecnav_docheader
            endif
            " find a blank line (to pass over document header lines)
            call cursor(b:musecnav_docheader[0] + 1, 1)
        endif
    endif

    let [l:matchline, l:matchcol, l:matchlevel, l:header] = s:FindNextSection()
"    call Decho("1st sect :: " . s:headInfoStr([l:matchline, l:matchcol, l:matchlevel, l:header], 0))

    let l:title = getline(l:matchline)
    " strip leading/trailing whitespace from title
    let l:header = substitute(l:header, '\v^\s*(.{-})\s*$', {m -> m[1]}, "")

"    call Dret("FindFirstSecHead")
    return [l:matchline, l:matchlevel, l:header]
endfunc

" Function s:WalkSections {{{3

"                                                            WalkSections {{{4
" Scan the file beginning at cursor position (usually line 1) and build a tree
" representing the section hierarchy of the document from that point.
"
" Summary of the walk algorithm:
"
" For a section level n, create a list LL
" Loop on search for section header pattern :
"   Header at level n found => sibling
"     append to LL a data structure similar to:
"     [lineno, {header: str, level: num, subtree: []}]
"     Also, update level and ancestor maps
"   Header at level n+1 found => child
"     move cursor up 1 or 2, recurse this func with n+1 and add returned
"     descendant hierarchy to subtree of last added LL elem
"   Header at level < n found => ancestor
"     move cursor up 1 or 2, return LL
"   TODO Found special pattern => terminator (for skipping eof garbage)
"     same as reaching end of document
"   None of the above => error
"     found level is deeper than 1 level down
"
" Param 1: level number of the topmost section that we want processed
" Param 2: parent ID (name) or empty string if level is topmost
"                                                                          }}}
func! s:WalkSections(level, parent) abort
"    call Dfunc("WalkSections(".a:level.")")
    let l:levellist = []

    let [l:matchline, l:matchcol, l:matchlevel, l:matchheader] = s:FindNextSection()
"    call Decho("LVL" . a:level . " FINDNEXT :: " . s:headInfoStr(
                \ [l:matchline, l:matchcol, l:matchlevel, l:matchheader], 0))

    while l:matchline > 0
        " Set to true when we need to include the last found header when
        " searching for the next one.
        " Exclude ID/anchor element preceding or following section name if
        " present. (These are strings enclosed in double square braces.)
        " TODO: Move patterns to FindNextSec()? Or put in global var(s)?
        let l:patt1 = '\v^' . b:headermark . '+\s+\zs%(\[\[[^[\]]+]])?\ze\S+'
        let l:patt2 = '\v\s*\[\[[^[\]]+]]\s?$'
        "let l:line = getline(l:matchline)
            "\ ->substitute(l:patt1, '', '')
            "\ ->substitute(l:patt2, '', '')
"        call Decho("Processing header: " . l:matchheader)

        if l:matchlevel != a:level && empty(l:levellist)
            if b:musecnav_parse_lenient
"                call Decho("Skipping header with unexpected level ".l:matchlevel)
            else
"                call Dret("WalkSections - error 91")
                throw "MU91: Illegal State (bad hierarchy)"
            endif
        endif

        if l:matchlevel == a:level
"            call Decho("LVL".a:level.": match type ** SIBLING **")
            let l:map = {'header': l:matchheader, 'level': l:matchlevel, 'subtree': []}
            call add(l:levellist, [ l:matchline, l:map ])
            call s:UpdateLevelMap(b:musecnav_data.level_map, a:level, [l:matchline, l:map.header])
            call s:UpdateAncestorMap(b:musecnav_data.ancestor_map, l:matchline, [l:matchheader, a:parent])
        elseif l:matchlevel < a:level
"            call Decho("LVL".a:level.": match type ** ANCESTOR **")
            call cursor(0, 1)
"            call Dret("WalkSections - return to ancestor")
            return l:levellist

        elseif l:matchlevel == a:level + 1
"            call Decho("LVL".a:level.": match type ** CHILD **")
            call cursor(0, 1)
            let l:descendants = s:WalkSections(a:level + 1, l:levellist[-1][0])
            eval l:levellist[-1][1].subtree->extend(l:descendants)
        else
            if b:musecnav_parse_lenient
                echohl WarningMsg | echo "Skipped unexpected level ".l:matchlevel | echohl None
            else
"                call Dret("WalkSections - error 92")
                throw "MU92: Invalid hierarchy. See line ".l:matchline
            endif
        endif

        let [l:matchline, l:matchcol, l:matchlevel, l:matchheader] = s:FindNextSection(0)

"        call Decho("LVL".a:level.": iteration end search() ret:".l:matchline)
    endwhile

"    call Decho("LEVELLIST ON RETURN: <<<".s:Struncate(l:levellist).">>>")
"    call Dret("WalkSections - returning levellist from LVL".a:level.")")
    return l:levellist
endfunc

" Function s:GetSectionAncestry {{{3

"                                                      GetSectionAncestry {{{4
" Build a list of section headers in hierarchical order starting at the first
" level and ending at the section whose start is at the line specified in
" param 1. In other words a complete ancestry for the given section.
"
" Param 1: line number of a section header
" Param 2: a recursively traversable ancestor map (dictionary with line number
"          keys and list values: [section header, section parent line num]
" Returns list of lists. Inner list form: [section start line, section header]
"                                                                          }}}
function! s:GetSectionAncestry(line, map)
    let l:res = []
    let l:key = a:line
    while a:map->has_key(l:key)
        let l:val = a:map[l:key]
        call add(l:res, [l:key, l:val[0]])
        let l:key = l:val[1]
    endwhile

    if l:res->empty()
        return l:res
    endif

    return l:res->reverse()
endfunction

" Function s:DrawMenu {{{3

" Show menu representing current state of navigation either above the command
" line or in a popup window. If not using popups get the user's selection and
" return it.  Otherwise, popups handle user input in a separate thread so this
" will always returns -1 immediately in that case.
func! s:DrawMenu() abort
"    call Dfunc("DrawMenu()")

    if b:musecnav_data.level > 1 && b:musecnav_display_mode ==# 'ancestors'
        let l:topancestor = s:GetSectionAncestry(
                    \ b:musecnav_data.currparent[0],
                    \ b:musecnav_data.ancestor_map)
        let l:menudata = s:MenuizeTree(
                    \ 1, l:topancestor[0], b:musecnav_data.sections)
    else
        let l:menudata = s:MenuizeTree(b:musecnav_data.level, b:musecnav_data.selheadline, b:musecnav_data.sections)
    endif
"    call Decho("Generated menu data: ".s:Struncate(l:menudata))

    let l:currlevel = b:musecnav_data.level
    let l:idx = 0

    let l:displaymenu = []
    " the row number to highlight (the selected row)
    let l:hirownum = 0

    "echom printf("lvl %d | menudata %s", l:currlevel, l:menudata)
    if !b:musecnav_use_popup
        echom '--------'
    endif

    while l:idx < len(l:menudata)
        let l:rowitem = l:menudata[l:idx]
    "echom printf("idx %d, rowitem '%s'", l:idx, string(l:rowitem))
        let l:rowlevel = l:rowitem[0]
"        call Decho("  process rowitem: " . s:Struncate(l:rowitem))
        let l:pad = '  '
        " For currently selected menu item insert our marker icon
        if b:musecnav_data.selheadline == l:rowitem[1]
            let l:pad = b:musecnav_place_mark . ' '
            let l:hirownum = l:idx + 1
        endif
    "echom printf("pad '%s' | hirownum %d", l:pad, l:hirownum)

        " Add padding proportional to current row's section level
        let l:rowtext = repeat(' ', (l:rowlevel - 1) * 2)
                    \ . l:pad . l:rowitem[2]
        " Prepend menu line numbers and we have one menu item ready to go.
        let l:rowtext = printf("%2s", l:idx+1) . ": " . l:rowtext
    "echom printf("rowtext '%s'", l:rowtext)
"        call Decho("    into rowtext: " . l:rowtext)
        call add(l:displaymenu, l:rowtext)

        if !b:musecnav_use_popup
            echom l:rowtext
        endif
        let l:idx += 1
    endwhile

    let b:musecnav_data.last_menu_data = l:menudata
    let b:musecnav_data.last_menu_text = l:displaymenu
    let b:musecnav_data.last_menu_row = l:hirownum

    let l:choice = -1
"    call Decho("Display menu len: ".len(l:displaymenu)." data: ".s:Struncate(l:displaymenu))
    let l:title = ' ' .g:musecnav_popup_titles[g:musecnav_popup_title_idx] . ' '
    if exists("b:musecnav_batch")
        echom '--------'
    elseif b:musecnav_use_popup
        let l:ww = winwidth(0)
        let l:popcol = min([b:musecnav_pop_col+4, l:ww - strlen(l:title)])
        let popid = popup_menu(l:displaymenu, #{
                    \ title: l:title,
                    \ col: l:popcol,
                    \ pos: 'topleft',
                    \ resize: 1,
                    \ close: 'button',
                    \ maxheight: 60,
                    \ scrollbar: 1,
                    \ highlight: 'Popup',
                    \ padding: [1,2,1,2],
                    \ filter: 'musecnav#MenuFilter',
                    \ callback: 'musecnav#MenuHandler',
                    \ })

        if l:hirownum > 0
            " last chosen section will be highlighted row
			"let winid = popup_create('hello', {})
			"let bufnr = winbufnr(winid)
			"call setbufline(bufnr, 2, 'second line')

            call win_execute(popid, 'call cursor('.l:hirownum.', 1)')
        endif

        if has('b:musecnav_debug') && b:musecnav_debug
            let g:musecnav_popinfo = popup_getpos(popid)
            call extend(g:musecnav_popinfo, popup_getoptions(popid))
            call extend(g:musecnav_popinfo, {"ww" : l:ww, "popcol" : l:popcol})
        endif
    else
        echom '--------'
        let l:choice = input("Enter number of section: ")
        while strlen(l:choice) && type(eval(l:choice)) != v:t_number
            echohl WarningMsg | echo "You must enter a valid number" | echohl None
            let l:choice = input("Enter number of section: ")
        endwhile
        redraw
    endif

"    call Dret("DrawMenu")
    return l:choice
endfunc

" Function s:ProcessSelection {{{3

" Given user selection of a menu row determine what section that represents
" and what line number contains it and move the cursor to that line.
" Params:
" id - a popup window id or -1 if we're using non-popup menus
" choice - the user's selection, normally a positive integer
func! s:ProcessSelection(id, choice) abort
"    call Dfunc("ProcessSelection(id:".a:id.", choice:".a:choice.")")
    if a:id == -1
        if b:musecnav_use_popup
"            call Dret("ProcessSelection - error 93")
            throw "MU93: Illegal State - non-popup id but popup flag set"
        endif
    endif

    let l:choiceidx = a:choice - 1
"    call Decho("User selected ".b:musecnav_data.last_menu_text[l:choiceidx])
    let l:chosendata = b:musecnav_data.last_menu_data[l:choiceidx]
"    call Decho("Menu data (".l:choiceidx."): " . s:Struncate(l:chosendata))

    let b:musecnav_data.selheadline = l:chosendata[1]
    let b:musecnav_data.level = l:chosendata[0]
    "let b:musecnav_data.level = max([0, stridx(l:chosenitem, " ") - b:leveladj])

"    call Decho("Navigate to line ".b:musecnav_data.selheadline." (level ".b:musecnav_data.level.")")
    exe b:musecnav_data.selheadline
    norm! zz
    " Clear the menu digit buffer
    let b:musecnav_select_buf = -1
"    call Dret("ProcessSelection")
endfunc

" Function s:MenuizeTree {{{3

"                                                          MenuizeTree {{{4
" Build and return a data structure containing everything required to render a
" section header menu.
"
" TODO: Address efficiency. The hierarchy is traversed three times within (two
" recursive descents). 'Tis not ideal. We're talking small trees here and it's
" perfectly performant on my machine but could be an issue on lesser machines.
" Investigate if this is ever shared.
"
" Parameters and the actual values passed at this time:
" 1. current level                              [b:musecnav_data.level]
" 2. lineno of sect header for curr section     [b:musecnav_data.selheadline]
" 3. section/sub-section data to be menuized    [b:musecnav_data.sections]
"
" Enhancement todos:
" * menu mode that displays all sections expanded
"                                                                          }}}
func! s:MenuizeTree(level, secline, tree) abort
"    call Dfunc("MenuizeTree(lvl: ".a:level.", line: ".a:secline.", tree: ".s:Struncate(a:tree).")")
    let b:musecnav_data.currparent = []
    if a:level > 0 && b:musecnav_display_mode !=? "all"
        " get the current section's entire hierarchy...
        let l:subtree = s:DescendToLine(a:secline, a:tree, [0, "ROOT"])
    else
        " ...which is the whole shebang if we're at the start of the file
        " or configured to always expand headers.
        let l:subtree = a:tree
    endif

    let l:sibrangestart = 1
    let l:sibrangeend = line('$')
    if &ft ==? 'asciidoc' && b:musecnav_hasdocheader
        " If there's a document header it'll be first menu item (ROOT)
        let l:levellist = [[0, 1, b:musecnav_docheader[2] . " (ROOT)"]]
    else
        let l:levellist = []
    endif

    " If configured expand rule is 'all' we just need to flatten everything
    " and return the result.
    if b:musecnav_display_mode ==? "all"
"        call Decho("Recurse and flatten entire tree")
        let l:levellist = l:levellist->extend(s:FlattenSubTree(a:tree, 1, 9))
"        call Dret("MenuizeTree (expand all)")
        return l:levellist
    endif

    " If using 'always show level 1 sections' mode we do it in two chunks.
    " First, top sections preceding the current section's level 1 ancestor and
    " then the top sections following the ancestor. The latter is handled at
    " the end of this function. (Applicable only if current section is level 2
    " or deeper as level 1 is always displayed otherwise.)

    if a:level > 1 && b:musecnav_display_mode ==? 'top'
        " First chunk as described in preceding comment.
        for l:topsect in b:musecnav_data.level_map[b:musecnav_firstseclevel]
"            Decho("l:topsect is " . s:Struncate(l:topsect))
            if l:topsect[0] >= a:secline
                break
            endif
            " add a list of form [level, lineno, header]
            let l:sectdata = [b:musecnav_firstseclevel]
            eval l:levellist->add(l:sectdata->extend(l:topsect))
        endfor
    endif

    if !empty(b:musecnav_data.currparent)
"        call Decho("Process parent ".s:Struncate(b:musecnav_data.currparent))
        " Insert parent and all its ancestors except ROOT (already in list)
        if b:musecnav_data.currparent[0] != 0
            " Build ancestor list of current header and join with menudata
            let l:ancestors = s:GetSectionAncestry(b:musecnav_data.currparent[0], b:musecnav_data.ancestor_map)
            if b:musecnav_display_mode ==? 'top'
                " Level 1 ancestor already displayed in previous block
                let l:ancestors = l:ancestors[1:]
            endif
            " XXX: Really? Even if the root is level 3?
            let l:anclevel = 2
            for l:ancestor in l:ancestors
                " add a list of form [level, lineno, header]
                let l:sectdata = [l:anclevel]
                eval l:levellist->add(l:sectdata->extend(l:ancestor))
                let l:anclevel += 1
            endfor
        endif

        " beyond first level we need the parent's range of lines to
        " constrain the siblings that will be displayed
        if a:level > b:musecnav_firstseclevel
            " range start is line number of the parent
            let l:sibrangestart = b:musecnav_data.currparent[0]
            let l:found = 0
"            call Decho("Level is 2+ so find the parent's range")
            " loop through all nodes on parent's level
            for l:parentsibling in b:musecnav_data.level_map[a:level - 1]
"                call Decho("-=> Processing parentsib ".l:parentsibling[1])
                " this is the parent sibling next after the parent and
                " it's line number is our range end (if parent is last in
                " list we already set end of range to last line in file
                if l:found
                    let l:sibrangeend = l:parentsibling[0]
"                    call Decho("DONE - sibling range end is ".l:sibrangeend)
                    break
                endif

                " continue until we find the parent itself
                if l:parentsibling[0] == l:sibrangestart
"                    call Decho("-=> Found the parent")
                    let l:found = 1
                endif
            endfor
        endif
    endif

    let l:sibpre = []
    let l:sibpost = []
    let l:recursed = 0
    let l:targetline = l:subtree[0]

    let l:efflevel = a:level > 0 ? a:level : 1
    for l:sibling in b:musecnav_data.level_map[a:level > 0 ? a:level : 1]
        let l:siblineno = l:sibling[0]
        if l:siblineno < l:sibrangestart
            continue
        elseif l:siblineno > l:sibrangeend
            if ! l:recursed
                echohl WarningMsg | echo "sib range end before recurse" | echohl None
            endif
            break
        endif
"        call Decho("Adding to menu lineno: ".l:siblineno)
        " add a list of form [level, lineno, header]
        let l:sectdata = [l:efflevel]
        eval l:levellist->add(l:sectdata->extend(l:sibling))
        if a:level > 0 && l:siblineno == l:targetline
"            call Decho("Recurse and flatten selected subtree with ".len(l:subtree[1].subtree)." children")
            let l:ret = s:FlattenSubTree(l:subtree[1].subtree, 1, 9)
            eval l:levellist->extend(l:ret)
            let l:recursed = 1
        endif
    endfor

    if a:level > 1 && b:musecnav_display_mode ==? 'top'
        " Add remaining top-level sections, i.e. those that follow the current
        " section's top-level ancestor.
        for l:topsect in b:musecnav_data.level_map[b:musecnav_firstseclevel]
            if l:topsect[0] <= l:targetline
                continue
            endif
            let l:sectdata = [b:musecnav_firstseclevel]
            eval l:levellist->add(l:sectdata->extend(l:topsect))
        endfor
    endif

"    call Dret("MenuizeTree")
    return l:levellist
endfunc

" Function s:DescendToLine {{{3

"                                                           DescendToLine {{{4
" Navigates a (sub)tree looking for the specified line.
"
" Each level is traversed 'laterally' until we reach the node that we
" determine contains the target line. We make a recursive call, passing the
" subtree attached to that node. This continues until we reach the node with
" line number equal to our target line number.
"
" Params:
"   line   : target line that cause descent to end and this function to return
"   tree   : section header tree or a subtree thereof
"   parent : tree's parent represented as [linenum, header]
"            Example: [327, '=== Things to Do']
"
" Returns: the node with the line number we are targeting
"                                                                          }}}
func! s:DescendToLine(line, tree, parent) abort
"    call Dfunc("DescendToLine(line: ".a:line.", tree: ".string(a:tree)." parent: ".s:Struncate(a:parent).")")
    let l:levellen = len(a:tree)

    let l:curridx = 0
    for l:sect in a:tree
        if l:sect[0] == a:line
            " We've reached the target level
"            call Decho("Descent reached target. Final tree: ".s:Struncate(l:sect))
            let b:musecnav_data.currparent = a:parent
"            call Dret("DescendToLine - line ".a:line." FOUND, target line reached, currparent: ".s:Struncate(b:musecnav_data.currparent))
            return l:sect
        endif

        " If there is a next elem check whether a:line is between lines of
        " current and next elems. If so then we need to descend
        if l:sect[0] < a:line
            if l:curridx + 1 == l:levellen || a:line < a:tree[l:curridx+1][0]
                let l:parent = [l:sect[0], l:sect[1].header]
"                call Dret("DescendToLine - recursive descent")
                return s:DescendToLine(a:line, l:sect[1].subtree, l:parent)
            endif
        endif
        let l:curridx += 1
    endfor

"    call Dret("DescendToLine - ERROR (line:".a:line.", parent:".string(a:parent).", tree: ".s:Struncate(a:tree))
    throw "MUXX: Won't reach this line unless passed non-existent target line"
endfunc

" Function s:FlattenSubTree {{{3

" subtree is list of lists [[l1, ...], [l2, ...]]
func! s:FlattenSubTree(subtree, level, n) abort
"    call Dfunc("FlattenSubTree(level: ".a:level.", subtree: ".s:Struncate(a:subtree))
    if a:level == a:n
"        call Decho("Max depth reached at level ".a:level.". Recursion terminating")
"        call Dret("FlattenSubTree")
        return []
    endif

    "let l:accum = {lineno: -1, header: ""}
    let l:accum = []
    for l:sect in a:subtree
"        call Decho("processing section ".s:Struncate(l:sect))
        let l:sublist = [l:sect[1].level, l:sect[0], l:sect[1].header]
"        call Decho("Elem lineno: ".l:sublist[1].", header: ".l:sect[1].header)
        eval l:accum->add(l:sublist)
        let l:nested = l:sect[1].subtree
        if ! empty(l:nested)
"            call Decho("FlattenSubTree - Recurse on subtree with ".len(l:nested)." children")
            eval l:accum->extend(s:FlattenSubTree(l:nested, a:level+1, a:n))
        endif
    endfor

"    call Decho("LVL".a:level." returning : <<<".s:Struncate(l:accum).">>>")
"    call Dret("FlattenSubTree")
    return l:accum
endfunc

" Function s:UpdateLevelMap {{{3

" The level map is for looking up all the sections at a specified level.
" K->V where K is level number, V is list of [lineno, header]
" header is the section header text minus markup like opening '='
" Currently used while collecting data needed to construct menu. Ie. to get a
" section's siblings or siblings of a section parent.
"
func! s:UpdateLevelMap(map, key, value)
"    call Dfunc("UpdateLevelMap(key: ".a:key.", val: ".string(a:value).", map: ".s:Struncate(a:map).")")
    if ! has_key(a:map, a:key)
        let a:map[a:key] = []
    endif
    call add(a:map[a:key], a:value)
"    call Dret("UpdateLevelMap - new map: ".s:Struncate(a:map))
endfunc

" Function s:UpdateAncestorMap {{{3

" The level map is for looking up all the parent of any given section. By
" recursively looking up parents we can determine all ancestors of a section.
" K->V, K is section ID and V is list of [section name, section parent ID]
"
" Param 1: the ancestor map
" Param 2: section line number
" Param 3: list containing parent line number and section name
func! s:UpdateAncestorMap(map, key, value)
"    call Dfunc("UpdateAncestorMap(key: ".a:key.", val: ".string(a:value).", map: ".s:Struncate(a:map).")")
    if has_key(a:map, a:key)
        throw "Encountered a section (" . a:key . ") level a second time"
    endif
    let a:map[a:key] = a:value
"    call Dret("UpdateAncestorMap - new map: ".s:Struncate(a:map))
endfunc

" Function s:Struncate {{{3
"
" Wrapper for string() that truncates its result.
"
" Maximum length of returned strings (not counting the added '... <SNIP>'
" suffix) can be specified in global 'musecnav_liststr_limit' otherwise a
" default of 160 chars is used.
"
" Disable with global 'musecnav_struncate_off'.
"
" Currently used only with data passed to Decho functions.
function! s:Struncate(struct)
    if exists("g:musecnav_struncate_off") && g:musecnav_struncate_off
        return string(a:struct)
    endif

    let l:limit = exists("g:musecnav_liststr_limit")
                \ ? g:musecnav_liststr_limit : 160
    let l:ret = string(a:struct)
    let l:len = strlen(l:ret)
    if l:len == 0
        return ""
    elseif l:len > l:limit
        let l:ret = l:ret[0:l:limit-1] .. " ... <SNIP>"
    endif
    return l:ret
endfunc

" Function s:DebugLog {{{3
"
func! s:DebugLog(...) abort
    if !empty(g:musecnav_log_file)
        call writefile([json_encode(a:000)], g:musecnav_log_file, 'a')
    endif
endfunc

" Function s:ProcessMenuDigit {{{3
"                                                        ProcessMenuDigit {{{4
" A bit of a state machine for handling menu row numbers which make it easier
" for the user to jump to a section header when there are many such headers.
" The total number of headers and whether the user is entering the first or
" second (if applicable) digit of their choice determine what happens. (e.g.
" can/should we move to row 2 after the user enters the first digit of 25)
"                                                                          }}}
func! s:ProcessMenuDigit(rows, entry) abort
"    call Dfunc("ProcessMenuDigit(rows:".a:rows.", entry:".a:entry.")")
    let l:ret = -99
    " non-negative number?
    if !(a:entry >= 0 && a:entry <=9)
"    "    call Dret("ProcessMenuDigit - invalid entry ".a:entry)
        return -1
    endif

    " empty 'buffer'?
    if b:musecnav_select_buf < 0
        " first entry non-zero?
        if a:entry > 0
            " can entry only be first 10 rows?
            if a:rows < a:entry * 10
                " yep - final selection
                let b:musecnav_select_buf = -1
            else
                " tenative selection
                let b:musecnav_select_buf = a:entry
            endif

            if a:entry <= a:rows
                let l:ret = a:entry
            else
                let l:ret = -2
            endif

        else " 0 not allowed in first slot, discard
            let l:ret = -3
        endif
    else
        " combine with existing entry
        let l:entry = (10*b:musecnav_select_buf) + a:entry
        if l:entry <= a:rows
            " final selection
            let b:musecnav_select_buf = -1
            let l:ret = l:entry
        else
            " out of range
            let l:ret = -4
        endif
    endif

"    call Dret("ProcessMenuDigit - returning ".l:ret)
    return l:ret
endfunc

" Functions s:getfuncref and s:resolvefname {{{3

" Returns a funcref to the script-local function with given name
function! s:getfuncref(name)
    "return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
    return function(s:resolvefname(a:name))
endfunction

" Return resolved name of script-local function with given unresolved name
function! s:resolvefname(unresolved)
    return substitute(a:unresolved,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),'')
endfunction


" Function s:headInfoStr {{{3

let s:head_info_field_3 = ["Line", "Level", "Text"]
let s:head_info_field_4 = ["Line", "Column", "Level", "Text"]

"   [line number, header level, header text]
" Returns a string with nicely formatted header info list values. These have
" one of two forms:
"
"   [line number, column number, header level, header text]
"   [line number, header level, header text]
"
" Based on the length of the list the appropriate names and values will
" be paired together in the returned string ready for display.
function! s:headInfoStr(infolist, multiline)
    let l:len = len(a:infolist)
    if l:len != 3 && l:len != 4
        throw "MU41: invalid header info list"
    endif

    let l:fields = l:len == 3 ? s:head_info_field_3 : s:head_info_field_4

    let l:ret = ""
    for l:field in range(l:len)
        let l:ret .= l:fields[l:field] . ": " . a:infolist[l:field]
        if a:multiline
            let l:ret .= "\n"
        else
            let l:ret .= ", "
        endif
    endfor

    return strcharpart(l:ret, 0, len(l:ret)-2)
endfunction

" Global Functions {{{2

" User Functions {{{3

" musecnav#navigate {{{4
"                                                       musecnav#navigate {{{5
" Main entry point for normal plugin use. Primary hotkeys call this.
"
" Contains some setup and sanity checking before calling the local navigate
" function. Known error types will bubble up to here and get caught and
" properly messaged while anything else, unknown and therefore considered
" critical, is allowed to escape.
"
" An optional first param can be supplied which will trigger a reset
" based on the value. The allowed values and associated effects:
"
"     0: Initialize only. Run normally except return before calling Navigate.
"     1: Reinitialize section tree, ie. force a 'soft' reset
"     2: Reset state, and reinit tree, ie. force a 'hard' reset
"
" Any other value will result in an error.
"                                                                          }}}
func! musecnav#navigate(...)
"    call Dfunc("musecnav#navigate(" . s:Struncate(a:000) . ")")
    let l:initonly = 0
    let l:force = 0
    if a:0 == 1
        if a:1 == 0
            let l:initonly = 1
        else
            let l:force = a:1
        endif
    endif

    if l:force < 0 || l:force > 2
"        call Dret("musecnav#navigate - fatal MU14")
        throw "MU14: force param must have a value between 0 and 2"
    endif

    try
        if &ft !=? 'asciidoc' && &ft !=? 'markdown'
"            call Dret("musecnav#navigate - Wrong filetype")
            echohl WarningMsg | echo "Not a valid filetype: " . &ft | echohl None
            return
        endif

        " Do some file type specific setup and checks
        let b:leveladj = 0
        if &ft ==? 'asciidoc'
            let b:leveladj = 1
            if b:musecnav_use_ad_synhi && !exists("g:syntax_on")
                " For now just quietly disable the double-check
                let b:use_ad_synhi = 0
            endif
        elseif &ft ==? 'markdown'
            let b:headermark = '#'
            if !exists("g:syntax_on")
                echohl WarningMsg 
                echo "Markdown section header detection requires that syntax highlighting be enabled"
                echohl None
                return
            endif
        endif

        if !exists('b:musecnav_data') || l:force
"            call Decho("Clearing b:musecnav_data")
            let b:musecnav_data = {}
        endif

        if exists('b:musecnav_batch')
"            call Decho("Running in BATCH mode (no popups)")
            let b:musecnav_use_popup = 0
        endif

        if b:musecnav_use_popup && !has('popupwin')
"            call Dret("musecnav#navigate - Popups unsupported")
            echohl WarningMsg
            echo 'Vim 8.1.1517 or later required for the popup-style menu'
            echohl None
            return
        endif

        if l:force == 2
            let b:musecnav_hdrs_scanned = 0
        endif

        if !exists('b:musecnav_hdrs_scanned') || !b:musecnav_hdrs_scanned
            call s:InitHeaderInfo()
            let b:musecnav_hdrs_scanned = 1
        endif

        if l:force == 2
            " Hard reset positions cursor at start
            call setpos('.', [0, 1, 1])
        endif

        "if !exists("b:musecnav_data.selheadline") || l:force == 2

        if l:initonly
            return
        endif

        call s:Navigate()
"        call Dret("musecnav#navigate")
    catch /^MU\d\+/
        echohl ErrorMsg
        echom printf("Fatal error in MuSecNav: %s [%s]", v:exception, v:throwpoint)
        echohl None
    endtry
endfunc

" musecnav#CycleLayouts {{{4
"                                                 musecnav#CycleLayouts {{{5
" Set the menu's display mode by cycling forward or back through available
" values.
"
" The associated setting: b:musecnav_display_mode
"                                                                          }}}
func! musecnav#CycleLayouts(diff)
    if !exists('b:displaymodeidx')
        let b:displaymodeidx = index(s:displaymodes, b:musecnav_display_mode)
    endif
    let b:displaymodeidx = (b:displaymodeidx + a:diff) % len(s:displaymodes)
    let b:musecnav_display_mode = s:displaymodes[b:displaymodeidx]
    echom 'musecnav display mode: ' . b:musecnav_display_mode
endfunc

" musecnav#SetDisplayMode {{{4
"                                                 musecnav#SetDisplayMode {{{5
" Main entry point for normal plugin use. Primary hotkeys call this.
"
"
" Any other value will result in an error.
"                                                                          }}}
func! musecnav#SetDisplayMode(mode)
endfunc

" Popup Functions {{{3

" Function musecnav#MenuFilter {{{4
" As an enhancement to popup menus we number menu elements (section headers)
" and allow the user to enter one of those numbers in order to move the
" selection to that line.  (For large docs with many sections Up/Down just
" doesn't cut it.)
func! musecnav#MenuFilter(id, key) abort
    let l:last_key = getwinvar(a:id, 'last_key')
    call setwinvar(a:id, 'last_key', a:key)

    if match(a:key, '\r') >= 0 && empty(l:last_key)
        " Exit when Enter hit twice in a row
        call popup_close(a:id)
        return 1
    endif

    let l:rownum = 0
    if match(a:key, '\C^J$') == 0
        let l:rownum = popup_getpos(a:id).core_height
        let b:musecnav_select_buf = -1
    elseif match(a:key, '\C^K$') == 0
        let l:rownum = 1
        let b:musecnav_select_buf = -1
    elseif match(a:key, '^\d$') == 0
        let l:rownum = s:ProcessMenuDigit(popup_getpos(a:id).core_height, a:key)
    elseif match(a:key, '^j$') == 0
        let l:maxrow = popup_getpos(a:id).core_height
        let l:currow = b:musecnav_data.last_menu_row
        "let b:musecnav_popup_msg = printf(
        "            \ "Key j received with currow %d and maxrow %d",
        "            \ l:currow, l:maxrow)
        if l:currow == l:maxrow
            let s:test_past_menu_end = 1
        else
            let s:test_past_menu_end = 0
        endif
    endif

    if l:rownum > 0
        call win_execute(a:id, 'call cursor('.l:rownum.', 1)')
        return 1
    endif

    " No shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
endfunc

" Function musecnav#MenuHandler {{{4
" Menus can't callback into script-local code so this must be a global
" function. This will spawn an updated menu popup unless result param is -1.
func! musecnav#MenuHandler(id, result) abort
"    call Dfunc("MenuHandler(id:".a:id.", result:".a:result.")")
    if a:result < 1
        " FYI -1 indicates user canceled menu while 0 indicates popup_close()
        " was called without the 'result' param. Latter shouldn't happen here.
"        call Dret("MenuHandler - exit input loop")
        return
    endif
    call s:ProcessSelection(a:id, a:result)
    " TODO: if user didn't choose a section restore cursor position (i.e. col)
    "let l:view = winsaveview()
    call s:DrawMenu()
    "call winrestview(l:view)
"    call Dret("MenuHandler")
endfunc
" }}}
" }}}

" Utility Functions {{{3

" Function musecnav#InfoDump {{{4

func! musecnav#HeaderInfoDump()
    let l:vars = ['b:musecnav_docname', 'b:musecnav_rootlevel', 'b:musecnav_hasdocheader', 'b:musecnav_docheader', 'b:musecnav_firstsecheader']
    echo printf("\nHeader Info:\n\n")
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n", l:var[11:], eval(l:var))
        endif
    endfor
endfunc

func! musecnav#SettingInfoDump()
    echo printf("\nSettings:\n\n")
    for l:var in g:musecnav_config_vars
        if exists(l:var)
            echo printf("%-18s : %s\n", l:var[11:], eval(l:var))
        endif
    endfor
endfunc

func! musecnav#InfoDump()
    if !exists('b:musecnav_data')
        echo printf("No data for this buffer!")
        return
    elseif empty(b:musecnav_data)
        echo printf("Main dictionary not currently populated")
        return
    endif

    echo printf("Sections: %s\n\n", b:musecnav_data.sections)
    if exists('b:musecnav_data.last_menu_text')
        echo printf("Last Menu: %s\n\n", b:musecnav_data.last_menu_text)
    endif
    echo printf("Level Map: %s\n\n", b:musecnav_data.level_map)
    echo printf("Ancestor Map: %s\n\n", b:musecnav_data.ancestor_map)

    let l:vars = ['b:musecnav_data.level', 'b:musecnav_data.selheadline', 'b:musecnav_data.currparent']
    for l:var in l:vars
        if exists(l:var)
            echo printf("%-18s : %s\n", split(l:var, '_')[1], eval(l:var))
        endif
    endfor
    call musecnav#HeaderInfoDump()
    call musecnav#SettingInfoDump()
    echo printf("\nMuSecNav v%s\n\n", g:musecnav_version)
endfunc

" Function musecnav#ShiftPopupHi {{{4
"                                                            ShiftPopupHi {{{5
" Changes the linked highlight group for group Popup or PopupSelected.
" Both of those have a pre-configured list of link targets. This function
" will cycle through the appropriate list (determined by the function param)
" and the value is linked to the associated group (Popup or PopupSelected).
"                                                                          }}}
func! musecnav#ShiftPopupHi(forsel)
    if g:musecnav_popup_modifiable == 0
        return
    endif

    if !exists('b:musecnav_popup_hiidx')
        let b:musecnav_popup_hiidx = [0, 0]
    endif

    let l:type = 0
    let l:group = "Popup"
    if a:forsel
        let l:type = 1
        let l:group .= "Selected"
    endif
    let l:size = len(g:musecnav_popup_higroups[l:type])
    let b:musecnav_popup_hiidx[l:type] =
                \ (b:musecnav_popup_hiidx[l:type]+1)%l:size
    exe 'hi link ' . l:group . ' ' .
        \ g:musecnav_popup_higroups[l:type][b:musecnav_popup_hiidx[l:type]]
endfunc
" }}}
" }}}3

" Other Functions {{{3

" Currently only used by personal stuff (MSNReload)
func! musecnav#DataReset()
    let b:musecnav_data = {}
    let b:musecnav_ = {}
    let l:vars = ['b:musecnav_hasdocheader', 'b:musecnav_rootlevel', 'b:musecnav_docname', 'b:musecnav_docheader', 'b:musecnav_firstsecheader', 'b:musecnav_hdrs_scanned']
    for l:var in l:vars
        if exists(l:var)
            exe "unlet " . l:var
        endif
    endfor
endfunc

" T_ functions are FOR TESTING ONLY

func! musecnav#T_InitHeaderInfo()
    return s:InitHeaderInfo()
endfunc

" s:FindNextSection takes two params: bkwd and withroot
func! musecnav#T_SectionFind(...)
    echo printf("%s", join(function('s:FindNextSection', a:000)()))
endfunc

" . F7, j, Enter
" . Exit loop if s:test_past_menu_end is true
" . Save current line text (e.g. append to register)
" . Save menu text using that `for` loop a few sections back
" . Repeat
func! musecnav#T_RunFuncTest(tofile, ...)
    let l:outdir = '.'
    if a:tofile && a:0
        let l:outdir = a:1
    endif

    if !exists("s:test_past_menu_end")
        let s:test_past_menu_end = 0
    endif

    call feedkeys("\<F7>K\<CR>\<Esc>", "x")

    let l:mode = b:musecnav_display_mode
    let b:musecnav_display_mode = 'all'

    try
        let l:idx = 0
        let l:kill = 100
        let l:results = ""
        while 1
            call feedkeys("\<F7>j\<CR>\<Esc>", "x")

            if l:idx > l:kill || s:test_past_menu_end
                echom "Menu end reached. Saving..."
                break
            endif

            let l:result = printf("***** Test %d *****\n\n", l:idx+1)
            for row in b:musecnav_data.last_menu_text 
                let l:result .= printf("%s\n", row)
            endfor
            let l:result .= printf("\n\nHeader (line %d): %s\n\n", 
                        \ getcurpos()[1], getline("."))
            let l:idx += 1
            let l:results .= l:result
            echom printf("%d: %s", l:idx, l:result)
        endwhile

        " save collected data
        let l:fname = expand("%") . "_test.out"
        if a:tofile
            exe "redir! > " . l:outdir . '/' . l:fname
        else
            redir! @*>
        endif
        silent echo l:results
        redir END
    finally
        let b:musecnav_display_mode = l:mode
    endtry
    echom "Done!"
endfunc

func! musecnav#T_ShowMenuize()
    echo printf("%s", string(s:MenuizeTree(b:musecnav_data.level, b:musecnav_data.selheadline, b:musecnav_data.sections)))
endfunc

func! musecnav#T_FirstADHeadFind()
    let [l:lineno, l:level, l:text] = s:FindFirstHeader()
    echo printf("lineno: %d level: %d text: %s", l:lineno, l:level, l:text)
endfunc

func! musecnav#T_FirstSecHeadFind()
    let [l:lineno, l:level, l:text] = s:FindFirstSecHeader()
    echo printf("lineno: %d level: %d text: %s", l:lineno, l:level, l:text)
endfunc

" Call GetSectionAncestry() with current section's parent as param 1
func! musecnav#T_Ancestors()
    let l:ancestors = s:GetSectionAncestry(b:musecnav_data.currparent[0], b:musecnav_data.ancestor_map)
    echo printf("%s", string(l:ancestors))
endfunc

" Config Undo {{{1
" TODO: complete undo of config
let &cpoptions = s:save_cpo
unlet s:save_cpo

" Vim: set fdl=2 fcl=all fdc=5:
