"! The Claude Messages API provider against a transport double: the
"! request it sends (headers, body) and how it reads answers and errors -
"! no request leaves the test.
CLASS ltd_http DEFINITION FINAL FOR TESTING.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm_http.

    DATA ms_sent TYPE z2ui5_if_agent_llm_http=>ty_s_request.
    DATA ms_answer TYPE z2ui5_if_agent_llm_http=>ty_s_response.

ENDCLASS.


CLASS ltd_http IMPLEMENTATION.

  METHOD z2ui5_if_agent_llm_http~post.

    ms_sent = is_request.
    result = ms_answer.

  ENDMETHOD.

ENDCLASS.


CLASS ltcl_anthropic DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    DATA mo_http TYPE REF TO ltd_http.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_ag_set WITH EMPTY KEY.

    METHODS setup.
    METHODS teardown.

    METHODS request_shape FOR TESTING RAISING cx_static_check.
    METHODS settings_apply FOR TESTING RAISING cx_static_check.
    METHODS answer_read FOR TESTING RAISING cx_static_check.
    METHODS refusal_through_wrapper FOR TESTING RAISING cx_static_check.
    METHODS rate_limit_retryable FOR TESTING RAISING cx_static_check.
    METHODS bad_request_final FOR TESTING RAISING cx_static_check.

    METHODS header
      IMPORTING
        name          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS request
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_llm=>ty_s_request.

ENDCLASS.


