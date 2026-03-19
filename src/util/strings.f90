module strings_mod
  implicit none
contains
  pure function replace_all(text, old, new) result(out)
    character(len=*), intent(in) :: text, old, new
    character(len=:), allocatable :: out
    integer :: pos, start

    out = ''
    start = 1
    do
      pos = index(text(start:), old)
      if (pos == 0) then
        out = out // text(start:)
        exit
      end if
      pos = pos + start - 1
      out = out // text(start:pos-1) // new
      start = pos + len(old)
    end do
  end function replace_all

  pure function json_unescape(text) result(out)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: out
    out = text
    out = replace_all(out, '\\/','/')
    out = replace_all(out, '\\n', ' ')
    out = replace_all(out, '\\r', ' ')
    out = replace_all(out, '\\t', ' ')
    out = replace_all(out, '\\"', '"')
    out = replace_all(out, '\\\\', '\\')
  end function json_unescape

  pure function squeeze_spaces(text) result(out)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: out
    integer :: i
    logical :: prev_space

    out = ''
    prev_space = .false.
    do i = 1, len_trim(text)
      select case (text(i:i))
      case (' ', achar(9), achar(10), achar(13))
        if (.not. prev_space) then
          out = out // ' '
          prev_space = .true.
        end if
      case default
        out = out // text(i:i)
        prev_space = .false.
      end select
    end do
  end function squeeze_spaces


  pure function url_encode(text) result(out)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: out
    integer :: i, code, hi, lo
    character(len=16), parameter :: hexdigits = '0123456789ABCDEF'

    out = ''
    do i = 1, len_trim(text)
      code = iachar(text(i:i))
      select case (text(i:i))
      case ('A':'Z','a':'z','0':'9','-','_','.','~')
        out = out // text(i:i)
      case (' ')
        out = out // '%20'
      case default
        hi = code / 16 + 1
        lo = mod(code, 16) + 1
        out = out // '%' // hexdigits(hi:hi) // hexdigits(lo:lo)
      end select
    end do
  end function url_encode

end module strings_mod
