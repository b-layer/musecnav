let s:save_cpo = &cpoptions
set cpoptions&vim

let s:document = {}

" s:document.new() {{{1
func s:document.new()
    let newDoc = copy(self)
    let newDoc.sections = []
    let newDoc.levels = {}
    let newDoc.currsec =  #{line: 0, level: 0}
    let newDoc._lastlevel = -1

    return newDoc
endfunc

" s:document.add_section() {{{1
" OR do we pass section fields and build the section in this function?
func s:document.add_section(line, level, title) dict abort
    if !self.is_empty()
        let l:last = self.get(-1)
        if a:level > l:last.level+1
            " Levels can only ascend one at a time
            throw "MU53: Invalid hierarchy, line " . a:line
        endif
        if l:last.line >= a:line
            " What the heck? How does a start to end scan of the buffer end up
            " with out of order line numbers?!
            throw "MU59: Illegal state, line " . a:line
                        \ . " can't follow line " . l:last.line
        endif
    endif

    let l:newid = self.sections->len()
    let l:section = musecnav#section#new(l:newid, a:line, a:level, a:title)
    call add(self.sections, l:section)

    " See if the new section has a parent
    let l:parent_id = -1
    for l:idx in range((self.sections->len()-1), 0, -1)
        if self.sections[l:idx].level == (l:section.level-1)
            let l:parent_id = l:idx
            break
        endif
    endfor

    if l:parent_id >= 0
        call l:section.set_parent(self.sections[l:parent_id])
    endif

    " Update the levels map
    call self.add_to_levels(l:section)

    let self._lastlevel = l:section.level

    return l:section
endfunc

" s:document.set_current_section() {{{1
"
" Given a line number locate the containing section and set the document's
" current section field.
func s:document.set_current_section(line) abort
    if self.is_empty()
        throw "MU54: empty document object!"
    endif

    let l:first = self.get_root()
    if a:line < l:first.line
        let self.currsec = l:first
        return
    endif

    let l:last = l:first
    for l:idx in range(1, self.sections->len() - 1)
        let l:curr = self.get(l:idx)
        if a:line < l:curr.line
            let self.currsec = l:last
            return
        endif
        let l:last = l:curr
    endfor

    let self.currsec = l:curr
endfunc

" s:document.adjust_ad_root() {{{1
" When a Asciidoc file has a single document header technically all level 1
" sections are its children. We don't want that so we 'promote' it to level 1
" and remove any parent references to it and clear its child list.
func s:document.adjust_ad_root() abort
"    call Dfunc("s:adjust_ad_root()")

    let l:root = self.get(0)
    for l:child in l:root.children
        call l:child.remove_parent()
    endfor

    call l:root.remove_children()
    call self.change_level(l:root, 1)

"    call Dret("s:adjust_ad_root")
endfunc

" various s:document functions {{{1

func s:document.get(idx) dict abort
    return self.sections->get(a:idx, {})
endfunc

func s:document.get_root() dict abort
    return self.get(0)
endfunc

func s:document.get_top_level() dict abort
    return self.get_root().level
endfunc

func s:document.add_to_levels(section) dict abort
    if !self.levels->has_key(a:section.level)
        let self.levels[a:section.level] = []
    endif
    call add(self.levels[a:section.level], a:section.id)
endfunc

func s:document.remove_from_levels(section) dict abort
    let l:levelids = self.levels[a:section.level]
    eval l:levelids->remove(l:levelids->index(a:section.id))
    if l:levelids->empty()
        eval self.levels->remove(a:section.level)
    endif
endfunc

" Change a section's level and update the levels map
func s:document.change_level(section, newlevel) dict abort
    call self.remove_from_levels(a:section)
    let a:section.level = a:newlevel
    call self.add_to_levels(a:section)
endfunc

func s:document.is_empty() dict abort
    return self.sections->empty()
endfunc

func s:document.level_sections(level) dict abort
    let l:ret = []
    for l:id in self.ids_for_level(a:level)
        call add(l:ret, self.get(l:id))
    endfor
    return l:ret
endfunc

"func s:document.find_by_level(level) dict abort
"    let l:filtered = deepcopy(self.sections)
"    return filter(l:filtered, 'v:val.level == a:level')
"endfunc

func s:document.ids_for_level(level) dict abort
    return self.levels->get(a:level, [])
