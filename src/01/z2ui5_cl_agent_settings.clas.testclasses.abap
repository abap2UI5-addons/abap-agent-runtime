CLASS ltcl_policy DEFINITION DEFERRED.
CLASS z2ui5_cl_agent_settings DEFINITION LOCAL FRIENDS ltcl_policy.

"! The policy of an event as an app states it - read from the buffer of
"! the apps' describe( ), filled here directly, so no app class is needed.
CLASS ltcl_policy DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    CONSTANTS c_app TYPE string VALUE `ZT_AGENT_POLICY_CASE`.

    METHODS teardown.

    METHODS app_policy_any_case FOR TESTING.

ENDCLASS.


CLASS ltcl_policy IMPLEMENTATION.

  METHOD teardown.

    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD app_policy_any_case.

    " an app that writes its policies in upper case (a CHAR constant, a
    " domain value) means them all the same
    z2ui5_cl_agent_settings=>refresh( ).
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

ENDCLASS.
