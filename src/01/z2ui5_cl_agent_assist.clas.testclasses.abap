"! The in-app copilot end to end, on the headless frontend simulator: the
"! agent demo app (z2ui5_cl_agent_demo, two lines of copilot opt-in) is
"! started, its copilot button pressed, the copilot popup asked - with a
"! language model double answering canned JSON. What the double was sent
"! is what a real model would have seen.
CLASS ltcl_copilot DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    CONSTANTS c_demo TYPE string VALUE `Z2UI5_CL_AGENT_DEMO`.
    CONSTANTS c_popup TYPE string VALUE `POPUP`.

    DATA mo_double TYPE REF TO z2ui5_cl_agent_llm_double.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_ag_set WITH EMPTY KEY.

    METHODS setup.
    METHODS teardown.

    METHODS answer_grounded FOR TESTING RAISING cx_static_check.
    METHODS allowed_runs_on_click FOR TESTING RAISING cx_static_check.
    METHODS forbidden_never_offered FOR TESTING RAISING cx_static_check.
    METHODS unknown_field_rejected FOR TESTING RAISING cx_static_check.
    METHODS protected_field_rejected FOR TESTING RAISING cx_static_check.
    METHODS confirm_needs_the_click FOR TESTING RAISING cx_static_check.
    METHODS act_off_answers_only FOR TESTING RAISING cx_static_check.
    METHODS switched_off FOR TESTING RAISING cx_static_check.
    METHODS agents_never_open_it FOR TESTING RAISING cx_static_check.

    METHODS setting
      IMPORTING
        item  TYPE string
        value TYPE string.

    "! The demo with the copilot open - NAME and IBAN typed before the press.
    METHODS open
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    METHODS ask
      IMPORTING
        sim      TYPE REF TO z2ui5_cl_frontend_simulator
        question TYPE string.

    CLASS-METHODS answer
      IMPORTING
        text          TYPE string
        wanted        TYPE abap_bool DEFAULT abap_false
        summary       TYPE string DEFAULT ``
        event         TYPE string DEFAULT ``
        values        TYPE string DEFAULT ``
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_copilot IMPLEMENTATION.

  METHOD setup.

    SELECT * FROM z2ui5_t_ag_set WHERE kind = 'LLM' INTO TABLE @mt_saved.
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    setting( item  = z2ui5_cl_agent_settings=>cs_llm-copilot
             value = `on` ).
    setting( item  = z2ui5_cl_agent_settings=>cs_llm-copilot_act
             value = `on` ).
    mo_double = NEW #( ).
    z2ui5_cl_agent_llm=>set_double( mo_double ).

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_double( ).
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD setting.

    z2ui5_cl_agent_settings=>set_llm( item  = item
                                      value = value ).

  ENDMETHOD.

  METHOD open.

    result = z2ui5_cl_frontend_simulator=>start( c_demo ).
    result->set_value( name  = `NAME`
                       value = `Carol` ).
    result->set_value( name  = `IBAN`
                       value = `DE02100100109307118603` ).
    result->click( z2ui5_cl_agent_copilot=>c_event ).

  ENDMETHOD.

  METHOD ask.

    sim->set_value( name  = `QUESTION`
                    value = question
                    layer = c_popup ).
    sim->click( event = `ASK`
                layer = c_popup ).

  ENDMETHOD.

  METHOD answer.

    result = |\{"answer":{ z2ui5_cl_agent_viewxml=>json_string( text ) },"found":true,| &&
             |"proposal":\{"wanted":{ COND #( WHEN wanted = abap_true THEN `true` ELSE `false` ) },| &&
             |"summary":{ z2ui5_cl_agent_viewxml=>json_string( summary ) },| &&
             |"event":{ z2ui5_cl_agent_viewxml=>json_string( event ) },"values":[{ values }]\}\}|.

  ENDMETHOD.

  METHOD answer_grounded.

    DATA(sim) = open( ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_app( )
                                        exp = `Z2UI5_CL_AGENT_COPILOT` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*Ask about this screen (Travel requests*` ).

    mo_double->add_answer( answer( `Alice and Bob have travel requests.` ) ).
    ask( sim      = sim
         question = `Who has a request?` ).

    " grounded: the snapshot of the screen as the user left it - the typed
    " name included, the IBAN masked, no forbidden action
    DATA(ls_request) = mo_double->mt_request[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = ls_request-purpose
                                        exp = `copilot` ).
    cl_abap_unit_assert=>assert_equals( act = ls_request-app
                                        exp = c_demo ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_request-system
                                         exp = `*does not contain what the user asks, say so plainly*` ).
    DATA(lv_user) = ls_request-t_message[ lines( ls_request-t_message ) ]-content.
    cl_abap_unit_assert=>assert_char_cp( act = lv_user
                                         exp = `*Travel requests - the example app*"snapshotVersion":1*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_user
                                         exp = `*"value":"Carol"*Alice*Bob*The question: Who has a request?` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_user
                                         exp = `*"path":"/IBAN"*"value":"***"*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_user
                                                    sub = `DE021001` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_user
                                                    sub = `DELETE_ALL` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_user
                                                    sub = z2ui5_cl_agent_copilot=>c_event )
                                        exp = -1 ).

    DATA(lv_model) = sim->get_model( c_popup ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_model
                                         exp = `*Who has a request?*Alice and Bob have travel requests.*` ).

    " the second question carries the first turn
    mo_double->add_answer( answer( `The screen does not show that.` ) ).
    ask( sim      = sim
         question = `When do they fly?` ).
    DATA(lt_message) = mo_double->mt_request[ 2 ]-t_message.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_message )
                                        exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = lt_message[ 1 ]-content
                                        exp = `Who has a request?` ).
    cl_abap_unit_assert=>assert_equals( act = lt_message[ 2 ]-role
                                        exp = `assistant` ).

    " closing without a step leaves the app as it was
    sim->click( event = `CLOSE`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_app( )
                                        exp = c_demo ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `NAME` )
                                        exp = `Carol` ).

  ENDMETHOD.

  METHOD allowed_runs_on_click.

    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `I can add a request for Dave.`
                                   wanted  = abap_true
                                   summary = `add a request for Dave`
                                   event   = `ADD`
                                   values  = `{"field":"/NAME","value":"Dave"}` ) ).
    ask( sim      = sim
         question = `Add a request for Dave` ).

    " offered - nothing ran yet
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( name  = `HAS_PROPOSAL`
                                                              layer = c_popup )
                                        exp = `true` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( name  = `PROPOSAL_LABEL`
                                                               layer = c_popup )
                                         exp = `Do it: *` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( name  = `PROPOSAL_TEXT`
                                                               layer = c_popup )
                                         exp = `Proposed: add a request for Dave - fill Name = "Dave" - then press *` ).

    " the click runs it through the app's main( )
    sim->click( event = `DO`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*Done: *The app says: Request 3 added*` ).
    sim->click( event = `CLOSE`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_app( )
                                        exp = c_demo ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `STATUS` )
                                        exp = `Request 3 added` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( )
                                         exp = `*"NAME":"Dave"*` ).

  ENDMETHOD.

  METHOD forbidden_never_offered.

    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `I delete them.`
                                   wanted  = abap_true
                                   summary = `delete all requests`
                                   event   = `DELETE_ALL` ) ).
    ask( sim      = sim
         question = `Delete everything` ).

    cl_abap_unit_assert=>assert_differs( act = sim->get_value( name  = `HAS_PROPOSAL`
                                                               layer = c_popup )
                                         exp = `true` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*not offered: the action * (DELETE_ALL) is forbidden for agents - the copilot never offers it*` ).
    sim->click( event = `CLOSE`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `STATUS` )
                                        exp = `` ).

  ENDMETHOD.

  METHOD unknown_field_rejected.

    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `Done.`
                                   wanted  = abap_true
                                   summary = `fill the budget`
                                   values  = `{"field":"BUDGET","value":"1000"}` ) ).
    ask( sim      = sim
         question = `Set the budget to 1000` ).

    cl_abap_unit_assert=>assert_differs( act = sim->get_value( name  = `HAS_PROPOSAL`
                                                               layer = c_popup )
                                         exp = `true` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*not offered: *BUDGET*` ).

  ENDMETHOD.

  METHOD protected_field_rejected.

    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `Done.`
                                   wanted  = abap_true
                                   summary = `change the IBAN`
                                   values  = `{"field":"/IBAN","value":"DE00"}` ) ).
    ask( sim      = sim
         question = `Change my IBAN` ).

    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*not offered: the field /IBAN is protected*` ).

    " by its name in another case - app_check( ) resolves that to the same field
    mo_double->add_answer( answer( text    = `Done.`
                                   wanted  = abap_true
                                   summary = `change the IBAN`
                                   values  = `{"field":"iban","value":"DE00"}` ) ).
    ask( sim      = sim
         question = `Change my IBAN` ).

    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*not offered: the field iban is protected*` ).

  ENDMETHOD.

  METHOD confirm_needs_the_click.

    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `Enter Erin, then submit.`
                                   wanted  = abap_true
                                   summary = `enter Erin and submit`
                                   event   = `SUBMIT`
                                   values  = `{"field":"/NAME","value":"Erin"}` ) ).
    ask( sim      = sim
         question = `Submit a request for Erin` ).

    cl_abap_unit_assert=>assert_equals( act = sim->get_value( name  = `PROPOSAL_LABEL`
                                                              layer = c_popup )
                                        exp = `Fill in` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( name  = `PROPOSAL_TEXT`
                                                               layer = c_popup )
                                         exp = `*you press yourself, it needs a person*` ).
    sim->click( event = `DO`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*Filled 1 field(s). Press *on the screen yourself*` ).

    " back on the screen: the name filled in, nothing submitted
    sim->click( event = `CLOSE`
                layer = c_popup ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_app( )
                                        exp = c_demo ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `NAME` )
                                        exp = `Erin` ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `STATUS` )
                                        exp = `` ).

  ENDMETHOD.

  METHOD act_off_answers_only.

    setting( item  = z2ui5_cl_agent_settings=>cs_llm-copilot_act
             value = `off` ).
    DATA(sim) = open( ).
    mo_double->add_answer( answer( text    = `Press Add.`
                                   wanted  = abap_true
                                   summary = `add`
                                   event   = `ADD` ) ).
    ask( sim      = sim
         question = `Add it` ).

    cl_abap_unit_assert=>assert_char_cp( act = mo_double->mt_request[ 1 ]-system
                                         exp = `*You cannot change the screen*` ).
    cl_abap_unit_assert=>assert_differs( act = sim->get_value( name  = `HAS_PROPOSAL`
                                                               layer = c_popup )
                                         exp = `true` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*may not act on this system*` ).

  ENDMETHOD.

  METHOD switched_off.

    setting( item  = z2ui5_cl_agent_settings=>cs_llm-copilot
             value = `off` ).
    DATA(sim) = open( ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_model( c_popup )
                                         exp = `*not available here: the in-app copilot is switched off*` ).
    cl_abap_unit_assert=>assert_differs( act = sim->get_value( name  = `READY`
                                                               layer = c_popup )
                                         exp = `true` ).
    cl_abap_unit_assert=>assert_initial( mo_double->mt_request ).

  ENDMETHOD.

  METHOD agents_never_open_it.

    cl_abap_unit_assert=>assert_equals(
        act = z2ui5_cl_agent_settings=>get_policy( app_start = c_demo
                                                   app       = c_demo
                                                   event     = z2ui5_cl_agent_copilot=>c_event )-policy
        exp = z2ui5_if_agent_app=>cs_policy-forbidden ).
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_settings=>check_app( `Z2UI5_CL_AGENT_COPILOT` ) ).

  ENDMETHOD.

ENDCLASS.
