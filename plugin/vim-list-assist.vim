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
" FIXME: Check/test for problems when checking lines before beginning of file
"        (subtracting past line index 1)

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

" Tests if two markers are in the same list
function! s:ordered_markers_match(first_marker, second_marker)
  if a:first_marker !~ '\d' || a:second_marker !~ '\d'
    " One of the lists is not an ordered list
     return 0
  elseif indent(a:second_marker) >= strlen(a:first_marker)
    " If the second marker is indented past the first one, it's a sublist
    return 0
  endif

  return 1
endfunction

" 0: NEVER use paragraph lists
" 1: MANUAL paragraph lists. The first <CR> adds a non-paragraph list item, the
"    second converts to a paragraph list item, the third ends the list.
" 2: AUTOMATIC paragraph lists. Paragraph lists are used if the current list
"    item is a paragraph list, otherwise non-paragraph list items are used.
" 3: ALWAYS use paragraph lists.
function! s:paragraph_option()
  return get(g:, 'vim_list_assist_paragraphs', 2)
endfunction

" Tests if a line is within a list item
"
" Returns a list containing:
" - the marker, including the surrounding spacing
" - a boolean "empty" to indicate whether the list item has any contents
" - a boolean "paragraph" to indicate whether the list item was separated from
"   a previous list item by an empty line
function! s:in_list_item(line_index)
  let [list_marker, empty] = s:get_list_marker(a:line_index)

  let previous_line = getline(a:line_index - 1)

  if strlen(list_marker) != 0
    if s:paragraph_option() == 1 && empty
      " Special case for manual paragraph list option.
      if previous_line =~ s:re_blank_line
        " Unset paragraph, because we are not in a paragraph. We want to end
        " the list by simply clearing the current line.
        return [list_marker, 1, 0]
      endif

      let [previous_marker, previous_empty, previous_paragraph] = s:in_list_item(a:line_index - 1)
      " FIXME: Use == for unordered lists. Check that the list index is one
      "        higher than previous for ordered lists.
      if list_marker == previous_marker
        " Set paragraph, because we want to clear the current line and add a
        " new list item below.
        return [list_marker, 1, 1]
      endif
    endif

    if s:paragraph_option() == 3
      let paragraph = 1
    else
      let paragraph = 0
    endif

    if s:paragraph_option() == 2
      " Test if the line above is blank AND the line above that is in a list
      " of the same type as this one. If so, we are in a paragraph list.
      if getline(a:line_index - 1) =~ s:re_blank_line
        let [previous_marker, previous_empty, previous_paragraph] = s:in_list_item(a:line_index - 2)
        if previous_marker == list_marker || s:ordered_markers_match(previous_marker, list_marker)
          let paragraph = 1
        endif
      endif
    endif
    return [list_marker, empty, paragraph]
  endif

  let this_line = getline(a:line_index)

  " Check if this_line is blank.
  if this_line =~ s:re_blank_line
    " Pressing enter on a blank line should never result in a new list item.
    " FIXME: Arguably, pressing enter on a blank line within a paragraph
    "        list should create a new (correctly spaced) list item.
    return ["", 0, 0]
  endif

  if previous_line !~ s:re_blank_line
    " Line above is NOT blank: recurse
    return s:in_list_item(a:line_index - 1)
  else
    " Line above IS blank: Check indent
    let this_indent = indent(a:line_index)
    if this_indent < 2
      " Indent is less than two. We cannot be in a list
      return ["", 0, 0]
    else
      " If indent greater than or equal to any previous list marker, then
      " we're in that list
      let [list_marker, empty, paragraph] = s:in_list_item(a:line_index - 2)

      if this_indent >= strlen(list_marker)
        " N.B. This also returns correct value ("") if line above is NOT in a
        " list item.
        return [list_marker, empty, paragraph]
      else
        " Not in the same list item as previous non-blank line
        " FIXME: Check for list items further up, too, to handle lists with
        " sub lists
        return ["", 0, 0]
      endif
    endif
  endif
endfunction

function! s:auto_list()
  " First, we need to check if we're in a list.
  let line_index = line(".")
  let [list_marker, empty, paragraph] = s:in_list_item(line_index)

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
  elseif empty && (s:paragraph_option() != 1 || !paragraph)
    " Empty list item

    " We don't need a newline if we're ending a manual-paragraph list, because
    " one already exists
    " We don't need a newline if we're in an automatic paragraph, because one
    " already exists.
    if s:paragraph_option() != 1 && !paragraph
      call s:cr()
    endif
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

    if paragraph && s:paragraph_option() != 1
      " Add an extra newline
      call s:cr()
    endif

    call s:cr()
    let current_line = getline(".")
    call setline(".", list_marker . current_line)

    if empty && s:paragraph_option() == 1
      " And clear the empty list item
      call setline(line_index, "")
    endif
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
