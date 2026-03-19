module log_store_mod
  use iso_fortran_env, only: error_unit
  implicit none
contains
  subroutine ensure_dir(path)
    character(len=*), intent(in) :: path
    call execute_command_line('mkdir -p ' // trim(path))
  end subroutine ensure_dir

  function app_state_dir() result(path)
    character(len=:), allocatable :: path
    character(len=512) :: home
    integer :: stat
    call get_environment_variable('HOME', home, status=stat)
    if (stat == 0 .and. len_trim(home) > 0) then
      path = trim(home) // '/.fortransky'
    else
      path = '.fortransky'
    end if
    call ensure_dir(path)
  end function app_state_dir

  function state_file(name) result(path)
    character(len=*), intent(in) :: name
    character(len=:), allocatable :: path
    path = app_state_dir() // '/' // trim(name)
  end function state_file

  subroutine append_line(path, line)
    character(len=*), intent(in) :: path, line
    integer :: unit, ios
    open(newunit=unit, file=trim(path), status='unknown', position='append', action='write', iostat=ios)
    if (ios /= 0) then
      write(error_unit,'(a)') 'append_line failed: ' // trim(path)
      return
    end if
    write(unit,'(a)') trim(line)
    close(unit)
  end subroutine append_line

  function read_first_line(path) result(line)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: line
    integer :: unit, ios
    logical :: exists
    character(len=4096) :: buf

    inquire(file=trim(path), exist=exists)
    if (.not. exists) then
      line = ''
      return
    end if
    open(newunit=unit, file=trim(path), status='old', action='read', iostat=ios)
    if (ios /= 0) then
      line = ''
      return
    end if
    read(unit,'(a)', iostat=ios) buf
    close(unit)
    if (ios /= 0) then
      line = ''
    else
      line = trim(buf)
    end if
  end function read_first_line

  subroutine write_text(path, text)
    character(len=*), intent(in) :: path, text
    integer :: unit, ios
    open(newunit=unit, file=trim(path), status='replace', action='write', iostat=ios)
    if (ios /= 0) return
    write(unit,'(a)') trim(text)
    close(unit)
  end subroutine write_text
end module log_store_mod
