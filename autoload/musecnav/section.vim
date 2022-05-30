let s:save_cpo = &cpoptions
set cpoptions&vim

function! musecnav#section#new(id, line, level, title)
    let obj = {}
    let obj.id = a:id
    let obj.line = a:line
    let obj.level = a:level
    let obj.title = a:title

    let obj.visible = v:false
    let obj.parent = {}
    let obj.children = []

    func obj.initialize() dict abort
        return self
    endfunc

    func obj.is_top_level() dict abort
        return self.parent->empty()
    endfunc

    func obj.get_parent() dict abort
        return self.parent
    endfunc

    func obj.remove_parent() dict abort
        let self.parent = {}
    endfunc

    func obj.set_parent(parent) dict abort
        let self.parent = a:parent
        call a:parent.add_child(self)
    endfunc

    func obj.add_child(child) dict abort
        call add(self.children, a:child)
    endfunc

    func obj.remove_children() dict abort
        call remove(self.children, 0, -1)
    endfunc

    func! obj.get_top_ancestor() abort
        return self.is_top_level() ? self : self.parent.get_top_ancestor()
    endfunc

    func obj.to_string(full = 0) dict
        let l:str = printf("%s[%d] line: %d, lvl: %d, title: %s",
                \ (self.visible ? '+' : '-'),
                \ self.id, self.line, self.level, self.title)
        if a:full
            let l:str .= printf(", parent: %s, children: %s", 
                    \ self.parent->empty() ? '-' : self.parent.id,
                    \ musecnav#util#list_dict_vals('id', self.children))
        endif
        return l:str
    endfunc

    return obj.initialize()
endfunction

" Likely functions
" * getMenuFields() : return [line, level, title] for popup drawing use

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:fdl=2:fdc=3:fdm=marker:fmr={{{,}}}
