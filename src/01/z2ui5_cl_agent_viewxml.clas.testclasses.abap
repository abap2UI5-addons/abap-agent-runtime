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
    METHODS cut_surrogate_pair      FOR TESTING.

    METHODS eval
      IMPORTING
        src           TYPE string
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_viewxml IMPLEMENTATION.

  METHOD xml_namespaces_entities.

    DATA lt_node TYPE z2ui5_cl_agent_viewxml=>ty_t_node.
    DATA ls_view LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp2> LIKE LINE OF lt_node.
    DATA temp3 LIKE sy-tabix.
    FIELD-SYMBOLS <temp3> LIKE LINE OF lt_node.
    DATA temp4 LIKE sy-tabix.
    FIELD-SYMBOLS <temp15> LIKE LINE OF <temp3>-t_child.
    DATA temp16 LIKE sy-tabix.
    DATA ls_form LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp4> LIKE LINE OF lt_node.
    DATA temp5 LIKE sy-tabix.
    FIELD-SYMBOLS <temp5> LIKE LINE OF ls_view-t_child.
    DATA temp6 LIKE sy-tabix.
    DATA ls_content LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp6> LIKE LINE OF lt_node.
    DATA temp7 LIKE sy-tabix.
    FIELD-SYMBOLS <temp7> LIKE LINE OF ls_form-t_child.
    DATA temp8 LIKE sy-tabix.
    DATA ls_label LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp8> LIKE LINE OF lt_node.
    DATA temp9 LIKE sy-tabix.
    FIELD-SYMBOLS <temp9> LIKE LINE OF ls_content-t_child.
    DATA temp10 LIKE sy-tabix.
    DATA ls_input LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp10> LIKE LINE OF lt_node.
    DATA temp11 LIKE sy-tabix.
    FIELD-SYMBOLS <temp11> LIKE LINE OF ls_content-t_child.
    DATA temp12 LIKE sy-tabix.
    DATA ls_html LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp12> LIKE LINE OF lt_node.
    DATA temp13 LIKE sy-tabix.
    FIELD-SYMBOLS <temp13> LIKE LINE OF ls_view-t_child.
    DATA temp14 LIKE sy-tabix.
    FIELD-SYMBOLS <temp1> LIKE LINE OF lt_node.
    DATA temp2 LIKE sy-tabix.
    FIELD-SYMBOLS <temp14> LIKE LINE OF ls_view-t_child.
    DATA temp15 LIKE sy-tabix.
    lt_node = z2ui5_cl_agent_viewxml=>parse_xml(
        `<?xml version="1.0"?><mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:f="sap.ui.layout.form">` &&
        `<!-- c --><f:SimpleForm><f:content><Label text="A &amp; B &#x41;"/><Input value='{/X}'/></f:content></f:SimpleForm>` &&
        `<core:HTML xmlns:core="sap.ui.core" content="&lt;b&gt;"/><Text>inline</Text></mvc:View>` ).




    temp3 = sy-tabix.


    temp4 = sy-tabix.
    READ TABLE lt_node INDEX 1 ASSIGNING <temp3>.
    sy-tabix = temp4.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.


    temp16 = sy-tabix.
    READ TABLE <temp3>-t_child INDEX 1 ASSIGNING <temp15>.
    sy-tabix = temp16.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp15> ASSIGNING <temp2>.
    sy-tabix = temp3.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_view = <temp2>.
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.core.mvc.View`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_view ) ).



    temp5 = sy-tabix.


    temp6 = sy-tabix.
    READ TABLE ls_view-t_child INDEX 1 ASSIGNING <temp5>.
    sy-tabix = temp6.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp5> ASSIGNING <temp4>.
    sy-tabix = temp5.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_form = <temp4>.
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.layout.form.SimpleForm`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_form ) ).



    temp7 = sy-tabix.


    temp8 = sy-tabix.
    READ TABLE ls_form-t_child INDEX 1 ASSIGNING <temp7>.
    sy-tabix = temp8.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp7> ASSIGNING <temp6>.
    sy-tabix = temp7.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_content = <temp6>.
    cl_abap_unit_assert=>assert_true( z2ui5_cl_agent_viewxml=>is_aggregation( ls_content ) ).



    temp9 = sy-tabix.


    temp10 = sy-tabix.
    READ TABLE ls_content-t_child INDEX 1 ASSIGNING <temp9>.
    sy-tabix = temp10.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp9> ASSIGNING <temp8>.
    sy-tabix = temp9.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_label = <temp8>.
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.Label`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_label ) ).
    cl_abap_unit_assert=>assert_equals( exp = `A & B A`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_label
                                                                            name = `text` ) ).



    temp11 = sy-tabix.


    temp12 = sy-tabix.
    READ TABLE ls_content-t_child INDEX 2 ASSIGNING <temp11>.
    sy-tabix = temp12.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp11> ASSIGNING <temp10>.
    sy-tabix = temp11.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_input = <temp10>.
    cl_abap_unit_assert=>assert_equals( exp = `{/X}`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_input
                                                                            name = `value` ) ).



    temp13 = sy-tabix.


    temp14 = sy-tabix.
    READ TABLE ls_view-t_child INDEX 2 ASSIGNING <temp13>.
    sy-tabix = temp14.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp13> ASSIGNING <temp12>.
    sy-tabix = temp13.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_html = <temp12>.
    cl_abap_unit_assert=>assert_equals( exp = `sap.ui.core.HTML`
                                        act = z2ui5_cl_agent_viewxml=>control_name( ls_html ) ).
    cl_abap_unit_assert=>assert_equals( exp = `<b>`
                                        act = z2ui5_cl_agent_viewxml=>attr( node = ls_html
                                                                            name = `content` ) ).


    temp2 = sy-tabix.


    temp15 = sy-tabix.
    READ TABLE ls_view-t_child INDEX 3 ASSIGNING <temp14>.
    sy-tabix = temp15.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp14> ASSIGNING <temp1>.
    sy-tabix = temp2.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = `inline`
                                        act = <temp1>-text ).

  ENDMETHOD.

  METHOD xml_lenient.

    DATA lv_found TYPE abap_bool.

    " a closing tag pops whatever is open; an unknown prefix keeps its name
    DATA lt_node TYPE z2ui5_cl_agent_viewxml=>ty_t_node.
    DATA ls_a LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp16> LIKE LINE OF lt_node.
    DATA temp17 LIKE sy-tabix.
    FIELD-SYMBOLS <temp15> LIKE LINE OF lt_node.
    DATA temp16 LIKE sy-tabix.
    FIELD-SYMBOLS <temp19> LIKE LINE OF <temp15>-t_child.
    DATA temp20 LIKE sy-tabix.
    DATA ls_d LIKE LINE OF lt_node.
    FIELD-SYMBOLS <temp18> LIKE LINE OF lt_node.
    DATA temp19 LIKE sy-tabix.
    FIELD-SYMBOLS <temp17> LIKE LINE OF ls_a-t_child.
    DATA temp18 LIKE sy-tabix.
    lt_node = z2ui5_cl_agent_viewxml=>parse_xml( `<A xmlns="sap.m"><B><C/></X><D x=1 y/></A>` ).



    temp17 = sy-tabix.


    temp16 = sy-tabix.
    READ TABLE lt_node INDEX 1 ASSIGNING <temp15>.
    sy-tabix = temp16.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.


    temp20 = sy-tabix.
    READ TABLE <temp15>-t_child INDEX 1 ASSIGNING <temp19>.
    sy-tabix = temp20.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp19> ASSIGNING <temp16>.
    sy-tabix = temp17.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_a = <temp16>.
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ls_a-t_child ) ).



    temp19 = sy-tabix.


    temp18 = sy-tabix.
    READ TABLE ls_a-t_child INDEX 2 ASSIGNING <temp17>.
    sy-tabix = temp18.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    READ TABLE lt_node INDEX <temp17> ASSIGNING <temp18>.
    sy-tabix = temp19.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_d = <temp18>.
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

    DATA ls_b TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
    FIELD-SYMBOLS <temp3> LIKE LINE OF ls_b-t_part.
    DATA temp4 LIKE sy-tabix.
    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( `plain` ).
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


    temp4 = sy-tabix.
    READ TABLE ls_b-t_part INDEX 2 ASSIGNING <temp3>.
    sy-tabix = temp4.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = `/SUM`
                                        act = <temp3>-path ).

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

    DATA temp5 TYPE z2ui5_cl_agent_viewxml=>ty_t_ref_val.
    DATA temp6 LIKE LINE OF temp5.
    DATA ls_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    DATA temp7 TYPE string.
    CLEAR temp5.

    temp6-ref = `/EDIT`.
    temp6-val = z2ui5_cl_agent_viewxml=>val_boolean( abap_true ).
    INSERT temp6 INTO TABLE temp5.
    temp6-ref = `/MODE`.
    temp6-val = z2ui5_cl_agent_viewxml=>val_string( `A` ).
    INSERT temp6 INTO TABLE temp5.
    temp6-ref = `/N`.
    temp6-val = z2ui5_cl_agent_viewxml=>val_number( `3` ).
    INSERT temp6 INTO TABLE temp5.
    temp6-ref = `/LIST`.
    CLEAR temp6-val.
    temp6-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
    temp6-val-json = `[1,2]`.
    temp6-val-num = 2.
    INSERT temp6 INTO TABLE temp5.
    lt_ref = temp5.

    ls_val = z2ui5_cl_agent_viewxml=>eval_expression( val   = src
                                                            t_ref = lt_ref ).

    IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
      temp7 = `undefined`.
    ELSE.
      temp7 = z2ui5_cl_agent_viewxml=>val_to_json( ls_val ).
    ENDIF.
    result = temp7.

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

    DATA ls_wire TYPE z2ui5_cl_agent_viewxml=>ty_s_wire.
    DATA temp8 TYPE string_table.
    DATA ls_arg LIKE LINE OF ls_wire-t_arg.
      DATA temp10 TYPE string.
    DATA temp11 TYPE string_table.
    ls_wire = z2ui5_cl_agent_viewxml=>parse_wire(
        `.eB(['ROW',false,false,false,true], ${NAME}, 'it\'s, a', ${/S/X}, ${$source>/text}, ${$parameters>/selectedItem}, $event, ${QTY} * 10, 5)` ).
    cl_abap_unit_assert=>assert_true( ls_wire-valid ).
    cl_abap_unit_assert=>assert_equals( exp = `ROW`
                                        act = ls_wire-event ).

    CLEAR temp8.
    INSERT `false` INTO TABLE temp8.
    INSERT `false` INTO TABLE temp8.
    INSERT `false` INTO TABLE temp8.
    INSERT `true` INTO TABLE temp8.
    cl_abap_unit_assert=>assert_equals( exp = temp8
                                        act = ls_wire-t_flag ).

    LOOP AT ls_wire-t_arg INTO ls_arg.

      IF ls_arg-static = abap_true.
        temp10 = z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val ).
      ELSE.
        temp10 = ls_arg-describe.
      ENDIF.
      INSERT temp10 INTO TABLE lt_desc.
    ENDLOOP.

    CLEAR temp11.
    INSERT `$row:NAME` INTO TABLE temp11.
    INSERT `"it's, a"` INTO TABLE temp11.
    INSERT `$model:/S/X` INTO TABLE temp11.
    INSERT `$source:text` INTO TABLE temp11.
    INSERT `$parameters:selectedItem` INTO TABLE temp11.
    INSERT `$event` INTO TABLE temp11.
    INSERT `$expr:${QTY} * 10` INTO TABLE temp11.
    INSERT `5` INTO TABLE temp11.
    cl_abap_unit_assert=>assert_equals( exp = temp11
                                        act = lt_desc ).

  ENDMETHOD.

  METHOD wire_variants.

    DATA ls_wire TYPE z2ui5_cl_agent_viewxml=>ty_s_wire.
    FIELD-SYMBOLS <temp13> LIKE LINE OF ls_wire-t_arg.
    DATA temp14 LIKE sy-tabix.
    ls_wire = z2ui5_cl_agent_viewxml=>parse_wire( `.eBP($event, true, ['NAV'], 'x')` ).
    cl_abap_unit_assert=>assert_equals( exp = `NAV`
                                        act = ls_wire-event ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( ls_wire-t_arg ) ).

    ls_wire = z2ui5_cl_agent_viewxml=>parse_wire( `.eF('CONTROL_GLOBAL', 'VIEW_SLOTS', 'destroy', 'POPUP')` ).
    cl_abap_unit_assert=>assert_equals( exp = `eF`
                                        act = ls_wire-fn ).
    cl_abap_unit_assert=>assert_equals( exp = `CONTROL_GLOBAL`
                                        act = ls_wire-action ).


    temp14 = sy-tabix.
    READ TABLE ls_wire-t_arg INDEX 3 ASSIGNING <temp13>.
    sy-tabix = temp14.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = <temp13>-val-str ).

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
    DATA temp15 TYPE xstring.

    cl_abap_unit_assert=>assert_equals( exp = `"a\"b\\c\nd"`
                                        act = z2ui5_cl_agent_viewxml=>json_string( |a"b\\c{ cl_abap_char_utilities=>newline }d| ) ).
    " a control character without a short escape - valid JSON all the same
    cl_abap_unit_assert=>assert_equals( exp = `"a\u000bb"`
                                        act = z2ui5_cl_agent_viewxml=>json_string( |a{ cl_abap_char_utilities=>vertical_tab }b| ) ).
    " NUL too, as JSON.stringify writes it

    temp15 = `00`.
    cl_abap_unit_assert=>assert_equals( exp = `"a\u0000b"`
                                        act = z2ui5_cl_agent_viewxml=>json_string(
                                                  |a{ z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp15 ) }b| ) ).
    cl_abap_unit_assert=>assert_equals( exp = `1.5`
                                        act = z2ui5_cl_agent_viewxml=>number_normalize( `01.50` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ab...`
                                        act = z2ui5_cl_agent_viewxml=>clip( val = |ab  cd   ef|
                                                                            len = 5 ) ).

  ENDMETHOD.

  METHOD cut_surrogate_pair.

    " U+1F600, two UTF-16 code units: a cut between them keeps neither
    DATA temp16 TYPE xstring.
    DATA lv_emoji TYPE string.
    temp16 = `F09F9880`.

    lv_emoji = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp16 ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = strlen( lv_emoji ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ab`
                                        act = z2ui5_cl_agent_viewxml=>cut( val = |ab{ lv_emoji }c|
                                                                           len = 3 ) ).
    cl_abap_unit_assert=>assert_equals( exp = |ab{ lv_emoji }|
                                        act = z2ui5_cl_agent_viewxml=>cut( val = |ab{ lv_emoji }c|
                                                                           len = 4 ) ).
    cl_abap_unit_assert=>assert_equals( exp = `abc`
                                        act = z2ui5_cl_agent_viewxml=>cut( val = `abcd`
                                                                           len = 3 ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ab`
                                        act = z2ui5_cl_agent_viewxml=>cut( val = `ab`
                                                                           len = 3 ) ).

  ENDMETHOD.

ENDCLASS.
