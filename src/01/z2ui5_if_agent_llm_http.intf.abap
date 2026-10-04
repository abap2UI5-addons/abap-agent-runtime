"! The outbound HTTP call of a language model provider - one POST, the
"! platform's HTTP client behind it. It is the one place where ABAP
"! Standard and ABAP Cloud differ, so it has two implementations, shipped
"! like the two HTTP entries of the endpoint: z2ui5_cl_agent_llm_std
"! (package 03, cl_http_client - an SM59 destination or a URL) and
"! z2ui5_cl_agent_llm_cloud (package 04, cl_web_http_client_manager - a
"! communication arrangement or a URL). z2ui5_cl_agent_llm=&gt;get_http( )
"! finds the one installed; unit tests pass a double.
INTERFACE z2ui5_if_agent_llm_http PUBLIC.

  TYPES:
    BEGIN OF ty_s_header,
      name  TYPE string,
      value TYPE string,
    END OF ty_s_header.
  TYPES ty_t_header TYPE STANDARD TABLE OF ty_s_header WITH EMPTY KEY.

  TYPES:
    "! url: the full URL, or - with destination - the path below it.
    "! destination: ABAP Standard an SM59 destination (type G); ABAP Cloud a
    "! communication arrangement as SCENARIO/SERVICE_ID (outbound service
    "! of type HTTP), optionally SCENARIO/SERVICE_ID/COMM_SYSTEM. timeout in
    "! seconds.
    BEGIN OF ty_s_request,
      url         TYPE string,
      destination TYPE string,
      t_header    TYPE ty_t_header,
      body        TYPE string,
      timeout     TYPE i,
    END OF ty_s_request.

  TYPES:
    BEGIN OF ty_s_response,
      status TYPE i,
      reason TYPE string,
      body   TYPE string,
    END OF ty_s_response.

  "! One POST. Raises z2ui5_cx_agent_llm (kind http, http_status 0,
  "! retryable) when no answer came; an answer with any status is returned.
  METHODS post
    IMPORTING
      is_request    TYPE ty_s_request
    RETURNING
      VALUE(result) TYPE ty_s_response
    RAISING
      z2ui5_cx_agent_llm.

ENDINTERFACE.
