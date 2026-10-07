"! The engine of the in-app copilot ("ask this screen") - the popup app
"! z2ui5_cl_agent_copilot drives it, one static call per roundtrip:
"!
"!   attach( draft )   the screen the user is on, as an agent session: a
"!                     copy of the caller's draft continued headlessly
"!                     (z2ui5_cl_agent_session=&gt;app_attach in mode copilot -
"!                     opt-in and policy as for every agent)
"!   ask( )            one question: the agent snapshot v1 of that screen -
"!                     passwords and sensitive fields masked, forbidden
"!                     actions removed - plus the app's description go to
"!                     the language model, which answers grounded in it
"!                     (and says so when the screen does not hold the
"!                     answer) and may propose an action: fields to fill,
"!                     an event to fire. A proposal is validated like an
"!                     app_act of the MCP endpoint (app_check) before it is
"!                     shown; nothing runs here.
"!   act( )            what the user confirmed with a click: an allowed
"!                     event runs through the app's own main( ) in the
"!                     session (app_act); for an event classified confirm
"!                     only the fields are filled - the user presses the
"!                     button on the screen
"!   apply_pending( )  on close: filled values that no event sent yet are
"!                     written into the app instance the user returns to
"!
"! Every model call is audited by z2ui5_cl_agent_llm (purpose copilot),
"! every session operation by the session (MCP client "copilot").
CLASS z2ui5_cl_agent_assist DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_client TYPE string VALUE `copilot`.
    CONSTANTS c_mask TYPE string VALUE `***`.

    TYPES:
      "! role: user or assistant.
      BEGIN OF ty_s_turn,
        role TYPE string,
        text TYPE string,
      END OF ty_s_turn.
    TYPES ty_t_turn TYPE STANDARD TABLE OF ty_s_turn WITH EMPTY KEY.

    TYPES:
      "! field: as the model named it (id, path or name); label, path, kind:
      "! of the snapshot's field (value of a multichoice: its keys,
      "! separated by commas).
      BEGIN OF ty_s_value,
        field TYPE string,
        label TYPE string,
        path  TYPE string,
        kind  TYPE string,
        value TYPE string,
      END OF ty_s_value.
    TYPES ty_t_value TYPE STANDARD TABLE OF ty_s_value WITH EMPTY KEY.

    TYPES:
      "! present: the model proposed something. valid: it passed the
      "! validation and may be offered (reason says why not). needs_human:
      "! the event is classified confirm - the copilot fills the fields,
      "! the user presses the button. policy: allowed / confirm.
      BEGIN OF ty_s_proposal,
        present     TYPE abap_bool,
        valid       TYPE abap_bool,
        summary     TYPE string,
        event       TYPE string,
        "! The id of the action validated - what is checked and fired, as
        "! two actions may share an event and differ in their arguments.
        action      TYPE string,
        label       TYPE string,
        policy      TYPE string,
        needs_human TYPE abap_bool,
        t_value     TYPE ty_t_value,
        reason      TYPE string,
      END OF ty_s_proposal.

    TYPES:
      "! found: the screen holds the answer (the model says so).
      BEGIN OF ty_s_answer,
        ok       TYPE abap_bool,
        text     TYPE string,
        found    TYPE abap_bool,
        proposal TYPE ty_s_proposal,
        error    TYPE string,
      END OF ty_s_answer.

    TYPES:
      BEGIN OF ty_s_attach,
        ok          TYPE abap_bool,
        session     TYPE string,
        app         TYPE string,
        title       TYPE string,
        description TYPE string,
        error       TYPE string,
      END OF ty_s_attach.

    TYPES:
      "! session: the session after the act (an event mints a new draft).
      BEGIN OF ty_s_done,
        ok      TYPE abap_bool,
        text    TYPE string,
        session TYPE string,
        error   TYPE string,
      END OF ty_s_done.

    CLASS-METHODS attach
      IMPORTING
        draft         TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_attach.

    CLASS-METHODS ask
      IMPORTING
        session       TYPE clike
        question      TYPE clike
        t_turn        TYPE ty_t_turn OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_answer.

    CLASS-METHODS act
      IMPORTING
        session       TYPE clike
        is_proposal   TYPE ty_s_proposal
      RETURNING
        VALUE(result) TYPE ty_s_done.

    "! Write the pending values of the session (filled, not yet sent) into
    "! the app instance - its public attributes by model path. Returns the
    "! paths written; t_refused: why a value was not (a date that is none,
    "! a path that is no attribute) - the user enters it.
    CLASS-METHODS apply_pending
      IMPORTING
        session       TYPE clike
        app           TYPE REF TO object
      EXPORTING
        t_refused     TYPE string_table
      RETURNING
        VALUE(result) TYPE string_table.

    "! What the model sees of the screen: the snapshot JSON, masked.
    CLASS-METHODS get_context
      IMPORTING
        session       TYPE clike
      RETURNING
        VALUE(result) TYPE string
      RAISING
        z2ui5_cx_ui5_util_error.

    "! The JSON schema of an answer.
    CLASS-METHODS get_schema
      RETURNING
        VALUE(result) TYPE string.

    "! The system prompt - may_act: proposals allowed.
    CLASS-METHODS get_system
      IMPORTING
        may_act       TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CLASS-METHODS session_new
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_session.

    CLASS-METHODS mask
      IMPORTING
        io_snap       TYPE REF TO z2ui5_cl_agent_snapshot
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS check_protected
      IMPORTING
        io_snap       TYPE REF TO z2ui5_cl_agent_snapshot
        field         TYPE string
      EXPORTING
        label         TYPE string
        path          TYPE string
        kind          TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS validate
      IMPORTING
        session       TYPE string
        io_snap       TYPE REF TO z2ui5_cl_agent_snapshot
      CHANGING
        cs_proposal   TYPE ty_s_proposal.

    CLASS-METHODS values_json
      IMPORTING
        t_value       TYPE ty_t_value
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS write
      IMPORTING
        app  TYPE REF TO object
        path TYPE string
        val  TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    CLASS-METHODS date_of
      IMPORTING
        value         TYPE string
        path          TYPE string
      RETURNING
        VALUE(result) TYPE d.

    CLASS-METHODS time_of
      IMPORTING
        value         TYPE string
        path          TYPE string
      RETURNING
        VALUE(result) TYPE t.

