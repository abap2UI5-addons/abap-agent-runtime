"! The settings of the agent endpoint, as an abap2UI5 app: switch the
"! endpoint on and off, allow or deny app classes, classify events
"! (allowed / confirm / forbidden) on top of what the apps say, mark fields
"! whose values the audit log masks, maintain the administrators, set the
"! page a handover sends the user to, and clean up the audit log.
"! Start it with ?app_start=z2ui5_cl_agent_app_admin.
"!
"! Everybody may look; only an agent administrator may change anything.
"! The first administrator is added in the system - README, "Enabling the
"! endpoint". Every change is written to the audit log. Agents never reach
"! this app (z2ui5_cl_agent_settings=&gt;check_app refuses the addon's own
"! apps).
CLASS z2ui5_cl_agent_app_admin DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_rule,
        kind  TYPE string,
        app   TYPE string,
        item  TYPE string,
        value TYPE string,
        info  TYPE string,
      END OF ty_s_rule.
    TYPES ty_t_rule TYPE STANDARD TABLE OF ty_s_rule WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_app,
        app         TYPE string,
        description TYPE string,
        source      TYPE string,
      END OF ty_s_app.
    TYPES ty_t_app TYPE STANDARD TABLE OF ty_s_app WITH EMPTY KEY.

    DATA enabled      TYPE abap_bool.
    DATA url          TYPE string.
    DATA is_admin     TYPE abap_bool.
    DATA admin_hint   TYPE string.
    DATA t_rule       TYPE ty_t_rule.
    DATA t_app        TYPE ty_t_app.
    DATA new_kind     TYPE string.
    DATA new_app      TYPE string.
    DATA new_item     TYPE string.
    DATA new_value    TYPE string.
    DATA cleanup_days TYPE i.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS view_display.
    METHODS on_event.
    METHODS load.
    METHODS rule_add.
    METHODS check_change
      RETURNING
        VALUE(result) TYPE abap_bool.
    METHODS audit
      IMPORTING
        text TYPE string.
    METHODS model_init.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_app_admin IMPLEMENTATION.

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
            )->a( n = `xmlns:core`   v = `sap.ui.core`
            )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
            )->a( n = `displayBlock` v = `true`
            )->a( n = `height`       v = `100%` ).

    DATA(page) = view->ele( `Shell`
        )->ele( `Page`
            )->a( n = `title` v = `abap2UI5 agent - settings` ).

    page->tag( `MessageStrip`
        )->a( n = `text`     v = client->_bind( admin_hint )
        )->a( n = `type`     v = `Warning`
        )->a( n = `showIcon` v = `true`
        )->a( n = `visible`  b = xsdbool( is_admin = abap_false ) ).

    page->ele( n = `SimpleForm` ns = `form`
        )->a( n = `title`    v = `Endpoint`
        )->a( n = `editable` b = is_admin
        )->ele( n = `content` ns = `form`

            )->tag( `Label`
                )->a( n = `text` v = `Agents may operate apps`
            )->tag( `Switch`
                )->a( n = `state`   v = client->_bind( enabled )
                )->a( n = `enabled` b = is_admin
                )->a( n = `change`  v = client->_event( `ENABLED` )
            )->tag( `Label`
                )->a( n = `text` v = `Handover page`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( url )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_settings=>c_default_url
            )->tag( `Button`
                )->a( n = `text`    v = `Save`
                )->a( n = `enabled` b = is_admin
                )->a( n = `press`   v = client->_event( `URL_SAVE` ) ).

    DATA(rules) = page->ele( `Table`
        )->a( n = `headerText` v = `Rules`
        )->a( n = `items`      v = client->_bind( t_rule ) ).

    rules->ele( `columns`
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Kind`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `App (pattern)`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Event / field / user`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Value`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Meaning`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `` ).

    rules->ele( `items`
        )->ele( `ColumnListItem`
            )->ele( `cells`

                )->tag( `Text`
                    )->a( n = `text` v = `{KIND}`
                )->tag( `Text`
                    )->a( n = `text` v = `{APP}`
                )->tag( `Text`
                    )->a( n = `text` v = `{ITEM}`
                )->tag( `Text`
                    )->a( n = `text` v = `{VALUE}`
                )->tag( `Text`
                    )->a( n = `text` v = `{INFO}`
                )->tag( `Button`
                    )->a( n = `icon`    v = `sap-icon://delete`
                    )->a( n = `tooltip` v = `Remove the rule`
                    )->a( n = `visible` b = is_admin
                    )->a( n = `press`   v = client->_event( val   = `RULE_DELETE`
                                                            t_arg = VALUE #( ( `${KIND}` ) ( `${APP}` ) ( `${ITEM}` ) ) ) ).

    page->ele( n = `SimpleForm` ns = `form`
        )->a( n = `title`    v = `Add a rule`
        )->a( n = `editable` v = `true`
        )->a( n = `visible`  b = is_admin
        )->ele( n = `content` ns = `form`

            )->tag( `Label`
                )->a( n = `text` v = `Kind`
            )->ele( `Select`
                )->a( n = `selectedKey` v = client->_bind( new_kind )
                )->ele( `items`

                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `APP`
                        )->a( n = `text` v = `APP - allow or deny app classes`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `EVENT`
                        )->a( n = `text` v = `EVENT - allowed, confirm or forbidden`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `SENSITIVE`
                        )->a( n = `text` v = `SENSITIVE - mask a field in the audit log`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `ADMIN`
                        )->a( n = `text` v = `ADMIN - an administrator (user in App)`

                )->end(
            )->end(

            )->tag( `Label`
                )->a( n = `text` v = `App / user`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( new_app )
                )->a( n = `placeholder` v = `Z_MY_APP or ZCL_SALES_* or a user name`
            )->tag( `Label`
                )->a( n = `text` v = `Event / field`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( new_item )
                )->a( n = `placeholder` v = `DELETE* or /MS_DATA/IBAN`
            )->tag( `Label`
                )->a( n = `text` v = `Value`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( new_value )
                )->a( n = `placeholder` v = `allow, deny, allowed, confirm or forbidden`
            )->tag( `Button`
                )->a( n = `text`  v = `Add`
                )->a( n = `type`  v = `Emphasized`
                )->a( n = `press` v = client->_event( `RULE_ADD` ) ).

    DATA(apps) = page->ele( `Table`
        )->a( n = `headerText` v = `Apps an agent may start`
        )->a( n = `items`      v = client->_bind( t_app ) ).

    apps->ele( `columns`
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `App`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Description`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Opted in by` ).

    apps->ele( `items`
        )->ele( `ColumnListItem`
            )->ele( `cells`

                )->tag( `Text`
                    )->a( n = `text` v = `{APP}`
                )->tag( `Text`
                    )->a( n = `text` v = `{DESCRIPTION}`
                )->tag( `Text`
                    )->a( n = `text` v = `{SOURCE}` ).

    page->ele( n = `SimpleForm` ns = `form`
        )->a( n = `title`    v = `Audit log housekeeping`
        )->a( n = `editable` v = `true`
        )->a( n = `visible`  b = is_admin
        )->ele( n = `content` ns = `form`

            )->tag( `Label`
                )->a( n = `text` v = `Delete entries older than (days)`
            )->tag( `StepInput`
                )->a( n = `value` v = client->_bind( cleanup_days )
                )->a( n = `min`   v = `1`
            )->tag( `Button`
                )->a( n = `text`  v = `Delete`
                )->a( n = `press` v = client->_event( `CLEANUP` ) ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

  METHOD check_change.

    " the app checks its own authority: whoever may start it may look,
    " only an agent administrator may change
    result = z2ui5_cl_agent_settings=>check_admin( ).
    IF result = abap_false.
      client->message_box_display( text = `Only an agent administrator may change the settings`
                                   type = `error` ).
    ENDIF.

  ENDMETHOD.

  METHOD audit.

    z2ui5_cl_agent_audit=>log( VALUE #( operation = `settings`
                                        app       = `Z2UI5_CL_AGENT_APP_ADMIN`
                                        outcome   = z2ui5_cl_agent_audit=>cs_outcome-ok
                                        args      = text ) ).

  ENDMETHOD.

  METHOD on_event.

    CASE client->get_event( ).

      WHEN `ENABLED`.
        IF check_change( ) = abap_false.
          load( ).
          RETURN.
        ENDIF.
        z2ui5_cl_agent_settings=>set_enabled( enabled ).
        audit( |endpoint { COND #( WHEN enabled = abap_true THEN `enabled` ELSE `disabled` ) }| ).
        client->message_toast_display( COND #( WHEN enabled = abap_true
                                               THEN `Agents may operate the enabled apps now`
                                               ELSE `The agent endpoint is disabled` ) ).

      WHEN `URL_SAVE`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        z2ui5_cl_agent_settings=>save( kind  = z2ui5_cl_agent_settings=>cs_kind-url
                                       app   = `*`
                                       value = url ).
        audit( |handover page { url }| ).
        client->message_toast_display( `Handover page saved` ).

      WHEN `RULE_ADD`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        rule_add( ).

      WHEN `RULE_DELETE`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        DATA(lv_kind) = client->get_event_arg( ).
        DATA(lv_app) = client->get_event_arg( 2 ).
        DATA(lv_item) = client->get_event_arg( 3 ).
        READ TABLE t_rule INTO DATA(ls_rule) WITH KEY kind = lv_kind app = lv_app item = lv_item. "#EC CI_SORTSEQ
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        z2ui5_cl_agent_settings=>remove( kind = ls_rule-kind
                                         app  = ls_rule-app
                                         item = ls_rule-item ).
        audit( |rule removed: { ls_rule-kind } { ls_rule-app } { ls_rule-item } { ls_rule-value }| ).
        load( ).

      WHEN `CLEANUP`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        DATA(lv_count) = z2ui5_cl_agent_audit=>cleanup( cleanup_days ).
        audit( |audit log cleanup: { lv_count } entries older than { cleanup_days } days| ).
        client->message_toast_display( |{ lv_count } entries deleted| ).

    ENDCASE.

  ENDMETHOD.

  METHOD rule_add.

    DATA(lv_kind) = to_upper( condense( new_kind ) ).
    DATA(lv_app) = to_upper( condense( new_app ) ).
    DATA(lv_item) = to_upper( condense( new_item ) ).
    DATA(lv_value) = to_lower( condense( new_value ) ).

    IF lv_app IS INITIAL.
      client->message_box_display( text = `Enter an app class, a pattern (ZCL_SALES_*) or * - for ADMIN a user name`
                                   type = `error` ).
      RETURN.
    ENDIF.
    CASE lv_kind.
      WHEN z2ui5_cl_agent_settings=>cs_kind-app.
        IF lv_value <> z2ui5_cl_agent_settings=>cs_app_rule-allow AND lv_value <> z2ui5_cl_agent_settings=>cs_app_rule-deny.
          client->message_box_display( text = `An APP rule has the value allow or deny`
                                       type = `error` ).
          RETURN.
        ENDIF.
        CLEAR lv_item.
      WHEN z2ui5_cl_agent_settings=>cs_kind-event.
        IF lv_item IS INITIAL OR ( lv_value <> z2ui5_if_agent_app=>cs_policy-allowed
            AND lv_value <> z2ui5_if_agent_app=>cs_policy-confirm AND lv_value <> z2ui5_if_agent_app=>cs_policy-forbidden ).
          client->message_box_display( text = `An EVENT rule names an event (or a pattern) and has the value allowed, confirm or forbidden`
                                       type = `error` ).
          RETURN.
        ENDIF.
      WHEN z2ui5_cl_agent_settings=>cs_kind-sensitive.
        IF lv_item IS INITIAL.
          client->message_box_display( text = `A SENSITIVE rule names a field - its model path or name, or a pattern`
                                       type = `error` ).
          RETURN.
        ENDIF.
        lv_value = `X`.
      WHEN z2ui5_cl_agent_settings=>cs_kind-admin.
        CLEAR lv_item.
        lv_value = `X`.
      WHEN OTHERS.
        client->message_box_display( text = `Choose the kind of the rule`
                                     type = `error` ).
        RETURN.
    ENDCASE.

    z2ui5_cl_agent_settings=>save( kind  = lv_kind
                                   app   = lv_app
                                   item  = lv_item
                                   value = lv_value ).
    audit( |rule added: { lv_kind } { lv_app } { lv_item } { lv_value }| ).
    CLEAR: new_app, new_item, new_value.
    load( ).
    client->message_toast_display( `Rule added` ).

  ENDMETHOD.

  METHOD load.

    z2ui5_cl_agent_settings=>refresh( ).
    enabled = z2ui5_cl_agent_settings=>check_enabled( ).
    is_admin = z2ui5_cl_agent_settings=>check_admin( ).
    admin_hint = COND #( WHEN z2ui5_cl_agent_settings=>check_admin_defined( ) = abap_false
                         THEN |No agent administrator is defined yet - nothing can be changed here. Run | &&
                              |z2ui5_cl_agent_settings=>admin_add( '{ sy-uname }' ) once in this system (README, "Enabling the endpoint").|
                         ELSE |{ sy-uname } is no agent administrator - the settings are shown read-only.| ).

    CLEAR: t_rule, url.
    LOOP AT z2ui5_cl_agent_settings=>get_all( ) INTO DATA(ls_setting).
      CASE ls_setting-kind.
        WHEN z2ui5_cl_agent_settings=>cs_kind-url.
          url = ls_setting-value.
          CONTINUE.
        WHEN z2ui5_cl_agent_settings=>cs_kind-enabled.
          CONTINUE.
      ENDCASE.
      INSERT VALUE #( kind  = ls_setting-kind
                      app   = ls_setting-app
                      item  = ls_setting-item
                      value = ls_setting-value
                      info  = SWITCH #( ls_setting-kind
                                        WHEN z2ui5_cl_agent_settings=>cs_kind-app
                                          THEN COND #( WHEN ls_setting-value = z2ui5_cl_agent_settings=>cs_app_rule-deny
                                                       THEN `never startable by an agent`
                                                       ELSE `startable without z2ui5_if_agent_app` )
                                        WHEN z2ui5_cl_agent_settings=>cs_kind-event
                                          THEN |{ ls_setting-value } - the stricter of this and the app's own rule wins|
                                        WHEN z2ui5_cl_agent_settings=>cs_kind-sensitive
                                          THEN `masked in the audit log`
                                        WHEN z2ui5_cl_agent_settings=>cs_kind-admin
                                          THEN `may change these settings` ) ) INTO TABLE t_rule.
    ENDLOOP.

    CLEAR t_app.
    TRY.
        LOOP AT z2ui5_cl_agent_settings=>get_apps( ) INTO DATA(ls_app).
          INSERT VALUE #( app         = ls_app-app
                          description = ls_app-description
                          source      = SWITCH #( ls_app-source
                                                  WHEN `interface` THEN `the app (z2ui5_if_agent_app)`
                                                  ELSE `a rule of these settings` ) ) INTO TABLE t_app.
        ENDLOOP.
      CATCH cx_root ##NO_HANDLER.
        " the class directory may not be readable - the list stays empty
    ENDTRY.

  ENDMETHOD.

  METHOD model_init.

    new_kind = z2ui5_cl_agent_settings=>cs_kind-event.
    cleanup_days = 90.
    load( ).

  ENDMETHOD.

ENDCLASS.
