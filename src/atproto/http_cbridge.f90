module http_cbridge_mod
  use iso_c_binding, only: c_ptr, c_char, c_long, c_size_t, c_null_char, c_associated, c_f_pointer, c_int8_t, c_int
  use strings_mod, only: url_encode
  implicit none
  private
  public :: http_get, http_post_json, http_post_binary, http_get_urlencoded, &
            http_get_proxied, http_post_json_proxied, http_get_to_file, last_http_status

  integer :: last_http_status = 0

  interface
    function fortransky_http_get(url, auth_header, status_code, out_len) bind(C, name='fortransky_http_get') result(res)
      import :: c_ptr, c_char, c_long, c_size_t
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      integer(c_long), intent(out) :: status_code
      integer(c_size_t), intent(out) :: out_len
      type(c_ptr) :: res
    end function fortransky_http_get

    function fortransky_http_post_json(url, auth_header, json_body, &
        status_code, out_len) bind(C, name='fortransky_http_post_json') result(res)
      import :: c_ptr, c_char, c_long, c_size_t
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      character(kind=c_char), dimension(*), intent(in) :: json_body
      integer(c_long), intent(out) :: status_code
      integer(c_size_t), intent(out) :: out_len
      type(c_ptr) :: res
    end function fortransky_http_post_json

    subroutine fortransky_http_free(ptr) bind(C, name='fortransky_http_free')
      import :: c_ptr
      type(c_ptr), value :: ptr
    end subroutine fortransky_http_free

    function fortransky_http_post_binary(url, auth_header, content_type, data, data_len, status_code, out_len) &
        bind(C, name='fortransky_http_post_binary') result(res)
      import :: c_ptr, c_char, c_long, c_size_t, c_int8_t
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      character(kind=c_char), dimension(*), intent(in) :: content_type
      integer(c_int8_t),  dimension(*), intent(in) :: data
      integer(c_size_t),  value,         intent(in) :: data_len
      integer(c_long),    intent(out) :: status_code
      integer(c_size_t),  intent(out) :: out_len
      type(c_ptr) :: res
    end function fortransky_http_post_binary

    function fortransky_http_get_proxied(url, auth_header, proxy_did, status_code, out_len) &
        bind(C, name='fortransky_http_get_proxied') result(res)
      import :: c_ptr, c_char, c_long, c_size_t
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      character(kind=c_char), dimension(*), intent(in) :: proxy_did
      integer(c_long),   intent(out) :: status_code
      integer(c_size_t), intent(out) :: out_len
      type(c_ptr) :: res
    end function fortransky_http_get_proxied

    function fortransky_http_post_json_proxied(url, auth_header, json_body, proxy_did, status_code, out_len) &
        bind(C, name='fortransky_http_post_json_proxied') result(res)
      import :: c_ptr, c_char, c_long, c_size_t
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      character(kind=c_char), dimension(*), intent(in) :: json_body
      character(kind=c_char), dimension(*), intent(in) :: proxy_did
      integer(c_long),   intent(out) :: status_code
      integer(c_size_t), intent(out) :: out_len
      type(c_ptr) :: res
    end function fortransky_http_post_json_proxied

    function fortransky_http_get_to_file(url, auth_header, out_path, status_code) &
        bind(C, name='fortransky_http_get_to_file') result(rc)
      import :: c_char, c_long, c_int
      character(kind=c_char), dimension(*), intent(in) :: url
      character(kind=c_char), dimension(*), intent(in) :: auth_header
      character(kind=c_char), dimension(*), intent(in) :: out_path
      integer(c_long), intent(out) :: status_code
      integer(c_int) :: rc
    end function fortransky_http_get_to_file
  end interface
