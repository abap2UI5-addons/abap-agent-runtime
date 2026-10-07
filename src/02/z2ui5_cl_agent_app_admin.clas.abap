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
    TYPES ty_t_llm_item TYPE STANDARD TABLE OF ty_s_llm_item WITH EMPTY KEY.

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
      " the key is write-only: whatever the event, a typed key is neither
      " kept in the draft of this app nor sent back to the browser
      CLEAR llm_key.
      " the settings and their audit entries - abap2UI5 rolls back what
      " main( ) leaves open
      COMMIT WORK.
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
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_anthropic=>c_default_url
            )->tag( `Label`
                )->a( n = `text` v = `Model / effort`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_model )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_anthropic=>c_default_model
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
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm_anthropic=>c_default_beta
            )->tag( `Label`
                )->a( n = `text` v = `Provider class`
            )->tag( `Input`
                )->a( n = `value`       v = client->_bind( llm_provider )
                )->a( n = `editable`    b = is_admin
                )->a( n = `placeholder` v = z2ui5_cl_agent_llm=>c_default_provider
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
        DATA(lv_long) = z2ui5_cl_agent_settings=>check_fits( value = url ).
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
        DATA(lv_kind) = client->get_event_arg( ).
        DATA(lv_app) = client->get_event_arg( 2 ).
        DATA(lv_item) = client->get_event_arg( 3 ).
        READ TABLE t_rule INTO DATA(ls_rule) WITH KEY kind = lv_kind app = lv_app item = lv_item. "#EC CI_SORTSEQ
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        " the last administrator stays: without one nobody may change these
        " settings, and only a developer in the system could add one again
        IF ls_rule-kind = z2ui5_cl_agent_settings=>cs_kind-admin.
          " counted as stored, not as this form last showed them: two
          " administrators each removing themselves from a stale list left none
          z2ui5_cl_agent_settings=>refresh( ).
          DATA(lv_admins) = 0.
          DATA(lt_stored) = z2ui5_cl_agent_settings=>get_all( ).
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

    " cut to the table's length, a pattern would match another field or event
    DATA(lv_long) = z2ui5_cl_agent_settings=>check_fits( app   = lv_app
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

    DATA(lt_item) = VALUE string_table( ).
    " nothing is saved when a value does not fit - a key cut short is none
    LOOP AT VALUE string_table( ( llm_provider ) ( llm_model ) ( llm_effort ) ( llm_max_tokens ) ( llm_timeout )
                                ( llm_url ) ( llm_destination ) ( llm_beta ) ( llm_key ) ) INTO DATA(lv_value).
      DATA(lv_long) = z2ui5_cl_agent_settings=>check_fits( value = condense( lv_value ) ).
      IF lv_long IS NOT INITIAL.
        client->message_box_display( text = |Not saved - a setting is too long: { lv_long }|
                                     type = `error` ).
        RETURN.
      ENDIF.
    ENDLOOP.
    " only what this form changed: another administrator's change made
    " since it was loaded (a privacy switch turned off) stays - written from
    " the stale form, prompt logging was back on and nobody was told
    DATA(lt_changed) = VALUE string_table( ).
    LOOP AT llm_form( ) INTO DATA(ls_new).
      READ TABLE mt_llm_shown INTO DATA(ls_shown) WITH KEY item = ls_new-item. "#EC CI_SORTSEQ
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
    IF llm_key IS INITIAL AND mt_llm_shown IS NOT INITIAL AND z2ui5_cl_agent_settings=>check_llm_key( ) = abap_true
        AND ( line_exists( lt_changed[ table_line = z2ui5_cl_agent_settings=>cs_llm-url ] )
           OR line_exists( lt_changed[ table_line = z2ui5_cl_agent_settings=>cs_llm-destination ] )
           OR line_exists( lt_changed[ table_line = z2ui5_cl_agent_settings=>cs_llm-provider ] ) ).
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
    audit( |language model settings saved: provider { llm_provider }, model { llm_model }, effort { llm_effort }, | &&
           |destination { llm_destination }, url { llm_url }, copilot { llm_copilot }/{ llm_copilot_act }, | &&
           |log prompts { llm_log_prompts }{ COND #( WHEN lt_item IS NOT INITIAL
                                                     THEN |, { concat_lines_of( table = lt_item
                                                                                sep   = `, ` ) }| ) }| ).
    load( ).
    IF line_exists( lt_item[ table_line = `API key removed - the address changed; enter the key again` ] ).
      client->message_box_display( text = `Saved. The API key was removed because the address changed - enter it again.`
                                   type = `warning` ).
    ELSE.
      client->message_toast_display( `Language model settings saved` ).
    ENDIF.

  ENDMETHOD.

  METHOD llm_form.

    result = VALUE #(
        ( item = z2ui5_cl_agent_settings=>cs_llm-provider    value = to_upper( condense( llm_provider ) ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-model       value = condense( llm_model ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-effort      value = to_lower( condense( llm_effort ) ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-max_tokens  value = condense( llm_max_tokens ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-timeout     value = condense( llm_timeout ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-url         value = condense( llm_url ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-destination value = condense( llm_destination ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-beta        value = condense( llm_beta ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-fallback    value = COND #( WHEN llm_fallback = abap_true THEN `on` ELSE `off` ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-log_prompts value = COND #( WHEN llm_log_prompts = abap_true THEN `on` ELSE `off` ) )
        ( item  = z2ui5_cl_agent_settings=>cs_llm-genui_samples
          value = COND #( WHEN llm_genui_samples = abap_true THEN `on` ELSE `off` ) )
        ( item  = z2ui5_cl_agent_settings=>cs_llm-genui_repair
          value = COND #( WHEN llm_genui_repair = abap_true THEN `on` ELSE `off` ) )
        ( item = z2ui5_cl_agent_settings=>cs_llm-copilot     value = COND #( WHEN llm_copilot = abap_true THEN `on` ELSE `off` ) )
        ( item  = z2ui5_cl_agent_settings=>cs_llm-copilot_act
          value = COND #( WHEN llm_copilot_act = abap_true THEN `on` ELSE `off` ) ) ).

  ENDMETHOD.

  METHOD llm_test.

    TRY.
        DATA(ls_answer) = z2ui5_cl_agent_llm=>create( )->chat(
            VALUE #( purpose   = `test`
                     app       = `Z2UI5_CL_AGENT_APP_ADMIN`
                     t_message = VALUE #( ( role    = z2ui5_if_agent_llm=>cs_role-user
                                            content = `Answer with the single word: ok` ) ) ) ).
        client->message_box_display( text  = |{ ls_answer-model } answered "{ ls_answer-text }" | &&
                                             |({ ls_answer-usage-input_tokens } + { ls_answer-usage-output_tokens } tokens)|
                                     type  = `success`
                                     title = `Language model` ).
      CATCH z2ui5_cx_agent_llm INTO DATA(lx).
        client->message_box_display( text  = lx->get_text( )
                                     type  = `error`
                                     title = `Language model` ).
    ENDTRY.

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
        WHEN z2ui5_cl_agent_settings=>cs_kind-enabled OR z2ui5_cl_agent_settings=>cs_kind-llm.
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

    llm_provider = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-provider ).
    llm_model = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-model ).
    llm_effort = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-effort ).
    llm_max_tokens = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-max_tokens ).
    llm_timeout = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-timeout ).
    llm_url = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-url ).
    llm_destination = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-destination ).
    llm_beta = z2ui5_cl_agent_settings=>get_llm( z2ui5_cl_agent_settings=>cs_llm-beta ).
    llm_fallback = z2ui5_cl_agent_settings=>check_llm( item    = z2ui5_cl_agent_settings=>cs_llm-fallback
                                                       default = abap_true ).
    llm_log_prompts = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-log_prompts ).
    llm_genui_samples = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-genui_samples ).
    llm_genui_repair = z2ui5_cl_agent_settings=>check_llm( item    = z2ui5_cl_agent_settings=>cs_llm-genui_repair
                                                           default = abap_true ).
    llm_copilot = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot ).
    llm_copilot_act = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot_act ).
    CLEAR llm_key.
    mt_llm_shown = llm_form( ).
    llm_key_state = COND #( WHEN z2ui5_cl_agent_settings=>check_llm_key( ) = abap_true
                            THEN `set - type a new key to replace it`
                            ELSE `not set` ).

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