CLASS ltcl_anthropic IMPLEMENTATION.

  METHOD setup.

    SELECT * FROM z2ui5_t_ag_set WHERE kind = 'LLM' INTO TABLE @mt_saved.
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    " a placeholder, never a real key - the transport is a double
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-key
                                      value = `test-key` ).
    mo_http = NEW #( ).
    mo_http->ms_answer = VALUE #( status = 200
                                  body   = `{"id":"msg_1","type":"message","model":"claude-opus-5-5","stop_reason":"end_turn",` &&
                                           `"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"a\":\"b\"}"}],` &&
                                           `"usage":{"input_tokens":120,"output_tokens":30,"cache_read_input_tokens":100}}` ).
    z2ui5_cl_agent_llm=>set_http( mo_http ).

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_http( ).
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD request.

    result = VALUE #( purpose    = `test`
                      system     = `You answer in JSON.`
                      schema     = `{"type":"object","additionalProperties":false,"required":["a"],"properties":{"a":{"type":"string"}}}`
                      effort     = `low`
                      max_tokens = 16000
                      t_message  = VALUE #( ( role = `user` content = `say "b"` ) ) ).

  ENDMETHOD.

  METHOD header.

    READ TABLE mo_http->ms_sent-t_header INTO DATA(ls_header) WITH KEY name = name. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_header-value.
    ENDIF.

  ENDMETHOD.

  METHOD request_shape.

    NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).

    DATA(ls_sent) = mo_http->ms_sent.
    cl_abap_unit_assert=>assert_equals( act = ls_sent-url
                                        exp = `https://api.anthropic.com/v1/messages` ).
    cl_abap_unit_assert=>assert_equals( act = header( `x-api-key` )
                                        exp = `test-key` ).
    cl_abap_unit_assert=>assert_equals( act = header( `anthropic-version` )
                                        exp = `2023-06-01` ).
    cl_abap_unit_assert=>assert_equals( act = header( `content-type` )
                                        exp = `application/json` ).
    cl_abap_unit_assert=>assert_equals( act = header( `anthropic-beta` )
                                        exp = `server-side-fallback-2026-07-01` ).
    cl_abap_unit_assert=>assert_equals(
        act = ls_sent-body
        exp = `{"model":"claude-opus-5-5","max_tokens":16000,"system":"You answer in JSON.",` &&
              `"messages":[{"role":"user","content":"say \"b\""}],` &&
              `"output_config":{"effort":"low","format":{"type":"json_schema","schema":` &&
              `{"type":"object","additionalProperties":false,"required":["a"],"properties":{"a":{"type":"string"}}}}},` &&
              `"fallbacks":"default"}` ).
    " thinking is always on for this model - never configured
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_sent-body
                                                    sub = `thinking` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_true( xsdbool( ls_sent-timeout >= 120 ) ).

  ENDMETHOD.

  METHOD settings_apply.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-model
                                      value = `claude-sonnet-5-5` ).
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-fallback
                                      value = `off` ).
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-destination
                                      value = `ANTHROPIC` ).
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-timeout
                                      value = `30` ).
    NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).

    DATA(ls_sent) = mo_http->ms_sent.
    cl_abap_unit_assert=>assert_char_cp( act = ls_sent-body
                                         exp = `{"model":"claude-sonnet-5-5",*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_sent-body
                                                    sub = `fallbacks` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_initial( header( `anthropic-beta` ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_sent-destination
                                        exp = `ANTHROPIC` ).
    cl_abap_unit_assert=>assert_equals( act = ls_sent-url
                                        exp = `/v1/messages` ).
    cl_abap_unit_assert=>assert_equals( act = ls_sent-timeout
                                        exp = 120 ).

  ENDMETHOD.

  METHOD answer_read.

    DATA(ls_answer) = NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).

    " the first text block - the thinking block before it is skipped
    cl_abap_unit_assert=>assert_equals( act = ls_answer-text
                                        exp = `{"a":"b"}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_answer-stop_reason
                                        exp = `end_turn` ).
    cl_abap_unit_assert=>assert_equals( act = ls_answer-model
                                        exp = `claude-opus-5-5` ).
    cl_abap_unit_assert=>assert_equals( act = ls_answer-usage-input_tokens
                                        exp = 120 ).
    cl_abap_unit_assert=>assert_equals( act = ls_answer-usage-cache_read
                                        exp = 100 ).

  ENDMETHOD.

  METHOD refusal_through_wrapper.

    mo_http->ms_answer-body = `{"id":"msg_2","model":"claude-opus-5-5","stop_reason":"refusal",` &&
                              `"stop_details":{"type":"refusal","category":"cyber"},"content":[],"usage":{"input_tokens":5,"output_tokens":0}}`.
    TRY.
        z2ui5_cl_agent_llm=>create( )->chat( request( ) ).
        cl_abap_unit_assert=>fail( `a refusal is never an answer` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-refusal ).
    ENDTRY.

  ENDMETHOD.

  METHOD rate_limit_retryable.

    mo_http->ms_answer = VALUE #( status = 429
                                  reason = `Too Many Requests`
                                  body   = `{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}` ).
    TRY.
        NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).
        cl_abap_unit_assert=>fail( `429 must raise` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( act = lx->http_status
                                            exp = 429 ).
        cl_abap_unit_assert=>assert_true( lx->retryable ).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( )
                                             exp = `*HTTP 429*slow down*` ).
    ENDTRY.

    mo_http->ms_answer = VALUE #( status = 529
                                  body   = `{"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}` ).
    TRY.
        NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).
        cl_abap_unit_assert=>fail( `529 must raise` ).
      CATCH z2ui5_cx_agent_llm INTO lx.
        cl_abap_unit_assert=>assert_true( lx->retryable ).
    ENDTRY.

  ENDMETHOD.

  METHOD bad_request_final.

    mo_http->ms_answer = VALUE #( status = 400
                                  body   = `{"type":"error","error":{"type":"invalid_request_error","message":"bad schema"}}` ).
    TRY.
        NEW z2ui5_cl_agent_llm_anthropic( )->z2ui5_if_agent_llm~chat( request( ) ).
        cl_abap_unit_assert=>fail( `400 must raise` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        cl_abap_unit_assert=>assert_false( lx->retryable ).
        cl_abap_unit_assert=>assert_equals( act = lx->kind
                                            exp = z2ui5_cx_agent_llm=>cs_kind-http ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