contains
  function http_get(url, auth_token) result(body)
    character(len=*), intent(in) :: url
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: header
    integer(c_long) :: status_code
    integer(c_size_t) :: out_len
    type(c_ptr) :: raw

    header = auth_header_value(auth_token)
    raw = fortransky_http_get(c_string(trim(url)), c_string(header), status_code, out_len)
    last_http_status = int(status_code)
    body = from_c_buffer(raw, out_len)
    if (c_associated(raw)) call fortransky_http_free(raw)
  end function http_get

  function http_get_urlencoded(url, key, value, auth_token) result(body)
    character(len=*), intent(in) :: url, key, value
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: built

    if (index(url, '?') > 0) then
      built = trim(url) // '&' // trim(key) // '=' // url_encode(trim(value))
    else
      built = trim(url) // '?' // trim(key) // '=' // url_encode(trim(value))
    end if
    body = http_get(built, auth_token)
  end function http_get_urlencoded

  function http_post_json(url, json_body, auth_token) result(body)
    character(len=*), intent(in) :: url, json_body
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: header
    integer(c_long) :: status_code
    integer(c_size_t) :: out_len
    type(c_ptr) :: raw

    header = auth_header_value(auth_token)
    raw = fortransky_http_post_json(c_string(trim(url)), c_string(header), c_string(trim(json_body)), status_code, out_len)
    last_http_status = int(status_code)
    body = from_c_buffer(raw, out_len)
    if (c_associated(raw)) call fortransky_http_free(raw)
  end function http_post_json

  ! Upload raw binary data; returns the response body (JSON from uploadBlob)
  function http_post_binary(url, data, data_len, content_type, auth_token) result(body)
    character(len=*),  intent(in) :: url
    integer(c_int8_t), intent(in) :: data(*)
    integer,           intent(in) :: data_len
    character(len=*),  intent(in) :: content_type
    character(len=*),  intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: header
    integer(c_long)   :: status_code
    integer(c_size_t) :: out_len
    type(c_ptr) :: raw

    header = auth_header_value(auth_token)
    raw = fortransky_http_post_binary( &
            c_string(trim(url)),          &
            c_string(header),             &
            c_string(trim(content_type)), &
            data, int(data_len, c_size_t),&
            status_code, out_len)
    last_http_status = int(status_code)
    body = from_c_buffer(raw, out_len)
    if (c_associated(raw)) call fortransky_http_free(raw)
  end function http_post_binary

  ! GET with atproto-proxy header — for chat.bsky.* endpoints
  function http_get_proxied(url, proxy_did, auth_token) result(body)
    character(len=*), intent(in) :: url, proxy_did
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: header
    integer(c_long)   :: status_code
    integer(c_size_t) :: out_len
    type(c_ptr) :: raw

    header = auth_header_value(auth_token)
    raw = fortransky_http_get_proxied( &
            c_string(trim(url)), c_string(header), &
            c_string(trim(proxy_did)), status_code, out_len)
    last_http_status = int(status_code)
    body = from_c_buffer(raw, out_len)
    if (c_associated(raw)) call fortransky_http_free(raw)
  end function http_get_proxied

  ! POST JSON with atproto-proxy header — for chat.bsky.* endpoints
  function http_post_json_proxied(url, json_body, proxy_did, auth_token) result(body)
    character(len=*), intent(in) :: url, json_body, proxy_did
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: header
    integer(c_long)   :: status_code
    integer(c_size_t) :: out_len
    type(c_ptr) :: raw

    header = auth_header_value(auth_token)
    raw = fortransky_http_post_json_proxied( &
            c_string(trim(url)), c_string(header), &
            c_string(trim(json_body)), c_string(trim(proxy_did)), &
            status_code, out_len)
    last_http_status = int(status_code)
    body = from_c_buffer(raw, out_len)
    if (c_associated(raw)) call fortransky_http_free(raw)
  end function http_post_json_proxied

  ! Download binary content to a file — for blob/image fetch
  function http_get_to_file(url, out_path, auth_token) result(ok)
    character(len=*), intent(in) :: url, out_path
    character(len=*), intent(in), optional :: auth_token
    logical :: ok
    character(len=:), allocatable :: header
    integer(c_long) :: status_code
    integer(c_int)  :: rc

    header = auth_header_value(auth_token)
    rc = fortransky_http_get_to_file( &
           c_string(trim(url)), c_string(header), &
           c_string(trim(out_path)), status_code)
    last_http_status = int(status_code)
    ok = (rc == 0)
  end function http_get_to_file

  function auth_header_value(auth_token) result(header)
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: header
    if (present(auth_token)) then
      if (len_trim(auth_token) > 0) then
        header = 'Authorization: Bearer ' // trim(auth_token)
        return
      end if
    end if
    header = ''
  end function auth_header_value

  function c_string(text) result(buf)
    character(len=*), intent(in) :: text
    character(kind=c_char,len=:), allocatable :: buf
    buf = text // c_null_char
  end function c_string

  function from_c_buffer(ptr, nbytes) result(text)
    type(c_ptr), intent(in) :: ptr
    integer(c_size_t), intent(in) :: nbytes
    character(len=:), allocatable :: text
    character(kind=c_char), pointer :: chars(:)
    integer :: i, n

    if (.not. c_associated(ptr)) then
      text = ''
      return
    end if
    n = int(nbytes)
    if (n <= 0) then
      text = ''
      return
    end if
    call c_f_pointer(ptr, chars, [n])
    allocate(character(len=n) :: text)
    do i = 1, n
      text(i:i) = chars(i)
    end do
  end function from_c_buffer
end module http_cbridge_mod
