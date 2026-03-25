module tui_mod
  use client_mod, only: login_session, fetch_author_feed, search_posts, fetch_timeline, tail_live_stream, &
                         fetch_post_thread, create_post, create_reply, create_quote_post, like_post, repost_post, &
                         fetch_profile_view, fetch_notifications_view, load_saved_session, clear_saved_session, &
                         resolve_did_to_handle, create_image_post, &
                         list_convos, get_messages, send_dm, get_convo_for_member
  use dither_mod, only: run_dither
  use models_mod, only: post_view, stream_event, actor_profile, notification_view, convo_view, dm_message, MAX_ITEMS
  use config_mod, only: load_session_from_env
  use app_state_mod, only: app_state, VIEW_HOME, VIEW_POST_LIST, VIEW_PROFILE, VIEW_NOTIFICATIONS, VIEW_STREAM, &
                           VIEW_CONVO_LIST, VIEW_MESSAGES, reset_selection, set_status
  use post_store_mod, only: upsert_posts, get_current_post
  implicit none
contains
  subroutine clear_screen()
    write(*,'(a)', advance='no') achar(27)//'[2J'//achar(27)//'[H'
  end subroutine clear_screen

  subroutine wrap_print(prefix, text, width)
    character(len=*), intent(in) :: prefix, text
    integer, intent(in) :: width
    integer :: start, stop, last_space, maxw, n
    character(len=:), allocatable :: line

    maxw = max(20, width - len_trim(prefix))
    if (len_trim(text) == 0) then
      write(*,'(a)') trim(prefix)
      return
    end if
    start = 1
    n = len_trim(text)
    do while (start <= n)
      stop = min(n, start + maxw - 1)
      if (stop < n) then
        last_space = scan(text(start:stop), ' ', back=.true.)
        if (last_space > 0 .and. stop < n) stop = start + last_space - 2
      end if
      if (stop < start) stop = min(n, start + maxw - 1)
      line = text(start:stop)
      if (start == 1) then
        write(*,'(a)') trim(prefix) // trim(line)
      else
        write(*,'(a)') repeat(' ', len_trim(prefix)) // trim(line)
      end if
      start = stop + 1
      do while (start <= n .and. text(start:start) == ' ')
        start = start + 1
      end do
    end do
  end subroutine wrap_print

  subroutine prompt_line(prompt, text)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: text
    write(*,'(a)', advance='no') trim(prompt)
    read(*,'(a)') text
  end subroutine prompt_line

  subroutine draw_header(state)
    type(app_state), intent(in) :: state
    write(*,'(a)') 'Fortransky v1.4 - TUI only'
    write(*,'(a)') repeat('=', 28)
    write(*,'(a)') 'View   : ' // trim(state%view_title)
    if (len_trim(state%session%identifier) > 0) write(*,'(a)') 'User   : ' // trim(state%session%identifier)
    if (len_trim(state%session%did) > 0) write(*,'(a)') 'DID    : ' // trim(state%session%did)
    if (len_trim(state%session%access_jwt) > 0) then
      write(*,'(a)') 'Auth   : logged in'
    else
      write(*,'(a)') 'Auth   : anonymous'
    end if
    write(*,'(a)') 'Stream : ' // trim(state%stream_mode)
    write(*,'(a)') 'Status : ' // trim(state%status)
    write(*,'(a)') ''
  end subroutine draw_header

  subroutine draw_home(state)
    type(app_state), intent(in) :: state
    call clear_screen()
    call draw_header(state)
    write(*,'(a)') 'Commands:'
    write(*,'(a)') '  a <handle>   author feed'
    write(*,'(a)') '  s <query>    search posts'
    write(*,'(a)') '  p <handle>   profile view'
    write(*,'(a)') '  l            login + timeline'
    write(*,'(a)') '  x            logout + clear saved session'
    write(*,'(a)') '  n            notifications'
    write(*,'(a)') '  c            compose post'
    write(*,'(a)') '  d <image>    dither + post image'
    write(*,'(a)') '  i            DM inbox'
    write(*,'(a)') '  dm <handle>  new DM'
    write(*,'(a)') '  t <uri/url>  open thread'
    write(*,'(a)') '  j            stream tail'
    write(*,'(a)') '  m            toggle stream mode (jetstream/relay-raw)'
    write(*,'(a)') '  q            quit'
  end subroutine draw_home

  subroutine draw_post_list(state)
    type(app_state), intent(in) :: state
    integer :: i, start_idx, end_idx, pages
    type(post_view) :: post
    logical :: ok

    call clear_screen()
    call draw_header(state)
    if (state%current_post_count == 0) then
      write(*,'(a)') 'No posts loaded.'
      write(*,'(a)') ''
      write(*,'(a)') 'Commands: b back'
      return
    end if
    pages = max(1, (state%current_post_count + state%page_size - 1) / state%page_size)
    start_idx = (state%page - 1) * state%page_size + 1
    end_idx = min(state%current_post_count, start_idx + state%page_size - 1)
    write(*,'(a,i0,a,i0,a,i0)') 'Page ', state%page, '/', pages, '  Selected ', state%selected
    write(*,'(a)') ''
    do i = start_idx, end_idx
      call get_current_post(state, i, post, ok)
      if (.not. ok) cycle
      if (i == state%selected) then
        write(*,'(a,i0,a)') '>', i, ' <'
      else
        write(*,'(a,i0)') ' ', i
      end if
      call wrap_print('Author: ', trim(post%author), 96)
      if (len_trim(post%handle) > 0) call wrap_print('Handle: ', trim(post%handle), 96)
      if (len_trim(post%indexed_at) > 0) call wrap_print('When  : ', trim(post%indexed_at), 96)
      call wrap_print('Text  : ', trim(post%text), 96)
      call wrap_print('Meta  : ', post_meta_line(post), 96)
      if (len_trim(post%uri) > 0) call wrap_print('URI   : ', trim(post%uri), 96)
      write(*,'(a)') repeat('-', 72)
    end do
    write(*,'(a)') 'Commands: j/k move, n/p page, o open thread, r reply, P profile, b back, / search'
  end subroutine draw_post_list

  subroutine draw_profile(state)
    type(app_state), intent(in) :: state
    call clear_screen()
    call draw_header(state)
    call wrap_print('Name  : ', trim(state%profile%display_name), 96)
    call wrap_print('Handle: ', trim(state%profile%handle), 96)
    call wrap_print('DID   : ', trim(state%profile%did), 96)
    if (len_trim(state%profile%indexed_at) > 0) call wrap_print('Seen  : ', trim(state%profile%indexed_at), 96)
    if (len_trim(state%profile%posts_count) > 0) call wrap_print('Posts : ', trim(state%profile%posts_count), 96)
    if (len_trim(state%profile%followers_count) > 0) call wrap_print('Followers: ', trim(state%profile%followers_count), 96)
    if (len_trim(state%profile%follows_count) > 0) call wrap_print('Follows  : ', trim(state%profile%follows_count), 96)
    if (len_trim(state%profile%description) > 0) call wrap_print('Bio   : ', trim(state%profile%description), 96)
    write(*,'(a)') ''
    write(*,'(a)') 'Commands: b back, a load author feed'
  end subroutine draw_profile

  subroutine draw_notifications(state)
    type(app_state), intent(in) :: state
    integer :: i, start_idx, end_idx, pages

    call clear_screen()
    call draw_header(state)
    if (state%notification_count == 0) then
      write(*,'(a)') 'No notifications loaded.'
      write(*,'(a)') 'Commands: b back'
      return
    end if
    pages = max(1, (state%notification_count + state%page_size - 1) / state%page_size)
    start_idx = (state%page - 1) * state%page_size + 1
    end_idx = min(state%notification_count, start_idx + state%page_size - 1)
    write(*,'(a,i0,a,i0,a,i0)') 'Page ', state%page, '/', pages, '  Selected ', state%selected
    write(*,'(a)') ''
    do i = start_idx, end_idx
      if (i == state%selected) then
        write(*,'(a,i0,a)') '>', i, ' <'
      else
        write(*,'(a,i0)') ' ', i
      end if
      call wrap_print('Reason: ', trim(state%notifications(i)%reason), 96)
      call wrap_print('Actor : ', trim(state%notifications(i)%author), 96)
      if (len_trim(state%notifications(i)%handle) > 0) call wrap_print('Handle: ', trim(state%notifications(i)%handle), 96)
      if (len_trim(state%notifications(i)%indexed_at) > 0) call wrap_print('When  : ', trim(state%notifications(i)%indexed_at), 96)
      if (len_trim(state%notifications(i)%text) > 0) call wrap_print('Text  : ', trim(state%notifications(i)%text), 96)
      if (len_trim(state%notifications(i)%uri) > 0) call wrap_print('URI   : ', trim(state%notifications(i)%uri), 96)
      write(*,'(a)') repeat('-', 72)
    end do
    write(*,'(a)') 'Commands: j/k move, n/p page, o open thread, r reply, l like, R repost, q quote, b back'
  end subroutine draw_notifications

  subroutine draw_stream(events, n, message)
    type(stream_event), intent(in) :: events(MAX_ITEMS)
    integer, intent(in) :: n
    character(len=*), intent(in) :: message
    integer :: i
    call clear_screen()
    write(*,'(a)') 'Fortransky v1.4 - stream tail'
    write(*,'(a)') repeat('=', 28)
    write(*,'(a)') trim(message)
    write(*,'(a)') ''
    if (n == 0) then
      write(*,'(a)') 'No events decoded.'
    else
      do i = 1, n
        write(*,'(a,i0)') 'Event ', i
        call wrap_print('Kind  : ', trim(events(i)%kind), 96)
        if (len_trim(events(i)%handle) > 0) call wrap_print('Handle: ', trim(events(i)%handle), 96)
        if (len_trim(events(i)%did) > 0) call wrap_print('DID   : ', trim(events(i)%did), 96)
        if (len_trim(events(i)%time_us) > 0) call wrap_print('Cursor: ', trim(events(i)%time_us), 96)
        if (len_trim(events(i)%text) > 0) call wrap_print('Text  : ', trim(events(i)%text), 96)
        write(*,'(a)') repeat('-', 72)
      end do
    end if
    write(*,'(a)') 'Commands: b back, j refresh'
  end subroutine draw_stream

  function post_meta_line(post) result(out)
    type(post_view), intent(in) :: post
    character(len=:), allocatable :: out

    out = 'type=' // trim(post%record_type)
    if (len_trim(post%reason) > 0) out = out // ' reason=' // trim(post%reason)
    if (post%is_quote) out = out // ' quote'
    if (post%has_images) out = out // ' images'
    if (post%has_video) out = out // ' video'
    if (post%has_external) out = out // ' link'
    if (post%has_facets) out = out // ' facets'
    if (len_trim(post%reply_count) > 0) out = out // ' replies=' // trim(post%reply_count)
    if (len_trim(post%repost_count) > 0) out = out // ' reposts=' // trim(post%repost_count)
    if (len_trim(post%like_count) > 0) out = out // ' likes=' // trim(post%like_count)
    if (len_trim(post%quote_count) > 0) out = out // ' quotes=' // trim(post%quote_count)
  end function post_meta_line

  subroutine login_flow(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: posts(MAX_ITEMS)
    character(len=256) :: input, password, message
    integer :: n
    logical :: ok

    if (len_trim(state%session%identifier) == 0) then
      call prompt_line('Identifier: ', state%session%identifier)
    else
      call prompt_line('Identifier [' // trim(state%session%identifier) // ']: ', input)
      if (len_trim(input) > 0) state%session%identifier = trim(input)
    end if
    call prompt_line('Password/app password: ', password)
    call login_session(state%session, trim(password), ok, message)
    if (.not. ok) then
      call set_status(state, trim(message))
      return
    end if
    call fetch_timeline(state%session, posts, n, ok)
    if (ok) then
      call upsert_posts(state, posts, n)
      state%prev_view = state%view
      state%view = VIEW_POST_LIST
      state%view_title = 'Home timeline'
      call reset_selection(state)
      call set_status(state, 'Login OK. Timeline loaded.')
    else
      call set_status(state, 'Login OK, but timeline fetch failed.')
    end if
  end subroutine login_flow

  subroutine load_author_feed(state, handle)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: handle
    type(post_view) :: posts(MAX_ITEMS)
    integer :: n
    call fetch_author_feed(trim(handle), posts, n)
    call upsert_posts(state, posts, n)
    state%prev_view = state%view
    state%view = VIEW_POST_LIST
    state%view_title = 'Author feed: ' // trim(handle)
    call reset_selection(state)
    call set_status(state, 'Loaded author feed.')
  end subroutine load_author_feed

  subroutine load_search(state, query)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: query
    type(post_view) :: posts(MAX_ITEMS)
    integer :: n
    call search_posts(trim(query), posts, n)
    call upsert_posts(state, posts, n)
    state%prev_view = state%view
    state%view = VIEW_POST_LIST
    state%view_title = 'Search: ' // trim(query)
    call reset_selection(state)
    call set_status(state, 'Search loaded.')
  end subroutine load_search

  subroutine load_profile(state, handle)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: handle
    logical :: ok
    character(len=256) :: message

    call fetch_profile_view(trim(handle), state%profile, ok, message)
    if (ok) then
      state%prev_view = state%view
      state%view = VIEW_PROFILE
      state%view_title = 'Profile: ' // trim(handle)
      call set_status(state, 'Profile loaded.')
    else
      call set_status(state, trim(message))
    end if
  end subroutine load_profile

  subroutine load_notifications(state)
    type(app_state), intent(inout) :: state
    logical :: ok
    character(len=256) :: message
    integer :: n

    call fetch_notifications_view(state%session, state%notifications, n, ok, message)
    if (ok) then
      state%notification_count = n
      state%prev_view = state%view
      state%view = VIEW_NOTIFICATIONS
      state%view_title = 'Notifications'
      call reset_selection(state)
      call set_status(state, 'Notifications loaded.')
    else
      call set_status(state, trim(message))
    end if
  end subroutine load_notifications

  subroutine load_thread(state, ref)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: ref
    type(post_view) :: posts(MAX_ITEMS)
    integer :: n
    logical :: ok
    character(len=256) :: message

    call fetch_post_thread(trim(ref), posts, n, ok, message)
    if (ok) then
      call upsert_posts(state, posts, n)
      state%prev_view = state%view
      state%view = VIEW_POST_LIST
      state%view_title = 'Thread view'
      call reset_selection(state)
      call set_status(state, 'Thread loaded.')
    else
      call set_status(state, trim(message))
    end if
  end subroutine load_thread

  subroutine compose_flow(state)
    type(app_state), intent(inout) :: state
    character(len=2000) :: text
    character(len=256) :: message, created_uri
    logical :: ok

    call prompt_line('Compose text: ', text)
    if (len_trim(text) == 0) then
      call set_status(state, 'Empty post discarded.')
      return
    end if
    call create_post(state%session, trim(text), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Post created: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine compose_flow

  subroutine dither_flow(state, image_path)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in)   :: image_path

    character(len=2000) :: post_text
    character(len=256)  :: message, created_uri
    character(len=512)  :: cmd
    logical :: ok
    integer :: ios

    ! Step 1 — prep: convert image to flat pixel file via dither_prep.py
    call set_status(state, 'Dithering: preparing image...')
    cmd = 'python3 scripts/dither_prep.py ' // trim(image_path) // &
          ' --width 576 --height 720 2>/dev/null'
    call execute_command_line(trim(cmd), wait=.true., exitstat=ios)
    if (ios /= 0) then
      call set_status(state, 'dither_prep.py failed. Is Pillow installed?')
      return
    end if

    ! Step 2 — dither: run Floyd-Steinberg in Fortran
    call set_status(state, 'Dithering: running Floyd-Steinberg...')
    call run_dither(ok, message)
    if (.not. ok) then
      call set_status(state, 'Dither failed: ' // trim(message))
      return
    end if

    ! Step 3 — convert pixels to PNG via pixels_to_png.py
    call set_status(state, 'Dithering: converting to PNG...')
    call execute_command_line('python3 scripts/pixels_to_png.py 2>/dev/null', &
                              wait=.true., exitstat=ios)
    if (ios /= 0) then
      call set_status(state, 'PNG conversion failed. Is Pillow installed?')
      return
    end if

    ! Step 4 — prompt for post text
    call prompt_line('Post text (blank for default): ', post_text)
    if (len_trim(post_text) == 0) then
      post_text = 'Dithered with Bill Atkinson''s Floyd-Steinberg algorithm. ' // &
                  'Rendered in Fortran. #fortransky #formerlab'
    end if

    ! Step 5 — upload blob and post
    call set_status(state, 'Uploading image...')
    call create_image_post(state%session, trim(post_text), &
                           '/tmp/bsky_dither_preview.png', &
                           576, 720, ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Image post created: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine dither_flow

  ! ----------------------------------------------------------------
  ! load_inbox — list DM conversations
  ! ----------------------------------------------------------------
  subroutine load_inbox(state)
    type(app_state), intent(inout) :: state
    type(convo_view) :: convos(64)
    integer :: n, i
    logical :: ok
    character(len=256) :: message, line

    call set_status(state, 'Loading DM inbox...')
    call list_convos(state%session, convos, n, ok, message)

    call clear_screen()
    call draw_header(state)
    write(*,'(a)') 'DM Inbox'
    write(*,'(a)') repeat('=', 40)

    if (.not. ok .or. n == 0) then
      write(*,'(a)') 'No conversations. Use: dm <handle>'
    else
      do i = 1, n
        write(*,'(i3,a,a)') i, '  ', trim(convos(i)%id)
      end do
    end if

    write(*,*)
    write(*,'(a)') 'Commands: dm <handle> new conversation, b back'
    write(*,'(a)', advance='no') '> '
    read(*,'(a)') line
    line = adjustl(trim(line))

    if (trim(line) == 'b') return

    ! If they type a number, open that conversation
    if (len_trim(line) > 0 .and. line(1:1) >= '1' .and. line(1:1) <= '9') then
      read(line, *, iostat=i) i
      if (i >= 1 .and. i <= n) then
        call view_convo(state, convos(i)%id)
      end if
    end if
  end subroutine load_inbox

  ! ----------------------------------------------------------------
  ! start_dm — open or create a DM with a handle
  ! ----------------------------------------------------------------
  subroutine start_dm(state, handle)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in)   :: handle

    character(len=256) :: convo_id, message
    type(actor_profile) :: profile
    logical :: ok

    ! Resolve handle to DID via getProfile
    call set_status(state, 'Resolving ' // trim(handle) // '...')
    call fetch_profile_view(trim(handle), profile, ok, message)

    if (.not. ok .or. len_trim(profile%did) == 0) then
      call set_status(state, 'Could not resolve handle: ' // trim(handle))
      return
    end if

    call set_status(state, 'Opening DM with ' // trim(handle) // '...')
    call get_convo_for_member(state%session, trim(profile%did), convo_id, ok, message)

    if (.not. ok) then
      call set_status(state, trim(message))
      return
    end if

    call view_convo(state, convo_id)
  end subroutine start_dm

  ! ----------------------------------------------------------------
  ! view_convo — show messages in a conversation and allow replies
  ! ----------------------------------------------------------------
  subroutine view_convo(state, convo_id)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in)   :: convo_id

    type(dm_message) :: msgs(64)
    integer :: n, i, ios
    logical :: ok
    character(len=256) :: message
    character(len=2000) :: line

    call set_status(state, 'Loading messages...')
    call get_messages(state%session, trim(convo_id), msgs, n, ok, message)

    do
      call clear_screen()
      call draw_header(state)
      write(*,'(a)') 'DM Thread  [convo: ' // trim(convo_id(1:min(16,len_trim(convo_id)))) // '...]'
      write(*,'(a)') repeat('-', 60)

      if (.not. ok .or. n == 0) then
        write(*,'(a)') '(no messages yet)'
      else
        do i = n, 1, -1   ! newest last (API returns newest first, we reverse)
          ! Show sender: me or their DID truncated
          if (trim(msgs(i)%sender_did) == trim(state%session%did)) then
            write(*,'(a,a,a)') '[', trim(msgs(i)%sent_at(1:min(16,len_trim(msgs(i)%sent_at)))), '] you'
          else
            write(*,'(a,a,a,a)') '[', trim(msgs(i)%sent_at(1:min(16,len_trim(msgs(i)%sent_at)))), '] ', &
              trim(msgs(i)%sender_did(1:min(20,len_trim(msgs(i)%sender_did))))
          end if
          write(*,'(a)') '  ' // trim(msgs(i)%text)
          write(*,*)
        end do
      end if

      write(*,'(a)') repeat('-', 60)
      write(*,'(a)') 'Commands: r reply, j refresh, b back'
      write(*,'(a)', advance='no') '> '
      read(*,'(a)') line
      line = adjustl(trim(line))

      if (trim(line) == 'b') exit

      if (trim(line) == 'j') then
        call get_messages(state%session, trim(convo_id), msgs, n, ok, message)
        cycle
      end if

      if (trim(line) == 'r') then
        write(*,'(a)', advance='no') 'Message: '
        read(*,'(a)') line
        if (len_trim(line) > 0) then
          call send_dm(state%session, trim(convo_id), trim(line), ok, message)
          if (ok) then
            call get_messages(state%session, trim(convo_id), msgs, n, ok, message)
            call set_status(state, 'Message sent.')
          else
            call set_status(state, trim(message))
          end if
        end if
        cycle
      end if
    end do
  end subroutine view_convo

  subroutine reply_to_selected_post(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: target
    logical :: ok
    character(len=2000) :: text
    character(len=256) :: message, created_uri
    character(len=512) :: root_uri, root_cid

    call get_current_post(state, state%selected, target, ok)
    if (.not. ok) then
      call set_status(state, 'No selected post.')
      return
    end if
    if (len_trim(target%uri) == 0 .or. len_trim(target%cid) == 0) then
      call set_status(state, 'Selected post is missing reply metadata.')
      return
    end if
    call prompt_line('Reply text: ', text)
    if (len_trim(text) == 0) then
      call set_status(state, 'Empty reply discarded.')
      return
    end if
    if (len_trim(target%root_uri) > 0 .and. len_trim(target%root_cid) > 0) then
      root_uri = trim(target%root_uri)
      root_cid = trim(target%root_cid)
    else
      root_uri = trim(target%uri)
      root_cid = trim(target%cid)
    end if
    call create_reply(state%session, trim(text), trim(target%uri), trim(target%cid), trim(root_uri), trim(root_cid), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Reply created: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine reply_to_selected_post

  subroutine reply_to_selected_notification(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: temp

    if (state%selected < 1 .or. state%selected > state%notification_count) then
      call set_status(state, 'No selected notification.')
      return
    end if
    temp = post_view(state%notifications(state%selected)%author, state%notifications(state%selected)%handle, &
                     state%notifications(state%selected)%text, state%notifications(state%selected)%uri, &
                     state%notifications(state%selected)%cid, state%notifications(state%selected)%indexed_at, &
                     state%notifications(state%selected)%parent_uri, state%notifications(state%selected)%parent_cid, &
                     state%notifications(state%selected)%root_uri, state%notifications(state%selected)%root_cid)
    call reply_to_post_object(state, temp)
  end subroutine reply_to_selected_notification

  subroutine reply_to_post_object(state, target)
    type(app_state), intent(inout) :: state
    type(post_view), intent(in) :: target
    logical :: ok
    character(len=2000) :: text
    character(len=256) :: message, created_uri
    character(len=512) :: root_uri, root_cid

    if (len_trim(target%uri) == 0 .or. len_trim(target%cid) == 0) then
      call set_status(state, 'Selected item is missing reply metadata.')
      return
    end if
    call prompt_line('Reply text: ', text)
    if (len_trim(text) == 0) then
      call set_status(state, 'Empty reply discarded.')
      return
    end if
    if (len_trim(target%root_uri) > 0 .and. len_trim(target%root_cid) > 0) then
      root_uri = trim(target%root_uri)
      root_cid = trim(target%root_cid)
    else
      root_uri = trim(target%uri)
      root_cid = trim(target%cid)
    end if
    call create_reply(state%session, trim(text), trim(target%uri), trim(target%cid), trim(root_uri), trim(root_cid), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Reply created: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine reply_to_post_object

  subroutine like_selected_post(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: target
    logical :: ok
    character(len=256) :: message, created_uri

    call get_current_post(state, state%selected, target, ok)
    if (.not. ok) then
      call set_status(state, 'No selected post.')
      return
    end if
    call like_post(state%session, trim(target%uri), trim(target%cid), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Liked: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine like_selected_post

  subroutine repost_selected_post(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: target
    logical :: ok
    character(len=256) :: message, created_uri

    call get_current_post(state, state%selected, target, ok)
    if (.not. ok) then
      call set_status(state, 'No selected post.')
      return
    end if
    call repost_post(state%session, trim(target%uri), trim(target%cid), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Reposted: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine repost_selected_post

  subroutine quote_selected_post(state)
    type(app_state), intent(inout) :: state
    type(post_view) :: target
    logical :: ok
    character(len=2000) :: text
    character(len=256) :: message, created_uri

    call get_current_post(state, state%selected, target, ok)
    if (.not. ok) then
      call set_status(state, 'No selected post.')
      return
    end if
    if (len_trim(target%uri) == 0 .or. len_trim(target%cid) == 0) then
      call set_status(state, 'Selected post is missing URI/CID.')
      return
    end if
    call prompt_line('Quote text: ', text)
    if (len_trim(text) == 0) then
      call set_status(state, 'Empty quote discarded.')
      return
    end if
    call create_quote_post(state%session, trim(text), trim(target%uri), trim(target%cid), ok, message, created_uri)
    if (ok) then
      call set_status(state, 'Quote created: ' // trim(created_uri))
    else
      call set_status(state, trim(message))
    end if
  end subroutine quote_selected_post

  subroutine refresh_stream_view(state, events, n)
    type(app_state), intent(inout) :: state
    type(stream_event), intent(out) :: events(MAX_ITEMS)
    integer, intent(out) :: n
    logical :: ok
    character(len=256) :: message
    integer :: i
    character(len=256) :: resolved_handle

    call tail_live_stream(events, n, ok, message, 12, trim(state%stream_mode))

    ! Resolve DID -> handle for each event (cache hit is fast; miss calls API)
    do i = 1, n
      if (len_trim(events(i)%did) > 0 .and. len_trim(events(i)%handle) == 0) then
        call resolve_did_to_handle(state, trim(events(i)%did), resolved_handle)
        events(i)%handle = trim(resolved_handle)
      end if
    end do

    state%prev_view = state%view
    state%view = VIEW_STREAM
    state%view_title = 'Live stream tail'
    call set_status(state, trim(message))
  end subroutine refresh_stream_view

  subroutine move_selection(state, delta, count)
    type(app_state), intent(inout) :: state
    integer, intent(in) :: delta, count
    integer :: pages

    if (count <= 0) return
    state%selected = max(1, min(count, state%selected + delta))
    pages = max(1, (count + state%page_size - 1) / state%page_size)
    state%page = max(1, min(pages, (state%selected - 1) / state%page_size + 1))
  end subroutine move_selection

  subroutine next_page(state, count)
    type(app_state), intent(inout) :: state
    integer, intent(in) :: count
    integer :: pages
    pages = max(1, (count + state%page_size - 1) / state%page_size)
    if (state%page < pages) state%page = state%page + 1
    state%selected = min(count, (state%page - 1) * state%page_size + 1)
  end subroutine next_page

  subroutine prev_page(state, count)
    type(app_state), intent(inout) :: state
    integer, intent(in) :: count
    if (state%page > 1) state%page = state%page - 1
    state%selected = min(count, (state%page - 1) * state%page_size + 1)
  end subroutine prev_page

  subroutine handle_home_command(state, line, quit, events, stream_n)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: line
    logical, intent(inout) :: quit
    type(stream_event), intent(inout) :: events(MAX_ITEMS)
    integer, intent(inout) :: stream_n
    character(len=:), allocatable :: cmd, arg
    integer :: sp

    sp = index(trim(line), ' ')
    if (sp > 0) then
      cmd = adjustl(trim(line(1:sp-1)))
      arg = adjustl(trim(line(sp+1:)))
    else
      cmd = adjustl(trim(line))
      arg = ''
    end if

    select case (trim(cmd))
    case ('a')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: a <handle>')
      else
        call load_author_feed(state, arg)
      end if
    case ('s')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: s <query>')
      else
        call load_search(state, arg)
      end if
    case ('p')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: p <handle>')
      else
        call load_profile(state, arg)
      end if
    case ('l')
      call login_flow(state)
    case ('n')
      call load_notifications(state)
    case ('i')
      call load_inbox(state)
    case ('dm')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: dm <handle>')
      else
        call start_dm(state, arg)
      end if
    case ('c')
      call compose_flow(state)
    case ('d')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: d <image path>')
      else
        call dither_flow(state, arg)
      end if
    case ('t')
      if (len_trim(arg) == 0) then
        call set_status(state, 'Usage: t <at://uri or bsky.app URL>')
      else
        call load_thread(state, arg)
      end if
    case ('j')
      call refresh_stream_view(state, events, stream_n)
    case ('m')
      if (trim(state%stream_mode) == 'jetstream') then
        state%stream_mode = 'relay-raw'
      else
        state%stream_mode = 'jetstream'
      end if
      call set_status(state, 'Stream mode set to ' // trim(state%stream_mode))
    case ('x')
      state%session%access_jwt = ''
      state%session%refresh_jwt = ''
      state%session%did = ''
      call clear_saved_session()
      call set_status(state, 'Logged out and cleared saved session.')
    case ('q')
      quit = .true.
    case default
      call set_status(state, 'Unknown command on home view.')
    end select
  end subroutine handle_home_command

  subroutine handle_post_command(state, line)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: line
    character(len=256) :: arg
    type(post_view) :: target
    logical :: ok

    select case (trim(line))
    case ('j')
      call move_selection(state, 1, state%current_post_count)
    case ('k')
      call move_selection(state, -1, state%current_post_count)
    case ('n')
      call next_page(state, state%current_post_count)
    case ('p')
      call prev_page(state, state%current_post_count)
    case ('o')
      call get_current_post(state, state%selected, target, ok)
      if (ok) then
        call load_thread(state, trim(target%uri))
      else
        call set_status(state, 'No selected post.')
      end if
    case ('r')
      call reply_to_selected_post(state)
    case ('l')
      call like_selected_post(state)
    case ('R')
      call repost_selected_post(state)
    case ('q')
      call quote_selected_post(state)
    case ('P')
      call get_current_post(state, state%selected, target, ok)
      if (ok .and. len_trim(target%handle) > 0) then
        call load_profile(state, trim(target%handle))
      else
        call set_status(state, 'Selected post has no handle.')
      end if
    case ('b')
      state%view = VIEW_HOME
      state%view_title = 'Fortransky'
      call set_status(state, 'Back to home.')
    case default
      if (len_trim(line) >= 2 .and. line(1:1) == '/') then
        arg = adjustl(trim(line(2:)))
        if (len_trim(arg) > 0) then
          call load_search(state, trim(arg))
        else
          call set_status(state, 'Usage: /search terms')
        end if
      else
        call set_status(state, 'Unknown command on post list.')
      end if
    end select
  end subroutine handle_post_command

  subroutine handle_profile_command(state, line)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: line
    select case (trim(line))
    case ('b')
      state%view = VIEW_HOME
      state%view_title = 'Fortransky'
      call set_status(state, 'Back to home.')
    case ('a')
      if (len_trim(state%profile%handle) > 0) then
        call load_author_feed(state, trim(state%profile%handle))
      else
        call set_status(state, 'Profile has no handle.')
      end if
    case default
      call set_status(state, 'Unknown command on profile view.')
    end select
  end subroutine handle_profile_command

  subroutine handle_notification_command(state, line)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: line

    select case (trim(line))
    case ('j')
      call move_selection(state, 1, state%notification_count)
    case ('k')
      call move_selection(state, -1, state%notification_count)
    case ('n')
      call next_page(state, state%notification_count)
    case ('p')
      call prev_page(state, state%notification_count)
    case ('o')
      if (state%selected >= 1 .and. state%selected <= state%notification_count) then
        call load_thread(state, trim(state%notifications(state%selected)%uri))
      else
        call set_status(state, 'No selected notification.')
      end if
    case ('r')
      call reply_to_selected_notification(state)
    case ('b')
      state%view = VIEW_HOME
      state%view_title = 'Fortransky'
      call set_status(state, 'Back to home.')
    case default
      call set_status(state, 'Unknown command on notifications view.')
    end select
  end subroutine handle_notification_command

  subroutine handle_stream_command(state, line, events, n)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: line
    type(stream_event), intent(inout) :: events(MAX_ITEMS)
    integer, intent(inout) :: n
    select case (trim(line))
    case ('b')
      state%view = VIEW_HOME
      state%view_title = 'Fortransky'
      call set_status(state, 'Back to home.')
    case ('j')
      call refresh_stream_view(state, events, n)
    case default
      call set_status(state, 'Unknown command on stream view.')
    end select
  end subroutine handle_stream_command

  subroutine app_loop()
    type(app_state) :: state
    type(stream_event) :: events(MAX_ITEMS)
    character(len=512) :: line
    logical :: quit
    integer :: stream_n

    state = app_state()
    call load_session_from_env(state%session)
    call load_saved_session(state%session)
    state%view = VIEW_HOME
    state%view_title = 'Fortransky'
    if (len_trim(state%session%access_jwt) > 0) then
      call set_status(state, 'Loaded saved session. TUI commands are line based: type a key or command and press Enter.')
    else
      call set_status(state, 'Ready. TUI commands are line based: type a key or command and press Enter.')
    end if
    quit = .false.
    stream_n = 0

    do while (.not. quit)
      select case (state%view)
      case (VIEW_HOME)
        call draw_home(state)
      case (VIEW_POST_LIST)
        call draw_post_list(state)
      case (VIEW_PROFILE)
        call draw_profile(state)
      case (VIEW_NOTIFICATIONS)
        call draw_notifications(state)
      case (VIEW_STREAM)
        call draw_stream(events, stream_n, state%status)
      end select

      call prompt_line('> ', line)
      if (len_trim(line) == 0) cycle

      select case (state%view)
      case (VIEW_HOME)
        call handle_home_command(state, trim(line), quit, events, stream_n)
      case (VIEW_POST_LIST)
        call handle_post_command(state, trim(line))
      case (VIEW_PROFILE)
        call handle_profile_command(state, trim(line))
      case (VIEW_NOTIFICATIONS)
        call handle_notification_command(state, trim(line))
      case (VIEW_STREAM)
        call handle_stream_command(state, trim(line), events, stream_n)
      end select
    end do
  end subroutine app_loop
end module tui_mod