endfunc

func s:document.to_string(full=1) dict
    let l:str = ""
    for sect in self.sections
        let l:str .= sect.to_string(a:full) . "\n"
    endfor
    return l:str
endfunc

" s:convert() {{{1
" Return value is a List of Lists. Each contained list represents a header
" that will be visible in the menu. Contents: [lvl, line, title]
func s:convert(sections) abort
    let l:l = []

    for l:idx in range(0, a:sections->len()-1)
        let l:sect = a:sections[l:idx]
        if l:sect.visible
            call add(l:l, [l:sect.level, l:sect.line, l:sect.title])
        endif
    endfor

    return l:l
endfunc

" s:subtree() {{{1
"
" Return list of sections that belong to the sub-tree rooted at the provided
" section.
func s:subtree(section) abort
    let l:ret = [a:section]
    for l:child in a:section.children
        call extend(l:ret, s:subtree(l:child))
    endfor

    return l:ret
endfunc

" s:process_subtree() {{{1
"
" Runs procfunc on the given section and all its descendants.
func! s:process_subtree(section, procfunc) abort
    call a:procfunc(a:section)
    for l:child in a:section.children
        call s:process_subtree(l:child, a:procfunc)
    endfor
endfunc

" s:ancestors() {{{1
"
" Return list of sections that are ancestors to the given section.
" section.
func s:ancestors(section) abort
    if empty(a:section) | return [] | endif
    return add(Ancestors(a:section.parent), a:section)
endfunc

" s:process_ancestors() {{{1
"
" Runs procfunc on the given section and all its ancestors.
func! s:process_ancestors(section, procfunc) abort
    if empty(a:section) | return | endif
    call a:procfunc(a:section)
    call s:process_ancestors(a:section.parent, a:procfunc)
endfunc

" s:process_sections() {{{1
"
" Runs procfunc on the given section and all its ancestors.
func! s:process_sections(sections, procfunc) abort
    for l:section in a:sections
        call a:procfunc(l:section)
    endfor
endfunc

" s:set_visible_for_all() {{{1
"
" Simply sets visibility 'on' for every section in the document.
func s:set_visible_for_all(document) abort
    call s:process_sections(
                \ a:document.sections, function('s:mark_visible'))
endfunc

" s:set_visible_for_sel() {{{1

" Let's say selected section S is on level L. What are the criteria for
" whether a level's visibility is set to true for the 'sel' display mode?
"
" * section == S
" * section in S.descendants
" * section in S.siblings
" * section in S.ancestors
" * section is a top level section
"
" There's a lot of overlap, though, so we can reduce to:
"
" 1. mark all returned by S.getsubtree()
" 2. mark all in by S.parent.children
" 3. mark all found by following S.parent recursively
" 4. mark all returned by ids_for_level(get_top_level())
"
func s:set_visible_for_sel(document) abort
    let l:currsec = a:document.currsec

    " selected section's subtree
    call s:process_subtree(l:currsec, function('s:mark_visible'))

    " selected section's ancestors
    call s:process_ancestors(l:currsec, function('s:mark_visible'))

    " all top level sections
    call s:process_sections(
                \ a:document.level_sections(a:document.get_top_level()),
                \ function('s:mark_visible'))

    " all of section parent's children
    if !l:currsec.is_top_level()
        call s:process_sections(l:currsec.parent.children,
                    \ function('s:mark_visible'))
    endif
endfunc

" s:set_visible_for_anc() {{{1

" Let's say selected section S is on level L. Further, S has an ancestor
" at the top level (as all sections do) and we'll call it A. What are the
" criteria for whether a level's visibility is set to true for the 'anc'
" display mode?
"
" 'anc' is like 'sel' plus 'section in A.descendants'. By finding those
" descendant sections we most of what we need. There's just one additional
" criteriumm for a total of two:
"
" * section in A.descendants
" * section is a top level section
"
func s:set_visible_for_anc(document) abort
    call s:process_subtree(
                \ a:document.currsec.get_top_ancestor(),
                \ function('s:mark_visible'))

    call s:process_sections(
                \ a:document.level_sections(a:document.get_top_level()),
                \ function('s:mark_visible'))
endfunc

func! s:mark_visible(section) abort
    let a:section.visible = v:true
endfunc

