"! ABAP Cloud entry of the agent endpoint - the handler class of an HTTP
"! service (README, "ABAP Cloud"). Everything happens in
"! z2ui5_cl_agent_mcp; the logon of the request (the communication
"! arrangement's inbound user, or the business user by principal
"! propagation) is the user the agent runs as.
CLASS z2ui5_cl_agent_http_cloud DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_http_service_extension.

  PROTECTED SECTION.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_http_cloud IMPLEMENTATION.

  METHOD if_http_service_extension~handle_request.

    z2ui5_cl_agent_mcp=>run( req = request
                             res = response ).

  ENDMETHOD.

ENDCLASS.
