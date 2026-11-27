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

    z2ui5_cl_agent_settings=>refresh( ).
    IF allowed = abap_true.
      INSERT VALUE #( kind  = z2ui5_cl_agent_settings=>cs_kind-app
                      app   = c_app
                      value = z2ui5_cl_agent_settings=>cs_app_rule-allow ) INTO TABLE z2ui5_cl_agent_settings=>gt_setting.
    ENDIF.
    z2ui5_cl_agent_settings=>gv_loaded = abap_true.

  ENDMETHOD.

  METHOD app_policy_any_case.

    " an app that writes its policies in upper case (a CHAR constant, a
    " domain value) means them all the same
    settings( abap_true ).
    INSERT VALUE #( app  = c_app
                    info = VALUE #( t_event        = VALUE #( ( event = `DELETE*` policy = `FORBIDDEN` ) )
                                    default_policy = ` Confirm ` ) ) INTO TABLE z2ui5_cl_agent_settings=>gt_info.

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

    " an operable app that navigates to the settings app: its events stay
    " out of an agent's reach, whatever the settings and the started app say
    settings( abap_true ).
    INSERT VALUE #( app  = c_app
                    info = VALUE #( default_policy = `allowed` ) ) INTO TABLE z2ui5_cl_agent_settings=>gt_info.

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

    " an operable app calls an app without opt-in (nav_app_call), or the
    " administrator removes the allow rule while a session runs: the app's
    " events are out of reach - not "allowed" by default
    settings( abap_false ).
    INSERT VALUE #( app  = c_app
                    info = VALUE #( default_policy = `allowed` ) ) INTO TABLE z2ui5_cl_agent_settings=>gt_info.

    DATA(ls_policy) = z2ui5_cl_agent_settings=>get_policy( app_start = `Z2UI5_CL_AGENT_DEMO`
                                                           app       = c_app
                                                           event     = `POST` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = ls_policy-policy ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*not enabled for agents*`
                                         act = ls_policy-source ).

    " allowed by an administrator: operable again
    settings( abap_true ).
    INSERT VALUE #( app  = c_app
                    info = VALUE #( default_policy = `allowed` ) ) INTO TABLE z2ui5_cl_agent_settings=>gt_info.
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-allowed
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = `Z2UI5_CL_AGENT_DEMO`
                                                                                   app       = c_app
                                                                                   event     = `POST` )-policy ).

  ENDMETHOD.

ENDCLASS.