func! s:mark_invisible(section) abort
    let a:section.visible = v:false
endfunc


" s:get_level_adjustment() {{{1
" If the first seen section isn't level 1 (or, possibly, level 0 for AD) we
" want to normalize levels so they're displayed as if first section _is_ level
" 1.  This returns a value that should be subtracted from actual levels.
func s:get_level_adjustment(level) abort
    if a:level == 0 && &ft ==? 'markdown'
        throw "MU55: Fatal. Level 0 header can't be in Markdown"
    endif
    if a:level > 1
        return a:level - 1
    endif
    return 0
endfunc

" s:document.render() {{{1

" Update section visibility based on current state, i.e. cursor location.
" Return visible sections in a format suitable for the menu drawing routine.
"
" The returned data is a list of structures containing section header
" info data of the form: [level, linenum, sectitle]
func s:document.render()
"    call Dfunc("s:document.render()")
    call self.set_current_section(line('.'))
    let l:mode = musecnav#util#get_viz_mode()

"    call Decho("Old vis: " . musecnav#util#sec_viz_string(self.sections))
    if l:mode !=? 'all'
        " First turn off visibility for all nodes
        for l:sect in self.sections
            let l:sect.visible = v:false
        endfor
    endif

    call function('s:set_visible_for_' . l:mode)(self)
"    call Decho("New vis: " . musecnav#util#sec_viz_string(self.sections))

"    call Dret("s:document.render")
    return s:convert(self.sections)
endfunc

" musecnav#document#build() {{{1

" Scan the current buffer for section headers and store them in a new document
" object along with any relevant state/attributes.
"
" Before we scan we initialize the document with a special first section that
" represents the top of the document (i.e. line 1).
"
" AsciiDoc level 0 sections require special handling.
"
" If the first found section is L0 (known as a document header) we effectively
" ignore it as the virtual section is an adequate stand in though we will use
" it's text in the title of the virtual section.
"
" If there are multiple L0 headers that means a 'book' doctype. We want to
" handle each of these like a normal section but we'll need to normalize all
" levels, i.e. L0 to L1, L1 to L2, etc. We'll do this during rendering. Note
" that the virtual section and L0s will occupy the same level when rendered.
"
" For both AD and MD we want to handle another atypical situation: top level
" is greater than 1. In those cases we normalize such that all levels are
" shifted and thus the top level is effectively L1. Again, we do this during
" render and preserve actual levels in the section records.
"
" Returns the document object.
func musecnav#document#build() abort
"    call Dfunc("doc#build()")
    let l:document = s:document.new()

    " TODO: remove this when it's not longer necessary
    " We want the '*' pattern in find_ad_section()
    let l:fdm = get(g:, "musecnav_dev_mode", 0)
    let g:musecnav_dev_mode = 1

    let l:view = winsaveview()
"    call Decho("Entering section scan loop")
    try
    call setpos('.', [0, 1, 1])

        let l:next = musecnav#search#find_section()
        let l:adjustment = s:get_level_adjustment(l:next[2])
        while !empty(l:next)
"            call Decho("Found section: " . string(l:next))
            let l:sect = l:document.add_section(
                        \ l:next[0], (l:next[2] - l:adjustment), l:next[3])
            let l:next = musecnav#search#find_section()
        endwhile
    finally
        " TODO: remove this when it's not longer necessary
        let g:musecnav_dev_mode = l:fdm

        call winrestview(l:view)
    endtry
"    call Decho("Exiting section scan loop")

    if &ft !=? 'asciidoc'
"        call Dret("doc#build - done processing MD doc")
        return l:document
    endif

    let l:rootids = l:document.ids_for_level(0)
"    call Decho("Checking root ids: " . string(l:rootids))
    if l:rootids->len() == 1
        if l:rootids[0] != 0
            throw "MU41: Doc header must precede section headers, line "
                        \ . l:document.get(0).line
        endif
        call l:document.adjust_ad_root()
"        call Decho("Adjusted  doc header: " . l:document.get(0).to_string())
    elseif l:rootids->len() > 1
        " Multiple level 0 sections. Must be book doctype
        throw "MU0: book doctype (multiple lvl 0 sections) not supported yet"
    endif

"    call Dret("doc#build - done processing AD doc")
    return l:document
endfunc

" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdc=3:fdm=marker:fmr={{{,}}}
