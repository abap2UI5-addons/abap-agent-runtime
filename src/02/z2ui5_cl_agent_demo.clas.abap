"! An abap2UI5 app that opts in for agents - the example of the agent addon
"! and what its unit tests drive. A travel request: a form with a departure
"! date, a table with a row action and row selection, a popup that closes
"! in the browser, a trip plan with tags (a multichoice) and a structure
"! that holds a table of stops, two value helps - a SelectDialog for the
"! destination (one row is picked) and a TableSelectDialog for the tags
"! (several rows) - and three events of each policy: ADD and PLAN are
"! allowed, SUBMIT needs a human (confirm), DELETE_ALL is forbidden for
"! agents. The IBAN is sensitive - the audit log masks it.
"!
"! Start it in the browser with ?app_start=z2ui5_cl_agent_demo, or as an
"! agent with app_start { "app": "z2ui5_cl_agent_demo" }. The button in the
"! page header opens the in-app copilot (z2ui5_cl_agent_copilot) - an
"! agent never presses it (the settings classify it forbidden).
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

    TYPES:
      BEGIN OF ty_s_stop,
        city   TYPE string,
        nights TYPE i,
      END OF ty_s_stop.
    TYPES ty_t_stop TYPE STANDARD TABLE OF ty_s_stop WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_choice,
        key   TYPE string,
        text  TYPE string,
        selkz TYPE abap_bool,
      END OF ty_s_choice.
    TYPES ty_t_choice TYPE STANDARD TABLE OF ty_s_choice WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_trip,
        purpose TYPE string,
        t_stop  TYPE ty_t_stop,
      END OF ty_s_trip.

    DATA name        TYPE string.
    DATA destination TYPE string.
    DATA days        TYPE i.
    DATA hotel       TYPE abap_bool.
    DATA iban        TYPE string.
    DATA note        TYPE string.
    DATA status      TYPE string.
    DATA t_request   TYPE ty_t_request.
    DATA tags        TYPE string_table.
    DATA trip        TYPE ty_s_trip.
    DATA departure   TYPE d.
    DATA t_dest      TYPE ty_t_choice.
    DATA t_tag       TYPE ty_t_choice.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS view_display.
    METHODS popup_display.
    METHODS dest_help_display.
    METHODS tags_help_display.
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

    " the in-app copilot - the one line in main( ), the button in the page header
    IF z2ui5_cl_agent_copilot=>attach( client ) = abap_true.
      RETURN.
    ENDIF.
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

    page->ele( `headerContent`
        )->tag( `Button`
            )->a( n = `icon`    v = `sap-icon://discussion`
            )->a( n = `tooltip` v = `Copilot - ask this screen`
            )->a( n = `press`   v = client->_event( z2ui5_cl_agent_copilot=>c_event ) ).

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
                )->a( n = `value` v = client->_bind( iban )
            )->tag( `Label`
                )->a( n = `text` v = `Tags`
            )->ele( `MultiComboBox`
                )->a( n = `selectedKeys` v = client->_bind( tags )
                )->ele( `items`

                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `FAIR`
                        )->a( n = `text` v = `Trade fair`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `MEET`
                        )->a( n = `text` v = `Customer meeting`
                    )->tag( n = `Item` ns = `core`
                        )->a( n = `key`  v = `TRAIN`
                        )->a( n = `text` v = `Training`

                )->end(
            )->end(

            )->tag( `Label`
                )->a( n = `text` v = `Purpose`
            )->tag( `Input`
                )->a( n = `value` v = client->_bind( trip-purpose )
            )->tag( `Label`
                )->a( n = `text` v = `Departure`
            )->tag( `DatePicker`
                )->a( n = `value`       v = client->_bind( departure )
                )->a( n = `valueFormat` v = `yyyy-MM-dd` ).

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

    page->ele( `Table`
        )->a( n = `headerText` v = `Stops`
        )->a( n = `items`      v = client->_bind( trip-t_stop )
        )->ele( `columns`

            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `City`
            )->end(
            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Nights`
            )->end(

        )->end(
        )->ele( `items`
            )->ele( `ColumnListItem`
                )->ele( `cells`

                    )->tag( `Text`
                        )->a( n = `text` v = `{CITY}`
                    )->tag( `Input`
                        )->a( n = `value` v = `{NIGHTS}` ).

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
                )->a( n = `text`  v = `Plan`
                )->a( n = `press` v = client->_event( `PLAN` )
            )->tag( `Button`
                )->a( n = `text`  v = `Add`
                )->a( n = `press` v = client->_event( `ADD` )
            )->tag( `Button`
                )->a( n = `text`  v = `Submit`
                )->a( n = `type`  v = `Emphasized`
                )->a( n = `press` v = client->_event( `SUBMIT` )
            )->tag( `Button`
                )->a( n = `text`  v = `Pick destination`
                )->a( n = `press` v = client->_event( `DEST_HELP` )
            )->tag( `Button`
                )->a( n = `text`  v = `Pick tags`
                )->a( n = `press` v = client->_event( `TAGS_HELP` ) ).

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

  METHOD dest_help_display.

    " a value help: one row is picked - its SELKZ travels with the confirm,
    " the picked item's title is the event argument
    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `FragmentDefinition` ns = `core`
            )->a( n = `xmlns`      v = `sap.m`
            )->a( n = `xmlns:core` v = `sap.ui.core` ).

    popup->ele( `SelectDialog`
        )->a( n = `title`   v = `Destinations`
        )->a( n = `items`   v = client->_bind( t_dest )
        )->a( n = `confirm` v = client->_event( val = `DEST_PICKED`
                                                arg = `${$parameters>/selectedItem}.getTitle()` )
        )->a( n = `cancel`  v = client->_event( `HELP_CANCEL` )
        )->tag( `StandardListItem`
            )->a( n = `title`       v = `{TEXT}`
            )->a( n = `description` v = `{KEY}`
            )->a( n = `selected`    v = `{SELKZ}` ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

  METHOD tags_help_display.

    " a value help for several rows: the ticked rows travel with the OK, the
    " event argument is how many were selected
    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `FragmentDefinition` ns = `core`
            )->a( n = `xmlns`      v = `sap.m`
            )->a( n = `xmlns:core` v = `sap.ui.core` ).

    popup->ele( `TableSelectDialog`
        )->a( n = `title`       v = `Tags`
        )->a( n = `multiSelect` v = `true`
        )->a( n = `items`       v = client->_bind( t_tag )
        )->a( n = `confirm`     v = client->_event( val = `TAGS_PICKED`
                                                    arg = `${$parameters>/selectedContexts/length}` )
        )->a( n = `cancel`      v = client->_event( `HELP_CANCEL` )
        )->ele( `columns`

            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Tag`
            )->end(
            )->ele( `Column`
                )->tag( `Text`
                    )->a( n = `text` v = `Description`
            )->end(

        )->end(
        )->ele( `items`
            )->ele( `ColumnListItem`
                )->a( n = `selected` v = `{SELKZ}`
                )->ele( `cells`

                    )->tag( `Text`
                        )->a( n = `text` v = `{KEY}`
                    )->tag( `Text`
                        )->a( n = `text` v = `{TEXT}` ).

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

      WHEN `PLAN`.
        DATA(lv_nights) = 0.
        LOOP AT trip-t_stop INTO DATA(ls_stop).
          lv_nights = lv_nights + ls_stop-nights.
        ENDLOOP.
        status = |Plan: { trip-purpose }, { lines( trip-t_stop ) } stop(s), { lv_nights } night(s), | &&
                 |tags { COND #( WHEN tags IS INITIAL THEN `none`
                                 ELSE concat_lines_of( table = tags
                                                       sep   = `,` ) ) }, | &&
                 |hotel { COND #( WHEN hotel = abap_true THEN `yes` ELSE `no` ) }|.

      WHEN `SUBMIT`.
        DATA(lv_count) = 0.
        LOOP AT t_request TRANSPORTING NO FIELDS WHERE selkz = abap_true. "#EC CI_SORTSEQ
          lv_count = lv_count + 1.
        ENDLOOP.
        status = |{ lv_count } request(s) submitted|.

      WHEN `DELETE_ALL`.
        CLEAR t_request.
        status = `All requests deleted`.

      WHEN `DEST_HELP`.
        dest_help_display( ).

      WHEN `TAGS_HELP`.
        tags_help_display( ).

      WHEN `HELP_CANCEL`.
        client->popup_destroy( ).

      WHEN `DEST_PICKED`.
        client->popup_destroy( ).
        DATA(lv_selected) = 0.
        LOOP AT t_dest INTO DATA(ls_dest) WHERE selkz = abap_true. "#EC CI_SORTSEQ
          lv_selected = lv_selected + 1.
          destination = ls_dest-key.
        ENDLOOP.
        status = |Destination { destination } ({ client->get_event_arg( ) }), { lv_selected } selected|.

      WHEN `TAGS_PICKED`.
        client->popup_destroy( ).
        CLEAR tags.
        LOOP AT t_tag INTO DATA(ls_tag) WHERE selkz = abap_true. "#EC CI_SORTSEQ
          INSERT ls_tag-key INTO TABLE tags.
        ENDLOOP.
        status = |{ client->get_event_arg( ) } tag(s) picked: { concat_lines_of( table = tags
                                                                               sep   = `,` ) }|.

    ENDCASE.

  ENDMETHOD.

  METHOD model_init.

    destination = `BER`.
    days = 3.
    t_request = VALUE #( ( id = 1 name = `Alice` destination = `PAR` days = 2 )
                         ( id = 2 name = `Bob`   destination = `ROM` days = 5 ) ).
    t_dest = VALUE #( ( key = `BER` text = `Berlin` )
                      ( key = `PAR` text = `Paris` )
                      ( key = `ROM` text = `Rome` ) ).
    t_tag = VALUE #( ( key = `FAIR`  text = `Trade fair` )
                     ( key = `MEET`  text = `Customer meeting` )
                     ( key = `TRAIN` text = `Training` ) ).
    trip = VALUE #( purpose = `Customer visit`
                    t_stop  = VALUE #( ( city = `Lyon` nights = 1 )
                                       ( city = `Nice` nights = 2 ) ) ).

  ENDMETHOD.

ENDCLASS.
