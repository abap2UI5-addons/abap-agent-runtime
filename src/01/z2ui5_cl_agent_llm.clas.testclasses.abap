"! A provider of a customer's own that fails with something else than
"! z2ui5_cx_agent_llm - a bug of its own, a dynamic check.
CLASS ltd_failing_llm DEFINITION FINAL FOR TESTING.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_agent_llm.

ENDCLASS.


CLASS ltd_failing_llm IMPLEMENTATION.

  METHOD z2ui5_if_agent_llm~chat.

    RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
      EXPORTING
        val = `the gateway of the provider is gone`.

  ENDMETHOD.

ENDCLASS.


"! The wrapper around every language model call: settings applied, stop
"! reasons refused, structured answers parsed, every call audited - the
"! prompt only when the setting says so. With the double, no real model.
CLASS ltcl_llm DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    DATA mo_double TYPE REF TO z2ui5_cl_agent_llm_double.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_17 WITH DEFAULT KEY.
    "! an app name of this test only - its audit entries are its own
    DATA mv_app TYPE string.

    METHODS setup.
    METHODS teardown.

    METHODS defaults_and_json FOR TESTING RAISING cx_static_check.
    METHODS refusal_refused FOR TESTING RAISING cx_static_check.
    METHODS max_tokens_refused FOR TESTING RAISING cx_static_check.
    METHODS context_window_refused FOR TESTING RAISING cx_static_check.
    METHODS other_stop_refused FOR TESTING RAISING cx_static_check.
    METHODS not_the_json FOR TESTING RAISING cx_static_check.
    METHODS audit_without_prompt FOR TESTING RAISING cx_static_check.
    METHODS audit_with_prompt FOR TESTING RAISING cx_static_check.
    METHODS not_configured FOR TESTING RAISING cx_static_check.
    METHODS custom_provider FOR TESTING RAISING cx_static_check.
    METHODS key_never_shown FOR TESTING RAISING cx_static_check.
    METHODS provider_failure FOR TESTING RAISING cx_static_check.

    METHODS last_log
      RETURNING
        VALUE(result) TYPE z2ui5_t_14.

    METHODS request
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_llm=>ty_s_request.

ENDCLASS.


