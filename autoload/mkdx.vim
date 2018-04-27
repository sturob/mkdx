""""" UTILITY FUNCTIONS
let s:_is_nvim               = has('nvim')
let s:_can_async             = s:_is_nvim || has('job')
let s:util                   = {}
let s:util.modifier_mappings = {
      \ 'C': 'ctrl',
      \ 'M': 'meta',
      \ 'S': 'shift',
      \ 'ctrl': 'ctrl',
      \ 'meta': 'meta',
      \ 'shift': 'shift'
      \ }

fun! s:util.CsvRowToList(...)
  let line     = substitute(get(a:000, 0, getline('.')), '^\s\+|\s\+$', '', 'g')
  let len      = strlen(line) - 1
  let colcount = range(0, len)

  if (len < 1) | return [] | endif

  let quote    = ""
  let escaped  = 0
  let currcol  = ""
  let result   = []

  for idx in colcount
    let char = line[idx]
    if (escaped)
      let currcol .= char
      let escaped  = 0
    elseif (char == "\\")
      let escaped = 1
    elseif (!empty(quote))
      if (char != quote)
        let currcol .= char
      else
        let quote = ""
      endif
    elseif ((char == "'") || (char == "\""))
      let quote = char
    elseif ((char == ",") || (char == "\t"))
      call add(result, currcol)
      let currcol = ""
    else
      let currcol .= char
    endif
  endfor

  if (!empty(currcol))
    call add(result, currcol)
  endif

  return result
endfun

fun! s:util.ExtractCurlHttpCode(data, ...)
  let status = s:_is_nvim ? get(get(a:000, 1, []), 0, '404') : get(a:000, 1, '404')
  let status = status =~ '\D' ? 500 : str2nr(status)
  let qflen  = len(getqflist())
  let total  = a:data[0]

  if (status < 200 || status > 299)
    let [total, bufnum, lnum, column, url] = a:data
    let suff   = status == 0 ? '---' : repeat('0', 3 - strlen(status)) . status
    let text   = suff . ': ' . url
    let qflen += 1

    call setqflist([{'bufnr': bufnum, 'lnum': lnum, 'col': column + 1, 'text': text, 'status': status}], 'a')
    if (qflen == 1) | copen | endif
  endif

  if (qflen > 0) | echohl ErrorMsg | else | echohl MoreMsg | endif
  echo qflen . '/' . total . ' dead link' . (qflen == 1 ? '' : 's')
  echohl None
endfun

fun! s:util.GetRemoteUrl()
  if (!empty(g:mkdx#settings.links.external.host))
    return g:mkdx#settings.links.external.host
  endif

  let remote = system('git ls-remote --get-url 2>/dev/null')

  if (!v:shell_error && strlen(remote) > 4)
    let secure = remote[0:4] == "https"
    let branch = system('git branch 2>/dev/null | grep "\*.*"')
    if (!v:shell_error && strlen(branch) > 0)
      let remote = substitute(substitute(remote[0:-2], '^\(\(https\?:\)\?//\|.*@\)\|\.git$', '', 'g'), ':', '/', 'g')
      let remote = (secure ? 'https' : 'http') . '://' . remote . '/blob/' . branch[2:-2] . '/'
      return remote
    endif
    return ''
  endif
  return ''
endfun

fun! s:util.AsyncDeadExternalToQF(...)
  let resetqf  = get(a:000, 0, 1)
  let prev_tot = get(a:000, 1, 0)
  let _pt      = prev_tot
  let external = s:util.ListExternalLinks()
  let ext_len  = len(external)
  let bufnum   = bufnr('%')
  let total    = ext_len + prev_tot
  let remote   = ext_len > 0 ? s:util.GetRemoteUrl() : ''
  let skip_rel = g:mkdx#settings.links.external.relative == 0 ? 1 : (ext_len > 0 && empty(remote))

  if (resetqf) | call setqflist([]) | endif

  for [lnum, column, url] in external
    let has_frag = url[0]   == '#'
    let has_prot = url[0:1] == '//'
    let has_http = url[0:3] == 'http'

    if (!skip_rel && !has_frag && !has_http && !has_prot)
      let url = substitute(remote, '/\+$', '', '') . '/' . substitute(url, '^/\+', '', '')
    endif

    let cmd = 'curl -L -I -s --no-keepalive -o /dev/null -A "' . g:mkdx#settings.links.external.user_agent . '" -m ' . g:mkdx#settings.links.external.timeout . ' -w "%{http_code}" "' . url . '"'

    if (!skip_rel)
      if (s:_is_nvim)
        call jobstart(cmd, {'on_stdout': function(s:util.ExtractCurlHttpCode, [[total, bufnum, lnum, column, url]])})
      elseif (s:_can_async)
        call job_start(cmd, {'pty': 0, 'out_cb': function(s:util.ExtractCurlHttpCode, [[total, bufnum, lnum, column, url]])})
      endif
    endif
  endfor

  return external
endfun

fun! s:util.ListLinks()
  let limit = line('$') + 1
  let lnum  = 1
  let links = []

  while (lnum < limit)
    let line = getline(lnum)
    let col  = 0
    let len  = len(line)

    while (col < len)
        if (tolower(synIDattr(synID(lnum, 1, 0), 'name')) == 'markdowncode') | break | endif
        let tcol = match(line[col:], '\](\(#\?[^)]\+\))')
        let href = tcol > -1 ? -1 : match(line[col:], 'href="\(#\?[^"]\+\)"')
        let html = href > -1
        if ((html && href < 0) || (!html && tcol < 0)) | break | endif
        let col += html ? href : tcol
        let rgx  = html ? 'href="\(#\?[^"]\+\)"' : '\](\(#\?[^)]\+\))'

        let matchtext = get(matchlist(line[col:], rgx), 1, -1)
        if (matchtext == -1) | break | endif

        call add(links, [lnum, col + (html ? 6 : 2), matchtext])
        let col += len(matchtext)
    endwhile

    let lnum += 1
  endwhile

  return links
endfun

fun! s:util.ListExternalLinks()
  return filter(s:util.ListLinks(), {idx, val -> val[2][0] != '#'})
endfun

fun! s:util.ListFragmentLinks()
  return filter(s:util.ListLinks(), {idx, val -> val[2][0] == '#'})
endfun

fun! s:util.FindDeadFragmentLinks()
  let headers = {}
  let hashes  = []
  let dead    = []
  let src     = s:util.ListHeaders()
  let frags   = s:util.ListFragmentLinks()
  let bufnum  = bufnr('%')

  for [lnum, lvl, line, hash, sfx] in src
    call add(hashes, '#' . hash . sfx)
  endfor

  for [lnum, column, hash] in frags
    let exists = 0

    for existing in hashes
      if (hash == existing) | let exists = 1 | break | endif
    endfor

    if (!exists) | call add(dead, {'bufnr': bufnum, 'lnum': lnum, 'col': column + 1, 'text': hash}) | endif
  endfor

  return [dead, len(frags)]
endfun

fun! s:util.WrapSelectionOrWord(...)
  let mode  = get(a:000, 0, 'n')
  let start = get(a:000, 1, '')
  let end   = get(a:000, 2, start)
  let _r    = @z

  if (mode != 'n')
    let [slnum, scol] = getpos("'<")[1:2]
    let [elnum, ecol] = getpos("'>")[1:2]

    call cursor(elnum, ecol)
    exe 'normal! a' . end
    call cursor(slnum, scol)
    exe 'normal! i' . start
    call cursor(elnum, ecol)
  else
    normal! "zdiw
    let nl = virtcol('.') == strlen(getline('.'))
    let @z = start . @z . end
    exe 'normal! "z' . (nl ? 'p' : 'P')
  endif

  let zz = @z
  let @z = _r
  return zz
endfun

fun! s:util.IsDetailsTag(lnum)
  return substitute(getline(a:lnum), '[ \t]\+', '', 'g') == '</details>'
endfun

fun! s:util.IsHeader(lnum)
  return match(getline(a:lnum), '^[ \t]*#\{1,6}') > -1
endfun

fun! s:util.IsImage(str)
  if (empty(g:mkdx#settings.image_extension_pattern)) | return 0 | endif
  return match(get(split(a:str, '\.'), -1, ''), g:mkdx#settings.image_extension_pattern) > -1
endfun

fun! s:util.ToggleMappingToKbd(str)
  let input = a:str
  let parts = split(input, '[-\+]')
  let state = { 'regular': 0, 'meta': 0, 'ctrl': 0, 'shift': 0 }
  let ilen  = len(parts) - 1
  let idx   = 0
  let out   = []
  let res   = -1

  for key in parts
    if (match(key, '/kbd') > -1)
      let result = substitute(key, '</\?kbd>', '', 'g')
    else
      let is_mod         = has_key(s:util.modifier_mappings, key)
      let updater        = is_mod ? s:util.modifier_mappings[key] : 'regular'
      let result         = is_mod && state[updater] == 0 ? s:util.modifier_mappings[key] : tolower(key)
      let result         = idx == ilen ? tolower(key) : result
      let updater        = idx == ilen ? 'regular' : updater
      let state[updater] = 1
      let idx           += 1
      let result         = '<kbd>' . result . '</kbd>'
    endif

    call add(out, result)
  endfor

  return join(out, '+')
endfun

fun! s:util.ToggleTokenAtStart(line, token, ...)
  let line   = a:line
  let tok_re = '^' . a:token . ' '

  if (match(line, tok_re) > -1)
    return substitute(line, tok_re, '', '')
  elseif (!empty(line))
    return get(a:000, 0, a:token) . ' ' . line
  else
    return line
  endif
endfun

fun! s:util.ToggleLineType(line, type)
  if (empty(a:line)) | return a:line | endif

  let li_re = '\([0-9.]\+\|[' . join(g:mkdx#settings.tokens.enter, '') . ']\) '

  if (a:type == 'list')
    " if a:line is a list item, remove the list marker and return
    if (match(a:line, '^ *' . li_re) > -1)
      return substitute(a:line, '^\( *\)' . li_re . ' *', '\1', '')
    endif

    " if a:line isn't a list item, turn it into one
    return substitute(a:line, '^\( *\)', '\1' . g:mkdx#settings.tokens.list . ' ', '')
  elseif (a:type == 'checklist')
    " if a:line is a checklist item, remove the checklist marker and return
    if (match(a:line, '^ *' . li_re . ' *\[.\]') > -1)
      return substitute(a:line, '^\( *\)' . li_re . ' *\[.\] *', '\1', '')
    endif

    " if a:line is a checkbox, replace it with g:mkdx#settings.tokens.list followed
    " by a space and the checkbox with checkbox state intact
    if (match(a:line, '^ *\[.\]') > -1)
      return substitute(a:line, '^\( *\)\[\(.\)\]', '\1' . g:mkdx#settings.tokens.list . ' [\2]', '')
    endif

    " if a:line is a regular list item, replace it with the respective list
    " token and a checkbox with state of g:mkdx#settings.checkbox.initial_state
    if (match(a:line, '^ *' . li_re) > -1)
      return substitute(a:line, '^\( *\)' . li_re, '\1\2 [' . g:mkdx#settings.checkbox.initial_state . ']', '')
    endif

    " if it isn't one of the above, turn it into a checklist item
    return substitute(a:line, '^\( *\)', '\1' . g:mkdx#settings.tokens.list . ' [' . g:mkdx#settings.checkbox.initial_state . '] ', '')
  elseif (a:type == 'checkbox')
    " if a:line is a checkbox, remove the checkbox and return
    if (match(a:line, '^ *\[.\]') > -1) | return substitute(a:line, '^\( *\)\[.\] *', '\1', '') | endif

    " if a:line is a checklist item, remove the checkbox and return
    if (match(a:line, '^ *' . li_re . ' \[.\]') > -1)
      return substitute(a:line, '^\( *\)' . li_re . ' \(\[.\]\)', '\1\2', '')
    endif

    " if a:line is a list item, add a checkbox with a state of g:mkdx#settings.checkbox.initial_state
    if (match(a:line, '^ *' . li_re) > -1)
      return substitute(a:line,  '^\( *\)' . li_re, '\1\2 [' . g:mkdx#settings.checkbox.initial_state . ']', '')
    endif
    " otherwise, if it isn't a checkbox item, turn it into one
    return substitute(a:line, '^\( *\)', '\1' . '[' . g:mkdx#settings.checkbox.initial_state . '] ', '')
  elseif (a:type == 'off')
    " if a:line is either a list, checklist or checkbox item, remove the
    " marking while maintaining whitespace
    return substitute(a:line, '^\( *\)\(' . li_re . ' \?\)\?\(\[.\]\)\? *', '\1', '')
  endif

  return a:line
endfun

fun! s:util.ListHeaders()
  let headers = []
  let skip    = 0
  let bnum    = bufnr('%')
  let hashes  = {}

  for lnum in range((getpos('^')[1] + 1), getpos('$')[1])
    let header = getline(lnum)
    let lvl    = strlen(get(matchlist(header, '^' . g:mkdx#settings.tokens.header . '\{1,6}'), 0, ''))
    let hash   = s:util.HeaderToHash(header)
    let hcount = get(hashes, hash, 0)
    let final  = hash . (hcount > 0 ? '-' . hcount : '')
    let hashes[hash] = hcount + 1

    if (match(header, '^\(\`\`\`\|\~\~\~\)') > -1) | let skip = !skip | endif
    if (!skip && lvl > 0)
        call add(headers, [lnum, lvl, header, hash, (hcount > 0 ? '-' . hcount : '')])
    endif
  endfor

  return headers
endfun

fun! s:util.HeaderToQF(key, value)
  return {'bufnr': bufnr('%'), 'lnum': a:value[0], 'level': a:value[1],
        \ 'text': repeat(g:mkdx#settings.tokens.header, a:value[1]) . ' ' . s:util.CleanHeader(a:value[2])}
endfun

fun! s:util.FormatTOCHeader(level, content, ...)
  return repeat(repeat(' ', &sw), a:level) . g:mkdx#settings.toc.list_token . ' ' . s:util.HeaderToListItem(a:content, get(a:000, 0, ''))
endfun

fun! s:util.EscapeTags(str)
  return substitute(substitute(a:str, '<', '\&lt;', 'g'), '>', '\&gt;', 'g')
endfun

fun! s:util.HeaderToATag(header, ...)
  let cheader = substitute(s:util.CleanHeader(a:header), ' \+$', '', 'g')
  let cheader = substitute(cheader, '\\\@<!`\(.*\)\\\@<!`', '<code>\1</code>', 'g')
  let cheader = substitute(cheader, '<code>\(.*\)</code>', '\="<code>" . s:util.EscapeTags(submatch(1)) . "</code>"', 'g')
  let cheader = substitute(cheader, '\\<\(.*\)>', '\&lt;\1\&gt;', 'g')
  let cheader = substitute(cheader, '\\`\(.*\)\\`', '`\1`', 'g')
  return '<a href="#' . s:util.HeaderToHash(a:header) . get(a:000, 0, '') . '">' . cheader . '</a>'
endfun

fun! s:util.HeaderToListItem(header, ...)
  return '[' . substitute(s:util.CleanHeader(a:header), ' \+$', '', 'g') . '](#' . s:util.HeaderToHash(a:header) . get(a:000, 0, '') . ')'
endfun

fun! s:util.CleanHeader(header)
  let h = substitute(a:header, '^[ #]\+\| \+$', '', 'g')
  let h = substitute(h, '\[!\[\([^\]]\+\)\](\([^\)]\+\))\](\([^\)]\+\))', '', 'g')
  return substitute(h, '!\?\[\([^\]]\+\)]([^)]\+)', '\1', 'g')
endfun

fun! s:util.HeaderToHash(header)
  let h = tolower(s:util.CleanHeader(a:header))
  let h = substitute(h, '`<kbd>\(.*\)<\/kbd>`', 'kbd\1kbd', 'g')
  let h = substitute(h, '<kbd>\(.*\)<\/kbd>', '\1', 'g')
  let h = substitute(h, '[^0-9a-z_\- ]\+', '', 'g')
  let h = substitute(h, ' ', '-', 'g')
  return h
endfun

fun! s:util.TaskItem(linenum)
  let line   = getline(a:linenum)
  let token  = get(matchlist(line, '\[\(.\)\]'), 1, '')
  let ident  = strlen(get(matchlist(line, '^>\?\( \{0,}\)'), 1, ''))
  let rem    = ident % &sw
  let ident -= g:mkdx#settings.enter.malformed ? (rem - (rem > &sw / 2 ? &sw : 0)) : 0

  return [token, (ident == 0 ? ident : ident / &sw), line]
endfun

fun! s:util.TasksToCheck(linenum)
  let lnum              = type(a:linenum) == type(0) ? a:linenum : line(a:linenum)
  let cnum              = col('.')
  let current           = s:util.TaskItem(lnum)
  let [ctkn, cind, cln] = current
  let startc            = lnum
  let items             = []

  while (prevnonblank(startc) == startc)
    let indent = s:util.TaskItem(startc)[1]
    if (indent == 0) | break | endif
    let startc -= 1
  endwhile

  if (cind == -1) | return | endif

  while (nextnonblank(startc) == startc)
    let [token, indent, line] = s:util.TaskItem(startc)
    if ((startc < lnum) || (indent != 0))
      call add(items, [startc, token, indent, line])
      let startc += 1
    else
      break
    endif
  endwhile

  return [extend([lnum], current), items]
endfun

fun! s:util.UpdateListNumbers(lnum, depth, ...)
  let lnum       = a:lnum
  let min_indent = strlen(get(matchlist(getline(lnum), '^>\?\( \{0,}\)'), 1, ''))
  let incr       = get(a:000, 0, 0)

  while (nextnonblank(lnum) == lnum)
    let lnum  += 1
    let ln     = getline(lnum)
    let ident  = strlen(get(matchlist(ln, '^>\?\( \{0,}\)'), 1, ''))

    if (ident < min_indent) | break | endif
    call setline(lnum,
      \ substitute(ln,
      \    '^\(>\? \{' . min_indent . ',}\)\([0-9.]\+\)',
      \    '\=submatch(1) . s:util.NextListNumber(submatch(2), ' . a:depth . ', ' . incr . ')', ''))
  endwhile
endfun

fun! s:util.NextListNumber(current, depth, ...)
  let curr  = substitute(a:current, '^ \+\| \+$', '', 'g')
  let tdot  = match(curr, '\.$') > -1
  let parts = split(curr, '\.')
  let incr  = get(a:000, 0, 0)
  let incr  = incr < 0 ? incr : 1

  if (len(parts) > a:depth) | let parts[a:depth] = str2nr(parts[a:depth]) + incr | endif
  return join(parts, '.') . (tdot ? '.' : '')
endfun

fun! s:util.UpdateTaskList(...)
  let linenum               = get(a:000, 0, '.')
  let force_status          = get(a:000, 1, -1)
  let [target, tasks]       = s:util.TasksToCheck(linenum)
  let [tlnum, ttk, tdpt, _] = target
  let tasksilen             = len(tasks) - 1
  let [incompl, compl]      = g:mkdx#settings.checkbox.toggles[-2:-1]
  let empty                 = g:mkdx#settings.checkbox.toggles[0]
  let tasks_lnums           = map(deepcopy(tasks), {idx, val -> get(val, 0, -1)})

  if (tdpt > 0)
    let nextupd = tdpt - 1

    for [lnum, token, depth, line] in reverse(deepcopy(tasks))
      if ((lnum < tlnum) && (depth == nextupd))
        let nextupd  -= 1
        let substats  = []
        let parentidx = index(tasks_lnums, lnum)

        for ii in range(parentidx + 1, tasksilen)
          let next_task  = tasks[ii]
          let depth_diff = abs(next_task[2] - depth)

          if (depth_diff == 0) | break                            | endif
          if (depth_diff == 1) | call add(substats, next_task[1]) | endif
        endfor

        let completed = index(map(deepcopy(substats), {idx, val -> val != compl}), 1) == -1
        let unstarted = index(map(deepcopy(substats), {idx, val -> val != empty}), 1) == -1
        let new_token = completed ? compl : (unstarted ? empty : incompl)
        if (force_status > -1 && !unstarted)
          if (force_status == 0) | let new_token = empty   | endif
          if (force_status == 1) | let new_token = incompl | endif
          if (force_status > 1)  | let new_token = compl   | endif
        endif
        let new_line  = substitute(line, '\[' . token . '\]', '\[' . new_token . '\]', '')

        let tasks[parentidx][1] = new_token
        let tasks[parentidx][3] = new_line

        call setline(lnum, new_line)
        if (nextupd < 0) | break | endif
      endif
    endfor

    if (force_status < 0 && g:mkdx#settings.checkbox.update_tree == 2)
      for [lnum, token, depth, line] in tasks
        if (lnum > tlnum)
          if (depth == tdpt) | break | endif
          if (depth > tdpt) | call setline(lnum, substitute(line,  '\[.\]', '\[' . ttk . '\]', '')) | endif
        endif
      endfor
    endif
  endif
endfun

fun! s:util.InsertLine(line, position)
  let _z = @z
  let @z = a:line

  call cursor(a:position, 1)
  normal! A"zp

  let @z = _z
endfun

fun! s:util.AlignString(str, align, length)
  let remaining = a:length - strlen(a:str)

  if (remaining < 0) | return a:str[0:(a:length - 1)] | endif

  let center = !((a:align == 'right') || (a:align == 'left'))
  let lrem   = center ? float2nr(floor(remaining / 2.0)) : (a:align == 'left' ? 0 : remaining)
  let rrem   = center ? float2nr(ceil(remaining / 2.0))  : (remaining - lrem)

  return repeat(' ', lrem) . a:str . repeat(' ', rrem)
endfun

""""" MAIN FUNCTIONALITY
let s:HASH = type({})
fun! mkdx#MergeSettings(...)
  let a = get(a:000, 0, {})
  let b = get(a:000, 1, {})
  let c = {}

  for akey in keys(a)
    if has_key(b, akey)
      if (type(b[akey]) == s:HASH && type(a[akey]) == s:HASH)
        let c[akey] = mkdx#MergeSettings(a[akey], b[akey])
      else
        let c[akey] = b[akey]
      endif
    else
      let c[akey] = a[akey]
    endif
  endfor

  return c
