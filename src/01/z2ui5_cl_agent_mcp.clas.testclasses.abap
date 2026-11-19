CLASS ltcl_fit DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_mcp DEFINITION LOCAL FRIENDS ltcl_fit.

"! In-memory draft store - see z2ui5_cl_agent_session's test include.
CLASS ltd_draft_store DEFINITION FINAL FOR TESTING.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_ui5_draft_store.

    TYPES temp1_d2ae6e4954 TYPE STANDARD TABLE OF z2ui5_if_ui5_draft_store=>ty_s_db WITH DEFAULT KEY.
DATA mt_db TYPE temp1_d2ae6e4954.

ENDCLASS.


CLASS ltd_draft_store IMPLEMENTATION.

  METHOD z2ui5_if_ui5_draft_store~count_entries.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~count_entries_total.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~create.
    DATA temp1 TYPE z2ui5_t_01.

    DELETE mt_db WHERE id = draft-id.

    CLEAR temp1.
    temp1-id = draft-id.
    temp1-id_prev = draft-id_prev.
    temp1-id_prev_app = draft-id_prev_app.
    temp1-id_prev_app_stack = draft-id_prev_app_stack.
    temp1-data = model_xml.
    INSERT temp1 INTO TABLE mt_db.

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~read_draft.

    READ TABLE mt_db INTO result WITH KEY id = id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING
          val = `NO_DRAFT_ENTRY_OF_PREVIOUS_REQUEST_FOUND`.
    ENDIF.

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~read_info.

    DATA ls_db TYPE z2ui5_t_01.
    ls_db = z2ui5_if_ui5_draft_store~read_draft( id ).
    CLEAR result.
    result-id = ls_db-id.
    result-id_prev = ls_db-id_prev.
    result-id_prev_app = ls_db-id_prev_app.
    result-id_prev_app_stack = ls_db-id_prev_app_stack.

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~check_exists.
    DATA temp2 LIKE sy-subrc.
    DATA temp1 TYPE xsdboolean.
    READ TABLE mt_db WITH KEY id = id TRANSPORTING NO FIELDS.
    temp2 = sy-subrc.

    temp1 = boolc( temp2 = 0 ).
    result = temp1. "#EC CI_SORTSEQ
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~cleanup.
    " nothing expires within a test
  ENDMETHOD.

ENDCLASS.


"! The protocol: JSON-RPC 2.0 over MCP Streamable HTTP, without a server
"! object (handle( )). DANGEROUS: initialize writes an MCP session, a tool
"! call a session and the audit log - teardown deletes them and restores
"! the settings.
CLASS ltcl_mcp DEFINITION FINAL
  FOR TESTING RISK LEVEL DANGEROUS DURATION MEDIUM.

  PRIVATE SECTION.
    DATA mo_store   TYPE REF TO ltd_draft_store.
    DATA mt_setting TYPE z2ui5_cl_agent_settings=>ty_t_setting.
    DATA mv_start   TYPE timestampl.

    METHODS setup.
    METHODS teardown.

    METHODS get_not_allowed     FOR TESTING.
    METHODS content_type        FOR TESTING.
    METHODS cross_origin        FOR TESTING.
    METHODS delete_cross_origin FOR TESTING.
    METHODS long_session_id     FOR TESTING.
    METHODS parse_error         FOR TESTING.
    METHODS invalid_request     FOR TESTING.
    METHODS invalid_id          FOR TESTING.
    METHODS notification        FOR TESTING.
    METHODS ping                FOR TESTING.
    METHODS initialize          FOR TESTING RAISING cx_static_check.
    METHODS version_negotiation FOR TESTING.
    METHODS tools_list          FOR TESTING.
    METHODS unknown_method      FOR TESTING.
    METHODS unknown_tool        FOR TESTING.
    METHODS tool_argument_types FOR TESTING.
    METHODS unknown_argument    FOR TESTING.
    METHODS tool_call_session   FOR TESTING RAISING cx_static_check.
    METHODS batch               FOR TESTING.
    METHODS batch_audit         FOR TESTING.

    METHODS post
      IMPORTING
        body          TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_mcp=>ty_s_response.

    METHODS rpc
      IMPORTING
        body          TYPE string
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_if_ajson.

ENDCLASS.


