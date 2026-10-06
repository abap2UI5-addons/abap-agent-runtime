"! The audit log of the agent endpoint - table Z2UI5_T_AG_LOG.
"!
"! One row per tool call: when, which SAP user, which session and app,
"! which operation and event, the arguments (values masked where the app
"! or the settings mark a field sensitive, password inputs always, the
"! whole text cut to c_max_args characters), the outcome and the MCP
"! client that called (its name from initialize).
"!
"! log( ) never raises: a failing audit write must not turn a refused act
"! into a dump - but it is written in the caller's LUW, so the MCP handler
"! commits it with the session (z2ui5_cl_agent_mcp=&gt;run).
CLASS z2ui5_cl_agent_audit DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_max_args TYPE i VALUE 2000.
    CONSTANTS c_mask TYPE string VALUE `***`.
    "! cleanup( ) keeps everything beyond this many days - days * 86400
    "! seconds must stay an integer.
    CONSTANTS c_max_days TYPE i VALUE 24855.

    CONSTANTS:
      BEGIN OF cs_outcome,
        ok    TYPE string VALUE `ok`,
        error TYPE string VALUE `error`,
      END OF cs_outcome.

    TYPES:
      BEGIN OF ty_s_entry,
        session   TYPE string,
        app       TYPE string,
        operation TYPE string,
        event     TYPE string,
        args      TYPE string,
        outcome   TYPE string,
        text      TYPE string,
        client    TYPE string,
      END OF ty_s_entry.

    TYPES ty_t_log TYPE STANDARD TABLE OF z2ui5_t_ag_log WITH EMPTY KEY.

    CLASS-METHODS log
      IMPORTING
        is_entry TYPE ty_s_entry.

    "! The entries of one user (all users for an administrator), newest
    "! first, at most max_rows.
    CLASS-METHODS read
      IMPORTING
        uname         TYPE clike OPTIONAL
        max_rows      TYPE i DEFAULT 500
      RETURNING
        VALUE(result) TYPE ty_t_log.

    "! Delete the entries older than the given number of days (1 to
    "! c_max_days - any other number deletes nothing); returns how many
    "! went.
    CLASS-METHODS cleanup
      IMPORTING
        days          TYPE i
      RETURNING
        VALUE(result) TYPE i.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_audit IMPLEMENTATION.

  METHOD log.

    DATA ls_row TYPE z2ui5_t_ag_log.

    TRY.
        ls_row-id = z2ui5_cl_ui5_util_context=>uuid_get_c32( ).
        ls_row-timestampl = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
        ls_row-uname = sy-uname.
        ls_row-session_id = is_entry-session.
        ls_row-app = to_upper( is_entry-app ).
        ls_row-operation = is_entry-operation.
        ls_row-event = is_entry-event.
        ls_row-outcome = is_entry-outcome.
        ls_row-text = is_entry-text.
        ls_row-mcp_client = is_entry-client.
        ls_row-args = is_entry-args.
        IF strlen( ls_row-args ) > c_max_args.
          ls_row-args = |{ z2ui5_cl_agent_viewxml=>cut( val = ls_row-args
                                                        len = c_max_args - 3 ) }...|.
        ENDIF.
        INSERT z2ui5_t_ag_log FROM @ls_row.
      CATCH cx_root ##NO_HANDLER.
        " the audit must never break the call it records
    ENDTRY.

  ENDMETHOD.

  METHOD read.

    DATA lv_uname TYPE z2ui5_t_ag_log-uname.

    IF uname IS SUPPLIED.
      lv_uname = to_upper( uname ).
      SELECT * FROM z2ui5_t_ag_log WHERE uname = @lv_uname
        ORDER BY timestampl DESCENDING
        INTO TABLE @result
        UP TO @max_rows ROWS.
    ELSE.
      SELECT * FROM z2ui5_t_ag_log
        ORDER BY timestampl DESCENDING
        INTO TABLE @result
        UP TO @max_rows ROWS.
    ENDIF.

  ENDMETHOD.

  METHOD cleanup.

    " less than a day would delete what was just written; more than the
    " seconds an integer holds (68 years) reaches back before any entry
    IF days < 1 OR days > c_max_days.
      RETURN.
    ENDIF.
    DATA(lv_limit) = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = z2ui5_cl_ui5_util_context=>time_get_timestampl( )
                         seconds = days * 86400 ).
    DELETE FROM z2ui5_t_ag_log WHERE timestampl < @lv_limit.
    result = sy-dbcnt.

  ENDMETHOD.

ENDCLASS.