endfun

fun! mkdx#JumpToHeader()
  let [lnum, cnum] = getpos('.')[1:2]
  let line = getline(lnum)
  let col  = 0
  let len  = len(line)
  let lnks = []
  let link = ''

  while (col < len)
    let rgx  = '\[[^\]]\+\](\([^)]\+\))\|<a .*href="\([^"]\+\)".*>.*</a>'
    let tcol = match(line[col:], rgx)
    let matches   = matchlist(line[col:], rgx)
    let matchtext = get(matches, 0, '')
    let addr      = get(matches, matchtext[0:1] == '<a' ? 2 : 1, '')
    let matchlen  = strlen(matchtext)
    if (matchlen < 1) | break | endif

    let col += tcol + 1 + matchlen
    let sps  = col - matchlen
    let eps  = col - 1

    if (sps <= cnum && eps >= cnum && addr[0] == '#')
      let link = addr[1:]
      break
    elseif (addr[0] == '#')
      call add(lnks, addr[1:])
    endif
  endwhile

  if (empty(link) && !empty(lnks)) | let link = lnks[0] | endif
  if (empty(link)) | return | endif

  for [lnum, colnum, header, hash, sfx] in s:util.ListHeaders()
    if (link == (hash . sfx))
      if (g:mkdx#settings.links.fragment.jumplist)
        normal! m'0
      endif

      call cursor(lnum, 0)
      break
    endif
  endfor
endfun

fun! mkdx#QuickfixDeadLinks(...)
  let [dead, total] = s:util.FindDeadFragmentLinks()
  if (get(a:000, 0, 1))
    let dl = len(dead)

    call setqflist(dead)
    if (g:mkdx#settings.links.external.enable && s:_can_async && executable('curl'))
      call s:util.AsyncDeadExternalToQF(0, total)
    endif

    if (dl > 0) | echohl ErrorMsg | else | echohl MoreMsg | endif
    if (dl > 0) | copen           | else | cclose         | endif
    echo dl . '/' . total ' dead fragment link' . (dl == 1 ? '' : 's')
    echohl None
  else
    return dead
  endif
endfun

fun! mkdx#InsertFencedCodeBlock(...)
  let style = !empty(g:mkdx#settings.tokens.fence) ? g:mkdx#settings.tokens.fence : get(a:000, 0, '`')
  let delim = repeat(style, 3)
  return delim . '' . delim
endfun

fun! mkdx#ToggleToKbd(...)
  let m  = get(a:000, 0, 'n')
  let r  = @z
  let ln = getline('.')

  exe 'normal! ' . (m == 'n' ? '"zdiW' : 'gv"zd')
  let oz = @z
  let ps = split(oz, ' ')
  let @z = empty(ps) ? @z : join(map(ps, {idx, val -> s:util.ToggleMappingToKbd(val)}), ' ')
  exe 'normal! "z' . (match(ln, (oz . '$')) > -1 ? 'p' : 'P')
  let @z = r

  if (m == 'n')
    silent! call repeat#set("\<Plug>(mkdx-toggle-to-kbd-n)")
  endif
endfun

fun! mkdx#ToggleCheckboxState(...)
  let reverse = get(a:000, 0, 0) == 1
  let listcpy = deepcopy(g:mkdx#settings.checkbox.toggles)
  let listcpy = reverse ? reverse(listcpy) : listcpy
  let line    = getline('.')
  let len     = len(listcpy) - 1

  for mrk in listcpy
    if (match(line, '\[' . mrk . '\]') != -1)
      let nidx = index(listcpy, mrk) + 1
      let nidx = nidx > len ? 0 : nidx
      let line = substitute(line, '\[' . mrk . '\]', '\[' . listcpy[nidx] . '\]', '')
      break
    endif
  endfor

  call setline('.', line)
  if (g:mkdx#settings.checkbox.update_tree != 0) | call s:util.UpdateTaskList() | endif
  silent! call repeat#set("\<Plug>(mkdx-checkbox-" . (reverse ? 'prev' : 'next') . ")")
endfun

fun! mkdx#WrapText(...)
  let m = get(a:000, 0, 'n')
  let w = get(a:000, 1, '')
  let x = get(a:000, 2, w)
  let a = get(a:000, 3, '')

  call s:util.WrapSelectionOrWord(m, w, x, a)

  if (a != '')
    silent! call repeat#set("\<Plug>(" . a . ")")
  endif
endfun

fun! mkdx#WrapLink(...) range
  let r = @z
  let m = get(a:000, 0, 'n')

  if (m == 'v')
    normal! gv"zy
    let img = s:util.IsImage(@z)
    call s:util.WrapSelectionOrWord(m, (img ? '!' : '') . '[', '](' . (img ? substitute(@z, '\n', '', 'g') : '') . ')')
    normal! f)
  else
    call s:util.WrapSelectionOrWord(m, '[', ']()')
  end

  let @z = r

  silent! call repeat#set("\<Plug>(mkdx-wrap-link-" . m . ")")

  startinsert
endfun

fun! mkdx#ToggleList()
  call setline('.', s:util.ToggleLineType(getline('.'), 'list'))
  silent! call repeat#set("\<Plug>(mkdx-toggle-list)")
endfun

fun! mkdx#ToggleChecklist()
  call setline('.', s:util.ToggleLineType(getline('.'), 'checklist'))
  silent! call repeat#set("\<Plug>(mkdx-toggle-checklist)")
endfun

fun! mkdx#ToggleCheckboxTask()
  call setline('.', s:util.ToggleLineType(getline('.'), 'checkbox'))
  silent! call repeat#set("\<Plug>(mkdx-toggle-checkbox)")
endfun

fun! mkdx#ToggleQuote()
  call setline('.', s:util.ToggleTokenAtStart(getline('.'), '>'))
  silent! call repeat#set("\<Plug>(mkdx-toggle-quote)")
endfun

fun! mkdx#ToggleHeader(...)
  let increment = get(a:000, 0, 0)
  let line      = getline('.')

  if (!increment && (match(line, '^' . g:mkdx#settings.tokens.header . '\{1,6} ') == -1))
    call setline('.', g:mkdx#settings.tokens.header . ' ' . line)
    return
  endif

  let parts     = split(line, '^' . g:mkdx#settings.tokens.header . '\{1,6} \zs')
  let new_level = len(parts) < 2 ? -1 : strlen(substitute(parts[0], ' ', '', 'g')) + (increment ? -1 : 1)
  let new_level = new_level > 6 ? 0 : (new_level < 0 ? 6 : new_level)
  let tail      = get(parts, 1, parts[0])

  call setline('.', repeat(g:mkdx#settings.tokens.header, new_level) . (new_level > 0 ? ' ' : '') . tail)
  silent! call repeat#set("\<Plug>(mkdx-" . (increment ? 'promote' : 'demote') . "-header)")
endfun

fun! mkdx#Tableize() range
  let next_nonblank       = nextnonblank(a:firstline)
  let firstline           = getline(next_nonblank)
  let first_delimiter_pos = match(firstline, '[,\t]')

  if (first_delimiter_pos < 0) | return | endif

  let delimiter    = firstline[first_delimiter_pos]
  let lines        = getline(a:firstline, a:lastline)
  let col_maxlen   = {}
  let col_align    = {}
  let col_idx      = []
  let linecount    = range(0, len(lines) - 1)

  for column in s:util.CsvRowToList(firstline)
    call add(col_idx, column)
    if (index(map(g:mkdx#settings.table.align.left, {idx, val -> tolower(val)}), tolower(column)) > -1)
      let col_align[column] = 'left'
    elseif (index(map(g:mkdx#settings.table.align.right, {idx, val -> tolower(val)}), tolower(column)) > -1)
      let col_align[column] = 'right'
    elseif (index(map(g:mkdx#settings.table.align.center, {idx, val -> tolower(val)}), tolower(column)) > -1)
      let col_align[column] = 'center'
    else
      let col_align[column] = g:mkdx#settings.table.align.default
    endif
  endfor

  for idx in linecount
    let lines[idx] = s:util.CsvRowToList(lines[idx])

    for column in range(0, len(lines[idx]) - 1)
      let curr_word_max = strlen(lines[idx][column])
      let last_col_max  = get(col_maxlen, column, 0)

      if (curr_word_max > last_col_max) | let col_maxlen[column] = curr_word_max | endif
    endfor
  endfor

  let ld  = ' ' . g:mkdx#settings.table.divider . ' '
  for linec in linecount
    if !empty(filter(lines[linec], {idx, val -> !empty(val)}))
      call setline(a:firstline + linec,
        \ ld[1:2] . join(map(lines[linec], {key, val -> s:util.AlignString(val, get(col_align, get(col_idx, key, ''), 'center'), col_maxlen[key])}), ld) . ld[0:1])
    endif
  endfor

  let parts = []
  for column in keys(col_maxlen)
    let align  = tolower(get(col_align, get(col_idx, column, ''), g:mkdx#settings.table.align.default))
    let len    = col_maxlen[column]
    let lhs    = index(['right', 'center'], align) ? ':' : g:mkdx#settings.table.header_divider
    let rhs    = index(['left',  'center'], align) ? ':' : g:mkdx#settings.table.header_divider

    call add(parts, lhs . repeat(g:mkdx#settings.table.header_divider, col_maxlen[column]) . rhs)
  endfor
  let hline = join(parts, g:mkdx#settings.table.divider)

  call s:util.InsertLine(g:mkdx#settings.table.divider . hline . g:mkdx#settings.table.divider, next_nonblank)
  call cursor(a:lastline + 1, 1)
endfun

fun! mkdx#OHandler()
  normal A
  startinsert!
endfun

fun! mkdx#ShiftOHandler()
  let lnum = line('.')
  let line = getline(lnum)
  let len  = strlen(line)
  let qstr = ''
  let bld  = match(line, '^ *\*\*') > -1
  let quot = len > 0 ? line[0] == '>' : 0

  if (!bld && quot)
    let qstr = quot ? ('>' . get(matchlist(line, '^>\?\( *\)'), 1, '')) : ''
    let line = line[strlen(qstr):]
  endif

  let lin = bld ? -1 : get(matchlist(line, '^ *\([0-9.]\+\)'), 1, -1)
  let lis = bld ? -1 : get(matchlist(line, '^ *\([' . join(g:mkdx#settings.tokens.enter, '') . ']\) '), 1, -1)

  if (lin != -1)
    let esc  = lin == '*' ? '\*' : lin
    let suff = !empty(matchlist(line, '^ *' . esc . ' \[.\]'))
    exe 'normal! O' . qstr . lin . (suff ? ' [' . g:mkdx#settings.checkbox.initial_state . '] ' : ' ')
    call s:util.UpdateListNumbers(lnum, indent(lnum) / &sw)
  elseif (lis != -1)
    let esc  = lis == '*' ? '\*' : lis
    let suff = !empty(matchlist(line, '^ *' . esc . ' \[.\]'))
    exe 'normal! O' . qstr . lis . (suff ? ' [' . g:mkdx#settings.checkbox.initial_state . '] ' : ' ')
  elseif (quot)
    let suff = !empty(matchlist(line, '^ *\[.\]'))
    exe 'normal! O' . qstr . (strlen(qstr) > 1 ? '' : ' ') . (suff ? '[' . g:mkdx#settings.checkbox.initial_state . '] ' : '')
  else
    normal! O
  endif

  startinsert!
endfun

fun! mkdx#EnterHandler()
  let lnum    = line('.')
  let cnum    = virtcol('.')
  let line    = getline(lnum)

  if (!empty(line) && g:mkdx#settings.enter.enable)
    let len     = strlen(line)
    let at_end  = cnum > len
    let sp_pat  = '^>\? *\(\([0-9.]\+\|[' . join(g:mkdx#settings.tokens.enter, '') . ']\)\( \[.\]\)\? \|\[.\]\)'
    let results = matchlist(line, sp_pat)
    let t       = get(results, 2, '')
    let tcb     = match(get(results, 1, ''), '^>\? *\[.\] *') > -1
    let cb      = match(get(results, 3, ''), ' *\[.\] *') > -1
    let quote   = len > 0 ? line[0] == '>' : 0
    let remove  = empty(substitute(line, sp_pat . ' *', '', ''))
    let incr    = len(split(get(matchlist(line, '^>\? *\([0-9.]\+\) '), 1, ''), '\.')) - 1
    let upd_tl  = (cb || tcb) && g:mkdx#settings.checkbox.update_tree != 0 && at_end
    let tl_prms = remove ? [line('.') - 1, -1] : ['.', 1]
    let qu_str  = quote ? ('>' . get(matchlist(line, '^>\?\( *\)'), 1, '')) : ''
    let ast_bld = match(line, '^ *\*\*') > -1

    if (at_end && match(line, '^>\? *[0-9.]\+ ') > -1)
      call s:util.UpdateListNumbers(lnum, incr, (remove ? -1 : 1))
    endif

    if (remove)  | call setline('.', '')                                                      | endif
    if (upd_tl)  | call call(s:util.UpdateTaskList, tl_prms)                                  | endif
    if (remove)  | return ''                                                                  | endif
    if (ast_bld) | return "\n"                                                                | endif
    if (!at_end) | return "\n"                                                                | endif
    if (tcb)     | return "\n" . qu_str . '[' . g:mkdx#settings.checkbox.initial_state . '] ' | endif
    return ("\n"
      \ . qu_str
      \ . (match(t, '[0-9.]\+') > -1 ? s:util.NextListNumber(t, incr > -1 ? incr : 0) : t)
      \ . (cb ? ' [' . g:mkdx#settings.checkbox.initial_state . '] ' : (!empty(t) ? ' ' : '')))
  endif

  return "\n"
endfun

fun! mkdx#GenerateOrUpdateTOC()
  silent! call repeat#set("\<Plug>(mkdx-gen-or-upd-toc)")

  for lnum in range((getpos('^')[1] + 1), getpos('$')[1])
    if (match(getline(lnum), '^' . g:mkdx#settings.tokens.header . '\{1,6} \+' . g:mkdx#settings.toc.text) > -1)
      call mkdx#UpdateTOC()
      return
    endif
  endfor

  call mkdx#GenerateTOC()
endfun

fun! mkdx#UpdateTOC()
  let startc = -1
  let nnb    = -1
  let curpos = getpos('.')

  for lnum in range((getpos('^')[1] + 1), getpos('$')[1])
    if (match(getline(lnum), '^' . g:mkdx#settings.tokens.header . '\{1,6} \+' . g:mkdx#settings.toc.text) > -1)
      let startc = lnum
      break
    endif
  endfor

  if (startc)
    let endc = startc + (nextnonblank(startc + 1) - startc)
    while (nextnonblank(endc) == endc)
      let endc += 1
      if (s:util.IsHeader(endc))
        break
      elseif (s:util.IsDetailsTag(endc))
        let endc += 1
        break
      endif
    endwhile
    let endc -= 1
  endif

  exe 'normal! :' . startc . ',' . endc . 'd'
  let deleted = endc - startc + 1
  let curs_af = curpos[1] >= endc
  let inslen = mkdx#GenerateTOC(1)
  call cursor(curpos[1] - (curs_af ? deleted - inslen : 0), curpos[2])
endfun

fun! mkdx#QuickfixHeaders(...)
  let qflist = map(s:util.ListHeaders(), s:util.HeaderToQF)

  if (get(a:000, 0, 1))
    let dl = len(qflist)

    if (dl > 0)
      call setqflist(qflist)
      exe 'copen'
      echohl MoreMsg
    else
      call setqflist([])
      exe 'cclose'
      echohl ErrorMsg
    endif

    echo dl . ' header' . (dl == 1 ? '' : 's')
    echohl None
  else
    return qflist
  endif
endfun

fun! mkdx#GenerateTOC(...)
  let toc_exst = get(a:000, 0, 0)
  let contents = []
  let cpos     = getpos('.')
  let curspos  = cpos[1]
  let header   = ''
  let prevlvl  = 1
  let skip     = 0
  let headers  = {}
  let src      = s:util.ListHeaders()
  let srclen   = len(src)
  let curr     = 0
  let toc_pos = g:mkdx#settings.toc.position - 1
  let after_info = get(src, toc_pos, -1)
  let after_pos = toc_pos >= 0 && type(after_info) == type([])

  if (g:mkdx#settings.toc.details.enable)
    let summary_text =
          \ empty(g:mkdx#settings.toc.details.summary)
          \ ? g:mkdx#settings.toc.text
          \ : substitute(g:mkdx#settings.toc.details.summary, '{{toc.text}}', g:mkdx#settings.toc.text, 'g')

    call add(contents, '<details>')
    call add(contents, '<summary>' . summary_text . '</summary>')
    call add(contents, '<ul>')
  endif

  for [lnum, lvl, line, hsh, sfx] in src
    let curr += 1
    let headers[hsh] = sfx == '' ? 1 : headers[hsh] + 1
    let spc = repeat(repeat(' ', &sw), lvl)
    let nextlvl    = get(src, curr, [0, lvl])[1]
    let ending_tag = (nextlvl > lvl) ? '<ul>' : '</li>'

    if (g:mkdx#settings.toc.details.enable && lvl < prevlvl)
      let clvl = prevlvl
      while (clvl > lvl)
        let clvl -= 1
        call add(contents, repeat(repeat(' ', &sw), clvl) . '</ul></li>')
      endwhile
    endif

    if (empty(header) && (lnum >= curspos || (curr > toc_pos && after_pos)))
      let header = repeat(g:mkdx#settings.tokens.header, prevlvl) . ' ' . g:mkdx#settings.toc.text
      let csh    = s:util.HeaderToHash(header)
      let hc     = get(headers, csh, 0)
      let hsf    = (hc > 0) ? '-' . hc : ''
      let headers[csh] = hc == 0 ? 1 : headers[csh] + 1
      call insert(contents, '')
      call insert(contents, header)
      if (g:mkdx#settings.toc.details.enable)
        call add(contents, spc . '<li>' . s:util.HeaderToATag(header, hsf) . '</li>')
      else
        call add(contents, s:util.FormatTOCHeader(prevlvl - 1, header, hsf))
      endif
    endif

    if (g:mkdx#settings.toc.details.enable)
      call add(contents, spc . '<li>' . s:util.HeaderToATag(line, sfx) . ending_tag)
    else
      call add(contents, s:util.FormatTOCHeader(lvl - 1, line, sfx))
    endif

    if (empty(header) && curr == srclen)
      let header = repeat(g:mkdx#settings.tokens.header, prevlvl) . ' ' . g:mkdx#settings.toc.text
      let csh    = s:util.HeaderToHash(header)
      let hc     = get(headers, csh, 0)
      let hsf    = (hc > 0) ? '-' . hc : ''
      let headers[csh] = hc == 0 ? 1 : headers[csh] + 1

      call insert(contents, '')
      call insert(contents, header)
      if (g:mkdx#settings.toc.details.enable)
        call add(contents, spc . '<li>' . s:util.HeaderToATag(header, hsf) . '</li>')
      else
        call add(contents, s:util.FormatTOCHeader(prevlvl - 1, header, hsf))
      endif
    endif

    let prevlvl = lvl
  endfor

  if (g:mkdx#settings.toc.details.enable)
    call add(contents, '</ul>')
    call add(contents, '</details>')
  endif

  if (!toc_exst && after_pos)
    let c = after_info[0] - 1
  else
    let c = curspos - 1
  endif

  if (c > 0 && nextnonblank(c) == c)     | call insert(contents, '') | endif
  if (after_pos || !empty(getline('.'))) | call add(contents, '')    | endif

  for item in contents
    call append(c, item)
    let c += 1
  endfor

  call setpos('.', cpos)
  return len(contents)
endfun
