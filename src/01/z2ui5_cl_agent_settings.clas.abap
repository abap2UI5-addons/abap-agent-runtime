"! The agent endpoint's settings and policy - table Z2UI5_T_17.
"!
"! One row per setting, keyed by KIND / APP / ITEM:
"!   ENABLED    APP *            VALUE X       the endpoint answers tool calls
"!                                            at all (default: no row = OFF)
"!   APP        APP pattern      VALUE allow   start apps that do not implement
"!                                            z2ui5_if_agent_app
"!                               VALUE deny    never start them, even when
"!                                            they implement it
"!   EVENT      APP pattern      ITEM event    VALUE allowed / confirm /
"!                                            forbidden - next to what the app
"!                                            says itself; the stricter wins
"!   SENSITIVE  APP pattern      ITEM field    the audit log masks the value
"!   ADMIN      APP user name                 may change these settings
"!   URL        APP *            VALUE url     the abap2UI5 page a handover
"!                                            sends the user to
"!   LLM        APP *            ITEM name     the language model and the AI
"!                                            features (cs_llm) - get_llm( ),
"!                                            set_llm( ); the API key is never
"!                                            read back by an app, only whether
"!                                            it is set (check_llm_key)
"! Patterns are CP patterns (*, +), compared upper case.
"!
"! The addon's own apps (z2ui5_cl_agent_app_*) are never agent-operable,
"! whatever the settings say: an agent must not change its own rules.
CLASS z2ui5_cl_agent_settings DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      BEGIN OF cs_kind,
        enabled   TYPE string VALUE `ENABLED`,
        app       TYPE string VALUE `APP`,
        event     TYPE string VALUE `EVENT`,
        sensitive TYPE string VALUE `SENSITIVE`,
        admin     TYPE string VALUE `ADMIN`,
        url       TYPE string VALUE `URL`,
        llm       TYPE string VALUE `LLM`,
      END OF cs_kind.

    CONSTANTS:
      "! The items of kind LLM. provider: the class implementing
      "! z2ui5_if_agent_llm (default z2ui5_cl_agent_llm_claude); model,
      "! effort, max_tokens, timeout (seconds): of every call; url,
      "! destination, key: where the provider sends it (z2ui5_if_agent_llm_http);
      "! fallback (on/off, default on): the server-side refusal fallback of
      "! the Claude API, beta its header value; log_prompts (on/off, default
      "! off): the audit log keeps the prompt and the answer; genui_samples
      "! (on/off, default off): generative UI shows the model a few rows;
      "! genui_repair (on/off, default on): one repair round with the
      "! validation errors; copilot (on/off, default off): the in-app
      "! copilot answers; copilot_act (on/off, default off): it may propose
      "! actions.
      BEGIN OF cs_llm,
        provider      TYPE string VALUE `PROVIDER`,
        model         TYPE string VALUE `MODEL`,
        effort        TYPE string VALUE `EFFORT`,
        max_tokens    TYPE string VALUE `MAX_TOKENS`,
        timeout       TYPE string VALUE `TIMEOUT`,
        url           TYPE string VALUE `URL`,
        destination   TYPE string VALUE `DESTINATION`,
        key           TYPE string VALUE `KEY`,
        fallback      TYPE string VALUE `FALLBACK`,
        beta          TYPE string VALUE `BETA`,
        log_prompts   TYPE string VALUE `LOG_PROMPTS`,
        genui_samples TYPE string VALUE `GENUI_SAMPLES`,
        genui_repair  TYPE string VALUE `GENUI_REPAIR`,
        copilot       TYPE string VALUE `COPILOT`,
        copilot_act   TYPE string VALUE `COPILOT_ACT`,
      END OF cs_llm.

    CONSTANTS:
      BEGIN OF cs_app_rule,
        allow TYPE string VALUE `allow`,
        deny  TYPE string VALUE `deny`,
      END OF cs_app_rule.

    "! Where a handover sends the user when no URL is set: the ICF node the
    "! abap2UI5 documentation installs.
    CONSTANTS c_default_url TYPE string VALUE `/sap/bc/z2ui5`.

    "! The event that opens the in-app copilot (z2ui5_cl_agent_copilot) -
    "! forbidden for agents on every screen: the copilot is for people.
    CONSTANTS c_copilot_event TYPE string VALUE `Z2UI5_AGENT_COPILOT`.

    TYPES ty_t_setting TYPE STANDARD TABLE OF z2ui5_t_17 WITH DEFAULT KEY.

    TYPES:
      "! An app an agent may start. source: interface (it implements
      "! z2ui5_if_agent_app) or setting (an administrator allowed it).
      BEGIN OF ty_s_app,
        app         TYPE string,
        description TYPE string,
        source      TYPE string,
      END OF ty_s_app.
    TYPES ty_t_app TYPE STANDARD TABLE OF ty_s_app WITH DEFAULT KEY.

    TYPES:
      "! The verdict on one event: policy (z2ui5_if_agent_app=&gt;cs_policy)
      "! and who decided it, in words.
      BEGIN OF ty_s_policy,
        policy TYPE string,
        source TYPE string,
      END OF ty_s_policy.

    CLASS-METHODS check_enabled
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS set_enabled
      IMPORTING
        val TYPE abap_bool.

    "! Whether the user may change the settings. Nobody may until the first
    "! administrator is added - by admin_add( ) run in the system (README,
    "! "Installation").
    CLASS-METHODS check_admin
      IMPORTING
        uname         TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS check_admin_defined
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS admin_add
      IMPORTING
        uname TYPE clike.

    "! Every setting - the value of the API key masked.
    CLASS-METHODS get_all
      RETURNING
        VALUE(result) TYPE ty_t_setting.

    CLASS-METHODS save
      IMPORTING
        kind  TYPE clike
        app   TYPE clike
        item  TYPE clike OPTIONAL
        value TYPE clike OPTIONAL.

    "! Why a setting does not fit the table (app and item 60, value 255
    "! characters) - empty when it fits. save( ) would cut it, and a pattern
    "! or a key cut short is another one.
    CLASS-METHODS check_fits
      IMPORTING
        app           TYPE clike OPTIONAL
        item          TYPE clike OPTIONAL
        value         TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS remove
      IMPORTING
        kind TYPE clike
        app  TYPE clike
        item TYPE clike OPTIONAL.

    "! Forget the buffered settings (they are read once per request).
    CLASS-METHODS refresh.

    "! Whether an agent may start the class, and if not, why not.
    CLASS-METHODS check_app
      IMPORTING
        app           TYPE clike
      EXPORTING
        reason        TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The apps an agent may start, sorted, optionally filtered by a
    "! case-insensitive substring of the class name.
    CLASS-METHODS get_apps
      IMPORTING
        filter        TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_t_app.

    "! What the app class says about itself (empty when it does not
    "! implement z2ui5_if_agent_app or its describe( ) fails).
    CLASS-METHODS get_app_info
      IMPORTING
        app           TYPE clike
      RETURNING
        VALUE(result) TYPE z2ui5_if_agent_app=>ty_s_info.

    "! The policy of an event on the screen of app, in a session started
    "! with app_start: the stricter of the app's own rules (describe( ))
    "! and the EVENT settings matching either class; every event of the
    "! addon's own apps is forbidden.
    CLASS-METHODS get_policy
      IMPORTING
        app_start     TYPE clike
        app           TYPE clike
        event         TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_policy.

    "! Whether a value at this model path / under this name is masked in
    "! the audit log.
    CLASS-METHODS check_sensitive
      IMPORTING
        app           TYPE clike
        path          TYPE clike
        name          TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The abap2UI5 URL that restores a draft in the browser.
    CLASS-METHODS get_handover_url
      IMPORTING
        app           TYPE clike
        draft         TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! A language model setting (cs_llm) - empty when not set. Never the
    "! key: get_llm_key( ) is for the provider only.
    CLASS-METHODS get_llm
      IMPORTING
        item          TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! An on/off setting of kind LLM, with its default when not set.
    CLASS-METHODS check_llm
      IMPORTING
        item          TYPE clike
        default_value TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! Store a language model setting - an empty value removes it.
    CLASS-METHODS set_llm
      IMPORTING
        item  TYPE clike
        value TYPE clike OPTIONAL.

    "! Whether an API key is stored - what the settings app shows of it.
    CLASS-METHODS check_llm_key
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The stored API key - for a provider's outbound call only.
    CLASS-METHODS get_llm_key
      RETURNING
        VALUE(result) TYPE string.

    "! How long a session lives - the draft expiry of the abap2UI5
    "! configuration (z2ui5_if_ui5_exit, draft_exp_time_in_hours).
    CLASS-METHODS get_expiry_hours
      RETURNING
        VALUE(result) TYPE i.

  PROTECTED SECTION.

  PRIVATE SECTION.

    "! The interface names, read from typed references - a namespace rename
    "! rewrites a reference, never a literal.
    CLASS-METHODS if_app_name
      RETURNING
        VALUE(result) TYPE string.
    CLASS-METHODS if_agent_app_name
      RETURNING
        VALUE(result) TYPE string.

    TYPES:
      BEGIN OF ty_s_info_buffer,
        app  TYPE string,
        info TYPE z2ui5_if_agent_app=>ty_s_info,
      END OF ty_s_info_buffer.
    TYPES ty_t_info_buffer TYPE STANDARD TABLE OF ty_s_info_buffer WITH DEFAULT KEY.

    CLASS-DATA gt_setting  TYPE ty_t_setting.
    CLASS-DATA gv_loaded   TYPE abap_bool.
    CLASS-DATA gt_info     TYPE ty_t_info_buffer.

    CLASS-METHODS load.

    CLASS-METHODS check_own_app
      IMPORTING
        app           TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS strictest
      IMPORTING
        a             TYPE string
        b             TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

