"! The settings of the agent endpoint, as an abap2UI5 app: switch the
"! endpoint on and off, allow or deny app classes, classify events
"! (allowed / confirm / forbidden) on top of what the apps say, mark fields
"! whose values the audit log masks, maintain the administrators, set the
"! page a handover sends the user to, configure the language model of the
"! AI features (generative UI, the in-app copilot) and clean up the audit
"! log. The API key is write-only: the app shows whether one is set, never
"! the key.
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
    TYPES ty_t_rule TYPE STANDARD TABLE OF ty_s_rule WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_app,
        app         TYPE string,
        description TYPE string,
        source      TYPE string,
      END OF ty_s_app.
    TYPES ty_t_app TYPE STANDARD TABLE OF ty_s_app WITH DEFAULT KEY.

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

    DATA llm_provider      TYPE string.
    DATA llm_model         TYPE string.
    DATA llm_effort        TYPE string.
    DATA llm_max_tokens    TYPE string.
    DATA llm_timeout       TYPE string.
    DATA llm_url           TYPE string.
    DATA llm_destination   TYPE string.
    DATA llm_key           TYPE string.
    DATA llm_key_state     TYPE string.
    DATA llm_beta          TYPE string.
    DATA llm_fallback      TYPE abap_bool.
    DATA llm_log_prompts   TYPE abap_bool.
    DATA llm_genui_samples TYPE abap_bool.
    DATA llm_genui_repair  TYPE abap_bool.
    DATA llm_copilot       TYPE abap_bool.
    DATA llm_copilot_act   TYPE abap_bool.

  PROTECTED SECTION.

    TYPES:
      BEGIN OF ty_s_llm_item,
        item  TYPE string,
        value TYPE string,
      END OF ty_s_llm_item.
    TYPES ty_t_llm_item TYPE STANDARD TABLE OF ty_s_llm_item WITH DEFAULT KEY.

    DATA client TYPE REF TO z2ui5_if_client.
    "! The language model settings as the form showed them when it was
    "! loaded - Save writes only what was changed since.
    DATA mt_llm_shown TYPE ty_t_llm_item.

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
    METHODS llm_save.
    "! The form's language model settings as they are stored (key aside).
    METHODS llm_form
      RETURNING
        VALUE(result) TYPE ty_t_llm_item.
    METHODS llm_test.

  PRIVATE SECTION.

    "! This class's name, read at run time - a namespace rename rewrites the
    "! class, never a literal naming it.
    METHODS app_name
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_app_admin IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ) IS NOT INITIAL.
      model_init( ).
      view_display( ).
    ELSEIF client->check_on_navigated( ) IS NOT INITIAL.
      view_display( ).
    ELSEIF client->check_on_event( ) IS NOT INITIAL.
      on_event( ).
      " the key is write-only: whatever the event, a typed key is neither
      " kept in the draft of this app nor sent back to the browser
      CLEAR llm_key.
      " the settings and their audit entries - abap2UI5 rolls back what
      " main( ) leaves open
      COMMIT WORK.
    ENDIF.

  ENDMETHOD.

  METHOD view_display.

    DATA view TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA page TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA temp2 TYPE xsdboolean.
    DATA rules TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA temp1 TYPE string_table.
    DATA apps TYPE REF TO z2ui5_cl_ui5_view_builder.
    view = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `View` ns = `mvc`
            )->a( n = `xmlns`        v = `sap.m`
            )->a( n = `xmlns:mvc`    v = `sap.ui.core.mvc`
            )->a( n = `xmlns:core`   v = `sap.ui.core`
            )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
            )->a( n = `displayBlock` v = `true`
            )->a( n = `height`       v = `100%` ).


    page = view->ele( `Shell`
        )->ele( `Page`
            )->a( n = `title` v = `abap2UI5 agent - settings` ).


    temp2 = boolc( is_admin = abap_false ).
    page->tag( `MessageStrip`
        )->a( n = `text`     v = client->_bind( admin_hint )
        )->a( n = `type`     v = `Warning`
        )->a( n = `showIcon` v = `true`
        )->a( n = `visible`  b = temp2 ).

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


    rules = page->ele( `Table`
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


    CLEAR temp1.
    INSERT `${KIND}` INTO TABLE temp1.
    INSERT `${APP}` INTO TABLE temp1.
    INSERT `${ITEM}` INTO TABLE temp1.
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
                                                            t_arg = temp1 ) ).

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


    apps = page->ele( `Table`
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
        )->a( n = `title`    v = `Language model (generative UI, in-app copilot)`
        )->a( n = `editable` b = is_admin
        )->ele( n = `content` ns = `form`

            )->tag( `Label`
                )->a( n = `text` v = `API key`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_key )
                )->a( n = `type`        v = `Password`
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = client->_bind( llm_key_state )
            )->tag( `Button`
                )->a( n = `text`    v = `Remove key`
                )->a( n = `enabled` b = is_admin
                )->a( n = `press`   v = client->_event( `LLM_KEY_REMOVE` )
            )->tag( `Label`
                )->a( n = `text` v = `Destination`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_destination )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = `SM59 destination - on ABAP Cloud SCENARIO/SERVICE_ID of an arrangement`
            )->tag( `Label`
                )->a( n = `text` v = `URL`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_url )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_claude=>c_default_url
            )->tag( `Label`
                )->a( n = `text` v = `Model / effort`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_model )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_claude=>c_default_model
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_effort )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = `low (default), medium, high, xhigh, max`
            )->tag( `Label`
                )->a( n = `text` v = `Max tokens / timeout (s)`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_max_tokens )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = `16000`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_timeout )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = `300`
            )->tag( `Label`
                )->a( n = `text` v = `Refusal fallback / beta header`
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_fallback )
                )->a( n = `editable` b = is_admin
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_beta )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_claude=>c_default_beta
            )->tag( `Label`
                )->a( n = `text` v = `Provider class`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_provider )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm=>get_default_provider( )
            )->tag( `Label`
                )->a( n = `text` v = `Audit keeps prompts and answers`
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_log_prompts )
                )->a( n = `editable` b = is_admin
            )->tag( `Label`
                )->a( n = `text` v = `Generative UI: sample rows / repair round`
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_genui_samples )
                )->a( n = `editable` b = is_admin
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_genui_repair )
                )->a( n = `editable` b = is_admin
            )->tag( `Label`
                )->a( n = `text` v = `In-app copilot / may propose actions`
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_copilot )
                )->a( n = `editable` b = is_admin
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( llm_copilot_act )
                )->a( n = `editable` b = is_admin
            )->tag( `Label`
                )->a( n = `text` v = ``
            )->tag( `Button`
                )->a( n = `text`    v = `Save`
                )->a( n = `type`    v = `Emphasized`
                )->a( n = `enabled` b = is_admin
                )->a( n = `press`   v = client->_event( `LLM_SAVE` )
            )->tag( `Button`
                )->a( n = `text`    v = `Test call`
                )->a( n = `enabled` b = is_admin
                )->a( n = `press`   v = client->_event( `LLM_TEST` ) ).

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

    DATA temp3 TYPE z2ui5_cl_agent_audit=>ty_s_entry.
    CLEAR temp3.
    temp3-operation = `settings`.
    temp3-app = app_name( ).
    temp3-outcome = z2ui5_cl_agent_audit=>cs_outcome-ok.
    temp3-args = text.
    z2ui5_cl_agent_audit=>log( temp3 ).

  ENDMETHOD.

  METHOD on_event.
        DATA temp4 TYPE string.
        DATA temp5 TYPE string.
        DATA lv_long TYPE string.
        DATA lv_kind TYPE string.
        DATA lv_app TYPE string.
        DATA lv_item TYPE string.
        DATA ls_rule TYPE z2ui5_cl_agent_app_admin=>ty_s_rule.
          DATA lv_admins TYPE i.
          DATA lt_stored TYPE z2ui5_cl_agent_settings=>ty_t_setting.
        DATA lv_count TYPE i.

    CASE client->get_event( ).

      WHEN `ENABLED`.
        IF check_change( ) = abap_false.
          load( ).
          RETURN.
        ENDIF.
        z2ui5_cl_agent_settings=>set_enabled( enabled ).

        IF enabled = abap_true.
          temp4 = `enabled`.
        ELSE.
          temp4 = `disabled`.
        ENDIF.
        audit( |endpoint { temp4 }| ).

        IF enabled = abap_true.
          temp5 = `Agents may operate the enabled apps now`.
        ELSE.
          temp5 = `The agent endpoint is disabled`.
        ENDIF.
        client->message_toast_display( temp5 ).

      WHEN `URL_SAVE`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.

        lv_long = z2ui5_cl_agent_settings=>check_fits( value = url ).
        IF lv_long IS NOT INITIAL.
          client->message_box_display( text = |The handover page is too long: { lv_long }|
                                       type = `error` ).
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

        lv_kind = client->get_event_arg( ).

        lv_app = client->get_event_arg( 2 ).

        lv_item = client->get_event_arg( 3 ).

        READ TABLE t_rule INTO ls_rule WITH KEY kind = lv_kind app = lv_app item = lv_item. "#EC CI_SORTSEQ
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        " the last administrator stays: without one nobody may change these
        " settings, and only a developer in the system could add one again
        IF ls_rule-kind = z2ui5_cl_agent_settings=>cs_kind-admin.
          " counted as stored, not as this form last showed them: two
          " administrators each removing themselves from a stale list left none
          z2ui5_cl_agent_settings=>refresh( ).

          lv_admins = 0.

          lt_stored = z2ui5_cl_agent_settings=>get_all( ).
          LOOP AT lt_stored TRANSPORTING NO FIELDS
               WHERE kind = z2ui5_cl_agent_settings=>cs_kind-admin. "#EC CI_SORTSEQ
            lv_admins = lv_admins + 1.
          ENDLOOP.
          IF lv_admins <= 1.
            client->message_box_display( text = `The last administrator cannot be removed - add another one first.`
                                         type = `error` ).
            RETURN.
          ENDIF.
        ENDIF.
        z2ui5_cl_agent_settings=>remove( kind = ls_rule-kind
                                         app  = ls_rule-app
                                         item = ls_rule-item ).
        audit( |rule removed: { ls_rule-kind } { ls_rule-app } { ls_rule-item } { ls_rule-value }| ).
        load( ).

      WHEN `LLM_SAVE`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        llm_save( ).

      WHEN `LLM_KEY_REMOVE`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        z2ui5_cl_agent_settings=>set_llm( z2ui5_cl_agent_settings=>cs_llm-key ).
        audit( `language model: API key removed` ).
        load( ).
        client->message_toast_display( `API key removed` ).

      WHEN `LLM_TEST`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.
        llm_test( ).

      WHEN `CLEANUP`.
        IF check_change( ) = abap_false.
          RETURN.
        ENDIF.

        lv_count = z2ui5_cl_agent_audit=>cleanup( cleanup_days ).
        audit( |audit log cleanup: { lv_count } entries older than { cleanup_days } days| ).
        client->message_toast_display( |{ lv_count } entries deleted| ).

    ENDCASE.

  ENDMETHOD.

  METHOD rule_add.

    DATA lv_kind TYPE string.
    DATA lv_app TYPE string.
    DATA lv_item TYPE string.
    DATA lv_value TYPE string.
    DATA lv_long TYPE string.
    lv_kind = to_upper( condense( new_kind ) ).

    lv_app = to_upper( condense( new_app ) ).

    lv_item = to_upper( condense( new_item ) ).

    lv_value = to_lower( condense( new_value ) ).

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

    " cut to the table's length, a pattern would match another field or event

    lv_long = z2ui5_cl_agent_settings=>check_fits( app   = lv_app
                                                         item  = lv_item
                                                         value = lv_value ).
    IF lv_long IS NOT INITIAL.
      client->message_box_display( text = |The rule is too long: { lv_long }|
                                   type = `error` ).
      RETURN.
    ENDIF.

    z2ui5_cl_agent_settings=>save( kind  = lv_kind
                                   app   = lv_app
                                   item  = lv_item
                                   value = lv_value ).
    audit( |rule added: { lv_kind } { lv_app } { lv_item } { lv_value }| ).
    CLEAR: new_app, new_item, new_value.
    load( ).
    client->message_toast_display( `Rule added` ).

  ENDMETHOD.

  METHOD llm_save.

    DATA temp6 TYPE string_table.
    DATA lt_item LIKE temp6.
    DATA temp1 TYPE string_table.
    DATA temp7 LIKE temp1.
    DATA lv_value LIKE LINE OF temp7.
      DATA lv_long TYPE string.
    DATA temp8 TYPE string_table.
    DATA lt_changed LIKE temp8.
    DATA temp9 TYPE z2ui5_cl_agent_app_admin=>ty_t_llm_item.
    DATA ls_new LIKE LINE OF temp9.
      DATA ls_shown TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item.
    DATA temp10 LIKE sy-subrc.
    DATA temp3 LIKE sy-subrc.
    DATA temp4 LIKE sy-subrc.
    DATA temp2 LIKE sy-subrc.
    DATA temp5 LIKE sy-subrc.
    DATA temp11 TYPE string.
    DATA temp12 LIKE sy-subrc.
    CLEAR temp6.

    lt_item = temp6.
    " nothing is saved when a value does not fit - a key cut short is none

    CLEAR temp1.
    INSERT llm_provider INTO TABLE temp1.
    INSERT llm_model INTO TABLE temp1.
    INSERT llm_effort INTO TABLE temp1.
    INSERT llm_max_tokens INTO TABLE temp1.
    INSERT llm_timeout INTO TABLE temp1.
    INSERT llm_url INTO TABLE temp1.
    INSERT llm_destination INTO TABLE temp1.
    INSERT llm_beta INTO TABLE temp1.
    INSERT llm_key INTO TABLE temp1.

    temp7 = temp1.

    LOOP AT temp7 INTO lv_value.

      lv_long = z2ui5_cl_agent_settings=>check_fits( value = condense( lv_value ) ).
      IF lv_long IS NOT INITIAL.
        client->message_box_display( text = |Not saved - a setting is too long: { lv_long }|
                                     type = `error` ).
        RETURN.
      ENDIF.
    ENDLOOP.
    " only what this form changed: another administrator's change made
    " since it was loaded (a privacy switch turned off) stays - written from
    " the stale form, prompt logging was back on and nobody was told

    CLEAR temp8.

    lt_changed = temp8.

    temp9 = llm_form( ).

    LOOP AT temp9 INTO ls_new.

      READ TABLE mt_llm_shown INTO ls_shown WITH KEY item = ls_new-item. "#EC CI_SORTSEQ
      IF sy-subrc = 0 AND ls_shown-value = ls_new-value.
        CONTINUE.
      ENDIF.
      z2ui5_cl_agent_settings=>set_llm( item  = ls_new-item
                                        value = ls_new-value ).
      INSERT ls_new-item INTO TABLE lt_changed.
    ENDLOOP.
    " the key goes where the address says: sent to a new URL, destination
    " or provider, it is the key of a host an administrator just named -
    " who may never have seen the key. Kept only with a key typed anew.
    " (not on a form opened before this was remembered - mt_llm_shown empty,
    " every item counts as changed there and the key would go unasked)

    READ TABLE lt_changed WITH KEY table_line = z2ui5_cl_agent_settings=>cs_llm-url TRANSPORTING NO FIELDS.
    temp10 = sy-subrc.


    temp4 = sy-subrc.
    READ TABLE lt_changed WITH KEY table_line = z2ui5_cl_agent_settings=>cs_llm-destination TRANSPORTING NO FIELDS.
    temp3 = sy-subrc.
    sy-subrc = temp4.


    temp5 = sy-subrc.
    READ TABLE lt_changed WITH KEY table_line = z2ui5_cl_agent_settings=>cs_llm-provider TRANSPORTING NO FIELDS.
    temp2 = sy-subrc.
    sy-subrc = temp5.
    IF llm_key IS INITIAL AND mt_llm_shown IS NOT INITIAL AND z2ui5_cl_agent_settings=>check_llm_key( ) = abap_true
        AND ( temp10 = 0
           OR temp3 = 0
           OR temp2 = 0 ).
      z2ui5_cl_agent_settings=>set_llm( z2ui5_cl_agent_settings=>cs_llm-key ).
      INSERT `API key removed - the address changed; enter the key again` INTO TABLE lt_item.
    ENDIF.
    " the key only when a new one was typed - it is never shown back
    IF llm_key IS NOT INITIAL.
      z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-key
                                        value = condense( llm_key ) ).
      INSERT `API key replaced` INTO TABLE lt_item.
    ENDIF.
    CLEAR llm_key.

    IF lt_item IS NOT INITIAL.
      temp11 = |, { concat_lines_of( table = lt_item sep = `, ` ) }|.
    ELSE.
      CLEAR temp11.
    ENDIF.
    audit( |language model settings saved: provider { llm_provider }, model { llm_model }, effort { llm_effort }, | &&
           |destination { llm_destination }, url { llm_url }, copilot { llm_copilot }/{ llm_copilot_act }, | &&
           |log prompts { llm_log_prompts }{ temp11 }| ).
    load( ).

    READ TABLE lt_item WITH KEY table_line = `API key removed - the address changed; enter the key again` TRANSPORTING NO FIELDS.
    temp12 = sy-subrc.
    IF temp12 = 0.
      client->message_box_display( text = `Saved. The API key was removed because the address changed - enter it again.`
                                   type = `warning` ).
    ELSE.
      client->message_toast_display( `Language model settings saved` ).
    ENDIF.

  ENDMETHOD.

  METHOD llm_form.

    DATA temp13 TYPE z2ui5_cl_agent_app_admin=>ty_t_llm_item.
    DATA temp14 LIKE LINE OF temp13.
    DATA temp5 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    DATA temp6 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    DATA temp7 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    DATA temp8 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    DATA temp9 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    DATA temp10 TYPE z2ui5_cl_agent_app_admin=>ty_s_llm_item-value.
    CLEAR temp13.

    temp14-item = z2ui5_cl_agent_settings=>cs_llm-provider.
    temp14-value = to_upper( condense( llm_provider ) ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-model.
    temp14-value = condense( llm_model ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-effort.
    temp14-value = to_lower( condense( llm_effort ) ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-max_tokens.
    temp14-value = condense( llm_max_tokens ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-timeout.
    temp14-value = condense( llm_timeout ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-url.
    temp14-value = condense( llm_url ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-destination.
    temp14-value = condense( llm_destination ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-beta.
    temp14-value = condense( llm_beta ).
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-fallback.

    IF llm_fallback = abap_true.
      temp5 = `on`.
    ELSE.
      temp5 = `off`.
    ENDIF.
    temp14-value = temp5.
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-log_prompts.

    IF llm_log_prompts = abap_true.
      temp6 = `on`.
    ELSE.
      temp6 = `off`.
    ENDIF.
    temp14-value = temp6.
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-genui_samples.

    IF llm_genui_samples = abap_true.
      temp7 = `on`.
    ELSE.
      temp7 = `off`.
    ENDIF.
    temp14-value = temp7.
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-genui_repair.

    IF llm_genui_repair = abap_true.
      temp8 = `on`.
    ELSE.
      temp8 = `off`.
    ENDIF.
    temp14-value = temp8.
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-copilot.

    IF llm_copilot = abap_true.
      temp9 = `on`.
    ELSE.
      temp9 = `off`.
    ENDIF.
    temp14-value = temp9.
    INSERT temp14 INTO TABLE temp13.
    temp14-item = z2ui5_cl_agent_settings=>cs_llm-copilot_act.

    IF llm_copilot_act = abap_true.
      temp10 = `on`.
    ELSE.
      temp10 = `off`.
    ENDIF.
    temp14-value = temp10.
    INSERT temp14 INTO TABLE temp13.
    result = temp13.

  ENDMETHOD.

  METHOD llm_test.
        DATA temp15 TYPE z2ui5_if_agent_llm=>ty_s_request.
        DATA temp11 TYPE z2ui5_if_agent_llm=>ty_t_message.
        DATA temp12 LIKE LINE OF temp11.
        DATA ls_answer TYPE z2ui5_if_agent_llm=>ty_s_response.
        DATA lx TYPE REF TO z2ui5_cx_agent_llm.

    TRY.

        CLEAR temp15.
        temp15-purpose = `test`.
        temp15-app = app_name( ).

        CLEAR temp11.

        temp12-role = z2ui5_if_agent_llm=>cs_role-user.
        temp12-content = `Answer with the single word: ok`.
        INSERT temp12 INTO TABLE temp11.
        temp15-t_message = temp11.

        ls_answer = z2ui5_cl_agent_llm=>create( )->chat(
            temp15 ).
        client->message_box_display( text  = |{ ls_answer-model } answered "{ ls_answer-text }" | &&
                                             |({ ls_answer-usage-input_tokens } + { ls_answer-usage-output_tokens } tokens)|
                                     type  = `success`
                                     title = `Language model` ).

      CATCH z2ui5_cx_agent_llm INTO lx.
        client->message_box_display( text  = lx->get_text( )
                                     type  = `error`
                                     title = `Language model` ).
    ENDTRY.

  ENDMETHOD.

  METHOD load.
    DATA temp16 TYPE string.
    DATA temp17 TYPE z2ui5_cl_agent_settings=>ty_t_setting.
    DATA ls_setting LIKE LINE OF temp17.
      DATA temp18 TYPE z2ui5_cl_agent_app_admin=>ty_s_rule.
      DATA temp13 TYPE z2ui5_cl_agent_app_admin=>ty_s_rule-info.
          DATA temp6 TYPE z2ui5_cl_agent_app_admin=>ty_s_rule-info.
    DATA temp19 TYPE string.
        DATA temp20 TYPE z2ui5_cl_agent_settings=>ty_t_app.
        DATA ls_app LIKE LINE OF temp20.
          DATA temp21 TYPE z2ui5_cl_agent_app_admin=>ty_s_app.
          DATA temp14 TYPE z2ui5_cl_agent_app_admin=>ty_s_app-source.

    z2ui5_cl_agent_settings=>refresh( ).
    enabled = z2ui5_cl_agent_settings=>check_enabled( ).
    is_admin = z2ui5_cl_agent_settings=>check_admin( ).

    IF z2ui5_cl_agent_settings=>check_admin_defined( ) = abap_false.
      temp16 = |No agent administrator is defined yet - nothing can be changed here. Run | && |z2ui5_cl_agent_settings=>admin_add( '{ sy-uname }' ) once in this system (README, "Installation").|.
    ELSE.
      temp16 = |{ sy-uname } is no agent administrator - the settings are shown read-only.|.
    ENDIF.
    admin_hint = temp16.

    CLEAR: t_rule, url.

    temp17 = z2ui5_cl_agent_settings=>get_all( ).

    LOOP AT temp17 INTO ls_setting.
      CASE ls_setting-kind.
        WHEN z2ui5_cl_agent_settings=>cs_kind-url.
          url = ls_setting-value.
          CONTINUE.
        WHEN z2ui5_cl_agent_settings=>cs_kind-enabled OR z2ui5_cl_agent_settings=>cs_kind-llm.
          CONTINUE.
      ENDCASE.

      CLEAR temp18.
      temp18-kind = ls_setting-kind.
      temp18-app = ls_setting-app.
      temp18-item = ls_setting-item.
      temp18-value = ls_setting-value.

      CASE ls_setting-kind.
        WHEN z2ui5_cl_agent_settings=>cs_kind-app.

          IF ls_setting-value = z2ui5_cl_agent_settings=>cs_app_rule-deny.
            temp6 = `never startable by an agent`.
          ELSE.
            temp6 = `startable without z2ui5_if_agent_app`.
          ENDIF.
          temp13 = temp6.
        WHEN z2ui5_cl_agent_settings=>cs_kind-event.
          temp13 = |{ ls_setting-value } - the stricter of this and the app's own rule wins|.
        WHEN z2ui5_cl_agent_settings=>cs_kind-sensitive.
          temp13 = `masked in the audit log`.
        WHEN z2ui5_cl_agent_settings=>cs_kind-admin.
          temp13 = `may change these settings`.
      ENDCASE.
      temp18-info = temp13.
      INSERT temp18 INTO TABLE t_rule.
    ENDLOOP.

    llm_provider = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-provider ).
    llm_model = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-model ).
    llm_effort = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-effort ).
    llm_max_tokens = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-max_tokens ).
    llm_timeout = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-timeout ).
    llm_url = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-url ).
    llm_destination = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-destination ).
    llm_beta = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-beta ).
    llm_fallback = z2ui5_cl_agent_settings=>check_llm( item          = z2ui5_cl_agent_settings=>cs_llm-fallback
                                                       default_value = abap_true ).
    llm_log_prompts = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-log_prompts ).
    llm_genui_samples = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-genui_samples ).
    llm_genui_repair = z2ui5_cl_agent_settings=>check_llm( item          = z2ui5_cl_agent_settings=>cs_llm-genui_repair
                                                           default_value = abap_true ).
    llm_copilot = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot ).
    llm_copilot_act = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot_act ).
    CLEAR llm_key.
    mt_llm_shown = llm_form( ).

    IF z2ui5_cl_agent_settings=>check_llm_key( ) = abap_true.
      temp19 = `set - type a new key to replace it`.
    ELSE.
      temp19 = `not set`.
    ENDIF.
    llm_key_state = temp19.

    CLEAR t_app.
    TRY.

        temp20 = z2ui5_cl_agent_settings=>get_apps( ).

        LOOP AT temp20 INTO ls_app.

          CLEAR temp21.
          temp21-app = ls_app-app.
          temp21-description = ls_app-description.

          CASE ls_app-source.
            WHEN `interface`.
              temp14 = `the app (z2ui5_if_agent_app)`.
            WHEN OTHERS.
              temp14 = `a rule of these settings`.
          ENDCASE.
          temp21-source = temp14.
          INSERT temp21 INTO TABLE t_app.
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

  METHOD app_name.

    result = cl_abap_classdescr=>get_class_name( me ).
    SHIFT result LEFT DELETING LEADING '\CLASS='.

  ENDMETHOD.

ENDCLASS.
