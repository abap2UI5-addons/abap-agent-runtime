"! An abap2UI5 app that opts in for agents - the example of the agent addon
"! and what its unit tests drive. A travel request: a form, a table with a
"! row action and row selection, a popup that closes in the browser, and
"! three events of each policy: ADD and CHECK are allowed, SUBMIT needs a
"! human (confirm), DELETE_ALL is forbidden for agents. The IBAN is
"! sensitive - the audit log masks it.
"!
"! Start it in the browser with ?app_start=z2ui5_cl_agent_demo, or as an
"! agent with app_start { "app": "z2ui5_cl_agent_demo" }.
CLASS z2ui5_cl_agent_demo DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.
    INTERFACES z2ui5_if_agent_app.

    TYPES:
      BEGIN OF ty_s_request,
        id          TYPE i,
        name        TYPE string,
        destination TYPE string,
        days        TYPE i,
        hotel       TYPE abap_bool,
        selkz       TYPE abap_bool,
      END OF ty_s_request.
    TYPES ty_t_request TYPE STANDARD TABLE OF ty_s_request WITH EMPTY KEY.

    DATA name        TYPE string.
    DATA destination TYPE string.
    DATA days        TYPE i.
    DATA hotel       TYPE abap_bool.
    DATA iban        TYPE string.
    DATA note        TYPE string.
    DATA status      TYPE string.
    DATA t_request   TYPE ty_t_request.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS view_display.
    METHODS popup_display.
    METHODS on_event.
    METHODS model_init.

  PRIVATE SECTION.

ENDCLASS.


