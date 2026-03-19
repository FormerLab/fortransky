module process_mod
  use iso_fortran_env, only: error_unit
  implicit none
contains
  function slurp_file(path) result(content)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: content
    integer :: unit, ios, size
    logical :: exists

    inquire(file=path, exist=exists, size=size)
    if (.not. exists) then
      content = ''
      return
    end if

    open(newunit=unit, file=path, status='old', access='stream', form='unformatted', action='read', iostat=ios)
    if (ios /= 0) then
      write(error_unit, '(a)') 'Failed to open file: ' // trim(path)
      content = ''
      return
    end if

    allocate(character(len=size) :: content)
    if (size > 0) then
      read(unit, iostat=ios) content
      if (ios /= 0) content = ''
    else
      content = ''
    end if
    close(unit)
  end function slurp_file

  subroutine run_capture(command, output_path, exitstat)
    character(len=*), intent(in) :: command, output_path
    integer, intent(out) :: exitstat
    character(len=:), allocatable :: cmd

    cmd = trim(command) // ' > ' // trim(output_path) // ' 2>&1'
    call execute_command_line(cmd, exitstat=exitstat)
  end subroutine run_capture
end module process_mod
