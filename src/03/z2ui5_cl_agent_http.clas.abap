"! ABAP Standard entry of the agent endpoint - the handler of the ICF node
"! /sap/bc/z2ui5_agent (shipped in this package). Everything happens in
"! z2ui5_cl_agent_mcp; the logon of the request is the user the agent
"! runs as.
CLASS z2ui5_cl_agent_http DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_http_extension.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_http IMPLEMENTATION.

  METHOD if_http_extension~handle_request.

    z2ui5_cl_agent_mcp=>run( server ).

  ENDMETHOD.

ENDCLASS.
