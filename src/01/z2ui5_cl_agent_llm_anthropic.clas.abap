"! The Claude Messages API as a z2ui5_if_agent_llm - raw HTTP, as ABAP has
"! no SDK: POST https://api.anthropic.com/v1/messages with the headers
"! content-type, x-api-key and anthropic-version 2023-06-01, one
"! non-streaming request per chat call.
"!
"! The agent settings (kind LLM, z2ui5_cl_agent_app_admin) decide:
"!   model        default claude-opus-5-5
"!   effort       output_config.effort - the wrapper sends low unless set
"!   url          default https://api.anthropic.com/v1/messages; with a
"!                destination the path below it (default /v1/messages)
"!   destination  ABAP Standard: an SM59 destination (type G); ABAP Cloud:
"!                a communication arrangement SCENARIO/SERVICE_ID - the
"!                host, TLS and any proxy come from there
"!   key          the API key, sent as x-api-key (empty: the destination or
"!                a gateway behind it authenticates)
"!   fallback     on (default): the server-side refusal fallback -
"!                "fallbacks":"default" plus the anthropic-beta header
"!   beta         that header's value, default server-side-fallback-2026-07-01
"!   timeout      seconds, default 300
"!
"! Thinking is always on for this model and never configured here: the
"! body carries no thinking parameter (a disabled one is a 400). A
"! structured answer is requested with output_config.format json_schema;
"! there is no assistant prefill. The answer is the first content block of
"! type text - thinking blocks come first and are empty.
"!
"! Not every model takes every field: effort is a 400 on Claude Haiku 4.5,
"! Sonnet 4.5 and older models, and the server-side fallback exists for the
"! Fable, Mythos, Opus 5 and Sonnet 5.5 lines only - both are left out for a
"! model that does not take them (takes_effort, takes_fallback). The system
"! prompt is sent as a cached block: the generative UI's carries the whole
"! vocabulary, the same on every call and twice per generation.
CLASS z2ui5_cl_agent_llm_anthropic DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm.

    CONSTANTS c_default_model TYPE string VALUE `claude-opus-5-5`.
    CONSTANTS c_default_url TYPE string VALUE `https://api.anthropic.com/v1/messages`.
    CONSTANTS c_default_path TYPE string VALUE `/v1/messages`.
    CONSTANTS c_version TYPE string VALUE `2023-06-01`.
    CONSTANTS c_default_beta TYPE string VALUE `server-side-fallback-2026-07-01`.
    CONSTANTS c_default_timeout TYPE i VALUE 300.

    "! The JSON body of a request - public for the unit tests.
    METHODS build_body
      IMPORTING
        is_request    TYPE z2ui5_if_agent_llm=>ty_s_request
      RETURNING
        VALUE(result) TYPE string
      RAISING
        z2ui5_cx_agent_llm.

    "! The HTTP request of a chat call - public for the unit tests.
    METHODS build_request
      IMPORTING
        is_request    TYPE z2ui5_if_agent_llm=>ty_s_request
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_llm_http=>ty_s_request
      RAISING
        z2ui5_cx_agent_llm.

    "! An HTTP answer as a chat answer, or the exception it stands for.
    CLASS-METHODS parse_response
      IMPORTING
        is_response   TYPE z2ui5_if_agent_llm_http=>ty_s_response
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_llm=>ty_s_response
      RAISING
        z2ui5_cx_agent_llm.

    "! Whether the model takes output_config.effort.
    CLASS-METHODS takes_effort
      IMPORTING
        model         TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! Whether the model takes the server-side refusal fallback.
    CLASS-METHODS takes_fallback
      IMPORTING
        model         TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CLASS-METHODS setting
      IMPORTING
        item          TYPE string
        default       TYPE string OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_llm_anthropic IMPLEMENTATION.

  METHOD setting.

    result = condense( z2ui5_cl_agent_settings=>get_llm( item ) ).
    IF result IS INITIAL.
      result = default.
    ENDIF.

  ENDMETHOD.

  METHOD takes_effort.

    " a model id may carry a platform prefix (anthropic.claude-...) or a date
    result = xsdbool( NOT ( model CP `*claude-haiku*`
                         OR model CP `*claude-3*`
                         OR model CP `*claude-sonnet-4-5*`
                         OR model CP `*claude-sonnet-4-2*`
                         OR model CP `*claude-sonnet-4-0*`
                         OR model CP `*claude-opus-4-1*`
                         OR model CP `*claude-opus-4-2*`
                         OR model CP `*claude-opus-4-0*` ) ).

  ENDMETHOD.

  METHOD takes_fallback.

    result = xsdbool( model CP `*claude-fable-5*`
                   OR model CP `*claude-mythos-5*`
                   OR model CP `*claude-opus-5*`
                   OR model CP `*claude-sonnet-5-5*` ).

  ENDMETHOD.

  METHOD build_body.

    DATA lt_message TYPE string_table.
    DATA lt_config TYPE string_table.

    DATA(lv_model) = setting( item    = z2ui5_cl_agent_settings=>cs_llm-model
                              default = c_default_model ).

    IF is_request-t_message IS INITIAL.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind = z2ui5_cx_agent_llm=>cs_kind-config
          text = `a chat call needs at least one message`.
    ENDIF.
    LOOP AT is_request-t_message INTO DATA(ls_message).
      INSERT |\{"role":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-role ) }| &&
             |,"content":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-content ) }\}| INTO TABLE lt_message.
    ENDLOOP.

    IF is_request-effort IS NOT INITIAL AND takes_effort( lv_model ) = abap_true.
      INSERT |"effort":{ z2ui5_cl_agent_viewxml=>json_string( is_request-effort ) }| INTO TABLE lt_config.
    ENDIF.
    IF is_request-schema IS NOT INITIAL.
      " the schema is embedded as JSON - checked first, so a broken schema
      " is a readable error here and not a 400 from the service
      TRY.
          z2ui5_cl_ajson=>parse( is_request-schema ).
        CATCH cx_root INTO DATA(lx).
          RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
            EXPORTING
              kind     = z2ui5_cx_agent_llm=>cs_kind-config
              text     = `the JSON schema of the request is no valid JSON`
              previous = lx.
      ENDTRY.
      INSERT |"format":\{"type":"json_schema","schema":{ is_request-schema }\}| INTO TABLE lt_config.
    ENDIF.

    result = |\{"model":{ z2ui5_cl_agent_viewxml=>json_string( lv_model ) }| &&
             |,"max_tokens":{ COND i( WHEN is_request-max_tokens > 0 THEN is_request-max_tokens
                                       ELSE z2ui5_cl_agent_llm=>c_default_max_tokens ) }|.
    IF is_request-system IS NOT INITIAL.
      result = |{ result },"system":[\{"type":"text","text":{ z2ui5_cl_agent_viewxml=>json_string( is_request-system ) }| &&
               |,"cache_control":\{"type":"ephemeral"\}\}]|.
    ENDIF.
    result = |{ result },"messages":[{ concat_lines_of( table = lt_message
                                                       sep   = `,` ) }]|.
    IF lt_config IS NOT INITIAL.
      result = |{ result },"output_config":\{{ concat_lines_of( table = lt_config
                                                               sep   = `,` ) }\}|.
    ENDIF.
    IF z2ui5_cl_agent_settings=>check_llm( item    = z2ui5_cl_agent_settings=>cs_llm-fallback
                                           default = abap_true ) = abap_true
        AND takes_fallback( lv_model ) = abap_true.
      result = |{ result },"fallbacks":"default"|.
    ENDIF.
    result = |{ result }\}|.

  ENDMETHOD.

  METHOD build_request.

    result-body = build_body( is_request ).
    result-destination = setting( z2ui5_cl_agent_settings=>cs_llm-destination ).
    result-url = setting( item    = z2ui5_cl_agent_settings=>cs_llm-url
                          default = COND #( WHEN result-destination IS INITIAL THEN c_default_url ELSE c_default_path ) ).
    TRY.
        result-timeout = setting( item    = z2ui5_cl_agent_settings=>cs_llm-timeout
                                  default = |{ c_default_timeout }| ).
      CATCH cx_root.
        result-timeout = c_default_timeout.
    ENDTRY.
    IF result-timeout < 120.
      " a structured answer with thinking takes its time - never less than two minutes
      result-timeout = 120.
    ENDIF.

    INSERT VALUE #( name  = `content-type`
                    value = `application/json` ) INTO TABLE result-t_header.
    INSERT VALUE #( name  = `anthropic-version`
                    value = c_version ) INTO TABLE result-t_header.
    DATA(lv_key) = z2ui5_cl_agent_settings=>get_llm_key( ).
    IF lv_key IS NOT INITIAL.
      INSERT VALUE #( name  = `x-api-key`
                      value = lv_key ) INTO TABLE result-t_header.
    ENDIF.
    IF z2ui5_cl_agent_settings=>check_llm( item    = z2ui5_cl_agent_settings=>cs_llm-fallback
                                           default = abap_true ) = abap_true
        AND takes_fallback( setting( item    = z2ui5_cl_agent_settings=>cs_llm-model
                                     default = c_default_model ) ) = abap_true.
      INSERT VALUE #( name  = `anthropic-beta`
                      value = setting( item    = z2ui5_cl_agent_settings=>cs_llm-beta
                                       default = c_default_beta ) ) INTO TABLE result-t_header.
    ENDIF.

  ENDMETHOD.

  METHOD parse_response.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    DATA lv_message TYPE string.

    TRY.
        lo_json = z2ui5_cl_ajson=>parse( is_response-body ).
      CATCH cx_root.
        CLEAR lo_json.
    ENDTRY.

    IF is_response-status <> 200.
      IF lo_json IS BOUND.
        TRY.
            lv_message = lo_json->get_string( `/error/message` ).
          CATCH cx_root.
            CLEAR lv_message.
        ENDTRY.
      ENDIF.
      IF lv_message IS INITIAL.
        lv_message = z2ui5_cl_agent_viewxml=>cut( val = is_response-body
                                                  len = 200 ).
      ENDIF.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind        = z2ui5_cx_agent_llm=>cs_kind-http
          text        = |the Claude API answered HTTP { is_response-status } { is_response-reason } - { lv_message }|
          http_status = is_response-status
          retryable   = xsdbool( is_response-status = 408 OR is_response-status = 429 OR is_response-status >= 500 ).
    ENDIF.

    IF lo_json IS NOT BOUND.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind        = z2ui5_cx_agent_llm=>cs_kind-response
          text        = `the Claude API answered with no JSON`
          http_status = is_response-status.
    ENDIF.

    TRY.
        result-id = lo_json->get_string( `/id` ).
        result-model = lo_json->get_string( `/model` ).
        result-stop_reason = lo_json->get_string( `/stop_reason` ).
        result-usage-input_tokens = lo_json->get_integer( `/usage/input_tokens` ).
        result-usage-output_tokens = lo_json->get_integer( `/usage/output_tokens` ).
        result-usage-cache_read = lo_json->get_integer( `/usage/cache_read_input_tokens` ).
        result-usage-cache_write = lo_json->get_integer( `/usage/cache_creation_input_tokens` ).
        " the first text block - thinking blocks come first
        DATA(lv_count) = lines( lo_json->members( `/content` ) ).
        DO lv_count TIMES.
          IF lo_json->get_string( |/content/{ sy-index }/type| ) = `text`.
            result-text = lo_json->get_string( |/content/{ sy-index }/text| ).
            EXIT.
          ENDIF.
        ENDDO.
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
          EXPORTING
            kind     = z2ui5_cx_agent_llm=>cs_kind-response
            text     = `the answer of the Claude API is not a message`
            previous = lx.
    ENDTRY.

  ENDMETHOD.

  METHOD z2ui5_if_agent_llm~chat.

    DATA(ls_http) = build_request( is_request ).
    DATA(ls_response) = z2ui5_cl_agent_llm=>get_http( )->post( ls_http ).
    result = parse_response( ls_response ).

  ENDMETHOD.

ENDCLASS.
