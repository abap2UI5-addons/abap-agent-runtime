CLASS ltcl_policy DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_settings DEFINITION LOCAL FRIENDS ltcl_policy.

"! The policy of an event as an app states it - read from the buffer of
"! the apps' describe( ), filled here directly, so no app class is needed.
CLASS ltcl_policy DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    CONSTANTS c_app TYPE string VALUE `ZT_AGENT_POLICY_CASE`.

    METHODS teardown.

    METHODS app_policy_any_case FOR TESTING.
    METHODS own_app_navigated   FOR TESTING.

ENDCLASS.


CLASS ltcl_policy IMPLEMENTATION.

  METHOD teardown.

    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD app_policy_any_case.
    DATA temp1 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.
    DATA temp2 TYPE z2ui5_if_agent_app=>ty_t_event.
    DATA temp3 LIKE LINE OF temp2.

    " an app that writes its policies in upper case (a CHAR constant, a
    " domain value) means them all the same
    z2ui5_cl_agent_settings=>refresh( ).

    CLEAR temp1.
    temp1-app = c_app.
    CLEAR temp1-info.

    CLEAR temp2.

    temp3-event = `DELETE*`.
    temp3-policy = `FORBIDDEN`.
    INSERT temp3 INTO TABLE temp2.
    temp1-info-t_event = temp2.
    temp1-info-default_policy = ` Confirm `.
    INSERT temp1 INTO TABLE z2ui5_cl_agent_settings=>gt_info.

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
    DATA temp2 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.

    " an operable app that navigates to the settings app: its events stay
    " out of an agent's reach, whatever the settings and the started app say
    z2ui5_cl_agent_settings=>refresh( ).

    CLEAR temp2.
    temp2-app = c_app.
    CLEAR temp2-info.
    temp2-info-default_policy = `allowed`.
    INSERT temp2 INTO TABLE z2ui5_cl_agent_settings=>gt_info.

    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                   app       = `Z2UI5_CL_AGENT_APP_ADMIN`
                                                                                   event     = `RULE_ADD` )-policy ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_if_agent_app=>cs_policy-forbidden
                                        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_app
                                                                                   app       = `z2ui5_cl_agent_app_audit`
                                                                                   event     = `SEARCH` )-policy ).

  ENDMETHOD.

ENDCLASS.
