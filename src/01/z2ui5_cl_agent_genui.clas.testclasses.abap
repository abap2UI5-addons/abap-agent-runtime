"! Generative UI through its demo app (z2ui5_cl_agent_genui_demo) on the
"! headless frontend simulator, with a language model double: the double
"! answers canned UI trees, the tests read the generated popup and the
"! validation report the way a user sees them.
CLASS ltcl_genui DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.

    CONSTANTS c_demo TYPE string VALUE `Z2UI5_CL_AGENT_GENUI_DEMO`.
    CONSTANTS c_no_list TYPE string VALUE `{"dataset":"","aggregation":"","sort_by":"","descending":false,"group_by":""}`.

    DATA mo_double TYPE REF TO z2ui5_cl_agent_llm_double.
    DATA mt_saved TYPE STANDARD TABLE OF z2ui5_t_ag_set WITH EMPTY KEY.

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
    METHODS markup_is_escaped FOR TESTING RAISING cx_static_check.
    METHODS tree_shape FOR TESTING RAISING cx_static_check.
    METHODS repair_round FOR TESTING RAISING cx_static_check.
    METHODS model_fails FOR TESTING RAISING cx_static_check.

    METHODS repair
      IMPORTING
        val TYPE abap_bool.

    METHODS run
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

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

    SELECT * FROM z2ui5_t_ag_set WHERE kind = 'LLM' INTO TABLE @mt_saved.
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    z2ui5_cl_agent_settings=>refresh( ).
    mo_double = NEW #( ).
    z2ui5_cl_agent_llm=>set_double( mo_double ).
    repair( abap_false ).

  ENDMETHOD.

  METHOD teardown.

    z2ui5_cl_agent_llm=>set_double( ).
    DELETE FROM z2ui5_t_ag_set WHERE kind = 'LLM'.
    INSERT z2ui5_t_ag_set FROM TABLE @mt_saved.
    z2ui5_cl_agent_settings=>refresh( ).

  ENDMETHOD.

  METHOD repair.

    z2ui5_cl_agent_settings=>set_llm( item  = z2ui5_cl_agent_settings=>cs_llm-genui_repair
                                      value = COND #( WHEN val = abap_true THEN `on` ELSE `off` ) ).

  ENDMETHOD.

  METHOD run.

    result = z2ui5_cl_frontend_simulator=>start( c_demo ).
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

    DATA(lt_node) = VALUE string_table(
      ( node( id = `root` parent = `` control = `sap.m.VBox` props = prop( name = `class` value = `sapUiSmallMargin` ) ) )
      ( node( id = `title` parent = `root` control = `sap.m.Title` props = prop( name = `text` value = title_text ) ) )
      ( node( id = `table` parent = `root` control = `sap.m.Table`
              props = |{ prop( name = `headerText` value = `Flights` ) },{ prop( name = `mode` value = `None` ) }|
              list  = `{"dataset":"flights","aggregation":"","sort_by":"","descending":false,"group_by":"CARRID"}` ) )
      ( node( id = `c1` parent = `table` agg = `columns` control = `sap.m.Column` ) )
      ( node( id = `c1t` parent = `c1` control = `sap.m.Text` props = prop( name = `text` value = `Connection` ) ) )
      ( node( id = `c2` parent = `table` agg = `columns` control = `sap.m.Column` props = prop( name = `hAlign` value = `End` ) ) )
      ( node( id = `c2t` parent = `c2` control = `sap.m.Text` props = prop( name = `text` value = `Price` ) ) )
      ( node( id = `row` parent = `table` control = `sap.m.ColumnListItem`
              props  = prop( name = `type` value = `Active` )
              events = |\{"name":"press","event":"{ press_event }","args":{ press_args }\}| ) )
      ( node( id = `cell1` parent = `row` control = `sap.m.Text` props = prop( name = `text` field = cell_field ) ) )
      ( node( id = `cell2` parent = `row` control = `sap.m.ObjectNumber`
              props = |{ prop( name = `number` field = `PRICE` format = `decimal` ) },{ prop( name = `unit` field = `CURRENCY` ) }| ) ) ).
    INSERT LINES OF t_extra INTO TABLE lt_node.
    result = tree( lt_node ).

  ENDMETHOD.

  METHOD valid_view.

    mo_double->add_answer( valid_tree( ) ).
    DATA(sim) = run( ).

    DATA(lv_popup) = sim->get_popup( ).
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
    sim->click( event = `ROW_SELECT`
                t_arg = VALUE #( ( `LH` ) ( `0400` ) ( `2026-10-05` ) )
                layer = `POPUP` ).
    cl_abap_unit_assert=>assert_equals( act = sim->get_value( `SELECTED` )
                                        exp = `Selected: LH 0400 on 2026-10-05` ).
    sim->click( event = `GENUI_CLOSE`
                layer = `POPUP` ).
    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).

  ENDMETHOD.

  METHOD model_sees_no_data.

    mo_double->add_answer( valid_tree( ) ).
    run( ).

    " one call: field names, types and labels - no row of the data
    cl_abap_unit_assert=>assert_equals( act = lines( mo_double->mt_request )
                                        exp = 1 ).
    DATA(ls_request) = mo_double->mt_request[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = ls_request-purpose
                                        exp = `genui` ).
    " the closed vocabulary is in the schema already - HTML is not
    cl_abap_unit_assert=>assert_char_cp( act = ls_request-schema
                                         exp = `{"type":"object","additionalProperties":false,"required":["title","nodes"]*"sap.m.Table"*` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_request-schema
                                                    sub = `sap.ui.core.HTML` )
                                        exp = -1 ).
    DATA(lv_user) = ls_request-t_message[ 1 ]-content.
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

    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `x` parent = `root` control = `sap.m.Gadget` ) ) ) ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*REJECTED: node "x" (sap.m.Gadget): unknown control*` ).

  ENDMETHOD.

  METHOD excluded_control.

    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `x` parent = `root` control = `sap.ui.core.HTML`
                                                        props = prop( name = `content` value = `<b>hi</b>` ) ) ) ) ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "x" (sap.ui.core.HTML): this control is not allowed in a generated view*` ).

  ENDMETHOD.

  METHOD unknown_property.

    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `x` parent = `root` control = `sap.m.Button`
                                                        props = |{ prop( name = `text` value = `Go` ) },| &&
                                                                |{ prop( name = `onclick` value = `alert(1)` ) }| ) ) ) ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "x" (sap.m.Button): unknown property "onclick"*` ).

  ENDMETHOD.

  METHOD bad_literal.

    " an enum value with markup in it, a URI that is no icon
    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `x` parent = `root` control = `sap.m.Button`
                                                        props = |{ prop( name = `type` value = `Emphasized" press="x` ) },| &&
                                                                |{ prop( name = `icon` value = `javascript:alert(1)` ) }| ) ) ) ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    DATA(lv_report) = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*type = "Emphasized" press="x": one of Default, Back, *` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*icon = "javascript:alert(1)": only an icon URI of the SAP icon font*` ).

  ENDMETHOD.

  METHOD unknown_field.

    mo_double->add_answer( valid_tree( cell_field = `PASSWORD` ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*node "cell1" (sap.m.Text): text binds to "PASSWORD" - no field of flights*` ).

  ENDMETHOD.

  METHOD event_not_allowed.

    mo_double->add_answer( valid_tree( press_event = `DELETE_ALL`
                                       press_args  = `[]` ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*press fires "DELETE_ALL" - not an event of the app; allowed: ROW_SELECT, REFRESH*` ).

  ENDMETHOD.

  METHOD arg_not_allowed.

    mo_double->add_answer( valid_tree( press_args = `["CARRID","PRICE"]` ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*the event ROW_SELECT takes no argument "PRICE"; allowed: CARRID, CONNID, FLDATE*` ).

  ENDMETHOD.

  METHOD markup_is_escaped.

    " texts are literals: markup and binding syntax arrive as text
    mo_double->add_answer( valid_tree( title_text = `<script>alert(1)</script>"/><core:HTML content="x" {/T_FLIGHT} {= 1}` ) ).
    DATA(sim) = run( ).

    DATA(lv_popup) = sim->get_popup( ).
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
    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `y` parent = `` control = `sap.m.Text` ) )
                                                ( node( id = `z` parent = `nowhere` control = `sap.m.Text` ) ) ) ) ).
    DATA(sim) = run( ).

    DATA(lv_report) = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*the parent "nowhere" does not exist*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*exactly one root node (parent ""), it has 2*` ).

    mo_double->add_answer( valid_tree( VALUE #( ( node( id = `row2` parent = `table` control = `sap.m.ColumnListItem` ) ) ) ) ).
    sim = run( ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*a list needs exactly one row template in items, it has 2*` ).

  ENDMETHOD.

  METHOD repair_round.

    repair( abap_true ).
    mo_double->add_answer( valid_tree( cell_field = `PASSWORD` ) ).
    mo_double->add_answer( valid_tree( ) ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_char_cp( act = sim->get_popup( )
                                         exp = `*<Text text="{CONNID}"/>*` ).
    DATA(lv_report) = sim->get_value( `REPORT` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_report
                                         exp = `*round 1: rejected - 1 issue(s)*repair*round 2: the UI tree is valid*` ).
    " the second call carries the rejected answer and the reasons
    cl_abap_unit_assert=>assert_equals( act = lines( mo_double->mt_request )
                                        exp = 2 ).
    DATA(lt_message) = mo_double->mt_request[ 2 ]-t_message.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_message )
                                        exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = lt_message[ 2 ]-role
                                        exp = `assistant` ).
    cl_abap_unit_assert=>assert_char_cp( act = lt_message[ 3 ]-content
                                         exp = `The UI tree was rejected:*"PASSWORD" - no field of flights*` ).

  ENDMETHOD.

  METHOD model_fails.

    DATA lv_before TYPE i.
    DATA lv_after TYPE i.

    SELECT COUNT(*) FROM z2ui5_t_ag_log WHERE operation = 'llm' AND app = @c_demo AND outcome = 'error'
      INTO @lv_before.
    mo_double->add_error( ).
    DATA(sim) = run( ).

    cl_abap_unit_assert=>assert_initial( sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sim->get_value( `REPORT` )
                                         exp = `*the language model call failed (http)*` ).
    " audited as an error - and committed, abap2UI5 rolls back after main( )
    SELECT COUNT(*) FROM z2ui5_t_ag_log WHERE operation = 'llm' AND app = @c_demo AND outcome = 'error'
      INTO @lv_after.
    cl_abap_unit_assert=>assert_equals( act = lv_after
                                        exp = lv_before + 1 ).

  ENDMETHOD.

ENDCLASS.
