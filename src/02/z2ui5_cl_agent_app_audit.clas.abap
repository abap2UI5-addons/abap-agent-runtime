"! The audit log of the agent endpoint, as an abap2UI5 app: every tool call
"! an agent made - when, as which SAP user, on which app and session, with
"! which event and arguments (sensitive values masked), and how it ended.
"! Start it with ?app_start=z2ui5_cl_agent_app_audit.
"!
"! Every user sees the calls made in their own name; an agent administrator
"! (z2ui5_cl_agent_settings=&gt;check_admin) sees everybody's. Agents never
"! reach this app (z2ui5_cl_agent_settings=&gt;check_app refuses the addon's
"! own apps).
CLASS z2ui5_cl_agent_app_audit DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_entry,
        id        TYPE string,
        time      TYPE string,
        uname     TYPE string,
        app       TYPE string,
        session   TYPE string,
        operation TYPE string,
        event     TYPE string,
        outcome   TYPE string,
        state     TYPE string,
        client    TYPE string,
        text      TYPE string,
        args      TYPE string,
      END OF ty_s_entry.
    TYPES ty_t_entry TYPE STANDARD TABLE OF ty_s_entry WITH EMPTY KEY.

    DATA t_entry   TYPE ty_t_entry.
    DATA search    TYPE string.
    DATA outcome   TYPE string.
    DATA all_users TYPE abap_bool.
    DATA is_admin  TYPE abap_bool.
    DATA title     TYPE string.
    DATA s_detail  TYPE ty_s_entry.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS view_display.
    METHODS popup_detail.
    METHODS on_event.
    METHODS load.
    METHODS model_init.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_app_audit IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      model_init( ).
      view_display( ).
    ELSEIF client->check_on_navigated( ).
      view_display( ).
    ELSEIF client->check_on_event( ).
      on_event( ).
    ENDIF.

  ENDMETHOD.

  METHOD view_display.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `View` ns = `mvc`
            )->a( n = `xmlns`        v = `sap.m`
            )->a( n = `xmlns:mvc`    v = `sap.ui.core.mvc`
            )->a( n = `displayBlock` v = `true`
            )->a( n = `height`       v = `100%` ).

    DATA(page) = view->ele( `Shell`
        )->ele( `Page`
            )->a( n = `title` v = client->_bind( title ) ).

    DATA(table) = page->ele( `Table`
        )->a( n = `items`            v = client->_bind( t_entry )
        )->a( n = `growing`          v = `true`
        )->a( n = `growingThreshold` v = `50` ).

    DATA(toolbar) = table->ele( `headerToolbar`
        )->ele( `OverflowToolbar` ).

    toolbar->tag( `SearchField`
        )->a( n = `value`       v = client->_bind( search )
        )->a( n = `search`      v = client->_event( `SEARCH` )
        )->a( n = `placeholder` v = `App, event, session, user or text`
        )->a( n = `width`       v = `20rem` ).

    toolbar->ele( `SegmentedButton`
        )->a( n = `selectedKey`     v = client->_bind( outcome )
        )->a( n = `selectionChange` v = client->_event( `SEARCH` )
        )->ele( `items`

            )->tag( `SegmentedButtonItem`
                )->a( n = `key`  v = `all`
                )->a( n = `text` v = `All`
            )->tag( `SegmentedButtonItem`
                )->a( n = `key`  v = `ok`
                )->a( n = `text` v = `OK`
            )->tag( `SegmentedButtonItem`
                )->a( n = `key`  v = `error`
                )->a( n = `text` v = `Refused` ).

    toolbar->tag( `ToolbarSpacer`
        )->tag( `CheckBox`
            )->a( n = `text`     v = `All users`
            )->a( n = `selected` v = client->_bind( all_users )
            )->a( n = `visible`  b = is_admin
            )->a( n = `select`   v = client->_event( `SEARCH` )
        )->tag( `Button`
            )->a( n = `icon`    v = `sap-icon://refresh`
            )->a( n = `tooltip` v = `Refresh`
            )->a( n = `press`   v = client->_event( `SEARCH` ) ).

    table->ele( `columns`
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Time`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `User`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `App`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Operation`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Event`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Outcome`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `MCP client` ).

    table->ele( `items`
        )->ele( `ColumnListItem`
            )->a( n = `type`  v = `Navigation`
            )->a( n = `press` v = client->_event( val = `DETAIL`
                                                  arg = `${ID}` )
            )->ele( `cells`

                )->tag( `Text`
                    )->a( n = `text` v = `{TIME}`
                )->tag( `Text`
                    )->a( n = `text` v = `{UNAME}`
                )->tag( `Text`
                    )->a( n = `text` v = `{APP}`
                )->tag( `Text`
                    )->a( n = `text` v = `{OPERATION}`
                )->tag( `Text`
                    )->a( n = `text` v = `{EVENT}`
                )->tag( `ObjectStatus`
                    )->a( n = `text`  v = `{OUTCOME}`
                    )->a( n = `state` v = `{STATE}`
                )->tag( `Text`
                    )->a( n = `text` v = `{CLIENT}` ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

  METHOD popup_detail.

    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `FragmentDefinition` ns = `core`
            )->a( n = `xmlns`      v = `sap.m`
            )->a( n = `xmlns:core` v = `sap.ui.core`
            )->a( n = `xmlns:form` v = `sap.ui.layout.form` ).

    DATA(dialog) = popup->ele( `Dialog`
        )->a( n = `title`        v = `Agent call`
        )->a( n = `contentWidth` v = `40rem` ).

    dialog->ele( `content`
        )->ele( n = `SimpleForm` ns = `form`
            )->a( n = `editable` v = `false`
            )->ele( n = `content` ns = `form`

                )->tag( `Label`
                    )->a( n = `text` v = `Time`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-time )
                )->tag( `Label`
                    )->a( n = `text` v = `User`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-uname )
                )->tag( `Label`
                    )->a( n = `text` v = `App`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-app )
                )->tag( `Label`
                    )->a( n = `text` v = `Session`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-session )
                )->tag( `Label`
                    )->a( n = `text` v = `Operation`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-operation )
                )->tag( `Label`
                    )->a( n = `text` v = `Event`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-event )
                )->tag( `Label`
                    )->a( n = `text` v = `Outcome`
                )->tag( `ObjectStatus`
                    )->a( n = `text`  v = client->_bind( s_detail-outcome )
                    )->a( n = `state` v = client->_bind( s_detail-state )
                )->tag( `Label`
                    )->a( n = `text` v = `MCP client`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-client )
                )->tag( `Label`
                    )->a( n = `text` v = `Message`
                )->tag( `Text`
                    )->a( n = `text` v = client->_bind( s_detail-text )
                )->tag( `Label`
                    )->a( n = `text` v = `Arguments`
                )->tag( `TextArea`
                    )->a( n = `value`    v = client->_bind( s_detail-args )
                    )->a( n = `editable` v = `false`
                    )->a( n = `rows`     v = `6`
                    )->a( n = `width`    v = `100%` ).

    dialog->ele( `buttons`

        )->tag( `Button`
            )->a( n = `text`  v = `Close`
            )->a( n = `press` v = client->_event( `DETAIL_CLOSE` ) ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

  METHOD on_event.

    CASE client->get_event( ).

      WHEN `SEARCH`.
        load( ).

      WHEN `DETAIL`.
        DATA(lv_id) = client->get_event_arg( ).
        READ TABLE t_entry INTO s_detail WITH KEY id = lv_id. "#EC CI_SORTSEQ
        IF sy-subrc = 0.
          popup_detail( ).
        ENDIF.

      WHEN `DETAIL_CLOSE`.
        client->popup_destroy( ).

    ENDCASE.

  ENDMETHOD.

  METHOD load.

    DATA lv_ts TYPE string.

    " asked on every search, not remembered in the draft: an administrator
    " removed meanwhile sees only the own calls again
    is_admin = z2ui5_cl_agent_settings=>check_admin( ).
    DATA(lt_log) = COND z2ui5_cl_agent_audit=>ty_t_log( WHEN is_admin = abap_true AND all_users = abap_true
                                                       THEN z2ui5_cl_agent_audit=>read( )
                                                       ELSE z2ui5_cl_agent_audit=>read( uname = sy-uname ) ).
    DATA(lv_search) = to_upper( condense( search ) ).
    CLEAR t_entry.
    LOOP AT lt_log INTO DATA(ls_log).
      IF outcome IS NOT INITIAL AND outcome <> `all` AND ls_log-outcome <> outcome.
        CONTINUE.
      ENDIF.
      IF lv_search IS NOT INITIAL.
        DATA(lv_hay) = to_upper( |{ ls_log-app } { ls_log-event } { ls_log-session_id } { ls_log-uname } { ls_log-text } { ls_log-operation }| ).
        IF find( val = lv_hay
                 sub = lv_search ) < 0.
          CONTINUE.
        ENDIF.
      ENDIF.
      lv_ts = |{ ls_log-timestampl }|.
      INSERT VALUE #( id        = ls_log-id
                      time      = COND #( WHEN strlen( lv_ts ) >= 14
                                          THEN |{ lv_ts(4) }-{ lv_ts+4(2) }-{ lv_ts+6(2) } { lv_ts+8(2) }:{ lv_ts+10(2) }:{ lv_ts+12(2) } UTC|
                                          ELSE lv_ts )
                      uname     = ls_log-uname
                      app       = ls_log-app
                      session   = ls_log-session_id
                      operation = ls_log-operation
                      event     = ls_log-event
                      outcome   = ls_log-outcome
                      state     = COND #( WHEN ls_log-outcome = z2ui5_cl_agent_audit=>cs_outcome-ok THEN `Success` ELSE `Error` )
                      client    = ls_log-mcp_client
                      text      = ls_log-text
                      args      = ls_log-args ) INTO TABLE t_entry.
    ENDLOOP.
    title = |Agent audit log - { lines( t_entry ) } call(s){ COND #( WHEN is_admin = abap_true AND all_users = abap_true
                                                                    THEN `, all users`
                                                                    ELSE |, user { sy-uname }| ) }|.

  ENDMETHOD.

  METHOD model_init.

    outcome = `all`.
    load( ).

  ENDMETHOD.

ENDCLASS.
