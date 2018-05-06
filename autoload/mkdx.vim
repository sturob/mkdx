""""" UTILITY FUNCTIONS
let s:_is_nvim               = has('nvim')
let s:_has_curl              = executable('curl')
let s:_has_rg                = 1 && executable('rg')
let s:_has_ag                = s:_has_rg    || executable('ag')
let s:_has_cgrep             = s:_has_ag    || executable('cgrep')
let s:_has_ack               = s:_has_cgrep || executable('ack')
let s:_has_pt                = s:_has_ack   || executable('pt')
let s:_has_ucg               = s:_has_pt    || executable('ucg')
let s:_has_sift              = s:_has_ucg   || executable('sift')
let s:_can_async             = s:_is_nvim   || has('job')
let s:util                   = {}
let s:util.modifier_mappings = {
      \ 'C': 'ctrl',
      \ 'M': 'meta',
      \ 'S': 'shift',
      \ 'ctrl': 'ctrl',
      \ 'meta': 'meta',
      \ 'shift': 'shift'
      \ }

let s:util.grepopts = {
      \ 'rg':    { 'timeout': 35,
      \            'opts': ['--vimgrep', '-o'] },
      \ 'ag':    { 'timeout': 35,
      \            'opts': ['--vimgrep'] },
      \ 'cgrep': { 'timeout': 35,
      \            'opts': ['--regex-pcre', '--format="#f:#n:#0"'] },
      \ 'ack':   { 'timeout': 35,
      \            'opts': ['-H', '--column', '--nogroup'] },
      \ 'pt':    { 'timeout': 35,
      \            'opts': ['--nocolor', '--column', '--numbers', '--nogroup'], 'pat_flag': ['-e'] },
      \ 'ucg':   { 'timeout': 35,
      \            'opts': ['--column'] },
      \ 'sift':  { 'timeout': 35,
      \            'opts': ['-n', '--column', '--only-matching'] },
      \ 'grep':  { 'timeout': 35,
      \            'opts': ['-o', '--line-number', '--byte-offset'], 'pat_flag': ['-E'] }
      \ }

if (s:_has_rg)
  let s:util.grepcmd = 'rg'
elseif (s:_has_ag)
  let s:util.grepcmd = 'ag'
elseif (s:_has_cgrep)
  let s:util.grepcmd = 'cgrep'
elseif (s:_has_ack)
  let s:util.grepcmd = 'ack'
elseif (s:_has_pt)
  let s:util.grepcmd = 'pt'
elseif (s:_has_ucg)
  let s:util.grepcmd = 'ucg'
elseif (s:_has_sift)
  let s:util.grepcmd = 'sift'
else
  let s:util.grepcmd = executable('cgrep') ? 'cgrep' : 'grep'
endif

let s:_can_vimgrep_fmt = has_key(s:util.grepopts, s:util.grepcmd)
let s:_testing         = 0

fun! mkdx#testing(val)
  let s:_testing = a:val == 1 ? 1 : 0
endfun

fun! s:util._(...)
  return get(a:000, 0, '')
endfun

let s:HASH = type({})
let s:LIST = type([])
let s:INT  = type(1)
let s:STR  = type('')
let s:FUNC = type(s:util._)

fun! s:util.TypeString(t)
  return (a:t == s:HASH) ? 'hash'
     \ : (a:t == s:LIST) ? 'list'
     \ : (a:t == s:INT)  ? 'int'
     \ : (a:t == s:STR)  ? 'str'
     \ : (a:t == s:FUNC) ? 'func' : 'unknown'
endfun

fun! s:util.log(str, ...)
  let opts = extend({'hl': 'Comment'}, get(a:000, 0, {}))
  exe 'echohl ' . opts.hl
  echo a:str
  echohl None
endfun

fun! s:util.add_dict_watchers(hash, ...)
  let keypath = get(a:000, 0, [])

  call dictwatcheradd(a:hash, '*', function(s:util.OnSettingModified, [keypath]))
  for key in keys(a:hash)
    if (type(a:hash[key]) == s:HASH)
      call s:util.add_dict_watchers(a:hash[key], extend(deepcopy(keypath), [key]))
    endif
  endfor
endfun

fun! s:util.OnSettingModified(path, hash, key, value)
  let to = type(a:value.old)
  let tn = type(a:value.new)
  let ch = (to == tn) && (a:value.old != a:value.new)
  let yy = extend(deepcopy(a:path), [a:key])
  if (yy[0] != 'mkdx#settings') | let yy = extend(['mkdx#settings'], yy) | endif
  let yy[0] = 'g:' . yy[0]
  let sk = join(yy, '.')
  let er = []
  let et = 0
  let hu = has_key(s:util.updaters, sk)
  let s:util._last_time = get(s:util, '_last_time', localtime())
  if ((localtime() - s:util._last_time) > 1)
    unlet s:util._last_time
    let   s:util._err_count = 0
  else
    let s:util._err_count = get(s:util, '_err_count', 0)
  endif

  if (to != tn)
    let [tos, tns] = [s:util.TypeString(to), s:util.TypeString(tn)]

    call s:util.log('mkdx: {' . sk . '} value must be of type {' . tos . '}, got {' . tns . '}', {'hl': 'ErrorMsg'})

    let a:hash[a:key]      = a:value.old
    let et                 = 1
    let s:util._err_count += 1

    call s:util.DidNotUpdateValueAt(yy, 'mkdx-error-type')
  elseif (to == s:HASH)
    let a:hash[a:key] = mkdx#MergeSettings(a:value.old, a:value.new, {'modify': 1})
  elseif (ch && (has_key(s:util.validations, sk) || has_key(s:util.validations, a:key)))
    let er = s:util.validate(a:value.new, get(s:util.validations, sk, get(s:util.validations, a:key, {})))
    if (!empty(er))
      let s:util._err_count += len(er)
      for error in er
        call s:util.log(sk . ' ' . error, {'hl': 'ErrorMsg'})
      endfor
      call s:util.DidNotUpdateValueAt(yy)
      let a:hash[a:key] = a:value.old
    endif
  endif

  if (g:mkdx#settings.auto_update.enable && !et && empty(er) && ch && hu)
    let Updater = function(s:util.updaters[sk])
    call Updater(a:value.old, a:value.new)
  elseif ((to != s:HASH) && (s:util._err_count == 0))
    echo ''
  endif
endfun

fun! s:util.ReplaceTOCText(old, new)
  let [current, endc, details] = s:util.GetTOCPositionAndStyle()

  silent! call mkdx#UpdateTOC({'text': a:old, 'details': details})
  silent! update
endfun

fun! s:util.RepositionTOC(old, new)
  let [current, endc, details] = s:util.GetTOCPositionAndStyle()
  silent! exe 'normal! :' . current . ',' . endc . 'd'
  call mkdx#GenerateTOC(0, details)
endfun

fun! s:util.UpdateTOCStyle(old, new)
  silent! call mkdx#UpdateTOC({'details': a:new, 'force': 1})
endfun

fun! s:util.UpdateTOCSummary(old, new)
  if (g:mkdx#settings.toc.details.enable) | silent! call mkdx#UpdateTOC() | endif
endfun

fun! s:util.UpdateFencedCodeBlocks(old, new)
  for lnum in range(1, line('$'))
    let line = getline(lnum)
    if (match(line, '^' . repeat('\' . a:old, 3)) > -1)
      call setline(lnum, repeat(a:new, 3) . line[3:])
    endif
  endfor
endfun

fun! s:util.UpdateHeaders(old, new)
  let skip = 0

  for lnum in range(1, line('$'))
    let line = getline(lnum)
    let skip = match(line, '^\(\`\`\`\|\~\~\~\)') > -1 ? !skip : skip
    if (!skip && (line =~ ('^' . a:old . '\{1,6} ')))
      call setline(lnum, substitute(line, '^' . a:old . '\{1,6}', '\=repeat("' . a:new . '", strlen(submatch(0)))', ''))
    endif
  endfor
endfun

let s:util.validations = {
      \ 'g:mkdx#settings.checkbox.toggles':        { 'min_length': [2,          'value must be a list with at least 2 states'] },
      \ 'g:mkdx#settings.checkbox.update_tree':    { 'between':    [[0, 2],     'value must be >= 0 and <= 2'] },
      \ 'g:mkdx#settings.tokens.fence':            { 'only_valid': [['`', '~'], "value can only be '`' or '~'"] },
      \ 'g:mkdx#settings.enter.o':                 { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'g:mkdx#settings.enter.shifto':            { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'g:mkdx#settings.enter.malformed':         { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'g:mkdx#settings.links.external.relative': { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'g:mkdx#settings.links.fragment.jumplist': { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'g:mkdx#settings.links.fragment.complete': { 'only_valid': [[0, 1],     'value can only be 0 or 1'] },
      \ 'enable':                                  { 'only_valid': [[0, 1],     'value can only be 0 or 1'] }
      \ }

let s:util.updaters = {
      \ 'g:mkdx#settings.toc.text': s:util.ReplaceTOCText,
      \ 'g:mkdx#settings.toc.details.enable': s:util.UpdateTOCStyle,
      \ 'g:mkdx#settings.toc.details.summary': s:util.UpdateTOCSummary,
      \ 'g:mkdx#settings.toc.position': s:util.RepositionTOC,
      \ 'g:mkdx#settings.tokens.header': s:util.UpdateHeaders,
      \ 'g:mkdx#settings.tokens.fence': s:util.UpdateFencedCodeBlocks
      \ }

fun! s:util.validate(value, validations)
  let errors = []
  for validation in keys(a:validations)
    if (validation == 'min_length')
      let len = type(a:value) == s:STR ? strlen(a:value) : len(a:value)
      if (len < a:validations[validation][0])
        call add(errors, a:validations[validation][1])
      endif
    elseif (validation == 'between')
      let [min, max] = a:validations[validation][0]
      if (type(a:value) == s:INT)
        if (a:value < min || a:value > max)
          call add(errors, a:validations[validation][1])
        endif
      endif
    elseif (validation == 'only_valid')
      if (index(a:validations[validation][0], a:value) == -1)
        call add(errors, a:validations[validation][1])
      endif
    endif
  endfor
  return errors
endfun

fun! s:util.DidNotUpdateValueAt(path, ...)
  call s:util.log('info: did not update value of {' . join(a:path, '.') . '}')

  let helpkey  = len(a:path) == 1 ? 'overrides' : substitute(join(a:path[1:], '-'), '_', '-', 'g')
  let code     = get(a:000, 0, '')
  let helptags = join(extend(['mkdx-setting-' . helpkey, 'mkdx-errors'], !empty(code) ? [code] : []), ', ')

  call s:util.log('help: ' . helptags)
endfun

fun! s:util.JumpToHeader(link, hashes, jid, stream, ...)
  if (s:util._header_found) | return | endif
  let stream = type(a:stream) == s:LIST ? a:stream : [a:stream]
  for line in stream
    let item = s:util.IdentifyGrepLink(line)
    let hash = item.type == 'anchor' ? item.content : s:util.transform(tolower(getline(item.lnum)), ['clean-header', 'header-to-hash'])
    let a:hashes[hash] = get(a:hashes, hash, -1) + 1
    let suffixed_hash  = hash . (a:hashes[hash] == 0 ? '' : ('-' . a:hashes[hash]))
    if (a:link == suffixed_hash)
      let s:util._header_found = 1
      if (g:mkdx#settings.links.fragment.jumplist)
        normal! m'0
      endif
      call cursor(item.lnum, 0)
      redraw
      break
    endif
  endfor
endfun

fun! s:util.EchoQuickfixCount(subject, ...)
  let total = len(getqflist())
  call s:util.log(total . ' ' . (total == 1 ? a:subject : a:subject . 's'), {'hl': (total > 0) ? 'MoreMsg' : 'ErrorMsg'})
  return total
endfun

fun! s:util.AddHeaderToQuickfix(bufnr, jid, stream, ...)
  let stream     = type(a:stream) == s:LIST ? a:stream : [a:stream]
  let TQF        = {gl -> {'lnum': gl.lnum, 'bufnr': a:bufnr, 'text': s:util.transform(gl.content, ['clean-header'])}}
  let qf_entries = map(filter(stream, {idx, line -> !empty(line)}), {idx, line -> TQF(s:util.IdentifyGrepLink(line))})

  if (len(qf_entries) > 0) | call setqflist(qf_entries, 'a') | endif
  if (s:util.EchoQuickfixCount('header')) | copen | else | cclose | endif
endfun

fun! s:util.CsvRowToList(...)
  let line = substitute(get(a:000, 0, getline('.')), '^\s\+|\s\+$', '', 'g')
  let len  = strlen(line) - 1

  if (len < 1) | return [] | endif

  let quote    = ""
  let escaped  = 0
  let currcol  = ""
  let result   = []

  for idx in range(0, len)
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

  call s:util.log(qflen . '/' . total . ' dead fragment link' . (qflen == 1 ? '' : 's'), {'hl': (qflen > 0 ? 'ErrorMsg' : 'MoreMsg')})
  if (qflen > 0) | copen | else | cclose | endif
endfun

fun! s:util.GetRemoteUrl()
  if (!empty(g:mkdx#settings.links.external.host))
    return [g:mkdx#settings.links.external.host, '']
  endif

  let remote = system('git ls-remote --get-url 2>/dev/null')

  if (!v:shell_error && strlen(remote) > 4)
    let secure = remote[0:4] == "https"
    let branch = system('git branch 2>/dev/null | grep "\*.*"')
    if (!v:shell_error && strlen(branch) > 0)
      let remote = substitute(substitute(remote[0:-2], '^\(\(https\?:\)\?//\|.*@\)\|\.git$', '', 'g'), ':', '/', 'g')
      let remote = (secure ? 'https' : 'http') . '://' . remote . '/blob/' . branch[2:-2] . '/'
      return [remote, substitute(branch, '^ \+\| \+$', '', 'g')]
    endif
    return ['', '']
  endif
  return ['', '']
endfun

fun! s:util.AsyncDeadExternalToQF(...)
  let prev_tot         = get(a:000, 1, 0)
  let external         = filter(s:util.ListLinks(), {idx, val -> val[2][0] != '#'})
  let ext_len          = len(external)
  let bufnum           = bufnr('%')
  let total            = ext_len + prev_tot
  let [remote, branch] = ext_len > 0 ? s:util.GetRemoteUrl() : ''
  let skip_rel         = g:mkdx#settings.links.external.relative == 0 ? 1 : (ext_len > 0 && empty(remote))

  if (get(a:000, 0, 1)) | call setqflist([]) | endif

  for [lnum, column, url] in external
    let has_frag = url[0]   == '#'
    let has_prot = url[0:1] == '//'
    let has_http = url[0:3] == 'http'

    if (!skip_rel && !has_frag && !has_http && !has_prot)
      let tail = substitute(url, '^/\+', '', '')
      let brsl = len(split(branch, '/')) - 1
      if (brsl > 0 && tail[0:2] == '../')
        let tail = repeat('../', brsl) . tail
      endif
      let url = substitute(remote, '/\+$', '', '') . '/' . tail
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
    let len  = strlen(line)

    while (col < len)
        if (tolower(synIDattr(synID(lnum, 1, 0), 'name')) == 'markdowncode') | break | endif
        let tcol = match(line[col:], '\](\([^)]\+\))')
        let href = tcol > -1 ? -1 : match(line[col:], 'href="\([^"]\+\)"')
        let html = href > -1
        if ((html && href < 0) || (!html && tcol < 0)) | break | endif
        let col += html ? href : tcol
        let rgx  = html ? 'href="\([^"]\+\)"' : '\](\([^)]\+\))'

        let matchtext = get(matchlist(line[col:], rgx), 1, -1)
        if (matchtext == -1) | break | endif

        call add(links, [lnum, col + (html ? 6 : 2), matchtext])
        let col += strlen(matchtext)
    endwhile

    let lnum += 1
  endwhile

  return links
endfun

fun! s:util.ListIDAnchorLinks()
  let limit = line('$') + 1
  let lnum  = 1
  let links = []

  while (lnum < limit)
    let line = getline(lnum)
    let col  = 0
    let len  = strlen(line)

    while (col < len)
        if (tolower(synIDattr(synID(lnum, 1, 0), 'name')) == 'markdowncode') | break | endif
        let id = match(line[col:], '\(name\|id\)="\([^"]\+\)"')
        if (id < 0) | break | endif
        let col += id

        let matchtext = get(matchlist(line[col:], '\(name\|id\)="\([^"]\+\)"'), 2, -1)
        if (matchtext == -1) | break | endif

        call add(links, [lnum, col, matchtext])
        let col += strlen(matchtext)
    endwhile

    let lnum += 1
  endwhile

  return links
endfun

fun! s:util.FindDeadFragmentLinks()
  let headers = {}
  let hashes  = []
  let dead    = []
  let frags   = filter(s:util.ListLinks(), {idx, val -> val[2][0] == '#'})
  let bufnum  = bufnr('%')

  for [lnum, lvl, line, hash, sfx] in s:util.ListHeaders() | call add(hashes, '#' . hash . sfx) | endfor
  for [lnum, column, hash] in s:util.ListIDAnchorLinks()
    let _h = '#' . hash
    if (index(hashes, _h) == -1) | call add(hashes, _h) | endif
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
    let @z = start . @z . end
    exe 'normal! "z' . ((virtcol('.') == strlen(getline('.'))) ? 'p' : 'P')
  endif

  let zz = @z
  let @z = _r
  return zz
endfun

fun! s:util.ToggleMappingToKbd(str)
  let input = a:str
  let parts = split(input, '[-\+]')
  let state = { 'regular': 0, 'meta': 0, 'ctrl': 0, 'shift': 0 }
  let ilen  = len(parts) - 1
  let idx   = 0
  let out   = []

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

fun! s:util.ListHeaders()
  let headers = []
  let skip    = 0
  let hashes  = {}

  for lnum in range(1, line('$'))
    let header = getline(lnum)
    let skip   = match(header, '^\(\`\`\`\|\~\~\~\)') > -1 ? !skip : skip

    if (!skip)
      let lvl = strlen(get(matchlist(header, '^' . g:mkdx#settings.tokens.header . '\{1,6}'), 0, ''))
      if (lvl > 0)
        let hash         = s:util.transform(tolower(header), ['clean-header', 'header-to-hash'])
        let hashes[hash] = get(hashes, hash, -1) + 1

        call add(headers, [lnum, lvl, header, hash, (hashes[hash] > 0 ? '-' . hashes[hash] : '')])
      endif
    endif
  endfor

  return headers
endfun

fun! s:util.ToggleLineType(line, type)
  if (empty(a:line)) | return a:line | endif

  let li_re = '\([0-9.]\+\|[' . join(g:mkdx#settings.tokens.enter, '') . ']\) '
  let li_st = '^ *' . li_re
  let repl  = ['', '', '']

  if (a:type == 'list')
    let repl = (match(a:line, li_st) > -1 ? ['^\( *\)' . li_re, '\1', ''] : ['^\( *\)', '\1' . g:mkdx#settings.tokens.list . ' ', ''])
    return substitute(a:line, repl[0], repl[1], repl[2])
  elseif (a:type == 'checkbox' || a:type == 'checklist')
    let repl = (match(a:line, '^ *\[.\]') > -1
                  \ ? ['^\( *\)\[.\] *', '\1', '']
                  \ : (match(a:line, li_st . '\[.\]') > -1
                        \ ? ['^\( *\)' . li_re . '\(\[.\]\) ', (a:type == 'checklist' ? '\1' : '\1\2 '), '']
                        \ : (match(a:line, li_st) > -1
                              \ ? ['^\( *\)' . li_re, '\1\2 [' . g:mkdx#settings.checkbox.initial_state . '] ', '']
                              \ : ['^\( *\)', '\1' . (a:type == 'checklist' ? g:mkdx#settings.tokens.list . ' ' : '') . '[' . g:mkdx#settings.checkbox.initial_state . '] ', ''])))
  elseif (a:type == 'off')
    let repl = ['^\( *\)\(' . li_re . ' \?\)\?\(\[.\]\)\? *', '\1', '']
  endif

  return substitute(a:line, repl[0], repl[1], repl[2])
endfun

let s:util.transformations = {
      \ 'trailing-space': [[' \+$', '', 'g']],
      \ 'escape-tags':    [['>', '\&gt;', 'g'], ['<', '\&lt;', 'g']],
      \ 'header-to-html': [['\\\@<!`\(.*\)\\\@<!`', '<code>\1</code>', 'g'],
      \                    ['<code>\(.*\)</code>', '\="<code>" . s:util.transform(submatch(1), ["escape-tags"]) . "</code>"', 'g'],
      \                    ['\\<\(.*\)>', '\&lt;\1\&gt;', 'g'], ['\\`\(.*\)\\`', '`\1`', 'g']],
      \ 'clean-header':   [['^[ {{tokens.header}}]\+\| \+$', '', 'g'], ['\[!\[\([^\]]\+\)\](\([^\)]\+\))\](\([^\)]\+\))', '', 'g'],
      \                    ['<a.*>\(.*\)</a>', '\1', 'g'], ['!\?\[\([^\]]\+\)]([^)]\+)', '\1', 'g']],
      \ 'header-to-hash': [['`<kbd>\(.*\)<\/kbd>`', 'kbd\1kbd', 'g'], ['<kbd>\(.*\)<\/kbd>', '\1', 'g'],
      \                    ['[^0-9a-z_\- ]\+', '', 'g'], [' ', '-', 'g']],
      \ 'toggle-quote':   [['^\(> \)\?', '\=(submatch(1) == "> " ? "" : "> ")', '']]
      \ }

fun! s:util.transform(line, to, ...)
  let [curr, transforms, Cb] = [a:line, (type(a:to) == s:STR ? [a:to] : deepcopy(a:to)), get(a:000, 0, s:util._)]

  for name in transforms
    for [rgx, rpl, flg] in get(s:util.transformations, name, [])
      if (name == 'clean-header') | let rgx = substitute(rgx, '{{tokens.header}}', g:mkdx#settings.tokens.header, '') | endif
      let curr = substitute(curr, rgx, rpl, flg)
    endfor
  endfor

  return Cb(curr)
endfun

fun! s:util.FormatTOCHeader(level, content, ...)
  let hsh = s:util.transform(tolower(a:content), ['clean-header', 'header-to-hash']) . get(a:000, 0, '')
  let hdr = s:util.transform(a:content, ['clean-header', 'trailing-space'], {str -> '[' . str . '](#' . hsh . ')'})

  return repeat(repeat(' ', &sw), a:level) . g:mkdx#settings.toc.list_token . ' ' . hdr
endfun

fun! s:util.HeaderToATag(header, ...)
  let hsh = s:util.transform(tolower(a:header), ['clean-header', 'header-to-hash']) . get(a:000, 0, '')

  return s:util.transform(a:header, ['clean-header', 'trailing-space', 'header-to-html'],
                        \ {str -> '<a href="#' . hsh . '">' . str . '</a>'})
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
  let lnum    = type(a:linenum) == type(0) ? a:linenum : line(a:linenum)
  let cnum    = col('.')
  let current = s:util.TaskItem(lnum)
  let startc  = lnum
  let items   = []

  while (prevnonblank(startc) == startc)
    let indent = s:util.TaskItem(startc)[1]
    if (indent == 0) | break | endif
    let startc -= 1
  endwhile

  if (current[1] == -1) | return | endif

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
  let parts = split(curr, '\.')
  let incr  = get(a:000, 0, 0)
  let incr  = incr < 0 ? incr : 1

  if (len(parts) > a:depth) | let parts[a:depth] = str2nr(parts[a:depth]) + incr | endif
  return join(parts, '.') . ((match(curr, '\.$') > -1) ? '.' : '')
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

fun! s:util.TruncateString(str, len, ...)
  let ending = get(a:000, 0, '..')
  return strlen(a:str) >= a:len ? (a:str[0:(a:len - 1 - strlen(ending))] . ending) : a:str
endfun

fun! s:util.IsInsideLink()
  let col   = col('.')
  let start = col
  let line  = getline('.')
  let len   = strlen(line)
  let [mdlink, htmllink] = [0, 0]

  while (start > 0 && line[start - 1] != ']' && line[start - 1] != ' ') | let start -= 1 | endwhile
  let mdlink = line[(start - 1):start] == ']('

  if (!mdlink)
    let start = col
    while (start > 0 && line[start - 1] != '"') | let start -= 1 | endwhile
    let htmllink = line[(start - 7):(start - 3)] == 'href='
  endif

  return mdlink || htmllink
endfun

fun! s:util.Grep(...)
  let grepopts = extend({'opts': [], 'timeout': 100, 'pat_flag': []}, get(s:util.grepopts, s:util.grepcmd, {}))
  let options  = extend({'pattern': 'href="[^"]+"|\]\([^\(]+\)|^#{1,6}.*\$',
                      \  'done': s:util._, 'each': s:util._, 'file': expand('%')},
                      \ get(a:000, 0, {}))
  let base = [s:util.grepcmd]
  let base = extend(base, extend(grepopts.pat_flag, [options.pattern]))
  call add(base, options.file)
  let base = extend(base, grepopts.opts)

  if (s:_is_nvim)
    return jobstart(base, {'on_stdout': options.each, 'on_exit': options.done})
  elseif (s:_can_async)
    return job_start(base, {'pty': 0, 'out_cb': options.each})
  endif
endfun

fun! s:util.HeadersAndAnchorsToHashCompletions(hashes, jid, stream, ...)
  let stream = type(a:stream) == s:LIST ? a:stream : [a:stream]
  for line in stream
    let item = s:util.IdentifyGrepLink(line)
    if (item.type == 'header')
      let hash           = s:util.transform(tolower(item.content), ['clean-header', 'header-to-hash'])
      let a:hashes[hash] = get(a:hashes, hash, -1) + 1
      let suffix         = a:hashes[hash] == 0 ? '' : ('-' . a:hashes[hash])
      let lvl            = '<h' . strlen(matchlist(item.content, '^#\{1,6}')[0]) . '>'
      call complete_add({'word': ('#' . hash . suffix), 'menu': ("\t| header | " . lvl . ' ' . s:util.TruncateString(s:util.transform(item.content, ['clean-header']), 35))})
    elseif (item.type == 'anchor')
      let line_part = substitute(getline(item.lnum), '`.*`', '', 'g')[(item._col - 1):]
      if (!empty(matchlist(line_part, '\(name\|id\)="[^"]\+"')))
        call complete_add({'word': ('#' . item.content), 'menu': ("\t| anchor | <a>  " . s:util.TruncateString(s:util.transform(item.content, ['clean-header']), 40))})
      endif
    endif
  endfor
endfun

fun! s:util.IdentifyGrepLink(input)
  let input   = s:util.grepcmd == 'cgrep' ? a:input[1:-2] : a:input
  let parts   = matchlist(input, '^\(.*:\)\?\(\d\+\):\(\d\+\):\(.*\)$')[2:5]
  let lnum    = str2nr(get(parts, 0, 1))
  let cnum    = str2nr(get(parts, 1, 1))
  let matched = get(parts, 2, '')

  if (index(['pt', 'ag', 'ucg', 'ack'], s:util.grepcmd) > -1)
    let mtc     = matchlist(matched[(cnum - 1):], '\(id\|name\)="[^"]\+"\|\]([^)]\+)\|^#\{1,6}.*$')
    let tmp     = get(mtc, 0, '')
    let matched = empty(tmp) ? matched : ((index(['id', 'name'], get(mtc, 1, '')) > -1) ? tmp[:-1] : tmp)
  endif

  if (matched[0]   == '#')    | return { 'type': 'header', 'lnum': lnum, '_col': cnum, 'col': cnum,     'content': matched }       | endif
  if (matched[0:1] == '](')   | return { 'type': 'link',   'lnum': lnum, '_col': cnum, 'col': cnum + 2, 'content': matched[2:-2] } | endif
  if (matched[0:1] == 'id')   | return { 'type': 'anchor', 'lnum': lnum, '_col': cnum, 'col': cnum + 4, 'content': matched[4:-2] } | endif
  if (matched[0:3] == 'href') | return { 'type': 'link',   'lnum': lnum, '_col': cnum, 'col': cnum + 6, 'content': matched[6:-2] } | endif
  if (matched[0:3] == 'name') | return { 'type': 'anchor', 'lnum': lnum, '_col': cnum, 'col': cnum + 6, 'content': matched[6:-2] } | endif

  return { 'type': 'unknown', 'lnum': lnum, 'col': cnum, 'content': matched }
endfun

""""" MAIN FUNCTIONALITY
fun! mkdx#guard_settings()
  if (exists('*dictwatcheradd'))
    call dictwatcheradd(g:, 'mkdx#settings', function(s:util.OnSettingModified, [[]]))
    call s:util.add_dict_watchers(g:mkdx#settings)
  endif
endfun

fun! mkdx#MergeSettings(...)
  let a = get(a:000, 0, {})
  let b = get(a:000, 1, {})
  let o = get(a:000, 2, {'modify': 0})
  let c = o.modify ? a : {}

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

fun! mkdx#InsertCtrlPHandler()
  return getline('.')[col('.') - 2] == '#' ? "\<C-X>\<C-U>" : "\<C-P>"
endfun

fun! mkdx#InsertCtrlNHandler()
  return getline('.')[col('.') - 2] == '#' ? "\<C-X>\<C-U>" : "\<C-N>"
endfun

fun! mkdx#CompleteLink()
  if (s:util.IsInsideLink())
    return "#\<C-X>\<C-U>"
  endif
  return '#'
endfun

fun! s:util.ContextualComplete()
  let col   = col('.') - 2
  let start = col
  let line  = getline('.')

  while (start > 0 && line[start] != '#')
    let start -= 1
  endwhile

  if (line[start] != '#') | return [start, []] | endif

  if (!s:_testing && s:_can_vimgrep_fmt)
    let hashes = {}
    let opts = extend({'pattern': '^#{1,6}.*$|(name|id)="[^"]+"'}, get(s:util.grepopts, s:util.grepcmd, {}))
    let opts['each'] = function(s:util.HeadersAndAnchorsToHashCompletions, [hashes])
    call s:util.Grep(opts)

    exe 'sleep' . get(s:util.grepopts, s:util.grepcmd, {'timeout': 100}).timeout . 'm'

    return [start, []]
  else
    return [start, extend(
          \ map(s:util.ListHeaders(), {idx, val -> {'word': ('#' . val[3] . val[4]), 'menu': ("\t| header | " . s:util.TruncateString(repeat(g:mkdx#settings.tokens.header, val[1]) . ' ' . s:util.transform(val[2], ['clean-header']), 40))}}),
          \ map(s:util.ListIDAnchorLinks(), {idx, val -> {'word': ('#' . val[2]), 'menu': ("\t| anchor | " . val[2])}}))]
  endif
endfun

fun! mkdx#Complete(findstart, base)
  if (a:findstart)
    let s:util._user_compl = s:util.ContextualComplete()
    return s:util._user_compl[0]
  else
    return s:util._user_compl[1]
endfun

fun! mkdx#JumpToHeader()
  let [lnum, cnum] = getpos('.')[1:2]
  let line = getline(lnum)
  let col  = 0
  let len  = strlen(line)
  let lnks = []
  let link = ''

  while (col < len)
    let rgx        = '\[[^\]]\+\](\([^)]\+\))\|<a .*\(name\|id\|href\)="\([^"]\+\)".*>.*</a>'
    let tcol       = match(line[col:], rgx)
    let matches    = matchlist(line[col:], rgx)
    let matchtext  = get(matches, 0, '')
    let is_anchor  = matchtext[0:1] == '<a'
    let addr       = get(matches, is_anchor ? 3 : 1, '')
    let matchlen   = strlen(matchtext)
    let col       += tcol + 1 + matchlen

    if (matchlen < 1) | break | endif
    if (is_anchor && index(['name', 'id'], get(matches, 2, '')) > -1) | return | endif
    if ((col - matchlen) <= cnum && (col - 1) >= cnum)
      let link = addr[(addr[0] == '#' ? 1 : 0):]
      break
    else
      call add(lnks, addr[(addr[0] == '#' ? 1 : 0):])
    endif
  endwhile

  if (empty(link) && !empty(lnks)) | let link = lnks[0] | endif
  if (empty(link)) | return | endif

  if (!s:_testing && s:_can_vimgrep_fmt)
    let hashes               = {}
    let s:util._header_found = 0
    call s:util.Grep({'pattern': '^#{1,6} .*$|(name|id)="[^"]+"',
                    \ 'each': function(s:util.JumpToHeader, [link, hashes])})
  else
    let headers = s:util.ListHeaders()

    for [lnum, column, hash] in s:util.ListIDAnchorLinks()
      if (index(headers, '#' . hash) == -1)
        call add(headers, [lnum, column, hash, ''])
      endif
    endfor

    for [lnum, colnum, header, hash, sfx] in headers
      if (link == (hash . sfx))
        if (g:mkdx#settings.links.fragment.jumplist)
          normal! m'0
        endif

        call cursor(lnum, 0)
        break
      endif
    endfor
  endif
endfun

fun! mkdx#QuickfixDeadLinks(...)
  let [dead, total] = s:util.FindDeadFragmentLinks()
  if (get(a:000, 0, 1))
    let dl = len(dead)

    call setqflist(dead)
    if (!s:_testing && g:mkdx#settings.links.external.enable && s:_can_async && s:_has_curl)
      call s:util.AsyncDeadExternalToQF(0, total)
    endif
    call s:util.log(dl . '/' . total . ' dead fragment link' . (dl == 1 ? '' : 's'), {'hl': (dl > 0 ? 'ErrorMsg' : 'MoreMsg')})
    if (dl > 0) | copen | else | cclose | endif
  else
    return dead
  endif
endfun

fun! mkdx#InsertFencedCodeBlock(...)
  let delim = repeat(!empty(g:mkdx#settings.tokens.fence) ? g:mkdx#settings.tokens.fence : get(a:000, 0, '`'), 3)
  return delim . '' . delim
endfun

fun! mkdx#ToggleToKbd(...)
  let m  = get(a:000, 0, 'n')
  let r  = @z
  let ln = getline('.')

  silent! exe 'normal! ' . (m == 'n' ? '"zdiW' : 'gv"zd')
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
    let img = empty(g:mkdx#settings.image_extension_pattern) ? 0 : (match(get(split(@z, '\.'), -1, ''), g:mkdx#settings.image_extension_pattern) > -1)
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
  let line = getline('.')
  if (!empty(line)) | call setline('.', s:util.transform(getline('.'), ['toggle-quote'])) | endif
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
  let next_nonblank = nextnonblank(a:firstline)
  let firstline     = getline(next_nonblank)

  if (match(firstline, '[,\t]') < 0) | return | endif

  let lines                                   = getline(a:firstline, a:lastline)
  let [col_maxlen, col_align, col_idx, parts] = [{}, {}, [], []]
  let [linecount, ld]                         = [range(0, len(lines) - 1), ' ' . g:mkdx#settings.table.divider . ' ']

  for column in s:util.CsvRowToList(firstline)
    call add(col_idx, column)
    if (index(map(deepcopy(g:mkdx#settings.table.align.left), {idx, val -> tolower(val)}), tolower(column)) > -1)
      let col_align[column] = 'left'
    elseif (index(map(deepcopy(g:mkdx#settings.table.align.right), {idx, val -> tolower(val)}), tolower(column)) > -1)
      let col_align[column] = 'right'
    elseif (index(map(deepcopy(g:mkdx#settings.table.align.center), {idx, val -> tolower(val)}), tolower(column)) > -1)
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

  for linec in linecount
    if !empty(filter(lines[linec], {idx, val -> !empty(val)}))
      call setline(a:firstline + linec,
        \ ld[1:2] . join(map(lines[linec], {key, val -> s:util.AlignString(val, get(col_align, get(col_idx, key, ''), 'center'), col_maxlen[key])}), ld) . ld[0:1])
    endif
  endfor

  for column in keys(col_maxlen)
    let align = tolower(get(col_align, get(col_idx, column, ''), g:mkdx#settings.table.align.default))
    let lhs   = index(['right', 'center'], align) ? ':' : g:mkdx#settings.table.header_divider
    let rhs   = index(['left',  'center'], align) ? ':' : g:mkdx#settings.table.header_divider

    call add(parts, lhs . repeat(g:mkdx#settings.table.header_divider, col_maxlen[column]) . rhs)
  endfor

  call s:util.InsertLine(g:mkdx#settings.table.divider . join(parts, g:mkdx#settings.table.divider) . g:mkdx#settings.table.divider, next_nonblank)
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
    let remove  = empty(substitute(line, sp_pat . ' *', '', ''))
    let incr    = len(split(get(matchlist(line, '^>\? *\([0-9.]\+\) '), 1, ''), '\.')) - 1
    let upd_tl  = (cb || tcb) && g:mkdx#settings.checkbox.update_tree != 0 && at_end
    let tl_prms = remove ? [line('.') - 1, -1] : ['.', 1]
    let qu_str  = (len > 0 ? line[0] == '>' : 0) ? ('>' . get(matchlist(line, '^>\?\( *\)'), 1, '')) : ''

    if (at_end && match(line, '^>\? *[0-9.]\+ ') > -1)
      call s:util.UpdateListNumbers(lnum, incr, (remove ? -1 : 1))
    endif

    if (remove)                                   | call setline('.', '')                                                      | endif
    if (upd_tl)                                   | call call(s:util.UpdateTaskList, tl_prms)                                  | endif
    if (remove)                                   | return ''                                                                  | endif
    if ((match(line, '^ *\*\*') > -1) || !at_end) | return "\n"                                                                | endif
    if (tcb)                                      | return "\n" . qu_str . '[' . g:mkdx#settings.checkbox.initial_state . '] ' | endif

    return ("\n"
      \ . qu_str
      \ . (match(t, '[0-9.]\+') > -1 ? s:util.NextListNumber(t, incr > -1 ? incr : 0) : t)
      \ . (cb ? ' [' . g:mkdx#settings.checkbox.initial_state . '] ' : (!empty(t) ? ' ' : '')))
  endif

  return "\n"
endfun

fun! mkdx#GenerateOrUpdateTOC()
  silent! call repeat#set("\<Plug>(mkdx-gen-or-upd-toc)")

  for lnum in range(1, line('$'))
    if (match(getline(lnum), '^' . g:mkdx#settings.tokens.header . '\{1,6} \+' . g:mkdx#settings.toc.text) > -1)
      call mkdx#UpdateTOC()
      return
    endif
  endfor

  call mkdx#GenerateTOC()
endfun

fun! s:util.GetTOCPositionAndStyle(...)
  let opts   = extend({'text': g:mkdx#settings.toc.text, 'details': g:mkdx#settings.toc.details.enable, 'force': 0}, get(a:000, 0, {}))
  let startc = -1

  for lnum in range(1, line('$'))
    if (match(getline(lnum), '^' . g:mkdx#settings.tokens.header . '\{1,6} \+' . opts.text) > -1)
      let startc = lnum
      break
    endif
  endfor

  if (startc)
    let endc = nextnonblank(startc + 1)
    while (nextnonblank(endc) == endc)
      let endc += 1
      let endl  = getline(endc)
      if (match(endl, '^[ \t]*#\{1,6}') > -1)
        break
      elseif (substitute(endl, '[ \t]\+', '', 'g') == '</details>')
        let endc += 1
        break
      endif
    endwhile
    if (nextnonblank(endc) == endc) | let endc -= 1 | endif
  endif

  let details = (!opts.force && opts.details > -1) ? (getline(nextnonblank(startc + 1)) =~ '^<details>') : opts.details

  return [startc, endc, details]
endfun

fun! mkdx#UpdateTOC(...)
  let opts                    = extend({'text': g:mkdx#settings.toc.text, 'details': g:mkdx#settings.toc.details.enable, 'force': 0}, get(a:000, 0, {}))
  let curpos                  = getpos('.')
  let [startc, endc, details] = s:util.GetTOCPositionAndStyle(opts)

  silent! exe 'normal! :' . startc . ',' . endc . 'd'

  let inslen = mkdx#GenerateTOC(1, details)

  call cursor(curpos[1] - (curpos[1] >= endc ? endc - startc - inslen + 1 : 0), curpos[2])
endfun

fun! mkdx#QuickfixHeaders(...)
  let open_qf  = get(a:000, 0, 1)
  let curr_buf = bufnr('%')
  if (open_qf && !s:_testing && s:_can_vimgrep_fmt)
    call setqflist([])
    call s:util.Grep({'pattern': '^#{1,6} .*$',
                    \ 'each': function(s:util.AddHeaderToQuickfix, [curr_buf]),
                    \ 'done': function(s:util.EchoQuickfixCount, ['header'])})
  else
    let qflist = map(s:util.ListHeaders(),
          \ {k, v -> {'bufnr': curr_buf, 'lnum': v[0], 'level': v[1],
                    \ 'text': repeat(g:mkdx#settings.tokens.header, v[1]) . ' ' . s:util.transform(v[2], ['clean-header']) }})

    if (open_qf)
      call setqflist(qflist)
      if (s:util.EchoQuickfixCount('header')) | copen | else | cclose | endif
    else
      return qflist
    endif
  end
endfun

fun! mkdx#GenerateTOC(...)
  let contents   = []
  let cpos       = getpos('.')
  let header     = ''
  let prevlvl    = 1
  let headers    = {}
  let src        = s:util.ListHeaders()
  let srclen     = len(src)
  let curr       = 0
  let toc_pos    = g:mkdx#settings.toc.position - 1
  let after_info = get(src, toc_pos, -1)
  let after_pos  = toc_pos >= 0 && type(after_info) == type([])
  let detail_opt = get(a:000, 1, -1)
  let do_details = detail_opt > -1 ? detail_opt : g:mkdx#settings.toc.details.enable
  let LI = {prevlvl, spc, hdr, prfx, ending -> add(contents, (do_details ? (spc . '<li>' . s:util.HeaderToATag(hdr, prfx) . ending)
                                                                       \ : s:util.FormatTOCHeader(prevlvl - 1, hdr, prfx)))}

  if (do_details)
    let summary_text = (empty(g:mkdx#settings.toc.details.summary)
                         \ ? g:mkdx#settings.toc.text
                         \ : substitute(g:mkdx#settings.toc.details.summary, '{{toc.text}}', g:mkdx#settings.toc.text, 'g'))

    call extend(contents, ['<details>', '<summary>' . summary_text . '</summary>', '<ul>'])
  endif

  for [lnum, lvl, line, hsh, sfx] in src
    let curr         += 1
    let headers[hsh]  = get(headers, hsh, -1) + 1
    let spc           = repeat(repeat(' ', &sw), lvl)
    let ending_tag    = (get(src, curr, [0, lvl])[1] > lvl) ? '<ul>' : '</li>'

    if (do_details && lvl < prevlvl) | call add(contents, repeat(' ', &sw * lvl) . repeat('</ul></li>', prevlvl - lvl)) | endif
    if (empty(header) && (lnum >= cpos[1] || (curr > toc_pos && after_pos)))
      let header       = repeat(g:mkdx#settings.tokens.header, prevlvl) . ' ' . g:mkdx#settings.toc.text
      let csh          = s:util.transform(tolower(header), ['clean-header', 'header-to-hash'])
      let headers[csh] = get(headers, csh, -1) + 1
      let contents     = extend([header, ''], contents)
      call LI(prevlvl, spc, header, ((headers[csh] > 0) ? '-' . headers[csh] : ''), ending_tag)
    endif

    call LI(lvl, spc, line, sfx, ending_tag)
    if (empty(header) && curr == srclen)
      let header       = repeat(g:mkdx#settings.tokens.header, prevlvl) . ' ' . g:mkdx#settings.toc.text
      let csh          = s:util.transform(tolower(header), ['clean-header', 'header-to-hash'])
      let headers[csh] = get(headers, csh, -1) + 1
      let contents     = extend([header, ''], contents)
      call LI(prevlvl, spc, header, ((headers[csh] > 0) ? '-' . headers[csh] : ''), ending_tag)
    endif

    let prevlvl = lvl
  endfor

  if (do_details && prevlvl > 0) | call add(contents, repeat(' ', &sw) . repeat('</ul></li>', prevlvl - 1)) | endif
  if (do_details) | call extend(contents, ['</ul>', '</details>']) | endif

  let c = (!get(a:000, 0, 0) && after_pos) ? : (after_info[0] - 1) : (cpos[1] - 1)

  if (c > 0 && nextnonblank(c) == c)     | call insert(contents, '') | endif
  if (after_pos || !empty(getline('.'))) | call add(contents, '')    | endif

  for item in contents
    call append(c, item)
    let c += 1
  endfor

  call setpos('.', cpos)
  return len(contents)
endfun