CLASS z2ui5_cl_agent_demo IMPLEMENTATION.

  METHOD z2ui5_if_agent_app~describe.

    result-description = `Travel requests - the example app of the abap2UI5 agent addon`.
    result-t_event = VALUE #( ( event = `SUBMIT`  policy = z2ui5_if_agent_app=>cs_policy-confirm )
                              ( event = `DELETE*` policy = z2ui5_if_agent_app=>cs_policy-forbidden ) ).
    result-t_sensitive = VALUE #( ( `/IBAN` ) ).

  ENDMETHOD.

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
            )->a( n = `title` v = `Travel requests` ).

    page->tag( `MessageStrip`
        )->a( n = `text`     v = client->_bind( status )
        )->a( n = `type`     v = `Information`
        )->a( n = `showIcon` v = `true`
        )->a( n = `visible`  v = |\{= $\{{ client->_bind_path( status ) }\} !== '' \}| ).

    page->ele( n = `SimpleForm` ns = `form`
        )->a( n = `title`    v = `New request`
        )->a( n = `editable` v = `true`
        )->ele( n = `content` ns = `form`

            )->tag( `Label`
                )->a( n = `text`     v = `Name`
                )->a( n = `required` v = `true`
            )->tag( `Input`
                )->a( n = `value` v = client->_bind( name )
            )->tag( `Label`
                )->a( n = `text` v = `Destination`
            )->ele( `Select`
                )->a( n = `selectedKey` v = client->_bind( destination )
                )->ele( `items`

                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `BER`
                        )->a( n = `text` v = `Berlin`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `PAR`
                        )->a( n = `text` v = `Paris`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `ROM`
                        )->a( n = `text` v = `Rome`

                )->end(
            )->end(

            )->tag( `Label`
                )->a( n = `text` v = `Days`
            )->tag( `Input`
                )->a( n = `type`  v = `Number`
                )->a( n = `value` v = client->_bind( days )
            )->tag( `Label`
                )->a( n = `text` v = `Hotel`
            )->tag( `CheckBox`
                )->a( n = `selected` v = client->_bind( hotel )
                )->a( n = `text`     v = `with hotel`
            )->tag( `Label`
                )->a( n = `text` v = `IBAN for the refund`
            )->tag( `Input`
                )->a( n = `value` v = client->_bind( iban ) ).

    page->ele( `Table`
        )->a( n = `headerText` v = `Requests`
        )->a( n = `mode`       v = `MultiSelect`
        )->a( n = `items`      v = client->_bind( t_request )
        )->ele( `columns`

            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Id`
            )->end(
            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Name`
            )->end(
            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Destination`
            )->end(
            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Days`
            )->end(

        )->end(
        )->ele( `items`
            )->ele( `ColumnListItem`
                )->a( n = `selected`    v = `{SELKZ}`
                )->a( n = `type`        v = `Detail`
                )->a( n = `detailPress` v = client->_event( val = `DETAIL`
                                                            arg = `${ID}` )
                )->ele( `cells`

                    )->tag( `Text`
                        )->a( n = `text` v = `{ID}`
                    )->tag( `Text`
                        )->a( n = `text` v = `{NAME}`
                    )->tag( `Text`
                        )->a( n = `text` v = `{DESTINATION}`
                    )->tag( `Text`
                        )->a( n = `text` v = `{DAYS}` ).

    page->ele( `footer`
        )->ele( `OverflowToolbar`

            )->tag( `Button`
                )->a( n = `text`  v = `Note`
                )->a( n = `press` v = client->_event( `POPUP_OPEN` )
            )->tag( `ToolbarSpacer`
            )->tag( `Button`
                )->a( n = `text`  v = `Delete all`
                )->a( n = `press` v = client->_event( `DELETE_ALL` )
            )->tag( `Button`
                )->a( n = `text`  v = `Add`
                )->a( n = `press` v = client->_event( `ADD` )
            )->tag( `Button`
                )->a( n = `text`  v = `Submit`
                )->a( n = `type`  v = `Emphasized`
                )->a( n = `press` v = client->_event( `SUBMIT` ) ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

  METHOD popup_display.

    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `FragmentDefinition` ns = `core`
            )->a( n = `xmlns`      v = `sap.m`
            )->a( n = `xmlns:core` v = `sap.ui.core` ).

    DATA(dialog) = popup->ele( `Dialog`
        )->a( n = `title` v = `Note for the approver` ).

    dialog->ele( `content`

        )->tag( `TextArea`
            )->a( n = `value`       v = client->_bind( note )
            )->a( n = `placeholder` v = `Note`
            )->a( n = `width`       v = `100%` ).

    dialog->ele( `buttons`

        )->tag( `Button`
            )->a( n = `text`  v = `Cancel`
            )->a( n = `press` v = client->follow_up_action( client->cs_event-popup_close )
        )->tag( `Button`
            )->a( n = `text`  v = `OK`
            )->a( n = `type`  v = `Emphasized`
            )->a( n = `press` v = client->_event( `POPUP_OK` ) ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

  METHOD on_event.

    CASE client->get_event( ).

      WHEN `ADD`.
        IF name IS INITIAL.
          client->message_box_display( text = `Enter a name first`
                                       type = `error` ).
          RETURN.
        ENDIF.
        INSERT VALUE #( id          = lines( t_request ) + 1
                        name        = name
                        destination = destination
                        days        = days
                        hotel       = hotel ) INTO TABLE t_request.
        status = |Request { lines( t_request ) } added|.
        CLEAR name.
        client->message_toast_display( status ).

      WHEN `DETAIL`.
        DATA(lv_id) = client->get_event_arg( ).
        client->message_box_display( |Request { lv_id }| ).

      WHEN `POPUP_OPEN`.
        popup_display( ).

      WHEN `POPUP_OK`.
        client->popup_destroy( ).
        status = |Note: { note }|.

      WHEN `SUBMIT`.
        DATA(lv_count) = 0.
        LOOP AT t_request TRANSPORTING NO FIELDS WHERE selkz = abap_true. "#EC CI_SORTSEQ
          lv_count = lv_count + 1.
        ENDLOOP.
        status = |{ lv_count } request(s) submitted|.

      WHEN `DELETE_ALL`.
        CLEAR t_request.
        status = `All requests deleted`.

    ENDCASE.

  ENDMETHOD.

  METHOD model_init.

    destination = `BER`.
    days = 3.
    t_request = VALUE #( ( id = 1 name = `Alice` destination = `PAR` days = 2 )
                         ( id = 2 name = `Bob`   destination = `ROM` days = 5 ) ).

  ENDMETHOD.

ENDCLASS.