ENDCLASS.


CLASS z2ui5_cl_agent_settings IMPLEMENTATION.

  METHOD load.

    IF gv_loaded = abap_true.
      RETURN.
    ENDIF.
    SELECT * FROM z2ui5_t_17 INTO TABLE gt_setting ORDER BY PRIMARY KEY.
    gv_loaded = abap_true.

  ENDMETHOD.

  METHOD refresh.

    CLEAR gt_setting.
    CLEAR gt_info.
    gv_loaded = abap_false.

  ENDMETHOD.

  METHOD get_all.
    DATA temp3 LIKE LINE OF result.
    DATA lr_setting LIKE REF TO temp3.

    load( ).
    result = gt_setting.
    " the API key never leaves this class but through get_llm_key( )


    LOOP AT result REFERENCE INTO lr_setting WHERE kind = cs_kind-llm AND item = cs_llm-key. "#EC CI_SORTSEQ
      lr_setting->value = `***`.
    ENDLOOP.

  ENDMETHOD.

  METHOD check_enabled.
    DATA ls_setting TYPE z2ui5_t_17.
    DATA temp1 TYPE xsdboolean.

    load( ).

    READ TABLE gt_setting INTO ls_setting WITH KEY kind = cs_kind-enabled. "#EC CI_SORTSEQ

    temp1 = boolc( sy-subrc = 0 AND ls_setting-value = abap_true ).
    result = temp1.

  ENDMETHOD.

  METHOD set_enabled.

    DATA temp4 TYPE string.
    IF val = abap_true.
      temp4 = `X`.
    ELSE.
      CLEAR temp4.
    ENDIF.
    save( kind  = cs_kind-enabled
          app   = `*`
          value = temp4 ).

  ENDMETHOD.

  METHOD check_admin.

    DATA lv_uname TYPE string.

    DATA temp5 TYPE string.
    DATA temp6 LIKE sy-subrc.
    DATA temp2 TYPE xsdboolean.
    IF uname IS SUPPLIED.
      temp5 = uname.
    ELSE.
      temp5 = sy-uname.
    ENDIF.
    lv_uname = temp5.
    lv_uname = to_upper( lv_uname ).
    load( ).

    READ TABLE gt_setting WITH KEY kind = cs_kind-admin app = lv_uname TRANSPORTING NO FIELDS.
    temp6 = sy-subrc.

    temp2 = boolc( temp6 = 0 ).
    result = temp2. "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD check_admin_defined.
    DATA temp7 LIKE sy-subrc.
    DATA temp3 TYPE xsdboolean.

    load( ).

    READ TABLE gt_setting WITH KEY kind = cs_kind-admin TRANSPORTING NO FIELDS.
    temp7 = sy-subrc.

    temp3 = boolc( temp7 = 0 ).
    result = temp3. "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD admin_add.

    " the bootstrap, run once in the system (README, "Installation") -
    " committed here, as nothing else would commit it there
    save( kind  = cs_kind-admin
          app   = to_upper( uname )
          value = `X` ).
    COMMIT WORK.

  ENDMETHOD.

  METHOD save.

    DATA ls_row TYPE z2ui5_t_17.

    ls_row-kind = to_upper( kind ).
    ls_row-app = to_upper( app ).
    ls_row-item = to_upper( item ).
    ls_row-value = value.
    ls_row-changed_by = sy-uname.
    ls_row-changed_at = z2ui5_cl_ui5_util_context=>time_get_timestampl( ).
    MODIFY z2ui5_t_17 FROM ls_row.
    refresh( ).

  ENDMETHOD.

  METHOD check_fits.

    DATA ls_row TYPE z2ui5_t_17.

    " the characters the columns hold
    DATA temp8 TYPE REF TO cl_abap_elemdescr.
    DATA lv_app LIKE temp8->output_length.
    DATA temp9 TYPE REF TO cl_abap_elemdescr.
    DATA lv_item LIKE temp9->output_length.
    DATA temp10 TYPE REF TO cl_abap_elemdescr.
    DATA lv_value LIKE temp10->output_length.
    temp8 ?= cl_abap_typedescr=>describe_by_data( ls_row-app ).

    lv_app = temp8->output_length.

    temp9 ?= cl_abap_typedescr=>describe_by_data( ls_row-item ).

    lv_item = temp9->output_length.

    temp10 ?= cl_abap_typedescr=>describe_by_data( ls_row-value ).

    lv_value = temp10->output_length.
    IF strlen( app ) > lv_app.
      result = |{ strlen( app ) } characters - an app pattern or user name holds at most { lv_app }|.
    ELSEIF strlen( item ) > lv_item.
      result = |{ strlen( item ) } characters - an event or field pattern holds at most { lv_item }|.
    ELSEIF strlen( value ) > lv_value.
      result = |{ strlen( value ) } characters - a value holds at most { lv_value }|.
    ENDIF.

  ENDMETHOD.

  METHOD remove.

    DATA lv_kind TYPE z2ui5_t_17-kind.
    DATA lv_app TYPE z2ui5_t_17-app.
    DATA lv_item TYPE z2ui5_t_17-item.

    lv_kind = to_upper( kind ).
    lv_app = to_upper( app ).
    lv_item = to_upper( item ).
    DELETE FROM z2ui5_t_17 WHERE kind = lv_kind AND app = lv_app AND item = lv_item.
    refresh( ).

  ENDMETHOD.

  METHOD check_own_app.

    " the addon's own apps change and show the rules - never agent-operable;
    " nor the copilot, which operates apps itself
    DATA temp4 TYPE xsdboolean.
    temp4 = boolc( app CP `Z2UI5_CL_AGENT_APP_*` OR app CP `Z2UI5_CL_AGENT_COPILOT*` ).
    result = temp4.

  ENDMETHOD.

  METHOD check_app.

    DATA lv_app TYPE string.
    DATA ls_rule LIKE LINE OF gt_setting.

    lv_app = to_upper( condense( app ) ).
    CLEAR reason.
    IF lv_app IS INITIAL.
      reason = `no class name given`.
      RETURN.
    ENDIF.
    IF check_own_app( lv_app ) = abap_true.
      reason = |{ lv_app } belongs to the agent addon itself and is never operable by an agent|.
      RETURN.
    ENDIF.
    IF z2ui5_cl_ui5_util_context=>rtti_check_class_impl_intf( class = lv_app
                                                              intf  = if_app_name( ) ) = abap_false.
      reason = |{ lv_app } is no abap2UI5 app (no class of that name implements z2ui5_if_app)|.
      RETURN.
    ENDIF.

    load( ).

    LOOP AT gt_setting INTO ls_rule WHERE kind = cs_kind-app. "#EC CI_SORTSEQ
      IF lv_app CP ls_rule-app AND ls_rule-value = cs_app_rule-deny.
        reason = |{ lv_app } is denied for agents by the setting APP { ls_rule-app }|.
        RETURN.
      ENDIF.
    ENDLOOP.

    IF z2ui5_cl_ui5_util_context=>rtti_check_class_impl_intf( class = lv_app
                                                              intf  = if_agent_app_name( ) ) = abap_true.
      result = abap_true.
      RETURN.
    ENDIF.

    LOOP AT gt_setting INTO ls_rule WHERE kind = cs_kind-app. "#EC CI_SORTSEQ
      IF lv_app CP ls_rule-app AND ls_rule-value = cs_app_rule-allow.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.

    reason = |{ lv_app } is not enabled for agents - the app implements z2ui5_if_agent_app to opt in, | &&
             |or an administrator allows it in the agent settings (z2ui5_cl_agent_app_admin)|.

  ENDMETHOD.

  METHOD get_apps.

    DATA lt_name TYPE string_table.
    DATA lv_filter TYPE string.
        DATA lt_impl TYPE z2ui5_cl_ui5_util_context=>ty_t_classes.
    DATA ls_impl LIKE LINE OF lt_impl.
      DATA temp11 TYPE z2ui5_cl_agent_settings=>ty_s_app.
    DATA lv_patterns LIKE abap_false.
    DATA ls_rule LIKE LINE OF gt_setting.
        DATA temp12 LIKE LINE OF lt_name.
        DATA temp1 TYPE string.
    DATA lv_name LIKE LINE OF lt_name.
      DATA temp13 LIKE sy-subrc.
      DATA temp14 LIKE sy-tabix.
        DATA temp15 TYPE z2ui5_cl_agent_settings=>ty_s_app.
    DATA temp16 LIKE LINE OF result.
    DATA lr_app LIKE REF TO temp16.
      DATA lv_tabix LIKE sy-tabix.

    load( ).
    " the class directory: SEOMETAREL on ABAP Standard, XCO on ABAP Cloud -
    " where it cannot be read, the list holds what the settings name
    TRY.

        lt_impl = z2ui5_cl_ui5_util_context=>rtti_get_classes_impl_intf( if_agent_app_name( ) ).
      CATCH cx_root.
        CLEAR lt_impl.
    ENDTRY.

    LOOP AT lt_impl INTO ls_impl.

      CLEAR temp11.
      temp11-app = to_upper( ls_impl-classname ).
      temp11-source = `interface`.
      INSERT temp11 INTO TABLE result.
    ENDLOOP.

    " what an administrator allowed: names as they are, patterns against
    " every abap2UI5 app of the system

    lv_patterns = abap_false.

    LOOP AT gt_setting INTO ls_rule WHERE kind = cs_kind-app AND value = cs_app_rule-allow. "#EC CI_SORTSEQ
      IF ls_rule-app CA `*+`.
        lv_patterns = abap_true.
      ELSE.

        temp12 = ls_rule-app.
        INSERT temp12 INTO TABLE lt_name.
      ENDIF.
    ENDLOOP.
    IF lv_patterns = abap_true.
      TRY.
          lt_impl = z2ui5_cl_ui5_util_context=>rtti_get_classes_impl_intf( if_app_name( ) ).
        CATCH cx_root.
          CLEAR lt_impl.
      ENDTRY.
      LOOP AT lt_impl INTO ls_impl.

        temp1 = to_upper( ls_impl-classname ).
        INSERT temp1 INTO TABLE lt_name.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_name INTO lv_name.


      temp14 = sy-tabix.
      READ TABLE result WITH KEY app = lv_name TRANSPORTING NO FIELDS.
      temp13 = sy-subrc.
      sy-tabix = temp14.
      IF temp13 = 0. "#EC CI_SORTSEQ
        CONTINUE.
      ENDIF.
      IF check_app( lv_name ) = abap_true.

        CLEAR temp15.
        temp15-app = lv_name.
        temp15-source = `setting`.
        INSERT temp15 INTO TABLE result.
      ENDIF.
    ENDLOOP.

    " the final word is check_app( ): denied and own apps go
    lv_filter = to_upper( condense( filter ) ).


    LOOP AT result REFERENCE INTO lr_app.

      lv_tabix = sy-tabix.
      IF ( lv_filter IS NOT INITIAL AND find( val = lr_app->app
                                              sub = lv_filter ) < 0 )
          OR ( lr_app->source = `interface` AND check_app( lr_app->app ) = abap_false ).
        DELETE result INDEX lv_tabix.
        CONTINUE.
      ENDIF.
      lr_app->description = get_app_info( lr_app->app )-description.
    ENDLOOP.
    SORT result BY app.
    DELETE ADJACENT DUPLICATES FROM result COMPARING app.

  ENDMETHOD.

  METHOD get_app_info.

    DATA lo_app TYPE REF TO object.
    DATA lv_app TYPE string.
    DATA ls_buffer TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.
          DATA temp17 TYPE REF TO z2ui5_if_agent_app.
    DATA temp18 TYPE z2ui5_cl_agent_settings=>ty_s_info_buffer.

    lv_app = to_upper( condense( app ) ).

    READ TABLE gt_info INTO ls_buffer WITH KEY app = lv_app. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_buffer-info.
      RETURN.
    ENDIF.

    IF z2ui5_cl_ui5_util_context=>rtti_check_class_impl_intf( class = lv_app
                                                              intf  = if_agent_app_name( ) ) = abap_true.
      TRY.
          CREATE OBJECT lo_app TYPE (lv_app).

          temp17 ?= lo_app.
          result = temp17->describe( ).
        CATCH cx_root.
          CLEAR result.
      ENDTRY.
    ENDIF.

    CLEAR temp18.
    temp18-app = lv_app.
    temp18-info = result.
    INSERT temp18 INTO TABLE gt_info.

  ENDMETHOD.

  METHOD strictest.

    " abap_true when b is stricter than a: forbidden > confirm > allowed
    DATA temp19 TYPE i.
    DATA lv_a LIKE temp19.
    DATA temp20 TYPE i.
    DATA lv_b LIKE temp20.
    DATA temp5 TYPE xsdboolean.
    IF a = z2ui5_if_agent_app=>cs_policy-forbidden.
      temp19 = 2.
    ELSEIF a = z2ui5_if_agent_app=>cs_policy-confirm.
      temp19 = 1.
    ELSE.
      temp19 = 0.
    ENDIF.

    lv_a = temp19.

    IF b = z2ui5_if_agent_app=>cs_policy-forbidden.
      temp20 = 2.
    ELSEIF b = z2ui5_if_agent_app=>cs_policy-confirm.
      temp20 = 1.
    ELSE.
      temp20 = 0.
    ENDIF.

    lv_b = temp20.

    temp5 = boolc( lv_b > lv_a ).
    result = temp5.

  ENDMETHOD.

  METHOD get_policy.

    DATA lv_app TYPE string.
    DATA lv_start TYPE string.
    DATA lv_event TYPE string.
    DATA lv_policy TYPE string.
    DATA ls_deny LIKE LINE OF gt_setting.
    DATA ls_info TYPE z2ui5_if_agent_app=>ty_s_info.
    DATA lv_matched LIKE abap_false.
    DATA ls_rule LIKE LINE OF ls_info-t_event.
    DATA ls_setting LIKE LINE OF gt_setting.

    lv_app = to_upper( condense( app ) ).
    lv_start = to_upper( condense( app_start ) ).
    lv_event = event.
    CLEAR result.
    result-policy = z2ui5_if_agent_app=>cs_policy-allowed.
    result-source = `default`.
    IF lv_event = c_copilot_event.
      CLEAR result.
      result-policy = z2ui5_if_agent_app=>cs_policy-forbidden.
      result-source = `the in-app copilot is for people - an agent never opens it`.
      RETURN.
    ENDIF.
    " the addon's own apps also when an operable app navigated there: an
    " agent must not change its own rules
    IF check_own_app( lv_app ) = abap_true.
      CLEAR result.
      result-policy = z2ui5_if_agent_app=>cs_policy-forbidden.
      result-source = |{ lv_app } belongs to the agent addon itself and is never operable by an agent|.
      RETURN.
    ENDIF.
    " an app an administrator denied, also when an operable app navigated
    " there or the rule came after the session started: check_app( ) only
    " guards app_start and app_attach, and "deny wins"
    load( ).

    LOOP AT gt_setting INTO ls_deny WHERE kind = cs_kind-app. "#EC CI_SORTSEQ
      IF lv_app CP ls_deny-app AND ls_deny-value = cs_app_rule-deny.
        CLEAR result.
        result-policy = z2ui5_if_agent_app=>cs_policy-forbidden.
        result-source = |{ lv_app } is denied for agents by the setting APP { ls_deny-app }|.
        RETURN.
      ENDIF.
    ENDLOOP.

    " the app's own word

    ls_info = get_app_info( lv_app ).

    lv_matched = abap_false.

    LOOP AT ls_info-t_event INTO ls_rule.
      IF lv_event CP ls_rule-event.
        lv_policy = ls_rule-policy.
        lv_matched = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_matched = abap_false.
      lv_policy = ls_info-default_policy.
    ENDIF.
    " in any case, as the settings' rules below - FORBIDDEN is forbidden
    lv_policy = to_lower( condense( lv_policy ) ).
    IF strictest( a = result-policy
                  b = lv_policy ) = abap_true.
      CLEAR result.
      result-policy = lv_policy.
      result-source = |the app { lv_app } classifies it { lv_policy }|.
    ENDIF.

    " the administrator's word - for the app on the screen and the one the
    " session was started with (it brought the user there)
    load( ).

    LOOP AT gt_setting INTO ls_setting WHERE kind = cs_kind-event. "#EC CI_SORTSEQ
      IF ( lv_app CP ls_setting-app OR lv_start CP ls_setting-app ) AND lv_event CP ls_setting-item.
        lv_policy = to_lower( ls_setting-value ).
        IF strictest( a = result-policy
                      b = lv_policy ) = abap_true.
          CLEAR result.
          result-policy = lv_policy.
          result-source = |the setting EVENT { ls_setting-app } { ls_setting-item } classifies it { lv_policy }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD check_sensitive.

    DATA lv_path TYPE string.
    DATA lv_name TYPE string.
    DATA lv_app TYPE string.
    DATA temp21 TYPE string_table.
    DATA lv_pattern LIKE LINE OF temp21.
    DATA ls_setting LIKE LINE OF gt_setting.

    lv_path = path.
    lv_name = name.
    lv_app = to_upper( condense( app ) ).

    temp21 = get_app_info( lv_app )-t_sensitive.

    LOOP AT temp21 INTO lv_pattern.
      IF lv_path CP lv_pattern OR ( lv_name IS NOT INITIAL AND lv_name CP lv_pattern ).
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    load( ).

    LOOP AT gt_setting INTO ls_setting WHERE kind = cs_kind-sensitive. "#EC CI_SORTSEQ
      IF lv_app CP ls_setting-app AND ( lv_path CP ls_setting-item OR ( lv_name IS NOT INITIAL AND lv_name CP ls_setting-item ) ).
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD get_handover_url.
    DATA ls_setting TYPE z2ui5_t_17.
    DATA temp22 TYPE string.
    DATA lv_base LIKE temp22.

    load( ).

    READ TABLE gt_setting INTO ls_setting WITH KEY kind = cs_kind-url. "#EC CI_SORTSEQ

    IF sy-subrc = 0 AND ls_setting-value IS NOT INITIAL.
      temp22 = ls_setting-value.
    ELSE.
      temp22 = c_default_url.
    ENDIF.

    lv_base = temp22.
    result = |{ lv_base }#/app/{ to_upper( app ) }/{ draft }|.

  ENDMETHOD.

  METHOD get_llm.

    DATA lv_item TYPE string.
    DATA ls_setting TYPE z2ui5_t_17.

    lv_item = to_upper( item ).
    IF lv_item = cs_llm-key.
      RETURN.
    ENDIF.
    load( ).

    READ TABLE gt_setting INTO ls_setting WITH KEY kind = cs_kind-llm item = lv_item. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_setting-value.
    ENDIF.

  ENDMETHOD.

  METHOD check_llm.

    DATA lv_value TYPE string.
    DATA temp23 TYPE abap_bool.
    lv_value = to_lower( get_llm( item ) ).

    IF lv_value = `on` OR lv_value = `x` OR lv_value = `true`.
      temp23 = abap_true.
    ELSEIF lv_value = `off` OR lv_value = `-` OR lv_value = `false`.
      temp23 = abap_false.
    ELSE.
      temp23 = default_value.
    ENDIF.
    result = temp23.

  ENDMETHOD.

  METHOD set_llm.

    IF value IS INITIAL.
      remove( kind = cs_kind-llm
              app  = `*`
              item = item ).
    ELSE.
      save( kind  = cs_kind-llm
            app   = `*`
            item  = item
            value = value ).
    ENDIF.

  ENDMETHOD.

  METHOD check_llm_key.

    DATA temp6 TYPE xsdboolean.
    temp6 = boolc( get_llm_key( ) IS NOT INITIAL ).
    result = temp6.

  ENDMETHOD.

  METHOD get_llm_key.
    DATA ls_setting TYPE z2ui5_t_17.

    load( ).

    READ TABLE gt_setting INTO ls_setting WITH KEY kind = cs_kind-llm item = cs_llm-key. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_setting-value.
    ENDIF.

  ENDMETHOD.

  METHOD get_expiry_hours.

    DATA temp24 TYPE z2ui5_if_ui5_exit=>ty_s_http_config_post.
    DATA ls_config LIKE temp24.
        DATA temp1 TYPE REF TO z2ui5_if_ui5_exit.
    CLEAR temp24.

    ls_config = temp24.
    TRY.

        temp1 = z2ui5_cl_ui5_user_exit=>get_instance( ).
        temp1->set_config_http_post( CHANGING cs_config = ls_config ).
        result = ls_config-draft_exp_time_in_hours.
      CATCH cx_root.
        CLEAR result.
    ENDTRY.
    IF result <= 0.
      result = 4.
    ENDIF.

  ENDMETHOD.

  METHOD if_app_name.

    DATA li_app TYPE REF TO z2ui5_if_app.
    result = z2ui5_cl_ui5_util_context=>rtti_get_ref_type_name( li_app ).

  ENDMETHOD.

  METHOD if_agent_app_name.

    DATA li_app TYPE REF TO z2ui5_if_agent_app.
    result = z2ui5_cl_ui5_util_context=>rtti_get_ref_type_name( li_app ).

  ENDMETHOD.

ENDCLASS.