CLASS ltcl_mcp IMPLEMENTATION.

  METHOD setup.

    CREATE OBJECT mo_store.
    z2ui5_cl_ui5_srv_draft=>set_instance( mo_store ).
    mv_start = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    SELECT * FROM z2ui5_t_17 INTO TABLE mt_setting.
    DELETE FROM z2ui5_t_17.
    z2ui5_cl_agent_settings=>set_enabled( abap_true ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD teardown.

    DATA li_default TYPE REF TO z2ui5_if_ui5_draft_store.

    DELETE FROM z2ui5_t_15 WHERE uname = sy-uname AND created_at >= mv_start.
    DELETE FROM z2ui5_t_16 WHERE uname = sy-uname AND created_at >= mv_start.
    DELETE FROM z2ui5_t_14 WHERE uname = sy-uname AND timestampl >= mv_start AND mcp_client = 'unit-test 1.0'.
    DELETE FROM z2ui5_t_17.
    INSERT z2ui5_t_17 FROM TABLE mt_setting.
    COMMIT WORK.
    z2ui5_cl_agent_settings=>refresh( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( li_default ).

  ENDMETHOD.

  METHOD post.

    DATA temp3 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA temp1 TYPE REF TO z2ui5_cl_agent_mcp.
    CLEAR temp3.
    temp3-method = `POST`.
    temp3-body = body.
    temp3-content_type = `application/json`.

    CREATE OBJECT temp1 TYPE z2ui5_cl_agent_mcp.
    result = temp1->handle( temp3 ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD rpc.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    ls_response = post( body ).
    cl_abap_unit_assert=>assert_equals( exp = 200
                                        act = ls_response-status ).
    TRY.
        result = z2ui5_cl_ajson=>parse( ls_response-body ).
      CATCH cx_root.
        cl_abap_unit_assert=>fail( |no JSON: { ls_response-body }| ).
    ENDTRY.

  ENDMETHOD.

  METHOD get_not_allowed.

    DATA temp4 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp1 TYPE REF TO z2ui5_cl_agent_mcp.
    FIELD-SYMBOLS <temp5> LIKE LINE OF ls_response-t_header.
    DATA temp6 LIKE sy-tabix.
    CLEAR temp4.
    temp4-method = `GET`.


    CREATE OBJECT temp1 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp1->handle( temp4 ).
    cl_abap_unit_assert=>assert_equals( exp = 405
                                        act = ls_response-status ).


    temp6 = sy-tabix.
    READ TABLE ls_response-t_header WITH KEY name = `Allow` ASSIGNING <temp5>.
    sy-tabix = temp6.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = `POST, DELETE`
                                        act = <temp5>-value ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD content_type.

    DATA temp7 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp3 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA temp8 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA temp2 TYPE REF TO z2ui5_cl_agent_mcp.
    CLEAR temp7.
    temp7-method = `POST`.
    temp7-body = `{}`.
    temp7-content_type = `text/plain`.


    CREATE OBJECT temp3 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp3->handle( temp7 ).
    cl_abap_unit_assert=>assert_equals( exp = 415
                                        act = ls_response-status ).

    " a simple request of a page - the media type is text/plain

    CLEAR temp8.
    temp8-method = `POST`.
    temp8-body = `{}`.
    temp8-content_type = `text/plain;application/json`.

    CREATE OBJECT temp2 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp2->handle( temp8 ).
    cl_abap_unit_assert=>assert_equals( exp = 415
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD cross_origin.

    " a page of another host must not drive the endpoint with the user's cookies
    DATA temp9 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp4 TYPE REF TO z2ui5_cl_agent_mcp.
    CLEAR temp9.
    temp9-method = `POST`.
    temp9-body = `{"jsonrpc":"2.0","id":1,"method":"ping"}`.
    temp9-content_type = `application/json`.
    temp9-origin = `https://evil.example`.
    temp9-host = `sap.example:443`.


    CREATE OBJECT temp4 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp4->handle( temp9 ).
    cl_abap_unit_assert=>assert_equals( exp = 403
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD delete_cross_origin.

    DATA ls_init TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA lv_session TYPE z2ui5_cl_agent_mcp=>ty_s_header-value.
    FIELD-SYMBOLS <temp3> LIKE LINE OF ls_init-t_header.
    DATA temp4 LIKE sy-tabix.
    DATA temp10 TYPE z2ui5_t_15-id.
    DATA lv_id LIKE temp10.
    DATA temp11 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp5 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA lv_client TYPE z2ui5_t_15-mcp_client.
    ls_init = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                          `"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).



    temp4 = sy-tabix.
    READ TABLE ls_init-t_header WITH KEY name = `Mcp-Session-Id` ASSIGNING <temp3>.
    sy-tabix = temp4.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_session = <temp3>-value. "#EC CI_SORTSEQ

    temp10 = lv_session.

    lv_id = temp10.

    " a page of another host ends no MCP session either

    CLEAR temp11.
    temp11-method = `DELETE`.
    temp11-session_id = lv_session.
    temp11-origin = `https://evil.example`.
    temp11-host = `sap.example:443`.


    CREATE OBJECT temp5 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp5->handle( temp11 ).
    cl_abap_unit_assert=>assert_equals( exp = 403
                                        act = ls_response-status ).

    SELECT SINGLE mcp_client FROM z2ui5_t_15 INTO lv_client WHERE id = lv_id .
    cl_abap_unit_assert=>assert_subrc( exp = 0 ).
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

  ENDMETHOD.

  METHOD long_session_id.

    DATA lv_count TYPE i.

    DATA ls_init TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA lv_session TYPE z2ui5_cl_agent_mcp=>ty_s_header-value.
    FIELD-SYMBOLS <temp5> LIKE LINE OF ls_init-t_header.
    DATA temp6 LIKE sy-tabix.
    DATA temp12 TYPE z2ui5_t_15-id.
    DATA lv_id LIKE temp12.
    DATA temp13 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_long TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp8 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA temp14 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA temp7 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA lv_client TYPE z2ui5_t_15-mcp_client.
    ls_init = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                          `"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).



    temp6 = sy-tabix.
    READ TABLE ls_init-t_header WITH KEY name = `Mcp-Session-Id` ASSIGNING <temp5>.
    sy-tabix = temp6.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_session = <temp5>-value. "#EC CI_SORTSEQ

    temp12 = lv_session.

    lv_id = temp12.

    " an id longer than the column is none: it names no client in the audit
    " log - it is no session at all, answered 404 as the spec says ...

    CLEAR temp13.
    temp13-method = `POST`.
    temp13-content_type = `application/json`.
    temp13-session_id = |{ lv_session }X|.
    temp13-body = `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":` && `{"name":"app_list","arguments":{"filter":"long_session_id"}}}`.


    CREATE OBJECT temp8 TYPE z2ui5_cl_agent_mcp.
    ls_long = temp8->handle( temp13 ).
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 404
                                        act = ls_long-status ).
    SELECT COUNT(*) FROM z2ui5_t_14 INTO lv_count
      WHERE uname = sy-uname AND operation = 'app_list' AND mcp_client = 'unit-test 1.0' AND timestampl >= mv_start
      .
    DELETE FROM z2ui5_t_14 WHERE uname = sy-uname AND operation = 'app_list' AND timestampl >= mv_start.
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = lv_count ).

    " ... and ends no session of its first 32 characters

    CLEAR temp14.
    temp14-method = `DELETE`.
    temp14-session_id = |{ lv_session }X|.

    CREATE OBJECT temp7 TYPE z2ui5_cl_agent_mcp.
    temp7->handle( temp14 ).

    SELECT SINGLE mcp_client FROM z2ui5_t_15 INTO lv_client WHERE id = lv_id .
    cl_abap_unit_assert=>assert_subrc( exp = 0 ).
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

  ENDMETHOD.

  METHOD parse_error.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    ls_response = post( `{not json` ).
    cl_abap_unit_assert=>assert_equals( exp = 400
                                        act = ls_response-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"code":-32700*`
                                         act = ls_response-body ).

  ENDMETHOD.

  METHOD invalid_request.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    lo_json = rpc( `{"jsonrpc":"1.0","id":7,"method":"ping"}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32600
                                        act = lo_json->get_integer( `/error/code` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 7
                                        act = lo_json->get_integer( `/id` ) ).

  ENDMETHOD.

  METHOD invalid_id.

    " an id that is neither a string nor a number makes no notification of
    " the request: it is answered - with id null - and nothing runs
    DATA temp8 TYPE string_table.
    DATA temp15 LIKE temp8.
    DATA lv_id LIKE LINE OF temp15.
      DATA lo_json TYPE REF TO z2ui5_if_ajson.
    CLEAR temp8.
    INSERT `null` INTO TABLE temp8.
    INSERT `true` INTO TABLE temp8.
    INSERT `{"n":1}` INTO TABLE temp8.
    INSERT `[1]` INTO TABLE temp8.

    temp15 = temp8.

    LOOP AT temp15 INTO lv_id.

      lo_json = rpc( |\{"jsonrpc":"2.0","id":{ lv_id },"method":"tools/call","params":\{"name":"app_list"\}\}| ).
      cl_abap_unit_assert=>assert_equals( exp = -32600
                                          act = lo_json->get_integer( `/error/code` )
                                          msg = |id { lv_id }| ).
      cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_ajson_types=>node_type-null
                                          act = lo_json->get_node_type( `/id` ) ).
      cl_abap_unit_assert=>assert_false( lo_json->exists( `/result` ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD notification.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    ls_response = post( `{"jsonrpc":"2.0","method":"notifications/initialized"}` ).
    cl_abap_unit_assert=>assert_equals( exp = 202
                                        act = ls_response-status ).
    cl_abap_unit_assert=>assert_initial( ls_response-body ).

  ENDMETHOD.

  METHOD ping.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    FIELD-SYMBOLS <temp16> LIKE LINE OF ls_response-t_header.
    DATA temp17 LIKE sy-tabix.
    ls_response = post( `{"jsonrpc":"2.0","id":"p-1","method":"ping"}` ).
    cl_abap_unit_assert=>assert_equals( exp = `{"jsonrpc":"2.0","id":"p-1","result":{}}`
                                        act = ls_response-body ).


    temp17 = sy-tabix.
    READ TABLE ls_response-t_header WITH KEY name = `Content-Type` ASSIGNING <temp16>.
    sy-tabix = temp17.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = `application/json`
                                        act = <temp16>-value ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD initialize.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp18 TYPE REF TO z2ui5_if_ajson.
    DATA lo_json LIKE temp18.
    DATA lv_session TYPE z2ui5_cl_agent_mcp=>ty_s_header-value.
    FIELD-SYMBOLS <temp10> LIKE LINE OF ls_response-t_header.
    DATA temp11 LIKE sy-tabix.
    DATA temp19 TYPE z2ui5_t_15-id.
    DATA lv_id LIKE temp19.
    DATA lv_client TYPE z2ui5_t_15-mcp_client.
    DATA temp20 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA temp12 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA temp21 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA temp13 TYPE REF TO z2ui5_cl_agent_mcp.
    ls_response = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                              `"capabilities":{},"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).

    temp18 ?= z2ui5_cl_ajson=>parse( ls_response-body ).

    lo_json = temp18.
    cl_abap_unit_assert=>assert_equals( exp = `2025-06-18`
                                        act = lo_json->get_string( `/result/protocolVersion` ) ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_mcp=>c_server_name
                                        act = lo_json->get_string( `/result/serverInfo/name` ) ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_ajson_types=>node_type-object
                                        act = lo_json->get_node_type( `/result/capabilities/tools` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*The endpoint is enabled.*`
                                         act = lo_json->get_string( `/result/instructions` ) ).

    " the MCP session names the client in the audit log of later calls



    temp11 = sy-tabix.
    READ TABLE ls_response-t_header WITH KEY name = `Mcp-Session-Id` ASSIGNING <temp10>.
    sy-tabix = temp11.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_session = <temp10>-value. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_not_initial( lv_session ).

    temp19 = lv_session.

    lv_id = temp19.

    SELECT SINGLE mcp_client FROM z2ui5_t_15 INTO lv_client WHERE id = lv_id .
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

    " ... and DELETE ends it

    CLEAR temp20.
    temp20-method = `DELETE`.
    temp20-session_id = lv_session.

    CREATE OBJECT temp12 TYPE z2ui5_cl_agent_mcp.
    temp12->handle( temp20 ).
    SELECT SINGLE mcp_client FROM z2ui5_t_15 INTO lv_client WHERE id = lv_id .
    cl_abap_unit_assert=>assert_subrc( exp = 4 ).
    " a request on the ended session is a 404 - the client starts anew

    CLEAR temp21.
    temp21-method = `POST`.
    temp21-content_type = `application/json`.
    temp21-session_id = lv_session.
    temp21-body = `{"jsonrpc":"2.0","id":9,"method":"ping"}`.

    CREATE OBJECT temp13 TYPE z2ui5_cl_agent_mcp.
    cl_abap_unit_assert=>assert_equals(
        exp = 404
        act = temp13->handle( temp21 )-status ).

  ENDMETHOD.

  METHOD version_negotiation.

    " an unknown revision is answered with the newest this endpoint speaks
    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    TYPES temp2 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_version TYPE temp2.
    FIELD-SYMBOLS <temp22> LIKE LINE OF lt_version.
    DATA temp23 LIKE sy-tabix.
    DATA temp24 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp9 TYPE REF TO z2ui5_cl_agent_mcp.
    lo_json = rpc( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}` ).


    SPLIT z2ui5_cl_agent_mcp=>c_protocol_versions AT `,` INTO TABLE lt_version.


    temp23 = sy-tabix.
    READ TABLE lt_version INDEX 1 ASSIGNING <temp22>.
    sy-tabix = temp23.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = <temp22>
                                        act = lo_json->get_string( `/result/protocolVersion` ) ).
    " an unsupported version header is a bad request

    CLEAR temp24.
    temp24-method = `POST`.
    temp24-body = `{"jsonrpc":"2.0","id":1,"method":"ping"}`.
    temp24-content_type = `application/json`.
    temp24-protocol_version = `1999-01-01`.


    CREATE OBJECT temp9 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp9->handle( temp24 ).
    cl_abap_unit_assert=>assert_equals( exp = 400
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD tools_list.

    DATA lt_name TYPE string_table.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    DATA lv_count TYPE i.
    DATA temp25 TYPE string_table.
    lo_json = rpc( `{"jsonrpc":"2.0","id":2,"method":"tools/list"}` ).

    lv_count = lines( lo_json->members( `/result/tools` ) ).
    DO lv_count TIMES.
      INSERT lo_json->get_string( |/result/tools/{ sy-index }/name| ) INTO TABLE lt_name.
      cl_abap_unit_assert=>assert_equals( exp = `object`
                                          act = lo_json->get_string( |/result/tools/{ sy-index }/inputSchema/type| ) ).
    ENDDO.

    CLEAR temp25.
    INSERT `app_list` INTO TABLE temp25.
    INSERT `app_start` INTO TABLE temp25.
    INSERT `app_describe` INTO TABLE temp25.
    INSERT `app_act` INTO TABLE temp25.
    cl_abap_unit_assert=>assert_equals( exp = temp25
                                        act = lt_name ).
    cl_abap_unit_assert=>assert_equals( exp = `app`
                                        act = lo_json->get_string( `/result/tools/2/inputSchema/required/1` ) ).

  ENDMETHOD.

  METHOD unknown_method.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    lo_json = rpc( `{"jsonrpc":"2.0","id":3,"method":"resources/list"}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32601
                                        act = lo_json->get_integer( `/error/code` ) ).

  ENDMETHOD.

  METHOD unknown_tool.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    lo_json = rpc( `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"run_app","arguments":{}}}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32602
                                        act = lo_json->get_integer( `/error/code` ) ).

  ENDMETHOD.

  METHOD tool_argument_types.

    " a schema violation is a tool error the agent can read, not a protocol error
    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    lo_json = rpc( `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"app_start","arguments":{"app":42}}}` ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_json->get_boolean( `/result/isError` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `app must be a string`
                                        act = lo_json->get_string( `/result/content/1/text` ) ).

  ENDMETHOD.

  METHOD unknown_argument.

    " refused, not dropped: app_act { value: {...}, event } fired the
    " event without the edits
    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    DATA temp2 TYPE xsdboolean.
    lo_json = rpc( `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"app_start","arguments":` &&
                         `{"app":"z2ui5_cl_agent_demo","valuse":{"NAME":"x"}}}}` ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_json->get_boolean( `/result/isError` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `app_start has no argument 'valuse' - its arguments: app values max_rows`
                                        act = lo_json->get_string( `/result/content/1/text` ) ).
    " an unknown tool's name is echoed at most 80 characters
    lo_json = rpc( |\{"jsonrpc":"2.0","id":6,"method":"tools/call","params":\{"name":"{ repeat( val = `x`
                                                                                            occ = 5000 ) }","arguments":\{\}\}\}| ).

    temp2 = boolc( strlen( lo_json->get_string( `/error/message` ) ) < 300 ).
    cl_abap_unit_assert=>assert_true( temp2 ).

  ENDMETHOD.

  METHOD tool_call_session.

    DATA lo_init TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA lv_mcp_session TYPE z2ui5_cl_agent_mcp=>ty_s_header-value.
    FIELD-SYMBOLS <temp14> LIKE LINE OF lo_init-t_header.
    DATA temp15 LIKE sy-tabix.
    DATA temp27 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp10 TYPE REF TO z2ui5_cl_agent_mcp.
    DATA temp28 TYPE REF TO z2ui5_if_ajson.
    DATA lo_json LIKE temp28.
    DATA temp29 TYPE REF TO z2ui5_if_ajson.
    DATA lo_snap LIKE temp29.
    DATA temp30 TYPE z2ui5_t_14-session_id.
    DATA lv_session LIKE temp30.
    DATA lv_client TYPE z2ui5_t_14-mcp_client.
    lo_init = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                          `"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).



    temp15 = sy-tabix.
    READ TABLE lo_init-t_header WITH KEY name = `Mcp-Session-Id` ASSIGNING <temp14>.
    sy-tabix = temp15.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_mcp_session = <temp14>-value. "#EC CI_SORTSEQ


    CLEAR temp27.
    temp27-method = `POST`.
    temp27-content_type = `application/json; charset=utf-8`.
    temp27-session_id = lv_mcp_session.
    temp27-body = `{"jsonrpc":"2.0","id":6,"method":"tools/call","params":` && `{"name":"app_start","arguments":{"app":"z2ui5_cl_agent_demo","max_rows":1}}}`.


    CREATE OBJECT temp10 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp10->handle( temp27 ).
    COMMIT WORK.

    temp28 ?= z2ui5_cl_ajson=>parse( ls_response-body ).

    lo_json = temp28.
    cl_abap_unit_assert=>assert_equals( exp = abap_false
                                        act = lo_json->get_boolean( `/result/isError` ) ).

    temp29 ?= z2ui5_cl_ajson=>parse( lo_json->get_string( `/result/content/1/text` ) ).

    lo_snap = temp29.
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_AGENT_DEMO`
                                        act = lo_snap->get_string( `/app` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_snap->members( `/tables/1/rows` ) ) ).

    " the audit entry carries the client of the MCP session

    temp30 = lo_snap->get_string( `/session` ).

    lv_session = temp30.

    SELECT SINGLE mcp_client FROM z2ui5_t_14 INTO lv_client WHERE session_id = lv_session AND operation = 'app_start' . "#EC CI_NOORDER
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

  ENDMETHOD.

  METHOD batch_audit.

    DATA lv_count TYPE i.
    DATA lv_body TYPE string.

    " every call of a batch is audited: the roundtrip of a later call (here
    " app_start) rolls back what the earlier ones left uncommitted
    DATA lo_init TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA lv_mcp_session TYPE z2ui5_cl_agent_mcp=>ty_s_header-value.
    FIELD-SYMBOLS <temp16> LIKE LINE OF lo_init-t_header.
    DATA temp17 LIKE sy-tabix.
    DATA temp31 TYPE z2ui5_cl_agent_mcp=>ty_s_request.
    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    DATA temp11 TYPE REF TO z2ui5_cl_agent_mcp.
    lo_init = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",` &&
                          `"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).



    temp17 = sy-tabix.
    READ TABLE lo_init-t_header WITH KEY name = `Mcp-Session-Id` ASSIGNING <temp16>.
    sy-tabix = temp17.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_mcp_session = <temp16>-value. "#EC CI_SORTSEQ
    lv_body = `[{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"app_list","arguments":{}}},` &&
              `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":` &&
              `{"name":"app_start","arguments":{"app":"z2ui5_cl_agent_demo","max_rows":1}}}]`.

    CLEAR temp31.
    temp31-method = `POST`.
    temp31-content_type = `application/json`.
    temp31-session_id = lv_mcp_session.
    temp31-body = lv_body.


    CREATE OBJECT temp11 TYPE z2ui5_cl_agent_mcp.
    ls_response = temp11->handle( temp31 ).
    COMMIT WORK.
    cl_abap_unit_assert=>assert_char_cp( exp = `*"id":3*`
                                         act = ls_response-body ).
    SELECT COUNT(*) FROM z2ui5_t_14 INTO lv_count
      WHERE uname = sy-uname AND operation = 'app_list' AND mcp_client = 'unit-test 1.0' AND timestampl >= mv_start
      .
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lv_count ).

  ENDMETHOD.

  METHOD batch.

    DATA ls_response TYPE z2ui5_cl_agent_mcp=>ty_s_response.
    ls_response = post( `[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},` &&
                              `{"jsonrpc":"2.0","id":2,"method":"ping"}]` ).
    cl_abap_unit_assert=>assert_equals( exp = `[{"jsonrpc":"2.0","id":1,"result":{}},{"jsonrpc":"2.0","id":2,"result":{}}]`
                                        act = ls_response-body ).

  ENDMETHOD.

