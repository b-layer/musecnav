let s:save_cpo = &cpoptions
set cpoptions&vim

let s:document = {}

" s:document.new() {{{1
function! s:document.new(searchobj)
    let newDoc = copy(self)
    let newDoc.sections = []
    let newDoc.levels = {}
    let newDoc.currsec =  #{line: 0, level: 0}
    let newDoc._lastlevel = -1
    let newDoc.searchobj = a:searchobj

    return newDoc
endfunction

" s:document.add_section() {{{1
" OR do we pass section fields and build the section in this function?
function! s:document.add_section(line, level, title) dict abort
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
endfunction

" s:document.set_curr_sec() {{{1
"
" Given a line number locate the containing section and set the document's
" current section field.
function! s:document.set_curr_sec(line) abort
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
endfunction

" s:document.adjust_ad_root() {{{1
" When a Asciidoc file has a single document header technically all level 1
" sections are its children. We don't want that so we 'promote' it to level 1
" and remove any parent references to it and clear its child list.
function! s:document.adjust_ad_root() abort
    let l:root = self.get(0)
    for l:child in l:root.children
        call l:child.remove_parent()
    endfor

    call l:root.remove_children()
    call self.change_level(l:root, 1)
endfunction

" various s:document functions {{{1

function! s:document.add_search_obj(searchobj) dict abort
    let self.searchobj = a:searchobj
endfunction

function! s:document.search() dict abort
    return self.searchobj
endfunction

function! s:document.curr_sec_line() dict abort
    return self.currsec.line
endfunction

function! s:document.curr_sec_level() dict abort
    return self.currsec.level
endfunction

function! s:document.get(idx) dict abort
    return self.sections->get(a:idx, {})
endfunction

function! s:document.get_root() dict abort
    return self.get(0)
endfunction

function! s:document.get_top_level() dict abort
    return self.get_root().level
endfunction

function! s:document.add_to_levels(section) dict abort
    if !self.levels->has_key(a:section.level)
        let self.levels[a:section.level] = []
    endif
    call add(self.levels[a:section.level], a:section.id)
endfunction

function! s:document.remove_from_levels(section) dict abort
    let l:levelids = self.levels[a:section.level]
    eval l:levelids->remove(l:levelids->index(a:section.id))
    if l:levelids->empty()
        eval self.levels->remove(a:section.level)
    endif
endfunction

" Change a section's level and update the levels map
function! s:document.change_level(section, newlevel) dict abort
    call self.remove_from_levels(a:section)
    let a:section.level = a:newlevel
    call self.add_to_levels(a:section)
endfunction

function! s:document.is_empty() dict abort
    return self.sections->empty()
endfunction

function! s:document.level_sections(level) dict abort
    let l:ret = []
    for l:id in self.ids_for_level(a:level)
        call add(l:ret, self.get(l:id))
    endfor
    return l:ret
endfunction

"func s:document.find_by_level(level) dict abort
"    let l:filtered = deepcopy(self.sections)
"    return filter(l:filtered, 'v:val.level == a:level')
"endfunc

function! s:document.ids_for_level(level) dict abort
    return self.levels->get(a:level, [])
endfunction

function! s:document.to_string(full=1) dict
    let l:str = ""
    for sect in self.sections
        let l:str .= sect.to_string(a:full) . "\n"
    endfor
    return l:str
endfunction

" s:extract_menu_data() {{{1
"
" Processes given sections into a list of lists. Each inner list represents a
" visible section and contains three attributes: level, line number and title.
"
" Example inner list: [2, 289, 'This is a Title']
function! s:extract_menu_data(sections) abort
    let l:l = []

    for l:idx in range(0, a:sections->len()-1)
        let l:sect = a:sections[l:idx]
        if l:sect.visible
            call add(l:l, [l:sect.level, l:sect.line, l:sect.title])
        endif
    endfor

    return l:l
endfunction

" s:subtree() {{{1
"
" Return list of sections that belong to the sub-tree rooted at the provided
" section.
function! s:subtree(section) abort
    let l:ret = [a:section]
    for l:child in a:section.children
        call extend(l:ret, s:subtree(l:child))
    endfor

    return l:ret
endfunction

" s:process_subtree() {{{1
"
" Runs procfunc on the specified section and all its descendants.
function! s:process_subtree(section, procfunc) abort
    call a:procfunc(a:section)
    for l:child in a:section.children
        call s:process_subtree(l:child, a:procfunc)
    endfor
endfunction

" s:ancestors() {{{1
"
" Return list of sections that are ancestors to the given section.
" section.
function! s:ancestors(section) abort
    if empty(a:section) | return [] | endif
    return add(Ancestors(a:section.parent), a:section)
endfunction

" s:process_ancestors() {{{1
"
" Runs procfunc on the specified section and all its ancestors.
function! s:process_ancestors(section, procfunc) abort
    if empty(a:section) | return | endif
    call a:procfunc(a:section)
    call s:process_ancestors(a:section.parent, a:procfunc)
