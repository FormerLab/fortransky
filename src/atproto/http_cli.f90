module http_cli_mod
  use process_mod, only: run_capture, slurp_file
  implicit none
contains
  function http_get(url, auth_token) result(body)
    character(len=*), intent(in) :: url
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: cmd
    integer :: code

    cmd = 'curl -sL --max-time 20 '
    if (present(auth_token)) then
      if (len_trim(auth_token) > 0) then
        cmd = cmd // '-H "Authorization: Bearer ' // trim(auth_token) // '" '
      end if
    end if
    cmd = cmd // '"' // trim(url) // '"'
    call run_capture(cmd, '/tmp/fortransky_http.out', code)
    body = slurp_file('/tmp/fortransky_http.out')
  end function http_get

  function http_get_urlencoded(url, key, value, auth_token) result(body)
    character(len=*), intent(in) :: url, key, value
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: cmd
    integer :: code

    cmd = 'curl -sL --max-time 20 --get '
    if (present(auth_token)) then
      if (len_trim(auth_token) > 0) then
        cmd = cmd // '-H "Authorization: Bearer ' // trim(auth_token) // '" '
      end if
    end if
    cmd = cmd // '--data-urlencode "' // trim(key) // '=' // trim(value) // '" '
    cmd = cmd // '"' // trim(url) // '"'
    call run_capture(cmd, '/tmp/fortransky_http.out', code)
    body = slurp_file('/tmp/fortransky_http.out')
  end function http_get_urlencoded

  function http_post_json(url, json_body, auth_token) result(body)
    character(len=*), intent(in) :: url, json_body
    character(len=*), intent(in), optional :: auth_token
    character(len=:), allocatable :: body
    character(len=:), allocatable :: cmd
    integer :: code

    cmd = 'curl -sL --max-time 20 -X POST -H "Content-Type: application/json" '
    if (present(auth_token)) then
      if (len_trim(auth_token) > 0) then
        cmd = cmd // '-H "Authorization: Bearer ' // trim(auth_token) // '" '
      end if
    end if
    cmd = cmd // '--data ' // "'" // trim(json_body) // "'" // ' "' // trim(url) // '"'
    call run_capture(cmd, '/tmp/fortransky_http.out', code)
    body = slurp_file('/tmp/fortransky_http.out')
  end function http_post_json
end module http_cli_mod
