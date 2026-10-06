"! The language model of the agent addon - the factory every AI feature
"! asks (generative UI, the in-app copilot) and the wrapper around the
"! configured provider:
"!
"!   DATA(llm) = z2ui5_cl_agent_llm=&gt;create( ).
"!   DATA(answer) = llm-&gt;chat( VALUE #( purpose = `genui` app = `ZCL_MY_APP`
"!                                       system = `...` schema = `{...}`
"!                                       t_message = VALUE #( ( role = `user` content = `...` ) ) ) ).
"!
"! create( ) reads the agent settings (z2ui5_cl_agent_settings, kind LLM):
"! the provider class (default z2ui5_cl_agent_llm_anthropic, or a class of
"! your own implementing z2ui5_if_agent_llm - SAP AI Core, Bedrock, a
"! gateway), and wraps it. The wrapper fills in the effort and max_tokens
"! of the settings, refuses an answer that stopped for refusal, max_tokens
"! or a full context window (z2ui5_cx_agent_llm - never parsed), parses a
"! structured answer into json, and writes one audit entry per call into
"! Z2UI5_T_AG_LOG (operation llm): who, which app, purpose, model, tokens,
"! duration, outcome - the prompt and the answer only when the setting
"! log_prompts is on.
"!
"! Unit tests replace the provider with set_double( ) (a
"! z2ui5_cl_agent_llm_double with canned answers) and the transport of the
"! Anthropic provider with set_http( ) - no test reaches a real model.
CLASS z2ui5_cl_agent_llm DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm.
    ALIASES chat FOR z2ui5_if_agent_llm~chat.

    CONSTANTS c_default_provider TYPE string VALUE `Z2UI5_CL_AGENT_LLM_ANTHROPIC`.
    CONSTANTS c_default_max_tokens TYPE i VALUE 16000.

    "! The configured language model, wrapped (see the class comment).
    "! Raises z2ui5_cx_agent_llm (config) when the provider class is not
    "! usable or - for the shipped provider - neither a key nor a
    "! destination is set.
    CLASS-METHODS create
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_llm
      RAISING
        z2ui5_cx_agent_llm.

    "! Whether create( ) would succeed - for a UI that hides an AI feature
    "! that is not set up.
    CLASS-METHODS check_configured
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! Test seam: every create( ) wraps this instance instead of the
    "! configured provider, until reset with an unbound reference.
    CLASS-METHODS set_double
      IMPORTING
        llm TYPE REF TO z2ui5_if_agent_llm OPTIONAL.

    "! Test seam: the transport the shipped provider sends with.
    CLASS-METHODS set_http
      IMPORTING
        http TYPE REF TO z2ui5_if_agent_llm_http OPTIONAL.

    "! The transport of this platform: the test seam, else
    "! z2ui5_cl_agent_llm_std (ABAP Standard, package 03) or
    "! z2ui5_cl_agent_llm_cloud (ABAP Cloud, package 04) - whichever is
    "! installed.
    CLASS-METHODS get_http
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_if_agent_llm_http
      RAISING
        z2ui5_cx_agent_llm.

    "! The provider class name in effect.
    CLASS-METHODS get_provider
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CLASS-DATA gi_double TYPE REF TO z2ui5_if_agent_llm.
    CLASS-DATA gi_http TYPE REF TO z2ui5_if_agent_llm_http.

    DATA mi_inner TYPE REF TO z2ui5_if_agent_llm.
    DATA mv_provider TYPE string.

    METHODS audit
      IMPORTING
        is_request  TYPE z2ui5_if_agent_llm=>ty_s_request
        is_response TYPE z2ui5_if_agent_llm=>ty_s_response
        ms          TYPE i
        error       TYPE string OPTIONAL.

ENDCLASS.


