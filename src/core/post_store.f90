module post_store_mod
  use models_mod, only: post_view, MAX_ITEMS
  use app_state_mod, only: app_state, MAX_CACHE
  implicit none
contains
  integer function find_post_index(state, post) result(idx)
    type(app_state), intent(in) :: state
    type(post_view), intent(in) :: post
    integer :: i

    idx = 0
    do i = 1, state%post_count
      if (len_trim(post%uri) > 0 .and. trim(state%post_cache(i)%uri) == trim(post%uri)) then
        idx = i
        return
      end if
    end do
  end function find_post_index

  subroutine upsert_posts(state, posts, n)
    type(app_state), intent(inout) :: state
    type(post_view), intent(in) :: posts(MAX_ITEMS)
    integer, intent(in) :: n
    integer :: i, idx

    state%current_post_ids = 0
    state%current_post_count = 0
    do i = 1, n
      idx = find_post_index(state, posts(i))
      if (idx == 0) then
        if (state%post_count < MAX_CACHE) then
          state%post_count = state%post_count + 1
          idx = state%post_count
          state%post_cache(idx) = posts(i)
        else
          idx = mod(i-1, MAX_CACHE) + 1
          state%post_cache(idx) = posts(i)
        end if
      else
        state%post_cache(idx) = posts(i)
      end if
      if (state%current_post_count < MAX_ITEMS) then
        state%current_post_count = state%current_post_count + 1
        state%current_post_ids(state%current_post_count) = idx
      end if
    end do
  end subroutine upsert_posts

  subroutine get_current_post(state, list_index, post, ok)
    type(app_state), intent(in) :: state
    integer, intent(in) :: list_index
    type(post_view), intent(out) :: post
    logical, intent(out) :: ok
    integer :: idx

    post = post_view()
    ok = .false.
    if (list_index < 1 .or. list_index > state%current_post_count) return
    idx = state%current_post_ids(list_index)
    if (idx < 1 .or. idx > state%post_count) return
    post = state%post_cache(idx)
    ok = .true.
  end subroutine get_current_post
end module post_store_mod
