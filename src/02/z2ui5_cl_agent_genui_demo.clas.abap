"! Generative UI, the demo: a week of flights (an internal table filled in
"! code - no DDIC), a sentence ("the flights as a table grouped by carrier,
"! the free seats as a progress bar") and a button. z2ui5_cl_agent_genui
"! asks the language model for a UI tree over exactly this table, validates
"! it and builds the view; the popup shows it, the report below says what
"! was checked or why it was rejected. The generated view may fire
"! ROW_SELECT (with carrier, connection and date of the row) and REFRESH -
"! nothing else.
"!
"! Start it with ?app_start=z2ui5_cl_agent_genui_demo once a language model
"! is configured (z2ui5_cl_agent_app_admin, "Language model"). The unit
"! tests drive it with a language model double.
CLASS z2ui5_cl_agent_genui_demo DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_flight,
        carrid   TYPE string,
        connid   TYPE string,
        fldate   TYPE string,
        cityfrom TYPE string,
        cityto   TYPE string,
        price    TYPE p LENGTH 8 DECIMALS 2,
        currency TYPE string,
        seatsmax TYPE i,
        seatsocc TYPE i,
        status   TYPE string,
      END OF ty_s_flight.
    TYPES ty_t_flight TYPE STANDARD TABLE OF ty_s_flight WITH DEFAULT KEY.

    DATA t_flight   TYPE ty_t_flight.
    DATA request    TYPE string.
    DATA report     TYPE string.
    DATA configured TYPE abap_bool.
    DATA selected   TYPE string.
    DATA generated  TYPE abap_bool.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.
    DATA xml_popup TYPE string.

    METHODS view_display.
    METHODS on_event.
    METHODS generate.
    METHODS model_init.

  PRIVATE SECTION.

    "! This class's name, read at run time - a namespace rename rewrites the
    "! class, never a literal naming it.
    METHODS app_name
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_genui_demo IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ) IS NOT INITIAL.
      model_init( ).
      view_display( ).
    ELSEIF client->check_on_navigated( ) IS NOT INITIAL.
      view_display( ).
    ELSEIF client->check_on_event( ) IS NOT INITIAL.
      on_event( ).
    ENDIF.

  ENDMETHOD.

  METHOD model_init.
    DATA temp1 TYPE z2ui5_cl_agent_genui_demo=>ty_t_flight.
    DATA temp2 LIKE LINE OF temp1.

    request = `the flights as a table grouped by carrier, with the price and the occupied seats`.
    configured = z2ui5_cl_agent_llm=>check_configured( ).

    CLEAR temp1.

    temp2-carrid = `LH`.
    temp2-connid = `0400`.
    temp2-fldate = `2026-10-05`.
    temp2-cityfrom = `Frankfurt`.
    temp2-cityto = `New York`.
    temp2-price = '666.00'.
    temp2-currency = `EUR`.
    temp2-seatsmax = 330.
    temp2-seatsocc = 312.
    temp2-status = `open`.
    INSERT temp2 INTO TABLE temp1.
    temp2-carrid = `LH`.
    temp2-connid = `0402`.
    temp2-fldate = `2026-10-06`.
    temp2-cityfrom = `Frankfurt`.
    temp2-cityto = `New York`.
    temp2-price = '702.50'.
    temp2-currency = `EUR`.
    temp2-seatsmax = 330.
    temp2-seatsocc = 330.
    temp2-status = `full`.
    INSERT temp2 INTO TABLE temp1.
    temp2-carrid = `AA`.
    temp2-connid = `0017`.
    temp2-fldate = `2026-10-05`.
    temp2-cityfrom = `New York`.
    temp2-cityto = `San Francisco`.
    temp2-price = '422.94'.
    temp2-currency = `USD`.
    temp2-seatsmax = 385.
    temp2-seatsocc = 201.
    temp2-status = `open`.
    INSERT temp2 INTO TABLE temp1.
    temp2-carrid = `AA`.
    temp2-connid = `0064`.
    temp2-fldate = `2026-10-07`.
    temp2-cityfrom = `San Francisco`.
    temp2-cityto = `New York`.
    temp2-price = '422.94'.
    temp2-currency = `USD`.
    temp2-seatsmax = 385.
    temp2-seatsocc = 0.
    temp2-status = `cancelled`.
    INSERT temp2 INTO TABLE temp1.
    temp2-carrid = `SQ`.
    temp2-connid = `0002`.
    temp2-fldate = `2026-10-08`.
    temp2-cityfrom = `Singapore`.
    temp2-cityto = `San Francisco`.
    temp2-price = '849.00'.
    temp2-currency = `SGD`.
    temp2-seatsmax = 280.
    temp2-seatsocc = 254.
    temp2-status = `open`.
    INSERT temp2 INTO TABLE temp1.
    temp2-carrid = `JL`.
    temp2-connid = `0407`.
    temp2-fldate = `2026-10-09`.
    temp2-cityfrom = `Tokyo`.
    temp2-cityto = `Frankfurt`.
    temp2-price = '1065.00'.
    temp2-currency = `JPY`.
    temp2-seatsmax = 280.
    temp2-seatsocc = 99.
    temp2-status = `open`.
    INSERT temp2 INTO TABLE temp1.
    t_flight = temp1.

  ENDMETHOD.

  METHOD view_display.

    DATA view TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA page TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA temp1 TYPE xsdboolean.
    DATA table TYPE REF TO z2ui5_cl_ui5_view_builder.
    view = z2ui5_cl_ui5_view_builder=>factory(
        )->ele( n = `View` ns = `mvc`
            )->a( n = `xmlns`        v = `sap.m`
            )->a( n = `xmlns:mvc`    v = `sap.ui.core.mvc`
            )->a( n = `displayBlock` v = `true`
            )->a( n = `height`       v = `100%` ).


    page = view->ele( `Shell`
        )->ele( `Page`
            )->a( n = `title` v = `abap2UI5 agent - generative UI` ).


    temp1 = boolc( configured = abap_false ).
    page->tag( `MessageStrip`
        )->a( n = `text`     v = `No language model is configured - an agent administrator sets it up in z2ui5_cl_agent_app_admin.`
        )->a( n = `type`     v = `Warning`
        )->a( n = `showIcon` v = `true`
        )->a( n = `visible`  b = temp1 ).


    table = page->ele( `Table`
        )->a( n = `headerText` v = `The data the view may show (the app decides - the model never chooses data)`
        )->a( n = `items`      v = client->_bind( t_flight ) ).

    table->ele( `columns`
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Flight`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Date`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Route`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Price`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Seats`
        )->end(
        )->ele( `Column`
            )->tag( `Text`
                )->a( n = `text` v = `Status` ).

    table->ele( `items`
        )->ele( `ColumnListItem`
            )->ele( `cells`

                )->tag( `Text`
                    )->a( n = `text` v = `{CARRID} {CONNID}`
                )->tag( `Text`
                    )->a( n = `text` v = `{FLDATE}`
                )->tag( `Text`
                    )->a( n = `text` v = `{CITYFROM} - {CITYTO}`
                )->tag( `Text`
                    )->a( n = `text` v = `{PRICE} {CURRENCY}`
                )->tag( `Text`
                    )->a( n = `text` v = `{SEATSOCC} / {SEATSMAX}`
                )->tag( `Text`
                    )->a( n = `text` v = `{STATUS}` ).

    page->ele( `VBox`
        )->a( n = `class` v = `sapUiSmallMargin`
        )->tag( `Label`
            )->a( n = `text`     v = `Describe the view you want`
            )->a( n = `labelFor` v = `genuiRequest`
        )->tag( `TextArea`
            )->a( n = `id`          v = `genuiRequest`
            )->a( n = `value`       v = client->_bind( request )
            )->a( n = `width`       v = `100%`
            )->a( n = `rows`        v = `3`
            )->a( n = `placeholder` v = `e.g. the open flights as a list, the free seats as a progress bar`
        )->ele( `HBox`
            )->tag( `Button`
                )->a( n = `text`    v = `Generate`
                )->a( n = `type`    v = `Emphasized`
                )->a( n = `icon`    v = `sap-icon://create`
                )->a( n = `enabled` b = configured
                )->a( n = `press`   v = client->_event( `GENERATE` )
            )->tag( `Button`
                )->a( n = `text`    v = `Show again`
                )->a( n = `enabled` v = client->_bind( generated )
                )->a( n = `press`   v = client->_event( `SHOW` )
        )->end(
        )->tag( `Label`
            )->a( n = `text` v = `Validation report`
        )->tag( `Text`
            )->a( n = `text` v = client->_bind( report )
        )->tag( `Text`
            )->a( n = `text` v = client->_bind( selected ) ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

  METHOD generate.

    DATA temp3 TYPE z2ui5_cl_agent_genui=>ty_t_label.
    DATA temp4 LIKE LINE OF temp3.
    DATA temp1 TYPE string_table.
    DATA genui TYPE REF TO z2ui5_cl_agent_genui.
    DATA ls_result TYPE z2ui5_cl_agent_genui=>ty_s_result.
    CLEAR temp3.

    temp4-field = `CARRID`.
    temp4-label = `Airline`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `CONNID`.
    temp4-label = `Connection`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `FLDATE`.
    temp4-label = `Date`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `CITYFROM`.
    temp4-label = `From`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `CITYTO`.
    temp4-label = `To`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `SEATSMAX`.
    temp4-label = `Seats`.
    INSERT temp4 INTO TABLE temp3.
    temp4-field = `SEATSOCC`.
    temp4-label = `Occupied seats`.
    INSERT temp4 INTO TABLE temp3.

    CLEAR temp1.
    INSERT `CARRID` INTO TABLE temp1.
    INSERT `CONNID` INTO TABLE temp1.
    INSERT `FLDATE` INTO TABLE temp1.

    genui = z2ui5_cl_agent_genui=>create( client = client
                                                app    = app_name( )
        )->add_table( name        = `flights`
                      val         = t_flight
                      description = `flights of the coming week, one row per flight`
                      t_label     = temp3
        )->add_event( event       = `ROW_SELECT`
                      description = `the user picks a flight`
                      t_arg       = temp1
        )->add_event( event       = `REFRESH`
                      description = `reload the data` ).


    ls_result = genui->generate( request     = request
                                       close_event = `GENUI_CLOSE` ).
    report = concat_lines_of( table = ls_result-t_note
                              sep   = ` / ` ).
    IF ls_result-t_issue IS NOT INITIAL.
      report = |{ report } / REJECTED: { concat_lines_of( table = ls_result-t_issue
                                                          sep   = ` / ` ) }|.
    ENDIF.
    IF ls_result-ok = abap_true.
      xml_popup = ls_result-xml_popup.
      " bound: the view is not rendered again after this event
      generated = abap_true.
      client->popup_display( xml_popup ).
    ELSE.
      client->message_box_display( text = `The view was rejected - see the validation report`
                                   type = `warning` ).
    ENDIF.

  ENDMETHOD.

  METHOD on_event.

    CASE client->get_event( ).

      WHEN `GENERATE`.
        generate( ).

      WHEN `SHOW`.
        IF xml_popup IS NOT INITIAL.
          " the bindings of the generated view are this app's attributes
          client->_bind( t_flight ).
          client->popup_display( xml_popup ).
        ENDIF.

      WHEN `GENUI_CLOSE`.
        client->popup_destroy( ).

      WHEN `ROW_SELECT`.
        selected = |Selected: { client->get_event_arg( 1 ) } { client->get_event_arg( 2 ) } on { client->get_event_arg( 3 ) }|.
        client->message_toast_display( selected ).

      WHEN `REFRESH`.
        client->message_toast_display( `The data is up to date` ).

    ENDCASE.

  ENDMETHOD.

  METHOD app_name.

    result = cl_abap_classdescr=>get_class_name( me ).
    SHIFT result LEFT DELETING LEADING '\CLASS='.

  ENDMETHOD.

ENDCLASS.
