"! Opt-in of an abap2UI5 app for AI agents (the agent addon's MCP endpoint).
"!
"! An app class that implements this interface next to z2ui5_if_app is
"! listed by app_list and can be started by app_start - nothing else is,
"! unless an administrator allows it explicitly in the agent settings
"! (z2ui5_cl_agent_app_admin). The agent always runs as the SAP user who
"! called the endpoint, through the app's own main( ): the same
"! validation, the same authority checks as in the browser.
"!
"! describe( ) is where the app tells agents what it is and which of its
"! events an agent must not fire on its own. An empty implementation is
"! fine - every event is allowed then:
"!
"!   METHOD z2ui5_if_agent_app~describe.
"!     result-description = `Create and change sales orders`.
"!     result-t_event = VALUE #( ( event = `DELETE*` policy = z2ui5_if_agent_app=&gt;cs_policy-forbidden )
"!                               ( event = `POST`    policy = z2ui5_if_agent_app=&gt;cs_policy-confirm ) ).
"!     result-t_sensitive = VALUE #( ( `/MS_LOGIN/PASSWORD` ) ).
"!   ENDMETHOD.
"!
"! describe( ) runs on a fresh instance of the class (it needs a public
"! constructor without mandatory parameters - every abap2UI5 app has one),
"! never on the running app: return what is true for the class, not for a
"! state of it.
INTERFACE z2ui5_if_agent_app PUBLIC.

  CONSTANTS:
    "! What an agent may do with an event.
    "!   allowed   - an agent fires it like a user presses the button
    "!   confirm   - only a human may fire it: app_act refuses and hands over
    "!               the URL of the draft, so the user opens the very screen
    "!               the agent prepared in the browser and presses the button
    "!   forbidden - an agent never fires it; app_act refuses
    BEGIN OF cs_policy,
      allowed   TYPE string VALUE `allowed`,
      confirm   TYPE string VALUE `confirm`,
      forbidden TYPE string VALUE `forbidden`,
    END OF cs_policy.

  TYPES:
    "! One event rule. event is the event name or a pattern (CP: DELETE*,
    "! *_POST); the first rule that matches decides for this app.
    BEGIN OF ty_s_event,
      event  TYPE string,
      policy TYPE string,
    END OF ty_s_event.
  TYPES ty_t_event TYPE STANDARD TABLE OF ty_s_event WITH EMPTY KEY.

  TYPES:
    "! description: one sentence for app_list. t_event: event rules (see
    "! ty_s_event). default_policy: the policy of an event no rule matches -
    "! allowed when empty. t_sensitive: model paths or names (CP patterns:
    "! /MS_LOGIN/PASSWORD, *IBAN*) whose values the audit log masks.
    BEGIN OF ty_s_info,
      description    TYPE string,
      t_event        TYPE ty_t_event,
      default_policy TYPE string,
      t_sensitive    TYPE string_table,
    END OF ty_s_info.

  METHODS describe
    RETURNING
      VALUE(result) TYPE ty_s_info.

ENDINTERFACE.
