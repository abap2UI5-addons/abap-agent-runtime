"! ABAP Cloud transport of the language model call (z2ui5_if_agent_llm_http):
"! cl_web_http_client_manager with an HTTP destination from a
"! communication arrangement (destination = SCENARIO/SERVICE_ID or
"! SCENARIO/SERVICE_ID/COMM_SYSTEM - URL, TLS and the outbound logon come
"! from the arrangement) or from the URL itself.
"! z2ui5_cl_agent_llm=&gt;get_http( ) creates it - nothing else does.
CLASS z2ui5_cl_agent_llm_cloud DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm_http.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_llm_cloud IMPLEMENTATION.

  METHOD z2ui5_if_agent_llm_http~post.

    DATA lo_destination TYPE REF TO if_http_destination.
    DATA lt_part TYPE string_table.

    TRY.
        IF is_request-destination IS NOT INITIAL.
          SPLIT is_request-destination AT `/` INTO TABLE lt_part.
          lo_destination = cl_http_destination_provider=>create_by_comm_arrangement(
                               comm_scenario  = CONV #( VALUE string( lt_part[ 1 ] OPTIONAL ) )
                               service_id     = CONV #( VALUE string( lt_part[ 2 ] OPTIONAL ) )
                               comm_system_id = CONV #( VALUE string( lt_part[ 3 ] OPTIONAL ) ) ).
        ELSE.
          lo_destination = cl_http_destination_provider=>create_by_url( is_request-url ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_destination).
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind     = z2ui5_cx_agent_llm=>cs_kind-config
            text     = |no HTTP destination for the language model - { lx_destination->get_text( ) }|
            previous = lx_destination.
    ENDTRY.

    TRY.
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).
        DATA(lo_request) = lo_client->get_http_request( ).
        IF is_request-destination IS NOT INITIAL AND is_request-url IS NOT INITIAL.
          lo_request->set_uri_path( is_request-url ).
        ENDIF.
        LOOP AT is_request-t_header INTO DATA(ls_header).
          lo_request->set_header_field( i_name  = ls_header-name
                                        i_value = ls_header-value ).
        ENDLOOP.
        lo_request->set_text( is_request-body ).
        DATA(lo_response) = lo_client->execute( i_method  = if_web_http_client=>post
                                                i_timeout = is_request-timeout ).
        DATA(ls_status) = lo_response->get_status( ).
        result-status = ls_status-code.
        result-reason = ls_status-reason.
        result-body = lo_response->get_text( ).
        lo_client->close( ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind      = z2ui5_cx_agent_llm=>cs_kind-http
            text      = |no answer from the language model service - { lx->get_text( ) }|
            retryable = abap_true
            previous  = lx.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
