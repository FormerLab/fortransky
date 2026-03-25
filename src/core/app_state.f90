module app_state_mod
  use models_mod, only: session_state, post_view, actor_profile, notification_view, MAX_ITEMS, HANDLE_LEN, URI_LEN
  implicit none
  integer, parameter :: VIEW_HOME=1, VIEW_POST_LIST=2, VIEW_PROFILE=3, VIEW_NOTIFICATIONS=4, VIEW_STREAM=5, &
                        VIEW_CONVO_LIST=6, VIEW_MESSAGES=7
  integer, parameter :: MAX_CACHE = 256
  integer, parameter :: DID_CACHE_SIZE = 128

  type :: app_state
    type(session_state) :: session
    integer :: view = VIEW_HOME
    integer :: prev_view = VIEW_HOME
    character(len=128) :: view_title = 'Fortransky'
    character(len=256) :: status = 'Ready.'
    integer :: selected = 1
    integer :: page = 1
    integer :: page_size = 5
    character(len=16) :: stream_mode = 'jetstream'

    type(post_view) :: post_cache(MAX_CACHE)
    integer :: post_count = 0
    integer :: current_post_ids(MAX_ITEMS) = 0
    integer :: current_post_count = 0

    type(notification_view) :: notifications(MAX_ITEMS)
    integer :: notification_count = 0

    type(actor_profile) :: profile

    ! DID -> handle resolution cache
    character(len=URI_LEN)    :: did_cache(DID_CACHE_SIZE)    = ''
    character(len=HANDLE_LEN) :: handle_cache(DID_CACHE_SIZE) = ''
    integer :: did_cache_count = 0
  end type app_state
contains
  subroutine reset_selection(state)
    type(app_state), intent(inout) :: state
    state%selected = 1
    state%page = 1
  end subroutine reset_selection

  subroutine set_status(state, text)
    type(app_state), intent(inout) :: state
    character(len=*), intent(in) :: text
    state%status = ''
    state%status(1:min(len_trim(text), len(state%status))) = trim(text)
  end subroutine set_status
end module app_state_mod