ENDCLASS.


CLASS z2ui5_cl_agent_assist IMPLEMENTATION.

  METHOD session_new.

    result = NEW #( client = c_client
                    mode   = z2ui5_cl_agent_session=>cs_mode-copilot ).

  ENDMETHOD.

  METHOD attach.

    DATA(ls_result) = session_new( )->app_attach( draft ).
    IF ls_result-is_error = abap_true.
      result-error = ls_result-text.
      RETURN.
    ENDIF.
    result-ok = abap_true.
    result-session = ls_result-session.
    TRY.
        DATA(lo_json) = z2ui5_cl_ajson=>parse( ls_result-text ).
        result-app = lo_json->get_string( `/app` ).
        result-title = lo_json->get_string( `/title` ).
      CATCH cx_root ##NO_HANDLER.
        " the snapshot is the session's own JSON
    ENDTRY.
    result-description = z2ui5_cl_agent_settings=>get_app_info( result-app )-description.

  ENDMETHOD.

  METHOD get_schema.

    result = `{"type":"object","additionalProperties":false,"required":["answer","found","proposal"],"properties":{` &&
             `"answer":{"type":"string"},"found":{"type":"boolean"},` &&
             `"proposal":{"type":"object","additionalProperties":false,"required":["wanted","summary","event","values"],` &&
             `"properties":{"wanted":{"type":"boolean"},"summary":{"type":"string"},"event":{"type":"string"},` &&
             `"values":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["field","value"],` &&
             `"properties":{"field":{"type":"string"},"value":{"type":"string"}}}}}}}}`.

  ENDMETHOD.

  METHOD get_system.

    DATA lt_line TYPE string_table.

    INSERT `You are the copilot of one screen of an SAP business app (abap2UI5). The user looks at this screen ` &&
           `and asks about it. The screen is given to you as an "agent snapshot": fields (id, path, label, ` &&
           `kind, value, editable), actions (buttons and other events with their label), tables (columns and ` &&
           `the first rows), messages and texts. Values shown as *** are protected - you do not know them.` INTO TABLE lt_line.
    INSERT `Answer only from the snapshot and the app description. When the screen does not contain what the ` &&
           `user asks, say so plainly and set found to false - never guess or invent values, records or ` &&
           `functions. Keep answers short and refer to fields and buttons by their labels.` INTO TABLE lt_line.
    IF may_act = abap_true.
      INSERT `When the user asks you to do something on this screen, you may propose ONE step: set ` &&
             `proposal.wanted true, describe it in summary, list the fields to fill in values (field = the ` &&
             `field id or path from the snapshot, only editable fields, never a protected one; value as text, ` &&
             `a choice by its key, a multichoice by its keys separated by commas, a boolean as true or false) and optionally the action to press in event ` &&
             `(its event name or action id). The user sees the proposal and confirms it with a click before ` &&
             `anything runs. An action marked "policy":"confirm" is never pressed by you: propose the fields, ` &&
             `the user presses it. Otherwise set proposal.wanted false and leave summary, event and values empty.` INTO TABLE lt_line.
    ELSE.
      INSERT `You cannot change the screen: always set proposal.wanted false and leave summary, event and ` &&
             `values empty. Tell the user which fields to fill and which button to press instead.` INTO TABLE lt_line.
    ENDIF.
    result = concat_lines_of( table = lt_line
                              sep   = cl_abap_char_utilities=>newline ).

  ENDMETHOD.

  METHOD get_context.

    result = mask( session_new( )->get_snapshot( session ) ).

  ENDMETHOD.

  METHOD mask.

    DATA lt_drop TYPE string_table.

    TRY.
        DATA(lo_json) = z2ui5_cl_ajson=>parse( iv_json            = io_snap->get_json( )
                                               iv_keep_item_order = abap_true ).

        " password inputs and sensitive fields: the model never sees them
        DATA(lv_count) = lines( lo_json->members( `/fields` ) ).
        DO lv_count TIMES.
          DATA(lv_id) = lo_json->get_string( |/fields/{ sy-index }/id| ).
          IF check_protected( io_snap = io_snap
                              field   = lv_id ) = abap_true.
            lo_json->set( iv_path = |/fields/{ sy-index }/value|
                          iv_val  = c_mask ).
          ENDIF.
        ENDDO.

        " columns of tables that are sensitive by name
        DATA(lv_tables) = lines( lo_json->members( `/tables` ) ).
        DO lv_tables TIMES.
          DATA(lv_table) = |/tables/{ sy-index }|.
          DATA(lv_path) = lo_json->get_string( |{ lv_table }/path| ).
          DATA(ls_snap_table) = VALUE z2ui5_cl_agent_snapshot=>ty_s_table( ).
          READ TABLE io_snap->mt_table INTO ls_snap_table
               WITH KEY id = lo_json->get_string( |{ lv_table }/id| ). "#EC CI_SORTSEQ
          DATA(lv_columns) = lines( lo_json->members( |{ lv_table }/columns| ) ).
          DO lv_columns TIMES.
            DATA(lv_column) = lo_json->get_string( |{ lv_table }/columns/{ sy-index }/name| ).
            DATA(lv_column_masked) = z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                                               path = |{ lv_path }/{ lv_column }|
                                                                               name = lv_column ).
            " a cell bound to several fields or an expression ("{IBAN} ({BANK})",
            " "{= ${IBAN} }") is a column COL<n> - judged by the fields its
            " binding reads, by table path and by row path alike
            DATA(ls_cellspec) = VALUE z2ui5_cl_agent_snapshot=>ty_s_cellspec( ).
            READ TABLE ls_snap_table-t_cellspec INTO ls_cellspec WITH KEY name = lv_column. "#EC CI_SORTSEQ
            DATA(lt_read) = z2ui5_cl_agent_snapshot=>binding_paths( ls_cellspec-binding ).
            DELETE lt_read WHERE table_line = lv_column.
            LOOP AT lt_read INTO DATA(lv_read).
              DATA(lv_read_index) = sy-tabix.
              " an absolute path inside a row is judged as it is
              IF strlen( lv_read ) > 0 AND lv_read(1) = `/`.
                DATA(lv_read_name) = lv_read.
                WHILE lv_read_name CS `/`.
                  lv_read_name = substring_after( val = lv_read_name
                                                  sub = `/` ).
                ENDWHILE.
                IF z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                             path = lv_read
                                                             name = lv_read_name ) = abap_true.
                  lv_column_masked = abap_true.
                ENDIF.
                DELETE lt_read INDEX lv_read_index.
                CONTINUE.
              ENDIF.
              IF z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                           path = |{ lv_path }/{ lv_read }|
                                                           name = lv_read ) = abap_true.
                lv_column_masked = abap_true.
              ENDIF.
            ENDLOOP.
            DATA(lv_rows) = lines( lo_json->members( |{ lv_table }/rows| ) ).
            DO lv_rows TIMES.
              DATA(lv_row_masked) = lv_column_masked.
              LOOP AT lt_read INTO lv_read.
                IF z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                             path = |{ lv_path }/{ sy-index - 1 }/{ lv_read }|
                                                             name = lv_read ) = abap_true.
                  lv_row_masked = abap_true.
                ENDIF.
              ENDLOOP.
              " a cell by its model path too (/T_PARTNER/*/IBAN), as the audit log masks it
              IF lo_json->exists( |{ lv_table }/rows/{ sy-index }/{ lv_column }| ) = abap_true
                  AND ( lv_row_masked = abap_true
                        OR z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                                     path = |{ lv_path }/{ sy-index - 1 }/{ lv_column }|
                                                                     name = lv_column ) = abap_true ).
                lo_json->set( iv_path = |{ lv_table }/rows/{ sy-index }/{ lv_column }|
                              iv_val  = c_mask ).
              ENDIF.
            ENDDO.
          ENDDO.
        ENDDO.

        " texts that show a sensitive field ("IBAN: DE89...") - the snapshot
        " keeps which paths each text read
        DATA(lv_texts) = lines( lo_json->members( `/texts` ) ).
        DO lv_texts TIMES.
          DATA(lv_text_path) = |/texts/{ sy-index }|.
          DATA(lv_text_value) = lo_json->get_string( lv_text_path ).
          READ TABLE io_snap->mt_text_source INTO DATA(ls_source)
               WITH KEY text = lv_text_value. "#EC CI_SORTSEQ
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          LOOP AT ls_source-t_path INTO DATA(lv_source).
            DATA(lv_source_name) = lv_source.
            " the field's own name: the last segment of the path
            WHILE lv_source_name CS `/`.
              lv_source_name = substring_after( val = lv_source_name
                                                sub = `/` ).
            ENDWHILE.
            IF z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                         path = lv_source
                                                         name = lv_source_name ) = abap_true
                OR z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                             path = |/{ lv_source }|
                                                             name = lv_source_name ) = abap_true.
              lo_json->set( iv_path = lv_text_path
                            iv_val  = c_mask ).
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDDO.

        " forbidden actions: never proposed, so never shown
        DATA(lv_actions) = lines( lo_json->members( `/actions` ) ).
        DO lv_actions TIMES.
          IF lo_json->get_string( |/actions/{ sy-index }/policy| ) = z2ui5_if_agent_app=>cs_policy-forbidden.
            INSERT |/actions/{ sy-index }| INTO lt_drop INDEX 1.
          ENDIF.
        ENDDO.
        LOOP AT lt_drop INTO DATA(lv_drop).
          lo_json->delete( lv_drop ).
        ENDLOOP.
        result = lo_json->stringify( ).
      CATCH cx_root.
        CLEAR result.
    ENDTRY.

  ENDMETHOD.

  METHOD check_protected.

    DATA lv_index TYPE i.

    CLEAR: label, path, kind.
    " the field app_check( ) resolves the key to: by id, by path, by name in
    " any case - in that order, as the session resolves it
    LOOP AT io_snap->mt_field INTO DATA(ls_field) WHERE id = field. "#EC CI_SORTSEQ
      lv_index = sy-tabix.
      EXIT.
    ENDLOOP.
    IF lv_index = 0.
      LOOP AT io_snap->mt_field INTO ls_field WHERE path = field. "#EC CI_SORTSEQ
        lv_index = sy-tabix.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF lv_index = 0.
      DATA(lv_upper) = to_upper( field ).
      LOOP AT io_snap->mt_field INTO ls_field.
        IF to_upper( ls_field-name ) = lv_upper.
          lv_index = sy-tabix.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF lv_index > 0.
      label = ls_field-label.
      path = ls_field-path.
      kind = ls_field-kind.
      IF io_snap->is_secret( ls_field-id ) = abap_true
          OR z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                       path = ls_field-path
                                                       name = ls_field-name ) = abap_true.
        result = abap_true.
      ENDIF.
      RETURN.
    ENDIF.

    " a table cell "<table path or id>/<row>/<COLUMN>": sensitive by its
    " column or by its model path, as the audit log judges it
    DATA(lt_part) = VALUE string_table( ).
    SPLIT field AT `/` INTO TABLE lt_part.
    DATA(lv_count) = lines( lt_part ).
    DATA(lv_column) = VALUE string( lt_part[ lv_count ] OPTIONAL ).
    DATA(lv_path) = CONV string( field ).
    IF lv_count >= 3.
      DATA(lv_row) = VALUE string( lt_part[ lv_count - 1 ] OPTIONAL ).
      DATA(lv_table) = substring( val = field
                                  len = strlen( field ) - strlen( lv_row ) - strlen( lv_column ) - 2 ).
      LOOP AT io_snap->mt_table INTO DATA(ls_table) WHERE id = lv_table OR path = lv_table. "#EC CI_SORTSEQ
        lv_path = |{ ls_table-path }/{ lv_row }/{ lv_column }|.
        LOOP AT ls_table-t_cellspec INTO DATA(ls_spec) WHERE name = lv_column AND has_field_spec = abap_true. "#EC CI_SORTSEQ
          kind = ls_spec-field_kind.
          EXIT.
        ENDLOOP.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF lv_count > 1 AND z2ui5_cl_agent_settings=>check_sensitive( app  = io_snap->mv_app
                                                                  path = lv_path
                                                                  name = lv_column ) = abap_true.
      result = abap_true.
    ENDIF.

  ENDMETHOD.

  METHOD values_json.

    DATA lt_member TYPE string_table.
    DATA lt_key TYPE string_table.
    DATA lt_json TYPE string_table.
    DATA lv_json TYPE string.

    LOOP AT t_value INTO DATA(ls_value).
      IF ls_value-kind = `multichoice`.
        " the proposal's values are text - the session takes a multichoice
        " as an array of keys
        SPLIT ls_value-value AT `,` INTO TABLE lt_key.
        CLEAR lt_json.
        LOOP AT lt_key INTO DATA(lv_key).
          lv_key = condense( lv_key ).
          IF lv_key IS NOT INITIAL.
            INSERT z2ui5_cl_agent_viewxml=>json_string( lv_key ) INTO TABLE lt_json.
          ENDIF.
        ENDLOOP.
        lv_json = |[{ concat_lines_of( table = lt_json
                                       sep   = `,` ) }]|.
      ELSE.
        lv_json = z2ui5_cl_agent_viewxml=>json_string( ls_value-value ).
      ENDIF.
      INSERT |{ z2ui5_cl_agent_viewxml=>json_string( ls_value-field ) }:{ lv_json }| INTO TABLE lt_member.
    ENDLOOP.
    IF lt_member IS NOT INITIAL.
      result = |\{{ concat_lines_of( table = lt_member
                                     sep   = `,` ) }\}|.
    ENDIF.

  ENDMETHOD.

  METHOD ask.

    DATA lt_message TYPE z2ui5_if_agent_llm=>ty_t_message.
    DATA lv_context TYPE string.
    DATA lo_snap TYPE REF TO z2ui5_cl_agent_snapshot.

    DATA(lv_session) = CONV string( session ).
    TRY.
        lo_snap = session_new( )->get_snapshot( lv_session ).
        lv_context = mask( lo_snap ).
      CATCH cx_root INTO DATA(lx_session).
        result-error = lx_session->get_text( ).
        RETURN.
    ENDTRY.
    DATA(lv_may_act) = z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-copilot_act ).
    DATA(lv_description) = z2ui5_cl_agent_settings=>get_app_info( lo_snap->mv_app )-description.

    " the conversation so far, then the screen as it is now and the question
    LOOP AT t_turn INTO DATA(ls_turn) WHERE text IS NOT INITIAL. "#EC CI_SORTSEQ
      IF ls_turn-role <> z2ui5_if_agent_llm=>cs_role-user AND ls_turn-role <> z2ui5_if_agent_llm=>cs_role-assistant.
        CONTINUE.
      ENDIF.
      IF lt_message IS INITIAL AND ls_turn-role <> z2ui5_if_agent_llm=>cs_role-user.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( role    = ls_turn-role
                      content = ls_turn-text ) INTO TABLE lt_message.
    ENDLOOP.
    INSERT VALUE #( role    = z2ui5_if_agent_llm=>cs_role-user
                    content = |The app: { lo_snap->mv_app }{ COND #( WHEN lv_description IS NOT INITIAL THEN | - { lv_description }| ) }| &&
                              |{ cl_abap_char_utilities=>newline }The screen now (agent snapshot v1):| &&
                              |{ cl_abap_char_utilities=>newline }{ lv_context }| &&
                              |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }The question: { question }| )
           INTO TABLE lt_message.

    TRY.
        DATA(ls_answer) = z2ui5_cl_agent_llm=>create( )->chat( VALUE #( purpose   = `copilot`
                                                                         app       = lo_snap->mv_app
                                                                         system    = get_system( lv_may_act )
                                                                         t_message = lt_message
                                                                         schema    = get_schema( ) ) ).
        result-text = ls_answer-json->get_string( `/answer` ).
        result-found = ls_answer-json->get_boolean( `/found` ).
        result-proposal-present = ls_answer-json->get_boolean( `/proposal/wanted` ).
        IF result-proposal-present = abap_true.
          result-proposal-summary = ls_answer-json->get_string( `/proposal/summary` ).
          result-proposal-event = condense( ls_answer-json->get_string( `/proposal/event` ) ).
          DATA(lv_count) = lines( ls_answer-json->members( `/proposal/values` ) ).
          DO lv_count TIMES.
            INSERT VALUE #( field = condense( ls_answer-json->get_string( |/proposal/values/{ sy-index }/field| ) )
                            value = ls_answer-json->get_string( |/proposal/values/{ sy-index }/value| ) )
                   INTO TABLE result-proposal-t_value.
          ENDDO.
        ENDIF.
        result-ok = abap_true.
      CATCH cx_root INTO DATA(lx).
        result-error = lx->get_text( ).
        RETURN.
    ENDTRY.

    IF result-proposal-present = abap_false.
      RETURN.
    ENDIF.
    IF lv_may_act = abap_false.
      result-proposal-reason = `the copilot may not act on this system (setting copilot_act) - it answers only`.
      RETURN.
    ENDIF.
    IF result-proposal-event IS INITIAL AND result-proposal-t_value IS INITIAL.
      result-proposal-reason = `the proposal names neither a field nor an action`.
      RETURN.
    ENDIF.
    validate( EXPORTING session     = lv_session
                        io_snap     = lo_snap
              CHANGING  cs_proposal = result-proposal ).

  ENDMETHOD.

  METHOD validate.

    DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
    DATA lv_found TYPE abap_bool.

    " the fields: on the screen and not protected
    LOOP AT cs_proposal-t_value REFERENCE INTO DATA(lr_value).
      IF check_protected( EXPORTING io_snap = io_snap
                                    field   = lr_value->field
                          IMPORTING label   = lr_value->label
                                    path    = lr_value->path
                                    kind    = lr_value->kind ) = abap_true.
        cs_proposal-reason = |the field { lr_value->field } is protected (a password or sensitive field) - the copilot never fills it|.
        RETURN.
      ENDIF.
    ENDLOOP.

    " the action and its policy - a forbidden one is never offered
    IF cs_proposal-event IS NOT INITIAL.
      " an action id first, then the first ENABLED action of the event - as
      " the session resolves it (find_action), so the label the user
      " confirms and the action that runs are the same control
      lv_found = abap_false.
      LOOP AT io_snap->mt_action INTO ls_action
           WHERE id = cs_proposal-event AND frontend IS INITIAL. "#EC CI_SORTSEQ
        lv_found = abap_true.
        EXIT.
      ENDLOOP.
      IF lv_found = abap_false.
        LOOP AT io_snap->mt_action INTO ls_action
             WHERE event = cs_proposal-event AND enabled = abap_true AND frontend IS INITIAL. "#EC CI_SORTSEQ
          lv_found = abap_true.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF lv_found = abap_false.
        LOOP AT io_snap->mt_action INTO ls_action
             WHERE event = cs_proposal-event AND frontend IS INITIAL. "#EC CI_SORTSEQ
          lv_found = abap_true.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF lv_found = abap_false.
        cs_proposal-reason = |there is no action { cs_proposal-event } on this screen|.
        RETURN.
      ENDIF.
      cs_proposal-event = ls_action-event.
      cs_proposal-action = ls_action-id.
      cs_proposal-label = ls_action-label.
      cs_proposal-policy = COND #( WHEN ls_action-policy IS INITIAL THEN z2ui5_if_agent_app=>cs_policy-allowed
                                   ELSE ls_action-policy ).
      IF cs_proposal-policy = z2ui5_if_agent_app=>cs_policy-forbidden.
        cs_proposal-reason = |the action { ls_action-label } ({ ls_action-event }) is forbidden for agents - the copilot never offers it|.
        RETURN.
      ENDIF.
      cs_proposal-needs_human = xsdbool( cs_proposal-policy = z2ui5_if_agent_app=>cs_policy-confirm ).
    ENDIF.

    " the rest exactly as the MCP endpoint's app_act checks it, without the act
    DATA(ls_check) = session_new( )->app_check( session = session
                                                values  = values_json( cs_proposal-t_value )
                                                event   = COND string( WHEN cs_proposal-needs_human = abap_false
                                                                  THEN cs_proposal-action ) ).
    IF ls_check-is_error = abap_true.
      cs_proposal-reason = ls_check-text.
      RETURN.
    ENDIF.
    cs_proposal-valid = abap_true.

  ENDMETHOD.

  METHOD act.

    DATA lt_text TYPE string_table.

    IF is_proposal-valid = abap_false.
      result-error = `only a validated proposal runs`.
      RETURN.
    ENDIF.
    DATA(lo_session) = session_new( ).
    DATA(lv_fire) = xsdbool( is_proposal-event IS NOT INITIAL AND is_proposal-needs_human = abap_false ).
    " the session validates all of it again - and never fires a confirm or
    " forbidden event
    DATA(ls_result) = lo_session->app_act( session = session
                                           values  = values_json( is_proposal-t_value )
                                           event   = COND string( WHEN lv_fire = abap_true
                                                                  THEN COND #( WHEN is_proposal-action IS NOT INITIAL
                                                                               THEN is_proposal-action
                                                                               ELSE is_proposal-event ) ) ).
    IF ls_result-is_error = abap_true.
      result-error = ls_result-text.
      result-session = session.
      RETURN.
    ENDIF.
    result-ok = abap_true.
    result-session = ls_result-session.

    IF lv_fire = abap_false.
      result-text = COND #( WHEN is_proposal-needs_human = abap_true
                            THEN |Filled { lines( is_proposal-t_value ) } field(s). Press "{ is_proposal-label }" on the screen yourself - | &&
                                 |the app asks for a person there, so the copilot never presses it.|
                            ELSE |Filled { lines( is_proposal-t_value ) } field(s) - they are on the screen when you close the copilot.| ).
      RETURN.
    ENDIF.
    TRY.
        DATA(lo_json) = z2ui5_cl_ajson=>parse( ls_result-text ).
        DATA(lv_count) = lines( lo_json->members( `/messages` ) ).
        DO lv_count TIMES.
          INSERT lo_json->get_string( |/messages/{ sy-index }/text| ) INTO TABLE lt_text.
        ENDDO.
      CATCH cx_root ##NO_HANDLER.
        " the snapshot is the session's own JSON
    ENDTRY.
    result-text = |Done: { is_proposal-label }.{ COND #( WHEN lt_text IS NOT INITIAL
                                                         THEN | The app says: { concat_lines_of( table = lt_text
                                                                                                 sep   = ` / ` ) }| ) }| &&
                  ` You see it when you close the copilot.`.

  ENDMETHOD.

  METHOD apply_pending.

    CLEAR t_refused.
    TRY.
        DATA(lo_snap) = session_new( )->get_snapshot( session ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    " each value with its model: one typed into a dialog was read from the
    " main model - the stale value there written over the user's, and the
    " path reported as filled
    LOOP AT lo_snap->get_pending( ) INTO DATA(ls_pending).
      IF ls_pending-model_key <> z2ui5_cl_agent_snapshot=>cs_model-main.
        INSERT |{ ls_pending-path } was typed into a dialog - enter it yourself| INTO TABLE t_refused.
        CONTINUE.
      ENDIF.
      TRY.
          write( app  = app
                 path = ls_pending-path
                 val  = ls_pending-val ).
          INSERT ls_pending-path INTO TABLE result.
        CATCH cx_root INTO DATA(lx).
          " a path that is no attribute: the user enters it
          INSERT lx->get_text( ) INTO TABLE t_refused.
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.

  METHOD write.

    DATA lt_segment TYPE string_table.
    DATA lo_object TYPE REF TO object.
    FIELD-SYMBOLS <current> TYPE any.
    FIELD-SYMBOLS <table> TYPE ANY TABLE.
    FIELD-SYMBOLS <next> TYPE any.

    SPLIT path AT `/` INTO TABLE lt_segment.
    DELETE lt_segment WHERE table_line IS INITIAL.
    IF lt_segment IS INITIAL.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path } is no attribute path of the app|.
    ENDIF.

    LOOP AT lt_segment INTO DATA(lv_segment).
      IF sy-tabix = 1.
        DATA(lv_attribute) = to_upper( lv_segment ).
        ASSIGN app->(lv_attribute) TO <current>.
      ELSE.
        DATA(lo_type) = cl_abap_typedescr=>describe_by_data( <current> ).
        " a failed ASSIGN leaves <next> where the last segment put it
        UNASSIGN <next>.
        IF lo_type->kind = cl_abap_typedescr=>kind_table.
          ASSIGN <current> TO <table>.
          DATA(lv_index) = CONV i( lv_segment ) + 1.
          DATA(lv_tabix) = 0.
          LOOP AT <table> ASSIGNING FIELD-SYMBOL(<row>).
            lv_tabix = lv_tabix + 1.
            IF lv_tabix = lv_index.
              ASSIGN <row> TO <next>.
              EXIT.
            ENDIF.
          ENDLOOP.
        ELSEIF lo_type->type_kind = cl_abap_typedescr=>typekind_oref.
          " an attribute of an object the app holds - abap2UI5 binds
          " MO_SUB->VALUE as /MO_SUB/VALUE
          lo_object = <current>.
          IF lo_object IS BOUND.
            DATA(lv_member) = to_upper( lv_segment ).
            ASSIGN lo_object->(lv_member) TO <next>.
          ENDIF.
        ELSE.
          ASSIGN COMPONENT to_upper( lv_segment ) OF STRUCTURE <current> TO <next>.
        ENDIF.
        IF <next> IS NOT ASSIGNED.
          RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path } is no attribute path of the app|.
        ENDIF.
        ASSIGN <next> TO <current>.
      ENDIF.
      IF <current> IS NOT ASSIGNED.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path } is no attribute path of the app|.
      ENDIF.
    ENDLOOP.

    DATA(lv_text) = z2ui5_cl_agent_viewxml=>val_to_string( val ).
    DATA(lo_target) = cl_abap_typedescr=>describe_by_data( <current> ).
    CASE val-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-boolean.
        <current> = xsdbool( lv_text = `true` ).
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-number.
        <current> = val-num.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-array.
        " a multichoice: its keys into the table the app binds selectedKeys to
        IF lo_target->kind <> cl_abap_typedescr=>kind_table.
          RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path } holds no list - the keys { lv_text } do not fit|.
        ENDIF.
        TRY.
            z2ui5_cl_ajson=>parse( val-json )->to_abap( IMPORTING ev_container = <current> ).
          CATCH cx_root INTO DATA(lx).
            RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: the keys { lv_text } do not fit - { lx->get_text( ) }|.
        ENDTRY.
      WHEN OTHERS.
        IF lo_target->type_kind = cl_abap_typedescr=>typekind_date.
          <current> = date_of( value = lv_text
                               path  = path ).
        ELSEIF lo_target->type_kind = cl_abap_typedescr=>typekind_time.
          <current> = time_of( value = lv_text
                               path  = path ).
        ELSE.
          <current> = lv_text.
        ENDIF.
    ENDCASE.

  ENDMETHOD.

  METHOD date_of.

    " as the model shows a date (2026-10-06) or as ABAP holds it (20261006),
    " and a day the calendar has - anything else is refused, never written
    " as a date that is none
    DATA(lv_date) = condense( value ).
    IF lv_date IS INITIAL.
      RETURN.
    ENDIF.
    IF strlen( lv_date ) = 10.
      IF substring( val = lv_date
                    off = 4
                    len = 1 ) = `-` AND substring( val = lv_date
                                                   off = 7
                                                   len = 1 ) = `-`.
        lv_date = substring( val = lv_date
                             len = 4 ) && substring( val = lv_date
                                                     off = 5
                                                     len = 2 ) && substring( val = lv_date
                                                                             off = 8
                                                                             len = 2 ).
      ENDIF.
    ENDIF.
    IF strlen( lv_date ) <> 8 OR lv_date CN `0123456789`.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: '{ value }' is no date (YYYY-MM-DD)|.
    ENDIF.
    DATA(lv_year) = CONV i( substring( val = lv_date
                                       len = 4 ) ).
    DATA(lv_month) = CONV i( substring( val = lv_date
                                        off = 4
                                        len = 2 ) ).
    DATA(lv_day) = CONV i( substring( val = lv_date
                                      off = 6
                                      len = 2 ) ).
    DATA(lv_last) = 31.
    IF lv_month = 4 OR lv_month = 6 OR lv_month = 9 OR lv_month = 11.
      lv_last = 30.
    ELSEIF lv_month = 2.
      lv_last = COND #( WHEN ( lv_year MOD 4 = 0 AND lv_year MOD 100 <> 0 ) OR lv_year MOD 400 = 0 THEN 29 ELSE 28 ).
    ENDIF.
    IF lv_year < 1 OR lv_month < 1 OR lv_month > 12 OR lv_day < 1 OR lv_day > lv_last.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: '{ value }' is no date of the calendar|.
    ENDIF.
    result = lv_date.

  ENDMETHOD.

  METHOD time_of.

    DATA lt_part TYPE string_table.
    DATA lv_time TYPE string.
    DATA lv_max TYPE i.

    " as the model shows a time (09:30:00), without seconds (9:30) or as
    " ABAP holds it (093000), and a time the clock has - anything else is
    " refused, never written as a time that is none
    DATA(lv_value) = condense( value ).
    IF lv_value IS INITIAL.
      RETURN.
    ENDIF.
    IF lv_value CA `:`.
      SPLIT lv_value AT `:` INTO TABLE lt_part.
    ELSEIF strlen( lv_value ) = 6.
      INSERT substring( val = lv_value
                        len = 2 ) INTO TABLE lt_part.
      INSERT substring( val = lv_value
                        off = 2
                        len = 2 ) INTO TABLE lt_part.
      INSERT substring( val = lv_value
                        off = 4
                        len = 2 ) INTO TABLE lt_part.
    ENDIF.
    IF lines( lt_part ) = 2.
      INSERT `00` INTO TABLE lt_part.
    ENDIF.
    IF lines( lt_part ) <> 3.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: '{ value }' is no time (HH:MM or HH:MM:SS)|.
    ENDIF.
    LOOP AT lt_part INTO DATA(lv_part).
      " the hour in one or two digits, minutes and seconds in two
      lv_max = 59.
      IF sy-tabix = 1.
        lv_max = 23.
      ELSEIF strlen( lv_part ) <> 2.
        CLEAR lv_part.
      ENDIF.
      IF lv_part IS INITIAL OR lv_part CN `0123456789` OR strlen( lv_part ) > 2.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: '{ value }' is no time (HH:MM or HH:MM:SS)|.
      ENDIF.
      IF CONV i( lv_part ) > lv_max.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = |{ path }: '{ value }' is no time (HH:MM or HH:MM:SS)|.
      ENDIF.
      lv_time = |{ lv_time }{ lv_part WIDTH = 2 ALIGN = RIGHT PAD = `0` }|.
    ENDLOOP.
    result = lv_time.

  ENDMETHOD.

ENDCLASS.
