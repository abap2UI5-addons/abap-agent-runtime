"! The parsers on literal input - the cases of the reference's own tests
"! (abap2UI5/mcp-server test/snapshot.test.mjs, "viewxml").
CLASS ltcl_viewxml DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    METHODS xml_namespaces_entities FOR TESTING.
    METHODS xml_lenient             FOR TESTING.
    METHODS binding_kinds           FOR TESTING.
    METHODS expression_operators    FOR TESTING.
    METHODS wire_arguments          FOR TESTING.
    METHODS wire_variants           FOR TESTING.
    METHODS name_of_path            FOR TESTING.
    METHODS json_escaping           FOR TESTING.

    METHODS eval
      IMPORTING
        src           TYPE string
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_viewxml IMPLEMENTATION.

  METHOD xml_namespaces_entities.

    DATA(lt_node) = z2ui5_cl_agent_viewxml=>parse_xml(
        `<?xml version="1.0"?><mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:f="sap.ui.layout.form">` &&
        `<!-- c --><f:SimpleForm><f:content><Label text="A &amp; B &#x41;"/><Input value='{/X}'/></f:content></f:SimpleForm>` &&
        `<core:HTML xmlns:core="sap.ui.core" content="&lt;b&gt;"/><Text>inline</Text></mvc:View>` ).

    DATA(ls_view) = lt_node[ lt_node[ 1 ]-t_child[ 1 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.core.mvc.View`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_view ) ).
    DATA(ls_form) = lt_node[ ls_view-t_child[ 1 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.layout.form.SimpleForm`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_form ) ).
    DATA(ls_content) = lt_node[ ls_form-t_child[ 1 ] ].
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_viewxml=>is_aggregation( ls_content ) ).
    DATA(ls_label) = lt_node[ ls_content-t_child[ 1 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.Label`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_label ) ).
    cl_abap_unit_assert=>assert_equals( exp = `A & B A`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_label
                                                                            name = `text` ) ).
    DATA(ls_input) = lt_node[ ls_content-t_child[ 2 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `{/X}`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_input
                                                                            name = `value` ) ).
    DATA(ls_html) = lt_node[ ls_view-t_child[ 2 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.core.HTML`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_html ) ).
    cl_abap_unit_assert=>assert_equals( exp = `<b>`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_html
                                                                            name = `content` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `inline`
                                        act = lt_node[ ls_view-t_child[ 3 ] ]-text ).

  ENDMETHOD.

  METHOD xml_lenient.

    DATA lv_found TYPE abap_bool.

    " a closing tag pops whatever is open; an unknown prefix keeps its name
    DATA(lt_node) = z2ui5_cl_agent_viewxml=>parse_xml( `<A xmlns="sap.m"><B><C/></X><D x=1 y/></A>` ).
    DATA(ls_a) = lt_node[ lt_node[ 1 ]-t_child[ 1 ] ].
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ls_a-t_child ) ).
    DATA(ls_d) = lt_node[ ls_a-t_child[ 2 ] ].
    cl_abap_unit_assert=>assert_equals( exp = `1`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_d
                                                                            name = `x` ) ).
    z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_d
                                            name  = `y`
                                  IMPORTING found = lv_found ).
    cl_abap_unit_assert=>assert_true( lv_found ).
    z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_d
                                            name  = `z`
                                  IMPORTING found = lv_found ).
    cl_abap_unit_assert=>assert_false( lv_found ).

  ENDMETHOD.

  METHOD binding_kinds.

    DATA(ls_b) = z2ui5_cl_agent_viewxml=>parse_binding( `plain` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-literal
                                        act = ls_b-kind ).
    cl_abap_unit_assert=>assert_equals( exp = `a { b }`
                                        act = z2ui5_cl_agent_viewxml=>parse_binding( `a \{ b \}` )-value ).

    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `{/S_SCREEN/NAME}` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-path
                                        act = ls_b-kind ).
    cl_abap_unit_assert=>assert_equals( exp = `/S_SCREEN/NAME`
                                        act = ls_b-path ).
    cl_abap_unit_assert=>assert_false( ls_b-relative ).

    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `{TITLE}` ).
    cl_abap_unit_assert=>assert_true( ls_b-relative ).

    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `{i18n>title}` ).
    cl_abap_unit_assert=>assert_equals( exp = `i18n`
                                        act = ls_b-model ).
    cl_abap_unit_assert=>assert_equals( exp = `title`
                                        act = ls_b-path ).

    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `{ path: '/AMOUNT', type: 'sap.ui.model.type.Integer' }` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-path
                                        act = ls_b-kind ).
    cl_abap_unit_assert=>assert_equals( exp = `/AMOUNT`
                                        act = ls_b-path ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.model.type.Integer`
                                        act = ls_b-type ).

    cl_abap_unit_assert=>assert_equals( exp = `/T_TAB`
                                        act = z2ui5_cl_agent_viewxml=>parse_binding( `{path: '/T_TAB', templateShareable: false}` )-path ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-expression
                                        act = z2ui5_cl_agent_viewxml=>parse_binding( `{= ${/X} > 1 }` )-kind ).

    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `Total: {/SUM} EUR` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-composite
                                        act = ls_b-kind ).
    cl_abap_unit_assert=>assert_equals( exp = 3
                                        act = lines( ls_b-t_part ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/SUM`
                                        act = ls_b-t_part[ 2 ]-path ).

    " the model of the object syntax names a model too - not the default one
    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `{ path: '/A', model: 'other' }` ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-path
                                        act = ls_b-kind ).
    cl_abap_unit_assert=>assert_equals( exp = `other`
                                        act = ls_b-model ).
    cl_abap_unit_assert=>assert_equals( exp = `/A`
                                        act = ls_b-path ).

    " a formatter makes it one-way
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_viewxml=>cs_binding-composite
                                        act = z2ui5_cl_agent_viewxml=>parse_binding( `{ path: '/D', formatter: 'f.x' }` )-kind ).

  ENDMETHOD.

  METHOD eval.

    DATA lt_ref TYPE z2ui5_cl_agent_viewxml=>ty_t_ref_val.

    lt_ref = VALUE #( ( ref = `/EDIT` val = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ) )
                      ( ref = `/MODE` val = z2ui5_cl_agent_viewxml=>val_string( `A` ) )
                      ( ref = `/N`    val = z2ui5_cl_agent_viewxml=>val_number( `3` ) )
                      ( ref = `/LIST` val = VALUE #( kind = z2ui5_cl_agent_viewxml=>cs_kind-array
                                                     json = `[1,2]`
                                                     num  = 2 ) ) ).
    DATA(ls_val) = z2ui5_cl_agent_viewxml=>eval_expression( val   = src
                                                            t_ref = lt_ref ).
    result = COND #( WHEN ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined
                     THEN `undefined`
                     ELSE z2ui5_cl_agent_viewxml=>val_to_json( ls_val ) ).

  ENDMETHOD.

  METHOD expression_operators.

    cl_abap_unit_assert=>assert_equals( exp = `true`
                                        act = eval( ` ${/EDIT} ` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `false`
                                        act = eval( `!${/EDIT}` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `true`
                                        act = eval( `${/MODE} === 'A' && ${/N} > 2` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `false`
                                        act = eval( `${/MODE} !== 'A' || ${/N} <= 2` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `true`
                                        act = eval( `${/LIST}.length > 1 ? true : false` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `true`
                                        act = eval( `(${/N} + 1) * 2 === 8` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `"3 items"`
                                        act = eval( `${/N} + ' items'` ) ).
    " what a browser computes is unknown here, never guessed
    cl_abap_unit_assert=>assert_equals( exp = `undefined`
                                        act = eval( `${/N}.toFixed(2)` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `undefined`
                                        act = eval( `odata.compare(1,2)` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `undefined`
                                        act = eval( `${/N} >` ) ).

  ENDMETHOD.

  METHOD wire_arguments.

    DATA lt_desc TYPE string_table.

    DATA(ls_wire) = z2ui5_cl_agent_viewxml=>parse_wire(
        `.eB(['ROW',false,false,false,true], ${NAME}, 'it\'s, a', ${/S/X}, ${$source>/text}, ${$parameters>/selectedItem}, $event, ${QTY} * 10, 5)` ).
    cl_abap_unit_assert=>assert_true( ls_wire-valid ).
    cl_abap_unit_assert=>assert_equals( exp = `ROW`
                                        act = ls_wire-event ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `false` ) ( `false` ) ( `false` ) ( `true` ) )
                                        act = ls_wire-t_flag ).
    LOOP AT ls_wire-t_arg INTO DATA(ls_arg).
      INSERT COND #( WHEN ls_arg-static = abap_true
                     THEN z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val )
                     ELSE ls_arg-describe ) INTO TABLE lt_desc.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `$row:NAME` )
                                                                  ( `"it's, a"` )
                                                                  ( `$model:/S/X` )
                                                                  ( `$source:text` )
                                                                  ( `$parameters:selectedItem` )
                                                                  ( `$event` )
                                                                  ( `$expr:${QTY} * 10` )
                                                                  ( `5` ) )
                                        act = lt_desc ).

  ENDMETHOD.

  METHOD wire_variants.

    DATA(ls_wire) = z2ui5_cl_agent_viewxml=>parse_wire( `.eBP($event, true, ['NAV'], 'x')` ).
    cl_abap_unit_assert=>assert_equals( exp = `NAV`
                                        act = ls_wire-event ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( ls_wire-t_arg ) ).

    ls_wire = z2ui5_cl_agent_viewxml=>parse_wire( `.eF('CONTROL_GLOBAL', 'VIEW_SLOTS', 'destroy', 'POPUP')` ).
    cl_abap_unit_assert=>assert_equals( exp = `eF`
                                        act = ls_wire-fn ).
    cl_abap_unit_assert=>assert_equals( exp = `CONTROL_GLOBAL`
                                        act = ls_wire-action ).
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = ls_wire-t_arg[ 3 ]-val-str ).

    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_viewxml=>parse_wire( `press('x')` )-valid ).
    " a string where the event array belongs is no wire
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_viewxml=>parse_wire( `.eB('SAVE')` )-valid ).
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_viewxml=>has_wire( `.eB (['SAVE'])` ) ).
    cl_abap_unit_assert=>assert_false( z2ui5_cl_agent_viewxml=>has_wire( `.eX(['SAVE'])` ) ).

  ENDMETHOD.

  METHOD name_of_path.

    cl_abap_unit_assert=>assert_equals( exp = `MS_HEAD-KUNNR`
                                        act = z2ui5_cl_agent_snapshot=>name_of_path( `/MS_HEAD/KUNNR` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `MS_HEAD-KUNNR`
                                        act = z2ui5_cl_agent_snapshot=>name_of_path( `/XX/MS_HEAD/KUNNR` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `NAME`
                                        act = z2ui5_cl_agent_snapshot=>name_of_path( `/NAME` ) ).
    cl_abap_unit_assert=>assert_initial( z2ui5_cl_agent_snapshot=>name_of_path( `/` ) ).

  ENDMETHOD.

  METHOD json_escaping.

    cl_abap_unit_assert=>assert_equals( exp = `"a\"b\\c\nd"`
                                        act = z2ui5_cl_agent_viewxml=>json_string( |a"b\\c{ cl_abap_char_utilities=>newline }d| ) ).
    " a control character without a short escape - valid JSON all the same
    cl_abap_unit_assert=>assert_equals( exp = `"a\u000bb"`
                                        act = z2ui5_cl_agent_viewxml=>json_string( |a{ cl_abap_char_utilities=>vertical_tab }b| ) ).
    cl_abap_unit_assert=>assert_equals( exp = `1.5`
                                        act = z2ui5_cl_agent_viewxml=>number_normalize( `01.50` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ab...`
                                        act = z2ui5_cl_agent_viewxml=>clip( val = |ab  cd   ef|
                                                                            len = 5 ) ).

  ENDMETHOD.

ENDCLASS.
