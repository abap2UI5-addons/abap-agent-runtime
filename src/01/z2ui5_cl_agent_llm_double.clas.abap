"! A language model with canned answers - the test double of
"! z2ui5_if_agent_llm. Queue answers (or failures), hand it to
"! z2ui5_cl_agent_llm=&gt;set_double( ), and every chat call takes the next
"! one and records the request it got:
"!
"!   DATA(double) = NEW z2ui5_cl_agent_llm_double( ).
"!   double-&gt;add_answer( `{"answer":"...","proposal":...}` ).
"!   z2ui5_cl_agent_llm=&gt;set_double( double ).
"!   ... the feature under test ...
"!   cl_abap_unit_assert=&gt;assert_char_cp( act = double-&gt;mt_request[ 1 ]-system exp = `*...*` ).
"!   z2ui5_cl_agent_llm=&gt;set_double( ).
"!
"! No answer left is a failure of kind config - a test that asks more
"! often than it planned for notices.
CLASS z2ui5_cl_agent_llm_double DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_agent_llm.

    TYPES:
      BEGIN OF ty_s_canned,
        text        TYPE string,
        stop_reason TYPE string,
        error_kind  TYPE string,
        http_status TYPE i,
        retryable   TYPE abap_bool,
      END OF ty_s_canned.
    TYPES ty_t_canned TYPE STANDARD TABLE OF ty_s_canned WITH EMPTY KEY.
    TYPES ty_t_request TYPE STANDARD TABLE OF z2ui5_if_agent_llm=>ty_s_request WITH EMPTY KEY.

    "! The requests of every chat call so far, in order.
    DATA mt_request TYPE ty_t_request READ-ONLY.
    DATA mt_canned TYPE ty_t_canned READ-ONLY.

    "! Queue an answer - text is the JSON for a structured request.
    METHODS add_answer
      IMPORTING
        text          TYPE clike
        stop_reason   TYPE clike DEFAULT z2ui5_if_agent_llm=>cs_stop-end_turn
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_llm_double.

    "! Queue a failed call (z2ui5_cx_agent_llm of that kind).
    METHODS add_error
      IMPORTING
        kind          TYPE clike DEFAULT z2ui5_cx_agent_llm=>cs_kind-http
        http_status   TYPE i DEFAULT 503
        retryable     TYPE abap_bool DEFAULT abap_true
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_llm_double.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_llm_double IMPLEMENTATION.

  METHOD add_answer.

    INSERT VALUE #( text        = text
                    stop_reason = stop_reason ) INTO TABLE mt_canned.
    result = me.

  ENDMETHOD.

  METHOD add_error.

    INSERT VALUE #( error_kind  = kind
                    http_status = http_status
                    retryable   = retryable ) INTO TABLE mt_canned.
    result = me.

  ENDMETHOD.

  METHOD z2ui5_if_agent_llm~chat.

    INSERT is_request INTO TABLE mt_request.
    IF mt_canned IS INITIAL.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind = z2ui5_cx_agent_llm=>cs_kind-config
          text = `the language model double has no canned answer left`.
    ENDIF.
    DATA(ls_canned) = mt_canned[ 1 ].
    DELETE mt_canned INDEX 1.
    IF ls_canned-error_kind IS NOT INITIAL.
      RAISE EXCEPTION TYPE z2ui5_cx_agent_llm
        EXPORTING
          kind        = ls_canned-error_kind
          text        = |canned failure ({ ls_canned-error_kind } { ls_canned-http_status })|
          http_status = ls_canned-http_status
          retryable   = ls_canned-retryable.
    ENDIF.
    result = VALUE #( id          = |msg_double_{ lines( mt_request ) }|
                      model       = `double`
                      text        = ls_canned-text
                      stop_reason = ls_canned-stop_reason
                      usage       = VALUE #( input_tokens  = strlen( is_request-system ) DIV 4 + 1
                                             output_tokens = strlen( ls_canned-text ) DIV 4 + 1 ) ).

  ENDMETHOD.

ENDCLASS.
