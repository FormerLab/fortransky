module client_mod
  use http_cbridge_mod, only: http_get, http_post_json, http_post_binary, http_get_urlencoded, &
                              http_get_proxied, http_post_json_proxied, http_get_to_file, last_http_status
  use json_extract_mod, only: extract_json_string, escape_json_string
  use decode_mod, only: decode_posts_json, decode_stream_blob, decode_thread_json, decode_profile_json, decode_notifications_json
  use models_mod, only: session_state, post_view, stream_event, actor_profile, notification_view, &
                        convo_view, dm_message, MAX_ITEMS, HANDLE_LEN, URI_LEN
  use app_state_mod, only: app_state, DID_CACHE_SIZE
  use process_mod, only: run_capture, slurp_file
  use log_store_mod, only: state_file, append_line, read_first_line, write_text
  implicit none
  private
  public :: session_state, login_session, fetch_author_feed, search_posts, fetch_timeline
  public :: tail_live_stream, fetch_post_thread, create_post, create_reply, create_quote_post, like_post, repost_post
  public :: fetch_profile_view, fetch_notifications_view, load_saved_session, save_session, clear_saved_session
  public :: resolve_did_to_handle, upload_blob, create_image_post
  public :: list_convos, get_messages, send_dm, get_convo_for_member
  public :: fetch_image_blob
