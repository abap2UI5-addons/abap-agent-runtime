"! The MCP endpoint of the agent addon: JSON-RPC 2.0 over the "Streamable
"! HTTP" transport of the Model Context Protocol, answered with plain JSON
"! (one POST, one application/json response - no event stream needed).
"!
"!   POST  initialize                 protocol version negotiation,
"!                                    serverInfo, capabilities.tools; answers
"!                                    an Mcp-Session-Id header
"!         notifications/*            202, no body
"!         ping                       {}
"!         tools/list                 app_list, app_start, app_describe,
"!                                    app_act with their JSON Schemas
"!         tools/call                 z2ui5_cl_agent_session
"!   GET   405 (no server-initiated stream)
"!   DELETE                           ends the MCP session (Mcp-Session-Id)
"!
"! Authentication is the SAP logon of the HTTP request - basic, OAuth,
"! certificates, principal propagation, whatever the ICF node or the HTTP
"! service is configured for. Nothing here authenticates or switches
"! users: every call runs as sy-uname, and so does the app.
"!
"! The two entry classes are thin: z2ui5_cl_agent_http (ABAP Standard,
"! if_http_extension, ICF node /sap/bc/z2ui5_agent) and
"! z2ui5_cl_agent_http_cloud (ABAP Cloud, if_http_service_extension) both
"! call run( ). handle( ) is the whole protocol without a server object.
CLASS z2ui5_cl_agent_mcp DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_server_name TYPE string VALUE `abap2ui5-agent`.
    CONSTANTS c_server_version TYPE string VALUE `1.0.0`.

    "! The MCP revisions this endpoint speaks, newest first - it uses
    "! nothing (tools, JSON responses) that differs between them.
    CONSTANTS c_protocol_versions TYPE string VALUE `2025-11-25,2025-06-18,2025-03-26,2024-11-05`.

    TYPES:
      BEGIN OF ty_s_header,
        name  TYPE string,
        value TYPE string,
      END OF ty_s_header.
    TYPES ty_t_header TYPE STANDARD TABLE OF ty_s_header WITH EMPTY KEY.

    TYPES:
      "! The parts of an HTTP request the protocol reads. Header values as
      "! sent, empty when absent.
      BEGIN OF ty_s_request,
        method           TYPE string,
        body             TYPE string,
        content_type     TYPE string,
        origin           TYPE string,
        referer          TYPE string,
        host             TYPE string,
        session_id       TYPE string,
        protocol_version TYPE string,
      END OF ty_s_request.

    TYPES:
      BEGIN OF ty_s_response,
        status   TYPE i,
        reason   TYPE string,
        body     TYPE string,
        t_header TYPE ty_t_header,
      END OF ty_s_response.

    "! The HTTP entry: on ABAP Standard pass the ICF server object
    "! (if_http_extension~handle_request), on ABAP Cloud request and
    "! response (if_http_service_extension~handle_request).
    CLASS-METHODS run
      IMPORTING
        server TYPE REF TO object OPTIONAL
        req    TYPE REF TO object OPTIONAL
        res    TYPE REF TO object OPTIONAL
          PREFERRED PARAMETER server.

    "! One HTTP request of the protocol -&gt; its response.
    METHODS handle
      IMPORTING
        is_request    TYPE ty_s_request
      RETURNING
        VALUE(result) TYPE ty_s_response.

    "! The tools and their input schemas, as the result of tools/list.
    CLASS-METHODS get_tools
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF cs_error,
        parse            TYPE i VALUE -32700,
        invalid_request  TYPE i VALUE -32600,
        method_not_found TYPE i VALUE -32601,
        invalid_params   TYPE i VALUE -32602,
        internal         TYPE i VALUE -32603,
      END OF cs_error.

    DATA ms_request TYPE ty_s_request.
    DATA mv_client TYPE string.
    DATA mt_header TYPE ty_t_header.

    METHODS message
      IMPORTING
        io_json       TYPE REF TO z2ui5_if_ajson
        path          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS initialize
      IMPORTING
        io_json       TYPE REF TO z2ui5_if_ajson
        path          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS tools_call
      IMPORTING
        io_json       TYPE REF TO z2ui5_if_ajson
        path          TYPE string
      EXPORTING
        error_code    TYPE i
        error_text    TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS client_of_session.

    CLASS-METHODS rpc_result
      IMPORTING
        id            TYPE string
        result        TYPE string
      RETURNING
        VALUE(rv_out) TYPE string.

    CLASS-METHODS rpc_error
      IMPORTING
        id            TYPE string
        code          TYPE i
        text          TYPE string
      RETURNING
        VALUE(rv_out) TYPE string.

    CLASS-METHODS tool_result
      IMPORTING
        text          TYPE string
        is_error      TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS http_error
      IMPORTING
        status        TYPE i
        reason        TYPE string
        code          TYPE i
        text          TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_response.

    CLASS-METHODS check_version
      IMPORTING
        version       TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

