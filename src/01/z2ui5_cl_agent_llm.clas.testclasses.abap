"! The wrapper around every language model call: settings applied, stop
"! reasons refused, structured answers parsed, every call audited - the
"! prompt only when the setting says so. With the double, no real model.
CLASS ltcl_llm DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    DATA mo_double TYPE REF TO z2ui5_cl_agent_llm_double.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_ag_set WITH EMPTY KEY.
    "! an app name of this test only - its audit entries are its own
    DATA mv_app TYPE string.

    METHODS setup.
    METHODS teardown.

    METHODS defaults_and_json FOR TESTING RAISING cx_static_check.
    METHODS refusal_refused FOR TESTING RAISING cx_static_check.
    METHODS max_tokens_refused FOR TESTING RAISING cx_static_check.
    METHODS not_the_json FOR TESTING RAISING cx_static_check.
    METHODS audit_without_prompt FOR TESTING RAISING cx_static_check.
    METHODS audit_with_prompt FOR TESTING RAISING cx_static_check.
    METHODS not_configured FOR TESTING RAISING cx_static_check.
    METHODS custom_provider FOR TESTING RAISING cx_static_check.
    METHODS key_never_shown FOR TESTING RAISING cx_static_check.

    METHODS last_log
      RETURNING
        VALUE(result) TYPE z2ui5_t_ag_log.

    METHODS request
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_llm=>ty_s_request.

ENDCLASS.


CLASS ltcl_llm IMPLEMENTATION.

  METHOD setup.

    SELECT * FROM z2ui5_t_ag_set WHERE kind = 'LLM' INTO TABLE @mt_saved.
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    mo_double = NEW #( ).
    z2ui5_cl_agent_llm=>set_double( mo_double ).
    mv_app = |ZT{ substring( val = z2ui5_cl_ui5_util_context=>uuid_get_c32( )
                             len = 28 ) }|.

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_double( ).
    z2ui5_cl_agent_llm=>set_http( ).
    DELETE FROM z2ui5_t_ag_log WHERE app = @mv_app.
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD request.

    result = VALUE #( purpose   = `test`
                      app       = mv_app
                      system    = `You answer in JSON.`
                      schema    = `{"type":"object","additionalProperties":false,"required":["a"],"properties":{"a":{"type":"string"}}}`
                      t_message = VALUE #( ( role = `user` content = `the secret question` ) ) ).

  ENDMETHOD.

  METHOD last_log.

    DATA lv_app TYPE z2ui5_t_ag_log-app.

    lv_app = mv_app.
    SELECT * FROM z2ui5_t_ag_log WHERE operation = 'llm' AND app = @lv_app
      INTO TABLE @DATA(lt_log).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_log )
                                        exp = 1
                                        msg = `one call, one audit entry` ).
    READ TABLE lt_log INTO result INDEX 1.

  ENDMETHOD.

  METHOD defaults_and_json.

    mo_double->add_answer( `{"a":"b"}` ).
    DATA(ls_answer) = z2ui5_cl_agent_llm=>create( )->chat( request( ) ).

    cl_abap_unit_assert=>assert_equals( act = ls_answer-json->get_string( `/a` )
                                        exp = `b` ).
    " the settings' defaults: effort low, 16000 tokens
    cl_abap_unit_assert=>assert_equals( act = mo_double->mt_request[ 1 ]-effort
                                        exp = `low` ).
    cl_abap_unit_assert=>assert_equals( act = mo_double->mt_request[ 1 ]-max_tokens
                                        exp = 16000 ).

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-effort
                                      value = `high` ).
    mo_double->add_answer( `{"a":"c"}` ).
    z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_double->mt_request[ 2 ]-effort
                                        exp = `high` ).

  ENDMETHOD.

  METHOD refusal_refused.

    mo_double->add_answer( text        = `{"a":"half`
                           stop_reason = z2ui5_if_agent_llm=>cs_stop-refusal ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a refusal must raise` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-refusal ).
        cl_abap_unit_assert=>assert_false( lx->retryable ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = last_log( )-outcome
                                        exp = `error` ).

  ENDMETHOD.

  METHOD max_tokens_refused.

    mo_double->add_answer( text        = `{"a":"cut`
                           stop_reason = z2ui5_if_agent_llm=>cs_stop-max_tokens ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `max_tokens must raise` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-max_tokens ).
    ENDTRY.

  ENDMETHOD.

  METHOD not_the_json.

    mo_double->add_answer( `Sure! Here is your view:` ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `text instead of JSON must raise` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-response ).
    ENDTRY.

  ENDMETHOD.

  METHOD audit_without_prompt.

    mo_double->add_answer( `{"a":"the secret answer"}` ).
    z2ui5_cl_agent_llm=>create( )->chat( request( ) ).

    DATA(ls_log) = last_log( ).
    cl_abap_unit_assert=>assert_equals( act = ls_log-uname
                                        exp = sy-uname ).
    cl_abap_unit_assert=>assert_equals( act = ls_log-app
                                        exp = mv_app ).
    cl_abap_unit_assert=>assert_equals( act = ls_log-event
                                        exp = `test` ).
    cl_abap_unit_assert=>assert_equals( act = ls_log-outcome
                                        exp = `ok` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_log-args
                                         exp = `*"input_tokens":*"output_tokens":*"ms":*` ).
    " privacy by default: neither the question nor the answer
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_log-args
                                                    sub = `secret` )
                                        exp = -1 ).

  ENDMETHOD.

  METHOD audit_with_prompt.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-log_prompts
                                      value = `on` ).
    mo_double->add_answer( `{"a":"the secret answer"}` ).
    z2ui5_cl_agent_llm=>create( )->chat( request( ) ).

    cl_abap_unit_assert=>assert_char_cp( act = last_log( )-args
                                         exp = `*the secret question*the secret answer*` ).

  ENDMETHOD.

  METHOD not_configured.

    z2ui5_cl_agent_llm=>set_double( ).
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_llm=>check_configured( ) ).
    TRY.
        z2ui5_cl_agent_llm=>create( ).
        cl_abap_unit_assert=>fail( `no key, no destination - no model` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-config ).
    ENDTRY.

  ENDMETHOD.

  METHOD custom_provider.

    " a class of a customer's own - here the double, created by name
    z2ui5_cl_agent_llm=>set_double( ).
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-provider
                                      value = `Z2UI5_CL_AGENT_LLM_DOUBLE` ).
    cl_abap_unit_assert=>assert_equals( act = z2ui5_cl_agent_llm=>get_provider( )
                                        exp = `Z2UI5_CL_AGENT_LLM_DOUBLE` ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a fresh double has no answer` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( )
                                             exp = `*no canned answer left*` ).
    ENDTRY.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-provider
                                      value = `Z2UI5_CL_AGENT_AUDIT` ).
    TRY.
        z2ui5_cl_agent_llm=>create( ).
        cl_abap_unit_assert=>fail( `a class that is no provider` ).
      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( )
                                             exp = `*no class implementing z2ui5_if_agent_llm*` ).
    ENDTRY.

  ENDMETHOD.

  METHOD key_never_shown.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-key
                                      value = `test-key-123` ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_llm_key( ) ).
    cl_abap_unit_assert=>assert_initial( z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-key ) ).
    LOOP AT z2ui5_cl_agent_settings=>get_all( ) INTO DATA(ls_setting) WHERE kind = 'LLM'.
      cl_abap_unit_assert=>assert_differs( act = ls_setting-value
                                           exp = `test-key-123` ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
