"! ABAP Standard transport of the language model call (z2ui5_if_agent_llm_http):
"! cl_http_client by an SM59 destination (type G - host, TLS, proxy and,
"! for a gateway, its logon there) or by URL (SSL client identity ANONYM:
"! the server certificate chain of the host must be in that PSE, STRUST).
"! z2ui5_cl_agent_llm=&gt;get_http( ) creates it - nothing else does.
CLASS z2ui5_cl_agent_llm_std DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm_http.

  PROTECTED SECTION.

  PRIVATE SECTION.

    METHODS fail
      IMPORTING
        text TYPE string
      RAISING
        z2ui5_cx_agent_llm.

ENDCLASS.


CLASS z2ui5_cl_agent_llm_std IMPLEMENTATION.

  METHOD fail.

    RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
      EXPORTING
        kind      = z2ui5_cx_agent_llm=>cs_kind-http
        text      = text
        retryable = abap_true.

  ENDMETHOD.

  METHOD z2ui5_if_agent_llm_http~post.

    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_destination TYPE c LENGTH 32.
    DATA lv_message TYPE string.

    IF is_request-destination IS NOT INITIAL.
      lv_destination = is_request-destination.
      cl_http_client=>create_by_destination(
        EXPORTING
          destination              = lv_destination
        IMPORTING
          client                   = lo_client
        EXCEPTIONS
          argument_not_found       = 1
          destination_not_found    = 2
          destination_no_authority = 3
          plugin_not_active        = 4
          internal_error           = 5
          OTHERS                   = 6 ).
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind = z2ui5_cx_agent_llm=>cs_kind-config
            text = |the destination { is_request-destination } cannot be used (SM59, return code { sy-subrc })|.
      ENDIF.
      IF is_request-url IS NOT INITIAL.
        cl_http_utility=>set_request_uri( request = lo_client->request
                                          uri     = is_request-url ).
      ENDIF.
    ELSE.
      cl_http_client=>create_by_url(
        EXPORTING
          url                = is_request-url
          ssl_id             = 'ANONYM'
        IMPORTING
          client             = lo_client
        EXCEPTIONS
          argument_not_found = 1
          plugin_not_active  = 2
          internal_error     = 3
          OTHERS             = 4 ).
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind = z2ui5_cx_agent_llm=>cs_kind-config
            text = |no HTTP client for { is_request-url } (return code { sy-subrc })|.
      ENDIF.
    ENDIF.

    lo_client->request->set_method( 'POST' ).
    LOOP AT is_request-t_header INTO DATA(ls_header).
      IF to_lower( ls_header-name ) = `content-type`.
        lo_client->request->set_content_type( ls_header-value ).
      ELSE.
        lo_client->request->set_header_field( name  = ls_header-name
                                              value = ls_header-value ).
      ENDIF.
    ENDLOOP.
    lo_client->request->set_cdata( is_request-body ).

    lo_client->send( EXPORTING
                       timeout                    = is_request-timeout
                     EXCEPTIONS
                       http_communication_failure = 1
                       http_invalid_state         = 2
                       http_processing_failed     = 3
                       http_invalid_timeout       = 4
                       OTHERS                     = 5 ).
    IF sy-subrc = 0.
      lo_client->receive( EXCEPTIONS
                            http_communication_failure = 1
                            http_invalid_state         = 2
                            http_processing_failed     = 3
                            OTHERS                     = 4 ).
    ENDIF.
    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING message = lv_message ).
      lo_client->close( ).
      fail( |no answer from the language model service - { lv_message }| ).
    ENDIF.

    lo_client->response->get_status( IMPORTING code   = result-status
                                               reason = result-reason ).
    result-body = lo_client->response->get_cdata( ).
    lo_client->close( ).

  ENDMETHOD.

ENDCLASS.