CLASS ltcl_llm IMPLEMENTATION.

  METHOD setup.

    SELECT * FROM z2ui5_t_17 INTO TABLE mt_saved WHERE kind = 'LLM' .
    DELETE FROM z2ui5_t_17 WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    CREATE OBJECT mo_double.
    z2ui5_cl_agent_llm=>set_double( mo_double ).
    mv_app = |ZT{ substring( val = z2ui5_cl_ui5_util_context=>uuid_get_c32( )
                             len = 28 ) }|.

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_double( ).
    z2ui5_cl_agent_llm=>set_http( ).
    DELETE FROM z2ui5_t_14 WHERE app = mv_app.
    DELETE FROM z2ui5_t_17 WHERE kind = 'LLM'.
    INSERT z2ui5_t_17 FROM TABLE mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD request.
    DATA temp1 TYPE z2ui5_if_agent_llm=>ty_t_message.
    DATA temp2 LIKE LINE OF temp1.

    CLEAR result.
    result-purpose = `test`.
    result-app = mv_app.
    result-system = `You answer in JSON.`.
    result-schema = `{"type":"object","additionalProperties":false,"required":["a"],"properties":{"a":{"type":"string"}}}`.

    CLEAR temp1.

    temp2-role = `user`.
    temp2-content = `the secret question`.
    INSERT temp2 INTO TABLE temp1.
    result-t_message = temp1.

  ENDMETHOD.

  METHOD last_log.

    DATA lv_app TYPE z2ui5_t_14-app.
    DATA lt_log TYPE STANDARD TABLE OF z2ui5_t_14 WITH DEFAULT KEY.

    lv_app = mv_app.

    SELECT * FROM z2ui5_t_14 INTO TABLE lt_log WHERE operation = 'llm' AND app = lv_app
      .
    cl_abap_unit_assert=>assert_equals( act = lines( lt_log )
                                        exp = 1
                                        msg = `one call, one audit entry` ).
    READ TABLE lt_log INTO result INDEX 1.

  ENDMETHOD.

  METHOD defaults_and_json.
    DATA ls_answer TYPE z2ui5_if_agent_llm=>ty_s_response.
    FIELD-SYMBOLS <temp2> LIKE LINE OF mo_double->mt_request.
    DATA temp3 LIKE sy-tabix.
    FIELD-SYMBOLS <temp4> LIKE LINE OF mo_double->mt_request.
    DATA temp5 LIKE sy-tabix.
    FIELD-SYMBOLS <temp6> LIKE LINE OF mo_double->mt_request.
    DATA temp7 LIKE sy-tabix.

    mo_double->add_answer( `{"a":"b"}` ).

    ls_answer = z2ui5_cl_agent_llm=>create( )->chat( request( ) ).

    cl_abap_unit_assert=>assert_equals( act = ls_answer-json->get_string( `/a` )
                                        exp = `b` ).
    " the settings' defaults: effort low, 16000 tokens


    temp3 = sy-tabix.
    READ TABLE mo_double->mt_request INDEX 1 ASSIGNING <temp2>.
    sy-tabix = temp3.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = <temp2>-effort
                                        exp = `low` ).


    temp5 = sy-tabix.
    READ TABLE mo_double->mt_request INDEX 1 ASSIGNING <temp4>.
    sy-tabix = temp5.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = <temp4>-max_tokens
                                        exp = 16000 ).

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-effort
                                      value = `high` ).
    mo_double->add_answer( `{"a":"c"}` ).
    z2ui5_cl_agent_llm=>create( )->chat( request( ) ).


    temp7 = sy-tabix.
    READ TABLE mo_double->mt_request INDEX 2 ASSIGNING <temp6>.
    sy-tabix = temp7.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = <temp6>-effort
                                        exp = `high` ).

  ENDMETHOD.

  METHOD refusal_refused.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    mo_double->add_answer( text        = `{"a":"half`
                           stop_reason = z2ui5_if_agent_llm=>cs_stop-refusal ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a refusal must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-refusal ).
        cl_abap_unit_assert=>assert_false( lx->retryable ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = last_log( )-outcome
                                        exp = `error` ).

  ENDMETHOD.

  METHOD max_tokens_refused.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    mo_double->add_answer( text        = `{"a":"cut`
                           stop_reason = z2ui5_if_agent_llm=>cs_stop-max_tokens ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `max_tokens must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-max_tokens ).
    ENDTRY.

  ENDMETHOD.

  METHOD context_window_refused.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    " cut off by the full context window - valid JSON or not, never an answer
    mo_double->add_answer( text        = `{"a":"cut"}`
                           stop_reason = z2ui5_if_agent_llm=>cs_stop-context_window ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `model_context_window_exceeded must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-max_tokens ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = last_log( )-outcome
                                        exp = `error` ).

  ENDMETHOD.

  METHOD other_stop_refused.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    " a reason that is no answer (pause_turn, a provider's guardrail) - its
    " text is never taken for one
    mo_double->add_answer( text        = `{"a":"b"}`
                           stop_reason = `guardrail_intervened` ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `guardrail_intervened must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-response ).
    ENDTRY.

  ENDMETHOD.

  METHOD not_the_json.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    mo_double->add_answer( `Sure! Here is your view:` ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `text instead of JSON must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-response ).
    ENDTRY.

  ENDMETHOD.

  METHOD audit_without_prompt.
    DATA ls_log TYPE z2ui5_t_14.

    mo_double->add_answer( `{"a":"the secret answer"}` ).
    z2ui5_cl_agent_llm=>create( )->chat( request( ) ).


    ls_log = last_log( ).
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
    DATA ls_request TYPE z2ui5_if_agent_llm=>ty_s_request.
    DATA temp8 TYPE z2ui5_if_agent_llm=>ty_s_message.
    DATA lv_args TYPE string.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-log_prompts
                                      value = `on` ).
    mo_double->add_answer( `{"a":"the secret answer"}` ).
    " a question as long as a copilot's, which carries the whole screen

    ls_request = request( ).

    CLEAR temp8.
    temp8-role = `user`.
    temp8-content = repeat( val = `0123456789` occ = 500 ).
    INSERT temp8 INTO TABLE ls_request-t_message.
    z2ui5_cl_agent_llm=>create( )->chat( ls_request ).

    " the answer first, so the cut at 2000 characters never takes it, and
    " what is kept is still JSON

    lv_args = last_log( )-args.
    cl_abap_unit_assert=>assert_char_cp( act = lv_args
                                         exp = `*the secret answer*the secret question*` ).
    z2ui5_cl_ajson=>parse( lv_args ).

  ENDMETHOD.

  METHOD not_configured.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    z2ui5_cl_agent_llm=>set_double( ).
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_llm=>check_configured( ) ).
    TRY.
        z2ui5_cl_agent_llm=>create( ).
        cl_abap_unit_assert=>fail( `no key, no destination - no model` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-config ).
    ENDTRY.

  ENDMETHOD.

  METHOD custom_provider.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    " a class of a customer's own - here the double, created by name
    z2ui5_cl_agent_llm=>set_double( ).
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-provider
                                      value = `Z2UI5_CL_AGENT_LLM_DOUBLE` ).
    cl_abap_unit_assert=>assert_equals( act = z2ui5_cl_agent_llm=>get_provider( )
                                        exp = `Z2UI5_CL_AGENT_LLM_DOUBLE` ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a fresh double has no answer` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
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
    DATA temp9 TYPE z2ui5_cl_agent_settings=>ty_t_setting.
    DATA ls_setting LIKE LINE OF temp9.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-key
                                      value = `test-key-123` ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_settings=>check_llm_key( ) ).
    cl_abap_unit_assert=>assert_initial( z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-key ) ).

    temp9 = z2ui5_cl_agent_settings=>get_all( ).

    LOOP AT temp9 INTO ls_setting WHERE kind = 'LLM'.
      cl_abap_unit_assert=>assert_differs( act = ls_setting-value
                                           exp = `test-key-123` ).
    ENDLOOP.

  ENDMETHOD.

  METHOD provider_failure.

    " whatever a provider raises: one exception for the callers (generate( )
    " never raises), and the call is audited like every other
    DATA temp10 TYPE REF TO ltd_failing_llm.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.
    CREATE OBJECT temp10 TYPE ltd_failing_llm.
    z2ui5_cl_agent_llm=>set_double( temp10 ).
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a failed provider must raise` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-response ).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( )
                                             exp = `*the gateway of the provider is gone*` ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = last_log( )-outcome
                                        exp = `error` ).

  ENDMETHOD.

ENDCLASS.
