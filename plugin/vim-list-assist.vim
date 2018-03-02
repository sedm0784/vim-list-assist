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
" FIXME: Maybe run auto-renumbering feature whenever cursor moves and we are
"        found to be within a list item.
" FIXME: Mapping shouldn't run if cursor is on or before the list item. We
"        should still be able to insert empty lines above by using <CR> from
"        that position.
" FIXME: Can we renumber lists using v_g_CTRL-A? What about sublists? Is it
"        possible to skip these with simple visual blocks, or is overlap
"        possible, necessitating more thorough parsing?
" FIXME: The plugin breaks insert commands when a count is used! e.g.
"        5iblah<cr><esc> Can we access the count with `v:count1`? Does it help
"        if we can? (I'm guessing not.)
" FIXME: Allow user to specify filetypes where mappings should be created

let s:re_blank_line = '^\s*$'

" A "strict" implementation of <CR> which does not allow anything (notably,
" 'autoindent') to mess with indentation.
function! s:cr()
  " This function needs to behave differently if it is the second time we have
  " been called in order to correctly handle the case where we are entering
  " two newlines for a paragraph list where the cursor was positioned in the
  " middle of the item.
  "
  " When this occurs, the cursor is left ON the first character of the content
  " of the list item (because that has been inserted at the beginning of the
  " line, i.e. at column #1). Therefore we need to adjust our operations
  " accordingly.
  "
  " See test case:
  "   2 Splits existing list items
  "
  " in file:
  "   unordered_lists_paragraph-always.vader
  if s:first_cr
    let insert_command = 'a'
    let column = col(".")
  else
    let insert_command = 'i'
    let column = 0
  endif

  let line = getline(".")

  execute "normal! " . insert_command . "\<CR>"
  call setline(".", line[column:])
  let s:first_cr = 0
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

" The valid options are:
"
"     NEVER use paragraph lists
"    MANUAL - The first <CR> adds a non-paragraph list item, the second
"           converts to a paragraph list item, the third ends the list.
"      AUTO - Paragraph lists are used if the current list item is a paragraph
"           list, otherwise non-paragraph list items are used.
"    ALWAYS use paragraph lists.
let s:paragraph_option_never = 'never'
let s:paragraph_option_manual = 'manual'
let s:paragraph_option_auto = 'auto'
let s:paragraph_option_always = 'always'

function! s:paragraph_option()
  " FIXME: Maybe do a fuzzy match for typoes? Or just check for a valid value
  "        on VimEnter.
  return tolower(get(g:, 'list_assist_paragraphs', 'auto'))
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
    if s:paragraph_option() == s:paragraph_option_manual && empty
      " Special cases for manual paragraph list option: an empty list item can
      " either mean we want to end the list, or it can mean we just pressed
      " return and want to convert the new item we just added into a
      " paragraph list item.

      if previous_line =~ s:re_blank_line
        " Unset paragraph, because we are not in a paragraph. We want to end
        " the list by simply clearing the current line.
        return [list_marker, 1, 0]
      endif

      " Check if the current marker matches the marker from the previous line.
      " For unordered lists, this just means if the markers are the same. For
      " ordered lists, it means if this marker is one higher than the
      " previous. We can test both using the same comparision, because
      " increment_marker doesn't do anything for unordered lists.
      let [previous_marker, previous_empty, previous_paragraph] = s:in_list_item(a:line_index - 1)

      if list_marker == s:increment_marker(previous_marker)
        " Set paragraph, because we want to clear the current line and add a
        " new list item below.
        return [previous_marker, 1, 1]
      endif
    endif

    if s:paragraph_option() == s:paragraph_option_always
      let paragraph = 1
    else
      let paragraph = 0
    endif

    if s:paragraph_option() == s:paragraph_option_auto
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

function! s:increment_marker(list_marker)
  let list_ordinal = matchstr(a:list_marker, '\d\+')
  if strlen(list_ordinal) == 0
    return a:list_marker
  endif

  " FIXME: account for 999999999 case
  let list_ordinal = list_ordinal + 1
  return substitute(a:list_marker, '\d\+', list_ordinal, "")
endfunction


function! s:return_to_insert(list_marker)
  " Return to insert mode
  let current_line = getline(".")
  if current_line == a:list_marker
    " Append

    startinsert!
  else
    " Place cursor in correct position and insert
    call cursor(0, strlen(a:list_marker) + 1)
    startinsert
  endif
endfunction

function! s:perform_cr_in_list_item(line_index, list_marker, empty, paragraph)
  if a:empty && (s:paragraph_option() != s:paragraph_option_manual || !a:paragraph)
    " Empty list item that we want to end

    " We don't need a newline if we're ending a manual-paragraph list, because
    " one already exists
    " We don't need a newline if we're in an automatic paragraph, because one
    " already exists.
    if s:paragraph_option() != s:paragraph_option_manual && !a:paragraph
      call s:cr()
    endif
    " And clear the empty list item
    call setline(a:line_index, "")

    call s:return_to_insert(a:list_marker)
  else
    " Non-empty list item or empty item that we need to move down a line
    " (after the second press of Return with "paragraphs" option set to
    " "manual").
    let l:list_marker = s:increment_marker(a:list_marker)

    if a:paragraph && s:paragraph_option() != s:paragraph_option_manual
      " Add an extra newline
      call s:cr()
    endif

    call s:cr()
    let current_line = getline(".")
    call setline(".", l:list_marker . current_line)

    if a:empty
      " The "paragraphs" option is set to manual, the existing list item is
      " empty, and we just created a new list item on the line below. We need
      " to delete the existing empty list item.
      call setline(a:line_index, "")
    endif

    call s:return_to_insert(l:list_marker)
  endif
endfunction

" This function is invoked by the expression mapping. It returns either "<CR>"
" to perform a normal <CR>, or a string that will perform the add-list-item or
" end-list operation.
function! s:auto_list()
  " See the function s:cr() for why this variable is required
  let s:first_cr = 1

  " First, we need to check if we're in a list.
  let line_index = line(".")
  let [list_marker, empty, paragraph] = s:in_list_item(line_index)

  if strlen(list_marker) == 0
    return "\<CR>"
  else
    return "\<Esc>:call " . s:SID() . "perform_cr_in_list_item("
      \ . line_index
      \ . ", '" . list_marker . "', "
      \ . empty . ", "
      \ . paragraph . ")\<CR>"
  endif
endfunction

" We can't use <SID> in the value returned from our expression map because the
" code is actually executed outside of the context of the script. We need to
" emulate its behaviour in code, as described towards the bottom of :h <SID>.
function! s:SID()
  return "<SNR>" . matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$') . "_"
endfun

" N.B. Currently only enabled for return key in insert mode, not for normal
" mode 'o' or 'O'
autocmd FileType markdown inoremap <expr> <buffer> <CR> <SID>auto_list()
autocmd FileType text inoremap <expr> <buffer> <CR> <SID>auto_list()
autocmd FileType mail inoremap <expr> <buffer> <CR> <SID>auto_list()
