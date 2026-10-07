CLASS ltcl_args DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_session DEFINITION LOCAL FRIENDS ltcl_args.

"! In-memory draft store, installed through the core's store seam
"! (z2ui5_cl_ui5_srv_draft=&gt;set_instance) - the drafts of the sessions
"! below never reach Z2UI5_T_01.
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
    METHODS row_selection       FOR TESTING.
    METHODS typed_values        FOR TESTING.
    METHODS structure_table     FOR TESTING.
    METHODS disabled            FOR TESTING.
    METHODS audit_masks         FOR TESTING.
    METHODS audit_masks_act     FOR TESTING.
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

    mo_store = NEW #( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( mo_store ).
    mv_start = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).

    SELECT * FROM z2ui5_t_ag_set INTO TABLE @mt_setting.
    DELETE FROM z2ui5_t_ag_set.
    z2ui5_cl_agent_settings=>set_enabled( abap_true ).
    COMMIT WORK.
    mo_session = NEW #( c_client ).

  ENDMETHOD.

  METHOD teardown.

    DATA li_default TYPE REF TO z2ui5_if_ui5_draft_store.

    DELETE FROM z2ui5_t_ag_ses WHERE uname = @sy-uname AND created_at >= @mv_start.
    DELETE FROM z2ui5_t_ag_log WHERE uname = @sy-uname AND mcp_client = @c_client AND timestampl >= @mv_start.
    DELETE FROM z2ui5_t_ag_set.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_setting.
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

    DATA(lv_count) = lines( io_snap->members( `/actions` ) ).
    DO lv_count TIMES.
      IF io_snap->get_string( |/actions/{ sy-index }/event| ) = event.
        result = io_snap->get_string( |/actions/{ sy-index }/id| ).
        RETURN.
      ENDIF.
    ENDDO.
    cl_abap_unit_assert=>fail( |no action { event }| ).

  ENDMETHOD.

  METHOD start_snapshot.

    DATA(ls_result) = start( ).
    DATA(lo_snap) = ok( ls_result ).
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
    DATA(lv_count) = lines( lo_snap->members( `/actions` ) ).
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
    DATA(lo_two) = ok( mo_session->app_describe( session  = ls_result-session
                                                 max_rows = `1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true
                                        act = lo_two->get_boolean( `/tables/1/truncated` ) ).
    " beyond any integer: clamped to the limit like any number above it
    DATA(lo_many) = ok( mo_session->app_describe( session  = ls_result-session
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

    DATA(ls_start) = start( ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
                                        values  = `{"NAME":"Carol","/DAYS":5,"f2":"ROM","HOTEL":true}`
                                        event   = `ADD` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_act ).
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
    DATA(lv_messages) = ls_act-text.
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Request 3 added","source":"toast"*`
                                         act = lv_messages ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"source":"strip"*`
                                         act = lv_messages ).
    " the field was cleared by the app
    cl_abap_unit_assert=>assert_initial( lo_snap->get_string( `/fields/1/value` ) ).

  ENDMETHOD.

  METHOD earlier_session.

    DATA(ls_start) = start( ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
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
    DATA(ls_start) = start( ).
    refused( is_result = mo_session->app_describe( |{ ls_start-session }X| )
             pattern   = |*unknown session '{ ls_start-session }X'*| ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
                                        values  = `{"NAME":"Eve"}`
                                        event   = `ADD` ).
    COMMIT WORK.
    ok( ls_act ).
    refused( is_result = mo_session->app_describe( |{ ls_start-session }X| )
             pattern   = `*unknown session*` ).
    ok( mo_session->app_describe( ls_act-session ) ).

  ENDMETHOD.

  METHOD validation.

    DATA(ls_start) = start( ).
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

    DATA(ls_start) = start( ).
    DATA(ls_submit) = mo_session->app_act( session = ls_start-session
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

    DATA(ls_start) = start( ).
    DATA(ls_typed) = mo_session->app_act( session = ls_start-session
                                          values  = `{"NAME":"Dave"}` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_typed ).
    " typing does not roundtrip: same session, the value pending
    cl_abap_unit_assert=>assert_equals( exp = ls_start-session
                                        act = ls_typed-session ).
    cl_abap_unit_assert=>assert_equals( exp = `Dave`
                                        act = lo_snap->get_string( `/fields/1/value` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/NAME`
                                        act = lo_snap->get_string( `/pending/1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = ls_typed-text
                                        act = mo_session->app_describe( ls_start-session )-text ).

    DATA(ls_add) = mo_session->app_act( session = ls_start-session
                                        event   = `ADD` ).
    COMMIT WORK.
    lo_snap = ok( ls_add ).
    cl_abap_unit_assert=>assert_equals( exp = `Dave`
                                        act = lo_snap->get_string( `/tables/1/rows/3/NAME` ) ).
    cl_abap_unit_assert=>assert_false( lo_snap->exists( `/pending` ) ).

  ENDMETHOD.

  METHOD popup_flow.

    DATA(ls_start) = start( ).
    DATA(ls_open) = mo_session->app_act( session = ls_start-session
                                         event   = `POPUP_OPEN` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_open ).
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

    " closed in the browser: no roundtrip, the draft stays
    DATA(ls_close) = mo_session->app_act( session = ls_open-session
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
    DATA(ls_ok) = mo_session->app_act( session = ls_open-session
                                       values  = `{"/NOTE":"back on Friday"}`
                                       event   = `POPUP_OK` ).
    COMMIT WORK.
    lo_snap = ok( ls_ok ).
    cl_abap_unit_assert=>assert_equals( exp = `main`
                                        act = lo_snap->get_string( `/layer` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Note: back on Friday","source":"strip"*`
                                         act = ls_ok-text ).

  ENDMETHOD.

  METHOD row_action.

    DATA(ls_start) = start( ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `DETAIL` )
             pattern   = `*is a row action of table t1 (2 rows) - pass row (0-1)*` ).
    refused( is_result = mo_session->app_act( session = ls_start-session
                                              event   = `DETAIL`
                                              row     = `7` )
             pattern   = `*table t1 has 2 row(s) - row 7 does not exist*` ).
    DATA(ls_detail) = mo_session->app_act( session = ls_start-session
                                           event   = `DETAIL`
                                           row     = `1` ).
    COMMIT WORK.
    ok( ls_detail ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"messages":[{"type":"info","text":"Request 2","source":"box"}]*`
                                         act = ls_detail-text ).

  ENDMETHOD.

  METHOD row_selection.

    " selecting a row is setting its selection field
    DATA(ls_start) = start( ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
                                        values  = `{"/T_REQUEST/1/SELKZ":true,"NAME":"Fay"}`
                                        event   = `ADD` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_act ).
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
    DATA(ls_start) = start( ).
    DATA(ls_plan) = mo_session->app_act( session = ls_start-session
                                         values  = `{"HOTEL":true,"TAGS":["FAIR","MEET"]}`
                                         event   = `PLAN` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_plan ).
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

    DATA(ls_none) = mo_session->app_act( session = ls_plan-session
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
    DATA(ls_start) = start( ).
    DATA(ls_plan) = mo_session->app_act( session = ls_start-session
                                         values  = `{"/TRIP/PURPOSE":"Fair","t2/1/NIGHTS":4}`
                                         event   = `PLAN` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_plan ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"text":"Plan: Fair, 2 stop(s), 5 night(s), tags none, hotel no","source":"strip"*`
                                         act = ls_plan-text ).
    cl_abap_unit_assert=>assert_equals( exp = `/TRIP/T_STOP`
                                        act = lo_snap->get_string( `/tables/2/path` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4
                                        act = lo_snap->get_integer( `/tables/2/rows/2/NIGHTS` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Lyon`
                                        act = lo_snap->get_string( `/tables/2/rows/1/CITY` ) ).

    " pending first, sent with the next event - the same delta
    DATA(ls_typed) = mo_session->app_act( session = ls_plan-session
                                          values  = `{"t2/0/NIGHTS":3}` ).
    COMMIT WORK.
    ok( ls_typed ).
    DATA(ls_sent) = mo_session->app_act( session = ls_typed-session
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

    DATA(ls_result) = mo_session->app_start( app    = c_app
                                             values = `{"IBAN":"DE02100100109307118603","NAME":"Gus"}` ).
    COMMIT WORK.
    ok( ls_result ).
    SELECT SINGLE args FROM z2ui5_t_ag_log
      WHERE uname = @sy-uname AND session_id = @ls_result-session AND operation = 'app_start'
      INTO @DATA(lv_args).
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
    DATA(ls_start) = start( ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
                                        values  = `{"IBAN":"DE02100100109307118603"}`
                                        event   = `POPUP_OPEN` ).
    COMMIT WORK.
    ok( ls_act ).
    SELECT SINGLE args FROM z2ui5_t_ag_log
      WHERE uname = @sy-uname AND session_id = @ls_act-session AND operation = 'app_act'
      INTO @DATA(lv_args).
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"IBAN":"***"*`
                                         act = lv_args ).
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = lv_args
                                                    sub = `DE02100100109307118603` ) ).

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
    DATA(lv_emoji) = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( CONV xstring( `F09F9880` ) ).
    DATA(lv_high) = substring( val = lv_emoji
                               len = 1 ).

    " the refusal quotes the value cut to 80 characters - right in the pair
    DATA(ls_start) = start( ).
    DATA(ls_act) = mo_session->app_act( session = ls_start-session
                                        values  = |\{"NAME":\{"k":"{ repeat( val = `a`
                                                                               occ = 73 ) }{ lv_emoji }"\}\}| ).
    refused( is_result = ls_act
             pattern   = `*takes a single value, not {"k":"aaa*` ).
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = ls_act-text
                                                    sub = lv_high ) ).

    " the audit log cuts its arguments to c_max_args characters - in the pair
    z2ui5_cl_agent_audit=>log( VALUE #( session   = `CUT_SURROGATE_PAIR`
                                        operation = `app_list`
                                        args      = |{ repeat( val = `a`
                                                               occ = z2ui5_cl_agent_audit=>c_max_args - 4 ) }{ lv_emoji }tail|
                                        outcome   = z2ui5_cl_agent_audit=>cs_outcome-ok
                                        client    = c_client ) ).
    COMMIT WORK.
    SELECT SINGLE args FROM z2ui5_t_ag_log
      WHERE uname = @sy-uname AND session_id = 'CUT_SURROGATE_PAIR' AND timestampl >= @mv_start
      INTO @lv_args.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = |{ repeat( val = `a`
                                                         occ = z2ui5_cl_agent_audit=>c_max_args - 4 ) }...|
                                        act = lv_args ).

  ENDMETHOD.

  METHOD admin_key_not_kept.

    " a key typed into the settings app and sent with another event than
    " Save (here by a user who may not change anything) is not kept in the
    " app's draft, nor sent back to the browser
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `LLM_KEY`
                       value = `sk-unit-typed-key` ).
    lo_sim->click( `LLM_TEST` ).
    LOOP AT mo_store->mt_db INTO DATA(ls_db).
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

    " abap2UI5 rolls back what main( ) leaves open: a change an
    " administrator saves in the settings app - and its audit entry - is
    " committed by the app itself
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `URL`
                       value = `/sap/bc/unit_handover` ).
    lo_sim->click( `URL_SAVE` ).
    SELECT SINGLE value FROM z2ui5_t_ag_set WHERE kind = 'URL' INTO @DATA(lv_url).
    cl_abap_unit_assert=>assert_equals( exp = `/sap/bc/unit_handover`
                                        act = lv_url ).
    SELECT COUNT(*) FROM z2ui5_t_ag_log
      WHERE uname = @sy-uname AND operation = 'settings' AND timestampl >= @mv_start INTO @lv_count.
    DELETE FROM z2ui5_t_ag_log WHERE uname = @sy-uname AND operation = 'settings' AND timestampl >= @mv_start.
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lv_count ).

  ENDMETHOD.

  METHOD admin_rule_fits.

    DATA lv_count TYPE i.

    " a rule longer than the settings table holds is refused, not cut: a
    " SENSITIVE pattern cut to 60 characters masks nothing
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_AGENT_APP_ADMIN` ).
    lo_sim->set_value( name  = `NEW_KIND`
                       value = `SENSITIVE` ).
    lo_sim->set_value( name  = `NEW_APP`
                       value = `*` ).
    lo_sim->set_value( name  = `NEW_ITEM`
                       value = `/MS_ORDER/S_PAYMENT/T_ACCOUNT/*/INTERNATIONAL_BANK_ACCOUNT_NUMBER` ).
    lo_sim->click( `RULE_ADD` ).
    SELECT COUNT(*) FROM z2ui5_t_ag_set WHERE kind = 'SENSITIVE' INTO @lv_count.
    DELETE FROM z2ui5_t_ag_log WHERE uname = @sy-uname AND operation = 'settings' AND timestampl >= @mv_start.
    COMMIT WORK.
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = lv_count ).
    cl_abap_unit_assert=>assert_char_cp( exp = `The rule is too long: 65 characters*at most 60*`
                                         act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD audit_admin_revoked.

    " the audit log app shows everybody's calls only while the user is an
    " agent administrator - not as long as its draft remembers that he was
    z2ui5_cl_agent_settings=>admin_add( sy-uname ).
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_AGENT_APP_AUDIT` ).
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
    DATA(ls_start) = start( ).
    DATA(ls_help) = mo_session->app_act( session = ls_start-session
                                         event   = `DEST_HELP` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_help ).
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
    DATA(ls_typed) = mo_session->app_act( session = ls_help-session
                                          values  = `{"t1/0/SELKZ":true}` ).
    COMMIT WORK.
    ok( ls_typed ).
    DATA(ls_pick) = mo_session->app_act( session = ls_typed-session
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
    DATA(ls_start) = start( ).
    DATA(ls_help) = mo_session->app_act( session = ls_start-session
                                         event   = `TAGS_HELP` ).
    COMMIT WORK.
    DATA(lo_snap) = ok( ls_help ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.TableSelectDialog`
                                        act = lo_snap->get_string( `/tables/1/control` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Multi`
                                        act = lo_snap->get_string( `/tables/1/selectionMode` ) ).
    DATA(ls_pick) = mo_session->app_act( session = ls_help-session
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
    DATA(ls_none) = mo_session->app_act( session = ls_help-session
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
    DATA(ls_start) = start( ).
    DATA(ls_help) = mo_session->app_act( session = ls_start-session
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

    mv_xml = |<mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:t="sap.ui.table"><Page title="T">{ xml }</Page></mvc:View>|.
    mv_model = model.
    mo_cut = NEW #( `ABAP Unit` ).
    mo_cut->mt_pending = t_pending.
    mo_cut->mo_snap = z2ui5_cl_agent_snapshot=>create( VALUE #( session   = `D1`
                                                                 app       = `Z_T`
                                                                 max_rows  = 20
                                                                 t_pending = t_pending
                                                                 t_layer   = VALUE #( ( layer = `MAIN`
                                                                                        xml   = mv_xml
                                                                                        model = mv_model ) ) ) ).

  ENDMETHOD.

  METHOD act.

    DATA lt_part TYPE string_table.
    DATA lt_picked TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    TRY.
        DATA(ls_action) = mo_cut->find_action( event   = event
                                               has_row = xsdbool( row IS NOT INITIAL ) ).
        IF ls_action-pick = abap_true.
          lt_picked = mo_cut->apply_pick( is_action = ls_action
                                          row_raw   = row ).
          mo_cut->mo_snap = z2ui5_cl_agent_snapshot=>create( VALUE #( session   = `D1`
                                                                       app       = `Z_T`
                                                                       max_rows  = 20
                                                                       t_pending = mo_cut->mt_pending
                                                                       t_layer   = VALUE #( ( layer = `MAIN`
                                                                                              xml   = mv_xml
                                                                                              model = mv_model ) ) ) ).
        ENDIF.
        LOOP AT mo_cut->event_args( is_action = ls_action
                                    t_given   = VALUE #( )
                                    row_raw   = row
                                    t_picked  = lt_picked ) INTO DATA(ls_val).
          INSERT z2ui5_cl_agent_viewxml=>val_to_json( ls_val ) INTO TABLE lt_part.
        ENDLOOP.
        result = |[{ concat_lines_of( table = lt_part
                                      sep   = `,` ) }]|.
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        result = lx->get_text( ).
    ENDTRY.

  ENDMETHOD.

  METHOD pending.

    DATA lt_part TYPE string_table.

    LOOP AT mo_cut->mt_pending INTO DATA(ls_pending).
      INSERT |{ ls_pending-path }={ z2ui5_cl_agent_viewxml=>val_to_json( ls_pending-val ) }| INTO TABLE lt_part.
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
    screen( xml       = dialog( multi = `true`
                                args  = `, ${$parameters>/selectedContexts/0/sPath}` )
            model     = replace( val  = rows( )
                                 sub  = `"N":10,"SEL":true`
                                 with = `"N":10,"SEL":false` )
            t_pending = VALUE #( ( model_key = `MAIN`
                                   path      = `/T/0/SEL`
                                   val       = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ) ) ) ).
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
    LOOP AT VALUE string_table( ( `${$parameters>/selectedItems}|$parameters:selectedItems` )
                                ( `${$parameters>/selectedItem}.getId()|$expr:${$parameters>/selectedItem}.getId()` )
                                ( `${$parameters>/selectedItem}.getCells()[5].getText()|$expr:${$parameters>/selectedItem}.getCells()[5].getText()` )
                                ( `${$parameters>/selectedItem}.getHighlight()|$expr:${$parameters>/selectedItem}.getHighlight()` ) ) INTO DATA(lv_case).
      SPLIT lv_case AT `|` INTO DATA(lv_arg) DATA(lv_describe).
      screen( xml   = dialog( multi = `false`
                              args  = |, { lv_arg }| )
              model = rows( ) ).
      cl_abap_unit_assert=>assert_equals( exp = |argument 0 of OK ({ lv_describe }) is computed in the browser - pass its value in args[0]|
                                          act = act( event = `OK`
                                                     row   = `0` ) ).
    ENDLOOP.

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
    DATA(lv_xml) = `<CheckBox selected="{/OPEN}"/><Button text="Delete" enabled="{/OPEN}" press=".eB(['DEL'])"/>`.
    screen( xml   = lv_xml
            model = `{"OPEN":true}` ).
    DATA(ls_action) = mo_cut->find_action( event   = `DEL`
                                           has_row = abap_false ).
    cl_abap_unit_assert=>assert_true( ls_action-enabled ).
    screen( xml       = lv_xml
            model     = `{"OPEN":true}`
            t_pending = VALUE #( ( model_key = `MAIN`
                                   path      = `/OPEN`
                                   val       = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ) ) ) ).
    TRY.
        mo_cut->action_again( id      = ls_action-id
                              event   = `DEL`
                              refusal = `refused` ).
        cl_abap_unit_assert=>fail( `an action the values disabled was not refused` ).
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( exp = `action a1 (Delete) is disabled once the values are filled*`
                                             act = lx->get_text( ) ).
    ENDTRY.

  ENDMETHOD.

  METHOD action_hidden.

    " the action checked before the values: still there, it is fired ...
    DATA(lv_xml) = `<CheckBox selected="{/SHOW}"/><Button text="Go" visible="{/SHOW}" press=".eB(['GO'])"/>`.
    screen( xml   = lv_xml
            model = `{"SHOW":true}` ).
    DATA(ls_action) = mo_cut->find_action( event   = `GO`
                                           has_row = abap_false ).
    TRY.
        cl_abap_unit_assert=>assert_equals( exp = `GO`
                                            act = mo_cut->action_again( id      = ls_action-id
                                                                        event   = `GO`
                                                                        refusal = `refused` )-event ).
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        cl_abap_unit_assert=>fail( lx->get_text( ) ).
    ENDTRY.

    " ... hidden by the values, it is gone - refused, not fired as it was
    screen( xml       = lv_xml
            model     = `{"SHOW":true}`
            t_pending = VALUE #( ( model_key = `MAIN`
                                   path      = `/SHOW`
                                   val       = z2ui5_cl_agent_viewxml=>val_boolean( abap_false ) ) ) ).
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