ENDCLASS.


CLASS z2ui5_cl_agent_mcp IMPLEMENTATION.

  METHOD run.

    DATA lo_http TYPE REF TO z2ui5_cl_ui5_util_http.
    DATA ls_response TYPE ty_s_response.

    lo_http = COND #( WHEN server IS BOUND
                      THEN z2ui5_cl_ui5_util_http=>factory( server )
                      ELSE z2ui5_cl_ui5_util_http=>factory_cloud( req = req
                                                                  res = res ) ).
    TRY.
        DATA(ls_request) = VALUE ty_s_request( method           = to_upper( lo_http->get_method( ) )
                                               body             = lo_http->get_cdata( )
                                               content_type     = lo_http->get_header_field( `content-type` )
                                               origin           = lo_http->get_header_field( `origin` )
                                               referer          = lo_http->get_header_field( `referer` )
                                               host             = lo_http->get_header_field( `host` )
                                               session_id       = lo_http->get_header_field( `mcp-session-id` )
                                               protocol_version = lo_http->get_header_field( `mcp-protocol-version` ) ).
        ls_response = NEW z2ui5_cl_agent_mcp( )->handle( ls_request ).
        " the sessions and the audit log are written in this LUW
        COMMIT WORK.
      CATCH cx_root INTO DATA(lx).
        ls_response = http_error( status = 500
                                  reason = `Internal Server Error`
                                  code   = cs_error-internal
                                  text   = lx->get_text( ) ).
    ENDTRY.

    lo_http->set_status( code   = ls_response-status
                         reason = ls_response-reason ).
    LOOP AT ls_response-t_header INTO DATA(ls_header).
      lo_http->set_header_field( n = ls_header-name
                                 v = ls_header-value ).
    ENDLOOP.
    lo_http->set_cdata( ls_response-body ).

  ENDMETHOD.

  METHOD http_error.

    result = VALUE #( status   = status
                      reason   = reason
                      body     = rpc_error( id   = `null`
                                            code = code
                                            text = text )
                      t_header = VALUE #( ( name = `Content-Type` value = `application/json` ) ) ).

  ENDMETHOD.

  METHOD check_version.

    SPLIT c_protocol_versions AT `,` INTO TABLE DATA(lt_version).
    result = xsdbool( line_exists( lt_version[ table_line = version ] ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD handle.

    DATA lt_out TYPE string_table.

    ms_request = is_request.
    DATA(lv_method) = to_upper( is_request-method ).

    IF lv_method = `DELETE`.
      IF is_request-session_id IS NOT INITIAL.
        DATA(lv_session) = CONV z2ui5_t_ag_mcp-id( is_request-session_id ).
        DELETE FROM z2ui5_t_ag_mcp WHERE id = @lv_session AND uname = @sy-uname.
      ENDIF.
      result = VALUE #( status = 200
                        reason = `OK` ).
      RETURN.
    ENDIF.
    IF lv_method <> `POST`.
      " no server-initiated stream: everything is answered on the POST
      result = VALUE #( status   = 405
                        reason   = `Method Not Allowed`
                        t_header = VALUE #( ( name = `Allow` value = `POST, DELETE` ) ) ).
      RETURN.
    ENDIF.

    " a browser page must not drive the endpoint with the user's SSO
    " cookies: an Origin (or Referer) of another host is refused, the same
    " rule abap2UI5 applies to its own POSTs
    IF z2ui5_cl_ui5_http_handler=>_check_csrf_rejected( active  = abap_true
                                                        origin  = is_request-origin
                                                        referer = is_request-referer
                                                        host    = is_request-host ) = abap_true.
      result = http_error( status = 403
                           reason = `Forbidden`
                           code   = cs_error-invalid_request
                           text   = `cross-origin request refused - the Origin does not match the host of this endpoint` ).
      RETURN.
    ENDIF.
    IF find( val  = to_lower( is_request-content_type )
             sub  = `application/json` ) < 0.
      result = http_error( status = 415
                           reason = `Unsupported Media Type`
                           code   = cs_error-invalid_request
                           text   = `send the JSON-RPC message as Content-Type: application/json` ).
      RETURN.
    ENDIF.
    IF is_request-protocol_version IS NOT INITIAL AND check_version( is_request-protocol_version ) = abap_false.
      result = http_error( status = 400
                           reason = `Bad Request`
                           code   = cs_error-invalid_request
                           text   = |unsupported MCP-Protocol-Version { is_request-protocol_version } - this endpoint speaks { c_protocol_versions }| ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( iv_json            = is_request-body
                                                                    iv_keep_item_order = abap_true ) ).
      CATCH cx_root.
        result = http_error( status = 400
                             reason = `Bad Request`
                             code   = cs_error-parse
                             text   = `parse error - the body is not JSON` ).
        RETURN.
    ENDTRY.

    client_of_session( ).

    IF lo_json->get_node_type( `/` ) = z2ui5_if_ajson_types=>node_type-array.
      " a batch (2025-03-26): every message answered, notifications not
      DATA(lv_count) = lines( lo_json->members( `/` ) ).
      IF lv_count = 0.
        result = http_error( status = 400
                             reason = `Bad Request`
                             code   = cs_error-invalid_request
                             text   = `an empty batch is no request` ).
        RETURN.
      ENDIF.
      DO lv_count TIMES.
        DATA(lv_out) = message( io_json = lo_json
                                path    = |/{ sy-index }| ).
        IF lv_out IS NOT INITIAL.
          INSERT lv_out INTO TABLE lt_out.
        ENDIF.
      ENDDO.
      IF lt_out IS NOT INITIAL.
        result-body = |[{ concat_lines_of( table = lt_out
                                           sep   = `,` ) }]|.
      ENDIF.
    ELSE.
      result-body = message( io_json = lo_json
                             path    = `` ).
    ENDIF.

    IF result-body IS INITIAL.
      " only notifications and responses: accepted, nothing to answer
      result-status = 202.
      result-reason = `Accepted`.
    ELSE.
      result-status = 200.
      result-reason = `OK`.
      INSERT VALUE #( name  = `Content-Type`
                      value = `application/json` ) INTO TABLE result-t_header.
    ENDIF.
    INSERT LINES OF mt_header INTO TABLE result-t_header.

  ENDMETHOD.

  METHOD client_of_session.

    " the client of an initialized MCP session names the audit entries
    IF ms_request-session_id IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_session) = CONV z2ui5_t_ag_mcp-id( ms_request-session_id ).
    SELECT SINGLE mcp_client FROM z2ui5_t_ag_mcp WHERE id = @lv_session AND uname = @sy-uname INTO @DATA(lv_client).
    IF sy-subrc = 0.
      mv_client = lv_client.
    ENDIF.

  ENDMETHOD.

  METHOD message.

    DATA lv_id TYPE string VALUE `null`.
    DATA lv_code TYPE i.
    DATA lv_text TYPE string.

    IF io_json->get_node_type( COND #( WHEN path IS INITIAL THEN `/` ELSE path ) ) <> z2ui5_if_ajson_types=>node_type-object.
      result = rpc_error( id   = lv_id
                          code = cs_error-invalid_request
                          text = `invalid request - a JSON-RPC message is an object` ).
      RETURN.
    ENDIF.

    DATA(lv_has_id) = abap_false.
    CASE io_json->get_node_type( |{ path }/id| ).
      WHEN z2ui5_if_ajson_types=>node_type-string.
        lv_id = z2ui5_cl_agent_viewxml=>json_string( io_json->get( |{ path }/id| ) ).
        lv_has_id = abap_true.
      WHEN z2ui5_if_ajson_types=>node_type-number.
        lv_id = io_json->get( |{ path }/id| ).
        lv_has_id = abap_true.
    ENDCASE.

    IF io_json->get_string( |{ path }/jsonrpc| ) <> `2.0`.
      result = rpc_error( id   = lv_id
                          code = cs_error-invalid_request
                          text = `invalid request - jsonrpc must be "2.0"` ).
      RETURN.
    ENDIF.
    IF io_json->get_node_type( |{ path }/method| ) <> z2ui5_if_ajson_types=>node_type-string.
      IF io_json->exists( |{ path }/result| ) = abap_true OR io_json->exists( |{ path }/error| ) = abap_true.
        " a response of the client - nothing was asked, nothing to answer
        RETURN.
      ENDIF.
      result = rpc_error( id   = lv_id
                          code = cs_error-invalid_request
                          text = `invalid request - method is missing` ).
      RETURN.
    ENDIF.
    DATA(lv_method) = io_json->get( |{ path }/method| ).

    IF lv_has_id = abap_false.
      " a notification (notifications/initialized, notifications/cancelled,
      " ...): accepted and never answered
      RETURN.
    ENDIF.

    TRY.
        CASE lv_method.
          WHEN `initialize`.
            result = rpc_result( id     = lv_id
                                 result = initialize( io_json = io_json
                                                      path    = path ) ).
          WHEN `ping`.
            result = rpc_result( id     = lv_id
                                 result = `{}` ).
          WHEN `tools/list`.
            result = rpc_result( id     = lv_id
                                 result = get_tools( ) ).
          WHEN `tools/call`.
            DATA(lv_result) = tools_call( EXPORTING io_json    = io_json
                                                    path       = path
                                          IMPORTING error_code = lv_code
                                                    error_text = lv_text ).
            result = COND #( WHEN lv_code IS NOT INITIAL
                             THEN rpc_error( id   = lv_id
                                             code = lv_code
                                             text = lv_text )
                             ELSE rpc_result( id     = lv_id
                                              result = lv_result ) ).
          WHEN OTHERS.
            result = rpc_error( id   = lv_id
                                code = cs_error-method_not_found
                                text = |method not found: { lv_method } - this endpoint offers initialize, ping, tools/list and tools/call| ).
        ENDCASE.
      CATCH cx_root INTO DATA(lx).
        result = rpc_error( id   = lv_id
                            code = cs_error-internal
                            text = lx->get_text( ) ).
    ENDTRY.

  ENDMETHOD.

  METHOD initialize.

    DATA ls_row TYPE z2ui5_t_ag_mcp.

    SPLIT c_protocol_versions AT `,` INTO TABLE DATA(lt_version).
    DATA(lv_requested) = io_json->get_string( |{ path }/params/protocolVersion| ).
    DATA(lv_version) = COND string( WHEN check_version( lv_requested ) = abap_true
                                    THEN lv_requested
                                    ELSE VALUE #( lt_version[ 1 ] OPTIONAL ) ).
    DATA(lv_name) = io_json->get_string( |{ path }/params/clientInfo/name| ).
    DATA(lv_client_version) = io_json->get_string( |{ path }/params/clientInfo/version| ).
    mv_client = condense( |{ lv_name } { lv_client_version }| ).

    TRY.
        ls_row = VALUE #( id         = z2ui5_cl_ui5_util_context=>uuid_get_c32( )
                          uname      = sy-uname
                          mcp_client = mv_client
                          protocol   = lv_version
                          created_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( )
                          changed_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ) ).
        INSERT z2ui5_t_ag_mcp FROM @ls_row.
        INSERT VALUE #( name  = `Mcp-Session-Id`
                        value = ls_row-id ) INTO TABLE mt_header.
        " MCP sessions older than a day are gone
        DATA(lv_limit) = z2ui5_cl_ui5_util_context=>time_subtract_seconds( time    = ls_row-created_at
                                                                           seconds = 86400 ).
        DELETE FROM z2ui5_t_ag_mcp WHERE changed_at < @lv_limit.
      CATCH cx_root ##NO_HANDLER.
        " the session id is optional - without it the client name stays
        " out of the audit log of later requests
    ENDTRY.

    DATA(lv_state) = COND string( WHEN z2ui5_cl_agent_settings=>check_enabled( ) = abap_true
                                  THEN `The endpoint is enabled.`
                                  ELSE `The endpoint is DISABLED on this system - every tool call is refused until an administrator ` &&
                                       `enables it (app Z2UI5_CL_AGENT_APP_ADMIN).` ).
    DATA(lv_instructions) = |Operate the abap2UI5 apps of this SAP system as the SAP user { sy-uname }, through the apps' own logic | &&
                            |and authority checks. app_list names the apps enabled for agents; app_start answers with an agent | &&
                            |snapshot (fields, actions, tables, messages); app_act fills fields and fires one event, and answers | &&
                            |with the next snapshot - always continue with its session. Actions marked policy "confirm" or | &&
                            |"forbidden" are never fired by an agent: for confirm, app_act answers with a URL that hands the | &&
                            |screen over to the user. Every call is audited. { lv_state }|.

    result = |\{"protocolVersion":{ z2ui5_cl_agent_viewxml=>json_string( lv_version ) }| &&
             |,"capabilities":\{"tools":\{"listChanged":false\}\}| &&
             |,"serverInfo":\{"name":{ z2ui5_cl_agent_viewxml=>json_string( c_server_name ) }| &&
             |,"title":"abap2UI5 agent","version":{ z2ui5_cl_agent_viewxml=>json_string( c_server_version ) }\}| &&
             |,"instructions":{ z2ui5_cl_agent_viewxml=>json_string( lv_instructions ) }\}|.

  ENDMETHOD.

  METHOD tools_call.

    DATA ls_result TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lv_values TYPE string.
    DATA lv_args TYPE string.

    CLEAR error_code.
    DATA(lv_name) = io_json->get_string( |{ path }/params/name| ).
    DATA(lv_base) = |{ path }/params/arguments|.
    DATA(lv_args_type) = io_json->get_node_type( lv_base ).
    IF lv_args_type IS NOT INITIAL AND lv_args_type <> z2ui5_if_ajson_types=>node_type-object
        AND lv_args_type <> z2ui5_if_ajson_types=>node_type-null.
      error_code = cs_error-invalid_params.
      error_text = `invalid params - arguments is an object`.
      RETURN.
    ENDIF.

    " the schema is documentation to the client, not a gate on the wire:
    " every argument is checked for its type before it is used
    DATA(lt_string) = VALUE string_table( ( `filter` ) ( `app` ) ( `session` ) ( `event` ) ).
    LOOP AT lt_string INTO DATA(lv_key).
      DATA(lv_type) = io_json->get_node_type( |{ lv_base }/{ lv_key }| ).
      IF lv_type IS NOT INITIAL AND lv_type <> z2ui5_if_ajson_types=>node_type-string AND lv_type <> z2ui5_if_ajson_types=>node_type-null.
        result = tool_result( text     = |{ lv_key } must be a string|
                              is_error = abap_true ).
        RETURN.
      ENDIF.
    ENDLOOP.
    DATA(lt_number) = VALUE string_table( ( `max_rows` ) ( `row` ) ).
    LOOP AT lt_number INTO lv_key.
      lv_type = io_json->get_node_type( |{ lv_base }/{ lv_key }| ).
      IF lv_type IS NOT INITIAL AND lv_type <> z2ui5_if_ajson_types=>node_type-number AND lv_type <> z2ui5_if_ajson_types=>node_type-null.
        result = tool_result( text     = |{ lv_key } must be a number|
                              is_error = abap_true ).
        RETURN.
      ENDIF.
    ENDLOOP.
    lv_type = io_json->get_node_type( |{ lv_base }/values| ).
    IF lv_type = z2ui5_if_ajson_types=>node_type-object.
      lv_values = io_json->slice( |{ lv_base }/values| )->stringify( ).
    ELSEIF lv_type IS NOT INITIAL AND lv_type <> z2ui5_if_ajson_types=>node_type-null.
      result = tool_result( text     = `values is an object: { "<field id, path or name>": value }`
                            is_error = abap_true ).
      RETURN.
    ENDIF.
    lv_type = io_json->get_node_type( |{ lv_base }/args| ).
    IF lv_type = z2ui5_if_ajson_types=>node_type-array.
      lv_args = io_json->slice( |{ lv_base }/args| )->stringify( ).
    ELSEIF lv_type IS NOT INITIAL AND lv_type <> z2ui5_if_ajson_types=>node_type-null.
      result = tool_result( text     = `args is an array, positional to the action's args (null where the client should fill in the value)`
                            is_error = abap_true ).
      RETURN.
    ENDIF.

    DATA(lv_row) = COND string( WHEN io_json->get_node_type( |{ lv_base }/row| ) = z2ui5_if_ajson_types=>node_type-number
                                THEN io_json->get( |{ lv_base }/row| ) ).
    DATA(lv_max_rows) = COND string( WHEN io_json->get_node_type( |{ lv_base }/max_rows| ) = z2ui5_if_ajson_types=>node_type-number
                                     THEN io_json->get( |{ lv_base }/max_rows| ) ).
    DATA(lo_session) = NEW z2ui5_cl_agent_session( mv_client ).

    CASE lv_name.
      WHEN `app_list`.
        ls_result = lo_session->app_list( io_json->get_string( |{ lv_base }/filter| ) ).
      WHEN `app_start`.
        ls_result = lo_session->app_start( app      = io_json->get_string( |{ lv_base }/app| )
                                           values   = lv_values
                                           max_rows = lv_max_rows ).
      WHEN `app_describe`.
        ls_result = lo_session->app_describe( session  = io_json->get_string( |{ lv_base }/session| )
                                              max_rows = lv_max_rows ).
      WHEN `app_act`.
        ls_result = lo_session->app_act( session  = io_json->get_string( |{ lv_base }/session| )
                                         values   = lv_values
                                         event    = io_json->get_string( |{ lv_base }/event| )
                                         args     = lv_args
                                         row      = lv_row
                                         max_rows = lv_max_rows ).
      WHEN OTHERS.
        error_code = cs_error-invalid_params.
        error_text = |unknown tool: { lv_name } - this endpoint offers app_list, app_start, app_describe and app_act|.
        RETURN.
    ENDCASE.

    result = tool_result( text     = ls_result-text
                          is_error = ls_result-is_error ).

  ENDMETHOD.

  METHOD tool_result.

    result = |\{"content":[\{"type":"text","text":{ z2ui5_cl_agent_viewxml=>json_string( text ) }\}]| &&
             |,"isError":{ COND #( WHEN is_error = abap_true THEN `true` ELSE `false` ) }\}|.

  ENDMETHOD.

  METHOD rpc_result.

    rv_out = |\{"jsonrpc":"2.0","id":{ id },"result":{ result }\}|.

  ENDMETHOD.

  METHOD rpc_error.

    rv_out = |\{"jsonrpc":"2.0","id":{ id },"error":\{"code":{ code },"message":{ z2ui5_cl_agent_viewxml=>json_string( text ) }\}\}|.

  ENDMETHOD.

  METHOD get_tools.

    DATA(lv_max_rows) = `"max_rows":{"type":"number","description":"table rows per table in the snapshot (default 20, max 200)"}`.
    DATA(lv_max_rows_kept) = `"max_rows":{"type":"number","description":"table rows per table (default: what app_start used)"}`.

    result = `{"tools":[` &&
      `{"name":"app_list","description":"The abap2UI5 apps of this SAP system an agent may start with app_start: the classes ` &&
      `that implement z2ui5_if_agent_app (source \"interface\") and the ones an administrator allowed (source \"setting\"), ` &&
      `each with the description the app gives itself. Optional filter: a substring of the class name. Starts nothing.",` &&
      `"inputSchema":{"type":"object","properties":{"filter":{"type":"string","description":"substring of the class name, ` &&
      `case-insensitive"}}}},` &&
      `{"name":"app_start","description":"Start an abap2UI5 app as your SAP user and get its screen as an AGENT SNAPSHOT (v1): ` &&
      `the fields you can fill (id, model path, label, kind, current value, editable, choice values), the actions you can fire ` &&
      `(event name and arguments of each button, link, row and value-help wire), the tables (columns, the first rows, ` &&
      `selection), the messages (toast, message box, MessageStrip, field value states, message popover items) and some static text - read from the ` &&
      `abap2UI5 protocol itself, no browser. Continue with app_act using the snapshot's session. Optional values are applied ` &&
      `as pending edits right after the start.",` &&
      `"inputSchema":{"type":"object","properties":{"app":{"type":"string","description":"the app class to start (app_list ` &&
      `names them)"},"values":{"type":"object","description":"optional { \"<field id, model path or name>\": value } kept as ` &&
      `pending edits (sent with the next app_act event)"},` && lv_max_rows && `},"required":["app"]}},` &&
      `{"name":"app_describe","description":"The current agent snapshot of a running app session - answered from what the ` &&
      `endpoint kept, no roundtrip. Pending edits (values sent without an event) show as the fields' values and are listed ` &&
      `under pending.",` &&
      `"inputSchema":{"type":"object","properties":{"session":{"type":"string","description":"the session of the last ` &&
      `snapshot"},` && lv_max_rows_kept && `},"required":["session"]}},` &&
      `{"name":"app_act","description":"Operate a running app session: fill fields and fire one event, then get the next ` &&
      `agent snapshot. values { \"<field id | model path | name>\": value } (table cells as \"<table path or id>/<row>/<COLUMN>\", ` &&
      `e.g. \"/T_TAB/2/SELKZ\" to select a row) go out as the model delta of the roundtrip; event is an action's event name ` &&
      `or its id (\"a3\"); row (0-based) fills the row-dependent arguments of a row action (\"$row:FIELD\", ` &&
      `\"$source:text\", and the row-valued event parameters such as ${$parameters>/listItem}.getBindingContext()...); ` &&
      `on a SelectDialog/TableSelectDialog the confirm action is the pick: row selects that row as a click does (its ` &&
      `selectionField, sent as the model delta) and fills selectedItem/selectedContexts arguments from it; args ` &&
      `(positional, null = let the client fill it) supplies arguments the browser would compute. Without event the values stay pending, as typing ` &&
      `does in the browser. Strict: an event that is not among the snapshot's actions, a field that is not on the screen or ` &&
      `not editable, a choice outside its values is refused - the error names what is allowed - and nothing is sent. ` &&
      `Actions with policy \"confirm\" or \"forbidden\" are never fired by an agent; confirm answers with a URL that hands ` &&
      `the screen over to the user. \"@CLOSE_POPUP\" / \"@CLOSE_POPOVER\" close the dialog locally, as the browser does.",` &&
      `"inputSchema":{"type":"object","properties":{"session":{"type":"string","description":"the session of the last ` &&
      `snapshot"},"values":{"type":"object","description":"{ \"<field id, model path or name>\": value, \"<table path>/<row>/` &&
      `<COLUMN>\": value }"},"event":{"type":"string","description":"the action to fire: its event name (e.g. \"SAVE\") or ` &&
      `its id (\"a3\")"},"args":{"type":"array","description":"event arguments, positional to the action's args; null where ` &&
      `the client fills the value in"},"row":{"type":"number","description":"for a row action: the row index (0-based) in ` &&
      `its table - for a selection dialog's confirm, the row to pick"},` && lv_max_rows_kept && `},"required":["session"]}}` &&
      `]}`.

  ENDMETHOD.

ENDCLASS.
