CLASS ltcl_policy DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_settings DEFINITION LOCAL FRIENDS ltcl_policy.

"! The policy of an event as an app states it - read from the buffer of
"! the apps' describe( ) and the buffered settings, filled here directly,
"! so the app needs no opt-in of its own and nothing is written.
CLASS ltcl_policy DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    "! an abap2UI5 app of the framework without z2ui5_if_agent_app
    CONSTANTS c_app TYPE string VALUE `Z2UI5_CL_UI5_APP_HI_WORLD`.

    METHODS teardown.

    "! the buffered settings: an APP allow rule for c_app, or none
    METHODS settings
      IMPORTING
        allowed TYPE abap_bool.

    METHODS app_policy_any_case   FOR TESTING.
    METHODS own_app_navigated     FOR TESTING.
    METHODS not_opted_in_navigated FOR TESTING.

ENDCLASS.


CLASS ltcl_policy IMPLEMENTATION.

  METHOD teardown.

    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD settings.
      DATA temp1 TYPE z2ui5_t_17.

    z2ui5_cl_agent_settings=>refresh( ).
    IF allowed = abap_true.

      CLEAR temp1.
      temp1-kind = z2ui5_cl_agent_settings=>cs_kind-app.
      temp1-app = c_app.
      temp1-value = z2ui5_cl_agent_settings=>cs_app_rule-allow.
      INSERT temp1 INTO TABLE z2ui5_cl_agent_settings=>gt_setting.
    ENDIF.
    z2ui5_cl_agent_settings=>gv_loaded = abap_true.

  ENDMETHOD.

  METHOD app_policy_any_case.
    DATA temp2 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.
    DATA temp1 TYPE z2ui5_if_agent_app=>ty_t_event.
    DATA temp3 LIKE LINE OF temp1.

    " an app that writes its policies in upper case (a CHAR constant, a
    " domain value) means them all the same
    settings( abap_true ).

    CLEAR temp2.
    temp2-app = c_app.
    CLEAR temp2-info.

    CLEAR temp1.

    temp3-event = `DELETE*`.
    temp3-policy = `FORBIDDEN`.
    INSERT temp3 INTO TABLE temp1.
    temp2-info-t_event = temp1.
    temp2-info-default_policy = ` Confirm `.
    INSERT temp2 INTO TABLE z2ui5_cl_agent_settings=>gt_info.

    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                   app       = c_app
                                                                                   event     = `DELETE_ALL` )-policy ).
    cl_abap_unit_assert=>assert_differs( exp = z2ui5_if_agent_app=>cs_policy-allowed
                                         act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                    app       = c_app
                                                                                    event     = `SAVE` )-policy ).

  ENDMETHOD.

  METHOD own_app_navigated.
    DATA temp3 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.

    " an operable app that navigates to the settings app: its events stay
    " out of an agent's reach, whatever the settings and the started app say
    settings( abap_true ).

    CLEAR temp3.
    temp3-app = c_app.
    CLEAR temp3-info.
    temp3-info-default_policy = `allowed`.
    INSERT temp3 INTO TABLE z2ui5_cl_agent_settings=>gt_info.

    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                   app       = `Z2UI5_CL_AGENT_APP_ADMIN`
                                                                                   event     = `RULE_ADD` )-policy ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                   app       = `z2ui5_cl_agent_app_audit`
                                                                                   event     = `SEARCH` )-policy ).

  ENDMETHOD.

  METHOD not_opted_in_navigated.
    DATA temp4 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.
    DATA ls_policy TYPE z2ui5_cl_agent_settings=>ty_s_policy.
    DATA temp5 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.

    " an operable app calls an app without opt-in (nav_app_call), or the
    " administrator removes the allow rule while a session runs: the app's
    " events are out of reach - not "allowed" by default
    settings( abap_false ).

    CLEAR temp4.
    temp4-app = c_app.
    CLEAR temp4-info.
    temp4-info-default_policy = `allowed`.
    INSERT temp4 INTO TABLE z2ui5_cl_agent_settings=>gt_info.


    ls_policy = z2ui5_cl_agent_settings=>get_policy( app_start = `Z2UI5_CL_AGENT_DEMO`
                                                           app       = c_app
                                                           event     = `POST` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = ls_policy-policy ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*not enabled for agents*`
                                         act = ls_policy-source ).

    " allowed by an administrator: operable again
    settings( abap_true ).

    CLEAR temp5.
    temp5-app = c_app.
    CLEAR temp5-info.
    temp5-info-default_policy = `allowed`.
    INSERT temp5 INTO TABLE z2ui5_cl_agent_settings=>gt_info.
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-allowed
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = `Z2UI5_CL_AGENT_DEMO`
                                                                                   app       = c_app
                                                                                   event     = `POST` )-policy ).

  ENDMETHOD.

ENDCLASS.


"! The test seam the other test classes run on: save( ), remove( ),
"! set_enabled( ) and admin_add( ) change the buffer only - the settings
"! of the system the tests run in stay as they are.
CLASS ltcl_test_buffer DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    METHODS teardown.

    METHODS table_untouched FOR TESTING.

ENDCLASS.


CLASS ltcl_test_buffer IMPLEMENTATION.

  METHOD teardown.

    z2ui5_cl_agent_settings=>end_test_buffer( ).

  ENDMETHOD.

  METHOD table_untouched.

    DATA lt_before TYPE STANDARD TABLE OF z2ui5_t_17 WITH DEFAULT KEY.
    DATA temp7 TYPE z2ui5_cl_agent_settings=>ty_t_setting.
    DATA temp8 LIKE LINE OF temp7.
    DATA lt_after TYPE STANDARD TABLE OF z2ui5_t_17 WITH DEFAULT KEY.
    SELECT * FROM z2ui5_t_17 INTO TABLE lt_before ORDER BY PRIMARY KEY.


    CLEAR temp7.

    temp8-kind = z2ui5_cl_agent_settings=>cs_kind-admin.
    temp8-app = `UNIT_ADMIN`.
    temp8-value = `X`.
    INSERT temp8 INTO TABLE temp7.
    z2ui5_cl_agent_settings=>set_test_buffer( temp7 ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_admin( `unit_admin` ) ).
    z2ui5_cl_agent_settings=>set_enabled( abap_true ).
    z2ui5_cl_agent_settings=>admin_add( `unit_other` ).
    z2ui5_cl_agent_settings=>remove( kind = z2ui5_cl_agent_settings=>cs_kind-admin
                                     app  = `unit_admin` ).
    z2ui5_cl_agent_settings=>refresh( ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_enabled( ) ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_admin( `UNIT_OTHER` ) ).
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_settings=>check_admin( `UNIT_ADMIN` ) ).


    SELECT * FROM z2ui5_t_17 INTO TABLE lt_after ORDER BY PRIMARY KEY.
    cl_abap_unit_assert=>assert_equals( exp = lt_before
                                        act = lt_after ).

  ENDMETHOD.

ENDCLASS.
