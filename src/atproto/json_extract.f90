module json_extract_mod
  use strings_mod, only: json_unescape, squeeze_spaces, replace_all
  use models_mod, only: post_view, stream_event, actor_profile, notification_view, MAX_ITEMS, FIELD_LEN, HANDLE_LEN, URI_LEN, CID_LEN, TS_LEN
  implicit none
  private
  public :: extract_json_string, extract_json_object_after, extract_json_array_after
  public :: next_array_object, extract_reply_refs, slice_fit, find_first_array
  public :: extract_posts, extract_thread_posts, extract_stream_events
  public :: escape_json_string, extract_profile, extract_notifications
  public :: extract_json_string_any
contains
  function extract_json_string(json, key, start_at) result(value)
    character(len=*), intent(in) :: json, key
    integer, intent(in), optional :: start_at
    character(len=:), allocatable :: value
    integer :: s, vstart, vend, kind

    s = 1
    if (present(start_at)) s = max(1, start_at)
    call find_key_value(json, key, s, vstart, vend, kind)
    if (kind == 1 .and. vstart > 0 .and. vend >= vstart) then
      value = squeeze_spaces(json_unescape(json(vstart:vend)))
    else if (kind == 4 .and. vstart > 0 .and. vend >= vstart) then
      value = adjustl(trim(json(vstart:vend)))
    else
      value = ''
    end if
  end function extract_json_string

  ! Like extract_json_string but searches at any nesting depth.
  ! Use for keys that appear deep in nested objects (e.g. embed.images[0].fullsize).
  function extract_json_string_any(json, key) result(value)
    character(len=*), intent(in) :: json, key
    character(len=:), allocatable :: value
    character(len=:), allocatable :: key_pat
    integer :: pos, vstart, vend

    value = ''
    key_pat = '"' // trim(key) // '"'
    pos = index(json, key_pat)
    if (pos == 0) return

    ! Skip past the key and colon to the value
    pos = pos + len(key_pat)
    do while (pos <= len(json) .and. (json(pos:pos) == ' ' .or. json(pos:pos) == ':'))
      pos = pos + 1
    end do
    if (pos > len(json)) return

    if (json(pos:pos) == '"') then
      vstart = pos + 1
      vend = parse_json_string_end(json, pos)
      if (vend > pos) value = squeeze_spaces(json_unescape(json(vstart:vend-1)))
    end if
  end function extract_json_string_any

  function extract_json_object_after(json, key, start_at) result(obj)
    character(len=*), intent(in) :: json, key
    integer, intent(in), optional :: start_at
    character(len=:), allocatable :: obj
    integer :: s, vstart, vend, kind

    s = 1
    if (present(start_at)) s = max(1, start_at)
    call find_key_value(json, key, s, vstart, vend, kind)
    if (kind == 2 .and. vstart > 0 .and. vend >= vstart) then
      obj = json(vstart:vend)
    else
      obj = ''
    end if
  end function extract_json_object_after

  subroutine extract_posts(json, posts, n)
    character(len=*), intent(in) :: json
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: arr

    posts = post_view()
    n = 0
    arr = find_first_array(json, [character(len=32) :: 'feed', 'posts'])
    if (len_trim(arr) == 0) return
    call extract_post_array(arr, posts, n)
  end subroutine extract_posts

  subroutine extract_thread_posts(json, posts, n)
    character(len=*), intent(in) :: json
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: thread_obj

    posts = post_view()
    n = 0
    thread_obj = extract_json_object_after(json, 'thread')
    if (len_trim(thread_obj) == 0) return
    call walk_thread(thread_obj, posts, n)
  contains
    recursive subroutine walk_thread(obj, posts, n)
      character(len=*), intent(in) :: obj
      type(post_view), intent(inout) :: posts(MAX_ITEMS)
      integer, intent(inout) :: n
      character(len=:), allocatable :: post_obj, parent_obj, replies_arr, child_obj
      integer :: i, istart, iend

      post_obj = extract_json_object_after(obj, 'post')
      if (len_trim(post_obj) > 0) call append_post_object(post_obj, posts, n)

      parent_obj = extract_json_object_after(obj, 'parent')
      if (len_trim(parent_obj) > 0) call walk_thread(parent_obj, posts, n)

      replies_arr = extract_json_array_after(obj, 'replies')
      if (len_trim(replies_arr) > 0) then
        i = 1
        do
          call next_array_object(replies_arr, i, istart, iend)
          if (istart == 0) exit
          child_obj = replies_arr(istart:iend)
          call walk_thread(child_obj, posts, n)
          i = iend + 1
        end do
      end if
    end subroutine walk_thread
  end subroutine extract_thread_posts

  subroutine extract_stream_events(blob, events, n)
    character(len=*), intent(in) :: blob
    type(stream_event), intent(out) :: events(MAX_ITEMS)
    integer, intent(out) :: n
    integer :: start, stop, l
    character(len=:), allocatable :: line

    events = stream_event()
    n = 0
    l = len_trim(blob)
    start = 1
    do while (start <= l .and. n < MAX_ITEMS)
      stop = index(blob(start:), new_line('a'))
      if (stop == 0) then
        line = blob(start:l)
        start = l + 1
      else
        stop = start + stop - 2
        line = blob(start:stop)
        start = stop + 2
      end if
      if (len_trim(line) == 0) cycle
      n = n + 1
      events(n)%kind = slice_fit(extract_json_string(line, 'kind'), 32)
      if (len_trim(events(n)%kind) == 0) events(n)%kind = slice_fit(extract_json_string(line, 'event'), 32)
      events(n)%handle = slice_fit(extract_json_string(line, 'handle'), HANDLE_LEN)
      events(n)%did = slice_fit(extract_json_string(line, 'did'), URI_LEN)
      events(n)%text = slice_fit(extract_json_string(line, 'text'), FIELD_LEN)
      events(n)%time_us = slice_fit(extract_json_string(line, 'time_us'), TS_LEN)
    end do
  end subroutine extract_stream_events

  subroutine extract_profile(json, profile)
    character(len=*), intent(in) :: json
    type(actor_profile), intent(out) :: profile

    profile = actor_profile()
    profile%display_name = slice_fit(extract_json_string(json, 'displayName'), FIELD_LEN)
    profile%handle = slice_fit(extract_json_string(json, 'handle'), HANDLE_LEN)
    profile%did = slice_fit(extract_json_string(json, 'did'), URI_LEN)
    profile%description = slice_fit(extract_json_string(json, 'description'), FIELD_LEN)
    profile%indexed_at = slice_fit(extract_json_string(json, 'indexedAt'), TS_LEN)
    profile%followers_count = slice_fit(extract_json_string(json, 'followersCount'), 64)
    profile%follows_count = slice_fit(extract_json_string(json, 'followsCount'), 64)
    profile%posts_count = slice_fit(extract_json_string(json, 'postsCount'), 64)
  end subroutine extract_profile

  subroutine extract_notifications(json, items, n)
    character(len=*), intent(in) :: json
    type(notification_view), intent(out) :: items(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: arr, obj, author_obj, record_obj, reason_subject
    integer :: i, istart, iend

    items = notification_view()
    n = 0
    arr = extract_json_array_after(json, 'notifications')
    if (len_trim(arr) == 0) return
    i = 1
    do while (n < MAX_ITEMS)
      call next_array_object(arr, i, istart, iend)
      if (istart == 0) exit
      obj = arr(istart:iend)
      n = n + 1
      items(n)%reason = slice_fit(extract_json_string(obj, 'reason'), 32)
      items(n)%indexed_at = slice_fit(extract_json_string(obj, 'indexedAt'), TS_LEN)
      author_obj = extract_json_object_after(obj, 'author')
      if (len_trim(author_obj) > 0) then
        items(n)%author = slice_fit(extract_json_string(author_obj, 'displayName'), FIELD_LEN)
        items(n)%handle = slice_fit(extract_json_string(author_obj, 'handle'), HANDLE_LEN)
        if (len_trim(items(n)%author) == 0) items(n)%author = items(n)%handle
      end if
      record_obj = extract_json_object_after(obj, 'record')
      if (len_trim(record_obj) > 0) then
        items(n)%text = slice_fit(extract_json_string(record_obj, 'text'), FIELD_LEN)
        call extract_reply_refs(record_obj, items(n)%parent_uri, items(n)%parent_cid, items(n)%root_uri, items(n)%root_cid)
      end if
      reason_subject = extract_json_string(obj, 'reasonSubject')
      items(n)%uri = slice_fit(reason_subject, URI_LEN)
      items(n)%cid = slice_fit(extract_json_string(obj, 'cid'), CID_LEN)
      i = iend + 1
    end do
  end subroutine extract_notifications

  function escape_json_string(text) result(out)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: out
    out = trim(text)
    out = replace_all(out, '\\', '\\\\')
    out = replace_all(out, '"', '\\"')
    out = replace_all(out, new_line('a'), ' ')
  end function escape_json_string

  subroutine extract_post_array(arr, posts, n)
    character(len=*), intent(in) :: arr
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    integer :: i, istart, iend
    character(len=:), allocatable :: item, post_obj

    n = 0
    i = 1
    do while (n < MAX_ITEMS)
      call next_array_object(arr, i, istart, iend)
      if (istart == 0) exit
      item = arr(istart:iend)
      if (len_trim(extract_json_object_after(item, 'post')) > 0) then
        post_obj = extract_json_object_after(item, 'post')
      else
        post_obj = item
      end if
      call append_post_object(post_obj, posts, n)
      i = iend + 1
    end do
  end subroutine extract_post_array

  subroutine append_post_object(post_obj, posts, n)
    character(len=*), intent(in) :: post_obj
    type(post_view), intent(inout) :: posts(MAX_ITEMS)
    integer, intent(inout) :: n
    character(len=:), allocatable :: author_obj, record_obj, author, handle, text, uri, cid, ts
    character(len=URI_LEN) :: parent_uri, root_uri
    character(len=CID_LEN) :: parent_cid, root_cid

    if (n >= MAX_ITEMS) return
    text = extract_json_string(post_obj, 'text')
    uri = extract_json_string(post_obj, 'uri')
    cid = extract_json_string(post_obj, 'cid')
    ts = extract_json_string(post_obj, 'indexedAt')
    if (len_trim(ts) == 0) ts = extract_json_string(post_obj, 'createdAt')

    author_obj = extract_json_object_after(post_obj, 'author')
    author = ''
    handle = ''
    if (len_trim(author_obj) > 0) then
      author = extract_json_string(author_obj, 'displayName')
      handle = extract_json_string(author_obj, 'handle')
    end if

    record_obj = extract_json_object_after(post_obj, 'record')
    if (len_trim(text) == 0) then
      if (len_trim(record_obj) > 0) then
        text = extract_json_string(record_obj, 'text')
        if (len_trim(ts) == 0) ts = extract_json_string(record_obj, 'createdAt')
      end if
    end if

    parent_uri = ''
    parent_cid = ''
    root_uri = ''
    root_cid = ''
    if (len_trim(record_obj) > 0) call extract_reply_refs(record_obj, parent_uri, parent_cid, root_uri, root_cid)

    if (len_trim(author) == 0) author = handle
    if (len_trim(text) == 0 .and. len_trim(uri) == 0) return

    n = n + 1
    posts(n)%author = slice_fit(author, FIELD_LEN)
    posts(n)%handle = slice_fit(handle, HANDLE_LEN)
    posts(n)%text = slice_fit(text, FIELD_LEN)
    posts(n)%uri = slice_fit(uri, URI_LEN)
    posts(n)%cid = slice_fit(cid, CID_LEN)
    posts(n)%indexed_at = slice_fit(ts, TS_LEN)
    posts(n)%parent_uri = parent_uri
    posts(n)%parent_cid = parent_cid
    posts(n)%root_uri = root_uri
    posts(n)%root_cid = root_cid
  end subroutine append_post_object

  subroutine extract_reply_refs(record_obj, parent_uri, parent_cid, root_uri, root_cid)
    character(len=*), intent(in) :: record_obj
    character(len=*), intent(out) :: parent_uri, parent_cid, root_uri, root_cid
    character(len=:), allocatable :: reply_obj, parent_obj, root_obj

    parent_uri = ''
    parent_cid = ''
    root_uri = ''
    root_cid = ''
    reply_obj = extract_json_object_after(record_obj, 'reply')
    if (len_trim(reply_obj) == 0) return
    parent_obj = extract_json_object_after(reply_obj, 'parent')
    root_obj = extract_json_object_after(reply_obj, 'root')
    if (len_trim(parent_obj) > 0) then
      parent_uri = slice_fit(extract_json_string(parent_obj, 'uri'), len(parent_uri))
      parent_cid = slice_fit(extract_json_string(parent_obj, 'cid'), len(parent_cid))
    end if
    if (len_trim(root_obj) > 0) then
      root_uri = slice_fit(extract_json_string(root_obj, 'uri'), len(root_uri))
      root_cid = slice_fit(extract_json_string(root_obj, 'cid'), len(root_cid))
    end if
  end subroutine extract_reply_refs

  function find_first_array(json, keys) result(arr)
    character(len=*), intent(in) :: json
    character(len=*), dimension(:), intent(in) :: keys
    character(len=:), allocatable :: arr
    integer :: i, vstart, vend, kind

    arr = ''
    do i = 1, size(keys)
      call find_key_value(json, trim(keys(i)), 1, vstart, vend, kind)
      if (kind == 3 .and. vstart > 0) then
        arr = json(vstart:vend)
        return
      end if
    end do
  end function find_first_array

  function extract_json_array_after(json, key) result(arr)
    character(len=*), intent(in) :: json, key
    character(len=:), allocatable :: arr
    integer :: vstart, vend, kind

    call find_key_value(json, key, 1, vstart, vend, kind)
    if (kind == 3 .and. vstart > 0) then
      arr = json(vstart:vend)
    else
      arr = ''
    end if
  end function extract_json_array_after

  subroutine next_array_object(arr, pos_inout, obj_start, obj_end)
    character(len=*), intent(in) :: arr
    integer, intent(inout) :: pos_inout
    integer, intent(out) :: obj_start, obj_end
    integer :: i, start_pos, end_pos

    obj_start = 0
    obj_end = 0
    i = max(1, pos_inout)
    do while (i <= len_trim(arr))
      if (arr(i:i) == '{') then
        start_pos = i
        end_pos = match_bracket(arr, i, '{', '}')
        if (end_pos > 0) then
          obj_start = start_pos
          obj_end = end_pos
          pos_inout = end_pos + 1
        end if
        return
      end if
      i = i + 1
    end do
  end subroutine next_array_object

  subroutine find_key_value(json, key, start_at, value_start, value_end, value_kind)
    character(len=*), intent(in) :: json, key
    integer, intent(in) :: start_at
    integer, intent(out) :: value_start, value_end, value_kind
    integer :: i, kend, colon_pos, depth
    character(len=:), allocatable :: key_text

    value_start = 0
    value_end = 0
    value_kind = 0
    key_text = trim(key)
    i = max(1, start_at)
    depth = 0
    do while (i <= len_trim(json))
      select case (json(i:i))
      case ('{', '[')
        depth = depth + 1
        i = i + 1
      case ('}', ']')
        depth = depth - 1
        i = i + 1
      case ('"')
        kend = parse_json_string_end(json, i)
        if (kend <= i) exit
        ! Only match keys at depth 1 (direct children of the top-level object)
        if (depth == 1 .and. json_unescape(json(i+1:kend-1)) == key_text) then
          colon_pos = skip_ws(json, kend + 1)
          if (colon_pos <= len_trim(json) .and. json(colon_pos:colon_pos) == ':') then
            colon_pos = skip_ws(json, colon_pos + 1)
            call capture_value_bounds(json, colon_pos, value_start, value_end, value_kind)
            return
          end if
        end if
        i = kend + 1
      case default
        i = i + 1
      end select
    end do
  end subroutine find_key_value

  subroutine capture_value_bounds(json, pos, value_start, value_end, value_kind)
    character(len=*), intent(in) :: json
    integer, intent(in) :: pos
    integer, intent(out) :: value_start, value_end, value_kind
    integer :: p, e

    value_start = 0
    value_end = 0
    value_kind = 0
    p = skip_ws(json, pos)
    if (p > len_trim(json)) return
    select case (json(p:p))
    case ('"')
      e = parse_json_string_end(json, p)
      if (e > p) then
        value_start = p + 1
        value_end = e - 1
        value_kind = 1
      end if
    case ('{')
      e = match_bracket(json, p, '{', '}')
      if (e > 0) then
        value_start = p
        value_end = e
        value_kind = 2
      end if
    case ('[')
      e = match_bracket(json, p, '[', ']')
      if (e > 0) then
        value_start = p
        value_end = e
        value_kind = 3
      end if
    case default
      e = p
      do while (e <= len_trim(json))
        select case (json(e:e))
        case (',','}',']')
          exit
        case default
          e = e + 1
        end select
      end do
      value_start = p
      value_end = e - 1
      value_kind = 4
    end select
  end subroutine capture_value_bounds

  integer function skip_ws(text, pos) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: pos
    integer :: i
    i = max(1, pos)
    do while (i <= len(text))
      select case (text(i:i))
      case (' ', achar(9), achar(10), achar(13))
        i = i + 1
      case default
        exit
      end select
    end do
    out = i
  end function skip_ws

  integer function parse_json_string_end(text, quote_pos) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: quote_pos
    integer :: i, backslashes

    out = 0
    i = quote_pos + 1
    do while (i <= len_trim(text))
      if (text(i:i) == '"') then
        backslashes = 0
        do while (i - backslashes - 1 >= quote_pos .and. text(i-backslashes-1:i-backslashes-1) == '\\')
          backslashes = backslashes + 1
        end do
        if (mod(backslashes, 2) == 0) then
          out = i
          return
        end if
      end if
      i = i + 1
    end do
  end function parse_json_string_end

  integer function match_bracket(text, start_pos, open_ch, close_ch) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: start_pos
    character(len=1), intent(in) :: open_ch, close_ch
    integer :: i, depth, s_end

    out = 0
    depth = 0
    i = start_pos
    do while (i <= len_trim(text))
      if (text(i:i) == '"') then
        s_end = parse_json_string_end(text, i)
        if (s_end <= i) return
        i = s_end + 1
        cycle
      end if
      if (text(i:i) == open_ch) depth = depth + 1
      if (text(i:i) == close_ch) then
        depth = depth - 1
        if (depth == 0) then
          out = i
          return
        end if
      end if
      i = i + 1
    end do
  end function match_bracket

  function slice_fit(text, n) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: n
    character(len=n) :: out
    integer :: m
    out = ''
    m = min(len_trim(text), n)
    if (m > 0) out(1:m) = text(1:m)
  end function slice_fit
end module json_extract_mod
