module firehose_bridge
  use iso_c_binding
  implicit none
  private

  integer(c_int), parameter, public :: FS_OK = 0
  integer(c_int), parameter, public :: FS_ERR_CBOR = 1
  integer(c_int), parameter, public :: FS_ERR_ENVELOPE = 2
  integer(c_int), parameter, public :: FS_ERR_COMMIT_PARSE = 3
  integer(c_int), parameter, public :: FS_ERR_CAR_PARSE = 4
  integer(c_int), parameter, public :: FS_ERR_DAGCBOR_PARSE = 5
  integer(c_int), parameter, public :: FS_ERR_UNSUPPORTED = 6
  integer(c_int), parameter, public :: FS_ERR_OOM = 7
  integer(c_int), parameter, public :: FS_ERR_INTERNAL = 8

  integer(c_int), parameter, public :: FS_KIND_COMMIT_OP = 1
  integer(c_int), parameter, public :: FS_KIND_IDENTITY = 2
  integer(c_int), parameter, public :: FS_KIND_ACCOUNT = 3
  integer(c_int), parameter, public :: FS_KIND_INFO = 4
  integer(c_int), parameter, public :: FS_KIND_ERROR = 5

  integer(c_int), parameter, public :: FS_OP_NONE = 0
  integer(c_int), parameter, public :: FS_OP_CREATE = 1
  integer(c_int), parameter, public :: FS_OP_UPDATE = 2
  integer(c_int), parameter, public :: FS_OP_DELETE = 3

  type, bind(C), public :: fs_event_t
     integer(c_int64_t) :: seq
     integer(c_int) :: kind
     integer(c_int) :: op_action
     type(c_ptr) :: repo_did
     type(c_ptr) :: rev
     type(c_ptr) :: collection
     type(c_ptr) :: rkey
     type(c_ptr) :: record_cid
     type(c_ptr) :: uri
     type(c_ptr) :: record_json
     type(c_ptr) :: error_message
  end type fs_event_t

  type, bind(C), public :: fs_event_batch_t
     type(c_ptr) :: events
     integer(c_size_t) :: len
     type(c_ptr) :: owner
  end type fs_event_batch_t

  public :: bridge_init, bridge_shutdown, bridge_decode_frame, bridge_free_batch
  public :: bridge_decode_frame_with_status, c_string_to_fortran, get_event_ptr

  interface
     function fs_decoder_init() bind(C, name="fs_decoder_init") result(rc)
       import :: c_int
       integer(c_int) :: rc
     end function fs_decoder_init

     subroutine fs_decoder_shutdown() bind(C, name="fs_decoder_shutdown")
     end subroutine fs_decoder_shutdown

     function fs_decode_frame(data, len, out_batch) bind(C, name="fs_decode_frame") result(rc)
       import :: c_ptr, c_size_t, c_int, fs_event_batch_t
       type(c_ptr), value :: data
       integer(c_size_t), value :: len
       type(fs_event_batch_t) :: out_batch
       integer(c_int) :: rc
     end function fs_decode_frame

     subroutine fs_free_batch(batch) bind(C, name="fs_free_batch")
       import :: fs_event_batch_t
       type(fs_event_batch_t) :: batch
     end subroutine fs_free_batch
  end interface

contains

  function bridge_init() result(rc)
    integer(c_int) :: rc
    rc = fs_decoder_init()
  end function bridge_init

  subroutine bridge_shutdown()
    call fs_decoder_shutdown()
  end subroutine bridge_shutdown

  function bridge_decode_frame(bytes) result(batch)
    integer(c_signed_char), intent(in), target :: bytes(:)
    type(fs_event_batch_t) :: batch
    integer(c_int) :: rc

    batch%events = c_null_ptr
    batch%len = 0_c_size_t
    batch%owner = c_null_ptr

    if (size(bytes) <= 0) return
    rc = fs_decode_frame(c_loc(bytes(1)), int(size(bytes), c_size_t), batch)
    if (rc /= FS_OK) then
       ! Even on non-OK status, the bridge may still return an error event batch.
       ! Callers should inspect batch contents before discarding them.
    end if
  end function bridge_decode_frame

  function bridge_decode_frame_with_status(bytes, status) result(batch)
    integer(c_signed_char), intent(in), target :: bytes(:)
    integer(c_int), intent(out) :: status
    type(fs_event_batch_t) :: batch

    batch%events = c_null_ptr
    batch%len = 0_c_size_t
    batch%owner = c_null_ptr

    if (size(bytes) <= 0) then
       status = FS_ERR_INTERNAL
       return
    end if

    status = fs_decode_frame(c_loc(bytes(1)), int(size(bytes), c_size_t), batch)
  end function bridge_decode_frame_with_status

  subroutine bridge_free_batch(batch)
    type(fs_event_batch_t), intent(inout) :: batch
    call fs_free_batch(batch)
    batch%events = c_null_ptr
    batch%len = 0_c_size_t
    batch%owner = c_null_ptr
  end subroutine bridge_free_batch

  function get_event_ptr(batch, index) result(p)
    type(fs_event_batch_t), intent(in) :: batch
    integer, intent(in) :: index
    type(c_ptr) :: p
    type(fs_event_t), pointer :: events(:)

    p = c_null_ptr
    if (.not. c_associated(batch%events)) return
    if (index < 1) return
    if (index > int(batch%len)) return

    call c_f_pointer(batch%events, events, [int(batch%len)])
    p = c_loc(events(index))
  end function get_event_ptr

  function c_string_to_fortran(cstr) result(out)
    type(c_ptr), value :: cstr
    character(len=:), allocatable :: out
    character(kind=c_char), pointer :: p(:)
    integer :: n, i

    if (.not. c_associated(cstr)) then
       out = ''
       return
    end if

    call c_f_pointer(cstr, p, [1000000])
    n = 0
    do while (p(n+1) /= c_null_char)
       n = n + 1
    end do

    allocate(character(len=n) :: out)
    do i = 1, n
       out(i:i) = achar(iachar(p(i)))
    end do
  end function c_string_to_fortran

end module firehose_bridge
