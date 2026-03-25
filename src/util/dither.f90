! dither.f90 — Floyd-Steinberg error diffusion dither
! Bill Atkinson's algorithm, as used in MacPaint (1984).
!
! Reads:  /tmp/bsky_pixels_in.dat   (written by dither_prep.py)
! Writes: /tmp/bsky_pixels_out.dat  (read by dither_post.py)
!
! Pixel file format (same as Cobolsky dither.cob):
!   Line 1 — header: width(5) height(5) padding(10)
!   Lines 2..H+1 — one row per line, each pixel as "NNN " (3 digits + space)
!
! Floyd-Steinberg error distribution:
!                   [curr]  7/16 →
!          3/16  ↙  5/16 ↓  1/16 ↘
!
! Usage: called from dither_flow in tui.f90, not a standalone program.

module dither_mod
  implicit none
  private
  public :: run_dither, run_dither_for_display, render_pixels_terminal

  integer, parameter :: MAX_COLS = 576
  character(len=*), parameter :: PIXELS_IN  = '/tmp/bsky_pixels_in.dat'
  character(len=*), parameter :: PIXELS_OUT = '/tmp/bsky_pixels_out.dat'

contains

  subroutine run_dither(ok, message)
    logical, intent(out)           :: ok
    character(len=*), intent(out)  :: message

    integer :: width, height
    integer :: row, col
    integer :: old_val, new_val, err
    integer :: err7, err3, err5, err1

    ! Two-row pixel buffers with error accumulation headroom (-255..510)
    integer :: curr(MAX_COLS), nxt(MAX_COLS), out_row(MAX_COLS)

    character(len=4000) :: line_buf
    character(len=256)  :: hdr_buf
    integer :: in_unit, out_unit, ios
    integer :: parse_pos, pixel_idx
    character(len=3) :: px_str

    ok      = .false.
    message = 'Dither failed'

    ! ----------------------------------------------------------------
    ! Open files
    ! ----------------------------------------------------------------
    open(newunit=in_unit,  file=PIXELS_IN,  status='old', action='read',  &
         iostat=ios)
    if (ios /= 0) then
      message = 'Cannot open ' // PIXELS_IN
      return
    end if

    open(newunit=out_unit, file=PIXELS_OUT, status='replace', action='write', &
         iostat=ios)
    if (ios /= 0) then
      close(in_unit)
      message = 'Cannot open ' // PIXELS_OUT
      return
    end if

    ! ----------------------------------------------------------------
    ! Read header
    ! ----------------------------------------------------------------
    read(in_unit, '(a)', iostat=ios) hdr_buf
    if (ios /= 0) then
      message = 'Cannot read header from ' // PIXELS_IN
      close(in_unit); close(out_unit)
      return
    end if

    read(hdr_buf(1:5),  '(i5)') width
    read(hdr_buf(6:10), '(i5)') height

    if (width < 1 .or. width > MAX_COLS .or. height < 1) then
      message = 'Invalid image dimensions in pixel file'
      close(in_unit); close(out_unit)
      return
    end if

    ! Write header unchanged
    write(out_unit, '(a)') trim(hdr_buf)

    ! ----------------------------------------------------------------
    ! Initialise buffers
    ! ----------------------------------------------------------------
    curr = 0
    nxt  = 0
    out_row = 0

    ! ----------------------------------------------------------------
    ! Read first row into nxt (will be promoted to curr on first iter)
    ! ----------------------------------------------------------------
    call read_row(in_unit, width, nxt, ios)
    if (ios /= 0) then
      message = 'Cannot read first pixel row'
      close(in_unit); close(out_unit)
      return
    end if

    ! ----------------------------------------------------------------
    ! Main dither loop
    ! ----------------------------------------------------------------
    do row = 1, height

      ! Promote nxt → curr
      curr(1:width) = nxt(1:width)
      nxt(1:width)  = 0

      ! Read next row into nxt (except on last iteration)
      if (row < height) then
        call read_row(in_unit, width, nxt, ios)
        if (ios /= 0) nxt(1:width) = 0
      end if

      ! Apply Floyd-Steinberg across current row
      do col = 1, width

        old_val = curr(col)

        ! Clamp accumulated value to 0-255
        if (old_val < 0)   old_val = 0
        if (old_val > 255) old_val = 255

        ! 1-bit quantise
        if (old_val >= 128) then
          new_val = 255
        else
          new_val = 0
        end if

        out_row(col) = new_val

        ! Quantisation error
        err = old_val - new_val

        ! 7/16 → right
        if (col < width) then
          err7 = err * 7 / 16
          curr(col + 1) = curr(col + 1) + err7
        end if

        ! 3/16 → lower-left
        if (col > 1) then
          err3 = err * 3 / 16
          nxt(col - 1) = nxt(col - 1) + err3
        end if

        ! 5/16 → lower
        err5 = err * 5 / 16
        nxt(col) = nxt(col) + err5

        ! 1/16 → lower-right
        if (col < width) then
          err1 = err * 1 / 16
          nxt(col + 1) = nxt(col + 1) + err1
        end if

      end do

      ! Write output row
      call write_row(out_unit, width, out_row)

    end do

    close(in_unit)
    close(out_unit)

    ok      = .true.
    message = 'Dither complete'

  end subroutine run_dither

  ! ----------------------------------------------------------------
  ! Read one pixel row from the flat file into buf(1:width)
  ! Format: each pixel is "NNN " (3 digits + space)
  ! ----------------------------------------------------------------
  subroutine read_row(unit, width, buf, ios)
    integer, intent(in)  :: unit, width
    integer, intent(out) :: buf(MAX_COLS)
    integer, intent(out) :: ios

    character(len=4000) :: line
    integer :: pos, idx
    character(len=3) :: px

    buf = 0
    read(unit, '(a)', iostat=ios) line
    if (ios /= 0) return

    pos = 1
    do idx = 1, width
      px = line(pos:pos+2)
      read(px, '(i3)', iostat=ios) buf(idx)
      if (ios /= 0) buf(idx) = 0
      pos = pos + 4
    end do
    ios = 0

  end subroutine read_row

  ! ----------------------------------------------------------------
  ! Write one pixel row to the flat file from buf(1:width)
  ! ----------------------------------------------------------------
  subroutine write_row(unit, width, buf)
    integer, intent(in) :: unit, width
    integer, intent(in) :: buf(MAX_COLS)

    character(len=4000) :: line
    integer :: pos, idx
    character(len=3) :: px

    line = ' '
    pos  = 1
    do idx = 1, width
      write(px, '(i3.3)') buf(idx)
      line(pos:pos+2) = px
      line(pos+3:pos+3) = ' '
      pos = pos + 4
    end do

    write(unit, '(a)') line(1:pos-1)

  end subroutine write_row

  ! ----------------------------------------------------------------
  ! run_dither_for_display — like run_dither but uses custom pixel files
  ! for terminal display (smaller canvas than the posting path)
  ! ----------------------------------------------------------------
  subroutine run_dither_for_display(pixels_in, pixels_out, ok, message)
    character(len=*), intent(in)  :: pixels_in, pixels_out
    logical,          intent(out) :: ok
    character(len=*), intent(out) :: message

    integer :: width, height
    integer :: row, col
    integer :: old_val, new_val, err
    integer :: err7, err3, err5, err1
    integer :: curr(MAX_COLS), nxt(MAX_COLS), out_row(MAX_COLS)
    character(len=4000) :: line_buf
    integer :: in_unit, out_unit, ios

    ok      = .false.
    message = 'Dither failed'

    open(newunit=in_unit,  file=trim(pixels_in),  status='old', action='read',  iostat=ios)
    if (ios /= 0) then; message = 'Cannot open ' // trim(pixels_in); return; end if
    open(newunit=out_unit, file=trim(pixels_out), status='replace', action='write', iostat=ios)
    if (ios /= 0) then; close(in_unit); message = 'Cannot open ' // trim(pixels_out); return; end if

    read(in_unit, '(a)', iostat=ios) line_buf
    if (ios /= 0) then; close(in_unit); close(out_unit); message = 'Bad header'; return; end if
    read(line_buf(1:5),  '(i5)') width
    read(line_buf(6:10), '(i5)') height

    if (width < 1 .or. width > MAX_COLS .or. height < 1) then
      message = 'Invalid dimensions'; close(in_unit); close(out_unit); return
    end if

    write(out_unit, '(a)') trim(line_buf)
    curr = 0; nxt = 0; out_row = 0

    call read_row(in_unit, width, nxt, ios)
    if (ios /= 0) then
      close(in_unit); close(out_unit); message = 'Bad first row'; return
    end if

    do row = 1, height
      curr(1:width) = nxt(1:width)
      nxt(1:width)  = 0
      if (row < height) then
        call read_row(in_unit, width, nxt, ios)
        if (ios /= 0) nxt(1:width) = 0
      end if
      do col = 1, width
        old_val = curr(col)
        if (old_val < 0)   old_val = 0
        if (old_val > 255) old_val = 255
        if (old_val >= 128) then; new_val = 255; else; new_val = 0; end if
        out_row(col) = new_val
        err = old_val - new_val
        if (col < width)  curr(col+1)  = curr(col+1)  + err * 7 / 16
        if (col > 1)      nxt(col-1)   = nxt(col-1)   + err * 3 / 16
                          nxt(col)     = nxt(col)      + err * 5 / 16
        if (col < width)  nxt(col+1)   = nxt(col+1)   + err * 1 / 16
      end do
      call write_row(out_unit, width, out_row)
    end do

    close(in_unit); close(out_unit)
    ok = .true.; message = 'Dither complete'
  end subroutine run_dither_for_display

  ! ----------------------------------------------------------------
  ! render_pixels_terminal — read dithered pixel file and print using
  ! Unicode half-block characters for double vertical resolution.
  !
  ! Half-block encoding (two pixel rows per terminal line):
  !   top=0, bot=0  →  ' '   (space)
  !   top=1, bot=0  →  '▀'   (upper half block)
  !   top=0, bot=1  →  '▄'   (lower half block)
  !   top=1, bot=1  →  '█'   (full block)
  ! where 0=black (dithered on), 1=white (dithered off)
  ! ----------------------------------------------------------------
  subroutine render_pixels_terminal(pixels_out, ok, message)
    character(len=*), intent(in)  :: pixels_out
    logical,          intent(out) :: ok
    character(len=*), intent(out) :: message

    integer :: width, height, row, col
    integer :: top_px, bot_px
    integer :: top_row(MAX_COLS), bot_row(MAX_COLS)
    character(len=4000) :: line_buf
    integer :: in_unit, ios
    character(len=:), allocatable :: out_line

    ok = .false.; message = 'render failed'

    open(newunit=in_unit, file=trim(pixels_out), status='old', action='read', iostat=ios)
    if (ios /= 0) then; message = 'Cannot open ' // trim(pixels_out); return; end if

    read(in_unit, '(a)', iostat=ios) line_buf
    if (ios /= 0) then; close(in_unit); return; end if
    read(line_buf(1:5),  '(i5)') width
    read(line_buf(6:10), '(i5)') height

    ! Process two pixel rows at a time → one terminal line
    row = 0
    do while (row < height)
      ! Read top pixel row
      call read_row(in_unit, width, top_row, ios)
      if (ios /= 0) exit
      row = row + 1

      ! Read bottom pixel row (or use white if at last row)
      if (row < height) then
        call read_row(in_unit, width, bot_row, ios)
        if (ios /= 0) bot_row(1:width) = 255
        row = row + 1
      else
        bot_row(1:width) = 255
      end if

      ! Build output line using half-block chars
      out_line = ''
      do col = 1, width
        top_px = top_row(col)   ! 0=black, 255=white
        bot_px = bot_row(col)

        if (top_px < 128 .and. bot_px < 128) then
          out_line = out_line // char(226) // char(150) // char(136)  ! █ U+2588
        else if (top_px < 128 .and. bot_px >= 128) then
          out_line = out_line // char(226) // char(150) // char(128)  ! ▀ U+2580
        else if (top_px >= 128 .and. bot_px < 128) then
          out_line = out_line // char(226) // char(150) // char(132)  ! ▄ U+2584
        else
          out_line = out_line // ' '
        end if
      end do

      write(*, '(a)') trim(out_line)
    end do

    close(in_unit)
    ok = .true.; message = 'Rendered'
  end subroutine render_pixels_terminal

end module dither_mod
