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

ENDCLASS.
