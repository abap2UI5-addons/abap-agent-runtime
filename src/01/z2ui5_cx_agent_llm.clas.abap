"! A failed call of a large language model (z2ui5_if_agent_llm): kind says
"! what failed, retryable whether the same call may succeed later (HTTP 429,
"! 5xx, 529, a timeout) - a refusal, a cut-off answer, a 4xx or a missing
"! configuration never does.
CLASS z2ui5_cx_agent_llm DEFINITION PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      "! config: not configured / provider class unusable; http: the call
      "! failed (http_status, 0 when no answer came); refusal: the model
      "! declined (stop_reason refusal); max_tokens: the answer was cut off;
      "! response: the answer is unreadable or not the requested JSON
      BEGIN OF cs_kind,
        config     TYPE string VALUE `config`,
        http       TYPE string VALUE `http`,
        refusal    TYPE string VALUE `refusal`,
        max_tokens TYPE string VALUE `max_tokens`,
        response   TYPE string VALUE `response`,
      END OF cs_kind.

    DATA kind TYPE string READ-ONLY.
    DATA text TYPE string READ-ONLY.
    DATA http_status TYPE i READ-ONLY.
    DATA retryable TYPE abap_bool READ-ONLY.

    METHODS constructor
      IMPORTING
        textid      LIKE textid OPTIONAL
        !previous   LIKE previous OPTIONAL
        kind        TYPE clike OPTIONAL
        text        TYPE clike OPTIONAL
        http_status TYPE i OPTIONAL
        retryable   TYPE abap_bool OPTIONAL.

    METHODS get_text REDEFINITION.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cx_agent_llm IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( textid   = textid
                        previous = previous ).
    me->kind = kind.
    me->text = text.
    me->http_status = http_status.
    me->retryable = retryable.

  ENDMETHOD.

  METHOD get_text.

    result = text.
    IF result IS INITIAL AND previous IS BOUND.
      result = previous->get_text( ).
    ENDIF.
    IF result IS INITIAL.
      result = |the language model call failed ({ kind })|.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
