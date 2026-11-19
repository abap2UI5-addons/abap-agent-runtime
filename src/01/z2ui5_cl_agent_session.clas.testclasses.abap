CLASS ltcl_args DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_session DEFINITION LOCAL FRIENDS ltcl_args.

"! In-memory draft store, installed through the core's store seam
"! (z2ui5_cl_ui5_srv_draft=&gt;set_instance) - the drafts of the sessions
"! below never reach Z2UI5_T_01.
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


"! The four operations on the example app z2ui5_cl_agent_demo, end to end
"! through the headless frontend simulator. DANGEROUS: the sessions, the
"! audit log and the settings are database tables - setup switches the
"! endpoint on, teardown deletes what the tests wrote and restores the
"! settings as they were.
CLASS ltcl_session DEFINITION FINAL
  FOR TESTING RISK LEVEL DANGEROUS DURATION MEDIUM.

  PRIVATE SECTION.
    CONSTANTS c_client TYPE string VALUE `ABAP Unit`.
    CONSTANTS c_app TYPE string VALUE `Z2UI5_CL_AGENT_DEMO`.

    DATA mo_store   TYPE REF TO ltd_draft_store.
    DATA mo_session TYPE REF TO z2ui5_cl_agent_session.
    DATA mt_setting TYPE z2ui5_cl_agent_settings=>ty_t_setting.
    DATA mv_start   TYPE timestampl.

    METHODS setup.
    METHODS teardown.

    METHODS start_snapshot      FOR TESTING.
    METHODS list_and_opt_in     FOR TESTING.
    METHODS act_values_event    FOR TESTING.
    METHODS earlier_session     FOR TESTING.
    METHODS long_session_id     FOR TESTING.
    METHODS validation          FOR TESTING.
    METHODS policy              FOR TESTING.
    METHODS pending_values      FOR TESTING.
    METHODS popup_flow          FOR TESTING.
    METHODS row_action          FOR TESTING.
    METHODS max_rows_kept       FOR TESTING.
    METHODS copilot_dialog      FOR TESTING.
    METHODS row_selection       FOR TESTING.
    METHODS typed_values        FOR TESTING.
    METHODS structure_table     FOR TESTING.
    METHODS disabled            FOR TESTING.
    METHODS audit_masks         FOR TESTING.
    METHODS audit_masks_act     FOR TESTING.
    METHODS claimed_session     FOR TESTING.
    METHODS audit_cleanup_range FOR TESTING.
    METHODS cut_surrogate_pair  FOR TESTING.
    METHODS admin_key_not_kept  FOR TESTING.
    METHODS admin_change_kept   FOR TESTING.
    METHODS admin_rule_fits     FOR TESTING.
    METHODS audit_admin_revoked FOR TESTING.
    METHODS pick_single         FOR TESTING.
    METHODS pick_multi          FOR TESTING.
    METHODS pick_refused        FOR TESTING.

    METHODS start
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_session=>ty_s_result.

    METHODS ok
      IMPORTING
        is_result     TYPE z2ui5_cl_agent_session=>ty_s_result
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_if_ajson.

    METHODS refused
      IMPORTING
        is_result TYPE z2ui5_cl_agent_session=>ty_s_result
        pattern   TYPE string.

    METHODS action_id
      IMPORTING
        io_snap       TYPE REF TO z2ui5_if_ajson
        event         TYPE string
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_session IMPLEMENTATION.

  METHOD setup.

    CREATE OBJECT mo_store.
    z2ui5_cl_ui5_srv_draft=>set_instance( mo_store ).
    mv_start = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).

    SELECT * FROM z2ui5_t_17 INTO TABLE mt_setting.
    DELETE FROM z2ui5_t_17.
    z2ui5_cl_agent_settings=>set_enabled( abap_true ).
    COMMIT WORK.
    CREATE OBJECT mo_session EXPORTING CLIENT = c_client.

  ENDMETHOD.

  METHOD teardown.

    DATA li_default TYPE REF TO z2ui5_if_ui5_draft_store.

    DELETE FROM z2ui5_t_16 WHERE uname = sy-uname AND created_at >= mv_start.
    DELETE FROM z2ui5_t_14 WHERE uname = sy-uname AND mcp_client = c_client AND timestampl >= mv_start.
    DELETE FROM z2ui5_t_17.
    INSERT z2ui5_t_17 FROM TABLE mt_setting.
    COMMIT WORK.
    z2ui5_cl_agent_settings=>refresh( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( li_default ).

  ENDMETHOD.

  METHOD start.

    result = mo_session->app_start( c_app ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD ok.

    cl_abap_unit_assert=>assert_false( act = is_result-is_error
                                       msg = is_result-text ).
    TRY.
        result = z2ui5_cl_ajson=>parse( is_result-text ).
      CATCH cx_root.
        cl_abap_unit_assert=>fail( |no JSON: { is_result-text }| ).
    ENDTRY.

  ENDMETHOD.

  METHOD refused.

    cl_abap_unit_assert=>assert_true( act = is_result-is_error
                                      msg = |not refused: { substring( val = is_result-text
                                                                       len = nmin( val1 = 300
                                                                                   val2 = strlen( is_result-text ) ) ) }| ).
    cl_abap_unit_assert=>assert_char_cp( exp = pattern
                                         act = is_result-text ).

  ENDMETHOD.

  METHOD action_id.

    DATA lv_count TYPE i.
    lv_count = lines( io_snap->members( `/actions` ) ).
    DO lv_count TIMES.
      IF io_snap->get_string( |/actions/{ sy-index }/event| ) = event.
        result = io_snap->get_string( |/actions/{ sy-index }/id| ).
        RETURN.
      ENDIF.
    ENDDO.
    cl_abap_unit_assert=>fail( |no action { event }| ).

  ENDMETHOD.

  METHOD start_snapshot.

    DATA ls_result TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA lv_count TYPE i.
    DATA lo_two TYPE REF TO z2ui5_if_ajson.
    DATA lo_many TYPE REF TO z2ui5_if_ajson.
    ls_result = start( ).

    lo_snap = ok( ls_result ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lo_snap->get_integer( `/snapshotVersion` ) ).
    cl_abap_unit_assert=>assert_equals( exp = ls_result-session
                                        act = lo_snap->get_string( `/session` ) ).
    cl_abap_unit_assert=>assert_equals( exp = c_app
                                        act = lo_snap->get_string( `/app` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Travel requests`
                                        act = lo_snap->get_string( `/title` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Name`
                                        act = lo_snap->get_string( `/fields/1/label` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_snap->get_boolean( `/fields/1/required` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `choice`
                                        act = lo_snap->get_string( `/fields/2/kind` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `number`
                                        act = lo_snap->get_string( `/fields/3/kind` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lo_snap->get_integer( `/tables/1/rowCount` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `SELKZ`
                                        act = lo_snap->get_string( `/tables/1/selectionField` ) ).
    " the policy of each event rides on its action

    lv_count = lines( lo_snap->members( `/actions` ) ).
    DO lv_count TIMES.
      CASE lo_snap->get_string( |/actions/{ sy-index }/event| ).
        WHEN `SUBMIT`.
          cl_abap_unit_assert=>assert_equals( exp = `confirm`
                                              act = lo_snap->get_string( |/actions/{ sy-index }/policy| ) ).
        WHEN `DELETE_ALL`.
          cl_abap_unit_assert=>assert_equals( exp = `forbidden`
                                              act = lo_snap->get_string( |/actions/{ sy-index }/policy| ) ).
        WHEN `ADD`.
          cl_abap_unit_assert=>assert_false( lo_snap->exists( |/actions/{ sy-index }/policy| ) ).
      ENDCASE.
    ENDDO.

    " app_describe answers the same from the session, no roundtrip
    cl_abap_unit_assert=>assert_equals( exp = ls_result-text
                                        act = mo_session->app_describe( ls_result-session )-text ).

    lo_two = ok( mo_session->app_describe( session  = ls_result-session
                                                 max_rows = `1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_two->get_boolean( `/tables/1/truncated` ) ).
    " beyond any integer: clamped to the limit like any number above it

    lo_many = ok( mo_session->app_describe( session  = ls_result-session
                                                  max_rows = `10000000000` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false
                                        act = lo_many->get_boolean( `/tables/1/truncated` ) ).

  ENDMETHOD.

  METHOD list_and_opt_in.

    " the addon's own apps are never startable, an app without opt-in is not
    refused( is_result = mo_session->app_start( `Z2UI5_CL_AGENT_APP_ADMIN` )
             pattern   = `*never operable by an agent*` ).
    refused( is_result = mo_session->app_start( `Z2UI5_CL_UI5_APP_HI_WORLD` )
             pattern   = `*not enabled for agents*` ).
    refused( is_result = mo_session->app_start( `Z2UI5_CL_NO_SUCH_CLASS` )
             pattern   = `*no abap2UI5 app*` ).

    " an administrator allows it: startable without the interface
    z2ui5_cl_agent_settings=>save( kind  = z2ui5_cl_agent_settings=>cs_kind-app
                                   app   = `Z2UI5_CL_UI5_APP_HI_*`
                                   value = z2ui5_cl_agent_settings=>cs_app_rule-allow ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_app( `Z2UI5_CL_UI5_APP_HI_WORLD` ) ).
    " ... and a deny rule wins over the interface
    z2ui5_cl_agent_settings=>save( kind  = z2ui5_cl_agent_settings=>cs_kind-app
                                   app   = c_app
                                   value = z2ui5_cl_agent_settings=>cs_app_rule-deny ).
    refused( is_result = mo_session->app_start( c_app )
             pattern   = `*denied for agents*` ).

  ENDMETHOD.

  METHOD act_values_event.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA lv_messages LIKE ls_act-text.
    ls_start = start( ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = `{"NAME":"Carol","/DAYS":5,"f2":"ROM","HOTEL":true}`
                                        event   = `ADD` ).
    COMMIT WORK.

    lo_snap = ok( ls_act ).
    " a roundtrip mints a new draft - the session moves on with it
    cl_abap_unit_assert=>assert_differs( exp = ls_start-session
                                         act = ls_act-session ).
    cl_abap_unit_assert=>assert_equals( exp = 3
                                        act = lo_snap->get_integer( `/tables/1/rowCount` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Carol`
                                        act = lo_snap->get_string( `/tables/1/rows/3/NAME` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ROM`
                                        act = lo_snap->get_string( `/tables/1/rows/3/DESTINATION` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 5
                                        act = lo_snap->get_integer( `/tables/1/rows/3/DAYS` ) ).
    " the toast of the response, and the strip that is visible now

    lv_messages = ls_act-text.
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Request 3 added","source":"toast"*`
                                         act = lv_messages ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"source":"strip"*`
                                         act = lv_messages ).
    " the field was cleared by the app
    cl_abap_unit_assert=>assert_initial( lo_snap->get_string( `/fields/1/value` ) ).

  ENDMETHOD.

  METHOD earlier_session.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = `{"NAME":"Eve"}`
                                        event   = `ADD` ).
    COMMIT WORK.
    ok( ls_act ).
    refused( is_result = mo_session->app_describe( ls_start-session )
             pattern   = |*earlier state*'{ ls_act-session }'*| ).
    refused( is_result = mo_session->app_describe( `NO_SUCH_SESSION` )
             pattern   = `*unknown session*` ).

  ENDMETHOD.

  METHOD long_session_id.

    " an id longer than the column is unknown - not the session of its first
    " 32 characters, nor an earlier state of it
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).
    refused( is_result = mo_session->app_describe( |{ ls_start-session }X| )
             pattern   = |*unknown session '{ ls_start-session }X'*| ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = `{"NAME":"Eve"}`
                                        event   = `ADD` ).
    COMMIT WORK.
    ok( ls_act ).
    refused( is_result = mo_session->app_describe( |{ ls_start-session }X| )
             pattern   = `*unknown session*` ).
    ok( mo_session->app_describe( ls_act-session ) ).

  ENDMETHOD.

  METHOD validation.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"NOPE":"x"}` )
             pattern   = `*no field 'NOPE' on this screen - fields you can fill: f1 (Name, /NAME)*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"DESTINATION":"XYZ"}` )
             pattern   = `*'XYZ' is not one of its values - allowed keys: 'BER', 'PAR', 'ROM'*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"HOTEL":"yes"}` )
             pattern   = `*is a boolean - pass true or false, not "yes"*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"DAYS":"many"}` )
             pattern   = `*holds a number*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `FOO` )
             pattern   = `*no action 'FOO' on this screen - allowed events: *ADD (a*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              row     = `1` )
             pattern   = `*row belongs to an event*` ).
    refused( is_result = mo_session->app_act( session  = ls_start-session
                                              max_rows = `lots` )
             pattern   = `*max_rows must be a number*` ).
    " a row beyond any integer is no cell - refused, also by the audit entry
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"/T_REQUEST/99999999999999999999/SELKZ":true}` )
             pattern   = `*no field '/T_REQUEST/99999999999999999999/SELKZ' on this screen*` ).
    " a refused act changes nothing
    cl_abap_unit_assert=>assert_equals( exp = ls_start-text
                                        act = mo_session->app_describe( ls_start-session )-text ).

  ENDMETHOD.

  METHOD policy.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_submit TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_submit = mo_session->app_act( session = ls_start-session
                                           event   = `SUBMIT` ).
    refused( is_result = ls_submit
             pattern   = `*needs a human*` ).
    refused( is_result = ls_submit
             pattern   = |*#/app/{ c_app }/{ ls_start-session }*| ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `DELETE_ALL` )
             pattern   = `*forbidden for agents*` ).

    " a setting is stricter than the app: ADD becomes confirm
    z2ui5_cl_agent_settings=>save( kind  = z2ui5_cl_agent_settings=>cs_kind-event
                                   app   = `Z2UI5_CL_AGENT_*`
                                   item  = `ADD`
                                   value = z2ui5_if_agent_app=>cs_policy-confirm ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `ADD` )
             pattern   = `*the setting EVENT Z2UI5_CL_AGENT_* ADD classifies it confirm*` ).

    " an app denied after the session started - or reached by navigation -
    " is denied for every event, not only at app_start
    z2ui5_cl_agent_settings=>save( kind  = z2ui5_cl_agent_settings=>cs_kind-app
                                   app   = c_app
                                   value = z2ui5_cl_agent_settings=>cs_app_rule-deny ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `POPUP_OPEN` )
             pattern   = |*{ c_app } is denied for agents by the setting APP*| ).

  ENDMETHOD.

  METHOD pending_values.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_typed TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_add TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_typed = mo_session->app_act( session = ls_start-session
                                          values  = `{"NAME":"Dave"}` ).
    COMMIT WORK.

    lo_snap = ok( ls_typed ).
    " typing does not roundtrip: same session, the value pending
    cl_abap_unit_assert=>assert_equals( exp = ls_start-session
                                        act = ls_typed-session ).
    cl_abap_unit_assert=>assert_equals( exp = `Dave`
                                        act = lo_snap->get_string( `/fields/1/value` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/NAME`
                                        act = lo_snap->get_string( `/pending/1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = ls_typed-text
                                        act = mo_session->app_describe( ls_start-session )-text ).


    ls_add = mo_session->app_act( session = ls_start-session
                                        event   = `ADD` ).
    COMMIT WORK.
    lo_snap = ok( ls_add ).
    cl_abap_unit_assert=>assert_equals( exp = `Dave`
                                        act = lo_snap->get_string( `/tables/1/rows/3/NAME` ) ).
    cl_abap_unit_assert=>assert_false( lo_snap->exists( `/pending` ) ).

  ENDMETHOD.

  METHOD popup_flow.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_open TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_close TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_ok TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_open = mo_session->app_act( session = ls_start-session
                                         event   = `POPUP_OPEN` ).
    COMMIT WORK.

    lo_snap = ok( ls_open ).
    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->get_string( `/layer` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/NOTE`
                                        act = lo_snap->get_string( `/fields/1/path` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_snap->members( `/fields` ) ) ).
    " the page behind a dialog is not on the screen
    refused( is_result = mo_session->app_act( session = ls_open-session
                                              values  = `{"NAME":"x"}` )
             pattern   = `*(a popup is open: only its fields and actions count until it closes)*` ).

    " a layer closed in the browser reads nothing: a row or args are refused
    refused( is_result = mo_session->app_act( session = ls_open-session
                                              event   = `@CLOSE_POPUP`
                                              row     = `7` )
             pattern   = `*takes no row and no args*` ).

    " closed in the browser: no roundtrip, the draft stays

    ls_close = mo_session->app_act( session = ls_open-session
                                          event   = `@CLOSE_POPUP` ).
    COMMIT WORK.
    lo_snap = ok( ls_close ).
    cl_abap_unit_assert=>assert_equals( exp = ls_open-session
                                        act = ls_close-session ).
    cl_abap_unit_assert=>assert_equals( exp = `main`
                                        act = lo_snap->get_string( `/layer` ) ).

    " open again, write the note, confirm
    ls_open = mo_session->app_act( session = ls_close-session
                                   event   = action_id( io_snap = lo_snap
                                                        event   = `POPUP_OPEN` ) ).
    COMMIT WORK.
    ok( ls_open ).

    ls_ok = mo_session->app_act( session = ls_open-session
                                       values  = `{"/NOTE":"back on Friday"}`
                                       event   = `POPUP_OK` ).
    COMMIT WORK.
    lo_snap = ok( ls_ok ).
    cl_abap_unit_assert=>assert_equals( exp = `main`
                                        act = lo_snap->get_string( `/layer` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Note: back on Friday","source":"strip"*`
                                         act = ls_ok-text ).

  ENDMETHOD.

  METHOD copilot_dialog.

    " a value typed into a dialog is not written to the app on close: it was
    " read from the main model - the stale value there written over the
    " user's, and the path reported as filled
    DATA lt_refused TYPE string_table.
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA temp1 TYPE REF TO z2ui5_cl_agent_session.
    DATA ls_open TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA temp2 TYPE REF TO z2ui5_cl_agent_session.
    DATA ls_typed TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA temp3 TYPE REF TO z2ui5_cl_agent_session.
    DATA lo_demo TYPE REF TO z2ui5_cl_agent_demo.
    DATA lt_written TYPE string_table.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-copilot
                                      value = `on` ).
    COMMIT WORK.


    CREATE OBJECT temp1 TYPE z2ui5_cl_agent_session EXPORTING client = c_client mode = z2ui5_cl_agent_session=>cs_mode-copilot.
    ls_start = temp1->app_start( c_app ).
    COMMIT WORK.


    CREATE OBJECT temp2 TYPE z2ui5_cl_agent_session EXPORTING client = c_client mode = z2ui5_cl_agent_session=>cs_mode-copilot.
    ls_open = temp2->app_act( session = ls_start-session
                                                                                                         event   = `POPUP_OPEN` ).
    COMMIT WORK.


    CREATE OBJECT temp3 TYPE z2ui5_cl_agent_session EXPORTING client = c_client mode = z2ui5_cl_agent_session=>cs_mode-copilot.
    ls_typed = temp3->app_act( session = ls_open-session
                                                                                                          values  = `{"/NOTE":"back on Friday"}` ).
    COMMIT WORK.
    ok( ls_typed ).

    CREATE OBJECT lo_demo TYPE z2ui5_cl_agent_demo.
    lo_demo->note = `typed by the user`.

    lt_written = z2ui5_cl_agent_assist=>apply_pending( EXPORTING session   = ls_typed-session
                                                                       app       = lo_demo
                                                             IMPORTING t_refused = lt_refused ).
    cl_abap_unit_assert=>assert_equals( exp = `typed by the user`
                                        act = lo_demo->note ).
    cl_abap_unit_assert=>assert_initial( lt_written ).
    cl_abap_unit_assert=>assert_char_cp( exp = `/NOTE was typed into a dialog*`
                                         act = concat_lines_of( lt_refused ) ).

  ENDMETHOD.

  METHOD max_rows_kept.

    " an act's max_rows is the session's from then on - app_describe
    " answered the stored snapshot for any max_rows asked
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = mo_session->app_start( app      = c_app
                                            max_rows = `1` ).
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( ok( ls_start )->members( `/tables/1/rows` ) ) ).

    ls_act = mo_session->app_act( session  = ls_start-session
                                        values   = `{"NAME":"x"}`
                                        max_rows = `2` ).
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ok( ls_act )->members( `/tables/1/rows` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( ok( mo_session->app_describe( session  = ls_act-session
                                                                                   max_rows = `1` ) )->members( `/tables/1/rows` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ok( mo_session->app_describe( ls_act-session ) )->members( `/tables/1/rows` ) ) ).

  ENDMETHOD.

  METHOD row_action.

    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_detail TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `DETAIL` )
             pattern   = `*is a row action of table t1 (2 rows) - pass row (0-1)*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `DETAIL`
                                              row     = `7` )
             pattern   = `*table t1 has 2 row(s) - row 7 does not exist*` ).

    ls_detail = mo_session->app_act( session = ls_start-session
                                           event   = `DETAIL`
                                           row     = `1` ).
    COMMIT WORK.
    ok( ls_detail ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"messages":[{"type":"info","text":"Request 2","source":"box"}]*`
                                         act = ls_detail-text ).

  ENDMETHOD.

  METHOD row_selection.

    " selecting a row is setting its selection field
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    ls_start = start( ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = `{"/T_REQUEST/1/SELKZ":true,"NAME":"Fay"}`
                                        event   = `ADD` ).
    COMMIT WORK.

    lo_snap = ok( ls_act ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_snap->get_boolean( `/tables/1/rows/2/SELKZ` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false
                                        act = lo_snap->get_boolean( `/tables/1/rows/1/SELKZ` ) ).
    refused( is_result = mo_session->app_act( session = ls_act-session
                                              values  = `{"t1/0/NAME":"x"}` )
             pattern   = `*column NAME of table t1 is not editable - editable columns: SELKZ*` ).

  ENDMETHOD.

  METHOD typed_values.

    " a boolean and a multichoice travel as JSON true / false and an array
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_plan TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_none TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_plan = mo_session->app_act( session = ls_start-session
                                         values  = `{"HOTEL":true,"TAGS":["FAIR","MEET"]}`
                                         event   = `PLAN` ).
    COMMIT WORK.

    lo_snap = ok( ls_plan ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Plan: Customer visit, 2 stop(s), 3 night(s), tags FAIR,MEET, hotel yes","source":"strip"*`
                                         act = ls_plan-text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"path":"/TAGS"*"kind":"multichoice","value":["FAIR","MEET"]*`
                                         act = ls_plan-text ).

    refused( is_result = mo_session->app_act( session = ls_plan-session
                                              values  = `{"TAGS":["XX"]}` )
             pattern   = `*'XX' is not one of its values - allowed keys: 'FAIR', 'MEET', 'TRAIN'*` ).
    refused( is_result = mo_session->app_act( session = ls_plan-session
                                              values  = `{"TAGS":"FAIR"}` )
             pattern   = `*is a multichoice - pass an array of keys*` ).


    ls_none = mo_session->app_act( session = ls_plan-session
                                         values  = `{"HOTEL":false,"TAGS":[]}`
                                         event   = action_id( io_snap = lo_snap
                                                              event   = `PLAN` ) ).
    COMMIT WORK.
    ok( ls_none ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Plan: Customer visit, 2 stop(s), 3 night(s), tags none, hotel no","source":"strip"*`
                                         act = ls_none-text ).

  ENDMETHOD.

  METHOD structure_table.

    " a field of a structure that holds a table, and a cell of that table:
    " the whole structure travels, its table with it
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_plan TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_typed TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_sent TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_plan = mo_session->app_act( session = ls_start-session
                                         values  = `{"/TRIP/PURPOSE":"Fair","t2/1/NIGHTS":4}`
                                         event   = `PLAN` ).
    COMMIT WORK.

    lo_snap = ok( ls_plan ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Plan: Fair, 2 stop(s), 5 night(s), tags none, hotel no","source":"strip"*`
                                         act = ls_plan-text ).
    cl_abap_unit_assert=>assert_equals( exp = `/TRIP/T_STOP`
                                        act = lo_snap->get_string( `/tables/2/path` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4
                                        act = lo_snap->get_integer( `/tables/2/rows/2/NIGHTS` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Lyon`
                                        act = lo_snap->get_string( `/tables/2/rows/1/CITY` ) ).

    " pending first, sent with the next event - the same delta

    ls_typed = mo_session->app_act( session = ls_plan-session
                                          values  = `{"t2/0/NIGHTS":3}` ).
    COMMIT WORK.
    ok( ls_typed ).

    ls_sent = mo_session->app_act( session = ls_typed-session
                                         event   = `PLAN` ).
    COMMIT WORK.
    ok( ls_sent ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Plan: Fair, 2 stop(s), 7 night(s), tags none, hotel no","source":"strip"*`
                                         act = ls_sent-text ).

  ENDMETHOD.

  METHOD disabled.

    z2ui5_cl_agent_settings=>set_enabled( abap_false ).
    refused( is_result = mo_session->app_start( c_app )
             pattern   = `*endpoint is disabled*` ).
    refused( is_result = mo_session->app_list( )
             pattern   = `*endpoint is disabled*` ).

  ENDMETHOD.

  METHOD audit_masks.

    DATA ls_result TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lv_args TYPE z2ui5_t_14-args.
    ls_result = mo_session->app_start( app    = c_app
                                             values = `{"IBAN":"DE02100100109307118603","NAME":"Gus"}` ).
    COMMIT WORK.
    ok( ls_result ).

    SELECT SINGLE args FROM z2ui5_t_14 INTO lv_args
      WHERE uname = sy-uname AND session_id = ls_result-session AND operation = 'app_start'
      . "#EC CI_NOORDER
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"IBAN":"***"*`
                                         act = lv_args ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"NAME":"Gus"*`
                                         act = lv_args ).

  ENDMETHOD.

  METHOD audit_masks_act.

    " typed with an event that opens a popup: the next screen has no IBAN
    " field, and the value is still masked - judged against the screen it
    " was typed into
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lv_args TYPE z2ui5_t_14-args.
    ls_start = start( ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = `{"IBAN":"DE02100100109307118603"}`
                                        event   = `POPUP_OPEN` ).
    COMMIT WORK.
    ok( ls_act ).

    SELECT SINGLE args FROM z2ui5_t_14 INTO lv_args
      WHERE uname = sy-uname AND session_id = ls_act-session AND operation = 'app_act'
      . "#EC CI_NOORDER
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"IBAN":"***"*`
                                         act = lv_args ).
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = lv_args
                                                    sub = `DE02100100109307118603` ) ).

  ENDMETHOD.

  METHOD claimed_session.

    " another call holds the session (its claim puts changed_at ahead):
    " an act on it is refused before anything runs, and the row is left
    " as it was
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA temp3 TYPE z2ui5_t_16-id.
    DATA lv_id LIKE temp3.
    DATA lv_ahead TYPE timestampl.
    DATA lv_still TYPE z2ui5_t_16-id.
    ls_start = start( ).

    temp3 = ls_start-session.

    lv_id = temp3.

    lv_ahead = z2ui5_cl_ui5_util_context=>time_subtract_seconds(
                         time    = z2ui5_cl_ui5_util_context=>time_get_timestampl( )
                         seconds = -300 ).
    UPDATE z2ui5_t_16 SET changed_at = lv_ahead WHERE id = lv_id.
    COMMIT WORK.
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `POPUP_OPEN` )
             pattern   = `*being continued by another call*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              values  = `{"NAME":"x"}` )
             pattern   = `*being continued by another call*` ).

    SELECT SINGLE id FROM z2ui5_t_16 INTO lv_still WHERE id = lv_id .
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = lv_id
                                        act = lv_still ).

  ENDMETHOD.

  METHOD audit_cleanup_range.

    " days beyond what days * 86400 seconds holds as an integer: nothing to
    " delete that old - and no overflow
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = z2ui5_cl_agent_audit=>cleanup( z2ui5_cl_agent_audit=>c_max_days + 1 ) ).

  ENDMETHOD.

  METHOD cut_surrogate_pair.

    DATA lv_args TYPE string.

    " U+1F600 is two UTF-16 code units - its first one alone is no character
    DATA temp4 TYPE xstring.
    DATA lv_emoji TYPE string.
    DATA lv_high TYPE string.
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_act TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA temp5 TYPE z2ui5_cl_agent_audit=>ty_s_entry.
    temp4 = `F09F9880`.

    lv_emoji = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp4 ).

    lv_high = substring( val = lv_emoji
                               len = 1 ).

    " the refusal quotes the value cut to 80 characters - right in the pair

    ls_start = start( ).

    ls_act = mo_session->app_act( session = ls_start-session
                                        values  = |\{"NAME":\{"k":"{ repeat( val = `a`
                                                                               occ = 73 ) }{ lv_emoji }"\}\}| ).
    refused( is_result = ls_act
             pattern   = `*takes a single value, not {"k":"aaa*` ).
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = ls_act-text
                                                    sub = lv_high ) ).

    " the audit log cuts its arguments to c_max_args characters - in the pair

    CLEAR temp5.
    temp5-session = `CUT_SURROGATE_PAIR`.
    temp5-operation = `app_list`.
    temp5-args = |{ repeat( val = `a` occ = z2ui5_cl_agent_audit=>c_max_args - 4 ) }{ lv_emoji }tail|.
    temp5-outcome = z2ui5_cl_agent_audit=>cs_outcome-ok.
    temp5-client = c_client.
    z2ui5_cl_agent_audit=>log( temp5 ).
    COMMIT WORK.
    SELECT SINGLE args FROM z2ui5_t_14 INTO lv_args
      WHERE uname = sy-uname AND session_id = 'CUT_SURROGATE_PAIR' AND timestampl >= mv_start
      . "#EC CI_NOORDER
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = |{ repeat( val = `a`
                                                         occ = z2ui5_cl_agent_audit=>c_max_args - 4 ) }...|
                                        act = lv_args ).

  ENDMETHOD.

  METHOD admin_key_not_kept.

    " a key typed into the settings app and sent with another event than
    " Save (here by a user who may not change anything) is not kept in the
    " app's draft, nor sent back to the browser
    DATA lo_sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA ls_db LIKE LINE OF mo_store->mt_db.
    lo_sim = z2ui5_cl_frontend_sim=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `LLM_KEY`
                       value = `sk-unit-typed-key` ).
    lo_sim->click( `LLM_TEST` ).

    LOOP AT mo_store->mt_db INTO ls_db.
      cl_abap_unit_assert=>assert_equals( exp = -1
                                          act = find( val = ls_db-data
                                                      sub = `sk-unit-typed-key` )
                                          msg = |the typed key is in draft { ls_db-id }| ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = lo_sim->get_model( )
                                                    sub = `sk-unit-typed-key` ) ).

  ENDMETHOD.

  METHOD admin_change_kept.

    DATA lv_count TYPE i.
    DATA lo_sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_url TYPE z2ui5_t_17-value.

    " abap2UI5 rolls back what main( ) leaves open: a change an
    " administrator saves in the settings app - and its audit entry - is
    " committed by the app itself
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).

    lo_sim = z2ui5_cl_frontend_sim=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `URL`
                       value = `/sap/bc/unit_handover` ).
    lo_sim->click( `URL_SAVE` ).

    SELECT SINGLE value FROM z2ui5_t_17 INTO lv_url WHERE kind = 'URL' . "#EC CI_NOORDER
    cl_abap_unit_assert=>assert_equals( exp = `/sap/bc/unit_handover`
                                        act = lv_url ).
    SELECT COUNT(*) FROM z2ui5_t_14 INTO lv_count
      WHERE uname = sy-uname AND operation = 'settings' AND timestampl >= mv_start .
    DELETE FROM z2ui5_t_14 WHERE uname = sy-uname AND operation = 'settings' AND timestampl >= mv_start.
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lv_count ).

  ENDMETHOD.

  METHOD admin_rule_fits.

    DATA lv_count TYPE i.
    DATA lo_sim TYPE REF TO z2ui5_cl_frontend_sim.

    " a rule longer than the settings table holds is refused, not cut: a
    " SENSITIVE pattern cut to 60 characters masks nothing
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).

    lo_sim = z2ui5_cl_frontend_sim=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `NEW_KIND`
                       value = `SENSITIVE` ).
    lo_sim->set_value( name  = `NEW_APP`
                       value = `*` ).
    lo_sim->set_value( name  = `NEW_ITEM`
                       value = `/MS_ORDER/S_PAYMENT/T_ACCOUNT/*/INTERNATIONAL_BANK_ACCOUNT_NUMBER` ).
    lo_sim->click( `RULE_ADD` ).
    SELECT COUNT(*) FROM z2ui5_t_17 INTO lv_count WHERE kind = 'SENSITIVE' .
    DELETE FROM z2ui5_t_14 WHERE uname = sy-uname AND operation = 'settings' AND timestampl >= mv_start.
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = lv_count ).
    cl_abap_unit_assert=>assert_char_cp( exp = `The rule is too long: 65 characters*at most 60*`
                                         act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD audit_admin_revoked.
    DATA lo_sim TYPE REF TO z2ui5_cl_frontend_sim.

    " the audit log app shows everybody's calls only while the user is an
    " agent administrator - not as long as its draft remembers that he was
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).

    lo_sim = z2ui5_cl_frontend_sim=>start( `Z2UI5_CL_AGENT_APP_AUDIT` ).
    z2ui5_cl_agent_settings=>remove( kind = z2ui5_cl_agent_settings=>cs_kind-admin
                                     app  = sy-uname ).
    COMMIT WORK.
    lo_sim->set_bool( `ALL_USERS` ).
    lo_sim->click( `SEARCH` ).
    cl_abap_unit_assert=>assert_char_cp( exp = |*, user { sy-uname }*|
                                         act = lo_sim->get_model( ) ).

  ENDMETHOD.

  METHOD pick_single.

    " a SelectDialog value help: the pick selects the row (SELKZ), clears
    " the previous selection, and fills the confirm's argument from the row
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_help TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_typed TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_pick TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_help = mo_session->app_act( session = ls_start-session
                                         event   = `DEST_HELP` ).
    COMMIT WORK.

    lo_snap = ok( ls_help ).
    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->get_string( `/layer` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Destinations`
                                        act = lo_snap->get_string( `/title` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.SelectDialog`
                                        act = lo_snap->get_string( `/tables/1/control` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Single`
                                        act = lo_snap->get_string( `/tables/1/selectionMode` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `SELKZ`
                                        act = lo_snap->get_string( `/tables/1/selectionField` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"event":"DEST_PICKED","args":["$expr:${$parameters>/selectedItem}.getTitle()"]*"scope":"row","table":"t1"*`
                                         act = ls_help-text ).

    " a row ticked before: picking another one clears it

    ls_typed = mo_session->app_act( session = ls_help-session
                                          values  = `{"t1/0/SELKZ":true}` ).
    COMMIT WORK.
    ok( ls_typed ).

    ls_pick = mo_session->app_act( session = ls_typed-session
                                         event   = `DEST_PICKED`
                                         row     = `2` ).
    COMMIT WORK.
    lo_snap = ok( ls_pick ).
    cl_abap_unit_assert=>assert_equals( exp = `main`
                                        act = lo_snap->get_string( `/layer` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Destination ROM (Rome), 1 selected","source":"strip"*`
                                         act = ls_pick-text ).
    cl_abap_unit_assert=>assert_equals( exp = `ROM`
                                        act = lo_snap->get_string( `/fields/2/value` ) ).

    " without a ticked row the pick is enough
    ls_help = mo_session->app_act( session = ls_pick-session
                                   event   = `DEST_HELP` ).
    COMMIT WORK.
    ok( ls_help ).
    ls_pick = mo_session->app_act( session = ls_help-session
                                   event   = `DEST_PICKED`
                                   row     = `1` ).
    COMMIT WORK.
    ok( ls_pick ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Destination PAR (Paris), 1 selected","source":"strip"*`
                                         act = ls_pick-text ).

  ENDMETHOD.

  METHOD pick_multi.

    " a TableSelectDialog for several rows: the pick adds its row to the
    " ticked ones, the argument counts the selected contexts
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_help TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA lo_snap TYPE REF TO z2ui5_if_ajson.
    DATA ls_pick TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_none TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_help = mo_session->app_act( session = ls_start-session
                                         event   = `TAGS_HELP` ).
    COMMIT WORK.

    lo_snap = ok( ls_help ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.TableSelectDialog`
                                        act = lo_snap->get_string( `/tables/1/control` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Multi`
                                        act = lo_snap->get_string( `/tables/1/selectionMode` ) ).

    ls_pick = mo_session->app_act( session = ls_help-session
                                         values  = `{"t1/0/SELKZ":true}`
                                         event   = `TAGS_PICKED`
                                         row     = `2` ).
    COMMIT WORK.
    ok( ls_pick ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"2 tag(s) picked: FAIR,TRAIN","source":"strip"*`
                                         act = ls_pick-text ).

    " without row a multi-select dialog confirms what is ticked - here nothing
    ls_help = mo_session->app_act( session = ls_pick-session
                                   event   = `TAGS_HELP` ).
    COMMIT WORK.
    ok( ls_help ).

    ls_none = mo_session->app_act( session = ls_help-session
                                         values  = `{"t1/0/SELKZ":false,"t1/2/SELKZ":false}`
                                         event   = `TAGS_PICKED` ).
    COMMIT WORK.
    ok( ls_none ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"0 tag(s) picked:","source":"strip"*`
                                         act = ls_none-text ).

  ENDMETHOD.

  METHOD pick_refused.

    " picking one row needs one; a row that does not exist is refused; a
    " refused pick changes nothing
    DATA ls_start TYPE z2ui5_cl_agent_session=>ty_s_result.
    DATA ls_help TYPE z2ui5_cl_agent_session=>ty_s_result.
    ls_start = start( ).

    ls_help = mo_session->app_act( session = ls_start-session
                                         event   = `DEST_HELP` ).
    COMMIT WORK.
    ok( ls_help ).
    refused( is_result = mo_session->app_act( session = ls_help-session
                                              event   = `DEST_PICKED` )
             pattern   = `action a1 (DEST_PICKED) picks a row of table t1 (3 rows) - pass row (0-2)` ).
    refused( is_result = mo_session->app_act( session = ls_help-session
                                              event   = `DEST_PICKED`
                                              row     = `3` )
             pattern   = `table t1 has 3 row(s) - row 3 does not exist (rows are 0-based)` ).
    refused( is_result = mo_session->app_act( session = ls_help-session
                                              event   = `HELP_CANCEL`
                                              row     = `1` )
             pattern   = `row is for row actions - a2 (HELP_CANCEL) is a screen action; leave row out` ).
    cl_abap_unit_assert=>assert_equals( exp = ls_help-text
                                        act = mo_session->app_describe( ls_help-session )-text ).

  ENDMETHOD.

ENDCLASS.


"! The pick and the arguments of row events on synthetic screens - the
"! cases of the reference's test/appclient.test.mjs, without a backend:
"! the snapshot is built from the view and the model, the pick and the
"! argument filling run as app_act runs them, nothing is sent.
CLASS ltcl_args DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO z2ui5_cl_agent_session.
    DATA mv_xml TYPE string.
    DATA mv_model TYPE string.

    METHODS pick_single    FOR TESTING.
    METHODS pick_multi     FOR TESTING.
    METHODS pick_ticked    FOR TESTING.
    METHODS pick_none      FOR TESTING.
    METHODS pick_unknown   FOR TESTING.
    METHODS table_events   FOR TESTING.
    METHODS screen_before_row FOR TESTING.
    METHODS action_hidden  FOR TESTING.
    METHODS action_disabled FOR TESTING.

    METHODS screen
      IMPORTING
        xml       TYPE string
        model     TYPE string
        t_pending TYPE z2ui5_cl_agent_snapshot=>ty_t_pending OPTIONAL.

    "! The pick (for a pick action) and the arguments as JSON - or the refusal.
    METHODS act
      IMPORTING
        event         TYPE string
        row           TYPE string OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    METHODS pending
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS dialog
      IMPORTING
        multi         TYPE string
        args          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS rows
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_args IMPLEMENTATION.

  METHOD screen.
    DATA temp6 TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    DATA temp4 TYPE z2ui5_cl_frontend_sim=>ty_t_layer.
    DATA temp5 LIKE LINE OF temp4.

    mv_xml = |<mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:t="sap.ui.table"><Page title="T">{ xml }</Page></mvc:View>|.
    mv_model = model.
    CREATE OBJECT mo_cut EXPORTING CLIENT = `ABAP Unit`.
    mo_cut->mt_pending = t_pending.

    CLEAR temp6.
    temp6-session = `D1`.
    temp6-app = `Z_T`.
    temp6-max_rows = 20.
    temp6-t_pending = t_pending.

    CLEAR temp4.

    temp5-layer = `MAIN`.
    temp5-xml = mv_xml.
    temp5-model = mv_model.
    INSERT temp5 INTO TABLE temp4.
    temp6-t_layer = temp4.
    mo_cut->mo_snap = z2ui5_cl_agent_snapshot=>create( temp6 ).

  ENDMETHOD.

  METHOD act.

    DATA lt_part TYPE string_table.
    DATA lt_picked TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
        DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
        DATA temp2 TYPE xsdboolean.
          DATA temp7 TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
          DATA temp6 TYPE z2ui5_cl_frontend_sim=>ty_t_layer.
          DATA temp9 LIKE LINE OF temp6.
        DATA temp10 TYPE z2ui5_cl_agent_session=>ty_t_input.
        DATA temp8 TYPE z2ui5_cl_agent_viewxml=>ty_t_val.
        DATA ls_val LIKE LINE OF temp8.
        DATA lx TYPE REF TO z2ui5_cx_ui5_util_error.

    TRY.


        temp2 = boolc( row IS NOT INITIAL ).
        ls_action = mo_cut->find_action( event   = event
                                               has_row = temp2 ).
        IF ls_action-pick = abap_true.
          lt_picked = mo_cut->apply_pick( is_action = ls_action
                                          row_raw   = row ).

          CLEAR temp7.
          temp7-session = `D1`.
          temp7-app = `Z_T`.
          temp7-max_rows = 20.
          temp7-t_pending = mo_cut->mt_pending.

          CLEAR temp6.

          temp9-layer = `MAIN`.
          temp9-xml = mv_xml.
          temp9-model = mv_model.
          INSERT temp9 INTO TABLE temp6.
          temp7-t_layer = temp6.
          mo_cut->mo_snap = z2ui5_cl_agent_snapshot=>create( temp7 ).
        ENDIF.

        CLEAR temp10.

        temp8 = mo_cut->event_args( is_action = ls_action t_given = temp10 row_raw = row t_picked = lt_picked ).

        LOOP AT temp8 INTO ls_val.
          INSERT z2ui5_cl_agent_viewxml=>val_to_json( ls_val ) INTO TABLE lt_part.
        ENDLOOP.
        result = |[{ concat_lines_of( table = lt_part
                                      sep   = `,` ) }]|.

      CATCH z2ui5_cx_ui5_util_error INTO lx.
        result = lx->get_text( ).
    ENDTRY.

  ENDMETHOD.

  METHOD pending.

    DATA lt_part TYPE string_table.

    DATA ls_pending LIKE LINE OF mo_cut->mt_pending.
      DATA temp9 LIKE LINE OF lt_part.
    LOOP AT mo_cut->mt_pending INTO ls_pending.

      temp9 = |{ ls_pending-path }={ z2ui5_cl_agent_viewxml=>val_to_json( ls_pending-val ) }|.
      INSERT temp9 INTO TABLE lt_part.
    ENDLOOP.
    result = concat_lines_of( table = lt_part
                              sep   = ` ` ).

  ENDMETHOD.

  METHOD dialog.

    result = |<TableSelectDialog title="Pick" multiSelect="{ multi }" items="\{/T\}" confirm=".eB(['OK']{ args })">| &&
             `<ColumnListItem selected="{SEL}" type="Active"><cells><Text text="{A}"/><ObjectIdentifier title="{B}" text="{N}"/></cells>` &&
             `</ColumnListItem><columns><Column><header><Text text="A"/></header></Column><Column><header><Text text="B"/></header>` &&
             `</Column></columns></TableSelectDialog>`.

  ENDMETHOD.

  METHOD rows.

    result = `{"T":[{"A":"a0","B":"b0","N":0,"SEL":false},{"A":"a1","B":"b1","N":10,"SEL":true},{"A":"a2","B":"b2","N":20,"SEL":false}]}`.

  ENDMETHOD.

  METHOD pick_single.

    " the picked row selected, the previous selection cleared - both pending;
    " item arguments from the row; selectedContexts[0]/sPath is null, as the
    " browser's JSONModel has no [n] syntax
    screen( xml   = dialog( multi = `false`
                            args  = `, ${$parameters>/selectedContexts/0/sPath}` &&
                                    `, ${$parameters>/selectedItem}.getCells()[1].getTitle()` &&
                                    `, ${$parameters>/selectedItem}.getCells()[1].getText()` &&
                                    `, ${$parameters>/selectedItem}.getBindingContext().getProperty('A')` &&
                                    `, ${$parameters>/selectedItem}.getBindingContext().getPath()` &&
                                    `, ${$parameters>/selectedItem} ? ${$parameters>/selectedItem}.getCells()[0].getText() : ''` &&
                                    `, ${$parameters>/selectedItem}.getType()` &&
                                    `, ${$parameters>/selectedContexts/length}` &&
                                    `, ${$parameters>/selectedContexts[0]/sPath}` )
            model = rows( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `["/T/2","b2","20","a2","/T/2","a2","Active",1,null]`
                                        act = act( event = `OK`
                                                   row   = `2` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/T/1/SEL=false /T/2/SEL=true`
                                        act = pending( ) ).

  ENDMETHOD.

  METHOD pick_multi.

    " the row joins the selection, selectedItem is the first selected row in
    " model order
    screen( xml   = dialog( multi = `true`
                            args  = `, ${$parameters>/selectedContexts/1/sPath}, ${$parameters>/selectedItem}.getCells()[0].getText()` )
            model = rows( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `["/T/2","a1"]`
                                        act = act( event = `OK`
                                                   row   = `2` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/T/2/SEL=true`
                                        act = pending( ) ).

  ENDMETHOD.

  METHOD pick_ticked.

    " without row a multi-select dialog confirms what is ticked
    DATA temp10 TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.
    DATA temp11 LIKE LINE OF temp10.
    CLEAR temp10.

    temp11-model_key = `MAIN`.
    temp11-path = `/T/0/SEL`.
    temp11-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ).
    INSERT temp11 INTO TABLE temp10.
    screen( xml       = dialog( multi = `true`
                                args  = `, ${$parameters>/selectedContexts/0/sPath}` )
            model     = replace( val  = rows( )
                                 sub  = `"N":10,"SEL":true`
                                 with = `"N":10,"SEL":false` )
            t_pending = temp10 ).
    cl_abap_unit_assert=>assert_equals( exp = `["/T/0"]`
                                        act = act( `OK` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/T/0/SEL=true`
                                        act = pending( ) ).

  ENDMETHOD.

  METHOD pick_none.

    " an item argument with nothing ticked is refused; a single-select
    " dialog with nothing selected needs a row, and one that exists
    screen( xml   = dialog( multi = `true`
                            args  = `, ${$parameters>/selectedItem}.getCells()[0].getText()` )
            model = replace( val  = rows( )
                             sub  = `"N":10,"SEL":true`
                             with = `"N":10,"SEL":false` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `argument 0 of OK ($expr:${$parameters>/selectedItem}.getCells()[0].getText()) ` &&
                                              `reads the picked row and none is selected - pass row, or the value in args[0]`
                                        act = act( `OK` ) ).
    screen( xml   = dialog( multi = `false`
                            args  = `` )
            model = replace( val  = rows( )
                             sub  = `"N":10,"SEL":true`
                             with = `"N":10,"SEL":false` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `action a1 (OK) picks a row of table t1 (3 rows) - pass row (0-2)`
                                        act = act( `OK` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `table t1 has 3 row(s) - row 3 does not exist (rows are 0-based)`
                                        act = act( event = `OK`
                                                   row   = `3` ) ).

  ENDMETHOD.

  METHOD pick_unknown.

    " a marshalled control, an id, a cell that does not exist, a property the
    " template does not set: asked for in args
    DATA temp11 TYPE string_table.
    DATA temp12 LIKE temp11.
    DATA lv_case LIKE LINE OF temp12.
      DATA lv_arg TYPE string.
      DATA lv_describe TYPE string.
    CLEAR temp11.
    INSERT `${$parameters>/selectedItems}|$parameters:selectedItems` INTO TABLE temp11.
    INSERT `${$parameters>/selectedItem}.getId()|$expr:${$parameters>/selectedItem}.getId()` INTO TABLE temp11.
    INSERT `${$parameters>/selectedItem}.getCells()[5].getText()|$expr:${$parameters>/selectedItem}.getCells()[5].getText()` INTO TABLE temp11.
    INSERT `${$parameters>/selectedItem}.getHighlight()|$expr:${$parameters>/selectedItem}.getHighlight()` INTO TABLE temp11.

    temp12 = temp11.

    LOOP AT temp12 INTO lv_case.


      SPLIT lv_case AT `|` INTO lv_arg lv_describe.
      screen( xml   = dialog( multi = `false`
                              args  = |, { lv_arg }| )
              model = rows( ) ).
      cl_abap_unit_assert=>assert_equals( exp = |argument 0 of OK ({ lv_describe }) is computed in the browser - pass its value in args[0]|
                                          act = act( event = `OK`
                                                     row   = `0` ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD screen_before_row.

    " without row, the screen action of that name fires before a row action
    " of the same name that comes first in the view
    screen( xml   = `<Table items="{/T}"><columns><Column/></columns><items><ColumnListItem><cells>` &&
                    `<Button text="Del" press=".eB(['DELETE'], ${A})"/></cells></ColumnListItem></items></Table>` &&
                    `<Button text="Delete selected" press=".eB(['DELETE'])"/>`
            model = rows( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `[]`
                                        act = act( `DELETE` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `["a1"]`
                                        act = act( event = `DELETE`
                                                   row   = `1` ) ).

  ENDMETHOD.

  METHOD table_events.

    " listItem, rowIndex / rowContext and a row action item's row are filled
    " from row; a parameter outside them is asked for in args
    screen( xml   = `<Table items="{/T}" itemPress=".eB(['PRESS'], ${$parameters>/listItem}.getBindingContext().getProperty('B'), ` &&
                    `${$parameters>/listItem}.getCells()[0].getText())"><columns><Column/></columns><items><ColumnListItem type="Active">` &&
                    `<cells><Text text="{A}"/></cells></ColumnListItem></items></Table>` &&
                    `<t:Table rows="{/T}" rowSelectionChange=".eB(['SEL'], ${$parameters>/rowIndex}, ${$parameters>/rowContext}.getPath(), ` &&
                    `${$parameters>/rowContext/sPath})" cellClick=".eB(['CELL'], ${$parameters>/rowBindingContext}.getProperty('A'), ` &&
                    `${$parameters>/columnIndex})"><t:columns><t:Column><Label text="A"/><t:template><Text text="{A}"/></t:template>` &&
                    `</t:Column></t:columns><t:rowActionTemplate><t:RowAction><t:RowActionItem type="Navigation" ` &&
                    `press=".eB(['NAV'], ${$parameters>/row}.getBindingContext().getProperty('B'))"/></t:RowAction></t:rowActionTemplate></t:Table>`
            model = rows( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `action a1 (PRESS) is a row action of table t1 (3 rows) - pass row (0-2)`
                                        act = act( `PRESS` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `["b1","a1"]`
                                        act = act( event = `PRESS`
                                                   row   = `1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `[2,"/T/2","/T/2"]`
                                        act = act( event = `SEL`
                                                   row   = `2` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `argument 1 of CELL ($parameters:columnIndex) is computed in the browser - pass its value in args[1]`
                                        act = act( event = `CELL`
                                                   row   = `0` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `["b0"]`
                                        act = act( event = `NAV`
                                                   row   = `0` ) ).
    " a table row event selects nothing by itself
    cl_abap_unit_assert=>assert_initial( pending( ) ).

  ENDMETHOD.

  METHOD action_disabled.

    " the values disable the action - the browser cannot press it then, so
    " the act does not fire it either
    DATA lv_xml TYPE string.
    DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
    DATA temp13 TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.
    DATA temp14 LIKE LINE OF temp13.
        DATA lx TYPE REF TO z2ui5_cx_ui5_util_error.
    lv_xml = `<CheckBox selected="{/OPEN}"/><Button text="Delete" enabled="{/OPEN}" press=".eB(['DEL'])"/>`.
    screen( xml   = lv_xml
            model = `{"OPEN":true}` ).

    ls_action = mo_cut->find_action( event   = `DEL`
                                           has_row = abap_false ).
    cl_abap_unit_assert=>assert_true( ls_action-enabled ).

    CLEAR temp13.

    temp14-model_key = `MAIN`.
    temp14-path = `/OPEN`.
    temp14-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ).
    INSERT temp14 INTO TABLE temp13.
    screen( xml       = lv_xml
            model     = `{"OPEN":true}`
            t_pending = temp13 ).
    TRY.
        mo_cut->action_again( id      = ls_action-id
                              event   = `DEL`
                              refusal = `refused` ).
        cl_abap_unit_assert=>fail( `an action the values disabled was not refused` ).

      CATCH z2ui5_cx_ui5_util_error INTO lx.
        cl_abap_unit_assert=>assert_char_cp( exp = `action a1 (Delete) is disabled once the values are filled*`
                                             act = lx->get_text( ) ).
    ENDTRY.

  ENDMETHOD.

  METHOD action_hidden.

    " the action checked before the values: still there, it is fired ...
    DATA lv_xml TYPE string.
    DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
        DATA lx TYPE REF TO z2ui5_cx_ui5_util_error.
    DATA temp15 TYPE z2ui5_cl_agent_snapshot=>ty_t_pending.
    DATA temp16 LIKE LINE OF temp15.
    lv_xml = `<CheckBox selected="{/SHOW}"/><Button text="Go" visible="{/SHOW}" press=".eB(['GO'])"/>`.
    screen( xml   = lv_xml
            model = `{"SHOW":true}` ).

    ls_action = mo_cut->find_action( event   = `GO`
                                           has_row = abap_false ).
    TRY.
        cl_abap_unit_assert=>assert_equals( exp = `GO`
                                            act = mo_cut->action_again( id      = ls_action-id
                                                                        event   = `GO`
                                                                        refusal = `refused` )-event ).

      CATCH z2ui5_cx_ui5_util_error INTO lx.
        cl_abap_unit_assert=>fail( lx->get_text( ) ).
    ENDTRY.

    " ... hidden by the values, it is gone - refused, not fired as it was

    CLEAR temp15.

    temp16-model_key = `MAIN`.
    temp16-path = `/SHOW`.
    temp16-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ).
    INSERT temp16 INTO TABLE temp15.
    screen( xml       = lv_xml
            model     = `{"SHOW":true}`
            t_pending = temp15 ).
    TRY.
        mo_cut->action_again( id      = ls_action-id
                              event   = `GO`
                              refusal = `refused` ).
        cl_abap_unit_assert=>fail( `an action the values hid was not refused` ).
      CATCH z2ui5_cx_ui5_util_error INTO lx.
        cl_abap_unit_assert=>assert_equals( exp = `refused`
                                            act = lx->get_text( ) ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
