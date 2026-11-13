"! The in-app copilot - "ask this screen" for any abap2UI5 app that opts in
"! for agents (z2ui5_if_agent_app, or an administrator's APP rule), with
"! two lines in the app:
"!
"!   METHOD z2ui5_if_app~main.
"!     IF z2ui5_cl_agent_copilot=&gt;attach( client ) = abap_true.
"!       RETURN.
"!     ENDIF.
"!     ...
"!
"!   " anywhere in the view, e.g. the page's headerContent:
"!   )-&gt;tag( `Button`
"!       )-&gt;a( n = `icon`  v = `sap-icon://discussion`
"!       )-&gt;a( n = `press` v = client-&gt;_event( z2ui5_cl_agent_copilot=&gt;c_event ) )
"!
"! attach( ) takes the press and calls this app (nav_app_call): a popup on
"! top of the app's screen. It continues a copy of the caller's draft
"! headlessly (z2ui5_cl_agent_assist), so the question is answered from the
"! agent snapshot of exactly the screen the user sees - the values sent
"! with the press included - and every proposed action is validated like
"! an agent's app_act and runs only after the user's click. Closing the
"! copilot returns to the app: unchanged, or in the state the confirmed
"! actions left it in, with filled fields in place. README, "In-app copilot".
CLASS z2ui5_cl_agent_copilot DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    CONSTANTS c_event TYPE string VALUE z2ui5_cl_agent_settings=>c_copilot_event.

    TYPES:
      BEGIN OF ty_s_turn,
        role TYPE string,
        who  TYPE string,
        text TYPE string,
      END OF ty_s_turn.
    TYPES ty_t_turn TYPE STANDARD TABLE OF ty_s_turn WITH DEFAULT KEY.

    DATA t_turn         TYPE ty_t_turn.
    DATA question       TYPE string.
    DATA title          TYPE string.
    DATA proposal_text  TYPE string.
    DATA proposal_label TYPE string.
    DATA has_proposal   TYPE abap_bool.
    DATA ready          TYPE abap_bool.

    "! The opt-in line of an app's main( ): opens the copilot when the
    "! copilot button was pressed - then the app's main( ) returns.
    CLASS-METHODS attach
      IMPORTING
        client        TYPE REF TO z2ui5_if_client
      RETURNING
        VALUE(result) TYPE abap_bool.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.
    DATA session TYPE string.
    DATA changed TYPE abap_bool.
    DATA ms_proposal TYPE z2ui5_cl_agent_assist=>ty_s_proposal.

    METHODS popup_display.
    METHODS on_event.
    METHODS ask.
    METHODS act.
    METHODS close.
    METHODS turn_add
      IMPORTING
        role TYPE string
        text TYPE string.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_copilot IMPLEMENTATION.

  METHOD attach.
    DATA temp1 TYPE REF TO z2ui5_cl_agent_copilot.

    IF client->get_event( ) <> c_event.
      RETURN.
    ENDIF.

    CREATE OBJECT temp1 TYPE z2ui5_cl_agent_copilot.
    client->nav_app_call( temp1 ).
    result = abap_true.

  ENDMETHOD.

  METHOD z2ui5_if_app~main.
      DATA ls_attach TYPE z2ui5_cl_agent_assist=>ty_s_attach.
        DATA temp2 TYPE string.
        DATA temp3 TYPE string.

    me->client = client.
    IF client->check_on_init( ) IS NOT INITIAL.
      " the caller's draft, saved as the press left it

      ls_attach = z2ui5_cl_agent_assist=>attach( client->get( )-s_draft-id_prev_app ).
      " the session and the audit - abap2UI5 rolls back what main( ) leaves open
      COMMIT WORK.
      IF ls_attach-ok = abap_true.
        session = ls_attach-session.
        ready = abap_true.

        IF ls_attach-title IS NOT INITIAL.
          temp2 = |Copilot - { ls_attach-title }|.
        ELSE.
          temp2 = `Copilot`.
        ENDIF.
        title = temp2.

        IF ls_attach-description IS NOT INITIAL.
          temp3 = | ({ ls_attach-description })|.
        ELSE.
          CLEAR temp3.
        ENDIF.
        turn_add( role = `note`
                  text = |Ask about this screen{ temp3 }. | &&
                         `The copilot answers from what the screen shows and proposes steps you confirm.` ).
      ELSE.
        title = `Copilot`.
        turn_add( role = `note`
                  text = |The copilot is not available here: { ls_attach-error }| ).
      ENDIF.
      popup_display( ).
    ELSEIF client->check_on_navigated( ) IS NOT INITIAL.
      popup_display( ).
    ELSEIF client->check_on_event( ) IS NOT INITIAL.
      on_event( ).
    ENDIF.

  ENDMETHOD.

  METHOD turn_add.

    DATA temp4 TYPE z2ui5_cl_agent_copilot=>ty_s_turn.
    DATA temp1 TYPE z2ui5_cl_agent_copilot=>ty_s_turn-who.
    CLEAR temp4.
    temp4-role = role.

    CASE role.
      WHEN `user`.
        temp1 = `You`.
      WHEN `assistant`.
        temp1 = `Copilot`.
      WHEN OTHERS.
        temp1 = ``.
    ENDCASE.
    temp4-who = temp1.
    temp4-text = text.
    INSERT temp4 INTO TABLE t_turn.

  ENDMETHOD.

  METHOD popup_display.

    " afterClose: Escape closes the dialog in the browser alone - without
    " the event the copilot stayed the current app, behind the caller's
    " screen, whose events it ignores
    DATA popup TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA dialog TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA content TYPE REF TO z2ui5_cl_ui5_view_builder.
    popup = z2ui5_cl_ui5_view_builder=>factory( ).

    dialog = popup->ele( n = `FragmentDefinition` ns = `core`
        )->a( n = `xmlns`      v = `sap.m`
        )->a( n = `xmlns:core` v = `sap.ui.core`
        )->ele( `Dialog`
            )->a( n = `title`        v = client->_bind( title )
            )->a( n = `contentWidth` v = `40rem`
            )->a( n = `resizable`    v = `true`
            )->a( n = `afterClose`   v = client->_event( `CLOSE` ) ).


    content = dialog->ele( `content` ).

    content->ele( `List`
        )->a( n = `items`     v = client->_bind( t_turn )
        )->a( n = `showSeparators` v = `Inner`
        )->ele( `items`
            )->tag( `StandardListItem`
                )->a( n = `title`       v = `{WHO}`
                )->a( n = `description` v = `{TEXT}`
                )->a( n = `wrapping`    v = `true` ).

    content->ele( `VBox`
        )->a( n = `class`   v = `sapUiSmallMargin`
        )->a( n = `visible` v = client->_bind( has_proposal )
        )->tag( `MessageStrip`
            )->a( n = `text`     v = client->_bind( proposal_text )
            )->a( n = `type`     v = `Information`
            )->a( n = `showIcon` v = `true`
        )->ele( `HBox`
            )->tag( `Button`
                )->a( n = `text`  v = client->_bind( proposal_label )
                )->a( n = `type`  v = `Emphasized`
                )->a( n = `press` v = client->_event( `DO` )
            )->tag( `Button`
                )->a( n = `text`  v = `Discard`
                )->a( n = `press` v = client->_event( `DISCARD` ) ).

    content->ele( `HBox`
        )->a( n = `class` v = `sapUiSmallMargin`
        )->tag( `Input`
            )->a( n = `value`       v = client->_bind( question )
            )->a( n = `placeholder` v = `Ask about this screen`
            )->a( n = `enabled`     v = client->_bind( ready )
            )->a( n = `width`       v = `30rem`
            )->a( n = `submit`      v = client->_event( `ASK` )
        )->tag( `Button`
            )->a( n = `text`    v = `Ask`
            )->a( n = `icon`    v = `sap-icon://paper-plane`
            )->a( n = `enabled` v = client->_bind( ready )
            )->a( n = `press`   v = client->_event( `ASK` ) ).

    dialog->ele( `endButton`
        )->tag( `Button`
            )->a( n = `text`  v = `Close`
            )->a( n = `press` v = client->_event( `CLOSE` ) ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

  METHOD on_event.

    CASE client->get_event( ).

      WHEN `ASK`.
        ask( ).

      WHEN `DO`.
        act( ).

      WHEN `DISCARD`.
        CLEAR: ms_proposal, has_proposal, proposal_text, proposal_label.
        turn_add( role = `note`
                  text = `Proposal discarded - nothing was changed.` ).

      WHEN `CLOSE`.
        close( ).

    ENDCASE.

  ENDMETHOD.

  METHOD ask.

    DATA lt_turn TYPE z2ui5_cl_agent_assist=>ty_t_turn.
    DATA ls_turn LIKE LINE OF t_turn.
      DATA temp5 TYPE z2ui5_cl_agent_assist=>ty_s_turn.
    DATA lv_question LIKE question.
    DATA ls_answer TYPE z2ui5_cl_agent_assist=>ty_s_answer.
    DATA temp6 TYPE string_table.
    DATA lt_value LIKE temp6.
    DATA ls_value LIKE LINE OF ms_proposal-t_value.
      DATA temp7 TYPE string.
      DATA temp2 LIKE LINE OF lt_value.
    DATA temp8 TYPE string.
    DATA temp3 TYPE string.
    DATA temp9 TYPE string.

    IF ready = abap_false OR question IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT t_turn INTO ls_turn WHERE role = `user` OR role = `assistant`. "#EC CI_SORTSEQ

      CLEAR temp5.
      temp5-role = ls_turn-role.
      temp5-text = ls_turn-text.
      INSERT temp5 INTO TABLE lt_turn.
    ENDLOOP.

    lv_question = question.
    turn_add( role = `user`
              text = lv_question ).
    CLEAR: question, ms_proposal, has_proposal, proposal_text, proposal_label.


    ls_answer = z2ui5_cl_agent_assist=>ask( session  = session
                                                  question = lv_question
                                                  t_turn   = lt_turn ).
    COMMIT WORK.
    IF ls_answer-ok = abap_false.
      turn_add( role = `note`
                text = |No answer: { ls_answer-error }| ).
      RETURN.
    ENDIF.
    turn_add( role = `assistant`
              text = ls_answer-text ).

    IF ls_answer-proposal-present = abap_false.
      RETURN.
    ENDIF.
    IF ls_answer-proposal-valid = abap_false.
      turn_add( role = `note`
                text = |The copilot suggested a step that is not offered: { ls_answer-proposal-reason }| ).
      RETURN.
    ENDIF.
    ms_proposal = ls_answer-proposal.
    has_proposal = abap_true.

    CLEAR temp6.

    lt_value = temp6.

    LOOP AT ms_proposal-t_value INTO ls_value.

      IF ls_value-label IS NOT INITIAL.
        temp7 = ls_value-label.
      ELSE.
        temp7 = ls_value-field.
      ENDIF.

      temp2 = |{ temp7 } = "{ ls_value-value }"|.
      INSERT temp2
             INTO TABLE lt_value.
    ENDLOOP.

    IF lt_value IS NOT INITIAL.
      temp8 = | - fill { concat_lines_of( table = lt_value sep = `, ` ) }|.
    ELSE.
      CLEAR temp8.
    ENDIF.

    IF ms_proposal-event IS NOT INITIAL AND ms_proposal-needs_human = abap_false.
      temp3 = | - then press "{ ms_proposal-label }"|.
    ELSEIF ms_proposal-needs_human = abap_true.
      temp3 = | - "{ ms_proposal-label }" you press yourself, it needs a person|.
    ELSE.
      CLEAR temp3.
    ENDIF.
    proposal_text = |Proposed: { ms_proposal-summary }| &&
                    |{ temp8 }| &&
                    |{ temp3 }|.

    IF ms_proposal-event IS NOT INITIAL AND ms_proposal-needs_human = abap_false.
      temp9 = |Do it: { ms_proposal-label }|.
    ELSE.
      temp9 = `Fill in`.
    ENDIF.
    proposal_label = temp9.

  ENDMETHOD.

  METHOD act.
    DATA ls_done TYPE z2ui5_cl_agent_assist=>ty_s_done.
    DATA temp10 TYPE string_table.
    DATA lt_refused LIKE temp10.
    DATA temp11 TYPE string.

    IF has_proposal = abap_false.
      RETURN.
    ENDIF.

    ls_done = z2ui5_cl_agent_assist=>act( session     = session
                                                is_proposal = ms_proposal ).
    COMMIT WORK.
    CLEAR: ms_proposal, has_proposal, proposal_text, proposal_label.
    IF ls_done-ok = abap_false.
      turn_add( role = `note`
                text = |Not done: { ls_done-error }| ).
      RETURN.
    ENDIF.
    session = ls_done-session.
    changed = abap_true.
    " a filled value the app cannot take (a date that is none) is left out
    " when the copilot closes - said now, on a copy of the app

    CLEAR temp10.

    lt_refused = temp10.
    z2ui5_cl_agent_assist=>apply_pending( EXPORTING session   = session
                                                    app       = client->get_app( session )
                                          IMPORTING t_refused = lt_refused ).

    IF lt_refused IS NOT INITIAL.
      temp11 = | Not filled - the app does not take it, enter it on the screen yourself: | && |{ concat_lines_of( table = lt_refused sep = `; ` ) }|.
    ELSE.
      CLEAR temp11.
    ENDIF.
    turn_add( role = `note`
              text = ls_done-text && temp11 ).

  ENDMETHOD.

  METHOD close.
    DATA lo_app TYPE REF TO z2ui5_if_app.

    client->popup_destroy( ).
    IF changed = abap_false.
      client->nav_app_leave( ).
      RETURN.
    ENDIF.
    " back to the app in the state the confirmed steps left it in - the
    " filled values that no event sent yet written into it

    lo_app = client->get_app( session ).
    z2ui5_cl_agent_assist=>apply_pending( session = session
                                          app     = lo_app ).
    client->nav_app_leave( lo_app ).

  ENDMETHOD.

ENDCLASS.