contains
  subroutine load_saved_session(state)
    type(session_state), intent(inout) :: state
    character(len=:), allocatable :: body, pds

    body = read_first_line(state_file('session.json'))
    if (len_trim(body) == 0) return
    state%identifier = ''
    state%did = ''
    state%access_jwt = ''
    state%refresh_jwt = ''
    call copy_fit(extract_json_string(body, 'identifier'), state%identifier)
    call copy_fit(extract_json_string(body, 'did'), state%did)
    call copy_fit(extract_json_string(body, 'accessJwt'), state%access_jwt)
    call copy_fit(extract_json_string(body, 'refreshJwt'), state%refresh_jwt)
    pds = extract_json_string(body, 'pdsHost')
    if (len_trim(pds) > 0 .and. pds(1:4) == 'http') call copy_fit(pds, state%pds_host)
  end subroutine load_saved_session

  subroutine save_session(state)
    type(session_state), intent(in) :: state
    character(len=:), allocatable :: body
    body = '{"identifier":"' // escape_json_string(trim(state%identifier)) // '",' // &
           '"did":"' // escape_json_string(trim(state%did)) // '",' // &
           '"pdsHost":"' // escape_json_string(trim(state%pds_host)) // '",' // &
           '"accessJwt":"' // escape_json_string(trim(state%access_jwt)) // '",' // &
           '"refreshJwt":"' // escape_json_string(trim(state%refresh_jwt)) // '"}'
    call write_text(state_file('session.json'), body)
  end subroutine save_session

  subroutine clear_saved_session()
    call write_text(state_file('session.json'), '')
  end subroutine clear_saved_session

  subroutine copy_fit(src, dest)
    character(len=*), intent(in) :: src
    character(len=*), intent(inout) :: dest
    dest = ''
    if (len_trim(src) > 0) dest(1:min(len_trim(src), len(dest))) = src(1:min(len_trim(src), len(dest)))
  end subroutine copy_fit

  function itoa(i) result(s)
    integer, intent(in) :: i
    character(len=:), allocatable :: s
    character(len=32) :: tmp
    write(tmp,'(i0)') i
    s = trim(tmp)
  end function itoa

  subroutine login_session(state, password, ok, message)
    type(session_state), intent(inout) :: state
    character(len=*), intent(in) :: password
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=:), allocatable :: body, payload, access, refresh, did, identifier

    identifier = escape_json_string(trim(state%identifier))
    payload = '{"identifier":"' // identifier // '","password":"' // escape_json_string(trim(password)) // '"}'
    body = http_post_json(trim(state%pds_host) // '/xrpc/com.atproto.server.createSession', payload)
    access = extract_json_string(body, 'accessJwt')
    refresh = extract_json_string(body, 'refreshJwt')
    did = extract_json_string(body, 'did')
    if (len_trim(access) > 0) then
      state%access_jwt = ''
      state%refresh_jwt = ''
      state%did = ''
      state%access_jwt(1:min(len_trim(access), len(state%access_jwt))) = access(1:min(len_trim(access), len(state%access_jwt)))
      state%refresh_jwt(1:min(len_trim(refresh), len(state%refresh_jwt))) = &
        refresh(1:min(len_trim(refresh), len(state%refresh_jwt)))
      state%did(1:min(len_trim(did), len(state%did))) = did(1:min(len_trim(did), len(state%did)))
      ! Resolve real PDS host from plc.directory
      block
        character(len=:), allocatable :: plc_body, endpoint
        plc_body = http_get('https://plc.directory/' // trim(state%did))
        endpoint = extract_json_string(plc_body, 'serviceEndpoint')
        if (len_trim(endpoint) > 0 .and. endpoint(1:4) == 'http') then
          call copy_fit(endpoint, state%pds_host)
        end if
      end block
      ok = .true.
      call save_session(state)
      message = 'Login OK'
    else
      ok = .false.
      message = 'Login failed (HTTP ' // trim(itoa(last_http_status)) // ')'
    end if
  end subroutine login_session

  subroutine fetch_author_feed(handle, posts, n)
    character(len=*), intent(in) :: handle
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: body

    body = http_get_urlencoded('https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?limit=40', 'actor', trim(handle))
    call decode_posts_json(body, posts, n)
  end subroutine fetch_author_feed

  subroutine search_posts(query, posts, n)
    character(len=*), intent(in) :: query
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    character(len=:), allocatable :: body

    body = http_get_urlencoded('https://public.api.bsky.app/xrpc/app.bsky.feed.searchPosts?limit=40', 'q', trim(query))
    call decode_posts_json(body, posts, n)
  end subroutine search_posts

  subroutine fetch_timeline(state, posts, n, ok)
    type(session_state), intent(in) :: state
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    logical, intent(out) :: ok
    character(len=:), allocatable :: body

    if (len_trim(state%access_jwt) == 0) then
      ok = .false.
      n = 0
      posts = post_view()
      return
    end if

    body = http_get(trim(state%pds_host) // '/xrpc/app.bsky.feed.getTimeline?limit=40', trim(state%access_jwt))
    call decode_posts_json(body, posts, n)
    ok = (last_http_status >= 200 .and. last_http_status < 300)
  end subroutine fetch_timeline

  subroutine fetch_profile_view(handle, profile, ok, message)
    character(len=*), intent(in) :: handle
    type(actor_profile), intent(out) :: profile
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=:), allocatable :: body

    body = http_get_urlencoded('https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile', 'actor', trim(handle))
    call decode_profile_json(body, profile)
    ok = len_trim(profile%handle) > 0 .or. len_trim(profile%did) > 0
    if (ok) then
      message = 'Profile loaded'
    else
      message = 'Profile fetch failed'
    end if
  end subroutine fetch_profile_view

  subroutine fetch_notifications_view(state, items, n, ok, message)
    type(session_state), intent(in) :: state
    type(notification_view), intent(out) :: items(MAX_ITEMS)
    integer, intent(out) :: n
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=:), allocatable :: body

    if (len_trim(state%access_jwt) == 0) then
      items = notification_view()
      n = 0
      ok = .false.
      message = 'Login required before reading notifications.'
      return
    end if

    body = http_get(trim(state%pds_host) // '/xrpc/app.bsky.notification.listNotifications?limit=40', trim(state%access_jwt))
    call decode_notifications_json(body, items, n)
    ok = (last_http_status >= 200 .and. last_http_status < 300)
    if (ok) then
      message = 'Notifications loaded'
    else
      message = 'No notifications decoded'
    end if
  end subroutine fetch_notifications_view

  subroutine fetch_post_thread(uri_or_url, posts, n, ok, message)
    character(len=*), intent(in) :: uri_or_url
    type(post_view), intent(out) :: posts(MAX_ITEMS)
    integer, intent(out) :: n
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=:), allocatable :: uri, body

    uri = normalize_post_ref(trim(uri_or_url))
    if (len_trim(uri) == 0) then
      posts = post_view()
      n = 0
      ok = .false.
      message = 'Could not parse post reference. Use at://... or a bsky.app post URL.'
      return
    end if

    body = http_get_urlencoded('https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread', 'uri', trim(uri))
    call decode_thread_json(body, posts, n)
    ok = (last_http_status >= 200 .and. last_http_status < 300)
    if (ok) then
      message = 'Thread loaded for ' // trim(uri)
    else
      message = 'No thread posts decoded. Try a direct at:// URI.'
    end if
  contains
    function normalize_post_ref(raw) result(uri)
      character(len=*), intent(in) :: raw
      character(len=:), allocatable :: uri
      character(len=:), allocatable :: tmp
      integer :: p1, p2

      tmp = trim(raw)
      if (index(tmp, 'at://') == 1) then
        uri = tmp
        return
      end if
      if (index(tmp, 'https://bsky.app/profile/') == 1) then
        p1 = len('https://bsky.app/profile/') + 1
        p2 = index(tmp(p1:), '/post/')
        if (p2 > 0) then
          uri = 'at://' // tmp(p1:p1+p2-2) // '/app.bsky.feed.post/' // tmp(p1+p2+5:)
          return
        end if
      end if
      uri = ''
    end function normalize_post_ref
  end subroutine fetch_post_thread

  subroutine create_post(state, text, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_record_with_optional_reply(state, text, '', '', '', '', ok, message, created_uri)
  end subroutine create_post

  subroutine create_reply(state, text, parent_uri, parent_cid, root_uri, root_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text, parent_uri, parent_cid, root_uri, root_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_record_with_optional_reply(state, text, parent_uri, parent_cid, root_uri, root_cid, ok, message, created_uri)
  end subroutine create_reply

  subroutine create_quote_post(state, text, quote_uri, quote_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text, quote_uri, quote_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_record_with_embed(state, text, quote_uri, quote_cid, ok, message, created_uri)
  end subroutine create_quote_post

  subroutine like_post(state, subject_uri, subject_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: subject_uri, subject_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_subject_action_record(state, 'app.bsky.feed.like', subject_uri, subject_cid, ok, message, created_uri)
  end subroutine like_post

  subroutine repost_post(state, subject_uri, subject_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: subject_uri, subject_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_subject_action_record(state, 'app.bsky.feed.repost', subject_uri, subject_cid, ok, message, created_uri)
  end subroutine repost_post

  subroutine create_record_with_optional_reply(state, text, parent_uri, parent_cid, root_uri, root_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text, parent_uri, parent_cid, root_uri, root_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_post_record(state, text, parent_uri, parent_cid, root_uri, root_cid, '', '', ok, message, created_uri)
  end subroutine create_record_with_optional_reply

  subroutine create_record_with_embed(state, text, embed_uri, embed_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text, embed_uri, embed_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri

    call create_post_record(state, text, '', '', '', '', embed_uri, embed_cid, ok, message, created_uri)
  end subroutine create_record_with_embed

  subroutine create_post_record(state, text, parent_uri, parent_cid, &
      root_uri, root_cid, embed_uri, embed_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: text, parent_uri, parent_cid, root_uri, root_cid, embed_uri, embed_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri
    character(len=:), allocatable :: payload, body, now_utc, repo, reply_json, embed_json, facets_json

    ok = .false.
    message = 'Not sent'
    created_uri = ''
    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required before posting.'
      return
    end if

    repo = trim(state%did)
    if (len_trim(repo) == 0) repo = trim(state%identifier)
    now_utc = utc_timestamp_iso()

    reply_json = ''
    if (len_trim(parent_uri) > 0 .and. len_trim(parent_cid) > 0) then
      reply_json = ',"reply":{"root":{"uri":"' // escape_json_string(trim(root_uri)) // '","cid":"' // &
                   escape_json_string(trim(root_cid)) // '"},"parent":{"uri":"' // &
                   escape_json_string(trim(parent_uri)) // '","cid":"' // escape_json_string(trim(parent_cid)) // '"}}'
    end if

    embed_json = ''
    if (len_trim(embed_uri) > 0 .and. len_trim(embed_cid) > 0) then
      embed_json = ',"embed":{"$type":"app.bsky.embed.record","record":{"uri":"' // &
                   escape_json_string(trim(embed_uri)) // '","cid":"' // escape_json_string(trim(embed_cid)) // '"}}'
    end if

    facets_json = build_facets_json(trim(text))

    payload = '{' // &
              '"repo":"' // escape_json_string(repo) // '",' // &
              '"collection":"app.bsky.feed.post",' // &
              '"record":{' // &
              '"$type":"app.bsky.feed.post",' // &
              '"text":"' // escape_json_string(trim(text)) // '",' // &
              '"createdAt":"' // trim(now_utc) // '"' // trim(reply_json) // trim(embed_json) // trim(facets_json) // '}}'

    body = http_post_json(trim(state%pds_host) // '/xrpc/com.atproto.repo.createRecord', payload, trim(state%access_jwt))
    created_uri = extract_json_string(body, 'uri')
    if (len_trim(created_uri) > 0) then
      ok = .true.
      if (len_trim(embed_uri) > 0) then
        message = 'Quote post created'
      else if (len_trim(parent_uri) > 0) then
        message = 'Reply created'
      else
        message = 'Post created'
      end if
    else
      message = 'Post failed. Response did not contain a URI.'
    end if
  end subroutine create_post_record

  subroutine create_subject_action_record(state, collection, subject_uri, subject_cid, ok, message, created_uri)
    type(session_state), intent(in) :: state
    character(len=*), intent(in) :: collection, subject_uri, subject_cid
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    character(len=*), intent(out) :: created_uri
    character(len=:), allocatable :: payload, body, now_utc, repo

    ok = .false.
    message = 'Not sent'
    created_uri = ''
    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required before this action.'
      return
    end if
    if (len_trim(subject_uri) == 0 .or. len_trim(subject_cid) == 0) then
      message = 'Selected post is missing URI/CID.'
      return
    end if

    repo = trim(state%did)
    if (len_trim(repo) == 0) repo = trim(state%identifier)
    now_utc = utc_timestamp_iso()

    payload = '{' // &
              '"repo":"' // escape_json_string(repo) // '",' // &
              '"collection":"' // escape_json_string(trim(collection)) // '",' // &
              '"record":{' // &
              '"$type":"' // escape_json_string(trim(collection)) // '",' // &
              '"subject":{"uri":"' // escape_json_string(trim(subject_uri)) // '","cid":"' // &
                escape_json_string(trim(subject_cid)) // '"},' // &
              '"createdAt":"' // trim(now_utc) // '"}}'

    body = http_post_json(trim(state%pds_host) // '/xrpc/com.atproto.repo.createRecord', payload, trim(state%access_jwt))
    created_uri = extract_json_string(body, 'uri')
    if (len_trim(created_uri) > 0) then
      ok = .true.
      if (trim(collection) == 'app.bsky.feed.like') then
        message = 'Like created'
      else
        message = 'Repost created'
      end if
    else
      message = 'Action failed. Response did not contain a URI.'
    end if
  end subroutine create_subject_action_record

  function build_facets_json(text_in) result(out)
    character(len=*), intent(in) :: text_in
    character(len=:), allocatable :: out
    character(len=:), allocatable :: items, url
    integer :: pos, start_pos, end_pos, n, hit_http, hit_https

    items = ''
    pos = 1
    n = 0
    do
      hit_http = index(text_in(pos:), 'http://')
      hit_https = index(text_in(pos:), 'https://')
      if (hit_http == 0 .and. hit_https == 0) exit
      if (hit_http == 0) then
        start_pos = pos + hit_https - 1
      else if (hit_https == 0) then
        start_pos = pos + hit_http - 1
      else
        start_pos = pos + min(hit_http, hit_https) - 1
      end if
      end_pos = start_pos
      do while (end_pos <= len_trim(text_in))
        if (text_in(end_pos:end_pos) == ' ') exit
        end_pos = end_pos + 1
      end do
      url = trim(text_in(start_pos:end_pos-1))
      if (len_trim(url) > 0) then
        if (n > 0) items = items // ','
        items = items // '{"index":{"byteStart":' // trim(itoa(start_pos-1)) // ',"byteEnd":' // trim(itoa(end_pos-1)) // '},' // &
                '"features":[{"$type":"app.bsky.richtext.facet#link","uri":"' // escape_json_string(url) // '"}]}'
        n = n + 1
      end if
      pos = max(end_pos, start_pos + 1)
      if (pos > len_trim(text_in)) exit
    end do
    if (n > 0) then
      out = ',"facets":[' // items // ']'
    else
      out = ''
    end if
  end function build_facets_json

  function utc_timestamp_iso() result(out)
    character(len=:), allocatable :: out
    integer :: vals(8)
    character(len=32) :: tmp
    call date_and_time(values=vals)
    write(tmp,'(i4.4,"-",i2.2,"-",i2.2,"T",i2.2,":",i2.2,":",i2.2,"Z")') &
      vals(1), vals(2), vals(3), vals(5), vals(6), vals(7)
    out = trim(tmp)
  end function utc_timestamp_iso

  subroutine tail_live_stream(events, n, ok, message, limit, mode)
    type(stream_event), intent(out) :: events(MAX_ITEMS)
    integer, intent(out) :: n
    logical, intent(out) :: ok
    character(len=*), intent(out) :: message
    integer, intent(in), optional :: limit
    character(len=*), intent(in), optional :: mode
    integer :: count, code
    character(len=:), allocatable :: cmd, out_path, body, cursor_path, log_path, cursor, stream_mode

    count = 12
    if (present(limit)) count = max(1, min(limit, MAX_ITEMS))

    stream_mode = 'jetstream'
    if (present(mode)) then
      if (len_trim(mode) > 0) stream_mode = trim(mode)
    end if

    if (trim(stream_mode) == 'relay-raw') then
      out_path = state_file('relay_raw_tail.out')
      cursor_path = state_file('relay_raw.cursor')
      log_path = state_file('relay_raw.jsonl')
      cmd = 'python3 scripts/relay_raw_tail.py --limit ' // trim(itoa(count))
    else
      out_path = state_file('jetstream_tail.out')
      cursor_path = state_file('jetstream.cursor')
      log_path = state_file('jetstream.jsonl')
      cmd = 'python3 scripts/jetstream_tail.py --limit ' // trim(itoa(count))
    end if
    cursor = read_first_line(cursor_path)
    if (len_trim(cursor) > 0) cmd = cmd // ' --cursor ' // trim(cursor)
    call run_capture(cmd, out_path, code)
    body = slurp_file(out_path)

    if (code /= 0 .or. len_trim(body) == 0) then
      ok = .false.
      n = 0
      events = stream_event()
      message = 'Stream helper failed for mode ' // trim(stream_mode)
      return
    end if

    call decode_stream_blob(body, events, n)
    if (n > 0) then
      call append_line(log_path, trim(body))
      call write_text(cursor_path, trim(events(n)%time_us))
      ok = .true.
      message = 'Live stream updated (' // trim(stream_mode) // ')' 
    else
      ok = .false.
      message = 'No stream events decoded'
    end if
  end subroutine tail_live_stream
  subroutine resolve_did_to_handle(state, did, handle)
    ! Look up DID in local cache; on miss call getProfile and cache the result.
    ! Returns the handle on success, or the DID itself as fallback.
    type(app_state), intent(inout) :: state
    character(len=*), intent(in)   :: did
    character(len=*), intent(out)  :: handle
    type(actor_profile) :: profile
    logical :: ok
    character(len=256) :: msg
    integer :: i

    handle = ''

    ! Cache lookup
    do i = 1, state%did_cache_count
      if (trim(state%did_cache(i)) == trim(did)) then
        handle = trim(state%handle_cache(i))
        return
      end if
    end do

    ! Cache miss — fetch from API
    call fetch_profile_view(trim(did), profile, ok, msg)
    if (ok .and. len_trim(profile%handle) > 0) then
      handle = trim(profile%handle)
    else
      handle = trim(did)   ! fallback: show DID if resolution fails
    end if

    ! Store in cache (evict oldest entry when full)
    if (state%did_cache_count < DID_CACHE_SIZE) then
      state%did_cache_count = state%did_cache_count + 1
      i = state%did_cache_count
    else
      ! Shift entries down by one, dropping the oldest
      do i = 1, DID_CACHE_SIZE - 1
        state%did_cache(i)   = state%did_cache(i+1)
        state%handle_cache(i) = state%handle_cache(i+1)
      end do
      i = DID_CACHE_SIZE
    end if
    state%did_cache(i)   = trim(did)
    state%handle_cache(i) = trim(handle)
  end subroutine resolve_did_to_handle

  ! ----------------------------------------------------------------
  ! upload_blob — read a PNG file from disk and POST to uploadBlob
  ! Returns the blob JSON fragment for embedding in a post record.
  ! blob_json will be empty on failure.
  ! ----------------------------------------------------------------
  subroutine upload_blob(state, png_path, blob_json, ok, message)
    use iso_c_binding, only: c_int8_t
    use http_cbridge_mod, only: http_post_binary
    type(session_state), intent(in)   :: state
    character(len=*),    intent(in)   :: png_path
    character(len=:), allocatable, intent(out) :: blob_json
    logical,             intent(out)  :: ok
    character(len=*),    intent(out)  :: message

    integer(c_int8_t), allocatable :: file_bytes(:)
    integer :: file_unit, file_size, ios
    character(len=:), allocatable :: url, auth_header, resp
    character(len=1024) :: auth_buf

    ok        = .false.
    blob_json = ''
    message   = 'upload_blob failed'

    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required before uploading images.'
      return
    end if

    ! Read PNG file into byte array
    open(newunit=file_unit, file=trim(png_path), status='old', &
         action='read', form='unformatted', access='stream', iostat=ios)
    if (ios /= 0) then
      message = 'Cannot open PNG: ' // trim(png_path)
      return
    end if
    inquire(unit=file_unit, size=file_size)
    if (file_size <= 0) then
      close(file_unit)
      message = 'PNG file is empty: ' // trim(png_path)
      return
    end if
    allocate(file_bytes(file_size))
    read(file_unit, iostat=ios) file_bytes
    close(file_unit)
    if (ios /= 0) then
      message = 'Cannot read PNG data'
      return
    end if

    url = trim(state%pds_host) // '/xrpc/com.atproto.repo.uploadBlob'

    resp = http_post_binary(url, file_bytes, file_size, 'image/png', &
                            auth_token=trim(state%access_jwt))

    blob_json = extract_json_string(resp, 'blob')
    ! extract_json_string returns the string value — for blob we need the
    ! full blob object. Extract it as a raw sub-object instead.
    blob_json = extract_json_object(resp, 'blob')
    if (len_trim(blob_json) == 0) then
      message = 'uploadBlob response missing blob field. Response: ' // resp(1:min(len(resp),120))
      return
    end if

    ok      = .true.
    message = 'Blob uploaded'
  end subroutine upload_blob

  ! ----------------------------------------------------------------
  ! create_image_post — post text + dithered PNG image to Bluesky
  ! Calls upload_blob first, then createRecord with embed.
  ! ----------------------------------------------------------------
  subroutine create_image_post(state, text, png_path, width, height, ok, message, created_uri)
    type(session_state), intent(in)  :: state
    character(len=*),    intent(in)  :: text, png_path
    integer,             intent(in)  :: width, height
    logical,             intent(out) :: ok
    character(len=*),    intent(out) :: message, created_uri

    character(len=:), allocatable :: blob_json, payload, body, now_utc, repo

    ok          = .false.
    message     = 'Image post failed'
    created_uri = ''

    ! Step 1: upload blob
    call upload_blob(state, png_path, blob_json, ok, message)
    if (.not. ok) return

    ok = .false.

    ! Step 2: createRecord with app.bsky.embed.images
    repo    = trim(state%did)
    if (len_trim(repo) == 0) repo = trim(state%identifier)
    now_utc = utc_timestamp_iso()

    payload = '{' // &
      '"repo":"'       // escape_json_string(repo)         // '",' // &
      '"collection":"app.bsky.feed.post",'                          // &
      '"record":{'                                                   // &
        '"$type":"app.bsky.feed.post",'                            // &
        '"text":"'     // escape_json_string(trim(text))   // '",' // &
        '"createdAt":"' // trim(now_utc)                   // '",' // &
        '"embed":{'                                                  // &
          '"$type":"app.bsky.embed.images",'                       // &
          '"images":[{'                                             // &
            '"image":'  // trim(blob_json)                // ','   // &
            '"alt":"Floyd-Steinberg dithered image — rendered in Fortran",' // &
            '"aspectRatio":{"width":' // trim(itoa(width))         // &
                          ',"height":' // trim(itoa(height))       // '}' // &
          '}]'                                                      // &
        '}'                                                        // &
      '}}'

    body = http_post_json(trim(state%pds_host) // '/xrpc/com.atproto.repo.createRecord', &
                          payload, trim(state%access_jwt))

    created_uri = extract_json_string(body, 'uri')
    if (len_trim(created_uri) > 0) then
      ok      = .true.
      message = 'Image post created'
    else
      message = 'createRecord failed. Response: ' // body(1:min(len(body),120))
    end if
  end subroutine create_image_post

  ! ----------------------------------------------------------------
  ! extract_json_object — extract a raw JSON object value by key
  ! e.g. extract_json_object('{"blob":{...}}', 'blob') -> '{...}'
  ! ----------------------------------------------------------------
  function extract_json_object(json, key) result(val)
    character(len=*), intent(in) :: json, key
    character(len=:), allocatable :: val
    integer :: kpos, brace_start, brace_end, depth, i

    val = ''
    kpos = index(json, '"' // trim(key) // '"')
    if (kpos == 0) return

    ! Find the opening brace after the key
    brace_start = index(json(kpos:), '{')
    if (brace_start == 0) return
    brace_start = kpos + brace_start - 1

    ! Find matching closing brace
    depth = 0
    brace_end = 0
    do i = brace_start, len(json)
      if (json(i:i) == '{') depth = depth + 1
      if (json(i:i) == '}') then
        depth = depth - 1
        if (depth == 0) then
          brace_end = i
          exit
        end if
      end if
    end do

    if (brace_end > brace_start) val = json(brace_start:brace_end)
  end function extract_json_object

  ! ----------------------------------------------------------------
  ! list_convos — fetch conversation list via chat.bsky.convo.listConvos
  ! ----------------------------------------------------------------
  subroutine list_convos(state, convos, n, ok, message)
    use models_mod, only: convo_view, CHAT_PROXY
    type(session_state), intent(in)  :: state
    type(convo_view),    intent(out) :: convos(64)
    integer,             intent(out) :: n
    logical,             intent(out) :: ok
    character(len=*),    intent(out) :: message

    character(len=:), allocatable :: body, url, convo_arr, item
    integer :: i, pos, next_pos

    ok = .false.; n = 0; message = 'listConvos failed'

    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required.'; return
    end if

    url  = trim(state%pds_host) // '/xrpc/chat.bsky.convo.listConvos?limit=20'
    body = http_get_proxied(url, CHAT_PROXY, auth_token=trim(state%access_jwt))

    if (len_trim(body) == 0) then
      message = 'Empty response from listConvos'; return
    end if

    ! Parse convos array — simple scan for convo objects
    convo_arr = extract_json_string(body, 'convos')
    if (len_trim(convo_arr) == 0) then
      ok = .true.; message = 'No conversations'; return
    end if

    ! Walk through convo objects
    pos = 1
    i   = 0
    do while (pos <= len(body) .and. i < 64)
      next_pos = index(body(pos:), '"id"')
      if (next_pos == 0) exit
      pos = pos + next_pos - 1
      i = i + 1
      convos(i)%id           = extract_json_string(body(pos:pos+500), 'id')
      convos(i)%unread_count = 0
      pos = pos + 4
    end do

    n  = i
    ok = .true.
    message = 'OK'
  end subroutine list_convos

  ! ----------------------------------------------------------------
  ! get_convo_for_member — get or create a DM convo with a given DID
  ! Returns the convo_id to use for get_messages / send_dm
  ! ----------------------------------------------------------------
  subroutine get_convo_for_member(state, member_did, convo_id, ok, message)
    use models_mod, only: CHAT_PROXY
    type(session_state), intent(in)  :: state
    character(len=*),    intent(in)  :: member_did
    character(len=*),    intent(out) :: convo_id
    logical,             intent(out) :: ok
    character(len=*),    intent(out) :: message

    character(len=:), allocatable :: body, url

    ok = .false.; convo_id = ''; message = 'getConvoForMembers failed'

    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required.'; return
    end if

    url  = trim(state%pds_host) // '/xrpc/chat.bsky.convo.getConvoForMembers?members=' // &
           escape_json_string(trim(member_did))
    body = http_get_proxied(url, CHAT_PROXY, auth_token=trim(state%access_jwt))

    ! Response is {"convo":{"id":"..."}}, extract from inside convo object
    convo_id = extract_json_string(extract_json_object(body, 'convo'), 'id')
    if (len_trim(convo_id) > 0) then
      ok = .true.; message = 'OK'
    else
      message = 'Could not get convo ID. Response: ' // body(1:min(len(body),120))
    end if
  end subroutine get_convo_for_member

  ! ----------------------------------------------------------------
  ! get_messages — fetch messages for a conversation
  ! ----------------------------------------------------------------
  subroutine get_messages(state, convo_id, msgs, n, ok, message)
    use models_mod, only: dm_message, CHAT_PROXY
    type(session_state), intent(in)  :: state
    character(len=*),    intent(in)  :: convo_id
    type(dm_message),    intent(out) :: msgs(64)
    integer,             intent(out) :: n
    logical,             intent(out) :: ok
    character(len=*),    intent(out) :: message

    character(len=:), allocatable :: body, url
    integer :: i, pos, next_pos

    ok = .false.; n = 0; message = 'getMessages failed'

    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required.'; return
    end if

    url  = trim(state%pds_host) // '/xrpc/chat.bsky.convo.getMessages?convoId=' // &
           trim(convo_id) // '&limit=20'
    body = http_get_proxied(url, CHAT_PROXY, auth_token=trim(state%access_jwt))

    if (len_trim(body) == 0) then
      message = 'Empty response from getMessages'; return
    end if

    ! Walk the messages array object by object using brace-depth tracking.
    ! This isolates each message cleanly regardless of field order or length.
    block
      integer :: arr_pos, depth, obj_start, j
      character(len=:), allocatable :: obj

      ! Find start of messages array
      arr_pos = index(body, '"messages"')
      if (arr_pos > 0) arr_pos = index(body(arr_pos:), '[') + arr_pos - 1

      depth = 0; obj_start = 0; i = 0
      do j = arr_pos, len(body)
        if (body(j:j) == '{') then
          if (depth == 0) obj_start = j
          depth = depth + 1
        else if (body(j:j) == '}') then
          depth = depth - 1
          if (depth == 0 .and. obj_start > 0 .and. i < 64) then
            obj = body(obj_start:j)
            i = i + 1
            msgs(i)%id         = extract_json_string(obj, 'id')
            msgs(i)%text       = extract_json_string(obj, 'text')
            msgs(i)%sent_at    = extract_json_string(obj, 'sentAt')
            msgs(i)%sender_did = extract_json_string( &
              extract_json_object(obj, 'sender'), 'did')
            obj_start = 0
          end if
        else if (body(j:j) == ']' .and. depth == 0) then
          exit
        end if
      end do
    end block

    n  = i
    ok = .true.
    message = 'OK'
  end subroutine get_messages

  ! ----------------------------------------------------------------
  ! send_dm — send a message to a conversation
  ! ----------------------------------------------------------------
  subroutine send_dm(state, convo_id, text, ok, message)
    use models_mod, only: CHAT_PROXY
    type(session_state), intent(in)  :: state
    character(len=*),    intent(in)  :: convo_id, text
    logical,             intent(out) :: ok
    character(len=*),    intent(out) :: message

    character(len=:), allocatable :: body, url, payload, msg_id

    ok = .false.; message = 'sendMessage failed'

    if (len_trim(state%access_jwt) == 0) then
      message = 'Login required.'; return
    end if

    url     = trim(state%pds_host) // '/xrpc/chat.bsky.convo.sendMessage'
    payload = '{' // &
      '"convoId":"' // escape_json_string(trim(convo_id)) // '",' // &
      '"message":{"$type":"chat.bsky.convo.defs#messageInput",' // &
                 '"text":"' // escape_json_string(trim(text)) // '"}}' 

    body   = http_post_json_proxied(url, payload, CHAT_PROXY, &
                                    auth_token=trim(state%access_jwt))
    msg_id = extract_json_string(body, 'id')

    if (len_trim(msg_id) > 0) then
      ok = .true.; message = 'Message sent'
    else
      message = 'sendMessage failed. Response: ' // body(1:min(len(body),120))
    end if
  end subroutine send_dm

  ! ----------------------------------------------------------------
  ! fetch_image_blob — download an image URL to a local file
  ! ----------------------------------------------------------------
  subroutine fetch_image_blob(image_url, out_path, ok, message)
    character(len=*), intent(in)  :: image_url, out_path
    logical,          intent(out) :: ok
    character(len=*), intent(out) :: message

    ok = http_get_to_file(trim(image_url), trim(out_path))
    if (ok) then
      message = 'Image downloaded'
    else
      message = 'Could not fetch image (HTTP ' // trim(itoa(last_http_status)) // ')'
    end if
  end subroutine fetch_image_blob

end module client_mod
