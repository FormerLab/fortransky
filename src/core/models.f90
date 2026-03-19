module models_mod
  implicit none
  integer, parameter :: MAX_ITEMS = 64
  integer, parameter :: FIELD_LEN = 1024
  integer, parameter :: HANDLE_LEN = 256
  integer, parameter :: URI_LEN = 512
  integer, parameter :: CID_LEN = 256
  integer, parameter :: TS_LEN = 64

  type :: post_view
    character(len=FIELD_LEN) :: author = ''
    character(len=HANDLE_LEN) :: handle = ''
    character(len=FIELD_LEN) :: text = ''
    character(len=URI_LEN) :: uri = ''
    character(len=CID_LEN) :: cid = ''
    character(len=TS_LEN) :: indexed_at = ''
    character(len=URI_LEN) :: parent_uri = ''
    character(len=CID_LEN) :: parent_cid = ''
    character(len=URI_LEN) :: root_uri = ''
    character(len=CID_LEN) :: root_cid = ''
    character(len=32) :: reason = ''
    character(len=32) :: record_type = ''
    character(len=8) :: like_count = ''
    character(len=8) :: repost_count = ''
    character(len=8) :: reply_count = ''
    character(len=8) :: quote_count = ''
    logical :: is_repost = .false.
    logical :: is_quote = .false.
    logical :: has_images = .false.
    logical :: has_video = .false.
    logical :: has_external = .false.
    logical :: has_facets = .false.
  end type post_view

  type :: stream_event
    character(len=32) :: kind = ''
    character(len=HANDLE_LEN) :: handle = ''
    character(len=URI_LEN) :: did = ''
    character(len=FIELD_LEN) :: text = ''
    character(len=TS_LEN) :: time_us = ''
  end type stream_event

  type :: actor_profile
    character(len=FIELD_LEN) :: display_name = ''
    character(len=HANDLE_LEN) :: handle = ''
    character(len=URI_LEN) :: did = ''
    character(len=FIELD_LEN) :: description = ''
    character(len=TS_LEN) :: indexed_at = ''
    character(len=64) :: followers_count = ''
    character(len=64) :: follows_count = ''
    character(len=64) :: posts_count = ''
  end type actor_profile

  type :: notification_view
    character(len=32) :: reason = ''
    character(len=FIELD_LEN) :: author = ''
    character(len=HANDLE_LEN) :: handle = ''
    character(len=FIELD_LEN) :: text = ''
    character(len=URI_LEN) :: uri = ''
    character(len=CID_LEN) :: cid = ''
    character(len=TS_LEN) :: indexed_at = ''
    character(len=URI_LEN) :: parent_uri = ''
    character(len=CID_LEN) :: parent_cid = ''
    character(len=URI_LEN) :: root_uri = ''
    character(len=CID_LEN) :: root_cid = ''
  end type notification_view

  type :: session_state
    character(len=256) :: pds_host = 'https://bsky.social'
    character(len=256) :: identifier = ''
    character(len=256) :: did = ''
    character(len=1024) :: access_jwt = ''
    character(len=1024) :: refresh_jwt = ''
  end type session_state
end module models_mod
