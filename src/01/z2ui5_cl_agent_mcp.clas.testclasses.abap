"! In-memory draft store - see z2ui5_cl_agent_session's test include.
CLASS ltd_draft_store DEFINITION FINAL FOR TESTING.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_ui5_draft_store.

    DATA mt_db TYPE STANDARD TABLE OF z2ui5_if_ui5_draft_store=>ty_s_db WITH EMPTY KEY.

ENDCLASS.


CLASS ltd_draft_store IMPLEMENTATION.

  METHOD z2ui5_if_ui5_draft_store~count_entries.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~count_entries_total.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~create.

    DELETE mt_db WHERE id = draft-id.
    INSERT VALUE #( id                = draft-id
                    id_prev           = draft-id_prev
                    id_prev_app       = draft-id_prev_app
                    id_prev_app_stack = draft-id_prev_app_stack
                    data              = model_xml ) INTO TABLE mt_db.

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

    DATA(ls_db) = z2ui5_if_ui5_draft_store~read_draft( id ).
    result = VALUE #( id                = ls_db-id
                      id_prev           = ls_db-id_prev
                      id_prev_app       = ls_db-id_prev_app
                      id_prev_app_stack = ls_db-id_prev_app_stack ).

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~check_exists.
    result = xsdbool( line_exists( mt_db[ id = id ] ) ). "#EC CI_SORTSEQ
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
    METHODS parse_error         FOR TESTING.
    METHODS invalid_request     FOR TESTING.
    METHODS notification        FOR TESTING.
    METHODS ping                FOR TESTING.
    METHODS initialize          FOR TESTING.
    METHODS version_negotiation FOR TESTING.
    METHODS tools_list          FOR TESTING.
    METHODS unknown_method      FOR TESTING.
    METHODS unknown_tool        FOR TESTING.
    METHODS tool_argument_types FOR TESTING.
    METHODS tool_call_session   FOR TESTING.
    METHODS batch               FOR TESTING.

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

    mo_store = NEW #( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( mo_store ).
    mv_start = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    SELECT * FROM z2ui5_t_ag_set INTO TABLE @mt_setting.
    DELETE FROM z2ui5_t_ag_set.
    z2ui5_cl_agent_settings=>set_enabled( abap_true ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD teardown.

    DATA li_default TYPE REF TO z2ui5_if_ui5_draft_store.

    DELETE FROM z2ui5_t_ag_mcp WHERE uname = @sy-uname AND created_at >= @mv_start.
    DELETE FROM z2ui5_t_ag_ses WHERE uname = @sy-uname AND created_at >= @mv_start.
    DELETE FROM z2ui5_t_ag_log WHERE uname = @sy-uname AND timestampl >= @mv_start AND mcp_client = 'unit-test 1.0'.
    DELETE FROM z2ui5_t_ag_set.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_setting.
    COMMIT WORK.
    z2ui5_cl_agent_settings=>refresh( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( li_default ).

  ENDMETHOD.

  METHOD post.

    result = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method       = `POST`
                                                         body         = body
                                                         content_type = `application/json` ) ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD rpc.

    DATA(ls_response) = post( body ).
    cl_abap_unit_assert=>assert_equals( exp = 200
                                        act = ls_response-status ).
    TRY.
        result = z2ui5_cl_ajson=>parse( ls_response-body ).
      CATCH cx_root.
        cl_abap_unit_assert=>fail( |no JSON: { ls_response-body }| ).
    ENDTRY.

  ENDMETHOD.

  METHOD get_not_allowed.

    DATA(ls_response) = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method = `GET` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 405
                                        act = ls_response-status ).
    cl_abap_unit_assert=>assert_equals( exp = `POST, DELETE`
                                        act = ls_response-t_header[ name = `Allow` ]-value ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD content_type.

    DATA(ls_response) = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method       = `POST`
                                                                    body         = `{}`
                                                                    content_type = `text/plain` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 415
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD cross_origin.

    " a page of another host must not drive the endpoint with the user's cookies
    DATA(ls_response) = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method       = `POST`
                                                                    body         = `{"jsonrpc":"2.0","id":1,"method":"ping"}`
                                                                    content_type = `application/json`
                                                                    origin       = `https://evil.example`
                                                                    host         = `sap.example:443` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 403
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD parse_error.

    DATA(ls_response) = post( `{not json` ).
    cl_abap_unit_assert=>assert_equals( exp = 400
                                        act = ls_response-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"code":-32700*`
                                         act = ls_response-body ).

  ENDMETHOD.

  METHOD invalid_request.

    DATA(lo_json) = rpc( `{"jsonrpc":"1.0","id":7,"method":"ping"}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32600
                                        act = lo_json->get_integer( `/error/code` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 7
                                        act = lo_json->get_integer( `/id` ) ).

  ENDMETHOD.

  METHOD notification.

    DATA(ls_response) = post( `{"jsonrpc":"2.0","method":"notifications/initialized"}` ).
    cl_abap_unit_assert=>assert_equals( exp = 202
                                        act = ls_response-status ).
    cl_abap_unit_assert=>assert_initial( ls_response-body ).

  ENDMETHOD.

  METHOD ping.

    DATA(ls_response) = post( `{"jsonrpc":"2.0","id":"p-1","method":"ping"}` ).
    cl_abap_unit_assert=>assert_equals( exp = `{"jsonrpc":"2.0","id":"p-1","result":{}}`
                                        act = ls_response-body ).
    cl_abap_unit_assert=>assert_equals( exp = `application/json`
                                        act = ls_response-t_header[ name = `Content-Type` ]-value ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD initialize.

    DATA(ls_response) = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                              `"capabilities":{},"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).
    DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( ls_response-body ) ).
    cl_abap_unit_assert=>assert_equals( exp = `2025-06-18`
                                        act = lo_json->get_string( `/result/protocolVersion` ) ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_mcp=>c_server_name
                                        act = lo_json->get_string( `/result/serverInfo/name` ) ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_ajson_types=>node_type-object
                                        act = lo_json->get_node_type( `/result/capabilities/tools` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*The endpoint is enabled.*`
                                         act = lo_json->get_string( `/result/instructions` ) ).

    " the MCP session names the client in the audit log of later calls
    DATA(lv_session) = ls_response-t_header[ name = `Mcp-Session-Id` ]-value. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_not_initial( lv_session ).
    DATA(lv_id) = CONV z2ui5_t_ag_mcp-id( lv_session ).
    SELECT SINGLE mcp_client FROM z2ui5_t_ag_mcp WHERE id = @lv_id INTO @DATA(lv_client).
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

    " ... and DELETE ends it
    NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method     = `DELETE`
                                                session_id = lv_session ) ).
    SELECT SINGLE mcp_client FROM z2ui5_t_ag_mcp WHERE id = @lv_id INTO @lv_client.
    cl_abap_unit_assert=>assert_subrc( exp = 4 ).

  ENDMETHOD.

  METHOD version_negotiation.

    " an unknown revision is answered with the newest this endpoint speaks
    DATA(lo_json) = rpc( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}` ).
    SPLIT z2ui5_cl_agent_mcp=>c_protocol_versions AT `,` INTO TABLE DATA(lt_version).
    cl_abap_unit_assert=>assert_equals( exp = lt_version[ 1 ]
                                        act = lo_json->get_string( `/result/protocolVersion` ) ).
    " an unsupported version header is a bad request
    DATA(ls_response) = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method           = `POST`
                                                                    body             = `{"jsonrpc":"2.0","id":1,"method":"ping"}`
                                                                    content_type     = `application/json`
                                                                    protocol_version = `1999-01-01` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 400
                                        act = ls_response-status ).

  ENDMETHOD.

  METHOD tools_list.

    DATA lt_name TYPE string_table.

    DATA(lo_json) = rpc( `{"jsonrpc":"2.0","id":2,"method":"tools/list"}` ).
    DATA(lv_count) = lines( lo_json->members( `/result/tools` ) ).
    DO lv_count TIMES.
      INSERT lo_json->get_string( |/result/tools/{ sy-index }/name| ) INTO TABLE lt_name.
      cl_abap_unit_assert=>assert_equals( exp = `object`
                                          act = lo_json->get_string( |/result/tools/{ sy-index }/inputSchema/type| ) ).
    ENDDO.
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `app_list` ) ( `app_start` ) ( `app_describe` ) ( `app_act` ) )
                                        act = lt_name ).
    cl_abap_unit_assert=>assert_equals( exp = `app`
                                        act = lo_json->get_string( `/result/tools/2/inputSchema/required/1` ) ).

  ENDMETHOD.

  METHOD unknown_method.

    DATA(lo_json) = rpc( `{"jsonrpc":"2.0","id":3,"method":"resources/list"}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32601
                                        act = lo_json->get_integer( `/error/code` ) ).

  ENDMETHOD.

  METHOD unknown_tool.

    DATA(lo_json) = rpc( `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"run_app","arguments":{}}}` ).
    cl_abap_unit_assert=>assert_equals( exp = -32602
                                        act = lo_json->get_integer( `/error/code` ) ).

  ENDMETHOD.

  METHOD tool_argument_types.

    " a schema violation is a tool error the agent can read, not a protocol error
    DATA(lo_json) = rpc( `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"app_start","arguments":{"app":42}}}` ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_json->get_boolean( `/result/isError` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `app must be a string`
                                        act = lo_json->get_string( `/result/content/1/text` ) ).

  ENDMETHOD.

  METHOD tool_call_session.

    DATA(lo_init) = post( `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",` &&
                          `"clientInfo":{"name":"unit-test","version":"1.0"}}}` ).
    DATA(lv_mcp_session) = lo_init-t_header[ name = `Mcp-Session-Id` ]-value. "#EC CI_SORTSEQ

    DATA(ls_response) = NEW z2ui5_cl_agent_mcp( )->handle( VALUE #( method       = `POST`
                                                                    content_type = `application/json; charset=utf-8`
                                                                    session_id   = lv_mcp_session
                                                                    body         = `{"jsonrpc":"2.0","id":6,"method":"tools/call","params":` &&
                                                                                   `{"name":"app_start","arguments":{"app":"z2ui5_cl_agent_demo","max_rows":1}}}` ) ).
    COMMIT WORK.
    DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( ls_response-body ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false
                                        act = lo_json->get_boolean( `/result/isError` ) ).
    DATA(lo_snap) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( lo_json->get_string( `/result/content/1/text` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_AGENT_DEMO`
                                        act = lo_snap->get_string( `/app` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_snap->members( `/tables/1/rows` ) ) ).

    " the audit entry carries the client of the MCP session
    DATA(lv_session) = CONV z2ui5_t_ag_log-session_id( lo_snap->get_string( `/session` ) ).
    SELECT SINGLE mcp_client FROM z2ui5_t_ag_log WHERE session_id = @lv_session AND operation = 'app_start' INTO @DATA(lv_client).
    cl_abap_unit_assert=>assert_equals( exp = `unit-test 1.0`
                                        act = lv_client ).

  ENDMETHOD.

  METHOD batch.

    DATA(ls_response) = post( `[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},` &&
                              `{"jsonrpc":"2.0","id":2,"method":"ping"}]` ).
    cl_abap_unit_assert=>assert_equals( exp = `[{"jsonrpc":"2.0","id":1,"result":{}},{"jsonrpc":"2.0","id":2,"result":{}}]`
                                        act = ls_response-body ).

  ENDMETHOD.

ENDCLASS.
