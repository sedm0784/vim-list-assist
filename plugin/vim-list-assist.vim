" Auto lists: Automatically continue/end lists by adding markers if the
" previous line is a list item, or removing them when they are empty

" *** FEATURE TO DO LIST ***
" FIXME: Support code blocks within list items: We should continue the block,
"        not the item.
" FIXME: Markdown allows tabs instead of spaces in places
" FIXME: List markers must be followed by one or more spaces OR A TAB
" FIXME: List items can be inside blockquotes
" FIXME: Empty list items are allowed in markdown. Test thoroughly what
"        happens when they exist at various locations in the list.

let s:re_blank_line = '^\s*$'

" A "strict" implementation of <CR> which does not allow anything (notably,
" 'autoindent') to mess with indentation.
function! s:cr()
  let column = col(".")
  let line = getline(".")

  execute "normal! a\<CR>"
  call setline(".", line[column:])
endfunction

" Analyses a single line to see if it begins with a list marker.
"
" Returns the marker, including the surrounding spacing and a boolean "empty"
" to indicate whether the list item has any contents
function! s:get_list_marker(line_index)
  let this_line = getline(a:line_index)

  " Match spacing_bullet_spacing_non-whitespace-character
  let list_marker = matchstr(this_line, '\v^ {,3}(-|\+|\*) {1,4}\S?')

  if strlen(list_marker) == 0
    " Match spacing_ordinal_spacing_non-whitespace-character
    let list_marker = matchstr(this_line, '\v^ {,3}\d{1,9}(\.|\)) {1,4}\S?')
  endif

  if strlen(list_marker) == 0
    return ["", 0]
  endif

  if list_marker[-1:] == " "
    " Return empty
    return [list_marker, 1]
  else
    " Remove the extra character, and return non-empty
    return [list_marker[:-2], 0]
  endif

endfunction

" Tests if a line is within a list item
"
" Returns the marker, including the surrounding spacing and a boolean "empty"
" to indicate whether the list item has any contents
function! s:in_list_item(line_index)
  let [list_marker, empty] = s:get_list_marker(a:line_index)
  if strlen(list_marker) != 0
    return [list_marker, empty]
  endif

  let this_line = getline(a:line_index)
  let previous_line = getline(a:line_index - 1)

  " Need to check if this_line is blank. Pressing enter on a blank line
  " should never result in a new list item.
  " FIXME: Arguably, pressing enter on a blank line within a paragraph list
  " should create a new (correctly spaced) list item.
  if this_line =~ s:re_blank_line
    return ["", 0]
  endif

  if previous_line !~ s:re_blank_line
    " Line above is NOT blank: recurse
    return s:in_list_item(a:line_index - 1)
  else
    " Line above IS blank: Check indent
    let this_indent = indent(a:line_index)
    if this_indent < 2
      " Indent is less than two. We cannot be in a list
      return ["", 0]
    else
      " If indent greater than or equal to any previous list marker, then
      " we're in that list
      let [list_marker, empty] = s:in_list_item(a:line_index - 2)

      if this_indent >= strlen(list_marker)
        " N.B. This also returns correct value ("") if line above is NOT in a
        " list item.
        return [list_marker, empty]
      else
        " Not in the same list item as previous non-blank line
        " FIXME: Check for list items further up, too, to handle lists with
        " sub lists
        return ["", 0]
      endif
    endif
  endif
endfunction

function! s:auto_list()
  " First, we need to check if we're in a list.
  let line_index = line(".")
  let [list_marker, empty] = s:in_list_item(line_index)

  if strlen(list_marker) == 0
    " Not in a list
    " Add the newline.
    call s:cr()
    " FIXME: ensure that autoindent white-space fiddling is PRESERVED when
    " pressing CR outside of a list. i.e. behaviour should be different
    " depending on whether autoindent is set.

    " N.B. There is a problem here in that autoindent functionality is lost if
    " the execute statement completes without "typing" anything. Hack around
    " this by "typing" a dot and then immediately removing it again.
    " FIXME: This hack is inadequate. We need to remove indent again if <esc>
    " or <cr> are pressed.
    " FIXME: It also completely breaks if we press <CR> in the middle of a
    " line!
    "execute "normal! a\<CR>."
    "call setline(".", getline(".")[:-2])
    " Also hack around putting cursor in correct place
    "let list_marker = getline(".")
  elseif empty
    " Empty list item
    " Add the newline
    call s:cr()
    " And clear the empty list item
    call setline(line_index, "")
  else
    " Non-empty list item
    let list_ordinal = matchstr(list_marker, '\d\+')
    if strlen(list_ordinal) > 0
      " FIXME: account for 999999999 case
      let list_ordinal = list_ordinal + 1
      let list_marker = substitute(list_marker, '\d\+', list_ordinal, "")
    endif

    call s:cr()
    let current_line = getline(".")
    call setline(".", list_marker . current_line)
  endif

  " Return to insert mode
  let current_line = getline(".")
  if current_line == list_marker
    " Append
    startinsert!
  else
    " Place cursor in correct position and insert
    call cursor(0, strlen(list_marker) + 1)
    startinsert
  endif
endfunction

" N.B. Currently only enabled for return key in insert mode, not for normal
" mode 'o' or 'O'
autocmd FileType markdown inoremap <buffer> <CR> <Esc>:call <SID>auto_list()<CR>
