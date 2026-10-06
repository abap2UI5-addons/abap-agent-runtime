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
"!
"! The in-app copilot (z2ui5_cl_agent_assist) uses the same class in mode
"! copilot: app_attach( ) continues a copy of the draft the user's browser
"! is on (instead of app_start( )), app_check( ) validates an act without
"! sending it, and the copilot switch of the settings replaces the
"! endpoint switch - the validation and the policy are the very same.
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

    CONSTANTS:
      BEGIN OF cs_mode,
        mcp     TYPE string VALUE `mcp`,
        copilot TYPE string VALUE `copilot`,
      END OF cs_mode.

    "! client: the MCP client's name and version (for the audit log).
    "! mode: mcp (the endpoint, its switch) or copilot (the in-app copilot,
    "! the copilot switch of the language model settings).
    METHODS constructor
      IMPORTING
        client TYPE clike OPTIONAL
        mode   TYPE clike DEFAULT cs_mode-mcp
          PREFERRED PARAMETER client.

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

    "! Continue the screen of a draft the browser is on - a copy of it, so
    "! the user's own draft is never touched: the copy is restored with a
    "! restore roundtrip (the app's main( ) runs check_on_navigated( ) and
    "! displays its main view; a popup that was open is not part of a
    "! draft) and becomes an agent session of this user.
    METHODS app_attach
      IMPORTING
        draft         TYPE clike
        max_rows      TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! app_act( ) without the act: everything validated exactly as app_act( )
    "! validates it - the action, its policy, every value, the arguments -
    "! but nothing is sent and nothing is saved. text: the snapshot with
    "! the values applied as pending.
    METHODS app_check
      IMPORTING
        session       TYPE clike
        values        TYPE clike OPTIONAL
        event         TYPE clike OPTIONAL
        args          TYPE clike OPTIONAL
        row           TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! The analysed screen of a session (no roundtrip) - the snapshot and
    "! its index: which field is a password input, the model values.
    METHODS get_snapshot
      IMPORTING
        session       TYPE clike
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_snapshot
      RAISING
        z2ui5_cx_ui5_util_error.

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

    TYPES ty_t_int TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    TYPES:
      "! A value of a row event's $parameters (row_event_params): kind i an
      "! item of a row, c the row's binding context, l a cell of an item
      "! (cell: its 0-based index), a an array of items or contexts (elem,
      "! t_row), o the parameters themselves, v a plain value (val - undefined
      "! and null included), ? a value this client cannot know.
      BEGIN OF ty_s_pnode,
        kind  TYPE c LENGTH 1,
        elem  TYPE c LENGTH 1,
        row   TYPE i,
        cell  TYPE i,
        t_row TYPE ty_t_int,
        val   TYPE ty_s_val,
      END OF ty_s_pnode.

    TYPES:
      BEGIN OF ty_s_param,
        name TYPE string,
        node TYPE ty_s_pnode,
      END OF ty_s_param.
    TYPES ty_t_param TYPE STANDARD TABLE OF ty_s_param WITH EMPTY KEY.

    TYPES:
      "! The parameters of a row event - active = abap_false when the event's
      "! parameters are not the row (or no row is known).
      BEGIN OF ty_s_params,
        active  TYPE abap_bool,
        t_param TYPE ty_t_param,
      END OF ty_s_params.

    DATA mv_client TYPE string.
    DATA mv_mode TYPE string.
    DATA mv_dry_run TYPE abap_bool.
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

    "! The checked action once more, from the snapshot the values or the
    "! pick changed - refused when it is gone or no longer the event whose
    "! policy was checked.
    METHODS action_again
      IMPORTING
        id            TYPE string
        event         TYPE string
        refusal       TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_action
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS event_args
      IMPORTING
        is_action     TYPE z2ui5_cl_agent_snapshot=>ty_s_action
        t_given       TYPE ty_t_input
        row_raw       TYPE string
        t_picked      TYPE ty_t_int OPTIONAL
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_t_val
      RAISING
        z2ui5_cx_ui5_util_error.

    "! The 0-based row of row_raw, checked against the table's rows; -1
    "! without a row.
    METHODS row_index
      IMPORTING
        table_id      TYPE string
        count         TYPE i
        row_raw       TYPE string
      RETURNING
        VALUE(result) TYPE i
      RAISING
        z2ui5_cx_ui5_util_error.

    "! A selection dialog's confirm picks a row (see the implementation) -
    "! the selected rows, 0-based, in model order.
    METHODS apply_pick
      IMPORTING
        is_action     TYPE z2ui5_cl_agent_snapshot=>ty_s_action
        row_raw       TYPE string
      RETURNING
        VALUE(result) TYPE ty_t_int
      RAISING
        z2ui5_cx_ui5_util_error.

    "! A pending value set - in its place when the path is pending already.
    METHODS pending_set
      IMPORTING
        is_pending TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.

    METHODS row_event_params
      IMPORTING
        is_action     TYPE z2ui5_cl_agent_snapshot=>ty_s_action
        is_table      TYPE z2ui5_cl_agent_snapshot=>ty_s_table
        has_rows      TYPE abap_bool
        t_row         TYPE ty_t_int
      RETURNING
        VALUE(result) TYPE ty_s_params.

    METHODS row_param_arg
      IMPORTING
        is_desc       TYPE z2ui5_cl_agent_viewxml=>ty_s_arg
        is_params     TYPE ty_s_params
        is_table      TYPE z2ui5_cl_agent_snapshot=>ty_s_table
      RETURNING
        VALUE(result) TYPE ty_s_pnode.

    METHODS walk_params
      IMPORTING
        is_params     TYPE ty_s_params
        path          TYPE string
        is_table      TYPE z2ui5_cl_agent_snapshot=>ty_s_table
      RETURNING
        VALUE(result) TYPE ty_s_pnode.

    METHODS head_of
      IMPORTING
        is_params     TYPE ty_s_params
        path          TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_pnode.

    METHODS param_expr
      IMPORTING
        raw           TYPE string
        is_params     TYPE ty_s_params
        is_table      TYPE z2ui5_cl_agent_snapshot=>ty_s_table
      RETURNING
        VALUE(result) TYPE ty_s_pnode.

    CLASS-METHODS pnode_value
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE ty_s_pnode.

    CLASS-METHODS pnode_truthy
      IMPORTING
        is_node       TYPE ty_s_pnode
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS skip_ws
      IMPORTING
        val           TYPE string
        pos           TYPE i
      RETURNING
        VALUE(result) TYPE i.

    CLASS-METHODS str_trim
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE string.

    "! A JavaScript literal of the ternary shape at off: '...', "...",
    "! null or a number, with nothing but blanks after it.
    CLASS-METHODS tail_literal
      IMPORTING
        val           TYPE string
        off           TYPE i
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_s_val.

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

    "! Discard what the app left open in the LUW: abap2UI5 rolls back after
    "! main( ) only when main( ) returns and the app is not stateful - after
    "! a failed or a stateful roundtrip the session's own entries, and the
    "! commit that follows them, must not take the app's work with them.
    CLASS-METHODS app_rollback.

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
    mv_mode = mode.

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

    IF mv_mode = cs_mode-copilot.
      IF z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot ) = abap_false.
        fail( `the in-app copilot is switched off on this system - an agent administrator switches it on in ` &&
              `Z2UI5_CL_AGENT_APP_ADMIN ("Language model")` ).
      ENDIF.
      RETURN.
    ENDIF.
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
    " clamped before it becomes an integer - 10000000000 does not fit one
    IF ls_arg-val-num < 0.
      result = 0.
    ELSEIF ls_arg-val-num > z2ui5_cl_agent_snapshot=>c_max_rows_limit.
      result = z2ui5_cl_agent_snapshot=>c_max_rows_limit.
    ELSE.
      result = trunc( ls_arg-val-num ).
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
            app_rollback( ).
            fail( |the app { lv_app } failed to start - { lx_start->get_text( ) }| ).
        ENDTRY.
        IF mo_sim->is_sticky( ) = abap_true.
          app_rollback( ).
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
            IF lv_event IS NOT INITIAL.
              DATA(lv_action_id) = ls_action-id.
              DATA(lv_action_event) = ls_action-event.
              ls_action = action_again( id      = lv_action_id
                                        event   = lv_action_event
                                        refusal = |the values change the screen - action { lv_action_id } is no longer { lv_action_event }; | &&
                                                  |fill the values without an event first, then fire it from the next snapshot| ).
            ENDIF.
            IF mv_dry_run = abap_true.
              " checked: the action, its policy, every value - the arguments
              " too, unless the act closes a layer or picks a row (that
              " changes the session itself)
              IF lv_event IS NOT INITIAL AND ls_action-frontend IS INITIAL AND ls_action-pick = abap_false.
                event_args( is_action = ls_action
                            t_given   = lt_arg
                            row_raw   = lv_row ).
              ENDIF.
              result = VALUE #( text    = mo_snap->get_json( )
                                session = ms_row-id ).
              mt_pending = lt_pending_before.
            ELSEIF lv_event IS INITIAL.
              save( ).
            ELSEIF ls_action-frontend IS NOT INITIAL.
              " performed here, as the browser performs it: the slot closes,
              " its unsent edits go with it, no roundtrip
              close_layer( ls_action-frontend ).
              save( ).
            ELSE.
              " a selection dialog's confirm picks the row first - its
              " edits are part of the model the arguments read
              DATA(lt_picked) = VALUE z2ui5_cl_agent_viewxml=>ty_t_int( ).
              IF ls_action-pick = abap_true.
                lt_picked = apply_pick( is_action = ls_action
                                        row_raw   = lv_row ).
                analyze( ).
                ls_action = action_again( id      = lv_action_id
                                          event   = lv_action_event
                                          refusal = |the pick changes the screen - action { lv_action_id } is no longer { lv_action_event }| ).
              ENDIF.
              DATA(lt_tval) = event_args( is_action = ls_action
                                          t_given   = lt_arg
                                          row_raw   = lv_row
                                          t_picked  = lt_picked ).
              DATA(lv_id_old) = ms_row-id.
              send( is_action = ls_action
                    t_arg     = lt_tval ).
              save( lv_id_old ).
            ENDIF.
            IF mv_dry_run = abap_false.
              result = VALUE #( text    = ms_row-snapshot
                                session = ms_row-id ).
            ENDIF.
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
    audit( operation = COND #( WHEN mv_dry_run = abap_true THEN `app_check` ELSE `app_act` )
           event     = COND string( WHEN ls_action-event IS NOT INITIAL THEN ls_action-event ELSE lv_event )
           args      = |{ lv_args }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD app_attach.

    DATA lv_reason TYPE string.
    DATA lv_copy TYPE string.

    TRY.
        check_enabled( ).
        mv_max_rows = rows_of( val     = max_rows
                               default = z2ui5_cl_agent_snapshot=>c_max_rows_default ).
        IF draft IS INITIAL.
          fail( `pass draft - the draft id of the screen to continue` ).
        ENDIF.

        " a copy - the user's own draft stays as the browser left it
        TRY.
            DATA(lo_store) = z2ui5_cl_ui5_srv_draft=>get_instance( ).
            DATA(ls_db) = lo_store->read_draft( draft ).
            lv_copy = z2ui5_cl_ui5_util_context=>uuid_get_c32( ).
            lo_store->create( draft     = VALUE #( id                = lv_copy
                                                   id_prev           = ls_db-id_prev
                                                   id_prev_app       = ls_db-id_prev_app
                                                   id_prev_app_stack = ls_db-id_prev_app_stack )
                              model_xml = ls_db-data ).
          CATCH cx_root INTO DATA(lx_copy).
            fail( |the draft { draft } cannot be read - { lx_copy->get_text( ) }| ).
        ENDTRY.
        TRY.
            mo_sim = z2ui5_cl_frontend_simulator=>resume( id      = lv_copy
                                                          refresh = abap_true ).
          CATCH cx_root INTO DATA(lx_resume).
            app_rollback( ).
            fail( |the screen of draft { draft } cannot be restored - { lx_resume->get_text( ) }| ).
        ENDTRY.
        DATA(lv_app) = mo_sim->get_app( ).
        IF z2ui5_cl_agent_settings=>check_app( EXPORTING app    = lv_app
                                               IMPORTING reason = lv_reason ) = abap_false.
          fail( lv_reason ).
        ENDIF.
        IF mo_sim->is_sticky( ) = abap_true.
          app_rollback( ).
          fail( |the app { lv_app } runs in a stateful session (set_session_stateful) - it cannot be continued| ).
        ENDIF.

        ms_row = VALUE #( id         = mo_sim->get_id( )
                          uname      = sy-uname
                          app        = lv_app
                          app_start  = lv_app
                          mcp_client = mv_client
                          max_rows   = mv_max_rows
                          created_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ) ).
        mt_custom = custom_of_sim( ).
        analyze( ).
        save( ).
        result = VALUE #( text    = ms_row-snapshot
                          session = ms_row-id ).

      CATCH cx_root INTO DATA(lx).
        result = VALUE #( is_error = abap_true
                          text     = lx->get_text( )
                          session  = ms_row-id ).
    ENDTRY.
    audit( operation = `app_attach`
           args      = |\{"draft":{ z2ui5_cl_agent_viewxml=>json_string( draft ) }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD app_check.

    mv_dry_run = abap_true.
    TRY.
        result = app_act( session = session
                          values  = values
                          event   = event
                          args    = args
                          row     = row ).
      CLEANUP.
        mv_dry_run = abap_false.
    ENDTRY.
    mv_dry_run = abap_false.

  ENDMETHOD.

  METHOD get_snapshot.

    check_enabled( ).
    load( session ).
    mv_max_rows = ms_row-max_rows.
    TRY.
        mo_sim = z2ui5_cl_frontend_simulator=>resume( id    = ms_row-id
                                                      state = ms_row-state ).
      CATCH cx_root INTO DATA(lx).
        fail( |session '{ ms_row-id }' cannot be continued - { lx->get_text( ) }| ).
    ENDTRY.
    analyze( ).
    result = mo_snap.

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
    " at most 9 digits - a longer row does not fit the integer it becomes
    IF lv_row IS INITIAL OR lv_row CN `0123456789` OR strlen( lv_row ) > 9 OR lv_column IS INITIAL
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
      pending_set( ls_plan ).
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

  METHOD action_again.

    " ids follow the document order: a value that shows or hides a control
    " renumbers them - the id must still name the event whose policy was
    " checked, and an action the values hid is no longer there to fire
    READ TABLE mo_snap->mt_action INTO result WITH KEY id = id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR result-event <> event
        OR result-policy = z2ui5_if_agent_app=>cs_policy-forbidden
        OR result-policy = z2ui5_if_agent_app=>cs_policy-confirm.
      fail( refusal ).
    ENDIF.
    " a value that disables it (enabled="{/OPEN}") leaves a control the
    " browser cannot press any more
    IF result-enabled = abap_false.
      fail( |action { id } ({ result-label }) is disabled once the values are filled - { action_help( ) }| ).
    ENDIF.

  ENDMETHOD.

  METHOD event_args.

    DATA lv_row TYPE i VALUE -1.
    DATA ls_explicit TYPE ty_s_val.
    DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA ls_params TYPE ty_s_params.
    DATA lt_probe TYPE ty_t_int.

    DATA(lt_desc) = is_action-t_wire_arg.
    IF lines( t_given ) > lines( lt_desc ).
      fail( |action { is_action-id } ({ is_action-event }) takes { lines( lt_desc ) } argument(s) - | &&
            |[{ concat_lines_of( table = is_action-t_arg_json
                                 sep   = `,` ) }]; { lines( t_given ) } given| ).
    ENDIF.
    IF is_action-scope <> `row` AND row_raw IS NOT INITIAL.
      fail( |row is for row actions - { is_action-id } ({ is_action-event }) is a screen action; leave row out| ).
    ENDIF.

    DATA(lv_count) = 0.
    IF is_action-scope = `row`.
      READ TABLE mo_snap->mt_table INTO ls_table WITH KEY id = is_action-table. "#EC CI_SORTSEQ
      lv_count = mo_snap->table_rows( is_action-table ).
      " an argument the row would fill: a row property, the source control's
      " property in the row, or an event parameter that is the row
      IF is_action-pick = abap_true.
        lt_probe = t_picked.
      ELSEIF lv_count > 0.
        lt_probe = VALUE #( ( 0 ) ).
      ENDIF.
      DATA(ls_probe) = row_event_params( is_action = is_action
                                         is_table  = ls_table
                                         has_rows  = xsdbool( is_action-pick = abap_true OR lv_count > 0 )
                                         t_row     = lt_probe ).
      IF row_raw IS INITIAL.
        LOOP AT lt_desc INTO DATA(ls_desc).
          ls_explicit = VALUE #( t_given[ sy-tabix ]-val OPTIONAL ).
          IF ls_desc-static = abap_true OR is_action-pick = abap_true
              OR ( ls_explicit-kind IS NOT INITIAL AND ls_explicit-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null ).
            CONTINUE.
          ENDIF.
          IF ls_desc-kind = `row` OR ls_desc-kind = `source`
              OR ( ( ls_desc-kind = `parameters` OR ls_desc-kind = `expr` )
                   AND row_param_arg( is_desc   = ls_desc
                                      is_params = ls_probe
                                      is_table  = ls_table )-kind <> '?' ).
            fail( |action { is_action-id } ({ is_action-event }) is a row action of table { is_action-table } ({ lv_count } rows) - | &&
                  |pass row (0-{ nmax( val1 = 0
                                       val2 = lv_count - 1 ) })| ).
          ENDIF.
        ENDLOOP.
      ELSE.
        lv_row = row_index( table_id = is_action-table
                            count    = lv_count
                            row_raw  = row_raw ).
      ENDIF.
      IF is_action-pick = abap_true.
        ls_params = row_event_params( is_action = is_action
                                      is_table  = ls_table
                                      has_rows  = abap_true
                                      t_row     = t_picked ).
      ELSEIF lv_row >= 0.
        ls_params = row_event_params( is_action = is_action
                                      is_table  = ls_table
                                      has_rows  = abap_true
                                      t_row     = VALUE #( ( lv_row ) ) ).
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
          " a $parameters / $expr argument of a row event, from its row(s)
          IF ls_params-active = abap_true.
            DATA(ls_param) = row_param_arg( is_desc   = ls_desc
                                            is_params = ls_params
                                            is_table  = ls_table ).
            IF ls_param-kind = 'v'.
              INSERT COND #( WHEN ls_param-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_param-val-kind IS INITIAL
                             THEN VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-null )
                             ELSE ls_param-val ) INTO TABLE result.
              CONTINUE.
            ENDIF.
          ENDIF.
          IF is_action-pick = abap_true AND t_picked IS INITIAL AND lv_count > 0.
            DATA(ls_first) = row_event_params( is_action = is_action
                                               is_table  = ls_table
                                               has_rows  = abap_true
                                               t_row     = VALUE #( ( 0 ) ) ).
            IF ls_first-active = abap_true AND row_param_arg( is_desc   = ls_desc
                                                              is_params = ls_first
                                                              is_table  = ls_table )-kind <> '?'.
              fail( |argument { lv_index } of { is_action-event } ({ ls_desc-describe }) reads the picked row and none is selected - | &&
                    |pass row, or the value in args[{ lv_index }]| ).
            ENDIF.
          ENDIF.
          fail( |argument { lv_index } of { is_action-event } ({ ls_desc-describe }) is computed in the browser - pass its value in args[{ lv_index }]| ).
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.

  METHOD row_index.

    result = -1.
    IF row_raw IS INITIAL.
      RETURN.
    ENDIF.
    DATA(ls_row) = z2ui5_cl_agent_viewxml=>describe_arg( row_raw ).
    IF ls_row-static = abap_false OR ls_row-val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-number
        OR ls_row-val-num <> trunc( ls_row-val-num ) OR ls_row-val-num < 0 OR ls_row-val-num >= count.
      fail( |table { table_id } has { count } row(s) - row { row_raw } does not exist (rows are 0-based)| ).
    ENDIF.
    result = ls_row-val-num.

  ENDMETHOD.

  METHOD pending_set.

    READ TABLE mt_pending TRANSPORTING NO FIELDS
         WITH KEY model_key = is_pending-model_key path = is_pending-path. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      MODIFY mt_pending FROM is_pending INDEX sy-tabix.
    ELSE.
      INSERT is_pending INTO TABLE mt_pending.
    ENDIF.

  ENDMETHOD.

  METHOD apply_pick.

    DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA lt_truthy TYPE STANDARD TABLE OF abap_bool WITH EMPTY KEY.

    " a selection dialog's confirm picks a row, as a click on it does in the
    " browser: the row's selectionField becomes true (and, selecting one row,
    " every other selected row's false) - two-way bound, so the edits travel
    " with the confirm as the model delta. The selected rows, in model order,
    " are what the event's selectedItem / selectedItems / selectedContexts
    " are made of. Without row the selection stays as the model holds it (a
    " multi-select dialog's OK after the rows were ticked through values);
    " picking one row needs one
    READ TABLE mo_snap->mt_table INTO ls_table WITH KEY id = is_action-table. "#EC CI_SORTSEQ
    DATA(lv_has_table) = xsdbool( sy-subrc = 0 ).
    DATA(lv_count) = ls_table-row_count.
    DATA(lv_single) = xsdbool( lv_has_table = abap_true AND ls_table-selection_mode = `Single` ).
    DATA(lv_row) = row_index( table_id = is_action-table
                              count    = lv_count
                              row_raw  = row_raw ).
    DATA(lv_field) = ls_table-selection_field.

    IF lv_field IS NOT INITIAL.
      DO lv_count TIMES.
        INSERT z2ui5_cl_agent_viewxml=>val_truthy( mo_snap->model_value( model_key = ls_table-model_key
                                                                         path      = lv_field
                                                                         table_id  = ls_table-id
                                                                         row       = sy-index - 1 ) ) INTO TABLE lt_truthy.
      ENDDO.
    ENDIF.
    IF lv_field IS NOT INITIAL AND lv_row >= 0.
      IF lv_single = abap_true.
        LOOP AT lt_truthy REFERENCE INTO DATA(lr_truthy).
          DATA(lv_other) = sy-tabix - 1.
          IF lv_other <> lv_row AND lr_truthy->* = abap_true.
            pending_set( VALUE #( model_key = ls_table-model_key
                                  path      = |{ ls_table-path }/{ lv_other }/{ lv_field }|
                                  val       = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ) ) ).
            lr_truthy->* = abap_false.
          ENDIF.
        ENDLOOP.
      ENDIF.
      DATA(ls_current) = mo_snap->model_value( model_key = ls_table-model_key
                                               path      = lv_field
                                               table_id  = ls_table-id
                                               row       = lv_row ).
      IF NOT ( ls_current-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean AND ls_current-str = `true` ).
        pending_set( VALUE #( model_key = ls_table-model_key
                              path      = |{ ls_table-path }/{ lv_row }/{ lv_field }|
                              val       = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ) ) ).
      ENDIF.
      DATA(lv_line) = lv_row + 1.
      MODIFY lt_truthy FROM abap_true INDEX lv_line.
    ENDIF.

    LOOP AT lt_truthy INTO DATA(lv_truthy).
      DATA(lv_selected) = sy-tabix - 1.
      IF lv_truthy = abap_true.
        INSERT lv_selected INTO TABLE result.
      ENDIF.
    ENDLOOP.
    IF lv_row >= 0 AND ( lv_single = abap_true OR lv_field IS INITIAL ).
      result = VALUE #( ( lv_row ) ).
    ENDIF.
    IF lv_row >= 0 AND lv_single = abap_false AND lv_field IS NOT INITIAL AND NOT line_exists( result[ table_line = lv_row ] ).
      INSERT lv_row INTO TABLE result.
    ENDIF.
    IF lv_single = abap_true AND result IS INITIAL.
      fail( |action { is_action-id } ({ is_action-event }) picks a row of table { is_action-table } ({ lv_count } rows) - | &&
            |pass row (0-{ nmax( val1 = 0
                                 val2 = lv_count - 1 ) })| ).
    ENDIF.

  ENDMETHOD.

  METHOD row_event_params.

    " the event parameters a row event hands its ${$parameters>/...}
    " arguments, for the events whose parameters ARE the row: a selection
    " dialog's confirm (selectedItem, selectedItems, selectedContexts), a
    " list table's itemPress / selectionChange / delete /
    " beforeOpenContextMenu (listItem), a grid table's rowSelectionChange
    " (rowIndex, rowContext), cellClick (rowIndex, rowBindingContext) and
    " beforeOpenContextMenu (rowIndex), and a row action item of a grid
    " table (row). Not active: the event's parameters are not the row
    IF is_table-id IS INITIAL OR has_rows = abap_false.
      RETURN.
    ENDIF.
    IF is_action-pick = abap_true.
      result-active = abap_true.
      DATA(ls_selected) = VALUE ty_s_pnode( kind = 'v'
                                            val  = VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-null ) ).
      READ TABLE t_row INTO DATA(lv_first) INDEX 1.
      IF sy-subrc = 0.
        ls_selected = VALUE #( kind = 'i'
                               row  = lv_first ).
      ENDIF.
      INSERT VALUE #( name = `selectedItem`
                      node = ls_selected ) INTO TABLE result-t_param.
      INSERT VALUE #( name = `selectedItems`
                      node = VALUE #( kind  = 'a'
                                      elem  = 'i'
                                      t_row = t_row ) ) INTO TABLE result-t_param.
      INSERT VALUE #( name = `selectedContexts`
                      node = VALUE #( kind  = 'a'
                                      elem  = 'c'
                                      t_row = t_row ) ) INTO TABLE result-t_param.
      RETURN.
    ENDIF.
    READ TABLE t_row INTO DATA(lv_row) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(lv_trigger) = is_action-trigger.
    IF is_action-doc = is_table-doc AND is_action-node = is_table-node.
      IF is_table-kind = `m` AND ( lv_trigger = `itemPress` OR lv_trigger = `selectionChange`
                                   OR lv_trigger = `delete` OR lv_trigger = `beforeOpenContextMenu` ).
        result-t_param = VALUE #( ( name = `listItem`
                                    node = VALUE #( kind = 'i'
                                                    row  = lv_row ) ) ).
      ELSEIF is_table-kind = `ui` AND lv_trigger = `rowSelectionChange`.
        result-t_param = VALUE #( ( name = `rowIndex`
                                    node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ) )
                                  ( name = `rowContext`
                                    node = VALUE #( kind = 'c'
                                                    row  = lv_row ) ) ).
      ELSEIF is_table-kind = `ui` AND lv_trigger = `cellClick`.
        result-t_param = VALUE #( ( name = `rowIndex`
                                    node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ) )
                                  ( name = `rowBindingContext`
                                    node = VALUE #( kind = 'c'
                                                    row  = lv_row ) ) ).
      ELSEIF is_table-kind = `ui` AND lv_trigger = `beforeOpenContextMenu`.
        result-t_param = VALUE #( ( name = `rowIndex`
                                    node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ) ) ).
      ENDIF.
    ELSEIF is_table-kind = `ui` AND is_action-row_template = `rowActionTemplate`.
      result-t_param = VALUE #( ( name = `row`
                                  node = VALUE #( kind = 'i'
                                                  row  = lv_row ) ) ).
    ENDIF.
    result-active = xsdbool( result-t_param IS NOT INITIAL ).

  ENDMETHOD.

  METHOD row_param_arg.

    " a $parameters / $expr argument of a row event, from its row(s); ? when
    " this client cannot
    result-kind = '?'.
    IF is_params-active = abap_false.
      RETURN.
    ENDIF.
    CASE is_desc-kind.
      WHEN `parameters`.
        result = walk_params( is_params = is_params
                              path      = is_desc-path
                              is_table  = is_table ).
      WHEN `expr`.
        result = param_expr( raw       = is_desc-raw
                             is_params = is_params
                             is_table  = is_table ).
    ENDCASE.

  ENDMETHOD.

  METHOD walk_params.

    " ${$parameters>/<path>} with the semantics of the JSONModel UI5 puts
    " the parameters in (EventHandlerResolver): the path is split at / and
    " walked key by key - there is no [n] index syntax, so
    " selectedContexts[0]/sPath is undefined in the browser and goes out as
    " null here too. A context answers its sPath; anything else of an item
    " or a context (the control marshalled with all its properties) is
    " unknown, as is a parameter this client does not model
    SPLIT path AT `/` INTO TABLE DATA(lt_seg).
    DELETE lt_seg WHERE table_line IS INITIAL.
    DATA(ls_node) = VALUE ty_s_pnode( kind = 'o' ).
    LOOP AT lt_seg INTO DATA(lv_seg).
      IF ls_node-kind = 'v' AND ( ls_node-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null
                                  OR ls_node-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ).
        result = ls_node.
        RETURN.
      ENDIF.
      IF ls_node-kind = 'i' OR ls_node-kind = 'c' OR ls_node-kind = 'l'.
        IF ls_node-kind = 'c' AND lv_seg = `sPath`.
          ls_node = pnode_value( z2ui5_cl_agent_viewxml=>val_string( |{ is_table-path }/{ ls_node-row }| ) ).
          CONTINUE.
        ENDIF.
        result-kind = '?'.
        RETURN.
      ENDIF.
      IF lv_seg CA `[]`.
        result = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) ).
        RETURN.
      ENDIF.
      CASE ls_node-kind.
        WHEN 'a'.
          IF lv_seg = `length`.
            ls_node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lines( ls_node-t_row ) }| ) ).
          ELSE.
            DATA(lv_line) = 0.
            IF lv_seg CO `0123456789` AND strlen( lv_seg ) <= 9.
              lv_line = lv_seg.
              lv_line = lv_line + 1.
            ENDIF.
            DATA(lv_elem_row) = 0.
            IF lv_line > 0.
              READ TABLE ls_node-t_row INTO lv_elem_row INDEX lv_line.
            ENDIF.
            IF lv_line > 0 AND sy-subrc = 0.
              " not VALUE #( kind = ls_node-elem ) - the target is cleared first
              DATA(lv_elem) = ls_node-elem.
              ls_node = VALUE #( kind = lv_elem
                                 row  = lv_elem_row ).
            ELSE.
              ls_node = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) ).
            ENDIF.
          ENDIF.
        WHEN 'o'.
          READ TABLE is_params-t_param INTO DATA(ls_param) WITH KEY name = lv_seg. "#EC CI_SORTSEQ
          IF sy-subrc <> 0.
            result-kind = '?'.
            RETURN.
          ENDIF.
          ls_node = ls_param-node.
        WHEN OTHERS.
          " a number or a string has no key
          result = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) ).
          RETURN.
      ENDCASE.
    ENDLOOP.
    CASE ls_node-kind.
      WHEN 'i' OR 'c' OR 'l' OR 'o'.
        result-kind = '?'.
      WHEN 'a'.
        IF ls_node-t_row IS NOT INITIAL.
          result-kind = '?'.
        ELSE.
          result = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-array
                                         json = `[]` ) ).
        ENDIF.
      WHEN OTHERS.
        result = ls_node.
    ENDCASE.

  ENDMETHOD.

  METHOD head_of.

    " the parameter a call chain starts from, as a value: an item or a
    " context is not walked into; a parameter this client does not model is
    " unknown
    SPLIT path AT `/` INTO TABLE DATA(lt_seg).
    DELETE lt_seg WHERE table_line IS INITIAL.
    result = VALUE #( kind = 'o' ).
    LOOP AT lt_seg INTO DATA(lv_seg).
      IF ( result-kind = 'v' AND ( result-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null
                                   OR result-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) )
          OR result-kind = 'i' OR result-kind = 'c' OR result-kind = 'l' OR lv_seg CA `[]`.
        result = VALUE #( kind = '?' ).
        RETURN.
      ENDIF.
      CASE result-kind.
        WHEN 'o'.
          READ TABLE is_params-t_param INTO DATA(ls_param) WITH KEY name = lv_seg. "#EC CI_SORTSEQ
          IF sy-subrc <> 0.
            result = VALUE #( kind = '?' ).
            RETURN.
          ENDIF.
          result = ls_param-node.
        WHEN 'a'.
          DATA(lv_line) = 0.
          IF lv_seg CO `0123456789` AND strlen( lv_seg ) <= 9.
            lv_line = lv_seg.
            lv_line = lv_line + 1.
          ENDIF.
          DATA(lv_elem_row) = 0.
          IF lv_line > 0.
            READ TABLE result-t_row INTO lv_elem_row INDEX lv_line.
          ENDIF.
          IF lv_line > 0 AND sy-subrc = 0.
            " not VALUE #( kind = result-elem ) - the target is cleared first
            DATA(lv_elem) = result-elem.
            result = VALUE #( kind = lv_elem
                              row  = lv_elem_row ).
          ELSE.
            result = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) ).
          ENDIF.
        WHEN OTHERS.
          result = pnode_value( VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) ).
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.

  METHOD param_expr.

    " the browser-computed argument shapes of a row event, the ones views
    " actually write:
    "   ${$parameters>/P}                                (walk_params)
    "   ${$parameters>/P}.getBindingContext().getPath()
    "   ${$parameters>/P}.getBindingContext().getProperty('X')
    "   ${$parameters>/P}.getPath() / .getProperty('X')  (P a context)
    "   ${$parameters>/P}.get<Prop>()                    (the item template's <prop>)
    "   ${$parameters>/P}.getCells()[n].get<Prop>()
    "   ${$parameters>/P} ? <one of the above> : <literal>
    " anything else is unknown - the caller asks for it in args
    CONSTANTS lc_head TYPE string VALUE `${$parameters>`.
    CONSTANTS lc_alpha TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`.
    CONSTANTS lc_word TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_`.
    DATA lv_found TYPE abap_bool.

    result-kind = '?'.
    DATA(lv_src) = str_trim( raw ).
    DATA(lv_len) = strlen( lv_src ).
    IF lv_len < 15 OR substring( val = lv_src
                                 len = 14 ) <> lc_head.
      RETURN.
    ENDIF.
    " the reference: ${$parameters>/?<path>} - no braces inside
    DATA(lv_close) = find( val = lv_src
                           sub = `}`
                           off = 14 ).
    IF lv_close < 0.
      RETURN.
    ENDIF.
    DATA(lv_path) = substring( val = lv_src
                               off = 14
                               len = lv_close - 14 ).
    IF lv_path CA `{`.
      RETURN.
    ENDIF.
    IF strlen( lv_path ) > 0 AND lv_path(1) = `/`.
      lv_path = substring( val = lv_path
                           off = 1 ).
    ENDIF.
    DATA(lv_pos) = lv_close + 1.

    " the ternary: <reference> ? <shape> : <literal>
    DATA(lv_q) = skip_ws( val = lv_src
                          pos = lv_pos ).
    IF lv_q < lv_len AND lv_src+lv_q(1) = `?`.
      DATA(lv_after) = lv_q + 1.
      DATA(lv_max) = skip_ws( val = lv_src
                              pos = lv_after ).
      DATA(lv_start) = lv_max.
      DATA(lv_tern) = abap_false.
      DATA(ls_lit) = VALUE ty_s_val( ).
      DATA(lv_end) = 0.
      WHILE lv_start >= lv_after AND lv_tern = abap_false.
        lv_end = lv_start + 1.
        WHILE lv_end <= lv_len AND lv_tern = abap_false.
          ls_lit = tail_literal( EXPORTING val   = lv_src
                                           off   = lv_end
                                 IMPORTING found = lv_found ).
          IF lv_found = abap_true.
            lv_tern = abap_true.
          ELSE.
            lv_end = lv_end + 1.
          ENDIF.
        ENDWHILE.
        IF lv_tern = abap_false.
          lv_start = lv_start - 1.
        ENDIF.
      ENDWHILE.
      IF lv_tern = abap_true.
        " the condition is the parameter itself - an item is truthy
        DATA(ls_cond) = head_of( is_params = is_params
                                 path      = lv_path ).
        IF ls_cond-kind = '?'.
          RETURN.
        ENDIF.
        IF pnode_truthy( ls_cond ) = abap_true.
          result = param_expr( raw       = substring( val = lv_src
                                                      off = lv_start
                                                      len = lv_end - lv_start )
                               is_params = is_params
                               is_table  = is_table ).
        ELSE.
          result = pnode_value( ls_lit ).
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.

    DATA(lv_rest) = substring( val = lv_src
                               off = lv_pos ).
    IF str_trim( lv_rest ) IS INITIAL.
      result = walk_params( is_params = is_params
                            path      = lv_path
                            is_table  = is_table ).
      RETURN.
    ENDIF.
    DATA(ls_cur) = head_of( is_params = is_params
                            path      = lv_path ).
    IF ls_cur-kind = '?'.
      RETURN.
    ENDIF.
    WHILE str_trim( lv_rest ) IS NOT INITIAL.
      IF ls_cur-kind <> 'i' AND ls_cur-kind <> 'c' AND ls_cur-kind <> 'l'.
        RETURN.
      ENDIF.
      " .<name>( ) or .<name>('<arg>')
      DATA(lv_rlen) = strlen( lv_rest ).
      lv_pos = skip_ws( val = lv_rest
                        pos = 0 ).
      IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `.`.
        RETURN.
      ENDIF.
      lv_pos = skip_ws( val = lv_rest
                        pos = lv_pos + 1 ).
      IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) NA lc_alpha.
        RETURN.
      ENDIF.
      DATA(lv_name_from) = lv_pos.
      WHILE lv_pos < lv_rlen AND lv_rest+lv_pos(1) CA lc_word.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      DATA(lv_fn) = substring( val = lv_rest
                               off = lv_name_from
                               len = lv_pos - lv_name_from ).
      lv_pos = skip_ws( val = lv_rest
                        pos = lv_pos ).
      IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `(`.
        RETURN.
      ENDIF.
      lv_pos = skip_ws( val = lv_rest
                        pos = lv_pos + 1 ).
      DATA(lv_has_arg) = abap_false.
      DATA(lv_arg) = ``.
      IF lv_pos < lv_rlen AND ( lv_rest+lv_pos(1) = `'` OR lv_rest+lv_pos(1) = `"` ).
        DATA(lv_quote) = lv_rest+lv_pos(1).
        DATA(lv_arg_end) = find( val = lv_rest
                                 sub = lv_quote
                                 off = lv_pos + 1 ).
        IF lv_arg_end < 0.
          RETURN.
        ENDIF.
        lv_has_arg = abap_true.
        lv_arg = substring( val = lv_rest
                            off = lv_pos + 1
                            len = lv_arg_end - lv_pos - 1 ).
        lv_pos = skip_ws( val = lv_rest
                          pos = lv_arg_end + 1 ).
      ENDIF.
      IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `)`.
        RETURN.
      ENDIF.
      lv_rest = substring( val = lv_rest
                           off = lv_pos + 1 ).

      DATA(lv_row) = ls_cur-row.
      IF ls_cur-kind = 'c'.
        IF lv_fn = `getPath` AND lv_has_arg = abap_false.
          ls_cur = pnode_value( z2ui5_cl_agent_viewxml=>val_string( |{ is_table-path }/{ lv_row }| ) ).
        ELSEIF lv_fn = `getProperty` AND lv_has_arg = abap_true.
          DATA(ls_prop) = mo_snap->model_value( model_key = is_table-model_key
                                                path      = lv_arg
                                                table_id  = is_table-id
                                                row       = lv_row ).
          IF ls_prop-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_prop-kind IS INITIAL.
            ls_prop = VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-null ).
          ENDIF.
          ls_cur = pnode_value( ls_prop ).
        ELSE.
          RETURN.
        ENDIF.
      ELSEIF lv_fn = `getBindingContext` AND lv_has_arg = abap_false.
        ls_cur = VALUE #( kind = 'c'
                          row  = lv_row ).
      ELSEIF lv_fn = `getCells` AND lv_has_arg = abap_false AND ls_cur-kind = 'i'.
        " [n]
        lv_rlen = strlen( lv_rest ).
        lv_pos = skip_ws( val = lv_rest
                          pos = 0 ).
        IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `[`.
          RETURN.
        ENDIF.
        lv_pos = skip_ws( val = lv_rest
                          pos = lv_pos + 1 ).
        DATA(lv_digit_from) = lv_pos.
        WHILE lv_pos < lv_rlen AND lv_rest+lv_pos(1) CA `0123456789`.
          lv_pos = lv_pos + 1.
        ENDWHILE.
        IF lv_pos = lv_digit_from.
          RETURN.
        ENDIF.
        DATA(lv_digits) = substring( val = lv_rest
                                     off = lv_digit_from
                                     len = lv_pos - lv_digit_from ).
        lv_pos = skip_ws( val = lv_rest
                          pos = lv_pos ).
        IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `]`.
          RETURN.
        ENDIF.
        lv_rest = substring( val = lv_rest
                             off = lv_pos + 1 ).
        IF strlen( lv_digits ) > 9.
          RETURN.
        ENDIF.
        DATA(lv_cell) = CONV i( lv_digits ).
        IF lv_cell >= lines( is_table-t_cellnode ).
          RETURN.
        ENDIF.
        ls_cur = VALUE #( kind = 'l'
                          row  = lv_row
                          cell = lv_cell ).
      ELSEIF strlen( lv_fn ) > 3 AND lv_fn(3) = `get` AND lv_fn+3(1) CA `ABCDEFGHIJKLMNOPQRSTUVWXYZ`
          AND lv_has_arg = abap_false AND lv_fn <> `getId`.
        " a property getter: the template attribute resolved in the row - a
        " number as the string the UI5 property holds; an attribute the
        " template does not set (or one bound to nothing) is unknown
        DATA(lv_prop) = to_lower( lv_fn+3(1) ) && substring( val = lv_fn
                                                            off = 4 ).
        DATA(lv_node) = 0.
        IF ls_cur-kind = 'l'.
          DATA(lv_cell_line) = ls_cur-cell + 1.
          READ TABLE is_table-t_cellnode INTO lv_node INDEX lv_cell_line.
        ELSEIF is_table-kind = `m`.
          lv_node = is_table-template.
        ENDIF.
        IF lv_node = 0.
          RETURN.
        ENDIF.
        DATA(ls_value) = mo_snap->template_value( table_id = is_table-id
                                                  node     = lv_node
                                                  prop     = lv_prop
                                                  row      = lv_row ).
        CASE ls_value-kind.
          WHEN z2ui5_cl_agent_viewxml=>cs_kind-undefined OR z2ui5_cl_agent_viewxml=>cs_kind-null OR space.
            RETURN.
          WHEN z2ui5_cl_agent_viewxml=>cs_kind-number.
            ls_value = z2ui5_cl_agent_viewxml=>val_string( z2ui5_cl_agent_viewxml=>val_to_string( ls_value ) ).
        ENDCASE.
        ls_cur = pnode_value( ls_value ).
      ELSE.
        RETURN.
      ENDIF.
    ENDWHILE.
    IF ls_cur-kind = 'i' OR ls_cur-kind = 'c' OR ls_cur-kind = 'l'.
      RETURN.
    ENDIF.
    result = ls_cur.

  ENDMETHOD.

  METHOD tail_literal.

    " \s*:\s*('...'|"..."|null|-?\d+(\.\d+)?)\s*$ at off
    found = abap_false.
    DATA(lv_len) = strlen( val ).
    DATA(lv_pos) = skip_ws( val = val
                            pos = off ).
    IF lv_pos >= lv_len OR val+lv_pos(1) <> `:`.
      RETURN.
    ENDIF.
    lv_pos = skip_ws( val = val
                      pos = lv_pos + 1 ).
    IF lv_pos >= lv_len.
      RETURN.
    ENDIF.
    DATA(lv_char) = val+lv_pos(1).
    IF lv_char = `'` OR lv_char = `"`.
      DATA(lv_text) = ``.
      lv_pos = lv_pos + 1.
      DATA(lv_closed) = abap_false.
      WHILE lv_pos < lv_len AND lv_closed = abap_false.
        DATA(lv_c) = val+lv_pos(1).
        IF lv_c = `\`.
          IF lv_pos + 1 >= lv_len.
            RETURN.
          ENDIF.
          lv_text = lv_text && val+lv_pos(2).
          lv_pos = lv_pos + 2.
        ELSEIF lv_c = lv_char.
          lv_closed = abap_true.
          lv_pos = lv_pos + 1.
        ELSE.
          lv_text = lv_text && lv_c.
          lv_pos = lv_pos + 1.
        ENDIF.
      ENDWHILE.
      IF lv_closed = abap_false.
        RETURN.
      ENDIF.
      " the escapes: \x is x
      DATA(lv_value) = ``.
      DATA(lv_i) = 0.
      DATA(lv_text_len) = strlen( lv_text ).
      WHILE lv_i < lv_text_len.
        IF lv_text+lv_i(1) = `\` AND lv_i + 1 < lv_text_len.
          lv_i = lv_i + 1.
        ENDIF.
        lv_value = lv_value && lv_text+lv_i(1).
        lv_i = lv_i + 1.
      ENDWHILE.
      result = z2ui5_cl_agent_viewxml=>val_string( lv_value ).
    ELSEIF lv_pos + 4 <= lv_len AND val+lv_pos(4) = `null`.
      lv_pos = lv_pos + 4.
      result-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
    ELSE.
      DATA(lv_from) = lv_pos.
      IF lv_char = `-`.
        lv_pos = lv_pos + 1.
      ENDIF.
      DATA(lv_digits_from) = lv_pos.
      WHILE lv_pos < lv_len AND val+lv_pos(1) CA `0123456789`.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      IF lv_pos = lv_digits_from.
        RETURN.
      ENDIF.
      DATA(lv_next) = lv_pos + 1.
      IF lv_next < lv_len AND val+lv_pos(1) = `.` AND val+lv_next(1) CA `0123456789`.
        lv_pos = lv_next.
        WHILE lv_pos < lv_len AND val+lv_pos(1) CA `0123456789`.
          lv_pos = lv_pos + 1.
        ENDWHILE.
      ENDIF.
      result = z2ui5_cl_agent_viewxml=>val_number( z2ui5_cl_agent_viewxml=>number_normalize(
                                                       substring( val = val
                                                                  off = lv_from
                                                                  len = lv_pos - lv_from ) ) ).
    ENDIF.
    IF skip_ws( val = val
                pos = lv_pos ) = lv_len.
      found = abap_true.
    ENDIF.

  ENDMETHOD.

  METHOD pnode_value.

    result = VALUE #( kind = 'v'
                      val  = val ).

  ENDMETHOD.

  METHOD pnode_truthy.

    CASE is_node-kind.
      WHEN 'v'.
        result = z2ui5_cl_agent_viewxml=>val_truthy( is_node-val ).
      WHEN '?'.
        result = abap_false.
      WHEN OTHERS.
        result = abap_true.
    ENDCASE.

  ENDMETHOD.

  METHOD skip_ws.

    DATA(lv_ws) = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf
               && cl_abap_char_utilities=>form_feed && cl_abap_char_utilities=>vertical_tab.
    result = pos.
    DATA(lv_len) = strlen( val ).
    WHILE result < lv_len AND val+result(1) CA lv_ws.
      result = result + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD str_trim.

    DATA(lv_ws) = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf
               && cl_abap_char_utilities=>form_feed && cl_abap_char_utilities=>vertical_tab.
    DATA(lv_from) = skip_ws( val = val
                             pos = 0 ).
    DATA(lv_to) = strlen( val ).
    WHILE lv_to > lv_from.
      DATA(lv_last) = lv_to - 1.
      IF val+lv_last(1) NA lv_ws.
        EXIT.
      ENDIF.
      lv_to = lv_last.
    ENDWHILE.
    result = substring( val = val
                        off = lv_from
                        len = lv_to - lv_from ).

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
        app_rollback( ).
        fail( |the backend refused the roundtrip - { lx->get_text( ) }| ).
    ENDTRY.
    IF mo_sim->is_sticky( ) = abap_true.
      app_rollback( ).
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

  METHOD app_rollback.

    z2ui5_cl_ui5_util_context=>db_rollback( ).

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
