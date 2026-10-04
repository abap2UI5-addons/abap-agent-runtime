"! A large language model, as the agent addon's AI-at-runtime features use
"! it (generative UI - z2ui5_cl_agent_genui, the in-app copilot -
"! z2ui5_cl_agent_assist): one chat call - a system prompt, the messages,
"! optionally a JSON schema the answer must follow (structured output) and
"! an effort - and one answer.
"!
"! Nobody calls an implementation directly: z2ui5_cl_agent_llm=&gt;create( )
"! returns the configured one wrapped in the addon's own checks - a refusal
"! or a cut-off answer raises, a structured answer arrives parsed, every
"! call is audited. The addon ships z2ui5_cl_agent_llm_anthropic (the Claude
"! Messages API) and z2ui5_cl_agent_llm_double (canned answers, for unit
"! tests). To route through SAP AI Core / the Generative AI Hub, Amazon
"! Bedrock or a gateway of your own, implement this interface in a class
"! of your own and enter its name as the provider in the agent settings
"! (z2ui5_cl_agent_app_admin) - it needs a public constructor without
"! mandatory parameters.
"!
"! An implementation:
"!   - sends system, t_message and, when schema is filled, asks for an
"!     answer that is JSON matching that schema
"!   - answers text (the JSON text for a schema), stop_reason in the
"!     vocabulary of cs_stop, usage and model as far as the service tells
"!   - raises z2ui5_cx_agent_llm for a failed call (HTTP error, timeout,
"!     unreadable answer) with retryable set for a transient failure (429,
"!     5xx, timeout); it need not check stop_reason itself - the wrapper
"!     refuses a refusal and a max_tokens answer
"!   - never logs the prompt - auditing is the wrapper's job.
INTERFACE z2ui5_if_agent_llm PUBLIC.

  CONSTANTS:
    BEGIN OF cs_role,
      user      TYPE string VALUE `user`,
      assistant TYPE string VALUE `assistant`,
    END OF cs_role.

  CONSTANTS:
    "! How much the model thinks before it answers. low is the default of
    "! the addon: generated views and copilot answers are interactive.
    BEGIN OF cs_effort,
      low    TYPE string VALUE `low`,
      medium TYPE string VALUE `medium`,
      high   TYPE string VALUE `high`,
      xhigh  TYPE string VALUE `xhigh`,
      max    TYPE string VALUE `max`,
    END OF cs_effort.

  CONSTANTS:
    "! Why the model stopped. Only end_turn (and stop_sequence) is an answer;
    "! refusal and max_tokens are errors (z2ui5_cx_agent_llm).
    BEGIN OF cs_stop,
      end_turn      TYPE string VALUE `end_turn`,
      stop_sequence TYPE string VALUE `stop_sequence`,
      max_tokens    TYPE string VALUE `max_tokens`,
      refusal       TYPE string VALUE `refusal`,
    END OF cs_stop.

  TYPES:
    BEGIN OF ty_s_message,
      role    TYPE string,
      content TYPE string,
    END OF ty_s_message.
  TYPES ty_t_message TYPE STANDARD TABLE OF ty_s_message WITH EMPTY KEY.

  TYPES:
    "! purpose / app: who asks (genui, copilot, test / the abap2UI5 app
    "! class) - for the audit log, never sent. schema: a JSON schema as JSON
    "! text - the answer is then JSON matching it; empty for free text.
    "! effort, max_tokens: empty / 0 for the settings.
    BEGIN OF ty_s_request,
      purpose    TYPE string,
      app        TYPE string,
      system     TYPE string,
      t_message  TYPE ty_t_message,
      schema     TYPE string,
      effort     TYPE string,
      max_tokens TYPE i,
    END OF ty_s_request.

  TYPES:
    BEGIN OF ty_s_usage,
      input_tokens  TYPE i,
      output_tokens TYPE i,
      cache_read    TYPE i,
      cache_write   TYPE i,
    END OF ty_s_usage.

  TYPES:
    "! text: the answer (the JSON text when a schema was requested). json:
    "! that text parsed - filled by z2ui5_cl_agent_llm, an implementation
    "! may leave it initial. model: the model that answered (after a
    "! server-side fallback, the fallback model).
    BEGIN OF ty_s_response,
      id          TYPE string,
      model       TYPE string,
      text        TYPE string,
      json        TYPE REF TO z2ui5_if_ajson,
      stop_reason TYPE string,
      usage       TYPE ty_s_usage,
    END OF ty_s_response.

  METHODS chat
    IMPORTING
      is_request    TYPE ty_s_request
    RETURNING
      VALUE(result) TYPE ty_s_response
    RAISING
      z2ui5_cx_agent_llm.

ENDINTERFACE.
