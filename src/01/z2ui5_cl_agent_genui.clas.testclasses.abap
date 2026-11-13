"! Generative UI through its demo app (z2ui5_cl_agent_genui_demo) on the
"! headless frontend simulator, with a language model double: the double
"! answers canned UI trees, the tests read the generated popup and the
"! validation report the way a user sees them.
CLASS ltcl_genui DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    CONSTANTS c_demo TYPE string VALUE `Z2UI5_CL_AGENT_GENUI_DEMO`.
    CONSTANTS c_no_list TYPE string VALUE `{"dataset":"","aggregation":"","sort_by":"","descending":false,"group_by":""}`.

    DATA mo_double TYPE REF TO z2ui5_cl_agent_llm_double.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_17 WITH DEFAULT KEY.

    METHODS setup.
    METHODS teardown.

    METHODS valid_view FOR TESTING RAISING cx_static_check.
    METHODS model_sees_no_data FOR TESTING RAISING cx_static_check.
    METHODS unknown_control FOR TESTING RAISING cx_static_check.
    METHODS excluded_control FOR TESTING RAISING cx_static_check.
    METHODS unknown_property FOR TESTING RAISING cx_static_check.
    METHODS bad_literal FOR TESTING RAISING cx_static_check.
    METHODS unknown_field FOR TESTING RAISING cx_static_check.
    METHODS event_not_allowed FOR TESTING RAISING cx_static_check.
    METHODS arg_not_allowed FOR TESTING RAISING cx_static_check.
    METHODS arg_order FOR TESTING RAISING cx_static_check.
    METHODS literal_one_line FOR TESTING RAISING cx_static_check.
    METHODS markup_is_escaped FOR TESTING RAISING cx_static_check.
    METHODS tree_shape FOR TESTING RAISING cx_static_check.
    METHODS repair_round FOR TESTING RAISING cx_static_check.
    METHODS model_fails FOR TESTING RAISING cx_static_check.
    METHODS floor_views FOR TESTING RAISING cx_static_check.
    METHODS binding_types FOR TESTING RAISING cx_static_check.

    METHODS repair
      IMPORTING
        val TYPE abap_bool.

    METHODS run
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_sim.

    CLASS-METHODS node
      IMPORTING
        id            TYPE string
        parent        TYPE string
        agg           TYPE string DEFAULT ``
        control       TYPE string
        props         TYPE string DEFAULT ``
        list          TYPE string DEFAULT c_no_list
        events        TYPE string DEFAULT ``
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS prop
      IMPORTING
        name          TYPE string
        value         TYPE string DEFAULT ``
        field         TYPE string DEFAULT ``
        dataset       TYPE string DEFAULT ``
        format        TYPE string DEFAULT ``
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS tree
      IMPORTING
        t_node        TYPE string_table
      RETURNING
        VALUE(result) TYPE string.

    "! The flights as a table grouped by carrier, a row press fires
    "! ROW_SELECT with the row's carrier and connection - plus extra nodes.
    CLASS-METHODS valid_tree
      IMPORTING
        t_extra       TYPE string_table OPTIONAL
        title_text    TYPE string DEFAULT `Flights`
        press_event   TYPE string DEFAULT `ROW_SELECT`
        press_args    TYPE string DEFAULT `["CARRID","CONNID"]`
        cell_field    TYPE string DEFAULT `CONNID`
          PREFERRED PARAMETER t_extra
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_genui IMPLEMENTATION.

  METHOD setup.

    SELECT * FROM z2ui5_t_17 INTO TABLE mt_saved WHERE kind = 'LLM' .
    DELETE FROM z2ui5_t_17 WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    CREATE OBJECT mo_double.
    z2ui5_cl_agent_llm=>set_double( mo_double ).
    repair( abap_false ).

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_double( ).
    DELETE FROM z2ui5_t_17 WHERE kind = 'LLM'.
    INSERT z2ui5_t_17 FROM TABLE mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD repair.

    DATA temp1 TYPE string.
    IF val = abap_true.
      temp1 = `on`.
    ELSE.
      temp1 = `off`.
    ENDIF.
    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-genui_repair
                                      value = temp1 ).

  ENDMETHOD.

  METHOD run.

    result = z2ui5_cl_frontend_sim=>start( c_demo ).
    result->set_value( name  = `REQUEST`
                       value = `the flights as a table grouped by carrier` ).
    result->click( `GENERATE` ).

  ENDMETHOD.

  METHOD node.

    result = |\{"id":"{ id }","parent":"{ parent }","aggregation":"{ agg }","control":"{ control }",| &&
             |"properties":[{ props }],"list":{ list },"events":[{ events }]\}|.

  ENDMETHOD.

  METHOD prop.

    result = |\{"name":"{ name }","value":{ z2ui5_cl_agent_viewxml=>json_string( value ) },"field":"{ field }",| &&
             |"dataset":"{ dataset }","format":"{ format }"\}|.

  ENDMETHOD.

  METHOD tree.

    result = |\{"title":"Flights by carrier","nodes":[{ concat_lines_of( table = t_node
                                                                          sep   = `,` ) }]\}|.

  ENDMETHOD.

  METHOD valid_tree.

    DATA lv_table_props TYPE string.
    DATA temp2 TYPE string_table.
    DATA lt_node LIKE temp2.
    lv_table_props = |{ prop( name = `headerText` value = `Flights` ) },{ prop( name = `mode` value = `None` ) }|.

    CLEAR temp2.
    INSERT node( id = `root` parent = `` control = `sap.m.VBox` props = prop( name = `class` value = `sapUiSmallMargin` ) ) INTO TABLE temp2.
    INSERT node( id = `title` parent = `root` control = `sap.m.Title` props = prop( name = `text` value = title_text ) ) INTO TABLE temp2.
    INSERT node( id = `table` parent = `root` control = `sap.m.Table` props = lv_table_props list = `{"dataset":"flights","aggregation":"","sort_by":"","descending":false,"group_by":"CARRID"}` ) INTO TABLE temp2.
    INSERT node( id = `c1` parent = `table` agg = `columns` control = `sap.m.Column` ) INTO TABLE temp2.
    INSERT node( id = `c1t` parent = `c1` control = `sap.m.Text` props = prop( name = `text` value = `Connection` ) ) INTO TABLE temp2.
    INSERT node( id = `c2` parent = `table` agg = `columns` control = `sap.m.Column` props = prop( name = `hAlign` value = `End` ) ) INTO TABLE temp2.
    INSERT node( id = `c2t` parent = `c2` control = `sap.m.Text` props = prop( name = `text` value = `Price` ) ) INTO TABLE temp2.
    INSERT node( id = `row` parent = `table` control = `sap.m.ColumnListItem` props = prop( name = `type` value = `Active` ) events = |\{"name":"press","event":"{ press_event }","args":{ press_args }\}| ) INTO TABLE temp2.
    INSERT node( id = `cell1` parent = `row` control = `sap.m.Text` props = prop( name = `text` field = cell_field ) ) INTO TABLE temp2.
    INSERT node( id = `cell2` parent = `row` control = `sap.m.ObjectNumber` props = |{ prop( name = `number` field = `PRICE` format = `decimal` ) },{ prop( name = `unit` field = `CURRENCY` ) }| ) INTO TABLE temp2.

    lt_node = temp2.
    INSERT LINES OF t_extra INTO TABLE lt_node.
    result = tree( lt_node ).

  ENDMETHOD.

  METHOD valid_view.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_popup TYPE string.
    DATA temp4 TYPE string_table.

    mo_double->add_answer( valid_tree( ) ).

    sim = run( ).


    lv_popup = sim->get_popup( ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*<Dialog title="Flights by carrier"*` ).
    cl_abap_unit_assert=>assert_char_cp(
        act = lv_popup
        exp = `*<Table headerText="Flights" mode="None" items="{path:'/T_FLIGHT',templateShareable:false,sorter:{path:'CARRID',descending:false,group:true}}">*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*<columns><Column><Text text="Connection"/></Column>*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*<Text text="{CONNID}"/>*` ).
    cl_abap_unit_assert=>assert_char_cp(
        act = lv_popup
        exp = `*number="{path:'PRICE',type:'sap.ui.model.type.Float',formatOptions:{minFractionDigits:2,maxFractionDigits:2}}" unit="{CURRENCY}"*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*ROW_SELECT*${CARRID}*${CONNID}*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*round 1: the UI tree is valid (10 nodes)*` ).

    " the generated view fires the app's event with the row's fields

    CLEAR temp4.
    INSERT `LH` INTO TABLE temp4.
    INSERT `0400` INTO TABLE temp4.
    INSERT `2026-10-05` INTO TABLE temp4.
    sim->click( event = `ROW_SELECT`
                t_arg = temp4
                layer = `POPUP` ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `SELECTED` )
                                        exp = `Selected: LH 0400 on 2026-10-05` ).
    sim->click( event = `GENUI_CLOSE`
                layer = `POPUP` ).
    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

  ENDMETHOD.

  METHOD model_sees_no_data.
    DATA ls_request TYPE z2ui5_if_agent_llm=>ty_s_request.
    FIELD-SYMBOLS <temp1> LIKE LINE OF mo_double->mt_request.
    DATA temp2 LIKE sy-tabix.
    DATA lv_user TYPE z2ui5_if_agent_llm=>ty_s_message-content.
    FIELD-SYMBOLS <temp3> LIKE LINE OF ls_request-t_message.
    DATA temp4 LIKE sy-tabix.

    mo_double->add_answer( valid_tree( ) ).
    run( ).

    " one call: field names, types and labels - no row of the data
    cl_abap_unit_assert=>assert_equals( act = lines( mo_double->mt_request )
                                        exp = 1 ).



    temp2 = sy-tabix.
    READ TABLE mo_double->mt_request INDEX 1 ASSIGNING <temp1>.
    sy-tabix = temp2.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_request = <temp1>.
    cl_abap_unit_assert=>assert_equals( act = ls_request-purpose
                                        exp = `genui` ).
    " the closed vocabulary is in the schema already - HTML is not
    cl_abap_unit_assert=>assert_char_cp( act = ls_request-schema
                                         exp = `{"type":"object","additionalProperties":false,"required":["title","nodes"]*"sap.m.Table"*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_request-schema
                                                    sub = `sap.ui.core.HTML` )
                                        exp = -1 ).



    temp4 = sy-tabix.
    READ TABLE ls_request-t_message INDEX 1 ASSIGNING <temp3>.
    sy-tabix = temp4.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_user = <temp3>-content.
    cl_abap_unit_assert=>assert_char_cp( act = lv_user
                                         exp = `*CITYFROM (string, "From")*SEATSOCC (number, "Occupied seats")*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_user
                                         exp = `*ROW_SELECT: the user picks a flight; args may be CARRID, CONNID, FLDATE*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_user
                                                    sub = `Frankfurt` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_request-system
                                                    sub = `sap.ui.core.HTML:` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_request-system
                                         exp = `*sap.m.Table: *` ).

  ENDMETHOD.

  METHOD unknown_control.

    DATA temp6 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    CLEAR temp6.
    INSERT node( id = `x` parent = `root` control = `sap.m.Gadget` ) INTO TABLE temp6.
    mo_double->add_answer( valid_tree( temp6 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*REJECTED: node "x" (sap.m.Gadget): unknown control*` ).

  ENDMETHOD.

  METHOD excluded_control.

    DATA temp8 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    CLEAR temp8.
    INSERT node( id = `x` parent = `root` control = `sap.ui.core.HTML` props = prop( name = `content` value = `<b>hi</b>` ) ) INTO TABLE temp8.
    mo_double->add_answer( valid_tree( temp8 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "x" (sap.ui.core.HTML): this control is not allowed in a generated view*` ).

  ENDMETHOD.

  METHOD unknown_property.

    DATA temp10 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    CLEAR temp10.
    INSERT node( id = `x` parent = `root` control = `sap.m.Button` props = |{ prop( name = `text` value = `Go` ) },| && |{ prop( name = `onclick` value = `alert(1)` ) }| ) INTO TABLE temp10.
    mo_double->add_answer( valid_tree( temp10 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "x" (sap.m.Button): unknown property "onclick"*` ).

  ENDMETHOD.

  METHOD bad_literal.

    " an enum value with markup in it, a URI that is no icon, an icon name
    " the font does not have
    DATA temp12 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    CLEAR temp12.
    INSERT node( id = `x` parent = `root` control = `sap.m.Button` props = |{ prop( name = `type` value = `Emphasized" press="x` ) },| && |{ prop( name = `icon` value = `javascript:alert(1)` ) }| ) INTO TABLE temp12.
    INSERT node( id = `y` parent = `root` control = `sap.m.Input` props = prop( name = `maxLength` value = `5-` ) ) INTO TABLE temp12.
    INSERT node( id = `z` parent = `root` control = `sap.m.Button` props = prop( name = `icon` value = `sap-icon://a` ) ) INTO TABLE temp12.
    mo_double->add_answer( valid_tree( temp12 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*type = "Emphasized" press="x": one of Default, Back, *` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*icon = "javascript:alert(1)": only an icon URI of the SAP icon font*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*maxLength = "5-": an integer*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*icon = "sap-icon://a": no icon of the SAP icon font at UI5 1.71*` ).

  ENDMETHOD.

  METHOD unknown_field.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.

    mo_double->add_answer( valid_tree( cell_field = `PASSWORD` ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "cell1" (sap.m.Text): text binds to "PASSWORD" - no field of flights*` ).

  ENDMETHOD.

  METHOD event_not_allowed.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.

    mo_double->add_answer( valid_tree( press_event = `DELETE_ALL`
                                       press_args  = `[]` ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*press fires "DELETE_ALL" - not an event of the app; allowed: ROW_SELECT, REFRESH*` ).

  ENDMETHOD.

  METHOD arg_not_allowed.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.

    mo_double->add_answer( valid_tree( press_args = `["CARRID","PRICE"]` ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*the event ROW_SELECT takes no argument "PRICE"; allowed: CARRID, CONNID, FLDATE*` ).

  ENDMETHOD.

  METHOD arg_order.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.

    " the app reads its arguments by position - another order is refused
    mo_double->add_answer( valid_tree( press_args = `["CONNID","CARRID"]` ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*the event ROW_SELECT takes its arguments in this order: CARRID, CONNID, FLDATE*` ).

  ENDMETHOD.

  METHOD literal_one_line.

    " a valid first line and a binding on the second: ^ and $ of the size
    " check match per line - refused as a whole, never written as it is;
    " and an icon typed as a string by the profile is still an icon URI
    DATA temp14 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    CLEAR temp14.
    INSERT node( id = `x` parent = `root` control = `sap.m.Input` props = prop( name = `width` value = |10rem\n\{/T_FLIGHT\}| ) ) INTO TABLE temp14.
    INSERT node( id = `s` parent = `root` control = `sap.m.SegmentedButton` ) INTO TABLE temp14.
    INSERT node( id = `si` parent = `s` control = `sap.m.SegmentedButtonItem` props = prop( name = `icon` value = `https://example.com/?d=1` ) ) INTO TABLE temp14.
    mo_double->add_answer( valid_tree( temp14 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*width = "10rem*a single value - no line breaks, no braces*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*icon = "https://example.com/?d=1": only an icon URI*` ).

  ENDMETHOD.

  METHOD markup_is_escaped.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_popup TYPE string.

    " texts are literals: markup and binding syntax arrive as text
    mo_double->add_answer( valid_tree( title_text = `<script>alert(1)</script>"/><core:HTML content="x" {/T_FLIGHT} {= 1}` ) ).

    sim = run( ).


    lv_popup = sim->get_popup( ).
    cl_abap_unit_assert=>assert_char_cp(
        act = lv_popup
        exp = `*<Title text="&lt;script&gt;alert(1)&lt;/script&gt;&quot;/&gt;&lt;core:HTML content=&quot;x&quot; \{/T_FLIGHT\} \{= 1\}"/>*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_popup
                                                    sub = `<script` )
                                        exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_popup
                                                    sub = `<core:HTML` )
                                        exp = -1 ).

  ENDMETHOD.

  METHOD tree_shape.

    " two roots, a parent that does not exist, a second template
    DATA temp16 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    DATA temp18 TYPE string_table.
    DATA temp20 TYPE string_table.
    CLEAR temp16.
    INSERT node( id = `y` parent = `` control = `sap.m.Text` ) INTO TABLE temp16.
    INSERT node( id = `z` parent = `nowhere` control = `sap.m.Text` ) INTO TABLE temp16.
    mo_double->add_answer( valid_tree( temp16 ) ).

    sim = run( ).


    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*the parent "nowhere" does not exist*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*exactly one root node (parent ""), it has 2*` ).


    CLEAR temp18.
    INSERT node( id = `row2` parent = `table` control = `sap.m.ColumnListItem` ) INTO TABLE temp18.
    mo_double->add_answer( valid_tree( temp18 ) ).
    sim = run( ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*a list needs exactly one row template in items, it has 2*` ).

    " an element that is no control cannot be the content of the view

    CLEAR temp20.
    INSERT node( id = `root` parent = `` control = `sap.m.Column` ) INTO TABLE temp20.
    mo_double->add_answer( tree( temp20 ) ).
    sim = run( ).
    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "root" (sap.m.Column): the root sits in the content of a view*` ).

  ENDMETHOD.

  METHOD repair_round.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    DATA lt_message TYPE z2ui5_if_agent_llm=>ty_t_message.
    FIELD-SYMBOLS <temp5> LIKE LINE OF mo_double->mt_request.
    DATA temp6 LIKE sy-tabix.
    FIELD-SYMBOLS <temp22> LIKE LINE OF lt_message.
    DATA temp23 LIKE sy-tabix.
    FIELD-SYMBOLS <temp24> LIKE LINE OF lt_message.
    DATA temp25 LIKE sy-tabix.

    repair( abap_true ).
    mo_double->add_answer( valid_tree( cell_field = `PASSWORD` ) ).
    mo_double->add_answer( valid_tree( ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_char_cp( act = sim->get_popup( )
                                         exp = `*<Text text="{CONNID}"/>*` ).

    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*round 1: rejected - 1 issue(s)*repair*round 2: the UI tree is valid*` ).
    " the second call carries the rejected answer and the reasons
    cl_abap_unit_assert=>assert_equals( act = lines( mo_double->mt_request )
                                        exp = 2 ).



    temp6 = sy-tabix.
    READ TABLE mo_double->mt_request INDEX 2 ASSIGNING <temp5>.
    sy-tabix = temp6.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lt_message = <temp5>-t_message.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_message )
                                        exp = 3 ).


    temp23 = sy-tabix.
    READ TABLE lt_message INDEX 2 ASSIGNING <temp22>.
    sy-tabix = temp23.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = <temp22>-role
                                        exp = `assistant` ).


    temp25 = sy-tabix.
    READ TABLE lt_message INDEX 3 ASSIGNING <temp24>.
    sy-tabix = temp25.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_char_cp( act = <temp24>-content
                                         exp = `The UI tree was rejected:*"PASSWORD" - no field of flights*` ).

  ENDMETHOD.

  METHOD floor_views.

    " visible is no property of an item, ".5" no float to the linter, and a
    " spacer in a sap.m.Bar hides what follows it at UI5 1.71
    DATA temp26 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    DATA temp28 TYPE string_table.
    DATA lv_popup TYPE string.
    CLEAR temp26.
    INSERT node( id = `sel` parent = `root` control = `sap.m.Select` ) INTO TABLE temp26.
    INSERT node( id = `item` parent = `sel` control = `sap.ui.core.Item` props = |{ prop( name = `text` value = `A` ) },{ prop( name = `visible` value = `false` ) }| ) INTO TABLE temp26.
    INSERT node( id = `pi` parent = `root` control = `sap.m.ProgressIndicator` props = prop( name = `percentValue` value = `.5` ) ) INTO TABLE temp26.
    INSERT node( id = `bar` parent = `root` control = `sap.m.Bar` ) INTO TABLE temp26.
    INSERT node( id = `sp` parent = `bar` agg = `contentLeft` control = `sap.m.ToolbarSpacer` ) INTO TABLE temp26.
    mo_double->add_answer( valid_tree( temp26 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*node "item" (sap.ui.core.Item): unknown property "visible"*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*percentValue = ".5": a number*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*node "sp" (sap.m.ToolbarSpacer): a sap.m.ToolbarSpacer belongs in a toolbar*` ).

    " a column has visible, a spacer in a toolbar is laid out, an icon of
    " the font is shown

    CLEAR temp28.
    INSERT node( id = `c3` parent = `table` agg = `columns` control = `sap.m.Column` props = prop( name = `visible` value = `false` ) ) INTO TABLE temp28.
    INSERT node( id = `tb` parent = `root` control = `sap.m.Toolbar` ) INTO TABLE temp28.
    INSERT node( id = `sp` parent = `tb` control = `sap.m.ToolbarSpacer` ) INTO TABLE temp28.
    INSERT node( id = `pi` parent = `root` control = `sap.m.ProgressIndicator` props = prop( name = `percentValue` value = `0.5` ) ) INTO TABLE temp28.
    INSERT node( id = `ic` parent = `root` control = `sap.m.Button` props = prop( name = `icon` value = `sap-icon://add` ) ) INTO TABLE temp28.
    mo_double->add_answer( valid_tree( temp28 ) ).
    sim = run( ).


    lv_popup = sim->get_popup( ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*<Column visible="false"/>*<Toolbar><ToolbarSpacer/></Toolbar>*percentValue="0.5"*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_popup
                                         exp = `*<Button icon="sap-icon://add"/>*` ).

  ENDMETHOD.

  METHOD binding_types.

    " a boolean property bound to a text, a number property bound to a text,
    " a format on a text: UI5 throws on the first two, the third is no number
    DATA temp30 TYPE string_table.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.
    DATA lv_report TYPE string.
    DATA temp32 TYPE string_table.
    CLEAR temp30.
    INSERT node( id = `b1` parent = `row` control = `sap.m.CheckBox` props = prop( name = `selected` field = `STATUS` ) ) INTO TABLE temp30.
    INSERT node( id = `b2` parent = `row` control = `sap.m.ProgressIndicator` props = prop( name = `percentValue` field = `CARRID` ) ) INTO TABLE temp30.
    INSERT node( id = `b3` parent = `row` control = `sap.m.Text` props = prop( name = `text` field = `CARRID` format = `integer` ) ) INTO TABLE temp30.
    mo_double->add_answer( valid_tree( temp30 ) ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

    lv_report = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*node "b1" (sap.m.CheckBox): selected takes a boolean field - "STATUS" is a string field*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*node "b2" (sap.m.ProgressIndicator): percentValue takes a number field - "CARRID" is a string field*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*node "b3" (sap.m.Text): text: format integer formats a number field*` ).

    " a number property bound to a number field

    CLEAR temp32.
    INSERT node( id = `b2` parent = `row` control = `sap.m.ProgressIndicator` props = prop( name = `percentValue` field = `SEATSOCC` ) ) INTO TABLE temp32.
    mo_double->add_answer( valid_tree( temp32 ) ).
    sim = run( ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_popup( )
                                         exp = `*<ProgressIndicator percentValue="{SEATSOCC}"/>*` ).

  ENDMETHOD.

  METHOD model_fails.

    DATA lv_before TYPE i.
    DATA lv_after TYPE i.
    DATA sim TYPE REF TO z2ui5_cl_frontend_sim.

    SELECT COUNT(*) FROM z2ui5_t_14 INTO lv_before WHERE operation = 'llm' AND app = c_demo AND outcome = 'error'
      .
    mo_double->add_error( ).

    sim = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*the language model call failed (http)*` ).
    " audited as an error - and committed, abap2UI5 rolls back after main( )
    SELECT COUNT(*) FROM z2ui5_t_14 INTO lv_after WHERE operation = 'llm' AND app = c_demo AND outcome = 'error'
      .
    cl_abap_unit_assert=>assert_equals( act = lv_after
                                        exp = lv_before + 1 ).

  ENDMETHOD.

ENDCLASS.