CLASS z2ui5_cl_agent_llm IMPLEMENTATION.

  METHOD set_double.

    gi_double = llm.

  ENDMETHOD.

  METHOD set_http.

    gi_http = http.

  ENDMETHOD.

  METHOD get_provider.

    IF gi_double IS BOUND.
      result = z2ui5_cl_ui5_util_context=>rtti_get_classname_by_ref( gi_double ).
      RETURN.
    ENDIF.
    result = to_upper( condense( z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-provider ) ) ).
    IF result IS INITIAL.
      result = c_default_provider.
    ENDIF.

  ENDMETHOD.

  METHOD check_configured.

    TRY.
        create( ).
        result = abap_true.
      CATCH z2ui5_cx_agent_llm.
        result = abap_false.
    ENDTRY.

  ENDMETHOD.

  METHOD create.

    DATA li_inner TYPE REF TO z2ui5_if_agent_llm.

    result = NEW #( ).
    result->mv_provider = get_provider( ).
    IF gi_double IS BOUND.
      result->mi_inner = gi_double.
      RETURN.
    ENDIF.

    IF result->mv_provider = c_default_provider
        AND z2ui5_cl_agent_settings=>check_llm_key( ) = abap_false
        AND z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-destination ) IS INITIAL.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind = z2ui5_cx_agent_llm=>cs_kind-config
          text = `no language model is configured - an agent administrator sets an API key or a destination ` &&
                 `in the agent settings (z2ui5_cl_agent_app_admin, "Language model")`.
    ENDIF.
    IF z2ui5_cl_ui5_util_context=>rtti_check_class_impl_intf( class = result->mv_provider
                                                              intf  = `Z2UI5_IF_AGENT_LLM` ) = abap_false.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind = z2ui5_cx_agent_llm=>cs_kind-config
          text = |the language model provider { result->mv_provider } is no class implementing z2ui5_if_agent_llm|.
    ENDIF.
    TRY.
        CREATE OBJECT li_inner TYPE (result->mv_provider).
        result->mi_inner = li_inner.
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind     = z2ui5_cx_agent_llm=>cs_kind-config
            text     = |the language model provider { result->mv_provider } cannot be created - { lx->get_text( ) }|
            previous = lx.
    ENDTRY.

  ENDMETHOD.

  METHOD get_http.

    DATA li_http TYPE REF TO z2ui5_if_agent_llm_http.
    DATA lt_class TYPE string_table.

    IF gi_http IS BOUND.
      result = gi_http.
      RETURN.
    ENDIF.
    lt_class = VALUE #( ( `Z2UI5_CL_AGENT_LLM_STD` ) ( `Z2UI5_CL_AGENT_LLM_CLOUD` ) ).
    LOOP AT lt_class INTO DATA(lv_class).
      IF z2ui5_cl_ui5_util_context=>rtti_check_class_impl_intf( class = lv_class
                                                                intf  = `Z2UI5_IF_AGENT_LLM_HTTP` ) = abap_false.
        CONTINUE.
      ENDIF.
      TRY.
          CREATE OBJECT li_http TYPE (lv_class).
          result = li_http.
          RETURN.
        CATCH cx_root ##NO_HANDLER.
          " the other platform's class - try the next
      ENDTRY.
    ENDLOOP.
    RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
      EXPORTING
        kind = z2ui5_cx_agent_llm=>cs_kind-config
        text = `no HTTP transport for the language model - install the branch of your platform ` &&
               `(standard: z2ui5_cl_agent_llm_std, cloud: z2ui5_cl_agent_llm_cloud)`.

  ENDMETHOD.

  METHOD z2ui5_if_agent_llm~chat.

    DATA(ls_request) = is_request.
    IF ls_request-effort IS INITIAL.
      ls_request-effort = to_lower( z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-effort ) ).
    ENDIF.
    IF ls_request-effort IS INITIAL.
      ls_request-effort = z2ui5_if_agent_llm=>cs_effort-low.
    ENDIF.
    IF ls_request-max_tokens <= 0.
      TRY.
          ls_request-max_tokens = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-max_tokens ).
        CATCH cx_root.
          CLEAR ls_request-max_tokens.
      ENDTRY.
    ENDIF.
    IF ls_request-max_tokens <= 0.
      ls_request-max_tokens = c_default_max_tokens.
    ENDIF.

    DATA(lv_start) = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    TRY.
        result = mi_inner->chat( ls_request ).

        " the stop reason first - a declined or cut-off answer is never parsed
        IF result-stop_reason = z2ui5_if_agent_llm=>cs_stop-refusal.
          RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
            EXPORTING
              kind = z2ui5_cx_agent_llm=>cs_kind-refusal
              text = `the language model declined to answer this request (stop reason refusal)`.
        ENDIF.
        IF result-stop_reason = z2ui5_if_agent_llm=>cs_stop-max_tokens.
          RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
            EXPORTING
              kind = z2ui5_cx_agent_llm=>cs_kind-max_tokens
              text = |the answer of the language model was cut off at { ls_request-max_tokens } tokens (stop reason max_tokens)|.
        ENDIF.
        IF result-stop_reason = z2ui5_if_agent_llm=>cs_stop-context_window.
          RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
            EXPORTING
              kind = z2ui5_cx_agent_llm=>cs_kind-max_tokens
              text = |the answer of the language model was cut off - the context window is full (stop reason { result-stop_reason })|.
        ENDIF.
        IF ls_request-schema IS NOT INITIAL AND result-json IS NOT BOUND.
          TRY.
              result-json = z2ui5_cl_ajson=>parse( iv_json            = result-text
                                                   iv_keep_item_order = abap_true ).
            CATCH cx_root INTO DATA(lx_parse).
              RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
                EXPORTING
                  kind     = z2ui5_cx_agent_llm=>cs_kind-response
                  text     = `the language model did not answer with the requested JSON`
                  previous = lx_parse.
          ENDTRY.
        ENDIF.
        audit( is_request  = ls_request
               is_response = result
               ms          = z2ui5_cl_ui5_util_context=>time_diff_milliseconds(
                                 time_from = lv_start
                                 time_to   = z2ui5_cl_ui5_util_context=>time_get_timestampl( ) ) ).

      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        audit( is_request  = ls_request
               is_response = result
               ms          = z2ui5_cl_ui5_util_context=>time_diff_milliseconds(
                                 time_from = lv_start
                                 time_to   = z2ui5_cl_ui5_util_context=>time_get_timestampl( ) )
               error       = |{ lx->kind }: { lx->get_text( ) }| ).
        RAISE EXCEPTION lx.
    ENDTRY.

  ENDMETHOD.

  METHOD audit.

    DATA lt_message TYPE string_table.

    DATA(lv_args) = |\{"model":{ z2ui5_cl_agent_viewxml=>json_string( is_response-model ) }| &&
                    |,"effort":{ z2ui5_cl_agent_viewxml=>json_string( is_request-effort ) }| &&
                    |,"structured":{ COND string( WHEN is_request-schema IS NOT INITIAL THEN `true` ELSE `false` ) }| &&
                    |,"stop_reason":{ z2ui5_cl_agent_viewxml=>json_string( is_response-stop_reason ) }| &&
                    |,"input_tokens":{ is_response-usage-input_tokens }| &&
                    |,"output_tokens":{ is_response-usage-output_tokens }| &&
                    |,"ms":{ ms }|.
    " privacy: what the user and the screen said only when asked to keep it
    IF z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-log_prompts ) = abap_true.
      LOOP AT is_request-t_message INTO DATA(ls_message).
        INSERT |\{"role":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-role ) }| &&
               |,"content":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-content ) }\}| INTO TABLE lt_message.
      ENDLOOP.
      lv_args = |{ lv_args },"messages":[{ concat_lines_of( table = lt_message
                                                             sep   = `,` ) }]| &&
                |,"answer":{ z2ui5_cl_agent_viewxml=>json_string( is_response-text ) }|.
    ENDIF.

    z2ui5_cl_agent_audit=>log( VALUE #( app       = is_request-app
                                        operation = `llm`
                                        event     = is_request-purpose
                                        args      = |{ lv_args }\}|
                                        outcome   = COND #( WHEN error IS INITIAL
                                                            THEN z2ui5_cl_agent_audit=>cs_outcome-ok
                                                            ELSE z2ui5_cl_agent_audit=>cs_outcome-error )
                                        text      = error
                                        client    = mv_provider ) ).

  ENDMETHOD.

ENDCLASS.
