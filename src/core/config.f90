module config_mod
  use models_mod, only: session_state
  implicit none
contains
  subroutine load_session_from_env(state)
    type(session_state), intent(inout) :: state
    integer :: stat

    call get_environment_variable('BSKY_PDS_HOST', state%pds_host, status=stat)
    if (stat /= 0 .or. len_trim(state%pds_host) == 0) state%pds_host = 'https://bsky.social'
    call get_environment_variable('BSKY_IDENTIFIER', state%identifier, status=stat)
  end subroutine load_session_from_env
end module config_mod
