"! The four agent operations on abap2UI5 apps - app_list, app_start,
"! app_describe, app_act - with the semantics of docs/agent-snapshot.md
"! (abap2UI5/mcp-server), ported from its lib/appclient.mjs.
"!
"! The engine is the headless frontend simulator (abap2UI5/headless-
"! frontend, z2ui5_cl_frontend_sim): it plays the browser side of the
"! protocol inside ABAP, so every act runs the app's own main( ) as the
"! SAP user of the request, with the app's own validation and authority
"! checks. Every operation is one HTTP request; between requests a session
"! lives in Z2UI5_T_16: the simulator's get_state( ) (the view of
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
    TYPES ty_t_pending_db TYPE STANDARD TABLE OF ty_s_pending_db WITH DEFAULT KEY.

    TYPES:
      "! A value of the request (values / args), keyed.
      BEGIN OF ty_s_input,
        key TYPE string,
        val TYPE ty_s_val,
      END OF ty_s_input.
    TYPES ty_t_input TYPE STANDARD TABLE OF ty_s_input WITH DEFAULT KEY.

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
    TYPES ty_t_param TYPE STANDARD TABLE OF ty_s_param WITH DEFAULT KEY.

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
    DATA mo_sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA ms_row TYPE z2ui5_t_16.
    "! changed_at before and after claim( ), for release( ).
    DATA mv_claimed_from TYPE z2ui5_t_16-changed_at.
    DATA mv_claimed_until TYPE z2ui5_t_16-changed_at.
    "! How long a claim holds a session - longer than any request runs.
    CONSTANTS c_claim_seconds TYPE i VALUE 600.
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
        default_value TYPE i
      RETURNING
        VALUE(result) TYPE i
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS load
      IMPORTING
        session TYPE clike
      RAISING
        z2ui5_cx_ui5_util_error.

    "! Takes the session for this act: two calls on one session (an MCP
    "! client calls tools in parallel) both ran the app's main( ) and both
    "! fired the event - a document posted twice, two forks of the session.
    "! The second finds changed_at moved and is refused before anything
    "! runs. Committed at once: abap2UI5 rolls back around main( ), which
    "! would take the claim and its row lock with it.
    METHODS claim
      RAISING
        z2ui5_cx_ui5_util_error.

    "! Gives a claimed session back after a refused act - as it was.
    METHODS release.

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
    TYPES ty_t_member TYPE STANDARD TABLE OF ty_s_member WITH DEFAULT KEY.

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

    DATA lv_item LIKE LINE OF t_item.
    LOOP AT t_item INTO lv_item TO c_list_max.
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
            `Z2UI5_CL_AGENT_APP_ADMIN (README of abap2UI5-addons/abap-agent-runtime, "Installation")` ).
    ENDIF.

  ENDMETHOD.

  METHOD rows_of.
    DATA ls_arg TYPE z2ui5_cl_agent_viewxml=>ty_s_arg.

    IF val IS INITIAL.
      result = default_value.
      RETURN.
    ENDIF.

    ls_arg = z2ui5_cl_agent_viewxml=>describe_arg( val ).
    IF ls_arg-static = abap_false OR ls_arg-val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-number.
      fail( |max_rows must be a number, not '{ z2ui5_cl_agent_viewxml=>echo( val ) }' - leaving it out means { default_value }| ).
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

    DATA temp17 TYPE z2ui5_cl_agent_audit=>ty_s_entry.
    DATA temp14 TYPE z2ui5_cl_agent_audit=>ty_s_entry-session.
    DATA temp15 TYPE z2ui5_cl_agent_audit=>ty_s_entry-app.
    DATA temp16 TYPE z2ui5_cl_agent_audit=>ty_s_entry-outcome.
    DATA temp18 TYPE z2ui5_cl_agent_audit=>ty_s_entry-text.
    CLEAR temp17.

    IF is_result-session IS NOT INITIAL.
      temp14 = is_result-session.
    ELSE.
      temp14 = ms_row-id.
    ENDIF.
    temp17-session = temp14.

    IF mo_sim IS BOUND.
      temp15 = mo_sim->get_app( ).
    ELSE.
      temp15 = ms_row-app.
    ENDIF.
    temp17-app = temp15.
    temp17-operation = operation.
    temp17-event = event.
    temp17-args = args.

    IF is_result-is_error = abap_true.
      temp16 = z2ui5_cl_agent_audit=>cs_outcome-error.
    ELSE.
      temp16 = z2ui5_cl_agent_audit=>cs_outcome-ok.
    ENDIF.
    temp17-outcome = temp16.

    IF is_result-is_error = abap_true.
      temp18 = is_result-text.
    ELSE.
      CLEAR temp18.
    ENDIF.
    temp17-text = temp18.
    temp17-client = mv_client.
    z2ui5_cl_agent_audit=>log( temp17 ).

  ENDMETHOD.

  METHOD app_list.

    DATA lt_item TYPE string_table.
        DATA lt_app TYPE z2ui5_cl_agent_settings=>ty_t_app.
        DATA ls_app LIKE LINE OF lt_app.
          DATA temp18 LIKE LINE OF lt_item.
        DATA temp19 TYPE string.
        DATA lv_hint LIKE temp19.
        DATA lx TYPE REF TO cx_root.
    DATA temp20 TYPE string.

    TRY.
        check_enabled( ).

        lt_app = z2ui5_cl_agent_settings=>get_apps( filter ).

        LOOP AT lt_app INTO ls_app.

          temp18 = |\{"app":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-app ) }| && |,"description":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-description ) }| && |,"source":{ z2ui5_cl_agent_viewxml=>json_string( ls_app-source ) }\}|.
          INSERT temp18 INTO TABLE lt_item.
        ENDLOOP.

        IF lt_app IS NOT INITIAL.
          temp19 = `app_start { app } starts one and answers with its agent snapshot`.
        ELSEIF filter IS NOT INITIAL.
          temp19 = |no app enabled for agents contains '{ z2ui5_cl_agent_viewxml=>echo( filter ) }'|.
        ELSE.
          temp19 = `no app is enabled for agents on this system - an app opts in by implementing ` && `z2ui5_if_agent_app, or an administrator allows it in Z2UI5_CL_AGENT_APP_ADMIN`.
        ENDIF.

        lv_hint = temp19.
        result-text = |\{"count":{ lines( lt_app ) },"apps":[{ concat_lines_of( table = lt_item
                                                                              sep   = `,` ) }]| &&
                      |,"hint":{ z2ui5_cl_agent_viewxml=>json_string( lv_hint ) }\}|.

      CATCH cx_root INTO lx.
        CLEAR result.
        result-is_error = abap_true.
        result-text = lx->get_text( ).
    ENDTRY.

    IF filter IS NOT INITIAL.
      temp20 = |\{"filter":{ z2ui5_cl_agent_viewxml=>json_string( filter ) }\}|.
    ELSE.
      CLEAR temp20.
    ENDIF.
    audit( operation = `app_list`
           args      = temp20
           is_result = result ).

  ENDMETHOD.

  METHOD app_start.

    DATA lv_reason TYPE string.
    DATA lt_name TYPE string_table.

    DATA temp21 TYPE string.
    DATA lv_app TYPE string.
          DATA temp22 TYPE z2ui5_cl_agent_settings=>ty_t_app.
          DATA ls_app LIKE LINE OF temp22.
          DATA temp23 TYPE string.
        DATA lt_value TYPE z2ui5_cl_agent_session=>ty_t_input.
            DATA lx_start TYPE REF TO cx_root.
            DATA lx_values TYPE REF TO z2ui5_cx_ui5_util_error.
        DATA lx TYPE REF TO cx_root.
    DATA temp24 TYPE string.
    temp21 = app.

    lv_app = to_upper( condense( temp21 ) ).
    TRY.
        check_enabled( ).
        mv_max_rows = rows_of( val           = max_rows
                               default_value = z2ui5_cl_agent_snapshot=>c_max_rows_default ).
        IF lv_app IS INITIAL.
          fail( `pass app - the class to start (app_list names the apps enabled for agents)` ).
        ENDIF.
        IF z2ui5_cl_agent_settings=>check_app( EXPORTING app    = lv_app
                                               IMPORTING reason = lv_reason ) = abap_false.

          temp22 = z2ui5_cl_agent_settings=>get_apps( ).

          LOOP AT temp22 INTO ls_app.
            INSERT ls_app-app INTO TABLE lt_name.
          ENDLOOP.

          IF lt_name IS NOT INITIAL.
            temp23 = |; apps enabled for agents: { list_of( lt_name ) }|.
          ELSE.
            CLEAR temp23.
          ENDIF.
          fail( |{ lv_reason }{ temp23 }| ).
        ENDIF.

        lt_value = parse_input( values ).

        TRY.
            mo_sim = z2ui5_cl_frontend_sim=>start( lv_app ).

          CATCH cx_root INTO lx_start.
            app_rollback( ).
            fail( |the app { lv_app } failed to start - { lx_start->get_text( ) }| ).
        ENDTRY.
        IF mo_sim->is_sticky( ) = abap_true.
          app_rollback( ).
          fail( |the app { lv_app } runs in a stateful session (set_session_stateful), which lives in one request only - | &&
                |the agent endpoint operates draft-based apps, one request per call| ).
        ENDIF.

        CLEAR ms_row.
        ms_row-id = mo_sim->get_id( ).
        ms_row-uname = sy-uname.
        ms_row-app = mo_sim->get_app( ).
        ms_row-app_start = lv_app.
        ms_row-mcp_client = mv_client.
        ms_row-max_rows = mv_max_rows.
        ms_row-created_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
        mt_custom = custom_of_sim( ).
        analyze( ).

        " the values are applied as pending edits, validated against the
        " first snapshot - the session runs either way
        TRY.
            apply_values( lt_value ).

          CATCH z2ui5_cx_ui5_util_error INTO lx_values.
            save( ).
            fail( |{ lx_values->get_text( ) } (the app is running: session { ms_row-id } - app_describe shows it)| ).
        ENDTRY.
        IF lt_value IS NOT INITIAL.
          analyze( ).
        ENDIF.
        save( ).
        CLEAR result.
        result-text = ms_row-snapshot.
        result-session = ms_row-id.


      CATCH cx_root INTO lx.
        CLEAR result.
        result-is_error = abap_true.
        result-text = lx->get_text( ).
        result-session = ms_row-id.
    ENDTRY.

    IF values IS NOT INITIAL.
      temp24 = |,"values":{ mask_values( t_value = lt_value app = lv_app ) }|.
    ELSE.
      CLEAR temp24.
    ENDIF.
    audit( operation = `app_start`
           args      = |\{"app":{ z2ui5_cl_agent_viewxml=>json_string( lv_app ) }{ temp24 }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD app_describe.
        DATA lx TYPE REF TO cx_root.

    TRY.
        check_enabled( ).
        load( session ).
        mv_max_rows = rows_of( val           = max_rows
                               default_value = ms_row-max_rows ).
        IF mv_max_rows = ms_row-max_rows AND ms_row-snapshot IS NOT INITIAL.
          CLEAR result.
          result-text = ms_row-snapshot.
          result-session = ms_row-id.
        ELSE.
          mo_sim = z2ui5_cl_frontend_sim=>resume( id    = ms_row-id
                                                        state = ms_row-state ).
          analyze( ).
          CLEAR result.
          result-text = mo_snap->get_json( ).
          result-session = ms_row-id.
        ENDIF.

      CATCH cx_root INTO lx.
        CLEAR result.
        result-is_error = abap_true.
        result-text = lx->get_text( ).
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
    DATA lv_values_audit TYPE string.
            DATA lx_resume TYPE REF TO cx_root.
          DATA temp1 TYPE xsdboolean.
            DATA temp25 TYPE string_table.
            DATA lt_pending_paths LIKE temp25.
            DATA ls_pending LIKE LINE OF mt_pending.
            DATA temp26 TYPE string.
        DATA lt_pending_before LIKE mt_pending.
              DATA lv_action_id LIKE ls_action-id.
              DATA lv_action_event LIKE ls_action-event.
              DATA temp27 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
              DATA lt_picked LIKE temp27.
              DATA lt_tval TYPE z2ui5_cl_agent_viewxml=>ty_t_val.
              DATA lv_id_old LIKE ms_row-id.
            DATA lx_act TYPE REF TO z2ui5_cx_ui5_util_error.
        DATA lx TYPE REF TO cx_root.
    DATA lv_args TYPE string.
    DATA temp28 TYPE string.
    DATA temp19 TYPE string.

    lv_event = event.
    lv_row = row.
    CLEAR: mv_claimed_from, mv_claimed_until.
    TRY.
        check_enabled( ).
        load( session ).
        mv_max_rows = rows_of( val           = max_rows
                               default_value = ms_row-max_rows ).
        lt_value = parse_input( values ).
        lt_arg = parse_input( json  = args
                              array = abap_true ).

        TRY.
            mo_sim = z2ui5_cl_frontend_sim=>resume( id    = ms_row-id
                                                          state = ms_row-state ).

          CATCH cx_root INTO lx_resume.
            DELETE FROM z2ui5_t_16 WHERE id = ms_row-id.
            fail( |session '{ ms_row-id }' cannot be continued - { lx_resume->get_text( ) }; app_start { ms_row-app_start } again| ).
        ENDTRY.
        analyze( ).
        " masked for the audit against THIS screen - the one the values are
        " typed into. Masked after the act, they were judged against the next
        " screen: a popup or another app without the field, an id f3 naming
        " something else, and a sensitive value went into the log as it was.
        IF values IS NOT INITIAL.
          lv_values_audit = mask_values( t_value = lt_value
                                         app     = ms_row-app ).
        ENDIF.

        " validate everything before anything changes
        IF lv_event IS NOT INITIAL.

          temp1 = boolc( lv_row IS NOT INITIAL ).
          ls_action = find_action( event   = lv_event
                                   has_row = temp1 ).
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

            CLEAR temp25.

            lt_pending_paths = temp25.

            LOOP AT mt_pending INTO ls_pending.
              INSERT ls_pending-path INTO TABLE lt_pending_paths.
            ENDLOOP.

            IF lt_pending_paths IS NOT INITIAL.
              temp26 = |The pending values ({ list_of( lt_pending_paths ) }) are not part of the draft yet - | && |fire an allowed event first, or tell the user what to enter.|.
            ELSE.
              temp26 = `Everything the agent entered is part of the draft.`.
            ENDIF.
            fail( |event { ls_action-event } ({ ls_action-id } "{ ls_action-label }") needs a human - agents never fire it | &&
                  |({ z2ui5_cl_agent_settings=>get_policy( app_start = ms_row-app_start
                                                           app       = mo_sim->get_app( )
                                                           event     = ls_action-event )-source }). | &&
                  |Hand over to the user: open { z2ui5_cl_agent_settings=>get_handover_url( app   = mo_sim->get_app( )
                                                                                            draft = ms_row-id ) } | &&
                  |in the browser - it restores this session's screen - check it and press "{ ls_action-label }" there. | &&
                  |{ temp26 }| ).
          ENDIF.
        ELSEIF lv_row IS NOT INITIAL.
          fail( `row belongs to an event - pass event too` ).
        ENDIF.
        " a layer closed in the browser reads nothing: a row or args given to
        " it were taken without a word
        IF lv_event IS NOT INITIAL AND ls_action-frontend IS NOT INITIAL AND ( lv_row IS NOT INITIAL OR lt_arg IS NOT INITIAL ).
          fail( |{ ls_action-event } closes the { ls_action-frontend } in the browser - it takes no row and no args| ).
        ENDIF.


        lt_pending_before = mt_pending.
        TRY.
            apply_values( lt_value ).
            " the values may have changed what the args read: re-analyse first
            analyze( ).
            IF lv_event IS NOT INITIAL.

              lv_action_id = ls_action-id.

              lv_action_event = ls_action-event.
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
              CLEAR result.
              result-text = mo_snap->get_json( ).
              result-session = ms_row-id.
              mt_pending = lt_pending_before.
            ELSEIF lv_event IS INITIAL.
              " values only: claimed too - saved over a session another act
              " moved on from meanwhile, it brought the old one back
              IF mv_mode <> cs_mode-copilot.
                claim( ).
              ENDIF.
              save( ).
            ELSEIF ls_action-frontend IS NOT INITIAL.
              " performed here, as the browser performs it: the slot closes,
              " its unsent edits go with it, no roundtrip
              IF mv_mode <> cs_mode-copilot.
                claim( ).
              ENDIF.
              close_layer( ls_action-frontend ).
              save( ).
            ELSE.
              " a selection dialog's confirm picks the row first - its
              " edits are part of the model the arguments read

              CLEAR temp27.

              lt_picked = temp27.
              IF ls_action-pick = abap_true.
                lt_picked = apply_pick( is_action = ls_action
                                        row_raw   = lv_row ).
                analyze( ).
                ls_action = action_again( id      = lv_action_id
                                          event   = lv_action_event
                                          refusal = |the pick changes the screen - action { lv_action_id } is no longer { lv_action_event }| ).
              ENDIF.

              lt_tval = event_args( is_action = ls_action
                                          t_given   = lt_arg
                                          row_raw   = lv_row
                                          t_picked  = lt_picked ).

              lv_id_old = ms_row-id.
              IF mv_mode <> cs_mode-copilot.
                claim( ).
              ENDIF.
              send( is_action = ls_action
                    t_arg     = lt_tval ).
              save( lv_id_old ).
            ENDIF.
            IF mv_dry_run = abap_false.
              CLEAR result.
              result-text = ms_row-snapshot.
              result-session = ms_row-id.
            ENDIF.

          CATCH z2ui5_cx_ui5_util_error INTO lx_act.
            " a refused act changes nothing: neither the pending edits nor the session
            mt_pending = lt_pending_before.
            release( ).
            RAISE EXCEPTION lx_act.
        ENDTRY.


      CATCH cx_root INTO lx.
        " whatever failed after the claim - the session is free again
        release( ).
        CLEAR result.
        result-is_error = abap_true.
        result-text = lx->get_text( ).
        result-session = ms_row-id.
    ENDTRY.


    lv_args = |\{"session":{ z2ui5_cl_agent_viewxml=>json_string( session ) }|.
    IF values IS NOT INITIAL.
      IF lv_values_audit IS INITIAL.
        " the session was never loaded: judged by the keys alone
        lv_values_audit = mask_values( t_value = lt_value
                                       app     = ms_row-app ).
      ENDIF.
      lv_args = |{ lv_args },"values":{ lv_values_audit }|.
    ENDIF.
    IF args IS NOT INITIAL.
      lv_args = |{ lv_args },"args":{ args }|.
    ENDIF.
    IF lv_row IS NOT INITIAL.
      lv_args = |{ lv_args },"row":{ lv_row }|.
    ENDIF.

    IF mv_dry_run = abap_true.
      temp28 = `app_check`.
    ELSE.
      temp28 = `app_act`.
    ENDIF.

    IF ls_action-event IS NOT INITIAL.
      temp19 = ls_action-event.
    ELSE.
      temp19 = lv_event.
    ENDIF.
    audit( operation = temp28
           event     = temp19
           args      = |{ lv_args }\}|
           is_result = result ).

  ENDMETHOD.

  METHOD app_attach.

    DATA lv_reason TYPE string.
    DATA lv_copy TYPE string.
            DATA lo_store TYPE REF TO z2ui5_if_ui5_draft_store.
            DATA ls_db TYPE z2ui5_t_01.
            DATA temp29 TYPE z2ui5_if_ui5_draft_store=>ty_s_draft.
            DATA lx_copy TYPE REF TO cx_root.
            DATA lx_resume TYPE REF TO cx_root.
        DATA lv_app TYPE string.
        DATA lx TYPE REF TO cx_root.

    TRY.
        check_enabled( ).
        mv_max_rows = rows_of( val           = max_rows
                               default_value = z2ui5_cl_agent_snapshot=>c_max_rows_default ).
        IF draft IS INITIAL.
          fail( `pass draft - the draft id of the screen to continue` ).
        ENDIF.

        " a copy - the user's own draft stays as the browser left it
        TRY.

            lo_store = z2ui5_cl_ui5_srv_draft=>get_instance( ).

            ls_db = lo_store->read_draft( draft ).
            lv_copy = z2ui5_cl_ui5_util_context=>uuid_get_c32( ).

            CLEAR temp29.
            temp29-id = lv_copy.
            temp29-id_prev = ls_db-id_prev.
            temp29-id_prev_app = ls_db-id_prev_app.
            temp29-id_prev_app_stack = ls_db-id_prev_app_stack.
            lo_store->create( draft     = temp29
                              model_xml = ls_db-data ).

          CATCH cx_root INTO lx_copy.
            fail( |the draft { draft } cannot be read - { lx_copy->get_text( ) }| ).
        ENDTRY.
        TRY.
            mo_sim = z2ui5_cl_frontend_sim=>resume( id      = lv_copy
                                                          refresh = abap_true ).

          CATCH cx_root INTO lx_resume.
            app_rollback( ).
            fail( |the screen of draft { draft } cannot be restored - { lx_resume->get_text( ) }| ).
        ENDTRY.

        lv_app = mo_sim->get_app( ).
        IF z2ui5_cl_agent_settings=>check_app( EXPORTING app    = lv_app
                                               IMPORTING reason = lv_reason ) = abap_false.
          " the restore ran the app's main( ) - what it left open goes, as
          " for a screen that cannot be continued (a stateful app is not
          " rolled back by abap2UI5, and the caller's commit kept it)
          app_rollback( ).
          fail( lv_reason ).
        ENDIF.
        IF mo_sim->is_sticky( ) = abap_true.
          app_rollback( ).
          fail( |the app { lv_app } runs in a stateful session (set_session_stateful) - it cannot be continued| ).
        ENDIF.

        CLEAR ms_row.
        ms_row-id = mo_sim->get_id( ).
        ms_row-uname = sy-uname.
        ms_row-app = lv_app.
        ms_row-app_start = lv_app.
        ms_row-mcp_client = mv_client.
        ms_row-max_rows = mv_max_rows.
        ms_row-created_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
        mt_custom = custom_of_sim( ).
        analyze( ).
        save( ).
        CLEAR result.
        result-text = ms_row-snapshot.
        result-session = ms_row-id.


      CATCH cx_root INTO lx.
        CLEAR result.
        result-is_error = abap_true.
        result-text = lx->get_text( ).
        result-session = ms_row-id.
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
        DATA lx TYPE REF TO cx_root.

    check_enabled( ).
    load( session ).
    mv_max_rows = ms_row-max_rows.
    TRY.
        mo_sim = z2ui5_cl_frontend_sim=>resume( id    = ms_row-id
                                                      state = ms_row-state ).

      CATCH cx_root INTO lx.
        fail( |session '{ ms_row-id }' cannot be continued - { lx->get_text( ) }| ).
    ENDTRY.
    analyze( ).
    result = mo_snap.

  ENDMETHOD.

  METHOD load.

    DATA lv_id TYPE z2ui5_t_16-id.
    DATA lt_open TYPE string_table.
    DATA lt_pending_db TYPE ty_t_pending_db.
    DATA lv_fits TYPE abap_bool.
    DATA temp2 TYPE xsdboolean.
    DATA lv_found LIKE abap_false.
      DATA temp3 TYPE xsdboolean.
        DATA lv_current TYPE z2ui5_t_16-id.
TYPES BEGIN OF temp30.
TYPES id TYPE z2ui5_t_16-id.
TYPES app TYPE z2ui5_t_16-app.
TYPES END OF temp30.
      TYPES temp1 TYPE STANDARD TABLE OF temp30 WITH DEFAULT KEY.
DATA lt_session TYPE temp1.
      DATA ls_session LIKE LINE OF lt_session.
        DATA temp31 LIKE LINE OF lt_open.
      DATA temp32 TYPE string.
    DATA lv_limit TYPE timestampl.
          DATA temp4 TYPE REF TO z2ui5_cl_ajson.
          DATA temp5 TYPE REF TO z2ui5_cl_ajson.
        DATA lx TYPE REF TO cx_root.
    DATA ls_db LIKE LINE OF lt_pending_db.
      DATA temp33 TYPE ty_s_val.
      DATA ls_val LIKE temp33.
      DATA temp34 TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.

    IF session IS INITIAL.
      fail( `pass session - the session the last snapshot carried (app_start returns the first)` ).
    ENDIF.
    lv_id = condense( session ).
    " an id longer than the column is unknown - cut to it, an id with
    " anything appended would continue the session of its prefix


    temp2 = boolc( lv_id = condense( session ) ).
    lv_fits = temp2.

    lv_found = abap_false.
    IF lv_fits = abap_true.
      SELECT SINGLE * FROM z2ui5_t_16 INTO ms_row WHERE id = lv_id AND uname = sy-uname .

      temp3 = boolc( sy-subrc = 0 ).
      lv_found = temp3.
    ENDIF.
    IF lv_found = abap_false.
      IF lv_fits = abap_true.

        SELECT SINGLE id FROM z2ui5_t_16 INTO lv_current WHERE id_prev = lv_id AND uname = sy-uname . "#EC CI_NOORDER
        IF sy-subrc = 0.
          fail( |session '{ lv_id }' is an earlier state of this app session - continue with the current one: | &&
                |'{ lv_current }' (app_describe shows it)| ).
        ENDIF.
      ENDIF.



      SELECT id app FROM z2ui5_t_16 INTO TABLE lt_session WHERE uname = sy-uname ORDER BY changed_at DESCENDING .

      LOOP AT lt_session INTO ls_session.

        temp31 = |{ ls_session-id } ({ ls_session-app })|.
        INSERT temp31 INTO TABLE lt_open.
      ENDLOOP.

      IF lt_open IS NOT INITIAL.
        temp32 = |; open sessions: { list_of( lt_open ) }|.
      ELSE.
        CLEAR temp32.
      ENDIF.
      fail( |unknown session '{ z2ui5_cl_agent_viewxml=>echo( condense( session ) ) }' - start one with app_start{ temp32 }| ).
    ENDIF.


    lv_limit = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = z2ui5_cl_ui5_util_context=>time_get_timestampl( )
                         seconds = 3600 * z2ui5_cl_agent_settings=>get_expiry_hours( ) ).
    IF ms_row-changed_at < lv_limit.
      DELETE FROM z2ui5_t_16 WHERE id = lv_id.
      fail( |session '{ lv_id }' expired with its draft - app_start { ms_row-app_start } again| ).
    ENDIF.

    TRY.
        IF ms_row-custom IS NOT INITIAL.

          temp4 = z2ui5_cl_ajson=>parse( ms_row-custom ).
          temp4->to_abap( IMPORTING ev_container = mt_custom ).
        ENDIF.
        IF ms_row-pending IS NOT INITIAL.

          temp5 = z2ui5_cl_ajson=>parse( ms_row-pending ).
          temp5->to_abap( IMPORTING ev_container = lt_pending_db ).
        ENDIF.

      CATCH cx_root INTO lx.
        fail( |session '{ lv_id }' is damaged ({ lx->get_text( ) }) - app_start { ms_row-app_start } again| ).
    ENDTRY.
    CLEAR mt_pending.

    LOOP AT lt_pending_db INTO ls_db.

      CLEAR temp33.
      temp33-kind = ls_db-kind.
      temp33-str = ls_db-str.
      temp33-json = ls_db-json.

      ls_val = temp33.
      IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
        ls_val = z2ui5_cl_agent_viewxml=>val_number( ls_db-str ).
      ENDIF.

      CLEAR temp34.
      temp34-model_key = ls_db-model_key.
      temp34-path = ls_db-path.
      temp34-val = ls_val.
      INSERT temp34 INTO TABLE mt_pending.
    ENDLOOP.

  ENDMETHOD.

  METHOD claim.

    " changed_at in the future marks the session as taken - for as long as
    " a request may run; save( ) writes the present back and so releases
    " it, release( ) does on a refusal, and a request that dumps leaves it
    " blocked for that long at most. Taken by a call that loaded the row
    " before, or after the claim, the next is refused either way.
    DATA lv_now TYPE timestampl.
    DATA lv_until TYPE timestampl.
    lv_now = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    IF ms_row-changed_at > lv_now.
      fail( |session '{ ms_row-id }' is being continued by another call - wait for its answer and act on the session it returns| ).
    ENDIF.

    lv_until = z2ui5_cl_ui5_util_context=>time_subtract_seconds( time    = lv_now
                                                                       seconds = 0 - c_claim_seconds ).
    UPDATE z2ui5_t_16 SET changed_at = lv_until
      WHERE id = ms_row-id AND uname = sy-uname AND changed_at = ms_row-changed_at.
    IF sy-dbcnt = 0.
      fail( |session '{ ms_row-id }' is being continued by another call - wait for its answer and act on the session it returns| ).
    ENDIF.
    COMMIT WORK.
    mv_claimed_from = ms_row-changed_at.
    mv_claimed_until = lv_until.
    ms_row-changed_at = lv_until.

  ENDMETHOD.

  METHOD release.

    IF mv_claimed_until IS INITIAL.
      RETURN.
    ENDIF.
    UPDATE z2ui5_t_16 SET changed_at = mv_claimed_from
      WHERE id = ms_row-id AND uname = sy-uname AND changed_at = mv_claimed_until.
    COMMIT WORK.
    ms_row-changed_at = mv_claimed_from.
    CLEAR: mv_claimed_from, mv_claimed_until.

  ENDMETHOD.

  METHOD save.

    DATA lt_pending_db TYPE ty_t_pending_db.

    DATA ls_pending LIKE LINE OF mt_pending.
      DATA temp35 TYPE z2ui5_cl_agent_session=>ty_s_pending_db.
        DATA temp36 TYPE REF TO z2ui5_if_ajson.
        DATA lo_json LIKE temp36.
        DATA temp37 TYPE REF TO z2ui5_if_ajson.
    DATA lv_limit TYPE timestampl.
    LOOP AT mt_pending INTO ls_pending.

      CLEAR temp35.
      temp35-model_key = ls_pending-model_key.
      temp35-path = ls_pending-path.
      temp35-kind = ls_pending-val-kind.
      temp35-str = ls_pending-val-str.
      temp35-json = ls_pending-val-json.
      INSERT temp35 INTO TABLE lt_pending_db.
    ENDLOOP.
    TRY.

        temp36 ?= z2ui5_cl_ajson=>create_empty( ).

        lo_json = temp36.
        lo_json->set( iv_path = `/`
                      iv_val  = mt_custom ).
        ms_row-custom = lo_json->stringify( ).

        temp37 ?= z2ui5_cl_ajson=>create_empty( ).
        lo_json = temp37.
        lo_json->set( iv_path = `/`
                      iv_val  = lt_pending_db ).
        ms_row-pending = lo_json->stringify( ).
      CATCH cx_root ##NO_HANDLER.
        " both are built from typed tables - nothing to refuse
    ENDTRY.

    ms_row-state = mo_sim->get_state( ).
    ms_row-snapshot = mo_snap->get_json( ).
    " the rows the stored snapshot was built with: an act's max_rows was
    " not kept, and app_describe answered it for any max_rows asked
    ms_row-max_rows = mv_max_rows.
    ms_row-app = mo_sim->get_app( ).
    ms_row-uname = sy-uname.
    ms_row-changed_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    IF ms_row-created_at IS INITIAL.
      ms_row-created_at = ms_row-changed_at.
    ENDIF.

    IF id_old IS NOT INITIAL AND id_old <> mo_sim->get_id( ).
      DELETE FROM z2ui5_t_16 WHERE id = id_old.
      ms_row-id_prev = id_old.
    ENDIF.
    ms_row-id = mo_sim->get_id( ).
    MODIFY z2ui5_t_16 FROM ms_row.

    " sessions whose drafts are gone are gone as well

    lv_limit = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = ms_row-changed_at
                         seconds = 3600 * z2ui5_cl_agent_settings=>get_expiry_hours( ) ).
    DELETE FROM z2ui5_t_16 WHERE changed_at < lv_limit.

  ENDMETHOD.

  METHOD custom_of_sim.

    " the client work of the last response; the VIEW_SLOTS destroys in it
    " were applied to the layers already
    DATA temp38 TYPE z2ui5_cl_frontend_sim=>ty_t_action.
    DATA ls_action LIKE LINE OF temp38.
      DATA temp39 TYPE string.
      DATA temp40 TYPE string.
      DATA lv_arg1 LIKE temp39.
      DATA temp41 TYPE string.
      DATA temp42 TYPE string.
      DATA lv_arg2 LIKE temp41.
    temp38 = mo_sim->get_actions( ).

    LOOP AT temp38 INTO ls_action.

      CLEAR temp39.

      READ TABLE ls_action-t_arg INTO temp40 INDEX 1.
      IF sy-subrc = 0.
        temp39 = temp40.
      ENDIF.

      lv_arg1 = temp39.

      CLEAR temp41.

      READ TABLE ls_action-t_arg INTO temp42 INDEX 2.
      IF sy-subrc = 0.
        temp41 = temp42.
      ENDIF.

      lv_arg2 = temp41.
      IF ( ls_action-name = `VIEW_SLOTS` AND lv_arg1 = `destroy` )
          OR ( ls_action-name = z2ui5_if_client=>cs_event-control_global AND lv_arg1 = `VIEW_SLOTS` AND lv_arg2 = `destroy` ).
        CONTINUE.
      ENDIF.
      INSERT ls_action-json INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD analyze.

    DATA temp43 TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    DATA ls_input LIKE temp43.
    DATA ls_action LIKE LINE OF mo_snap->mt_action.
    CLEAR temp43.
    temp43-session = mo_sim->get_id( ).
    temp43-app = mo_sim->get_app( ).
    temp43-t_layer = mo_sim->get_layers( ).
    temp43-t_custom = mt_custom.
    temp43-t_pending = mt_pending.
    temp43-max_rows = mv_max_rows.

    ls_input = temp43.
    mo_snap = z2ui5_cl_agent_snapshot=>create( ls_input ).

    LOOP AT mo_snap->mt_action INTO ls_action WHERE frontend IS INITIAL. "#EC CI_SORTSEQ
      mo_snap->set_policy( id     = ls_action-id
                           policy = z2ui5_cl_agent_settings=>get_policy( app_start = ms_row-app_start
                                                                         app       = mo_sim->get_app( )
                                                                         event     = ls_action-event )-policy ).
    ENDLOOP.

  ENDMETHOD.

  METHOD parse_input.
        DATA temp44 TYPE REF TO z2ui5_if_ajson.
        DATA temp20 TYPE string.
        DATA lo_json LIKE temp44.
    DATA lv_type TYPE z2ui5_if_ajson_types=>ty_node_type.
      DATA lv_count TYPE i.
        DATA temp45 TYPE z2ui5_cl_agent_session=>ty_s_input.
    DATA temp21 TYPE string.
    DATA temp46 TYPE z2ui5_cl_agent_session=>ty_t_member.
    DATA ls_member LIKE LINE OF temp46.
          DATA temp47 TYPE REF TO z2ui5_if_ajson.
          DATA lo_value LIKE temp47.
      DATA temp48 TYPE z2ui5_cl_agent_session=>ty_s_input.

    IF json IS INITIAL.
      RETURN.
    ENDIF.
    TRY.


        temp20 = json.
        temp44 ?= z2ui5_cl_ajson=>parse( iv_json = temp20 iv_keep_item_order = abap_true ).

        lo_json = temp44.
      CATCH cx_root.
        IF array = abap_true.
          fail( `args is an array, positional to the action's args (null where the client should fill in the value)` ).
        ENDIF.
        fail( `values is an object: { "<field id, path or name>": value }` ).
    ENDTRY.

    lv_type = lo_json->get_node_type( `/` ).
    IF array = abap_true.
      IF lv_type <> z2ui5_if_ajson_types=>node_type-array.
        fail( `args is an array, positional to the action's args (null where the client should fill in the value)` ).
      ENDIF.

      lv_count = lines( lo_json->members( `/` ) ).
      DO lv_count TIMES.

        CLEAR temp45.
        temp45-key = |{ sy-index - 1 }|.
        temp45-val = val_of_node( io_json = lo_json path = |/{ sy-index }| ).
        INSERT temp45 INTO TABLE result.
      ENDDO.
      RETURN.
    ENDIF.
    IF lv_type <> z2ui5_if_ajson_types=>node_type-object.
      fail( `values is an object: { "<field id, path or name>": value }` ).
    ENDIF.

    " the keys are model paths ("/T_TAB/2/SELKZ") - a path of the JSON tree
    " cannot address them, so the object is split by hand, in its own order

    temp21 = json.

    temp46 = object_members( temp21 ).

    LOOP AT temp46 INTO ls_member.
      TRY.

          temp47 ?= z2ui5_cl_ajson=>parse( iv_json = |\{"v":{ ls_member-raw }\}| iv_keep_item_order = abap_true ).

          lo_value = temp47.
        CATCH cx_root.
          fail( `values is an object: { "<field id, path or name>": value }` ).
      ENDTRY.

      CLEAR temp48.
      temp48-key = ls_member-key.
      temp48-val = val_of_node( io_json = lo_value path = `/v` ).
      INSERT temp48 INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD object_members.

    DATA lv_depth TYPE i.
    DATA lv_in_string TYPE abap_bool.
    DATA lv_key TYPE string.

    " the top level of a JSON object: each key (unescaped) with the raw text
    " of its value
    DATA lv_len TYPE i.
    DATA lv_pos TYPE i.
      DATA lv_quote TYPE i.
      DATA lv_close TYPE i.
      DATA lv_i TYPE i.
        DATA lv_c TYPE string.
          DATA lv_i1 TYPE i.
          DATA temp49 TYPE string.
          DATA lv_e LIKE temp49.
          DATA temp50 TYPE string.
      DATA lv_colon TYPE i.
      DATA lv_start TYPE i.
      DATA temp51 TYPE z2ui5_cl_agent_session=>ty_s_member.
    lv_len = strlen( json ).

    lv_pos = find( val = json
                         sub = `{` ).
    IF lv_pos < 0.
      RETURN.
    ENDIF.
    lv_pos = lv_pos + 1.
    DO.
      " the key

      lv_quote = find( val = json
                             sub = `"`
                             off = lv_pos ).

      lv_close = find( val = json
                             sub = `}`
                             off = lv_pos ).
      IF lv_quote < 0 OR ( lv_close >= 0 AND lv_close < lv_quote ).
        RETURN.
      ENDIF.
      CLEAR lv_key.

      lv_i = lv_quote + 1.
      WHILE lv_i < lv_len.

        lv_c = json+lv_i(1).
        IF lv_c = `\`.

          lv_i1 = lv_i + 1.

          IF lv_i1 < lv_len.
            temp49 = json+lv_i1(1).
          ELSE.
            CLEAR temp49.
          ENDIF.

          lv_e = temp49.

          CASE lv_e.
            WHEN `n`.
              temp50 = cl_abap_char_utilities=>newline.
            WHEN `t`.
              temp50 = cl_abap_char_utilities=>horizontal_tab.
            WHEN OTHERS.
              temp50 = lv_e.
          ENDCASE.
          lv_key = lv_key && temp50.
          lv_i = lv_i + 2.
          CONTINUE.
        ENDIF.
        IF lv_c = `"`.
          EXIT.
        ENDIF.
        lv_key = lv_key && lv_c.
        lv_i = lv_i + 1.
      ENDWHILE.

      lv_colon = find( val = json
                             sub = `:`
                             off = lv_i + 1 ).
      IF lv_colon < 0.
        RETURN.
      ENDIF.

      " the value, up to the comma or brace that closes it on this level

      lv_start = lv_colon + 1.
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

      CLEAR temp51.
      temp51-key = lv_key.
      temp51-raw = condense( substring( val = json off = lv_start len = lv_i - lv_start ) ).
      INSERT temp51 INTO TABLE result.
      IF lv_i >= lv_len OR json+lv_i(1) = `}`.
        RETURN.
      ENDIF.
      lv_pos = lv_i + 1.
    ENDDO.

  ENDMETHOD.

  METHOD val_of_node.
        DATA temp52 TYPE z2ui5_cl_agent_viewxml=>ty_s_val-kind.

    CASE io_json->get_node_type( path ).
      WHEN z2ui5_if_ajson_types=>node_type-string.
        result = z2ui5_cl_agent_viewxml=>val_string( io_json->get( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-number.
        result = z2ui5_cl_agent_viewxml=>val_number( io_json->get( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-boolean.
        result = z2ui5_cl_agent_viewxml=>val_boolean( io_json->get_boolean( path ) ).
      WHEN z2ui5_if_ajson_types=>node_type-object OR z2ui5_if_ajson_types=>node_type-array.

        IF io_json->get_node_type( path ) = z2ui5_if_ajson_types=>node_type-array.
          temp52 = z2ui5_cl_agent_viewxml=>cs_kind-array.
        ELSE.
          temp52 = z2ui5_cl_agent_viewxml=>cs_kind-object.
        ENDIF.
        result-kind = temp52.
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

    DATA ls_field LIKE LINE OF mo_snap->mt_field.
      DATA temp53 LIKE LINE OF lt_editable.
    DATA ls_table LIKE LINE OF mo_snap->mt_table.
      DATA temp54 LIKE LINE OF lt_cells.
    DATA temp55 TYPE string.
    LOOP AT mo_snap->mt_field INTO ls_field WHERE editable = abap_true. "#EC CI_SORTSEQ

      temp53 = |{ ls_field-id } ({ ls_field-label }, { ls_field-path })|.
      INSERT temp53 INTO TABLE lt_editable.
    ENDLOOP.

    LOOP AT mo_snap->mt_table INTO ls_table.
      IF ls_table-t_editable IS INITIAL.
        CONTINUE.
      ENDIF.

      temp54 = |{ ls_table-path }/<row 0-{ nmax( val1 = 0 val2 = ls_table-row_count - 1 ) }>/\{{ concat_lines_of( table = ls_table-t_editable sep = `|` ) }\} (table { ls_table-id })|.
      INSERT temp54
             INTO TABLE lt_cells.
    ENDLOOP.

    IF lt_editable IS NOT INITIAL.
      temp55 = |fields you can fill: { list_of( lt_editable ) }|.
    ELSE.
      temp55 = `no editable field on this screen`.
    ENDIF.
    result = temp55.
    IF lt_cells IS NOT INITIAL.
      result = |{ result }; table cells: { list_of( lt_cells ) }|.
    ENDIF.
    result = result && layer_note( ).

  ENDMETHOD.

  METHOD action_help.

    DATA lt_item TYPE string_table.

    DATA ls_action LIKE LINE OF mo_snap->mt_action.
      DATA temp56 TYPE string.
      DATA temp22 TYPE string.
      DATA temp1 LIKE LINE OF lt_item.
    DATA temp57 TYPE string.
    LOOP AT mo_snap->mt_action INTO ls_action WHERE enabled = abap_true. "#EC CI_SORTSEQ

      IF ls_action-scope = `row`.
        temp56 = |, row action of { ls_action-table }|.
      ELSE.
        CLEAR temp56.
      ENDIF.

      IF ls_action-policy IS NOT INITIAL AND ls_action-policy <> z2ui5_if_agent_app=>cs_policy-allowed.
        temp22 = |, { ls_action-policy } - not for agents|.
      ELSE.
        CLEAR temp22.
      ENDIF.

      temp1 = |{ ls_action-event } ({ ls_action-id } "{ ls_action-label }"| && |{ temp56 }| && |{ temp22 })|.
      INSERT temp1 INTO TABLE lt_item.
    ENDLOOP.

    IF lt_item IS NOT INITIAL.
      temp57 = |allowed events: { list_of( lt_item ) }|.
    ELSE.
      temp57 = `this screen offers no action`.
    ENDIF.
    result = temp57.
    result = result && layer_note( ).

  ENDMETHOD.

  METHOD resolve_target.
    DATA ls_field LIKE LINE OF mo_snap->mt_field.
    DATA lv_upper TYPE string.
    TYPES temp2 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp2.
    DATA lv_count TYPE i.
    DATA lv_column LIKE LINE OF lt_seg.
    FIELD-SYMBOLS <temp23> LIKE LINE OF lt_seg.
    DATA temp24 LIKE sy-tabix.
    DATA lv_row LIKE LINE OF lt_seg.
    FIELD-SYMBOLS <temp25> LIKE LINE OF lt_seg.
    DATA temp26 LIKE sy-tabix.
    DATA lv_table TYPE string.
    DATA ls_table LIKE LINE OF mo_snap->mt_table.
        DATA temp27 TYPE i.

    found = abap_false.

    LOOP AT mo_snap->mt_field INTO ls_field WHERE id = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.
    LOOP AT mo_snap->mt_field INTO ls_field WHERE path = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.

    lv_upper = to_upper( key ).
    LOOP AT mo_snap->mt_field INTO ls_field.
      IF to_upper( ls_field-name ) = lv_upper.
        found = abap_true.
        result-field = sy-tabix.
        RETURN.
      ENDIF.
    ENDLOOP.

    " a table cell: /T_TAB/3/QTY or t1/3/QTY


    SPLIT key AT `/` INTO TABLE lt_seg.

    lv_count = lines( lt_seg ).
    IF lv_count < 3.
      RETURN.
    ENDIF.



    temp24 = sy-tabix.
    READ TABLE lt_seg INDEX lv_count ASSIGNING <temp23>.
    sy-tabix = temp24.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_column = <temp23>.



    temp26 = sy-tabix.
    READ TABLE lt_seg INDEX lv_count - 1 ASSIGNING <temp25>.
    sy-tabix = temp26.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_row = <temp25>.
    " at most 9 digits - a longer row does not fit the integer it becomes
    IF lv_row IS INITIAL OR lv_row CN `0123456789` OR strlen( lv_row ) > 9 OR lv_column IS INITIAL
        OR lv_column(1) CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`
        OR lv_column CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-`.
      RETURN.
    ENDIF.

    lv_table = substring( val = key
                                len = strlen( key ) - strlen( lv_row ) - strlen( lv_column ) - 2 ).

    LOOP AT mo_snap->mt_table INTO ls_table.
      IF ls_table-path = lv_table OR ls_table-id = lv_table.
        found = abap_true.
        CLEAR result.
        result-is_cell = abap_true.
        result-table = sy-tabix.

        temp27 = lv_row.
        result-row = temp27.
        result-column = lv_column.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD coerce.
        DATA temp4 TYPE xsdboolean.
      DATA temp58 TYPE string_table.
      DATA lt_key LIKE temp58.
          DATA temp59 TYPE REF TO z2ui5_if_ajson.
          DATA lo_json LIKE temp59.
          DATA lv_count TYPE i.
            DATA ls_element TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
      DATA ls_num TYPE z2ui5_cl_agent_viewxml=>ty_s_arg.
      DATA temp60 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    " the value in the type the model holds there (a Number input bound to a
    " string attribute stays a string, a boolean stays a boolean)
    IF kind = `boolean`.
      IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean.
        result = val.
      ELSEIF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-string AND ( val-str = `true` OR val-str = `false` ).

        temp4 = boolc( val-str = `true` ).
        result = z2ui5_cl_agent_viewxml=>val_boolean( temp4 ).
      ELSE.
        fail( |{ label } is a boolean - pass true or false, not { z2ui5_cl_agent_viewxml=>echo( val_json_quoted( val ) ) }| ).
      ENDIF.
      RETURN.
    ENDIF.
    IF kind = `multichoice`.
      IF val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array.
        fail( |{ label } is a multichoice - pass an array of keys| ).
      ENDIF.
      " every element as a string

      CLEAR temp58.

      lt_key = temp58.
      TRY.

          temp59 ?= z2ui5_cl_ajson=>parse( val-json ).

          lo_json = temp59.

          lv_count = lines( lo_json->members( `/` ) ).
          DO lv_count TIMES.

            ls_element = val_of_node( io_json = lo_json
                                            path    = |/{ sy-index }| ).
            INSERT z2ui5_cl_agent_viewxml=>json_string( z2ui5_cl_agent_viewxml=>val_to_string( ls_element ) ) INTO TABLE lt_key.
          ENDDO.
        CATCH cx_root.
          fail( |{ label } is a multichoice - pass an array of keys| ).
      ENDTRY.
      CLEAR result.
      result-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
      result-json = |[{ concat_lines_of( table = lt_key
sep = `,` ) }]|.
      result-num = lines( lt_key ).
      RETURN.
    ENDIF.
    IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-object OR val-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
      fail( |{ label } takes a single value, not { z2ui5_cl_agent_viewxml=>cut( val = val-json
                                                                                len = 80 ) }| ).
    ENDIF.
    IF current-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.

      ls_num = z2ui5_cl_agent_viewxml=>describe_arg( z2ui5_cl_agent_viewxml=>val_to_string( val ) ).
      IF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number AND val-nan = abap_false.
        result = val.
      ELSEIF val-kind = z2ui5_cl_agent_viewxml=>cs_kind-string AND ls_num-static = abap_true
          AND ls_num-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
        result = ls_num-val.
      ELSE.
        fail( |{ label } holds a number - { z2ui5_cl_agent_viewxml=>echo( val_json_quoted( val ) ) } is none| ).
      ENDIF.
      RETURN.
    ENDIF.
    IF current-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean.

      CLEAR temp60.
      result = coerce( val     = val
                       current = temp60
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

    DATA ls_value LIKE LINE OF t_value.
      DATA ls_target TYPE z2ui5_cl_agent_session=>ty_s_target.
        DATA ls_field TYPE z2ui5_cl_agent_snapshot=>ty_s_field.
        FIELD-SYMBOLS <temp28> LIKE LINE OF mo_snap->mt_field.
        DATA temp29 LIKE sy-tabix.
        DATA lv_label TYPE string.
        DATA ls_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA temp61 TYPE string_table.
          DATA lt_keys LIKE temp61.
          DATA temp62 TYPE string_table.
          DATA lt_quoted LIKE temp62.
          DATA ls_choice LIKE LINE OF ls_field-t_value.
            DATA temp63 LIKE LINE OF lt_quoted.
          DATA temp64 TYPE string_table.
          DATA lt_given LIKE temp64.
                DATA temp65 TYPE REF TO z2ui5_if_ajson.
                DATA lo_keys LIKE temp65.
                DATA lv_key_count TYPE i.
          DATA lv_one LIKE LINE OF lt_given.
            DATA temp66 LIKE sy-subrc.
          DATA temp67 TYPE z2ui5_cl_agent_snapshot=>ty_s_choice.
          DATA temp68 TYPE z2ui5_cl_agent_snapshot=>ty_s_choice.
          DATA ls_first LIKE temp67.
        DATA temp69 TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.
      DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
      FIELD-SYMBOLS <temp30> LIKE LINE OF mo_snap->mt_table.
      DATA temp31 LIKE sy-tabix.
      DATA temp70 LIKE sy-subrc.
        DATA temp71 TYPE string.
      DATA lv_path TYPE string.
      DATA temp72 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellspec.
      DATA ls_spec LIKE temp72.
      DATA temp73 TYPE string.
      DATA lv_kind LIKE temp73.
      DATA temp74 TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.
    DATA ls_plan LIKE LINE OF lt_plan.
    LOOP AT t_value INTO ls_value.

      ls_target = resolve_target( EXPORTING key   = ls_value-key
                                        IMPORTING found = lv_found ).
      IF lv_found = abap_false.
        fail( |no field '{ z2ui5_cl_agent_viewxml=>echo( ls_value-key ) }' on this screen - { field_help( ) }| ).
      ENDIF.

      IF ls_target-is_cell = abap_false.



        temp29 = sy-tabix.
        READ TABLE mo_snap->mt_field INDEX ls_target-field ASSIGNING <temp28>.
        sy-tabix = temp29.
        IF sy-subrc <> 0.
          ASSERT 1 = 0.
        ENDIF.
        ls_field = <temp28>.

        lv_label = |field { ls_field-id } ({ ls_field-label })|.
        IF ls_field-editable = abap_false.
          fail( |field { ls_field-id } ({ ls_field-label }) is not editable - { field_help( ) }| ).
        ENDIF.

        ls_val = coerce( val     = ls_value-val
                               current = mo_snap->model_value( model_key = ls_field-model_key
                                                               path      = ls_field-path )
                               kind    = ls_field-kind
                               label   = lv_label ).
        IF ( ls_field-kind = `choice` OR ls_field-kind = `multichoice` ) AND ls_field-has_values = abap_true.

          CLEAR temp61.

          lt_keys = temp61.

          CLEAR temp62.

          lt_quoted = temp62.

          LOOP AT ls_field-t_value INTO ls_choice.
            INSERT z2ui5_cl_agent_viewxml=>val_to_string( ls_choice-key ) INTO TABLE lt_keys.

            temp63 = |'{ z2ui5_cl_agent_viewxml=>val_to_string( ls_choice-key ) }'|.
            INSERT temp63 INTO TABLE lt_quoted.
          ENDLOOP.

          CLEAR temp64.

          lt_given = temp64.
          IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
            TRY.

                temp65 ?= z2ui5_cl_ajson=>parse( ls_val-json ).

                lo_keys = temp65.

                lv_key_count = lines( lo_keys->members( `/` ) ).
                DO lv_key_count TIMES.
                  INSERT lo_keys->get( |/{ sy-index }| ) INTO TABLE lt_given.
                ENDDO.
              CATCH cx_root ##NO_HANDLER.
                " built by coerce( ) - always an array of strings
            ENDTRY.
          ELSE.
            INSERT z2ui5_cl_agent_viewxml=>val_to_string( ls_val ) INTO TABLE lt_given.
          ENDIF.

          LOOP AT lt_given INTO lv_one.

            READ TABLE lt_keys WITH KEY table_line = lv_one TRANSPORTING NO FIELDS.
            temp66 = sy-subrc.
            IF NOT temp66 = 0. "#EC CI_SORTSEQ
              fail( |{ lv_label }: '{ z2ui5_cl_agent_viewxml=>echo( lv_one ) }' is not one of its values - allowed keys: { list_of( lt_quoted ) }| ).
            ENDIF.
          ENDLOOP.
          " a choice keyed by index (RadioButtonGroup) keeps its number

          CLEAR temp67.

          READ TABLE ls_field-t_value INTO temp68 INDEX 1.
          IF sy-subrc = 0.
            temp67 = temp68.
          ENDIF.

          ls_first = temp67.
          IF ls_field-kind = `choice` AND ls_first-key-kind = z2ui5_cl_agent_viewxml=>cs_kind-number.
            ls_val = z2ui5_cl_agent_viewxml=>val_number( z2ui5_cl_agent_viewxml=>number_normalize(
                                                             z2ui5_cl_agent_viewxml=>val_to_string( ls_val ) ) ).
          ENDIF.
        ENDIF.

        CLEAR temp69.
        temp69-model_key = ls_field-model_key.
        temp69-path = ls_field-path.
        temp69-val = ls_val.
        INSERT temp69 INTO TABLE lt_plan.
        CONTINUE.
      ENDIF.




      temp31 = sy-tabix.
      READ TABLE mo_snap->mt_table INDEX ls_target-table ASSIGNING <temp30>.
      sy-tabix = temp31.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      ls_table = <temp30>.

      READ TABLE ls_table-t_editable WITH KEY table_line = ls_target-column TRANSPORTING NO FIELDS.
      temp70 = sy-subrc.
      IF NOT temp70 = 0. "#EC CI_SORTSEQ

        IF ls_table-t_editable IS NOT INITIAL.
          temp71 = concat_lines_of( table = ls_table-t_editable sep = `, ` ).
        ELSE.
          temp71 = `none`.
        ENDIF.
        fail( |column { ls_target-column } of table { ls_table-id } is not editable - editable columns: | &&
              |{ temp71 }| ).
      ENDIF.
      IF ls_target-row >= ls_table-row_count.
        fail( |table { ls_table-id } has { ls_table-row_count } row(s) - row { ls_target-row } does not exist (rows are 0-based)| ).
      ENDIF.
      IF mo_snap->cell_editable( table_id = ls_table-id
                                 column   = ls_target-column
                                 row      = ls_target-row ) = abap_false.
        fail( |cell { ls_target-column } of row { ls_target-row } in table { ls_table-id } is not editable in that row| ).
      ENDIF.

      lv_path = |{ ls_table-path }/{ ls_target-row }/{ ls_target-column }|.

      CLEAR temp72.

      ls_spec = temp72.
      READ TABLE ls_table-t_cellspec INTO ls_spec WITH KEY name = ls_target-column. "#EC CI_SORTSEQ

      IF ls_spec-has_field_spec = abap_true.
        temp73 = ls_spec-field_kind.
      ELSEIF ls_target-column = ls_table-selection_field.
        temp73 = `boolean`.
      ELSE.
        temp73 = `text`.
      ENDIF.

      lv_kind = temp73.

      CLEAR temp74.
      temp74-model_key = ls_table-model_key.
      temp74-path = lv_path.
      temp74-val = coerce( val = ls_value-val current = mo_snap->model_value( model_key = ls_table-model_key path = lv_path ) kind = lv_kind label = |cell { lv_path }| ).
      INSERT temp74 INTO TABLE lt_plan.
    ENDLOOP.


    LOOP AT lt_plan INTO ls_plan.
      pending_set( ls_plan ).
      INSERT ls_plan-path INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD find_action.

    DATA lt_named TYPE z2ui5_cl_agent_snapshot=>ty_t_action.
    DATA lt_enabled TYPE z2ui5_cl_agent_snapshot=>ty_t_action.
    DATA ls_action LIKE LINE OF mo_snap->mt_action.
    DATA temp75 TYPE z2ui5_cl_agent_snapshot=>ty_t_action.
    DATA lt_pool LIKE temp75.
    FIELD-SYMBOLS <temp76> LIKE LINE OF lt_pool.
    DATA temp77 LIKE sy-tabix.

    READ TABLE mo_snap->mt_action INTO result WITH KEY id = event. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    LOOP AT mo_snap->mt_action INTO ls_action WHERE event = event. "#EC CI_SORTSEQ
      INSERT ls_action INTO TABLE lt_named.
      IF ls_action-enabled = abap_true.
        INSERT ls_action INTO TABLE lt_enabled.
      ENDIF.
    ENDLOOP.
    IF lt_named IS INITIAL.
      fail( |no action '{ z2ui5_cl_agent_viewxml=>echo( event ) }' on this screen - { action_help( ) }| ).
    ENDIF.

    IF lt_enabled IS NOT INITIAL.
      temp75 = lt_enabled.
    ELSE.
      temp75 = lt_named.
    ENDIF.

    lt_pool = temp75.
    IF has_row = abap_true.
      READ TABLE lt_pool INTO result WITH KEY scope = `row`. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
    ELSE.
      " without a row, a screen action of that name before a row action -
      " a "delete selected" button after a table with a DELETE per row was
      " reachable by its id only (mcp-server lib/appclient.mjs findAction)
      LOOP AT lt_pool INTO result WHERE scope <> `row`. "#EC CI_SORTSEQ
        RETURN.
      ENDLOOP.
    ENDIF.


    temp77 = sy-tabix.
    READ TABLE lt_pool INDEX 1 ASSIGNING <temp76>.
    sy-tabix = temp77.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    result = <temp76>.

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

    DATA lt_desc LIKE is_action-t_wire_arg.
    DATA lv_count TYPE i.
        DATA temp78 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
      DATA ls_probe TYPE z2ui5_cl_agent_session=>ty_s_params.
      DATA temp5 TYPE xsdboolean.
        DATA ls_desc LIKE LINE OF lt_desc.
          DATA temp80 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA temp81 TYPE z2ui5_cl_agent_session=>ty_s_input.
        DATA temp82 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
      DATA lv_index TYPE i.
      DATA temp84 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
      DATA temp85 TYPE z2ui5_cl_agent_session=>ty_s_input.
      DATA lv_explicit TYPE abap_bool.
      DATA temp6 TYPE xsdboolean.
        DATA temp86 LIKE sy-subrc.
        DATA temp87 LIKE sy-tabix.
          DATA ls_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA temp88 TYPE string.
          DATA lv_choice LIKE temp88.
            DATA ls_param TYPE z2ui5_cl_agent_session=>ty_s_pnode.
              DATA temp89 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
              DATA temp32 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
            DATA temp90 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
            DATA ls_first TYPE z2ui5_cl_agent_session=>ty_s_params.
    lt_desc = is_action-t_wire_arg.
    IF lines( t_given ) > lines( lt_desc ).
      fail( |action { is_action-id } ({ is_action-event }) takes { lines( lt_desc ) } argument(s) - | &&
            |[{ concat_lines_of( table = is_action-t_arg_json
                                 sep   = `,` ) }]; { lines( t_given ) } given| ).
    ENDIF.
    IF is_action-scope <> `row` AND row_raw IS NOT INITIAL.
      fail( |row is for row actions - { is_action-id } ({ is_action-event }) is a screen action; leave row out| ).
    ENDIF.


    lv_count = 0.
    IF is_action-scope = `row`.
      READ TABLE mo_snap->mt_table INTO ls_table WITH KEY id = is_action-table. "#EC CI_SORTSEQ
      lv_count = mo_snap->table_rows( is_action-table ).
      " an argument the row would fill: a row property, the source control's
      " property in the row, or an event parameter that is the row
      IF is_action-pick = abap_true.
        lt_probe = t_picked.
      ELSEIF lv_count > 0.

        CLEAR temp78.
        INSERT 0 INTO TABLE temp78.
        lt_probe = temp78.
      ENDIF.


      temp5 = boolc( is_action-pick = abap_true OR lv_count > 0 ).
      ls_probe = row_event_params( is_action = is_action
                                         is_table  = ls_table
                                         has_rows  = temp5
                                         t_row     = lt_probe ).
      IF row_raw IS INITIAL.

        LOOP AT lt_desc INTO ls_desc.

          CLEAR temp80.

          READ TABLE t_given INTO temp81 INDEX sy-tabix.
          IF sy-subrc = 0.
            temp80 = temp81-val.
          ENDIF.
          ls_explicit = temp80.
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

        CLEAR temp82.
        INSERT lv_row INTO TABLE temp82.
        ls_params = row_event_params( is_action = is_action
                                      is_table  = ls_table
                                      has_rows  = abap_true
                                      t_row     = temp82 ).
      ENDIF.
    ENDIF.

    LOOP AT lt_desc INTO ls_desc.

      lv_index = sy-tabix - 1.

      CLEAR temp84.

      READ TABLE t_given INTO temp85 INDEX lv_index + 1.
      IF sy-subrc = 0.
        temp84 = temp85-val.
      ENDIF.
      ls_explicit = temp84.


      temp6 = boolc( ls_explicit-kind IS NOT INITIAL AND ls_explicit-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null ).
      lv_explicit = temp6.
      IF ls_desc-static = abap_true.
        IF lv_explicit = abap_true AND z2ui5_cl_agent_viewxml=>val_to_json( ls_explicit ) <> z2ui5_cl_agent_viewxml=>val_to_json( ls_desc-val ).
          fail( |argument { lv_index } of { is_action-event } is static ({ z2ui5_cl_agent_viewxml=>val_to_json( ls_desc-val ) }) - pass null there| ).
        ENDIF.
        INSERT ls_desc-val INTO TABLE result.
        CONTINUE.
      ENDIF.
      IF lv_explicit = abap_true.


        temp87 = sy-tabix.
        READ TABLE is_action-t_choice WITH KEY table_line = z2ui5_cl_agent_viewxml=>val_to_string( ls_explicit ) TRANSPORTING NO FIELDS.
        temp86 = sy-subrc.
        sy-tabix = temp87.
        IF ls_desc-kind = `action` AND is_action-has_choices = abap_true
            AND NOT temp86 = 0. "#EC CI_SORTSEQ
          fail( |argument { lv_index } of { is_action-event }: '{ z2ui5_cl_agent_viewxml=>echo( z2ui5_cl_agent_viewxml=>val_to_string( ls_explicit ) ) }' | &&
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

          ls_val = mo_snap->model_value( model_key = is_action-model_key
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

          CLEAR temp88.

          lv_choice = temp88.
          INSERT z2ui5_cl_agent_viewxml=>val_string( lv_choice ) INTO TABLE result.
        WHEN OTHERS.
          " a $parameters / $expr argument of a row event, from its row(s)
          IF ls_params-active = abap_true.

            ls_param = row_param_arg( is_desc   = ls_desc
                                            is_params = ls_params
                                            is_table  = ls_table ).
            IF ls_param-kind = 'v'.

              CLEAR temp89.
              temp89-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.

              IF ls_param-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_param-val-kind IS INITIAL.
                temp32 = temp89.
              ELSE.
                temp32 = ls_param-val.
              ENDIF.
              INSERT temp32 INTO TABLE result.
              CONTINUE.
            ENDIF.
          ENDIF.
          IF is_action-pick = abap_true AND t_picked IS INITIAL AND lv_count > 0.

            CLEAR temp90.
            INSERT 0 INTO TABLE temp90.

            ls_first = row_event_params( is_action = is_action
                                               is_table  = ls_table
                                               has_rows  = abap_true
                                               t_row     = temp90 ).
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
    DATA ls_row TYPE z2ui5_cl_agent_viewxml=>ty_s_arg.

    result = -1.
    IF row_raw IS INITIAL.
      RETURN.
    ENDIF.

    ls_row = z2ui5_cl_agent_viewxml=>describe_arg( row_raw ).
    IF ls_row-static = abap_false OR ls_row-val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-number
        OR ls_row-val-num <> trunc( ls_row-val-num ) OR ls_row-val-num < 0 OR ls_row-val-num >= count.
      fail( |table { table_id } has { count } row(s) - row { z2ui5_cl_agent_viewxml=>echo( row_raw ) } does not exist (rows are 0-based)| ).
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
    TYPES temp3 TYPE STANDARD TABLE OF abap_bool WITH DEFAULT KEY.
DATA lt_truthy TYPE temp3.
    DATA lv_has_table TYPE abap_bool.
    DATA temp7 TYPE xsdboolean.
    DATA lv_count LIKE ls_table-row_count.
    DATA lv_single TYPE abap_bool.
    DATA temp8 TYPE xsdboolean.
    DATA lv_row TYPE i.
    DATA lv_field LIKE ls_table-selection_field.
        DATA temp92 LIKE LINE OF lt_truthy.
        DATA lr_truthy LIKE REF TO temp92.
          DATA lv_other TYPE i.
            DATA temp93 TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.
      DATA ls_current TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
        DATA temp94 TYPE z2ui5_cl_agent_snapshot=>ty_s_pending.
      DATA lv_line TYPE i.
    DATA lv_truthy LIKE LINE OF lt_truthy.
      DATA lv_selected TYPE i.
      DATA temp95 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA temp97 LIKE sy-subrc.

    " a selection dialog's confirm picks a row, as a click on it does in the
    " browser: the row's selectionField becomes true (and, selecting one row,
    " every other selected row's false) - two-way bound, so the edits travel
    " with the confirm as the model delta. The selected rows, in model order,
    " are what the event's selectedItem / selectedItems / selectedContexts
    " are made of. Without row the selection stays as the model holds it (a
    " multi-select dialog's OK after the rows were ticked through values);
    " picking one row needs one
    READ TABLE mo_snap->mt_table INTO ls_table WITH KEY id = is_action-table. "#EC CI_SORTSEQ


    temp7 = boolc( sy-subrc = 0 ).
    lv_has_table = temp7.

    lv_count = ls_table-row_count.


    temp8 = boolc( lv_has_table = abap_true AND ls_table-selection_mode = `Single` ).
    lv_single = temp8.

    lv_row = row_index( table_id = is_action-table
                              count    = lv_count
                              row_raw  = row_raw ).

    lv_field = ls_table-selection_field.

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


        LOOP AT lt_truthy REFERENCE INTO lr_truthy.

          lv_other = sy-tabix - 1.
          IF lv_other <> lv_row AND lr_truthy->* = abap_true.

            CLEAR temp93.
            temp93-model_key = ls_table-model_key.
            temp93-path = |{ ls_table-path }/{ lv_other }/{ lv_field }|.
            temp93-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ).
            pending_set( temp93 ).
            lr_truthy->* = abap_false.
          ENDIF.
        ENDLOOP.
      ENDIF.

      ls_current = mo_snap->model_value( model_key = ls_table-model_key
                                               path      = lv_field
                                               table_id  = ls_table-id
                                               row       = lv_row ).
      IF NOT ( ls_current-kind = z2ui5_cl_agent_viewxml=>cs_kind-boolean AND ls_current-str = `true` ).

        CLEAR temp94.
        temp94-model_key = ls_table-model_key.
        temp94-path = |{ ls_table-path }/{ lv_row }/{ lv_field }|.
        temp94-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ).
        pending_set( temp94 ).
      ENDIF.

      lv_line = lv_row + 1.
      MODIFY lt_truthy FROM abap_true INDEX lv_line.
    ENDIF.


    LOOP AT lt_truthy INTO lv_truthy.

      lv_selected = sy-tabix - 1.
      IF lv_truthy = abap_true.
        INSERT lv_selected INTO TABLE result.
      ENDIF.
    ENDLOOP.
    IF lv_row >= 0 AND ( lv_single = abap_true OR lv_field IS INITIAL ).

      CLEAR temp95.
      INSERT lv_row INTO TABLE temp95.
      result = temp95.
    ENDIF.

    READ TABLE result WITH KEY table_line = lv_row TRANSPORTING NO FIELDS.
    temp97 = sy-subrc.
    IF lv_row >= 0 AND lv_single = abap_false AND lv_field IS NOT INITIAL AND NOT temp97 = 0.
      INSERT lv_row INTO TABLE result.
    ENDIF.
    IF lv_single = abap_true AND result IS INITIAL.
      fail( |action { is_action-id } ({ is_action-event }) picks a row of table { is_action-table } ({ lv_count } rows) - | &&
            |pass row (0-{ nmax( val1 = 0
                                 val2 = lv_count - 1 ) })| ).
    ENDIF.

  ENDMETHOD.

  METHOD row_event_params.
      DATA temp98 TYPE ty_s_pnode.
      DATA ls_selected LIKE temp98.
      DATA lv_first TYPE i.
      DATA temp99 TYPE z2ui5_cl_agent_session=>ty_s_param.
      DATA temp100 TYPE z2ui5_cl_agent_session=>ty_s_param.
      DATA temp101 TYPE z2ui5_cl_agent_session=>ty_s_param.
    DATA lv_row TYPE i.
    DATA lv_trigger LIKE is_action-trigger.
        DATA temp102 TYPE z2ui5_cl_agent_session=>ty_t_param.
        DATA temp103 LIKE LINE OF temp102.
        DATA temp104 TYPE z2ui5_cl_agent_session=>ty_t_param.
        DATA temp105 LIKE LINE OF temp104.
        DATA temp106 TYPE z2ui5_cl_agent_session=>ty_t_param.
        DATA temp107 LIKE LINE OF temp106.
        DATA temp108 TYPE z2ui5_cl_agent_session=>ty_t_param.
        DATA temp109 LIKE LINE OF temp108.
      DATA temp110 TYPE z2ui5_cl_agent_session=>ty_t_param.
      DATA temp111 LIKE LINE OF temp110.
    DATA temp9 TYPE xsdboolean.

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

      CLEAR temp98.
      temp98-kind = 'v'.
      CLEAR temp98-val.
      temp98-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.

      ls_selected = temp98.

      READ TABLE t_row INTO lv_first INDEX 1.
      IF sy-subrc = 0.
        CLEAR ls_selected.
        ls_selected-kind = 'i'.
        ls_selected-row = lv_first.
      ENDIF.

      CLEAR temp99.
      temp99-name = `selectedItem`.
      temp99-node = ls_selected.
      INSERT temp99 INTO TABLE result-t_param.

      CLEAR temp100.
      temp100-name = `selectedItems`.
      CLEAR temp100-node.
      temp100-node-kind = 'a'.
      temp100-node-elem = 'i'.
      temp100-node-t_row = t_row.
      INSERT temp100 INTO TABLE result-t_param.

      CLEAR temp101.
      temp101-name = `selectedContexts`.
      CLEAR temp101-node.
      temp101-node-kind = 'a'.
      temp101-node-elem = 'c'.
      temp101-node-t_row = t_row.
      INSERT temp101 INTO TABLE result-t_param.
      RETURN.
    ENDIF.

    READ TABLE t_row INTO lv_row INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_trigger = is_action-trigger.
    IF is_action-doc = is_table-doc AND is_action-node = is_table-node.
      IF is_table-kind = `m` AND ( lv_trigger = `itemPress` OR lv_trigger = `selectionChange`
                                   OR lv_trigger = `delete` OR lv_trigger = `beforeOpenContextMenu` ).

        CLEAR temp102.

        temp103-name = `listItem`.
        CLEAR temp103-node.
        temp103-node-kind = 'i'.
        temp103-node-row = lv_row.
        INSERT temp103 INTO TABLE temp102.
        result-t_param = temp102.
      ELSEIF is_table-kind = `ui` AND lv_trigger = `rowSelectionChange`.

        CLEAR temp104.

        temp105-name = `rowIndex`.
        temp105-node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ).
        INSERT temp105 INTO TABLE temp104.
        temp105-name = `rowContext`.
        CLEAR temp105-node.
        temp105-node-kind = 'c'.
        temp105-node-row = lv_row.
        INSERT temp105 INTO TABLE temp104.
        result-t_param = temp104.
      ELSEIF is_table-kind = `ui` AND lv_trigger = `cellClick`.

        CLEAR temp106.

        temp107-name = `rowIndex`.
        temp107-node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ).
        INSERT temp107 INTO TABLE temp106.
        temp107-name = `rowBindingContext`.
        CLEAR temp107-node.
        temp107-node-kind = 'c'.
        temp107-node-row = lv_row.
        INSERT temp107 INTO TABLE temp106.
        result-t_param = temp106.
      ELSEIF is_table-kind = `ui` AND lv_trigger = `beforeOpenContextMenu`.

        CLEAR temp108.

        temp109-name = `rowIndex`.
        temp109-node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lv_row }| ) ).
        INSERT temp109 INTO TABLE temp108.
        result-t_param = temp108.
      ENDIF.
    ELSEIF is_table-kind = `ui` AND is_action-row_template = `rowActionTemplate`.

      CLEAR temp110.

      temp111-name = `row`.
      CLEAR temp111-node.
      temp111-node-kind = 'i'.
      temp111-node-row = lv_row.
      INSERT temp111 INTO TABLE temp110.
      result-t_param = temp110.
    ENDIF.

    temp9 = boolc( result-t_param IS NOT INITIAL ).
    result-active = temp9.

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
    TYPES temp4 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp4.
    DATA temp112 TYPE ty_s_pnode.
    DATA ls_node LIKE temp112.
    DATA lv_seg LIKE LINE OF lt_seg.
        DATA temp113 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
            DATA lv_line TYPE i.
            DATA lv_elem_row TYPE i.
              DATA lv_elem LIKE ls_node-elem.
              DATA temp114 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA ls_param TYPE z2ui5_cl_agent_session=>ty_s_param.
          DATA temp115 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA temp116 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    SPLIT path AT `/` INTO TABLE lt_seg.
    DELETE lt_seg WHERE table_line IS INITIAL.

    CLEAR temp112.
    temp112-kind = 'o'.

    ls_node = temp112.

    LOOP AT lt_seg INTO lv_seg.
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

        CLEAR temp113.
        temp113-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
        result = pnode_value( temp113 ).
        RETURN.
      ENDIF.
      CASE ls_node-kind.
        WHEN 'a'.
          IF lv_seg = `length`.
            ls_node = pnode_value( z2ui5_cl_agent_viewxml=>val_number( |{ lines( ls_node-t_row ) }| ) ).
          ELSE.

            lv_line = 0.
            IF lv_seg CO `0123456789` AND strlen( lv_seg ) <= 9.
              lv_line = lv_seg.
              lv_line = lv_line + 1.
            ENDIF.

            lv_elem_row = 0.
            IF lv_line > 0.
              READ TABLE ls_node-t_row INTO lv_elem_row INDEX lv_line.
            ENDIF.
            IF lv_line > 0 AND sy-subrc = 0.
              " not VALUE #( kind = ls_node-elem ) - the target is cleared first

              lv_elem = ls_node-elem.
              CLEAR ls_node.
              ls_node-kind = lv_elem.
              ls_node-row = lv_elem_row.
            ELSE.

              CLEAR temp114.
              temp114-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
              ls_node = pnode_value( temp114 ).
            ENDIF.
          ENDIF.
        WHEN 'o'.

          READ TABLE is_params-t_param INTO ls_param WITH KEY name = lv_seg. "#EC CI_SORTSEQ
          IF sy-subrc <> 0.
            result-kind = '?'.
            RETURN.
          ENDIF.
          ls_node = ls_param-node.
        WHEN OTHERS.
          " a number or a string has no key

          CLEAR temp115.
          temp115-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
          result = pnode_value( temp115 ).
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

          CLEAR temp116.
          temp116-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
          temp116-json = `[]`.
          result = pnode_value( temp116 ).
        ENDIF.
      WHEN OTHERS.
        result = ls_node.
    ENDCASE.

  ENDMETHOD.

  METHOD head_of.

    " the parameter a call chain starts from, as a value: an item or a
    " context is not walked into; a parameter this client does not model is
    " unknown
    TYPES temp5 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp5.
    DATA lv_seg LIKE LINE OF lt_seg.
          DATA ls_param TYPE z2ui5_cl_agent_session=>ty_s_param.
          DATA lv_line TYPE i.
          DATA lv_elem_row TYPE i.
            DATA lv_elem LIKE result-elem.
            DATA temp117 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
          DATA temp118 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    SPLIT path AT `/` INTO TABLE lt_seg.
    DELETE lt_seg WHERE table_line IS INITIAL.
    CLEAR result.
    result-kind = 'o'.

    LOOP AT lt_seg INTO lv_seg.
      IF ( result-kind = 'v' AND ( result-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null
                                   OR result-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined ) )
          OR result-kind = 'i' OR result-kind = 'c' OR result-kind = 'l' OR lv_seg CA `[]`.
        CLEAR result.
        result-kind = '?'.
        RETURN.
      ENDIF.
      CASE result-kind.
        WHEN 'o'.

          READ TABLE is_params-t_param INTO ls_param WITH KEY name = lv_seg. "#EC CI_SORTSEQ
          IF sy-subrc <> 0.
            CLEAR result.
            result-kind = '?'.
            RETURN.
          ENDIF.
          result = ls_param-node.
        WHEN 'a'.

          lv_line = 0.
          IF lv_seg CO `0123456789` AND strlen( lv_seg ) <= 9.
            lv_line = lv_seg.
            lv_line = lv_line + 1.
          ENDIF.

          lv_elem_row = 0.
          IF lv_line > 0.
            READ TABLE result-t_row INTO lv_elem_row INDEX lv_line.
          ENDIF.
          IF lv_line > 0 AND sy-subrc = 0.
            " not VALUE #( kind = result-elem ) - the target is cleared first

            lv_elem = result-elem.
            CLEAR result.
            result-kind = lv_elem.
            result-row = lv_elem_row.
          ELSE.

            CLEAR temp117.
            temp117-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
            result = pnode_value( temp117 ).
          ENDIF.
        WHEN OTHERS.

          CLEAR temp118.
          temp118-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
          result = pnode_value( temp118 ).
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
    DATA lv_src TYPE string.
    DATA lv_len TYPE i.
    DATA lv_close TYPE i.
    DATA lv_path TYPE string.
    DATA lv_pos TYPE i.
    DATA lv_q TYPE i.
      DATA lv_after TYPE i.
      DATA lv_max TYPE i.
      DATA lv_start LIKE lv_max.
      DATA lv_tern LIKE abap_false.
      DATA temp119 TYPE ty_s_val.
      DATA ls_lit LIKE temp119.
      DATA lv_end TYPE i.
        DATA ls_cond TYPE z2ui5_cl_agent_session=>ty_s_pnode.
    DATA lv_rest TYPE string.
    DATA ls_cur TYPE z2ui5_cl_agent_session=>ty_s_pnode.
      DATA lv_rlen TYPE i.
      DATA lv_name_from LIKE lv_pos.
      DATA lv_fn TYPE string.
      DATA lv_has_arg LIKE abap_false.
      DATA lv_arg TYPE string.
        DATA lv_quote TYPE string.
        DATA lv_arg_end TYPE i.
      DATA lv_row LIKE ls_cur-row.
          DATA ls_prop TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
        DATA lv_digit_from LIKE lv_pos.
        DATA lv_digits TYPE string.
        DATA temp120 TYPE i.
        DATA lv_cell LIKE temp120.
        DATA lv_prop TYPE string.
        DATA lv_node TYPE i.
          DATA lv_cell_line TYPE z2ui5_cl_agent_session=>ty_s_pnode-cell.
        DATA ls_value TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    result-kind = '?'.

    lv_src = str_trim( raw ).

    lv_len = strlen( lv_src ).
    IF lv_len < 15 OR substring( val = lv_src
                                 len = 14 ) <> lc_head.
      RETURN.
    ENDIF.
    " the reference: ${$parameters>/?<path>} - no braces inside

    lv_close = find( val = lv_src
                           sub = `}`
                           off = 14 ).
    IF lv_close < 0.
      RETURN.
    ENDIF.

    lv_path = substring( val = lv_src
                               off = 14
                               len = lv_close - 14 ).
    IF lv_path CA `{`.
      RETURN.
    ENDIF.
    IF strlen( lv_path ) > 0 AND lv_path(1) = `/`.
      lv_path = substring( val = lv_path
                           off = 1 ).
    ENDIF.

    lv_pos = lv_close + 1.

    " the ternary: <reference> ? <shape> : <literal>

    lv_q = skip_ws( val = lv_src
                          pos = lv_pos ).
    IF lv_q < lv_len AND lv_src+lv_q(1) = `?`.

      lv_after = lv_q + 1.

      lv_max = skip_ws( val = lv_src
                              pos = lv_after ).

      lv_start = lv_max.

      lv_tern = abap_false.

      CLEAR temp119.

      ls_lit = temp119.

      lv_end = 0.
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

        ls_cond = head_of( is_params = is_params
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


    lv_rest = substring( val = lv_src
                               off = lv_pos ).
    IF str_trim( lv_rest ) IS INITIAL.
      result = walk_params( is_params = is_params
                            path      = lv_path
                            is_table  = is_table ).
      RETURN.
    ENDIF.

    ls_cur = head_of( is_params = is_params
                            path      = lv_path ).
    IF ls_cur-kind = '?'.
      RETURN.
    ENDIF.
    WHILE str_trim( lv_rest ) IS NOT INITIAL.
      IF ls_cur-kind <> 'i' AND ls_cur-kind <> 'c' AND ls_cur-kind <> 'l'.
        RETURN.
      ENDIF.
      " .<name>( ) or .<name>('<arg>')

      lv_rlen = strlen( lv_rest ).
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

      lv_name_from = lv_pos.
      WHILE lv_pos < lv_rlen AND lv_rest+lv_pos(1) CA lc_word.
        lv_pos = lv_pos + 1.
      ENDWHILE.

      lv_fn = substring( val = lv_rest
                               off = lv_name_from
                               len = lv_pos - lv_name_from ).
      lv_pos = skip_ws( val = lv_rest
                        pos = lv_pos ).
      IF lv_pos >= lv_rlen OR lv_rest+lv_pos(1) <> `(`.
        RETURN.
      ENDIF.
      lv_pos = skip_ws( val = lv_rest
                        pos = lv_pos + 1 ).

      lv_has_arg = abap_false.

      lv_arg = ``.
      IF lv_pos < lv_rlen AND ( lv_rest+lv_pos(1) = `'` OR lv_rest+lv_pos(1) = `"` ).

        lv_quote = lv_rest+lv_pos(1).

        lv_arg_end = find( val = lv_rest
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


      lv_row = ls_cur-row.
      IF ls_cur-kind = 'c'.
        IF lv_fn = `getPath` AND lv_has_arg = abap_false.
          ls_cur = pnode_value( z2ui5_cl_agent_viewxml=>val_string( |{ is_table-path }/{ lv_row }| ) ).
        ELSEIF lv_fn = `getProperty` AND lv_has_arg = abap_true.

          ls_prop = mo_snap->model_value( model_key = is_table-model_key
                                                path      = lv_arg
                                                table_id  = is_table-id
                                                row       = lv_row ).
          IF ls_prop-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_prop-kind IS INITIAL.
            CLEAR ls_prop.
            ls_prop-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
          ENDIF.
          ls_cur = pnode_value( ls_prop ).
        ELSE.
          RETURN.
        ENDIF.
      ELSEIF lv_fn = `getBindingContext` AND lv_has_arg = abap_false.
        CLEAR ls_cur.
        ls_cur-kind = 'c'.
        ls_cur-row = lv_row.
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

        lv_digit_from = lv_pos.
        WHILE lv_pos < lv_rlen AND lv_rest+lv_pos(1) CA `0123456789`.
          lv_pos = lv_pos + 1.
        ENDWHILE.
        IF lv_pos = lv_digit_from.
          RETURN.
        ENDIF.

        lv_digits = substring( val = lv_rest
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

        temp120 = lv_digits.

        lv_cell = temp120.
        IF lv_cell >= lines( is_table-t_cellnode ).
          RETURN.
        ENDIF.
        CLEAR ls_cur.
        ls_cur-kind = 'l'.
        ls_cur-row = lv_row.
        ls_cur-cell = lv_cell.
      ELSEIF strlen( lv_fn ) > 3 AND lv_fn(3) = `get` AND lv_fn+3(1) CA `ABCDEFGHIJKLMNOPQRSTUVWXYZ`
          AND lv_has_arg = abap_false AND lv_fn <> `getId`.
        " a property getter: the template attribute resolved in the row - a
        " number as the string the UI5 property holds; an attribute the
        " template does not set (or one bound to nothing) is unknown

        lv_prop = to_lower( lv_fn+3(1) ) && substring( val = lv_fn
                                                            off = 4 ).

        lv_node = 0.
        IF ls_cur-kind = 'l'.

          lv_cell_line = ls_cur-cell + 1.
          READ TABLE is_table-t_cellnode INTO lv_node INDEX lv_cell_line.
        ELSEIF is_table-kind = `m`.
          lv_node = is_table-template.
        ENDIF.
        IF lv_node = 0.
          RETURN.
        ENDIF.

        ls_value = mo_snap->template_value( table_id = is_table-id
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
    DATA lv_len TYPE i.
    DATA lv_pos TYPE i.
    DATA lv_char TYPE string.
      DATA lv_text TYPE string.
      DATA lv_closed LIKE abap_false.
        DATA lv_c TYPE string.
      DATA lv_value TYPE string.
      DATA lv_i TYPE i.
      DATA lv_text_len TYPE i.
      DATA lv_from LIKE lv_pos.
      DATA lv_digits_from LIKE lv_pos.
      DATA lv_next TYPE i.

    " \s*:\s*('...'|"..."|null|-?\d+(\.\d+)?)\s*$ at off
    found = abap_false.

    lv_len = strlen( val ).

    lv_pos = skip_ws( val = val
                            pos = off ).
    IF lv_pos >= lv_len OR val+lv_pos(1) <> `:`.
      RETURN.
    ENDIF.
    lv_pos = skip_ws( val = val
                      pos = lv_pos + 1 ).
    IF lv_pos >= lv_len.
      RETURN.
    ENDIF.

    lv_char = val+lv_pos(1).
    IF lv_char = `'` OR lv_char = `"`.

      lv_text = ``.
      lv_pos = lv_pos + 1.

      lv_closed = abap_false.
      WHILE lv_pos < lv_len AND lv_closed = abap_false.

        lv_c = val+lv_pos(1).
        CASE lv_c.
          WHEN `\`.
            IF lv_pos + 1 >= lv_len.
              RETURN.
            ENDIF.
            lv_text = lv_text && val+lv_pos(2).
            lv_pos = lv_pos + 2.
          WHEN lv_char.
            lv_closed = abap_true.
            lv_pos = lv_pos + 1.
          WHEN OTHERS.
            lv_text = lv_text && lv_c.
            lv_pos = lv_pos + 1.
        ENDCASE.
      ENDWHILE.
      IF lv_closed = abap_false.
        RETURN.
      ENDIF.
      " the escapes: \x is x

      lv_value = ``.

      lv_i = 0.

      lv_text_len = strlen( lv_text ).
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

      lv_from = lv_pos.
      IF lv_char = `-`.
        lv_pos = lv_pos + 1.
      ENDIF.

      lv_digits_from = lv_pos.
      WHILE lv_pos < lv_len AND val+lv_pos(1) CA `0123456789`.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      IF lv_pos = lv_digits_from.
        RETURN.
      ENDIF.

      lv_next = lv_pos + 1.
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

    CLEAR result.
    result-kind = 'v'.
    result-val = val.

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

    DATA lv_ws TYPE string.
    DATA lv_len TYPE i.
    lv_ws = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf
               && cl_abap_char_utilities=>form_feed && cl_abap_char_utilities=>vertical_tab.
    result = pos.

    lv_len = strlen( val ).
    WHILE result < lv_len AND val+result(1) CA lv_ws.
      result = result + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD str_trim.

    DATA lv_ws TYPE string.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
      DATA lv_last TYPE i.
    lv_ws = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf
               && cl_abap_char_utilities=>form_feed && cl_abap_char_utilities=>vertical_tab.

    lv_from = skip_ws( val = val
                             pos = 0 ).

    lv_to = strlen( val ).
    WHILE lv_to > lv_from.

      lv_last = lv_to - 1.
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
        DATA temp121 TYPE string.

    " an event argument as the text the simulator sends (click( ) t_arg): a
    " boolean as abap_bool, as the core turns the browser's true / false
    " into X / space
    CASE val-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-boolean.

        IF val-str = `true`.
          temp121 = `X`.
        ELSE.
          CLEAR temp121.
        ENDIF.
        result = temp121.
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
    DATA temp122 TYPE string.
    DATA lv_model_key LIKE temp122.
        DATA ls_pending LIKE LINE OF mt_pending.
        DATA lx_value TYPE REF TO cx_root.
    DATA ls_arg LIKE LINE OF t_arg.
        DATA lx TYPE REF TO cx_root.
    DATA lt_layer TYPE z2ui5_cl_frontend_sim=>ty_t_layer.
    DATA ls_keep LIKE LINE OF lt_keep.
      DATA temp123 LIKE sy-subrc.
    IF is_action-model_key IS INITIAL.
      temp122 = z2ui5_cl_agent_snapshot=>cs_model-main.
    ELSE.
      temp122 = is_action-model_key.
    ENDIF.

    lv_model_key = temp122.
    TRY.

        LOOP AT mt_pending INTO ls_pending.
          IF ls_pending-model_key <> lv_model_key.
            INSERT ls_pending INTO TABLE lt_keep.
            CONTINUE.
          ENDIF.
          mo_sim->set_json( path  = ls_pending-path
                            json  = z2ui5_cl_agent_viewxml=>val_to_json( ls_pending-val )
                            layer = lv_model_key ).
        ENDLOOP.

      CATCH cx_root INTO lx_value.
        fail( |the pending values could not be sent - { lx_value->get_text( ) }; nothing was sent| ).
    ENDTRY.


    LOOP AT t_arg INTO ls_arg.
      INSERT sim_text( ls_arg ) INTO TABLE lt_arg.
    ENDLOOP.

    TRY.
        mo_sim->click( event = is_action-event
                       t_arg = lt_arg
                       layer = lv_model_key ).

      CATCH cx_root INTO lx.
        app_rollback( ).
        fail( |the backend refused the roundtrip - { lx->get_text( ) }| ).
    ENDTRY.
    IF mo_sim->is_sticky( ) = abap_true.
      app_rollback( ).
      DELETE FROM z2ui5_t_16 WHERE id = ms_row-id.
      fail( |the app switched to a stateful session (set_session_stateful) - such a session lives in one request only, | &&
            |so this agent session ended; app_start { ms_row-app_start } again| ).
    ENDIF.

    " edits of another layer's model survive, as long as that layer is open
    mt_custom = custom_of_sim( ).

    lt_layer = mo_sim->get_layers( ).
    CLEAR mt_pending.

    LOOP AT lt_keep INTO ls_keep.

      READ TABLE lt_layer WITH KEY layer = ls_keep-model_key TRANSPORTING NO FIELDS.
      temp123 = sy-subrc.
      IF temp123 = 0. "#EC CI_SORTSEQ
        INSERT ls_keep INTO TABLE mt_pending.
      ENDIF.
    ENDLOOP.
    analyze( ).

  ENDMETHOD.

  METHOD app_rollback.

    z2ui5_cl_ui5_util_context=>db_rollback( ).

  ENDMETHOD.

  METHOD close_layer.
        DATA lx TYPE REF TO cx_root.

    " performed in the browser: the simulator closes the slot without a
    " roundtrip, and get_state( ) - what the session is saved with - no
    " longer carries it
    TRY.
        mo_sim->close_layer( slot ).

      CATCH cx_root INTO lx.
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
    DATA ls_value LIKE LINE OF t_value.
      DATA lv_masked LIKE abap_false.
      DATA temp124 TYPE string.
      DATA lv_app LIKE temp124.
        DATA ls_target TYPE z2ui5_cl_agent_session=>ty_s_target.
          DATA ls_field TYPE z2ui5_cl_agent_snapshot=>ty_s_field.
          FIELD-SYMBOLS <temp33> LIKE LINE OF mo_snap->mt_field.
          DATA temp34 LIKE sy-tabix.
          DATA temp10 TYPE xsdboolean.
          DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
          FIELD-SYMBOLS <temp35> LIKE LINE OF mo_snap->mt_table.
          DATA temp36 LIKE sy-tabix.
      DATA temp125 TYPE string.
      DATA temp37 LIKE LINE OF lt_part.
    LOOP AT t_value INTO ls_value.

      lv_masked = abap_false.

      IF mo_sim IS BOUND.
        temp124 = mo_sim->get_app( ).
      ELSE.
        temp124 = app.
      ENDIF.

      lv_app = temp124.
      IF mo_snap IS NOT BOUND.
        " no screen to resolve the key against: judged by the key alone
        lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                              path = ls_value-key
                                                              name = ls_value-key ).
        IF lv_masked = abap_false.
          lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                path = |/{ ls_value-key }|
                                                                name = ls_value-key ).
        ENDIF.
      ELSE.

        ls_target = resolve_target( EXPORTING key   = ls_value-key
                                          IMPORTING found = lv_found ).
        IF lv_found = abap_true AND ls_target-is_cell = abap_false.



          temp34 = sy-tabix.
          READ TABLE mo_snap->mt_field INDEX ls_target-field ASSIGNING <temp33>.
          sy-tabix = temp34.
          IF sy-subrc <> 0.
            ASSERT 1 = 0.
          ENDIF.
          ls_field = <temp33>.

          temp10 = boolc( mo_snap->is_secret( ls_field-id ) = abap_true OR z2ui5_cl_agent_settings=>check_sensitive( app = lv_app path = ls_field-path name = ls_field-name ) = abap_true ).
          lv_masked = temp10.
        ELSEIF lv_found = abap_true.



          temp36 = sy-tabix.
          READ TABLE mo_snap->mt_table INDEX ls_target-table ASSIGNING <temp35>.
          sy-tabix = temp36.
          IF sy-subrc <> 0.
            ASSERT 1 = 0.
          ENDIF.
          ls_table = <temp35>.
          lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                path = |{ ls_table-path }/{ ls_target-row }/{ ls_target-column }|
                                                                name = ls_target-column ).
        ELSE.
          " a key the screen does not know: a name like IBAN is checked as
          " the path /IBAN as well, the shape the sensitive rules are written in
          lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                path = ls_value-key
                                                                name = ls_value-key ).
          IF lv_masked = abap_false.
            lv_masked = z2ui5_cl_agent_settings=>check_sensitive( app  = lv_app
                                                                  path = |/{ ls_value-key }|
                                                                  name = ls_value-key ).
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_masked = abap_true.
        temp125 = z2ui5_cl_agent_viewxml=>json_string( z2ui5_cl_agent_audit=>c_mask ).
      ELSE.
        temp125 = z2ui5_cl_agent_viewxml=>val_to_json( ls_value-val ).
      ENDIF.

      temp37 = |{ z2ui5_cl_agent_viewxml=>json_string( ls_value-key ) }:| && |{ temp125 }|.
      INSERT temp37 INTO TABLE lt_part.
    ENDLOOP.
    result = |\{{ concat_lines_of( table = lt_part
                                   sep   = `,` ) }\}|.

  ENDMETHOD.

ENDCLASS.
