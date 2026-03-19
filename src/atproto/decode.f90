module decode_mod
  use models_mod, only: post_view, stream_event, actor_profile, notification_view, MAX_ITEMS, FIELD_LEN, HANDLE_LEN, URI_LEN, CID_LEN, TS_LEN
  use json_extract_mod, only: extract_json_string, extract_json_object_after, extract_json_array_after, &
                              next_array_object, extract_reply_refs, slice_fit, find_first_array
  implicit none
  private
  public :: decode_posts_json, decode_thread_json, decode_profile_json, decode_notifications_json, decode_stream_blob
contains
  subroutine decode_posts_json(json, posts, n)
    character(len=*), intent(in) :: json
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: arr
    posts = post_view()
    n = 0
    arr = find_first_array(json, [character(len=32) :: 'feed', 'posts'])
    if (len_trim(arr) == 0) return
    call decode_post_array(arr, posts, n)
  end subroutine decode_posts_json

  subroutine decode_thread_json(json, posts, n)
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
      if (len_trim(post_obj) > 0) call append_post(post_obj, posts, n)
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
  end subroutine decode_thread_json

  subroutine decode_profile_json(json, profile)
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
  end subroutine decode_profile_json

  subroutine decode_notifications_json(json, items, n)
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
  end subroutine decode_notifications_json

  subroutine decode_stream_blob(blob, events, n)
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
      call decode_stream_line(line, events(n))
    end do
  end subroutine decode_stream_blob

  subroutine decode_post_array(arr, posts, n)
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
      call append_post(post_obj, posts, n)
      i = iend + 1
    end do
  end subroutine decode_post_array

  subroutine append_post(post_obj, posts, n)
    character(len=*), intent(in) :: post_obj
    type(post_view), intent(inout) :: posts(MAX_ITEMS)
    integer, intent(inout) :: n
    type(post_view) :: post
    call decode_post(post_obj, post)
    if (len_trim(post%text) == 0 .and. len_trim(post%uri) == 0) return
    if (n >= MAX_ITEMS) return
    n = n + 1
    posts(n) = post
  end subroutine append_post

  subroutine decode_post(post_obj, post)
    character(len=*), intent(in) :: post_obj
    type(post_view), intent(out) :: post
    character(len=:), allocatable :: author_obj, record_obj, reason_obj, reason_type
    post = post_view()
    post%text = slice_fit(extract_json_string(post_obj, 'text'), FIELD_LEN)
    post%uri = slice_fit(extract_json_string(post_obj, 'uri'), URI_LEN)
    post%cid = slice_fit(extract_json_string(post_obj, 'cid'), CID_LEN)
    post%indexed_at = slice_fit(extract_json_string(post_obj, 'indexedAt'), TS_LEN)
    post%like_count = slice_fit(extract_json_string(post_obj, 'likeCount'), 8)
    post%repost_count = slice_fit(extract_json_string(post_obj, 'repostCount'), 8)
    post%reply_count = slice_fit(extract_json_string(post_obj, 'replyCount'), 8)
    post%quote_count = slice_fit(extract_json_string(post_obj, 'quoteCount'), 8)
    if (len_trim(post%indexed_at) == 0) post%indexed_at = slice_fit(extract_json_string(post_obj, 'createdAt'), TS_LEN)
    author_obj = extract_json_object_after(post_obj, 'author')
    if (len_trim(author_obj) > 0) then
      post%author = slice_fit(extract_json_string(author_obj, 'displayName'), FIELD_LEN)
      post%handle = slice_fit(extract_json_string(author_obj, 'handle'), HANDLE_LEN)
      if (len_trim(post%author) == 0) post%author = post%handle
    end if
    reason_obj = extract_json_object_after(post_obj, 'reason')
    if (len_trim(reason_obj) > 0) then
      reason_type = extract_json_string(reason_obj, '$type')
      if (index(reason_type, 'reasonRepost') > 0) then
        post%reason = 'repost'
        post%is_repost = .true.
      else if (index(reason_type, 'reasonPin') > 0) then
        post%reason = 'pin'
      else if (index(reason_type, 'reason') > 0) then
        post%reason = slice_fit(reason_type, 32)
      end if
    end if
    record_obj = extract_json_object_after(post_obj, 'record')
    if (len_trim(record_obj) > 0) then
      post%record_type = slice_fit(extract_json_string(record_obj, '$type'), 32)
      if (len_trim(post%text) == 0) post%text = slice_fit(extract_json_string(record_obj, 'text'), FIELD_LEN)
      if (len_trim(post%indexed_at) == 0) post%indexed_at = slice_fit(extract_json_string(record_obj, 'createdAt'), TS_LEN)
      call extract_reply_refs(record_obj, post%parent_uri, post%parent_cid, post%root_uri, post%root_cid)
      if (index(record_obj, '"facets"') > 0) post%has_facets = .true.
    end if
    if (index(post_obj, 'app.bsky.embed.images') > 0) post%has_images = .true.
    if (index(post_obj, 'app.bsky.embed.video') > 0) post%has_video = .true.
    if (index(post_obj, 'app.bsky.embed.external') > 0) post%has_external = .true.
    if (index(post_obj, 'app.bsky.embed.record') > 0) then
      post%is_quote = .true.
      if (len_trim(post%record_type) == 0) post%record_type = 'quote'
    end if
    if (len_trim(post%record_type) == 0) post%record_type = 'post'
  end subroutine decode_post

  subroutine decode_stream_line(line, event)
    character(len=*), intent(in) :: line
    type(stream_event), intent(out) :: event
    event = stream_event()
    event%kind = slice_fit(extract_json_string(line, 'kind'), 32)
    if (len_trim(event%kind) == 0) event%kind = slice_fit(extract_json_string(line, 'event'), 32)
    event%handle = slice_fit(extract_json_string(line, 'handle'), HANDLE_LEN)
    event%did = slice_fit(extract_json_string(line, 'did'), URI_LEN)
    event%text = slice_fit(extract_json_string(line, 'text'), FIELD_LEN)
    event%time_us = slice_fit(extract_json_string(line, 'time_us'), TS_LEN)
  end subroutine decode_stream_line
end module decode_mod