ENDCLASS.


"! fit_snapshot: a snapshot answer within c_answer_budget - long values cut
"! and read-only, rows dropped from the end, the JSON whole.
CLASS ltcl_fit DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    METHODS fits FOR TESTING.

ENDCLASS.


CLASS ltcl_fit IMPLEMENTATION.

  METHOD fits.

    DATA lt_row TYPE string_table.

    DATA lv_cell TYPE string.
      DATA temp32 TYPE string.
      DATA temp18 LIKE LINE OF lt_row.
    DATA lv_json TYPE string.
    DATA lv_fitted TYPE string.
    DATA lv_note TYPE string.
    DATA temp3 TYPE xsdboolean.
        DATA temp33 TYPE REF TO z2ui5_if_ajson.
        DATA lo_json LIKE temp33.
    DATA temp4 TYPE xsdboolean.
    lv_cell = repeat( val = `c`
                            occ = 3000 ).
    DO 300 TIMES.

      IF sy-index = 1.
        temp32 = lv_cell.
      ELSE.
        temp32 = repeat( val = `n` occ = 300 ).
      ENDIF.

      temp18 = |\{"NOTE":"{ temp32 }","QTY":{ sy-index }\}|.
      INSERT temp18 INTO TABLE lt_row.
    ENDDO.

    lv_json = |\{"snapshotVersion":1,"fields":[\{"id":"f1","value":"{ repeat( val = `a`
                                                                               occ = 120000 ) }","editable":true\},| &&
                    |\{"id":"f2","value":"short","editable":true\}],"actions":[\{"id":"a1"\}],| &&
                    |"tables":[\{"id":"t1","rowCount":300,"rows":[{ concat_lines_of( table = lt_row
                                                                          sep   = `,` ) }],| &&
                    |"truncated":false,"editableCells":["NOTE","QTY"]\}],"messages":[\{"text":"PONG"\}]\}|.



    z2ui5_cl_agent_mcp=>fit_snapshot( EXPORTING json   = lv_json
                                      IMPORTING result = lv_fitted
                                                note   = lv_note ).

    temp3 = boolc( strlen( lv_fitted ) <= z2ui5_cl_agent_mcp=>c_answer_budget ).
    cl_abap_unit_assert=>assert_true( temp3 ).
    TRY.

        temp33 ?= z2ui5_cl_ajson=>parse( lv_fitted ).

        lo_json = temp33.
      CATCH cx_root.
        cl_abap_unit_assert=>fail( `the fitted snapshot is no JSON` ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( exp = 2003
                                        act = strlen( lo_json->get_string( `/fields/1/value` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false
                                        act = lo_json->get_boolean( `/fields/1/editable` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_json->get_boolean( `/fields/2/editable` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `QTY`
                                        act = lo_json->get_string( `/tables/1/editableCells/1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_json->members( `/tables/1/editableCells` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_json->get_boolean( `/tables/1/truncated` ) ).

    temp4 = boolc( lines( lo_json->members( `/tables/1/rows` ) ) < 300 ).
    cl_abap_unit_assert=>assert_true( temp4 ).
    cl_abap_unit_assert=>assert_equals( exp = `PONG`
                                        act = lo_json->get_string( `/messages/1/text` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*f1 are cut*table t1: cells of NOTE*table t1 shows its first*`
                                         act = lv_note ).

    " a snapshot that fits is the same
    z2ui5_cl_agent_mcp=>fit_snapshot( EXPORTING json   = `{"fields":[]}`
                                      IMPORTING result = lv_fitted
                                                note   = lv_note ).
    cl_abap_unit_assert=>assert_equals( exp = `{"fields":[]}`
                                        act = lv_fitted ).
    cl_abap_unit_assert=>assert_initial( lv_note ).

  ENDMETHOD.

ENDCLASS.