endfunction

" s:process_sections() {{{1
"
" Runs procfunc on the specified sections
function! s:process_sections(sections, procfunc) abort
    for l:section in a:sections
        call a:procfunc(l:section)
    endfor
endfunction

" s:set_visibility_for_all() {{{1

" Set section visiblity for the 'all' display mode. Every section in the
" hierarchy will be marked as visible.
"
function! s:set_visibility_for_all(document) abort
    call s:process_sections(
                \ a:document.sections, function('s:mark_visible'))
endfunction

" s:set_visibility_for_sel() {{{1

"                                                                         {{{2
" Set section visiblity for the 'sel' (selection) display mode.
"
" If the selected section, S, is on level L then a section will be visible if
" it meets one of these criteria:
"
" * section == S
" * section in S.descendants
" * section in S.siblings
" * section in S.ancestors
" * section is a top level section
"
" With some overlap that translates to the union of the following:
"
" 1. sections returned by S.getsubtree()
" 2. sections in S.parent.children
" 3. sections found by following S.parent recursively
" 4. sections returned by ids_for_level(get_top_level())
"                                                                          }}}
function! s:set_visibility_for_sel(document) abort
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
endfunction

" s:set_visibility_for_anc() {{{1

"                                                                         {{{2
" Set section visiblity for the 'anc' (ancestor) display mode.
"
" For the selected section, S, we'll call the most distant ancestor (in the
" topmost level) A. The visible sections are the union of the sections visible
" in 'sel' mode and all of A's descendants. Put another way, the criteria for
" section visibility in this mode has two criteria:
"
" * section in A.descendants
" * section is a top level section
"                                                                          }}}
function! s:set_visibility_for_anc(document) abort
    call s:process_subtree(
                \ a:document.currsec.get_top_ancestor(),
                \ function('s:mark_visible'))

    call s:process_sections(
                \ a:document.level_sections(a:document.get_top_level()),
                \ function('s:mark_visible'))
endfunction

function! s:mark_visible(section) abort
    let a:section.visible = v:true
endfunction

function! s:mark_invisible(section) abort
    let a:section.visible = v:false
endfunction


" s:get_level_adjustment() {{{1

" If the first seen section isn't level 1 (or, possibly, L0 for AD) we want to
" normalize levels so they're displayed as if first section _is_ level 1.
"
" Returns a value that should be subtracted from actual levels.
function! s:get_level_adjustment(level) abort
    if a:level == 0 && &ft ==? 'markdown'
        throw "MU55: Fatal. Level 0 header can't be in Markdown"
    endif
    if a:level > 1
        return a:level - 1
    endif
    return 0
endfunction

" s:document.render() {{{1

" Update section visibility based on current state, i.e. cursor location.
" Return visible sections in a format suitable for the menu drawing routine.
"
" The returned data is a list containing lists of section header attributes
" with the form: [level, linenum, title]
function! s:document.render()
"    call Dfunc("s:document.render()")
    call self.set_curr_sec(line('.'))

    let l:mode = musecnav#util#get_disp_mode()
    if l:mode !=? 'all'
        " Reset visibility of all nodes
        call s:process_sections(self.sections, function('s:mark_invisible'))
    endif

    " Set node visibility per the display mode
    call function('s:set_visibility_for_' . l:mode)(self)

"    call Dret("s:document.render")
    return s:extract_menu_data(self.sections)
endfunction

" musecnav#document#build() {{{1

"                                                                         {{{2
" Scan the current buffer for section headers and store them in a new document
" object along with any relevant state/attributes.
"
" Before we scan we initialize the document with a special first section that
" represents the top of the document (i.e. line 1). A 'virtual' section.
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
"                                                                          }}}
function! musecnav#document#build(searchobj) abort
"    call Dfunc("doc#build()")
    let l:document = s:document.new(a:searchobj)

    let l:view = winsaveview()
"    call Decho("Entering section scan loop")
    try
    call setpos('.', [0, 1, 1])

        let l:next = l:document.search().find_section()
        if empty(l:next)
            throw "MU40: No section headers found!"
        endif
        let l:adjustment = s:get_level_adjustment(l:next[2])
        while !empty(l:next)
            let l:sect = l:document.add_section(
                        \ l:next[0], (l:next[2] - l:adjustment), l:next[3])
            let l:next = l:document.search().find_section()
        endwhile
    finally
        call winrestview(l:view)
    endtry

    if !b:musecnav.adtype
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
"        call Decho("Adjusting doc header: " . l:document.get(0).to_string())
        call l:document.adjust_ad_root()
    elseif l:rootids->len() > 1
        " Multiple level 0 sections. Must be book doctype
        throw "MU0: book doctype (multiple lvl 0 sections) not supported yet"
    endif

"    call Dret("doc#build - done processing AD doc")
    return l:document
endfunction

" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdm=marker:fmr={{{,}}}
