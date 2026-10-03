"! The four agent operations on abap2UI5 apps - app_list, app_start,
"! app_describe, app_act - with the semantics of docs/agent-snapshot.md
"! (abap2UI5/mcp-server), ported from its lib/appclient.mjs.
"!
"! The engine is the headless frontend simulator (abap2UI5/headless-
"! frontend, z2ui5_cl_frontend_simulator): it plays the browser side of the
"! protocol inside ABAP, so every act runs the app's own main( ) as the
"! SAP user of the request, with the app's own validation and authority
"! checks. Every operation is one HTTP request; between requests a session
"! lives in Z2UI5_T_AG_SES: the simulator's get_state( ) (the view of
"! every layer), the client work of the last response, the pending values
"! and the last snapshot - so app_describe needs no roundtrip and app_act
"! resume( )s the session. A session belongs to its user only and expires
"! with the abap2UI5 draft it continues.
"!
"! Strict, like the reference: an event that is not among the snapshot's
"! actions, a field that is not on the screen or not editable, a choice
"! outside its values is refused naming what IS allowed, and a refused act
"! sends nothing and changes nothing. On top of the reference, the policy:
"! events the app or the settings classify confirm or forbidden are never
"! fired by an agent - see z2ui5_if_agent_app.
CLASS z2ui5_cl_agent_session DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      "! is_error: the operation was refused or failed, text says why and
      "! what is allowed. Otherwise text is the answer (the snapshot JSON,
      "! the app list JSON). session: the session the answer belongs to.
      BEGIN OF ty_s_result,
        is_error TYPE abap_bool,
        text     TYPE string,
        session  TYPE string,
      END OF ty_s_result.

    "! client: the MCP client's name and version (for the audit log).
    METHODS constructor
      IMPORTING
        client TYPE clike OPTIONAL.

    "! The apps an agent may start - {"count":..,"apps":[{app,description,source}],"hint":..}.
    METHODS app_list
      IMPORTING
        filter        TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! Start an app; values (a JSON object) become pending edits.
    METHODS app_start
      IMPORTING
        app           TYPE clike
        values        TYPE clike OPTIONAL
        max_rows      TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! The current snapshot of a session - no roundtrip.
    METHODS app_describe
      IMPORTING
        session       TYPE clike
        max_rows      TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! Fill fields (values, a JSON object) and fire an event (its name or
    "! action id) with args (a JSON array) and row (0-based) for a row
    "! action. Without an event the values stay pending.
    METHODS app_act
      IMPORTING
        session       TYPE clike
        values        TYPE clike OPTIONAL
        event         TYPE clike OPTIONAL
        args          TYPE clike OPTIONAL
        row           TYPE clike OPTIONAL
        max_rows      TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CONSTANTS c_list_max TYPE i VALUE 30.

    TYPES ty_s_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    TYPES:
      "! A pending value as stored (without the computed number).
      BEGIN OF ty_s_pending_db,
        model_key TYPE string,
        path      TYPE string,
        kind      TYPE string,
        str       TYPE string,
        json      TYPE string,
      END OF ty_s_pending_db.
    TYPES ty_t_pending_db TYPE STANDARD TABLE OF ty_s_pending_db WITH EMPTY KEY.

    TYPES:
      "! A value of the request (values / args), keyed.
      BEGIN OF ty_s_input,
        key TYPE string,
        val TYPE ty_s_val,
      END OF ty_s_input.
    TYPES ty_t_input TYPE STANDARD TABLE OF ty_s_input WITH EMPTY KEY.

    TYPES:
      "! Where a value goes: a field, or a table cell.
      BEGIN OF ty_s_target,
        is_cell  TYPE abap_bool,
        field    TYPE i,
        table    TYPE i,
        row      TYPE i,
        column   TYPE string,
      END OF ty_s_target.

    DATA mv_client TYPE string.
    DATA mo_sim TYPE REF TO z2ui5_cl_frontend_simulator.
    DATA ms_row TYPE z2ui5_t_ag_ses.
    DATA mt_custom TYPE string_table.
    DATA mt_pending TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.
    DATA mo_snap TYPE REF TO z2ui5_cl_agent_snapshot.
    DATA mv_max_rows TYPE i.

    METHODS fail
      IMPORTING
        text TYPE string
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS check_enabled
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS rows_of
      IMPORTING
        val           TYPE clike
        default       TYPE i
      RETURNING
        VALUE(result) TYPE i
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS load
      IMPORTING
        session TYPE clike
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS save
      IMPORTING
        id_old TYPE clike OPTIONAL.

    METHODS analyze.

    METHODS custom_of_sim
      RETURNING
        VALUE(result) TYPE string_table.

    METHODS parse_input
      IMPORTING
        json          TYPE clike
        array         TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result) TYPE ty_t_input
      RAISING
        z2ui5_cx_ui5_util_error.

    TYPES:
      BEGIN OF ty_s_member,
        key TYPE string,
        raw TYPE string,
      END OF ty_s_member.
    TYPES ty_t_member TYPE STANDARD TABLE OF ty_s_member WITH EMPTY KEY.

    METHODS object_members
      IMPORTING
        json          TYPE string
      RETURNING
        VALUE(result) TYPE ty_t_member.

    METHODS val_of_node
      IMPORTING
        io_json       TYPE REF TO z2ui5_if_ajson
        path          TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_val.

    METHODS apply_values
      IMPORTING
        t_value       TYPE ty_t_input
      RETURNING
        VALUE(result) TYPE string_table
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS resolve_target
      IMPORTING
        key           TYPE string
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_s_target.

    METHODS coerce
      IMPORTING
        val           TYPE ty_s_val
        current       TYPE ty_s_val
        kind          TYPE string
        label         TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS find_action
      IMPORTING
        event         TYPE string
        has_row       TYPE abap_bool
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_action
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS event_args
      IMPORTING
        is_action     TYPE z2ui5_cl_agent_snapshot=>ty_s_action
        t_given       TYPE ty_t_input
        row_raw       TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_t_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS send
      IMPORTING
        is_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action
        t_arg     TYPE z2ui5_cl_agent_viewxml=>ty_t_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS close_layer
      IMPORTING
        slot TYPE string
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS field_help
      RETURNING
        VALUE(result) TYPE string.

    METHODS action_help
      RETURNING
        VALUE(result) TYPE string.

    METHODS layer_note
      RETURNING
        VALUE(result) TYPE string.

    METHODS mask_values
      IMPORTING
        t_value       TYPE ty_t_input
        app           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    METHODS audit
      IMPORTING
        operation TYPE string
        event     TYPE clike OPTIONAL
        args      TYPE string OPTIONAL
        is_result TYPE ty_s_result.

    CLASS-METHODS list_of
      IMPORTING
        t_item        TYPE string_table
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS sim_text
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS val_json_quoted
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_session IMPLEMENTATION.

  METHOD constructor.

    mv_client = client.

  ENDMETHOD.

  METHOD fail.

    RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
      EXPORTING
        val = text.

  ENDMETHOD.

  METHOD list_of.

    DATA lt_shown TYPE string_table.

    LOOP AT t_item INTO DATA(lv_item) TO c_list_max.
      INSERT lv_item INTO TABLE lt_shown.
    ENDLOOP.
    result = concat_lines_of( table = lt_shown
                              sep   = `, ` ).
    IF lines( t_item ) > lines( lt_shown ).
      result = |{ result }, ... ({ lines( t_item ) - lines( lt_shown ) } more)|.
    ENDIF.

  ENDMETHOD.

  METHOD check_enabled.

    IF z2ui5_cl_agent_settings=>check_enabled( ) = abap_false.
      fail( `the abap2UI5 agent endpoint is disabled on this system - an administrator enables it in the app ` &&
            `Z2UI5_CL_AGENT_APP_ADMIN (README of abap2UI5-addons/agent, "Enabling the endpoint")` ).
    ENDIF.

  ENDMETHOD.

  METHOD rows_of.

    IF val IS INITIAL.
      result = default.
      RETURN.
    ENDIF.
    DATA(ls_arg) = z2ui5_cl_agent_viewxml=>describe_arg( val ).
    IF ls_arg-static = abap_false OR ls_arg-val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-number.
      fail( |max_rows must be a number, not '{ val }' - leaving it out means { default }| ).
    ENDIF.
    result = trunc( ls_arg-val-num ).
    IF result < 0.
      result = 0.
    ELSEIF result > z2ui5_cl_agent_snapshot=>c_max_rows_limit.
      result = z2ui5_cl_agent_snapshot=>c_max_rows_limit.
    ENDIF.

  ENDMETHOD.

  METHOD audit.

    z2ui5_cl_agent_audit=>log( VALUE #( session   = COND #( WHEN is_result-session IS NOT INITIAL THEN is_result-session ELSE ms_row-id )
                                        app       = COND #( WHEN mo_sim IS BOUND THEN mo_sim->get_app( ) ELSE ms_row-app )
                                        operation = operation
                                        event     = event
                                        args      = args
                                        outcome   = COND #( WHEN is_result-is_error = abap_true
                                                            THEN z2ui5_cl_agent_audit=>cs_outcome-error
                                                            ELSE z2ui5_cl_agent_audit=>cs_outcome-ok )
                                        text      = COND #( WHEN is_result-is_error = abap_true THEN is_result-text )
                                        client    = mv_client ) ).

  ENDMETHOD.

  METHOD app_list.

    DATA lt_item TYPE string_table.

    TRY.
        check_enabled( ).
        DATA(lt_app) = z2ui5_cl_agent_settings=>get_apps( filter ).
        LOOP AT lt_app INTO DATA(ls_app).
          INSERT |\{"app":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-app ) }| &&
                 |,"description":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-description ) }| &&
                 |,"source":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-source ) }\}| INTO TABLE lt_item.
        ENDLOOP.
        DATA(lv_hint) = COND string( WHEN lt_app IS NOT INITIAL
                                     THEN `app_start { app } starts one and answers with its agent snapshot`
                                     WHEN filter IS NOT INITIAL
                                     THEN |no app enabled for agents contains '{ filter }'|
                                     ELSE `no app is enabled for agents on this system - an app opts in by implementing ` &&
                                          `z2ui5_if_agent_app, or an administrator allows it in Z2UI5_CL_AGENT_APP_ADMIN` ).
        result-text = |\{"count":{ lines( lt_app ) },"apps":[{ concat_lines_of( table = lt_item
                                                                              sep   = `,` ) }]| &&
                      |,"hint":{ z2ui5_cl_agent_viewxml=>json_string( lv_hint ) }\}|.
      CATCH cx_root INTO DATA(lx).
        result = VALUE #( is_error = abap_true
                          text     = lx->get_text( ) ).
    ENDTRY.
    audit( operation = `app_list`
           args      = COND #( WHEN filter IS NOT INITIAL THEN |\{"filter":{ z2ui5_cl_agent_viewxml=>json_string( filter ) }\}| )
           is_result = result ).

  ENDMETHOD.

  METHOD app_start.

    DATA lv_reason TYPE string.
    DATA lt_name TYPE string_table.

    DATA(lv_app) = to_upper( condense( CONV string( app ) ) ).
    TRY.
        check_enabled( ).
        mv_max_rows = rows_of( val     = max_rows
                               default = z2ui5_cl_agent_snapshot=>c_max_rows_default ).
        IF lv_app IS INITIAL.
          fail( `pass app - the class to start (app_list names the apps enabled for agents)` ).
        ENDIF.
        IF z2ui5_cl_agent_settings=>check_app( EXPORTING app    = lv_app
                                               IMPORTING reason = lv_reason ) = abap_false.
          LOOP AT z2ui5_cl_agent_settings=>get_apps( ) INTO DATA(ls_app).
            INSERT ls_app-app INTO TABLE lt_name.
          ENDLOOP.
          fail( |{ lv_reason }{ COND #( WHEN lt_name IS NOT INITIAL THEN |; apps enabled for agents: { list_of( lt_name ) }| ) }| ).
        ENDIF.
        DATA(lt_value) = parse_input( values ).

        TRY.
            mo_sim = z2ui5_cl_frontend_simulator=>start( lv_app ).
          CATCH cx_root INTO DATA(lx_start).
            fail( |the app { lv_app } failed to start - { lx_start->get_text( ) }| ).
        ENDTRY.
        IF mo_sim->is_sticky( ) = abap_true.
          fail( |the app { lv_app } runs in a stateful session (set_session_stateful), which lives in one request only - | &&
                |the agent endpoint operates draft-based apps, one request per call| ).
        ENDIF.

        ms_row = VALUE #( id         = mo_sim->get_id( )
                          uname      = sy-uname
                          app        = mo_sim->get_app( )
                          app_start  = lv_app
                          mcp_client = mv_client
                          max_rows   = mv_max_rows
                          created_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ) ).
        mt_custom = custom_of_sim( ).
        analyze( ).

        " the values are applied as pending edits, validated against the
        " first snapshot - the session runs either way
        TRY.
            apply_values( lt_value ).
          CATCH z2ui5_cx_ui5_util_error INTO DATA(lx_values).
            save( ).
            fail( |{ lx_values->get_text( ) } (the app is running: session { ms_row-id } - app_describe shows it)| ).
        ENDTRY.
        IF lt_value IS NOT INITIAL.
          analyze( ).
        ENDIF.
        save( ).
        result = VALUE #( text    = ms_row-snapshot
                          session = ms_row-id ).

      CATCH cx_root INTO DATA(lx).
        result = VALUE #( is_error = abap_true
                          text     = lx->get_text( )
                          session  = ms_row-id ).
    ENDTRY.
    audit( operation = `app_start`
           args      = |\{"app":{ z2ui5_cl_agent_viewxml=>json_string( lv_app ) }{ COND #( WHEN values IS NOT INITIAL
                                                                                         THEN |,"values":{ mask_values( t_value = lt_value
                                                                                                                         app     = lv_app ) }| ) }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD app_describe.

    TRY.
        check_enabled( ).
        load( session ).
        mv_max_rows = rows_of( val     = max_rows
                               default = ms_row-max_rows ).
        IF mv_max_rows = ms_row-max_rows AND ms_row-snapshot IS NOT INITIAL.
          result = VALUE #( text    = ms_row-snapshot
                            session = ms_row-id ).
        ELSE.
          mo_sim = z2ui5_cl_frontend_simulator=>resume( id    = ms_row-id
                                                        state = ms_row-state ).
          analyze( ).
          result = VALUE #( text    = mo_snap->get_json( )
                            session = ms_row-id ).
        ENDIF.
      CATCH cx_root INTO DATA(lx).
        result = VALUE #( is_error = abap_true
                          text     = lx->get_text( ) ).
    ENDTRY.
    audit( operation = `app_describe`
           is_result = result ).

  ENDMETHOD.

  METHOD app_act.

    DATA lt_value TYPE ty_t_input.
    DATA lt_arg TYPE ty_t_input.
    DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
    DATA lv_event TYPE string.
    DATA lv_row TYPE string.

    lv_event = event.
    lv_row = row.
    TRY.
        check_enabled( ).
        load( session ).
        mv_max_rows = rows_of( val     = max_rows
                               default = ms_row-max_rows ).
        lt_value = parse_input( values ).
        lt_arg = parse_input( json  = args
                              array = abap_true ).

        TRY.
            mo_sim = z2ui5_cl_frontend_simulator=>resume( id    = ms_row-id
                                                          state = ms_row-state ).
          CATCH cx_root INTO DATA(lx_resume).
            DELETE FROM z2ui5_t_ag_ses WHERE id = @ms_row-id.
            fail( |session '{ ms_row-id }' cannot be continued - { lx_resume->get_text( ) }; app_start { ms_row-app_start } again| ).
        ENDTRY.
        analyze( ).

        " validate everything before anything changes
        IF lv_event IS NOT INITIAL.
          ls_action = find_action( event   = lv_event
                                   has_row = xsdbool( lv_row IS NOT INITIAL ) ).
          IF ls_action-enabled = abap_false.
            fail( |action { ls_action-id } ({ ls_action-label }) is disabled - { action_help( ) }| ).
          ENDIF.
          IF ls_action-policy = z2ui5_if_agent_app=>cs_policy-forbidden.
            fail( |event { ls_action-event } ({ ls_action-id } "{ ls_action-label }") is forbidden for agents - | &&
                  |{ z2ui5_cl_agent_settings=>get_policy( app_start = ms_row-app_start
                                                          app       = mo_sim->get_app( )
                                                          event     = ls_action-event )-source }. { action_help( ) }| ).
          ENDIF.
          IF ls_action-policy = z2ui5_if_agent_app=>cs_policy-confirm.
            DATA(lt_pending_paths) = VALUE string_table( ).
            LOOP AT mt_pending INTO DATA(ls_pending).
              INSERT ls_pending-path INTO TABLE lt_pending_paths.
            ENDLOOP.
            fail( |event { ls_action-event } ({ ls_action-id } "{ ls_action-label }") needs a human - agents never fire it | &&
                  |({ z2ui5_cl_agent_settings=>get_policy( app_start = ms_row-app_start
                                                           app       = mo_sim->get_app( )
                                                           event     = ls_action-event )-source }). | &&
                  |Hand over to the user: open { z2ui5_cl_agent_settings=>get_handover_url( app   = mo_sim->get_app( )
                                                                                            draft = ms_row-id ) } | &&
                  |in the browser - it restores this session's screen - check it and press "{ ls_action-label }" there. | &&
                  |{ COND #( WHEN lt_pending_paths IS NOT INITIAL
                            THEN |The pending values ({ list_of( lt_pending_paths ) }) are not part of the draft yet - | &&
                                 |fire an allowed event first, or tell the user what to enter.|
                            ELSE `Everything the agent entered is part of the draft.` ) }| ).
          ENDIF.
        ELSEIF lv_row IS NOT INITIAL.
          fail( `row belongs to an event - pass event too` ).
        ENDIF.

        DATA(lt_pending_before) = mt_pending.
        TRY.
            apply_values( lt_value ).
            " the values may have changed what the args read: re-analyse first
            analyze( ).
            IF lv_event IS INITIAL.
              save( ).
            ELSE.
              DATA(lv_action_id) = ls_action-id.
              READ TABLE mo_snap->mt_action INTO ls_action WITH KEY id = lv_action_id. "#EC CI_SORTSEQ
              IF ls_action-frontend IS NOT INITIAL.
                " performed here, as the browser performs it: the slot closes,
                " its unsent edits go with it, no roundtrip
                close_layer( ls_action-frontend ).
                save( ).
              ELSE.
                DATA(lt_tval) = event_args( is_action = ls_action
                                            t_given   = lt_arg
                                            row_raw   = lv_row ).
                DATA(lv_id_old) = ms_row-id.
                send( is_action = ls_action
                      t_arg     = lt_tval ).
                save( lv_id_old ).
              ENDIF.
            ENDIF.
            result = VALUE #( text    = ms_row-snapshot
                              session = ms_row-id ).
          CATCH z2ui5_cx_ui5_util_error INTO DATA(lx_act).
            " a refused act changes nothing: neither the pending edits nor the session
            mt_pending = lt_pending_before.
            RAISE EXCEPTION lx_act.
        ENDTRY.

      CATCH cx_root INTO DATA(lx).
        result = VALUE #( is_error = abap_true
                          text     = lx->get_text( )
                          session  = ms_row-id ).
    ENDTRY.

    DATA(lv_args) = |\{"session":{ z2ui5_cl_agent_viewxml=>json_string( session ) }|.
    IF values IS NOT INITIAL.
      lv_args = |{ lv_args },"values":{ mask_values( t_value = lt_value
                                                     app     = ms_row-app ) }|.
    ENDIF.
    IF args IS NOT INITIAL.
      lv_args = |{ lv_args },"args":{ args }|.
    ENDIF.
    IF lv_row IS NOT INITIAL.
      lv_args = |{ lv_args },"row":{ lv_row }|.
    ENDIF.
    audit( operation = `app_act`
           event     = COND string( WHEN ls_action-event IS NOT INITIAL THEN ls_action-event ELSE lv_event )
           args      = |{ lv_args }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD load.

    DATA lv_id TYPE z2ui5_t_ag_ses-id.
    DATA lt_open TYPE string_table.
    DATA lt_pending_db TYPE ty_t_pending_db.

    IF session IS INITIAL.
      fail( `pass session - the session the last snapshot carried (app_start returns the first)` ).
    ENDIF.
    lv_id = condense( session ).
    SELECT SINGLE * FROM z2ui5_t_ag_ses WHERE id = @lv_id AND uname = @sy-uname INTO @ms_row.
    IF sy-subrc <> 0.
      SELECT SINGLE id FROM z2ui5_t_ag_ses WHERE id_prev = @lv_id AND uname = @sy-uname INTO @DATA(lv_current).
      IF sy-subrc = 0.
        fail( |session '{ lv_id }' is an earlier state of this app session - continue with the current one: | &&
              |'{ lv_current }' (app_describe shows it)| ).
      ENDIF.
      SELECT id, app FROM z2ui5_t_ag_ses WHERE uname = @sy-uname ORDER BY changed_at DESCENDING INTO TABLE @DATA(lt_session).
      LOOP AT lt_session INTO DATA(ls_session).
        INSERT |{ ls_session-id } ({ ls_session-app })| INTO TABLE lt_open.
      ENDLOOP.
      fail( |unknown session '{ lv_id }' - start one with app_start{ COND #( WHEN lt_open IS NOT INITIAL
                                                                              THEN |; open sessions: { list_of( lt_open ) }| ) }| ).
    ENDIF.

    DATA(lv_limit) = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = z2ui5_cl_ui5_util_context=>time_get_timestampl( )
                         seconds = 3600 * z2ui5_cl_agent_settings=>get_expiry_hours( ) ).
    IF ms_row-changed_at < lv_limit.
      DELETE FROM z2ui5_t_ag_ses WHERE id = @lv_id.
      fail( |session '{ lv_id }' expired with its draft - app_start { ms_row-app_start } again| ).
    ENDIF.

    TRY.
        IF ms_row-custom IS NOT INITIAL.
          z2ui5_cl_ajson=>parse( ms_row-custom )->to_abap( IMPORTING ev_container = mt_custom ).
        ENDIF.
        IF ms_row-pending IS NOT INITIAL.
          z2ui5_cl_ajson=>parse( ms_row-pending )->to_abap( IMPORTING ev_container = lt_pending_db ).
        ENDIF.
      CATCH cx_root INTO DATA(lx).
        fail( |session '{ lv_id }' is damaged ({ lx->get_text( ) }) - app_start { ms_row-app_start } again| ).
    ENDTRY.
    CLEAR mt_pending.
    LOOP AT lt_pending_db INTO DATA(ls_db).
      DATA(ls_val) = VALUE ty_s_val( kind = ls_db-kind
                                     str  = ls_db-str
                                     json = ls_db-json ).
      IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
        ls_val = z2ui5_cl_agent_viewxml=>val_number( ls_db-str ).
      ENDIF.
      INSERT VALUE #( model_key = ls_db-model_key
                      path      = ls_db-path
                      val       = ls_val ) INTO TABLE mt_pending.
    ENDLOOP.

  ENDMETHOD.

  METHOD save.

    DATA lt_pending_db TYPE ty_t_pending_db.

    LOOP AT mt_pending INTO DATA(ls_pending).
      INSERT VALUE #( model_key = ls_pending-model_key
                      path      = ls_pending-path
                      kind      = ls_pending-val-kind
                      str       = ls_pending-val-str
                      json      = ls_pending-val-json ) INTO TABLE lt_pending_db.
    ENDLOOP.
    TRY.
        DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
        lo_json->set( iv_path = `/`
                      iv_val  = mt_custom ).
        ms_row-custom = lo_json->stringify( ).
        lo_json = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
        lo_json->set( iv_path = `/`
                      iv_val  = lt_pending_db ).
        ms_row-pending = lo_json->stringify( ).
      CATCH cx_root ##NO_HANDLER.
        " both are built from typed tables - nothing to refuse
    ENDTRY.

    ms_row-state = mo_sim->get_state( ).
    ms_row-snapshot = mo_snap->get_json( ).
    ms_row-app = mo_sim->get_app( ).
    ms_row-uname = sy-uname.
    ms_row-changed_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    IF ms_row-created_at IS INITIAL.
      ms_row-created_at = ms_row-changed_at.
    ENDIF.

    IF id_old IS NOT INITIAL AND id_old <> mo_sim->get_id( ).
      DELETE FROM z2ui5_t_ag_ses WHERE id = @id_old.
      ms_row-id_prev = id_old.
    ENDIF.
    ms_row-id = mo_sim->get_id( ).
    MODIFY z2ui5_t_ag_ses FROM @ms_row.

    " sessions whose drafts are gone are gone as well
    DATA(lv_limit) = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = ms_row-changed_at
                         seconds = 3600 * z2ui5_cl_agent_settings=>get_expiry_hours( ) ).
    DELETE FROM z2ui5_t_ag_ses WHERE changed_at < @lv_limit.

  ENDMETHOD.

  METHOD custom_of_sim.

    " the client work of the last response; the VIEW_SLOTS destroys in it
    " were applied to the layers already
    LOOP AT mo_sim->get_actions( ) INTO DATA(ls_action).
      DATA(lv_arg1) = VALUE string( ls_action-t_arg[ 1 ] OPTIONAL ).
      DATA(lv_arg2) = VALUE string( ls_action-t_arg[ 2 ] OPTIONAL ).
      IF ( ls_action-name = `VIEW_SLOTS` AND lv_arg1 = `destroy` )
          OR ( ls_action-name = z2ui5_if_client=>cs_event-control_global AND lv_arg1 = `VIEW_SLOTS` AND lv_arg2 = `destroy` ).
        CONTINUE.
      ENDIF.
      INSERT ls_action-json INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD analyze.

    DATA(ls_input) = VALUE z2ui5_cl_agent_snapshot=>ty_s_input( session   = mo_sim->get_id( )
                                                                 app       = mo_sim->get_app( )
                                                                 t_layer   = mo_sim->get_layers( )
                                                                 t_custom  = mt_custom
                                                                 t_pending = mt_pending
                                                                 max_rows  = mv_max_rows ).
    mo_snap = z2ui5_cl_agent_snapshot=>create( ls_input ).
    LOOP AT mo_snap->mt_action INTO DATA(ls_action) WHERE frontend IS INITIAL. "#EC CI_SORTSEQ
      mo_snap->set_policy( id     = ls_action-id
                           policy = z2ui5_cl_agent_settings=>get_policy( app_start = ms_row-app_start
                                                                         app       = mo_sim->get_app( )
                                                                         event     = ls_action-event )-policy ).
    ENDLOOP.

  ENDMETHOD.

  METHOD parse_input.

    IF json IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( iv_json            = CONV string( json )
                                                                    iv_keep_item_order = abap_true ) ).
      CATCH cx_root.
        IF array = abap_true.
          fail( `args is an array, positional to the action's args (null where the client should fill in the value)` ).
        ENDIF.
        fail( `values is an object: { "<field id, path or name>": value }` ).
    ENDTRY.
    DATA(lv_type) = lo_json->get_node_type( `/` ).
    IF array = abap_true.
      IF lv_type <> z2ui5_if_ajson_types=>node_type-array.
        fail( `args is an array, positional to the action's args (null where the client should fill in the value)` ).
      ENDIF.
      DATA(lv_count) = lines( lo_json->members( `/` ) ).
      DO lv_count TIMES.
        INSERT VALUE #( key = |{ sy-index - 1 }|
                        val = val_of_node( io_json = lo_json
                                           path    = |/{ sy-index }| ) ) INTO TABLE result.
      ENDDO.
      RETURN.
    ENDIF.
    IF lv_type <> z2ui5_if_ajson_types=>node_type-object.
      fail( `values is an object: { "<field id, path or name>": value }` ).
    ENDIF.

    " the keys are model paths ("/T_TAB/2/SELKZ") - a path of the JSON tree
    " cannot address them, so the object is split by hand, in its own order
    LOOP AT object_members( CONV string( json ) ) INTO DATA(ls_member).
      TRY.
          DATA(lo_value) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( iv_json            = |\{"v":{ ls_member-raw }\}|
                                                                       iv_keep_item_order = abap_true ) ).
        CATCH cx_root.
          fail( `values is an object: { "<field id, path or name>": value }` ).
      ENDTRY.
      INSERT VALUE #( key = ls_member-key
                      val = val_of_node( io_json = lo_value
                                         path    = `/v` ) ) INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD object_members.

    DATA lv_depth TYPE i.
    DATA lv_in_string TYPE abap_bool.
    DATA lv_key TYPE string.

    " the top level of a JSON object: each key (unescaped) with the raw text
    " of its value
    DATA(lv_len) = strlen( json ).
    DATA(lv_pos) = find( val = json
                         sub = `{` ).
    IF lv_pos < 0.
      RETURN.
    ENDIF.
    lv_pos = lv_pos + 1.
    DO.
      " the key
      DATA(lv_quote) = find( val = json
                             sub = `"`
                             off = lv_pos ).
      DATA(lv_close) = find( val = json
                             sub = `}`
                             off = lv_pos ).
      IF lv_quote < 0 OR ( lv_close >= 0 AND lv_close < lv_quote ).
        RETURN.
      ENDIF.
      CLEAR lv_key.
      DATA(lv_i) = lv_quote + 1.
      WHILE lv_i < lv_len.
        DATA(lv_c) = json+lv_i(1).
        IF lv_c = `\`.
          DATA(lv_i1) = lv_i + 1.
          DATA(lv_e) = COND string( WHEN lv_i1 < lv_len THEN json+lv_i1(1) ).
          lv_key = lv_key && SWITCH string( lv_e
                                            WHEN `n` THEN cl_abap_char_utilities=>newline
                                            WHEN `t` THEN cl_abap_char_utilities=>horizontal_tab
                                            ELSE lv_e ).
          lv_i = lv_i + 2.
          CONTINUE.
        ENDIF.
        IF lv_c = `"`.
          EXIT.
        ENDIF.
        lv_key = lv_key && lv_c.
        lv_i = lv_i + 1.
      ENDWHILE.
      DATA(lv_colon) = find( val = json
                             sub = `:`
                             off = lv_i + 1 ).
      IF lv_colon < 0.
        RETURN.
      ENDIF.

      " the value, up to the comma or brace that closes it on this level
      DATA(lv_start) = lv_colon + 1.
      lv_i = lv_start.
      lv_depth = 0.
      lv_in_string = abap_false.
      WHILE lv_i < lv_len.
        lv_c = json+lv_i(1).
        IF lv_in_string = abap_true.
          IF lv_c = `\`.
            lv_i = lv_i + 2.
            CONTINUE.
          ENDIF.
          IF lv_c = `"`.
            lv_in_string = abap_false.
          ENDIF.
        ELSEIF lv_c = `"`.
          lv_in_string = abap_true.
        ELSEIF lv_c = `{` OR lv_c = `[`.
          lv_depth = lv_depth + 1.
        ELSEIF ( lv_c = `}` OR lv_c = `]` ) AND lv_depth > 0.
          lv_depth = lv_depth - 1.
        ELSEIF ( lv_c = `,` OR lv_c = `}` ) AND lv_depth = 0.
          EXIT.
        ENDIF.
        lv_i = lv_i + 1.
      ENDWHILE.
      INSERT VALUE #( key = lv_key
                      raw = condense( substring( val = json
                                                 off = lv_start
                                                 len = lv_i - lv_start ) ) ) INTO TABLE result.
      IF lv_i >= lv_len OR json+lv_i(1) = `}`.
        RETURN.
      ENDIF.
      lv_pos = lv_i + 1.
    ENDDO.

  ENDMETHOD.

  METHOD val_of_node.

    CASE io_json->get_node_type( path ).
      WHEN z2ui5_if_ajson_types=>node_type-string.
        result = z2ui5_cl_agent_viewxml=>val_string( io_json->get( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-number.
        result = z2ui5_cl_agent_viewxml=>val_number( io_json->get( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-boolean.
        result = z2ui5_cl_agent_viewxml=>val_boolean( io_json->get_boolean( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-object OR z2ui5_if_ajson_types=>node_type-array.
        result-kind = COND #( WHEN io_json->get_node_type( path ) = z2ui5_if_ajson_types=>node_type-array
                              THEN z2ui5_cl_agent_viewxml=>cs_kind-array
                              ELSE z2ui5_cl_agent_viewxml=>cs_kind-object ).
        TRY.
            result-json = io_json->slice( path )->stringify( ).
          CATCH cx_root.
            result-json = `null`.
        ENDTRY.
        result-num = lines( io_json->members( path ) ).
      WHEN OTHERS.
        result-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
    ENDCASE.

  ENDMETHOD.

  METHOD layer_note.

    " a dialog in front of the page: the page's fields and actions are not
    " on the screen until it closes - said, so a refusal does not read as
    " "the field is gone"
    IF mo_snap->mv_layer <> `main`.
      result = | (a { mo_snap->mv_layer } is open: only its fields and actions count until it closes)|.
    ENDIF.

  ENDMETHOD.

  METHOD field_help.

    DATA lt_editable TYPE string_table.
    DATA lt_cells TYPE string_table.

    LOOP AT mo_snap->mt_field INTO DATA(ls_field) WHERE editable = abap_true. "#EC CI_SORTSEQ
      INSERT |{ ls_field-id } ({ ls_field-label }, { ls_field-path })| INTO TABLE lt_editable.
    ENDLOOP.
    LOOP AT mo_snap->mt_table INTO DATA(ls_table).
      IF ls_table-t_editable IS INITIAL.
        CONTINUE.
      ENDIF.
      INSERT |{ ls_table-path }/<row 0-{ nmax( val1 = 0
                                               val2 = ls_table-row_count - 1 ) }>/\{{ concat_lines_of( table = ls_table-t_editable
                                                                                                       sep   = `|` ) }\} (table { ls_table-id })|
             INTO TABLE lt_cells.
    ENDLOOP.
    result = COND #( WHEN lt_editable IS NOT INITIAL THEN |fields you can fill: { list_of( lt_editable ) }|
                     ELSE `no editable field on this screen` ).
    IF lt_cells IS NOT INITIAL.
      result = |{ result }; table cells: { list_of( lt_cells ) }|.
    ENDIF.
    result = result && layer_note( ).

  ENDMETHOD.

  METHOD action_help.

    DATA lt_item TYPE string_table.

    LOOP AT mo_snap->mt_action INTO DATA(ls_action) WHERE enabled = abap_true. "#EC CI_SORTSEQ
      INSERT |{ ls_action-event } ({ ls_action-id } "{ ls_action-label }"| &&
             |{ COND #( WHEN ls_action-scope = `row` THEN |, row action of { ls_action-table }| ) }| &&
             |{ COND #( WHEN ls_action-policy IS NOT INITIAL AND ls_action-policy <> z2ui5_if_agent_app=>cs_policy-allowed
                        THEN |, { ls_action-policy } - not for agents| ) })| INTO TABLE lt_item.
    ENDLOOP.
    result = COND #( WHEN lt_item IS NOT INITIAL THEN |allowed events: { list_of( lt_item ) }|
                     ELSE `this screen offers no action` ).
    result = result && layer_note( ).

  ENDMETHOD.

  METHOD resolve_target.

    found = abap_false.
    LOOP AT mo_snap->mt_field INTO DATA(ls_field) WHERE id = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.
    LOOP AT mo_snap->mt_field INTO ls_field WHERE path = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.
    DATA(lv_upper) = to_upper( key ).
    LOOP AT mo_snap->mt_field INTO ls_field.
      IF to_upper( ls_field-name ) = lv_upper.
        found = abap_true.
        result-field = sy-tabix.
        RETURN.
      ENDIF.
    ENDLOOP.

    " a table cell: /T_TAB/3/QTY or t1/3/QTY
    SPLIT key AT `/` INTO TABLE DATA(lt_seg).
    DATA(lv_count) = lines( lt_seg ).
    IF lv_count < 3.
      RETURN.
    ENDIF.
    DATA(lv_column) = lt_seg[ lv_count ].
    DATA(lv_row) = lt_seg[ lv_count - 1 ].
    IF lv_row IS INITIAL OR lv_row CN `0123456789` OR lv_column IS INITIAL
        OR lv_column(1) CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`
        OR lv_column CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-`.
      RETURN.
    ENDIF.
    DATA(lv_table) = substring( val = key
                                len = strlen( key ) - strlen( lv_row ) - strlen( lv_column ) - 2 ).
    LOOP AT mo_snap->mt_table INTO DATA(ls_table).
      IF ls_table-path = lv_table OR ls_table-id = lv_table.
        found = abap_true.
        result = VALUE #( is_cell = abap_true
                          table   = sy-tabix
                          row     = CONV i( lv_row )
                          column  = lv_column ).
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD coerce.

    " the value in the type the model holds there (a Number input bound to a
    " string attribute stays a string, a boolean stays a boolean)
    IF kind = `boolean`.
      IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean.
        result = val.
      ELSEIF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-string AND ( val-str = `true` OR val-str = `false` ).
        result = z2ui5_cl_agent_viewxml=>val_boolean( xsdbool( val-str = `true` ) ).
      ELSE.
        fail( |{ label } is a boolean - pass true or false, not { val_json_quoted( val ) }| ).
      ENDIF.
      RETURN.
    ENDIF.
    IF kind = `multichoice`.
      IF val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array.
        fail( |{ label } is a multichoice - pass an array of keys| ).
      ENDIF.
      " every element as a string
      DATA(lt_key) = VALUE string_table( ).
      TRY.
          DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( val-json ) ).
          DATA(lv_count) = lines( lo_json->members( `/` ) ).
          DO lv_count TIMES.
            DATA(ls_element) = val_of_node( io_json = lo_json
                                            path    = |/{ sy-index }| ).
            INSERT z2ui5_cl_agent_viewxml=>json_string( z2ui5_cl_agent_viewxml=>val_to_string( ls_element ) ) INTO TABLE lt_key.
          ENDDO.
        CATCH cx_root.
          fail( |{ label } is a multichoice - pass an array of keys| ).
      ENDTRY.
      result = VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-array
                        json = |[{ concat_lines_of( table = lt_key
                                                    sep   = `,` ) }]|
                        num  = lines( lt_key ) ).
      RETURN.
    ENDIF.
    IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-object OR val-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
      fail( |{ label } takes a single value, not { substring( val = val-json
                                                              len = nmin( val1 = 80
                                                                          val2 = strlen( val-json ) ) ) }| ).
    ENDIF.
    IF current-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
      DATA(ls_num) = z2ui5_cl_agent_viewxml=>describe_arg( z2ui5_cl_agent_viewxml=>val_to_string( val ) ).
      IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number AND val-nan = abap_false.
        result = val.
      ELSEIF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-string AND ls_num-static = abap_true
          AND ls_num-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
        result = ls_num-val.
      ELSE.
        fail( |{ label } holds a number - { val_json_quoted( val ) } is none| ).
      ENDIF.
      RETURN.
    ENDIF.
    IF current-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean.
      result = coerce( val     = val
                       current = VALUE #( )
                       kind    = `boolean`
                       label   = label ).
      RETURN.
    ENDIF.
    IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null OR val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR val-kind IS INITIAL.
      result = z2ui5_cl_agent_viewxml=>val_string( `` ).
    ELSE.
      result = z2ui5_cl_agent_viewxml=>val_string( z2ui5_cl_agent_viewxml=>val_to_string( val ) ).
    ENDIF.

  ENDMETHOD.

  METHOD val_json_quoted.

    result = z2ui5_cl_agent_viewxml=>val_to_json( val ).

  ENDMETHOD.

  METHOD apply_values.

    DATA lv_found TYPE abap_bool.
    DATA lt_plan TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.

    LOOP AT t_value INTO DATA(ls_value).
      DATA(ls_target) = resolve_target( EXPORTING key   = ls_value-key
                                        IMPORTING found = lv_found ).
      IF lv_found = abap_false.
        fail( |no field '{ ls_value-key }' on this screen - { field_help( ) }| ).
      ENDIF.

      IF ls_target-is_cell = abap_false.
        DATA(ls_field) = mo_snap->mt_field[ ls_target-field ].
        DATA(lv_label) = |field { ls_field-id } ({ ls_field-label })|.
        IF ls_field-editable = abap_false.
          fail( |field { ls_field-id } ({ ls_field-label }) is not editable - { field_help( ) }| ).
        ENDIF.
        DATA(ls_val) = coerce( val     = ls_value-val
                               current = mo_snap->model_value( model_key = ls_field-model_key
                                                               path      = ls_field-path )
                               kind    = ls_field-kind
                               label   = lv_label ).
        IF ( ls_field-kind = `choice` OR ls_field-kind = `multichoice` ) AND ls_field-has_values = abap_true.
          DATA(lt_keys) = VALUE string_table( ).
          DATA(lt_quoted) = VALUE string_table( ).
          LOOP AT ls_field-t_value INTO DATA(ls_choice).
            INSERT z2ui5_cl_agent_viewxml=>val_to_string( ls_choice-key ) INTO TABLE lt_keys.
            INSERT |'{ z2ui5_cl_agent_viewxml=>val_to_string( ls_choice-key ) }'| INTO TABLE lt_quoted.
          ENDLOOP.
          DATA(lt_given) = VALUE string_table( ).
          IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
            TRY.
                DATA(lo_keys) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( ls_val-json ) ).
                DATA(lv_key_count) = lines( lo_keys->members( `/` ) ).
                DO lv_key_count TIMES.
                  INSERT lo_keys->get( |/{ sy-index }| ) INTO TABLE lt_given.
                ENDDO.
              CATCH cx_root ##NO_HANDLER.
                " built by coerce( ) - always an array of strings
            ENDTRY.
          ELSE.
            INSERT z2ui5_cl_agent_viewxml=>val_to_string( ls_val ) INTO TABLE lt_given.
          ENDIF.
          LOOP AT lt_given INTO DATA(lv_one).
            IF NOT line_exists( lt_keys[ table_line = lv_one ] ). "#EC CI_SORTSEQ
              fail( |{ lv_label }: '{ lv_one }' is not one of its values - allowed keys: { list_of( lt_quoted ) }| ).
            ENDIF.
          ENDLOOP.
          " a choice keyed by index (RadioButtonGroup) keeps its number
          DATA(ls_first) = VALUE z2ui5_cl_agent_snapshot=>ty_s_choice( ls_field-t_value[ 1 ] OPTIONAL ).
          IF ls_field-kind = `choice` AND ls_first-key-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
            ls_val = z2ui5_cl_agent_viewxml=>val_number( z2ui5_cl_agent_viewxml=>number_normalize(
                                                             z2ui5_cl_agent_viewxml=>val_to_string( ls_val ) ) ).
          ENDIF.
        ENDIF.
        INSERT VALUE #( model_key = ls_field-model_key
                        path      = ls_field-path
                        val       = ls_val ) INTO TABLE lt_plan.
        CONTINUE.
      ENDIF.

      DATA(ls_table) = mo_snap->mt_table[ ls_target-table ].
      IF NOT line_exists( ls_table-t_editable[ table_line = ls_target-column ] ). "#EC CI_SORTSEQ
        fail( |column { ls_target-column } of table { ls_table-id } is not editable - editable columns: | &&
              |{ COND #( WHEN ls_table-t_editable IS NOT INITIAL
                         THEN concat_lines_of( table = ls_table-t_editable
                                               sep   = `, ` )
                         ELSE `none` ) }| ).
      ENDIF.
      IF ls_target-row >= ls_table-row_count.
        fail( |table { ls_table-id } has { ls_table-row_count } row(s) - row { ls_target-row } does not exist (rows are 0-based)| ).
      ENDIF.
      IF mo_snap->cell_editable( table_id = ls_table-id
                                 column   = ls_target-column
                                 row      = ls_target-row ) = abap_false.
        fail( |cell { ls_target-column } of row { ls_target-row } in table { ls_table-id } is not editable in that row| ).
      ENDIF.
      DATA(lv_path) = |{ ls_table-path }/{ ls_target-row }/{ ls_target-column }|.
      DATA(ls_spec) = VALUE z2ui5_cl_agent_snapshot=>ty_s_cellspec( ).
      READ TABLE ls_table-t_cellspec INTO ls_spec WITH KEY name = ls_target-column. "#EC CI_SORTSEQ
      DATA(lv_kind) = COND string( WHEN ls_spec-has_field_spec = abap_true THEN ls_spec-field_kind
                                   WHEN ls_target-column = ls_table-selection_field THEN `boolean`
                                   ELSE `text` ).
      INSERT VALUE #( model_key = ls_table-model_key
                      path      = lv_path
                      val       = coerce( val     = ls_value-val
                                          current = mo_snap->model_value( model_key = ls_table-model_key
                                                                          path      = lv_path )
                                          kind    = lv_kind
                                          label   = |cell { lv_path }| ) ) INTO TABLE lt_plan.
    ENDLOOP.

    LOOP AT lt_plan INTO DATA(ls_plan).
      DELETE mt_pending WHERE model_key = ls_plan-model_key AND path = ls_plan-path. "#EC CI_SORTSEQ
      INSERT ls_plan INTO TABLE mt_pending.
      INSERT ls_plan-path INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD find_action.

    DATA lt_named TYPE z2ui5_cl_agent_snapshot=>ty_t_action.
    DATA lt_enabled TYPE z2ui5_cl_agent_snapshot=>ty_t_action.

    READ TABLE mo_snap->mt_action INTO result WITH KEY id = event. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    LOOP AT mo_snap->mt_action INTO DATA(ls_action) WHERE event = event. "#EC CI_SORTSEQ
      INSERT ls_action INTO TABLE lt_named.
      IF ls_action-enabled = abap_true.
        INSERT ls_action INTO TABLE lt_enabled.
      ENDIF.
    ENDLOOP.
    IF lt_named IS INITIAL.
      fail( |no action '{ event }' on this screen - { action_help( ) }| ).
    ENDIF.
    DATA(lt_pool) = COND z2ui5_cl_agent_snapshot=>ty_t_action( WHEN lt_enabled IS NOT INITIAL THEN lt_enabled ELSE lt_named ).
    IF has_row = abap_true.
      READ TABLE lt_pool INTO result WITH KEY scope = `row`. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
    ENDIF.
    result = lt_pool[ 1 ].

  ENDMETHOD.

  METHOD event_args.

    DATA lv_row TYPE i VALUE -1.
    DATA ls_explicit TYPE ty_s_val.

    DATA(lt_desc) = is_action-t_wire_arg.
    IF lines( t_given ) > lines( lt_desc ).
      fail( |action { is_action-id } ({ is_action-event }) takes { lines( lt_desc ) } argument(s) - | &&
            |[{ concat_lines_of( table = is_action-t_arg_json
                                 sep   = `,` ) }]; { lines( t_given ) } given| ).
    ENDIF.
    IF is_action-scope <> `row` AND row_raw IS NOT INITIAL.
      fail( |row is for row actions - { is_action-id } ({ is_action-event }) is a screen action; leave row out| ).
    ENDIF.

    IF is_action-scope = `row`.
      DATA(lv_count) = mo_snap->table_rows( is_action-table ).
      IF row_raw IS INITIAL.
        LOOP AT lt_desc INTO DATA(ls_desc).
          ls_explicit = VALUE #( t_given[ sy-tabix ]-val OPTIONAL ).
          IF ls_desc-static = abap_false AND ( ls_desc-kind = `row` OR ls_desc-kind = `source` )
              AND ( ls_explicit-kind IS INITIAL OR ls_explicit-kind = z2ui5_cl_agent_viewxml=>cs_kind-null ).
            fail( |action { is_action-id } ({ is_action-event }) is a row action of table { is_action-table } ({ lv_count } rows) - | &&
                  |pass row (0-{ nmax( val1 = 0
                                       val2 = lv_count - 1 ) })| ).
          ENDIF.
        ENDLOOP.
      ELSE.
        DATA(ls_row) = z2ui5_cl_agent_viewxml=>describe_arg( row_raw ).
        IF ls_row-static = abap_false OR ls_row-val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-number
            OR ls_row-val-num <> trunc( ls_row-val-num ) OR ls_row-val-num < 0 OR ls_row-val-num >= lv_count.
          fail( |table { is_action-table } has { lv_count } row(s) - row { row_raw } does not exist (rows are 0-based)| ).
        ENDIF.
        lv_row = ls_row-val-num.
      ENDIF.
    ENDIF.

    LOOP AT lt_desc INTO ls_desc.
      DATA(lv_index) = sy-tabix - 1.
      ls_explicit = VALUE #( t_given[ lv_index + 1 ]-val OPTIONAL ).
      DATA(lv_explicit) = xsdbool( ls_explicit-kind IS NOT INITIAL AND ls_explicit-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null ).
      IF ls_desc-static = abap_true.
        IF lv_explicit = abap_true AND z2ui5_cl_agent_viewxml=>val_to_json( ls_explicit ) <> z2ui5_cl_agent_viewxml=>val_to_json( ls_desc-val ).
          fail( |argument { lv_index } of { is_action-event } is static ({ z2ui5_cl_agent_viewxml=>val_to_json( ls_desc-val ) }) - pass null there| ).
        ENDIF.
        INSERT ls_desc-val INTO TABLE result.
        CONTINUE.
      ENDIF.
      IF lv_explicit = abap_true.
        IF ls_desc-kind = `action` AND is_action-has_choices = abap_true
            AND NOT line_exists( is_action-t_choice[ table_line = z2ui5_cl_agent_viewxml=>val_to_string( ls_explicit ) ] ). "#EC CI_SORTSEQ
          fail( |argument { lv_index } of { is_action-event }: '{ z2ui5_cl_agent_viewxml=>val_to_string( ls_explicit ) }' | &&
                |is not one of { list_of( is_action-t_choice ) }| ).
        ENDIF.
        INSERT ls_explicit INTO TABLE result.
        CONTINUE.
      ENDIF.
      CASE ls_desc-kind.
        WHEN `row`.
          IF lv_row < 0.
            fail( |argument { lv_index } of { is_action-event } ({ ls_desc-describe }) reads a row - pass row, or the value in args[{ lv_index }]| ).
          ENDIF.
          DATA(ls_val) = mo_snap->model_value( model_key = is_action-model_key
                                               path      = ls_desc-path
                                               table_id  = is_action-table
                                               row       = lv_row ).
          IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
            ls_val = z2ui5_cl_agent_viewxml=>val_string( `` ).
          ENDIF.
          INSERT ls_val INTO TABLE result.
        WHEN `model`.
          ls_val = mo_snap->model_value( model_key = is_action-model_key
                                         path      = ls_desc-path ).
          IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
            ls_val = z2ui5_cl_agent_viewxml=>val_string( `` ).
          ENDIF.
          INSERT ls_val INTO TABLE result.
        WHEN `source`.
          ls_val = mo_snap->source_value( action_id = is_action-id
                                          prop      = ls_desc-prop
                                          row       = lv_row ).
          IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
            fail( |argument { lv_index } of { is_action-event } ({ ls_desc-describe }) cannot be read here - pass it in args[{ lv_index }]| ).
          ENDIF.
          INSERT ls_val INTO TABLE result.
        WHEN `action`.
          DATA(lv_choice) = VALUE string( is_action-t_choice[ 1 ] DEFAULT `OK` ).
          INSERT z2ui5_cl_agent_viewxml=>val_string( lv_choice ) INTO TABLE result.
        WHEN OTHERS.
          fail( |argument { lv_index } of { is_action-event } ({ ls_desc-describe }) is computed in the browser - pass its value in args[{ lv_index }]| ).
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.

  METHOD sim_text.

    " an event argument as the text the simulator sends (click( ) t_arg): a
    " boolean as abap_bool, as the core turns the browser's true / false
    " into X / space
    CASE val-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-boolean.
        result = COND #( WHEN val-str = `true` THEN `X` ).
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-string OR z2ui5_cl_agent_viewxml=>cs_kind-number.
        result = val-str.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-object OR z2ui5_cl_agent_viewxml=>cs_kind-array.
        result = val-json.
      WHEN OTHERS.
        CLEAR result.
    ENDCASE.

  ENDMETHOD.

  METHOD send.

    DATA lt_arg TYPE string_table.
    DATA lt_keep TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.

    " the edits of the model the event's view owns, as typed JSON values at
    " their model paths - the simulator builds the frontend's delta from
    " them (core/Lib.js buildDeltaFromPaths): a table cell as a row delta,
    " anything else - a boolean, an array, a structure that holds a table -
    " as the whole top-level attribute
    DATA(lv_model_key) = COND string( WHEN is_action-model_key IS INITIAL
                                      THEN z2ui5_cl_agent_snapshot=>cs_model-main
                                      ELSE is_action-model_key ).
    TRY.
        LOOP AT mt_pending INTO DATA(ls_pending).
          IF ls_pending-model_key <> lv_model_key.
            INSERT ls_pending INTO TABLE lt_keep.
            CONTINUE.
          ENDIF.
          mo_sim->set_json( path  = ls_pending-path
                            json  = z2ui5_cl_agent_viewxml=>val_to_json( ls_pending-val )
                            layer = lv_model_key ).
        ENDLOOP.
      CATCH cx_root INTO DATA(lx_value).
        fail( |the pending values could not be sent - { lx_value->get_text( ) }; nothing was sent| ).
    ENDTRY.

    LOOP AT t_arg INTO DATA(ls_arg).
      INSERT sim_text( ls_arg ) INTO TABLE lt_arg.
    ENDLOOP.

    TRY.
        mo_sim->click( event = is_action-event
                       t_arg = lt_arg
                       layer = lv_model_key ).
      CATCH cx_root INTO DATA(lx).
        fail( |the backend refused the roundtrip - { lx->get_text( ) }| ).
    ENDTRY.
    IF mo_sim->is_sticky( ) = abap_true.
      DELETE FROM z2ui5_t_ag_ses WHERE id = @ms_row-id.
      fail( |the app switched to a stateful session (set_session_stateful) - such a session lives in one request only, | &&
            |so this agent session ended; app_start { ms_row-app_start } again| ).
    ENDIF.

    " edits of another layer's model survive, as long as that layer is open
    mt_custom = custom_of_sim( ).
    DATA(lt_layer) = mo_sim->get_layers( ).
    CLEAR mt_pending.
    LOOP AT lt_keep INTO DATA(ls_keep).
      IF line_exists( lt_layer[ layer = ls_keep-model_key ] ). "#EC CI_SORTSEQ
        INSERT ls_keep INTO TABLE mt_pending.
      ENDIF.
    ENDLOOP.
    analyze( ).

  ENDMETHOD.

  METHOD close_layer.

    " performed in the browser: the simulator closes the slot without a
    " roundtrip, and get_state( ) - what the session is saved with - no
    " longer carries it
    TRY.
        mo_sim->close_layer( slot ).
      CATCH cx_root INTO DATA(lx).
        fail( |the { slot } could not be closed - { lx->get_text( ) }| ).
    ENDTRY.

    DELETE mt_pending WHERE model_key = slot. "#EC CI_SORTSEQ
    CLEAR mt_custom.
    analyze( ).

  ENDMETHOD.

  METHOD mask_values.

    DATA lt_part TYPE string_table.
    DATA lv_found TYPE abap_bool.

    " the arguments as JSON, a value masked when the app or the settings
    " mark its field sensitive, or when it is typed into a password input
    LOOP AT t_value INTO DATA(ls_value).
      DATA(lv_masked) = abap_false.
      DATA(lv_app) = COND string( WHEN mo_sim IS BOUND THEN mo_sim->get_app( ) ELSE app ).
      IF mo_snap IS NOT BOUND.
        " no screen to resolve the key against: judged by the key alone
        lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                              path = ls_value-key
                                                              name = ls_value-key ).
      ELSE.
        DATA(ls_target) = resolve_target( EXPORTING key   = ls_value-key
                                          IMPORTING found = lv_found ).
        IF lv_found = abap_true AND ls_target-is_cell = abap_false.
          DATA(ls_field) = mo_snap->mt_field[ ls_target-field ].
          lv_masked = xsdbool( mo_snap->is_secret( ls_field-id ) = abap_true
                            OR z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                         path = ls_field-path
                                                                         name = ls_field-name ) = abap_true ).
        ELSEIF lv_found = abap_true.
          DATA(ls_table) = mo_snap->mt_table[ ls_target-table ].
          lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                path = |{ ls_table-path }/{ ls_target-row }/{ ls_target-column }|
                                                                name = ls_target-column ).
        ELSE.
          lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                path = ls_value-key
                                                                name = ls_value-key ).
        ENDIF.
      ENDIF.
      INSERT |{ z2ui5_cl_agent_viewxml=>json_string( ls_value-key ) }:| &&
             |{ COND #( WHEN lv_masked = abap_true
                        THEN z2ui5_cl_agent_viewxml=>json_string( z2ui5_cl_agent_audit=>c_mask )
                        ELSE z2ui5_cl_agent_viewxml=>val_to_json( ls_value-val ) ) }| INTO TABLE lt_part.
    ENDLOOP.
    result = |\{{ concat_lines_of( table = lt_part
                                   sep   = `,` ) }\}|.

  ENDMETHOD.

ENDCLASS.
