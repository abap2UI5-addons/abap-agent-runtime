"! The three small parsers the agent snapshot stands on - an ABAP port of
"! lib/viewxml.mjs of abap2UI5/mcp-server, the reference implementation of
"! agent snapshot v1 (docs/agent-snapshot.md there):
"!
"!   parse_xml( )        an abap2UI5 view or fragment -&gt; flat node table with
"!                       RESOLVED namespaces (xmlns="sap.m" + Input is
"!                       sap.m.Input), entities decoded, text kept
"!   parse_binding( )    a UI5 property value -&gt; literal, path binding,
"!                       composite text or expression binding
"!   parse_wire( )       an event handler the backend wrote (.eB([...]),
"!                       .eBP($event, cond, [...]), .eF(...)) -&gt; event name
"!                       and argument descriptors
"!   eval_expression( )  a UI5 expression binding body evaluated over the
"!                       values of its ${...} references, WITHOUT any
"!                       dynamic code: a tiny parser for the operators views
"!                       actually use, and "undefined" for anything else
"!
"! Lenient on purpose, like the reference: a closing tag pops whatever is
"! open - the backend wrote this XML and the browser already accepted it;
"! the snapshot describes it, it does not judge it. That is also why this is
"! a hand-written scanner and not sXML: a strict parser refuses views the
"! browser renders, and the scanner runs unchanged on 7.02, ABAP Cloud and
"! the transpiled runtime.
CLASS z2ui5_cl_agent_viewxml DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      "! The kinds of a JavaScript value as the snapshot needs them.
      BEGIN OF cs_kind,
        undefined TYPE c LENGTH 1 VALUE 'u',
        null      TYPE c LENGTH 1 VALUE 'z',
        boolean   TYPE c LENGTH 1 VALUE 'b',
        number    TYPE c LENGTH 1 VALUE 'n',
        string    TYPE c LENGTH 1 VALUE 's',
        object    TYPE c LENGTH 1 VALUE 'o',
        array     TYPE c LENGTH 1 VALUE 'a',
      END OF cs_kind.

    TYPES:
      "! A JavaScript value. str holds the text of a string, the JSON literal
      "! of a number and true/false of a boolean; json the JSON text of an
      "! object or array; num the numeric value (the length of an array);
      "! nan marks a number that is not one. An initial kind is undefined.
      BEGIN OF ty_s_val,
        kind TYPE c LENGTH 1,
        str  TYPE string,
        num  TYPE decfloat34,
        nan  TYPE abap_bool,
        json TYPE string,
      END OF ty_s_val.
    TYPES ty_t_val TYPE STANDARD TABLE OF ty_s_val WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_attr,
        name  TYPE string,
        value TYPE string,
      END OF ty_s_attr.
    TYPES ty_t_attr TYPE STANDARD TABLE OF ty_s_attr WITH DEFAULT KEY.
    TYPES ty_t_int TYPE STANDARD TABLE OF i WITH DEFAULT KEY.

    TYPES:
      "! One element. The table index IS the id; node 1 is the document.
      "! ns is the namespace URI the prefix resolves to (UI5 uses library
      "! names as URIs: sap.m, sap.ui.layout.form, z2ui5.cc).
      BEGIN OF ty_s_node,
        id      TYPE i,
        parent  TYPE i,
        tag     TYPE string,
        prefix  TYPE string,
        local   TYPE string,
        ns      TYPE string,
        t_attr  TYPE ty_t_attr,
        t_child TYPE ty_t_int,
        t_ns    TYPE ty_t_attr,
        text    TYPE string,
      END OF ty_s_node.
    TYPES ty_t_node TYPE STANDARD TABLE OF ty_s_node WITH DEFAULT KEY.

    TYPES:
      "! One part of a binding: a text, or one {...} body classified as a
      "! path (with model, relative, type, formatter), an expression or a
      "! computed binding (parts/formatter) the snapshot cannot evaluate.
      BEGIN OF ty_s_part,
        is_text    TYPE abap_bool,
        text       TYPE string,
        is_path    TYPE abap_bool,
        path       TYPE string,
        model      TYPE string,
        relative   TYPE abap_bool,
        type       TYPE string,
        formatter  TYPE abap_bool,
        is_expr    TYPE abap_bool,
        expression TYPE string,
        computed   TYPE string,
      END OF ty_s_part.
    TYPES ty_t_part TYPE STANDARD TABLE OF ty_s_part WITH DEFAULT KEY.

    CONSTANTS:
      BEGIN OF cs_binding,
        literal    TYPE string VALUE `literal`,
        path       TYPE string VALUE `path`,
        expression TYPE string VALUE `expression`,
        composite  TYPE string VALUE `composite`,
      END OF cs_binding.

    TYPES:
      "! A property value classified - see cs_binding. A literal carries
      "! value; a path path, model, relative, type; an expression its body;
      "! a composite its parts.
      BEGIN OF ty_s_binding,
        kind       TYPE string,
        value      TYPE string,
        path       TYPE string,
        model      TYPE string,
        relative   TYPE abap_bool,
        type       TYPE string,
        expression TYPE string,
        t_part     TYPE ty_t_part,
      END OF ty_s_binding.

    TYPES:
      "! One argument of a wire. Static: val (a string, number or boolean).
      "! Dynamic: kind row | model | source | parameters | event | expr |
      "! action, with path / prop / raw, and describe - the descriptor string
      "! of the snapshot ($row:VALUE, $source:text, ...).
      BEGIN OF ty_s_arg,
        static   TYPE abap_bool,
        val      TYPE ty_s_val,
        kind     TYPE string,
        path     TYPE string,
        prop     TYPE string,
        raw      TYPE string,
        describe TYPE string,
      END OF ty_s_arg.
    TYPES ty_t_arg TYPE STANDARD TABLE OF ty_s_arg WITH DEFAULT KEY.

    TYPES:
      "! An event handler: fn eB (eBP included) with event, flags and args,
      "! or eF with action and args. valid is false when the value is no
      "! abap2UI5 wire.
      BEGIN OF ty_s_wire,
        valid  TYPE abap_bool,
        fn     TYPE string,
        event  TYPE string,
        action TYPE string,
        t_flag TYPE string_table,
        t_arg  TYPE ty_t_arg,
      END OF ty_s_wire.

    TYPES:
      "! The value of one ${...} reference of an expression.
      BEGIN OF ty_s_ref_val,
        ref TYPE string,
        val TYPE ty_s_val,
      END OF ty_s_ref_val.
    TYPES ty_t_ref_val TYPE STANDARD TABLE OF ty_s_ref_val WITH DEFAULT KEY.

    CLASS-METHODS parse_xml
      IMPORTING
        xml           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_t_node.

    CLASS-METHODS decode_entities
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! An element whose local name starts lower case is an AGGREGATION of
    "! its parent (content, headerToolbar), not a control.
    CLASS-METHODS is_aggregation
      IMPORTING
        node          TYPE ty_s_node
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The full control name: namespace URI + local name (sap.m.Input).
    CLASS-METHODS control_name
      IMPORTING
        node          TYPE ty_s_node
      RETURNING
        VALUE(result) TYPE string.

    "! The value of an attribute; found = abap_false when it is absent
    "! (absent and empty are different things to UI5).
    CLASS-METHODS attr
      IMPORTING
        node          TYPE ty_s_node
        name          TYPE clike
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS parse_binding
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_binding.

    CLASS-METHODS parse_wire
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_wire.

    CLASS-METHODS describe_arg
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_arg.

    "! Whether a property value carries a wire (.eB( / .eBP( / .eF( ).
    CLASS-METHODS has_wire
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The ${...} references of an expression body, in order - resolve
    "! them and hand the values to eval_expression( ).
    CLASS-METHODS expression_refs
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string_table.

    CLASS-METHODS eval_expression
      IMPORTING
        val           TYPE clike
        t_ref         TYPE ty_t_ref_val OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_val.

    "! JavaScript truthiness.
    CLASS-METHODS val_truthy
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! JavaScript String( value ).
    CLASS-METHODS val_to_string
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE string.

    "! The value as a JSON literal (undefined as null, like JSON.stringify
    "! inside an object writes a null for a missing value in this contract).
    CLASS-METHODS val_to_json
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS val_string
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_val.

    CLASS-METHODS val_number
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_val.

    CLASS-METHODS val_boolean
      IMPORTING
        val           TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_s_val.

    "! A string as a JSON string literal, escaped as JSON.stringify does.
    CLASS-METHODS json_string
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! A number literal as JavaScript writes it back (Number( s ) then
    "! String): no leading zeros, no trailing fraction zeros.
    CLASS-METHODS number_normalize
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! Whitespace collapsed and trimmed, cut to len characters with ...
    CLASS-METHODS clip
      IMPORTING
        val           TYPE clike
        len           TYPE i DEFAULT 200
      RETURNING
        VALUE(result) TYPE string.

    "! The first len characters of val - one less when the last of them
    "! would be the first half of a surrogate pair (an emoji): that half
    "! alone is no character. For a text cut short in a message or the
    "! audit log.
    CLASS-METHODS cut
      IMPORTING
        val           TYPE clike
        len           TYPE i
      RETURNING
        VALUE(result) TYPE string.

    "! An argument as an error text repeats it: at most 80 characters, cut
    "! as cut( ) cuts - a session id of 150k characters came back as a 150k
    "! error (mcp-server lib/appclient.mjs echo).
    CLASS-METHODS echo
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! A single- or double-quoted JavaScript string literal -&gt; its value.
    CLASS-METHODS js_string
      IMPORTING
        val           TYPE clike
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS split_args
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string_table.

  PROTECTED SECTION.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_s_token,
        type  TYPE string,
        value TYPE string,
      END OF ty_s_token.
    TYPES ty_t_token TYPE STANDARD TABLE OF ty_s_token WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_raw_part,
        is_binding TYPE abap_bool,
        text       TYPE string,
      END OF ty_s_raw_part.
    TYPES ty_t_raw_part TYPE STANDARD TABLE OF ty_s_raw_part WITH DEFAULT KEY.

    CONSTANTS c_word TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_`.
    CONSTANTS c_alpha TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`.
    CONSTANTS c_digit TYPE string VALUE `0123456789`.
    CONSTANTS c_hex TYPE string VALUE `0123456789abcdefABCDEF`.
    CONSTANTS c_name_chars TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-`.
    CONSTANTS c_path_chars TYPE string VALUE `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_$/.-`.
    "! The UTF-8 bytes of the control characters json_string( ) writes as
    "! \u00xx - the ones without a short escape.
    CONSTANTS c_json_control_hex TYPE string VALUE `0102030405060B0E0F101112131415161718191A1B1C1D1E1F`.

    "! c_json_control_hex as characters, built on first use.
    CLASS-DATA gv_json_controls TYPE string.
    CLASS-DATA gv_json_controls_set TYPE abap_bool.
    "! NUL as a character, built on first use - empty where the platform
    "! cannot build it.
    CLASS-DATA gv_json_nul TYPE string.
    CLASS-DATA gv_json_nul_set TYPE abap_bool.

    "! The UTF-8 bytes of U+10000 and U+10FFFF - as characters the first
    "! and the last high surrogate, each followed by a low one.
    CONSTANTS c_surrogate_hex TYPE string VALUE `F0908080F48FBFBF`.

    "! The first and the last high surrogate, built on first use.
    CLASS-DATA gv_high_first TYPE string.
    CLASS-DATA gv_high_last TYPE string.
    CLASS-DATA gv_high_set TYPE abap_bool.

    DATA mt_token TYPE ty_t_token.
    DATA mv_pos   TYPE i.
    DATA mt_ref   TYPE ty_t_ref_val.

    CLASS-METHODS ws
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS is_ws
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS trim
      IMPORTING
        val           TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS char_of_code
      IMPORTING
        code          TYPE i
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS split_binding_parts
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE ty_t_raw_part.

    CLASS-METHODS binding_info
      IMPORTING
        body          TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_part.

    CLASS-METHODS check_model_name
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS key_position
      IMPORTING
        body          TYPE string
        key           TYPE string
      RETURNING
        VALUE(result) TYPE i.

    CLASS-METHODS key_quoted_value
      IMPORTING
        body          TYPE string
        key           TYPE string
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS tokenize
      IMPORTING
        val           TYPE string
      EXPORTING
        failed        TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_t_token.

    CLASS-METHODS val_to_number
      IMPORTING
        val           TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE ty_s_val.

    CLASS-METHODS val_from_num
      IMPORTING
        num           TYPE decfloat34
      RETURNING
        VALUE(result) TYPE ty_s_val.

    CLASS-METHODS val_nan
      RETURNING
        VALUE(result) TYPE ty_s_val.

    CLASS-METHODS val_strict_equal
      IMPORTING
        a             TYPE ty_s_val
        b             TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS val_loose_equal
      IMPORTING
        a             TYPE ty_s_val
        b             TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS apply_op
      IMPORTING
        op            TYPE string
        a             TYPE ty_s_val
        b             TYPE ty_s_val
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS peek
      RETURNING
        VALUE(result) TYPE ty_s_token.

    METHODS take
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_s_token.

    METHODS parse_ternary
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS parse_binary
      IMPORTING
        level         TYPE i
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS parse_postfix
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS parse_primary
      RETURNING
        VALUE(result) TYPE ty_s_val
      RAISING
        z2ui5_cx_ui5_util_error.

    METHODS fail
      RAISING
        z2ui5_cx_ui5_util_error.

ENDCLASS.


CLASS z2ui5_cl_agent_viewxml IMPLEMENTATION.

  METHOD ws.

    result = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf
          && cl_abap_char_utilities=>form_feed && cl_abap_char_utilities=>vertical_tab.

  ENDMETHOD.

  METHOD is_ws.
    DATA temp1 TYPE xsdboolean.

    IF val IS INITIAL.
      RETURN.
    ENDIF.

    temp1 = boolc( val CA ws( ) ).
    result = temp1.

  ENDMETHOD.

  METHOD trim.

    DATA lv_ws TYPE string.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
      DATA lv_last TYPE i.

    result = val.
    lv_ws = ws( ).
    lv_to = strlen( result ).
    WHILE lv_from < lv_to AND result+lv_from(1) CA lv_ws.
      lv_from = lv_from + 1.
    ENDWHILE.
    WHILE lv_to > lv_from.

      lv_last = lv_to - 1.
      IF result+lv_last(1) CA lv_ws.
        lv_to = lv_last.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    result = substring( val = result
                        off = lv_from
                        len = lv_to - lv_from ).

  ENDMETHOD.

  METHOD clip.

    DATA lv_ws TYPE string.
    DATA lv_index TYPE i.
      DATA lv_char TYPE string.

    result = val.
    lv_ws = ws( ).

    lv_index = 0.
    WHILE lv_index < strlen( lv_ws ).

      lv_char = lv_ws+lv_index(1).
      IF lv_char <> ` `.
        REPLACE ALL OCCURRENCES OF lv_char IN result WITH ` `.
      ENDIF.
      lv_index = lv_index + 1.
    ENDWHILE.
    result = condense( result ).
    IF strlen( result ) > len.
      result = substring( val = result
                          len = len - 3 ) && `...`.
    ENDIF.

  ENDMETHOD.

  METHOD echo.

    result = val.
    IF strlen( result ) > 80.
      result = cut( val = result
                    len = 80 ) && `...`.
    ENDIF.

  ENDMETHOD.

  METHOD cut.
          DATA temp17 TYPE xstring.
          DATA lv_pairs TYPE string.
    DATA lv_last TYPE string.

    result = val.
    IF len <= 0.
      CLEAR result.
      RETURN.
    ENDIF.
    IF strlen( result ) <= len.
      RETURN.
    ENDIF.
    result = substring( val = result
                        len = len ).

    IF gv_high_set = abap_false.
      TRY.

          temp17 = c_surrogate_hex.

          lv_pairs = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp17 ).
          IF strlen( lv_pairs ) = 4.
            gv_high_first = substring( val = lv_pairs
                                       len = 1 ).
            gv_high_last = substring( val = lv_pairs
                                      off = 2
                                      len = 1 ).
          ENDIF.
        CATCH cx_root.
          CLEAR: gv_high_first, gv_high_last.
      ENDTRY.
      gv_high_set = abap_true.
    ENDIF.
    IF gv_high_first IS INITIAL.
      RETURN.
    ENDIF.

    lv_last = substring( val = result
                               off = len - 1
                               len = 1 ).
    IF lv_last >= gv_high_first AND lv_last <= gv_high_last.
      result = substring( val = result
                          len = len - 1 ).
    ENDIF.

  ENDMETHOD.

  METHOD char_of_code.

    CONSTANTS lc_ascii TYPE string VALUE ` !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_``abcdefghijklmnopqrstuvwxyz{|}~`.
    DATA lv_byte TYPE x LENGTH 1.
    DATA lv_utf8 TYPE xstring.

    CASE code.
      WHEN 9.
        result = cl_abap_char_utilities=>horizontal_tab.
        RETURN.
      WHEN 10.
        result = cl_abap_char_utilities=>newline.
        RETURN.
      WHEN 13.
        result = substring( val = cl_abap_char_utilities=>cr_lf
                            len = 1 ).
        RETURN.
    ENDCASE.

    IF code >= 32 AND code <= 126.
      result = substring( val = lc_ascii
                          off = code - 32
                          len = 1 ).
      RETURN.
    ENDIF.

    " anything else as UTF-8 bytes, decoded by the core's codepage helper
    IF code < 128 OR code > 1114111.
      RETURN.
    ELSEIF code < 2048.
      lv_byte = 192 + code DIV 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + code MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
    ELSEIF code < 65536.
      lv_byte = 224 + code DIV 4096.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + ( code DIV 64 ) MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + code MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
    ELSE.
      lv_byte = 240 + code DIV 262144.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + ( code DIV 4096 ) MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + ( code DIV 64 ) MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
      lv_byte = 128 + code MOD 64.
      CONCATENATE lv_utf8 lv_byte INTO lv_utf8 IN BYTE MODE.
    ENDIF.

    TRY.
        result = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( lv_utf8 ).
      CATCH cx_root.
        CLEAR result.
    ENDTRY.

  ENDMETHOD.

  METHOD decode_entities.

    DATA lv_code TYPE i.
    DATA lv_char TYPE string.

    DATA temp18 TYPE string.
    DATA lv_src LIKE temp18.
    DATA lv_len TYPE i.
    DATA lv_pos TYPE i.
      DATA lv_amp TYPE i.
      DATA lv_semi TYPE i.
      DATA lv_name TYPE string.
      DATA lv_ok LIKE abap_false.
        DATA lv_hex TYPE string.
              DATA lv_index TYPE i.
                DATA lv_digit TYPE i.
              DATA temp2 TYPE xsdboolean.
        DATA lv_dec TYPE string.
              DATA temp3 TYPE xsdboolean.
    temp18 = val.

    lv_src = temp18.

    lv_len = strlen( lv_src ).

    lv_pos = 0.

    WHILE lv_pos < lv_len.

      lv_amp = find( val = lv_src
                           sub = `&`
                           off = lv_pos ).
      IF lv_amp < 0.
        result = result && substring( val = lv_src
                                      off = lv_pos ).
        RETURN.
      ENDIF.
      result = result && substring( val = lv_src
                                    off = lv_pos
                                    len = lv_amp - lv_pos ).

      lv_semi = find( val = lv_src
                            sub = `;`
                            off = lv_amp + 1 ).
      IF lv_semi < 0.
        result = result && substring( val = lv_src
                                      off = lv_amp ).
        RETURN.
      ENDIF.


      lv_name = substring( val = lv_src
                                 off = lv_amp + 1
                                 len = lv_semi - lv_amp - 1 ).
      CLEAR lv_char.

      lv_ok = abap_false.
      IF strlen( lv_name ) > 2 AND ( lv_name(2) = `#x` OR lv_name(2) = `#X` ).

        lv_hex = substring( val = lv_name
                                  off = 2 ).
        IF lv_hex CO c_hex.
          TRY.
              lv_code = 0.

              lv_index = 0.
              WHILE lv_index < strlen( lv_hex ).

                lv_digit = find( val  = c_hex
                                       sub  = lv_hex+lv_index(1)
                                       case = abap_true ).
                IF lv_digit > 15.
                  lv_digit = lv_digit - 6.
                ENDIF.
                lv_code = lv_code * 16 + lv_digit.
                lv_index = lv_index + 1.
              ENDWHILE.
              lv_char = char_of_code( lv_code ).

              temp2 = boolc( lv_char IS NOT INITIAL ).
              lv_ok = temp2.
            CATCH cx_root.
              lv_ok = abap_false.
          ENDTRY.
        ENDIF.
      ELSEIF strlen( lv_name ) > 1 AND lv_name(1) = `#`.

        lv_dec = substring( val = lv_name
                                  off = 1 ).
        IF lv_dec CO c_digit.
          TRY.
              lv_code = lv_dec.
              lv_char = char_of_code( lv_code ).

              temp3 = boolc( lv_char IS NOT INITIAL ).
              lv_ok = temp3.
            CATCH cx_root.
              lv_ok = abap_false.
          ENDTRY.
        ENDIF.
      ELSE.
        CASE lv_name.
          WHEN `lt`.
            lv_char = `<`.
            lv_ok = abap_true.
          WHEN `gt`.
            lv_char = `>`.
            lv_ok = abap_true.
          WHEN `amp`.
            lv_char = `&`.
            lv_ok = abap_true.
          WHEN `quot`.
            lv_char = `"`.
            lv_ok = abap_true.
          WHEN `apos`.
            lv_char = `'`.
            lv_ok = abap_true.
        ENDCASE.
      ENDIF.

      IF lv_ok = abap_true.
        result = result && lv_char.
        lv_pos = lv_semi + 1.
      ELSE.
        result = result && `&`.
        lv_pos = lv_amp + 1.
      ENDIF.
    ENDWHILE.

  ENDMETHOD.

  METHOD parse_xml.

    DATA lt_stack TYPE ty_t_int.
    DATA ls_node TYPE ty_s_node.
    DATA lv_value TYPE string.
    DATA lv_self_close TYPE abap_bool.
    DATA lv_ws TYPE string.

    DATA temp19 TYPE string.
    DATA lv_src LIKE temp19.
    DATA lv_len TYPE i.
    DATA temp20 TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    DATA lv_i TYPE i.
      DATA lv_top LIKE LINE OF lt_stack.
      FIELD-SYMBOLS <temp20> LIKE LINE OF lt_stack.
      DATA temp31 LIKE sy-tabix.
      DATA lv_lt TYPE i.
        DATA lv_text TYPE string.
          DATA lr_top TYPE REF TO z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_rest TYPE i.
        DATA lv_end TYPE i.
        DATA temp21 TYPE i.
        DATA temp22 TYPE i.
        DATA lv_body_end LIKE temp22.
        DATA temp23 TYPE i.
      DATA temp24 TYPE string.
      DATA lv_next LIKE temp24.
        DATA temp25 TYPE i.
        DATA temp26 TYPE i.
      DATA lv_j TYPE i.
        DATA lv_c TYPE string.
          DATA lv_j1 TYPE i.
        DATA lv_k LIKE lv_j.
        DATA lv_name TYPE string.
          DATA temp27 TYPE string.
          DATA lv_quote LIKE temp27.
            DATA temp28 TYPE i.
          DATA lr_attr TYPE REF TO z2ui5_cl_agent_viewxml=>ty_s_attr.
            DATA temp29 TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
      DATA ls_parent TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA ls_attr LIKE LINE OF ls_node-t_attr.
        DATA lv_prefix_decl TYPE string.
        DATA lr_ns TYPE REF TO z2ui5_cl_agent_viewxml=>ty_s_attr.
          DATA temp30 TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
      DATA lv_colon TYPE i.
      DATA ls_ns TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
    temp19 = xml.

    lv_src = temp19.

    lv_len = strlen( lv_src ).
    lv_ws = ws( ).


    CLEAR temp20.
    temp20-id = 1.
    temp20-tag = `#document`.
    temp20-local = `#document`.
    INSERT temp20 INTO TABLE result.
    INSERT 1 INTO TABLE lt_stack.


    lv_i = 0.
    WHILE lv_i < lv_len.




      temp31 = sy-tabix.
      READ TABLE lt_stack INDEX lines( lt_stack ) ASSIGNING <temp20>.
      sy-tabix = temp31.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      lv_top = <temp20>.

      lv_lt = find( val = lv_src
                          sub = `<`
                          off = lv_i ).
      IF lv_lt < 0.

        lv_text = decode_entities( substring( val = lv_src
                                                    off = lv_i ) ).
        IF trim( lv_text ) IS NOT INITIAL.

          READ TABLE result INDEX lv_top REFERENCE INTO lr_top.
          lr_top->text = lr_top->text && lv_text.
        ENDIF.
        EXIT.
      ENDIF.
      IF lv_lt > lv_i.
        lv_text = decode_entities( substring( val = lv_src
                                              off = lv_i
                                              len = lv_lt - lv_i ) ).
        IF trim( lv_text ) IS NOT INITIAL.
          READ TABLE result INDEX lv_top REFERENCE INTO lr_top.
          lr_top->text = lr_top->text && lv_text.
        ENDIF.
      ENDIF.


      lv_rest = lv_len - lv_lt.

      " a comment
      IF lv_rest >= 4 AND lv_src+lv_lt(4) = `<!--`.

        lv_end = find( val = lv_src
                             sub = `-->`
                             off = lv_lt + 4 ).

        IF lv_end < 0.
          temp21 = lv_len.
        ELSE.
          temp21 = lv_end + 3.
        ENDIF.
        lv_i = temp21.
        CONTINUE.
      ENDIF.

      " CDATA: kept as text of the open element
      IF lv_rest >= 9 AND lv_src+lv_lt(9) = `<![CDATA[`.
        lv_end = find( val = lv_src
                       sub = `]]>`
                       off = lv_lt + 9 ).

        IF lv_end < 0.
          temp22 = lv_len.
        ELSE.
          temp22 = lv_end.
        ENDIF.

        lv_body_end = temp22.
        READ TABLE result INDEX lv_top REFERENCE INTO lr_top.
        lr_top->text = lr_top->text && substring( val = lv_src
                                                  off = lv_lt + 9
                                                  len = lv_body_end - lv_lt - 9 ).

        IF lv_end < 0.
          temp23 = lv_len.
        ELSE.
          temp23 = lv_end + 3.
        ENDIF.
        lv_i = temp23.
        CONTINUE.
      ENDIF.

      " a declaration or processing instruction

      IF lv_rest > 1.
        temp24 = lv_src+lv_lt(2).
      ELSE.
        CLEAR temp24.
      ENDIF.

      lv_next = temp24.
      IF lv_next = `<?` OR lv_next = `<!`.
        lv_end = find( val = lv_src
                       sub = `>`
                       off = lv_lt ).

        IF lv_end < 0.
          temp25 = lv_len.
        ELSE.
          temp25 = lv_end + 1.
        ENDIF.
        lv_i = temp25.
        CONTINUE.
      ENDIF.

      " a closing tag pops whatever is open
      IF lv_next = `</`.
        lv_end = find( val = lv_src
                       sub = `>`
                       off = lv_lt ).
        IF lines( lt_stack ) > 1.
          DELETE lt_stack INDEX lines( lt_stack ).
        ENDIF.

        IF lv_end < 0.
          temp26 = lv_len.
        ELSE.
          temp26 = lv_end + 1.
        ENDIF.
        lv_i = temp26.
        CONTINUE.
      ENDIF.

      " an opening tag: the name, then attributes up to the unquoted '>'

      lv_j = lv_lt + 1.
      WHILE lv_j < lv_len.

        lv_c = lv_src+lv_j(1).
        IF lv_c CA lv_ws OR lv_c = `/` OR lv_c = `>`.
          EXIT.
        ENDIF.
        lv_j = lv_j + 1.
      ENDWHILE.

      CLEAR ls_node.
      ls_node-tag = substring( val = lv_src
                               off = lv_lt + 1
                               len = lv_j - lv_lt - 1 ).
      lv_self_close = abap_false.

      DO.
        WHILE lv_j < lv_len AND lv_src+lv_j(1) CA lv_ws.
          lv_j = lv_j + 1.
        ENDWHILE.
        IF lv_j >= lv_len.
          EXIT.
        ENDIF.
        lv_c = lv_src+lv_j(1).
        IF lv_c = `>`.
          lv_j = lv_j + 1.
          EXIT.
        ENDIF.
        IF lv_c = `/` AND lv_j + 1 < lv_len.

          lv_j1 = lv_j + 1.
          IF lv_src+lv_j1(1) = `>`.
            lv_self_close = abap_true.
            lv_j = lv_j + 2.
            EXIT.
          ENDIF.
        ENDIF.


        lv_k = lv_j.
        WHILE lv_k < lv_len.
          lv_c = lv_src+lv_k(1).
          IF lv_c CA lv_ws OR lv_c = `=` OR lv_c = `/` OR lv_c = `>`.
            EXIT.
          ENDIF.
          lv_k = lv_k + 1.
        ENDWHILE.

        lv_name = substring( val = lv_src
                                   off = lv_j
                                   len = lv_k - lv_j ).
        lv_j = lv_k.
        WHILE lv_j < lv_len AND lv_src+lv_j(1) CA lv_ws.
          lv_j = lv_j + 1.
        ENDWHILE.

        CLEAR lv_value.
        IF lv_j < lv_len AND lv_src+lv_j(1) = `=`.
          lv_j = lv_j + 1.
          WHILE lv_j < lv_len AND lv_src+lv_j(1) CA lv_ws.
            lv_j = lv_j + 1.
          ENDWHILE.

          IF lv_j < lv_len.
            temp27 = lv_src+lv_j(1).
          ELSE.
            CLEAR temp27.
          ENDIF.

          lv_quote = temp27.
          IF lv_quote = `"` OR lv_quote = `'`.
            lv_end = find( val = lv_src
                           sub = lv_quote
                           off = lv_j + 1 ).
            IF lv_end < 0.
              lv_end = lv_len.
            ENDIF.
            lv_value = substring( val = lv_src
                                  off = lv_j + 1
                                  len = lv_end - lv_j - 1 ).

            IF lv_end >= lv_len.
              temp28 = lv_len.
            ELSE.
              temp28 = lv_end + 1.
            ENDIF.
            lv_j = temp28.
          ELSE.
            lv_end = lv_j.
            WHILE lv_end < lv_len.
              lv_c = lv_src+lv_end(1).
              IF lv_c CA lv_ws OR lv_c = `>`.
                EXIT.
              ENDIF.
              lv_end = lv_end + 1.
            ENDWHILE.
            lv_value = substring( val = lv_src
                                  off = lv_j
                                  len = lv_end - lv_j ).
            lv_j = lv_end.
          ENDIF.
        ENDIF.

        IF lv_name IS INITIAL.
          " a stray character: step over it rather than loop
          lv_j = lv_j + 1.
        ELSE.

          READ TABLE ls_node-t_attr REFERENCE INTO lr_attr WITH KEY name = lv_name. "#EC CI_SORTSEQ
          IF sy-subrc = 0.
            lr_attr->value = decode_entities( lv_value ).
          ELSE.

            CLEAR temp29.
            temp29-name = lv_name.
            temp29-value = decode_entities( lv_value ).
            INSERT temp29 INTO TABLE ls_node-t_attr.
          ENDIF.
        ENDIF.
      ENDDO.

      " namespaces: the parent's map plus what this element declares

      READ TABLE result INDEX lv_top INTO ls_parent.
      ls_node-t_ns = ls_parent-t_ns.

      LOOP AT ls_node-t_attr INTO ls_attr.

        lv_prefix_decl = ``.
        IF ls_attr-name = `xmlns`.
          lv_prefix_decl = ``.
        ELSEIF strlen( ls_attr-name ) > 6 AND ls_attr-name(6) = `xmlns:`.
          lv_prefix_decl = substring( val = ls_attr-name
                                      off = 6 ).
        ELSE.
          CONTINUE.
        ENDIF.

        READ TABLE ls_node-t_ns REFERENCE INTO lr_ns WITH KEY name = lv_prefix_decl. "#EC CI_SORTSEQ
        IF sy-subrc = 0.
          lr_ns->value = ls_attr-value.
        ELSE.

          CLEAR temp30.
          temp30-name = lv_prefix_decl.
          temp30-value = ls_attr-value.
          INSERT temp30 INTO TABLE ls_node-t_ns.
        ENDIF.
      ENDLOOP.


      lv_colon = find( val = ls_node-tag
                             sub = `:` ).
      IF lv_colon < 0.
        ls_node-local = ls_node-tag.
      ELSE.
        ls_node-prefix = ls_node-tag(lv_colon).
        ls_node-local = substring( val = ls_node-tag
                                   off = lv_colon + 1 ).
      ENDIF.

      READ TABLE ls_node-t_ns INTO ls_ns WITH KEY name = ls_node-prefix. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        ls_node-ns = ls_ns-value.
      ENDIF.

      ls_node-id = lines( result ) + 1.
      ls_node-parent = lv_top.
      INSERT ls_node INTO TABLE result.
      READ TABLE result INDEX lv_top REFERENCE INTO lr_top.
      INSERT ls_node-id INTO TABLE lr_top->t_child.
      IF lv_self_close = abap_false.
        INSERT ls_node-id INTO TABLE lt_stack.
      ENDIF.
      lv_i = lv_j.
    ENDWHILE.

  ENDMETHOD.

  METHOD is_aggregation.
    DATA lv_first TYPE z2ui5_cl_agent_viewxml=>ty_s_node-local.
    DATA temp4 TYPE xsdboolean.

    IF node-local IS INITIAL.
      RETURN.
    ENDIF.

    lv_first = node-local(1).

    temp4 = boolc( lv_first CA `abcdefghijklmnopqrstuvwxyz` ).
    result = temp4.

  ENDMETHOD.

  METHOD control_name.

    DATA temp31 TYPE string.
    IF node-ns IS NOT INITIAL.
      temp31 = |{ node-ns }.{ node-local }|.
    ELSE.
      temp31 = node-local.
    ENDIF.
    result = temp31.

  ENDMETHOD.

  METHOD attr.

    DATA lv_name TYPE string.
    DATA ls_attr TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
    DATA temp5 TYPE xsdboolean.

    lv_name = name.

    READ TABLE node-t_attr INTO ls_attr WITH KEY name = lv_name. "#EC CI_SORTSEQ

    temp5 = boolc( sy-subrc = 0 ).
    found = temp5.
    IF found = abap_true.
      result = ls_attr-value.
    ENDIF.

  ENDMETHOD.

  METHOD split_binding_parts.

    " the UI5 binding parser's split: braces nest, quotes inside a binding
    " hide braces, and \{ \} \\ are escaped literal characters
    DATA lv_lit TYPE string.
    DATA lv_quote TYPE string.
    DATA lv_depth TYPE i.

    DATA lv_len TYPE i.
    DATA lv_i TYPE i.
      DATA lv_c TYPE string.
      DATA lv_i1 TYPE i.
      DATA temp32 TYPE string.
      DATA lv_n LIKE temp32.
        DATA lv_j LIKE lv_i.
          DATA lv_d TYPE string.
          DATA temp33 TYPE z2ui5_cl_agent_viewxml=>ty_s_raw_part.
        DATA temp34 TYPE z2ui5_cl_agent_viewxml=>ty_s_raw_part.
      DATA temp35 TYPE z2ui5_cl_agent_viewxml=>ty_s_raw_part.
    lv_len = strlen( val ).

    lv_i = 0.
    WHILE lv_i < lv_len.

      lv_c = val+lv_i(1).

      lv_i1 = lv_i + 1.

      IF lv_i1 < lv_len.
        temp32 = val+lv_i1(1).
      ELSE.
        CLEAR temp32.
      ENDIF.

      lv_n = temp32.
      IF lv_c = `\` AND ( lv_n = `{` OR lv_n = `}` OR lv_n = `\` ).
        lv_lit = lv_lit && lv_n.
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF lv_c = `{`.
        lv_depth = 0.
        CLEAR lv_quote.

        lv_j = lv_i.
        WHILE lv_j < lv_len.

          lv_d = val+lv_j(1).
          IF lv_quote IS NOT INITIAL.
            IF lv_d = `\`.
              lv_j = lv_j + 2.
              CONTINUE.
            ENDIF.
            IF lv_d = lv_quote.
              CLEAR lv_quote.
            ENDIF.
            lv_j = lv_j + 1.
            CONTINUE.
          ENDIF.
          IF lv_d = `"` OR lv_d = `'`.
            lv_quote = lv_d.
            lv_j = lv_j + 1.
            CONTINUE.
          ENDIF.
          CASE lv_d.
            WHEN `{`.
              lv_depth = lv_depth + 1.
            WHEN `}`.
              lv_depth = lv_depth - 1.
              IF lv_depth = 0.
                EXIT.
              ENDIF.
          ENDCASE.
          lv_j = lv_j + 1.
        ENDWHILE.
        IF lv_j >= lv_len.
          " unbalanced: the rest is text
          lv_lit = lv_lit && substring( val = val
                                        off = lv_i ).
          EXIT.
        ENDIF.
        IF lv_lit IS NOT INITIAL.

          CLEAR temp33.
          temp33-text = lv_lit.
          INSERT temp33 INTO TABLE result.
        ENDIF.
        CLEAR lv_lit.

        CLEAR temp34.
        temp34-is_binding = abap_true.
        temp34-text = substring( val = val off = lv_i + 1 len = lv_j - lv_i - 1 ).
        INSERT temp34 INTO TABLE result.
        lv_i = lv_j + 1.
        CONTINUE.
      ENDIF.
      lv_lit = lv_lit && lv_c.
      lv_i = lv_i + 1.
    ENDWHILE.
    IF lv_lit IS NOT INITIAL.

      CLEAR temp35.
      temp35-text = lv_lit.
      INSERT temp35 INTO TABLE result.
    ENDIF.

  ENDMETHOD.

  METHOD check_model_name.
    DATA lv_first TYPE string.
    DATA temp6 TYPE xsdboolean.

    " [A-Za-z_][\w.-]*
    IF val IS INITIAL.
      RETURN.
    ENDIF.

    lv_first = val(1).
    IF lv_first CN c_alpha.
      RETURN.
    ENDIF.

    temp6 = boolc( val CO c_name_chars ).
    result = temp6.

  ENDMETHOD.

  METHOD key_position.

    " the offset of the value behind (^|[,{\s])key\s*: - or -1
    DATA lv_off TYPE i.
      DATA lv_hit TYPE i.
        DATA lv_before TYPE i.
        DATA lv_b TYPE string.
      DATA lv_pos TYPE i.
    lv_off = 0.
    result = -1.
    DO.

      lv_hit = find( val = body
                           sub = key
                           off = lv_off ).
      IF lv_hit < 0.
        RETURN.
      ENDIF.
      lv_off = lv_hit + 1.
      IF lv_hit > 0.

        lv_before = lv_hit - 1.

        lv_b = body+lv_before(1).
        IF NOT ( lv_b = `,` OR lv_b = `{` OR is_ws( lv_b ) = abap_true ).
          CONTINUE.
        ENDIF.
      ENDIF.

      lv_pos = lv_hit + strlen( key ).
      WHILE lv_pos < strlen( body ) AND is_ws( substring( val = body off = lv_pos len = 1 ) ) = abap_true.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      IF lv_pos < strlen( body ) AND body+lv_pos(1) = `:`.
        result = lv_pos + 1.
        RETURN.
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD key_quoted_value.
    DATA lv_pos TYPE i.
    DATA lv_quote TYPE string.
    DATA lv_end TYPE i.

    " (^|[,{\s])key\s*:\s*(['"])(.*?)\1
    found = abap_false.

    lv_pos = key_position( body = body
                                 key  = key ).
    IF lv_pos < 0.
      RETURN.
    ENDIF.
    WHILE lv_pos < strlen( body ) AND is_ws( substring( val = body off = lv_pos len = 1 ) ) = abap_true.
      lv_pos = lv_pos + 1.
    ENDWHILE.
    IF lv_pos >= strlen( body ).
      RETURN.
    ENDIF.

    lv_quote = body+lv_pos(1).
    IF lv_quote <> `'` AND lv_quote <> `"`.
      RETURN.
    ENDIF.

    lv_end = find( val = body
                         sub = lv_quote
                         off = lv_pos + 1 ).
    IF lv_end < 0.
      RETURN.
    ENDIF.
    found = abap_true.
    result = substring( val = body
                        off = lv_pos + 1
                        len = lv_end - lv_pos - 1 ).

  ENDMETHOD.

  METHOD binding_info.

    DATA lv_found TYPE abap_bool.

    DATA lv_b TYPE string.
    DATA lv_model TYPE string.
    DATA lv_rest LIKE lv_b.
    DATA lv_gt TYPE i.
    DATA lv_simple LIKE abap_true.
      DATA temp7 TYPE xsdboolean.
    DATA lv_path TYPE string.
      DATA lv_model_key TYPE string.
      DATA temp8 TYPE xsdboolean.
      DATA temp9 TYPE xsdboolean.
    lv_b = trim( body ).
    IF strlen( lv_b ) > 0 AND lv_b(1) = `=`.
      result-is_expr = abap_true.
      result-expression = substring( val = lv_b
                                     off = 1 ).
      RETURN.
    ENDIF.
    IF strlen( lv_b ) > 1 AND lv_b(2) = `:=`.
      result-is_expr = abap_true.
      result-expression = substring( val = lv_b
                                     off = 2 ).
      RETURN.
    ENDIF.

    " a simple path, optionally with a model name: name>/A/B

    lv_model = ``.

    lv_rest = lv_b.

    lv_gt = find( val = lv_b
                        sub = `>` ).

    lv_simple = abap_true.
    IF lv_gt >= 0.
      lv_model = lv_b(lv_gt).
      lv_rest = substring( val = lv_b
                           off = lv_gt + 1 ).
      IF check_model_name( lv_model ) = abap_false.
        lv_simple = abap_false.
      ENDIF.
    ENDIF.
    IF lv_simple = abap_true AND lv_rest IS NOT INITIAL AND lv_rest CO c_path_chars.
      result-is_path = abap_true.
      result-path = lv_rest.
      result-model = lv_model.

      temp7 = boolc( lv_rest(1) <> `/` ).
      result-relative = temp7.
      RETURN.
    ENDIF.

    " object syntax: { path: '/X', type: '...', formatter: '...' }
    IF key_position( body = lv_b
                     key  = `parts` ) >= 0.
      result-computed = lv_b.
      RETURN.
    ENDIF.

    lv_path = key_quoted_value( EXPORTING body  = lv_b
                                                key   = `path`
                                      IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result-is_path = abap_true.
      lv_gt = find( val = lv_path
                    sub = `>` ).
      IF lv_gt >= 0 AND check_model_name( substring( val = lv_path len = lv_gt ) ) = abap_true.
        result-model = lv_path(lv_gt).
        result-path = substring( val = lv_path
                                 off = lv_gt + 1 ).
      ELSE.
        result-path = lv_path.
      ENDIF.
      " model: 'name' binds to that model as well as name>/path does - a
      " value written to the default model's path would land elsewhere

      lv_model_key = key_quoted_value( EXPORTING body  = lv_b
                                                       key   = `model`
                                             IMPORTING found = lv_found ).
      IF lv_found = abap_true AND lv_model_key IS NOT INITIAL.
        result-model = lv_model_key.
      ENDIF.

      temp8 = boolc( result-path IS INITIAL OR result-path(1) <> `/` ).
      result-relative = temp8.
      result-type = key_quoted_value( body = lv_b
                                      key  = `type` ).

      temp9 = boolc( key_position( body = lv_b key = `formatter` ) >= 0 ).
      result-formatter = temp9.
      RETURN.
    ENDIF.

    result-computed = lv_b.

  ENDMETHOD.

  METHOD parse_binding.

    DATA lt_binding TYPE ty_t_raw_part.

    DATA temp36 TYPE string.
    DATA lt_raw TYPE z2ui5_cl_agent_viewxml=>ty_t_raw_part.
    DATA ls_raw LIKE LINE OF lt_raw.
      DATA ls_info TYPE z2ui5_cl_agent_viewxml=>ty_s_part.
      FIELD-SYMBOLS <temp32> LIKE LINE OF lt_binding.
      DATA temp33 LIKE sy-tabix.
        FIELD-SYMBOLS <temp37> LIKE LINE OF lt_binding.
        DATA temp38 LIKE sy-tabix.
        DATA temp39 TYPE z2ui5_cl_agent_viewxml=>ty_s_part.
    temp36 = val.

    lt_raw = split_binding_parts( temp36 ).

    LOOP AT lt_raw INTO ls_raw WHERE is_binding = abap_true.  "#EC CI_SORTSEQ
      INSERT ls_raw INTO TABLE lt_binding.
    ENDLOOP.

    IF lt_binding IS INITIAL.
      result-kind = cs_binding-literal.
      LOOP AT lt_raw INTO ls_raw.
        result-value = result-value && ls_raw-text.
      ENDLOOP.
      RETURN.
    ENDIF.

    IF lines( lt_raw ) = 1.



      temp33 = sy-tabix.
      READ TABLE lt_binding INDEX 1 ASSIGNING <temp32>.
      sy-tabix = temp33.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      ls_info = binding_info( <temp32>-text ).
      IF ls_info-is_expr = abap_true.
        result-kind = cs_binding-expression.
        result-expression = ls_info-expression.
        RETURN.
      ENDIF.
      IF ls_info-is_path = abap_true AND ls_info-formatter = abap_false.
        result-kind = cs_binding-path.
        result-path = ls_info-path.
        result-model = ls_info-model.
        result-relative = ls_info-relative.
        result-type = ls_info-type.
        RETURN.
      ENDIF.
      result-kind = cs_binding-composite.
      IF ls_info-is_path = abap_false AND ls_info-computed IS INITIAL.


        temp38 = sy-tabix.
        READ TABLE lt_binding INDEX 1 ASSIGNING <temp37>.
        sy-tabix = temp38.
        IF sy-subrc <> 0.
          ASSERT 1 = 0.
        ENDIF.
        ls_info-computed = <temp37>-text.
      ENDIF.
      INSERT ls_info INTO TABLE result-t_part.
      RETURN.
    ENDIF.

    result-kind = cs_binding-composite.
    LOOP AT lt_raw INTO ls_raw.
      IF ls_raw-is_binding = abap_true.
        INSERT binding_info( ls_raw-text ) INTO TABLE result-t_part.
      ELSE.

        CLEAR temp39.
        temp39-is_text = abap_true.
        temp39-text = ls_raw-text.
        INSERT temp39 INTO TABLE result-t_part.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD split_args.

    " a JS argument list split at top-level commas: quotes, (), [] and {} nest
    DATA lv_cur TYPE string.
    DATA lv_quote TYPE string.
    DATA lv_depth TYPE i.

    DATA temp40 TYPE string.
    DATA lv_s LIKE temp40.
    DATA lv_len TYPE i.
    DATA lv_i TYPE i.
      DATA lv_c TYPE string.
          DATA lv_i1 TYPE i.
    temp40 = val.

    lv_s = temp40.

    lv_len = strlen( lv_s ).

    lv_i = 0.
    WHILE lv_i < lv_len.

      lv_c = lv_s+lv_i(1).
      IF lv_quote IS NOT INITIAL.
        lv_cur = lv_cur && lv_c.
        IF lv_c = `\`.

          lv_i1 = lv_i + 1.
          IF lv_i1 < lv_len.
            lv_cur = lv_cur && lv_s+lv_i1(1).
          ENDIF.
          lv_i = lv_i + 2.
          CONTINUE.
        ENDIF.
        IF lv_c = lv_quote.
          CLEAR lv_quote.
        ENDIF.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      IF lv_c = `"` OR lv_c = `'`.
        lv_quote = lv_c.
        lv_cur = lv_cur && lv_c.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      IF lv_c CA `([{`.
        lv_depth = lv_depth + 1.
      ENDIF.
      IF lv_c CA `)]}`.
        lv_depth = lv_depth - 1.
      ENDIF.
      IF lv_c = `,` AND lv_depth = 0.
        INSERT trim( lv_cur ) INTO TABLE result.
        CLEAR lv_cur.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      lv_cur = lv_cur && lv_c.
      lv_i = lv_i + 1.
    ENDWHILE.
    IF trim( lv_cur ) IS NOT INITIAL.
      INSERT trim( lv_cur ) INTO TABLE result.
    ENDIF.

  ENDMETHOD.

  METHOD js_string.
    DATA lv_s TYPE string.
    DATA lv_len TYPE i.
    DATA lv_q TYPE string.
    DATA lv_last_off TYPE i.
    DATA lv_inner TYPE string.
    DATA lv_i TYPE i.
    DATA lv_ilen TYPE i.
      DATA lv_c TYPE string.
      DATA lv_i1 TYPE i.
        DATA lv_e TYPE string.

    found = abap_false.

    lv_s = trim( val ).

    lv_len = strlen( lv_s ).
    IF lv_len < 2.
      RETURN.
    ENDIF.

    lv_q = lv_s(1).

    lv_last_off = lv_len - 1.
    IF ( lv_q <> `'` AND lv_q <> `"` ) OR lv_s+lv_last_off(1) <> lv_q.
      RETURN.
    ENDIF.
    found = abap_true.

    lv_inner = substring( val = lv_s
                                off = 1
                                len = lv_len - 2 ).

    lv_i = 0.

    lv_ilen = strlen( lv_inner ).
    WHILE lv_i < lv_ilen.

      lv_c = lv_inner+lv_i(1).

      lv_i1 = lv_i + 1.
      IF lv_c = `\` AND lv_i1 < lv_ilen.

        lv_e = lv_inner+lv_i1(1).
        CASE lv_e.
          WHEN `n`.
            result = result && cl_abap_char_utilities=>newline.
          WHEN `r`.
            result = result && substring( val = cl_abap_char_utilities=>cr_lf
                                          len = 1 ).
          WHEN `t`.
            result = result && cl_abap_char_utilities=>horizontal_tab.
          WHEN `\` OR `'` OR `"`.
            result = result && lv_e.
          WHEN OTHERS.
            result = result && lv_c && lv_e.
        ENDCASE.
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      result = result && lv_c.
      lv_i = lv_i + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD number_normalize.

    DATA temp41 TYPE string.
    DATA lv_s LIKE temp41.
    DATA lv_sign TYPE string.
    DATA lv_int LIKE lv_s.
    DATA lv_frac TYPE string.
    DATA lv_dot TYPE i.
      DATA lv_last TYPE i.
    temp41 = val.

    lv_s = temp41.

    lv_sign = ``.
    IF strlen( lv_s ) > 0 AND lv_s(1) = `-`.
      lv_sign = `-`.
      lv_s = substring( val = lv_s
                        off = 1 ).
    ENDIF.

    lv_int = lv_s.

    lv_frac = ``.

    lv_dot = find( val = lv_s
                         sub = `.` ).
    IF lv_dot >= 0.
      lv_int = lv_s(lv_dot).
      lv_frac = substring( val = lv_s
                           off = lv_dot + 1 ).
    ENDIF.
    WHILE strlen( lv_int ) > 1 AND lv_int(1) = `0`.
      lv_int = substring( val = lv_int
                          off = 1 ).
    ENDWHILE.
    IF lv_int IS INITIAL.
      lv_int = `0`.
    ENDIF.
    WHILE strlen( lv_frac ) > 0.

      lv_last = strlen( lv_frac ) - 1.
      IF lv_frac+lv_last(1) <> `0`.
        EXIT.
      ENDIF.
      lv_frac = lv_frac(lv_last).
    ENDWHILE.
    result = lv_int.
    IF lv_frac IS NOT INITIAL.
      result = |{ result }.{ lv_frac }|.
    ENDIF.
    IF result <> `0`.
      result = lv_sign && result.
    ENDIF.

  ENDMETHOD.

  METHOD describe_arg.

    DATA lv_found TYPE abap_bool.

    DATA lv_s TYPE string.
    DATA lv_str TYPE string.
    DATA lv_num LIKE lv_s.
    DATA lv_dot TYPE i.
    DATA temp42 TYPE string.
    DATA lv_int LIKE temp42.
    DATA temp43 TYPE string.
    DATA lv_frac LIKE temp43.
      DATA temp10 TYPE xsdboolean.
    DATA lv_len TYPE i.
      DATA lv_last TYPE i.
      DATA lv_body TYPE string.
          DATA lv_prop TYPE string.
          DATA lv_ppath TYPE string.
    lv_s = trim( val ).

    lv_str = js_string( EXPORTING val   = lv_s
                              IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result-static = abap_true.
      result-val = val_string( lv_str ).
      RETURN.
    ENDIF.

    " -?[0-9]+(\.[0-9]+)?

    lv_num = lv_s.
    IF strlen( lv_num ) > 0 AND lv_num(1) = `-`.
      lv_num = substring( val = lv_num
                          off = 1 ).
    ENDIF.

    lv_dot = find( val = lv_num
                         sub = `.` ).

    IF lv_dot < 0.
      temp42 = lv_num.
    ELSE.
      temp42 = lv_num(lv_dot).
    ENDIF.

    lv_int = temp42.

    IF lv_dot >= 0.
      temp43 = substring( val = lv_num off = lv_dot + 1 ).
    ELSE.
      CLEAR temp43.
    ENDIF.

    lv_frac = temp43.
    IF lv_int IS NOT INITIAL AND lv_int CO c_digit
        AND ( lv_dot < 0 OR ( lv_frac IS NOT INITIAL AND lv_frac CO c_digit ) ).
      result-static = abap_true.
      result-val = val_number( number_normalize( lv_s ) ).
      RETURN.
    ENDIF.

    IF lv_s = `true` OR lv_s = `false`.
      result-static = abap_true.

      temp10 = boolc( lv_s = `true` ).
      result-val = val_boolean( temp10 ).
      RETURN.
    ENDIF.

    " ${...}: a reference the client resolves

    lv_len = strlen( lv_s ).
    IF lv_len >= 3 AND lv_s(2) = `${`.

      lv_last = lv_len - 1.

      lv_body = substring( val = lv_s
                                 off = 2
                                 len = lv_len - 3 ).
      IF lv_s+lv_last(1) = `}` AND lv_body NA `{}`.
        lv_body = trim( lv_body ).
        IF strlen( lv_body ) > 8 AND lv_body(8) = `$source>`.

          lv_prop = substring( val = lv_body
                                     off = 8 ).
          IF strlen( lv_prop ) > 0 AND lv_prop(1) = `/`.
            lv_prop = substring( val = lv_prop
                                 off = 1 ).
          ENDIF.
          IF lv_prop IS NOT INITIAL.
            result-kind = `source`.
            result-prop = lv_prop.
            result-describe = |$source:{ lv_prop }|.
            RETURN.
          ENDIF.
        ENDIF.
        IF strlen( lv_body ) >= 12 AND lv_body(12) = `$parameters>`.

          lv_ppath = substring( val = lv_body
                                      off = 12 ).
          IF strlen( lv_ppath ) > 0 AND lv_ppath(1) = `/`.
            lv_ppath = substring( val = lv_ppath
                                  off = 1 ).
          ENDIF.
          result-kind = `parameters`.
          result-path = lv_ppath.
          result-describe = |$parameters:{ lv_ppath }|.
          RETURN.
        ENDIF.
        IF strlen( lv_body ) > 0 AND lv_body(1) = `/` AND lv_body CO c_path_chars.
          result-kind = `model`.
          result-path = lv_body.
          result-describe = |$model:{ lv_body }|.
          RETURN.
        ENDIF.
        IF strlen( lv_body ) > 0 AND lv_body(1) CO c_alpha AND lv_body CO c_path_chars.
          result-kind = `row`.
          result-path = lv_body.
          result-describe = |$row:{ lv_body }|.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lv_s = `$event`.
      result-kind = `event`.
      result-describe = `$event`.
      RETURN.
    ENDIF.

    result-kind = `expr`.
    result-raw = lv_s.
    result-describe = |$expr:{ lv_s }|.

  ENDMETHOD.

  METHOD has_wire.

    " /\.(eB|eBP|eF)\s*\(/
    DATA temp44 TYPE string.
    DATA lv_s LIKE temp44.
    DATA lv_off TYPE i.
      DATA lv_hit TYPE i.
      DATA lv_pos TYPE i.
      DATA lv_c TYPE string.
    temp44 = val.

    lv_s = temp44.

    lv_off = 0.
    DO.

      lv_hit = find( val = lv_s
                           sub = `.e`
                           off = lv_off ).
      IF lv_hit < 0.
        RETURN.
      ENDIF.
      lv_off = lv_hit + 1.

      lv_pos = lv_hit + 2.
      IF lv_pos >= strlen( lv_s ).
        RETURN.
      ENDIF.

      lv_c = lv_s+lv_pos(1).
      IF lv_c <> `B` AND lv_c <> `F`.
        CONTINUE.
      ENDIF.
      lv_pos = lv_pos + 1.
      IF lv_c = `B` AND lv_pos < strlen( lv_s ) AND lv_s+lv_pos(1) = `P`.
        lv_pos = lv_pos + 1.
      ENDIF.
      WHILE lv_pos < strlen( lv_s ) AND is_ws( substring( val = lv_s off = lv_pos len = 1 ) ) = abap_true.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      IF lv_pos < strlen( lv_s ) AND lv_s+lv_pos(1) = `(`.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD parse_wire.

    DATA lv_found TYPE abap_bool.
    DATA lv_fn TYPE string.

    " ^\.?(eB|eBP|eF)\s*\(([\s\S]*)\)\s*;?\s*$
    DATA lv_s TYPE string.
    DATA lv_pos TYPE i.
    DATA lv_tail TYPE string.
    DATA lv_tlen TYPE i.
      DATA lv_tlast TYPE i.
    DATA lv_body TYPE string.
    DATA lt_args TYPE string_table.
      DATA temp45 TYPE string.
      DATA temp46 TYPE string.
      DATA lv_first LIKE temp45.
      DATA lv_action TYPE string.
      DATA lv_arg LIKE LINE OF lt_args.
    DATA temp47 TYPE string.
    DATA temp48 TYPE string.
    DATA lv_head LIKE temp47.
    DATA lv_hlen TYPE i.
    DATA lv_hlast TYPE i.
    DATA lt_inner TYPE string_table.
    DATA temp49 TYPE string.
    DATA temp50 TYPE string.
    DATA lv_event_raw LIKE temp49.
    DATA lv_event TYPE string.
    DATA lv_flag LIKE LINE OF lt_inner.
    lv_s = trim( val ).
    IF strlen( lv_s ) > 0 AND lv_s(1) = `.`.
      lv_s = substring( val = lv_s
                        off = 1 ).
    ENDIF.
    IF strlen( lv_s ) >= 3 AND lv_s(3) = `eBP`.
      lv_fn = `eBP`.
    ELSEIF strlen( lv_s ) >= 2 AND ( lv_s(2) = `eB` OR lv_s(2) = `eF` ).
      lv_fn = lv_s(2).
    ELSE.
      RETURN.
    ENDIF.

    lv_pos = strlen( lv_fn ).
    WHILE lv_pos < strlen( lv_s ) AND is_ws( substring( val = lv_s off = lv_pos len = 1 ) ) = abap_true.
      lv_pos = lv_pos + 1.
    ENDWHILE.
    IF lv_pos >= strlen( lv_s ) OR lv_s+lv_pos(1) <> `(`.
      RETURN.
    ENDIF.
    " the body runs to the last ')' behind which only blanks and one ';' follow

    lv_tail = trim( lv_s ).

    lv_tlen = strlen( lv_tail ).
    IF lv_tlen > 0.

      lv_tlast = lv_tlen - 1.
      IF lv_tail+lv_tlast(1) = `;`.
        lv_tail = trim( substring( val = lv_tail len = lv_tlast ) ).
      ENDIF.
    ENDIF.
    lv_tlen = strlen( lv_tail ).
    IF lv_tlen = 0.
      RETURN.
    ENDIF.
    lv_tlast = lv_tlen - 1.
    IF lv_tail+lv_tlast(1) <> `)` OR lv_tlast <= lv_pos.
      RETURN.
    ENDIF.

    lv_body = substring( val = lv_tail
                               off = lv_pos + 1
                               len = lv_tlast - lv_pos - 1 ).

    lt_args = split_args( lv_body ).

    IF lv_fn = `eF`.

      CLEAR temp45.

      READ TABLE lt_args INTO temp46 INDEX 1.
      IF sy-subrc = 0.
        temp45 = temp46.
      ENDIF.

      lv_first = temp45.

      lv_action = js_string( EXPORTING val   = lv_first
                                   IMPORTING found = lv_found ).
      IF lv_found = abap_false.
        RETURN.
      ENDIF.
      result-valid = abap_true.
      result-fn = `eF`.
      result-action = lv_action.

      LOOP AT lt_args INTO lv_arg FROM 2.
        INSERT describe_arg( lv_arg ) INTO TABLE result-t_arg.
      ENDLOOP.
      RETURN.
    ENDIF.

    IF lv_fn = `eBP`.
      DO 2 TIMES.
        IF lt_args IS NOT INITIAL.
          DELETE lt_args INDEX 1.
        ENDIF.
      ENDDO.
    ENDIF.

    CLEAR temp47.

    READ TABLE lt_args INTO temp48 INDEX 1.
    IF sy-subrc = 0.
      temp47 = temp48.
    ENDIF.

    lv_head = temp47.

    lv_hlen = strlen( lv_head ).
    IF lv_hlen < 2 OR lv_head(1) <> `[`.
      RETURN.
    ENDIF.

    lv_hlast = lv_hlen - 1.
    IF lv_head+lv_hlast(1) <> `]`.
      RETURN.
    ENDIF.

    lt_inner = split_args( substring( val = lv_head
                                            off = 1
                                            len = lv_hlen - 2 ) ).

    CLEAR temp49.

    READ TABLE lt_inner INTO temp50 INDEX 1.
    IF sy-subrc = 0.
      temp49 = temp50.
    ENDIF.

    lv_event_raw = temp49.

    lv_event = js_string( EXPORTING val   = lv_event_raw
                                IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    result-valid = abap_true.
    result-fn = `eB`.
    result-event = lv_event.

    LOOP AT lt_inner INTO lv_flag FROM 2.
      INSERT lv_flag INTO TABLE result-t_flag.
    ENDLOOP.
    LOOP AT lt_args INTO lv_arg FROM 2.
      INSERT describe_arg( lv_arg ) INTO TABLE result-t_arg.
    ENDLOOP.

  ENDMETHOD.

  METHOD val_string.

    result-kind = cs_kind-string.
    result-str = val.

  ENDMETHOD.

  METHOD val_number.

    result-kind = cs_kind-number.
    result-str = val.
    TRY.
        result-num = val.
      CATCH cx_root.
        result-nan = abap_true.
    ENDTRY.

  ENDMETHOD.

  METHOD val_boolean.
    DATA temp51 TYPE z2ui5_cl_agent_viewxml=>ty_s_val-str.

    result-kind = cs_kind-boolean.

    IF val = abap_true.
      temp51 = `true`.
    ELSE.
      temp51 = `false`.
    ENDIF.
    result-str = temp51.

  ENDMETHOD.

  METHOD val_nan.

    result-kind = cs_kind-number.
    result-str = `NaN`.
    result-nan = abap_true.

  ENDMETHOD.

  METHOD val_from_num.

    result-kind = cs_kind-number.
    result-num = num.
    result-str = number_normalize( condense( |{ num STYLE = SIMPLE }| ) ).

  ENDMETHOD.

  METHOD val_truthy.
        DATA temp11 TYPE xsdboolean.
        DATA temp12 TYPE xsdboolean.
        DATA temp13 TYPE xsdboolean.

    CASE val-kind.
      WHEN cs_kind-boolean.

        temp11 = boolc( val-str = `true` ).
        result = temp11.
      WHEN cs_kind-number.

        temp12 = boolc( val-nan = abap_false AND val-num <> 0 ).
        result = temp12.
      WHEN cs_kind-string.

        temp13 = boolc( val-str IS NOT INITIAL ).
        result = temp13.
      WHEN cs_kind-object OR cs_kind-array.
        result = abap_true.
      WHEN OTHERS.
        result = abap_false.
    ENDCASE.

  ENDMETHOD.

  METHOD val_to_string.

    CASE val-kind.
      WHEN cs_kind-string OR cs_kind-boolean OR cs_kind-number.
        result = val-str.
      WHEN cs_kind-null.
        result = `null`.
      WHEN cs_kind-object.
        result = `[object Object]`.
      WHEN cs_kind-array.
        result = val-json.
        IF strlen( result ) >= 2.
          result = substring( val = result
                              off = 1
                              len = strlen( result ) - 2 ).
        ENDIF.
        REPLACE ALL OCCURRENCES OF `"` IN result WITH ``.
      WHEN OTHERS.
        result = `undefined`.
    ENDCASE.

  ENDMETHOD.

  METHOD json_string.
          DATA temp52 TYPE xstring.
      DATA lv_off TYPE i.
          DATA temp53 TYPE xstring.

    " escaped as JSON.stringify escapes: the backslash first, then the quote
    " and the control characters a view or a model actually carries
    result = val.
    REPLACE ALL OCCURRENCES OF `\` IN result WITH `\\`.
    REPLACE ALL OCCURRENCES OF `"` IN result WITH `\"`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN result WITH `\n`.
    REPLACE ALL OCCURRENCES OF substring( val = cl_abap_char_utilities=>cr_lf
                                          len = 1 ) IN result WITH `\r`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN result WITH `\t`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN result WITH `\f`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>backspace IN result WITH `\b`.
    " every other control character as \u00xx - unescaped it makes the
    " whole document invalid JSON (a vertical tab of a long text)
    IF gv_json_controls_set = abap_false.
      TRY.

          temp52 = c_json_control_hex.
          gv_json_controls = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp52 ).
        CATCH cx_root.
          CLEAR gv_json_controls.
      ENDTRY.
      gv_json_controls_set = abap_true.
    ENDIF.
    IF gv_json_controls IS NOT INITIAL AND result CA gv_json_controls.

      lv_off = 0.
      WHILE lv_off < strlen( gv_json_controls ).
        REPLACE ALL OCCURRENCES OF gv_json_controls+lv_off(1) IN result
                WITH |\\u00{ to_lower( substring( val = c_json_control_hex
                                                  off = lv_off * 2
                                                  len = 2 ) ) }|.
        lv_off = lv_off + 1.
      ENDWHILE.
    ENDIF.
    " NUL (U+0000) on its own: a character a string may hold that not every
    " platform converts - built apart, so a failure here leaves the
    " escaping above as it was. Raw in a body, it made it invalid JSON.
    IF gv_json_nul_set = abap_false.
      TRY.

          temp53 = `00`.
          gv_json_nul = z2ui5_cl_ui5_util_context=>conv_get_string_by_xstring( temp53 ).
        CATCH cx_root.
          CLEAR gv_json_nul.
      ENDTRY.
      IF strlen( gv_json_nul ) <> 1.
        CLEAR gv_json_nul.
      ENDIF.
      gv_json_nul_set = abap_true.
    ENDIF.
    IF gv_json_nul IS NOT INITIAL AND find( val = result
                                            sub = gv_json_nul ) >= 0.
      REPLACE ALL OCCURRENCES OF gv_json_nul IN result WITH `\u0000`.
    ENDIF.
    result = `"` && result && `"`.

  ENDMETHOD.

  METHOD val_to_json.
        DATA temp54 TYPE string.

    CASE val-kind.
      WHEN cs_kind-string.
        result = json_string( val-str ).
      WHEN cs_kind-boolean.
        result = val-str.
      WHEN cs_kind-number.

        IF val-nan = abap_true.
          temp54 = `null`.
        ELSE.
          temp54 = val-str.
        ENDIF.
        result = temp54.
      WHEN cs_kind-object OR cs_kind-array.
        result = val-json.
      WHEN OTHERS.
        result = `null`.
    ENDCASE.

  ENDMETHOD.

  METHOD val_to_number.
        DATA lv_t TYPE string.
        DATA lv_arg TYPE z2ui5_cl_agent_viewxml=>ty_s_arg.

    CASE val-kind.
      WHEN cs_kind-number.
        result = val.
      WHEN cs_kind-boolean.
        IF val-str = `true`.
          result = val_from_num( 1 ).
        ELSE.
          result = val_from_num( 0 ).
        ENDIF.
      WHEN cs_kind-null.
        result = val_from_num( 0 ).
      WHEN cs_kind-string.

        lv_t = trim( val-str ).
        IF lv_t IS INITIAL.
          result = val_from_num( 0 ).
          RETURN.
        ENDIF.

        lv_arg = describe_arg( lv_t ).
        IF lv_arg-static = abap_true AND lv_arg-val-kind = cs_kind-number.
          result = lv_arg-val.
        ELSE.
          result = val_nan( ).
        ENDIF.
      WHEN OTHERS.
        result = val_nan( ).
    ENDCASE.

  ENDMETHOD.

  METHOD val_strict_equal.
      DATA temp14 TYPE xsdboolean.
        DATA temp15 TYPE xsdboolean.
        DATA temp16 TYPE xsdboolean.

    IF a-kind <> b-kind.
      " an initial kind is undefined as well

      temp14 = boolc( ( a-kind = cs_kind-undefined OR a-kind IS INITIAL ) AND ( b-kind = cs_kind-undefined OR b-kind IS INITIAL ) ).
      result = temp14.
      RETURN.
    ENDIF.
    CASE a-kind.
      WHEN cs_kind-number.

        temp15 = boolc( a-nan = abap_false AND b-nan = abap_false AND a-num = b-num ).
        result = temp15.
      WHEN cs_kind-string OR cs_kind-boolean.

        temp16 = boolc( a-str = b-str ).
        result = temp16.
      WHEN cs_kind-object OR cs_kind-array.
        result = abap_false.
      WHEN OTHERS.
        result = abap_true.
    ENDCASE.

  ENDMETHOD.

  METHOD val_loose_equal.

    DATA lv_a_nullish TYPE abap_bool.
    DATA temp17 TYPE xsdboolean.
    DATA lv_b_nullish TYPE abap_bool.
    DATA temp18 TYPE xsdboolean.
      DATA temp19 TYPE xsdboolean.
    temp17 = boolc( a-kind = cs_kind-null OR a-kind = cs_kind-undefined OR a-kind IS INITIAL ).
    lv_a_nullish = temp17.


    temp18 = boolc( b-kind = cs_kind-null OR b-kind = cs_kind-undefined OR b-kind IS INITIAL ).
    lv_b_nullish = temp18.
    IF lv_a_nullish = abap_true OR lv_b_nullish = abap_true.

      temp19 = boolc( lv_a_nullish = abap_true AND lv_b_nullish = abap_true ).
      result = temp19.
      RETURN.
    ENDIF.
    IF a-kind = b-kind.
      result = val_strict_equal( a = a
                                 b = b ).
      RETURN.
    ENDIF.
    IF a-kind = cs_kind-object OR a-kind = cs_kind-array OR b-kind = cs_kind-object OR b-kind = cs_kind-array.
      result = abap_false.
      RETURN.
    ENDIF.
    result = val_strict_equal( a = val_to_number( a )
                               b = val_to_number( b ) ).

  ENDMETHOD.

  METHOD apply_op.
        DATA temp55 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
        DATA temp56 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
        DATA temp20 TYPE xsdboolean.
        DATA temp21 TYPE xsdboolean.
              DATA temp22 TYPE xsdboolean.
              DATA temp23 TYPE xsdboolean.
              DATA temp24 TYPE xsdboolean.
              DATA temp25 TYPE xsdboolean.
        DATA ls_na TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
        DATA ls_nb TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
            DATA temp26 TYPE xsdboolean.
            DATA temp27 TYPE xsdboolean.
            DATA temp28 TYPE xsdboolean.
            DATA temp29 TYPE xsdboolean.

    CASE op.
      WHEN `||`.

        IF val_truthy( a ) = abap_true.
          temp55 = a.
        ELSE.
          temp55 = b.
        ENDIF.
        result = temp55.
      WHEN `&&`.

        IF val_truthy( a ) = abap_false.
          temp56 = a.
        ELSE.
          temp56 = b.
        ENDIF.
        result = temp56.
      WHEN `===`.
        result = val_boolean( val_strict_equal( a = a
                                                b = b ) ).
      WHEN `!==`.

        temp20 = boolc( val_strict_equal( a = a b = b ) = abap_false ).
        result = val_boolean( temp20 ).
      WHEN `==`.
        result = val_boolean( val_loose_equal( a = a
                                               b = b ) ).
      WHEN `!=`.

        temp21 = boolc( val_loose_equal( a = a b = b ) = abap_false ).
        result = val_boolean( temp21 ).
      WHEN `<` OR `>` OR `<=` OR `>=`.
        IF a-kind = cs_kind-string AND b-kind = cs_kind-string.
          CASE op.
            WHEN `<`.

              temp22 = boolc( a-str < b-str ).
              result = val_boolean( temp22 ).
            WHEN `>`.

              temp23 = boolc( a-str > b-str ).
              result = val_boolean( temp23 ).
            WHEN `<=`.

              temp24 = boolc( a-str <= b-str ).
              result = val_boolean( temp24 ).
            WHEN OTHERS.

              temp25 = boolc( a-str >= b-str ).
              result = val_boolean( temp25 ).
          ENDCASE.
          RETURN.
        ENDIF.

        ls_na = val_to_number( a ).

        ls_nb = val_to_number( b ).
        IF ls_na-nan = abap_true OR ls_nb-nan = abap_true.
          result = val_boolean( abap_false ).
          RETURN.
        ENDIF.
        CASE op.
          WHEN `<`.

            temp26 = boolc( ls_na-num < ls_nb-num ).
            result = val_boolean( temp26 ).
          WHEN `>`.

            temp27 = boolc( ls_na-num > ls_nb-num ).
            result = val_boolean( temp27 ).
          WHEN `<=`.

            temp28 = boolc( ls_na-num <= ls_nb-num ).
            result = val_boolean( temp28 ).
          WHEN OTHERS.

            temp29 = boolc( ls_na-num >= ls_nb-num ).
            result = val_boolean( temp29 ).
        ENDCASE.
      WHEN `+`.
        IF a-kind = cs_kind-string OR b-kind = cs_kind-string
            OR a-kind = cs_kind-object OR b-kind = cs_kind-object
            OR a-kind = cs_kind-array OR b-kind = cs_kind-array.
          result = val_string( val_to_string( a ) && val_to_string( b ) ).
          RETURN.
        ENDIF.
        ls_na = val_to_number( a ).
        ls_nb = val_to_number( b ).
        IF ls_na-nan = abap_true OR ls_nb-nan = abap_true.
          result = val_nan( ).
        ELSE.
          result = val_from_num( ls_na-num + ls_nb-num ).
        ENDIF.
      WHEN `-` OR `*` OR `/` OR `%`.
        ls_na = val_to_number( a ).
        ls_nb = val_to_number( b ).
        IF ls_na-nan = abap_true OR ls_nb-nan = abap_true.
          result = val_nan( ).
          RETURN.
        ENDIF.
        TRY.
            CASE op.
              WHEN `-`.
                result = val_from_num( ls_na-num - ls_nb-num ).
              WHEN `*`.
                result = val_from_num( ls_na-num * ls_nb-num ).
              WHEN `/`.
                result = val_from_num( ls_na-num / ls_nb-num ).
              WHEN OTHERS.
                result = val_from_num( ls_na-num - ls_nb-num * trunc( ls_na-num / ls_nb-num ) ).
            ENDCASE.
          CATCH cx_root.
            result = val_nan( ).
        ENDTRY.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
          EXPORTING
            val = |operator { op }|.
    ENDCASE.

  ENDMETHOD.

  METHOD tokenize.

    DATA lv_v TYPE string.
    DATA lv_found TYPE abap_bool.
    DATA lv_len TYPE i.
    DATA lv_i TYPE i.
      DATA lv_c TYPE string.
      DATA lv_i1 TYPE i.
      DATA temp57 TYPE string.
      DATA lv_next LIKE temp57.
      DATA temp58 TYPE string.
      DATA lv_two LIKE temp58.
      DATA temp59 TYPE string.
      DATA lv_three LIKE temp59.
        DATA lv_end TYPE i.
        DATA lv_body TYPE string.
          DATA lv_path TYPE string.
        DATA temp60 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA lv_j TYPE i.
            DATA lv_j1 TYPE i.
        DATA temp61 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp62 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp63 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp64 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp65 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp66 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA temp67 TYPE z2ui5_cl_agent_viewxml=>ty_s_token.

    failed = abap_false.

    lv_len = strlen( val ).

    lv_i = 0.
    WHILE lv_i < lv_len.

      lv_c = val+lv_i(1).

      lv_i1 = lv_i + 1.

      IF lv_i1 < lv_len.
        temp57 = val+lv_i1(1).
      ELSE.
        CLEAR temp57.
      ENDIF.

      lv_next = temp57.

      IF lv_i + 2 <= lv_len.
        temp58 = val+lv_i(2).
      ELSE.
        CLEAR temp58.
      ENDIF.

      lv_two = temp58.

      IF lv_i + 3 <= lv_len.
        temp59 = val+lv_i(3).
      ELSE.
        CLEAR temp59.
      ENDIF.

      lv_three = temp59.

      IF is_ws( lv_c ) = abap_true.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.

      IF lv_c = `$` AND lv_next = `{`.

        lv_end = find( val = val
                             sub = `}`
                             off = lv_i ).
        IF lv_end < 0.
          failed = abap_true.
          RETURN.
        ENDIF.

        lv_body = trim( substring( val = val
                                         off = lv_i + 2
                                         len = lv_end - lv_i - 2 ) ).
        " object syntax inside an expression: ${path: '/X', ...}
        IF strlen( lv_body ) >= 4 AND lv_body(4) = `path`.

          lv_path = key_quoted_value( EXPORTING body  = lv_body
                                                      key   = `path`
                                            IMPORTING found = lv_found ).
          IF lv_found = abap_true AND key_position( body = lv_body
                                                    key  = `path` ) <= 6.
            lv_body = lv_path.
          ENDIF.
        ENDIF.

        CLEAR temp60.
        temp60-type = `ref`.
        temp60-value = lv_body.
        INSERT temp60 INTO TABLE result.
        lv_i = lv_end + 1.
        CONTINUE.
      ENDIF.

      IF lv_c = `"` OR lv_c = `'`.

        lv_j = lv_i + 1.
        CLEAR lv_v.
        WHILE lv_j < lv_len AND val+lv_j(1) <> lv_c.
          IF val+lv_j(1) = `\`.

            lv_j1 = lv_j + 1.
            IF lv_j1 < lv_len.
              lv_v = lv_v && val+lv_j1(1).
            ENDIF.
            lv_j = lv_j + 2.
            CONTINUE.
          ENDIF.
          lv_v = lv_v && val+lv_j(1).
          lv_j = lv_j + 1.
        ENDWHILE.
        IF lv_j >= lv_len.
          failed = abap_true.
          RETURN.
        ENDIF.

        CLEAR temp61.
        temp61-type = `str`.
        temp61-value = lv_v.
        INSERT temp61 INTO TABLE result.
        lv_i = lv_j + 1.
        CONTINUE.
      ENDIF.

      IF lv_c CO c_digit.
        lv_j = lv_i.
        WHILE lv_j < lv_len AND val+lv_j(1) CO c_digit.
          lv_j = lv_j + 1.
        ENDWHILE.
        lv_j1 = lv_j + 1.
        IF lv_j < lv_len AND val+lv_j(1) = `.` AND lv_j1 < lv_len AND val+lv_j1(1) CO c_digit.
          lv_j = lv_j1.
          WHILE lv_j < lv_len AND val+lv_j(1) CO c_digit.
            lv_j = lv_j + 1.
          ENDWHILE.
        ENDIF.

        CLEAR temp62.
        temp62-type = `num`.
        temp62-value = substring( val = val off = lv_i len = lv_j - lv_i ).
        INSERT temp62 INTO TABLE result.
        lv_i = lv_j.
        CONTINUE.
      ENDIF.

      IF lv_c CO c_alpha.
        lv_j = lv_i.
        WHILE lv_j < lv_len AND val+lv_j(1) CO c_word.
          lv_j = lv_j + 1.
        ENDWHILE.

        CLEAR temp63.
        temp63-type = `word`.
        temp63-value = substring( val = val off = lv_i len = lv_j - lv_i ).
        INSERT temp63 INTO TABLE result.
        lv_i = lv_j.
        CONTINUE.
      ENDIF.

      IF lv_three = `===` OR lv_three = `!==`.

        CLEAR temp64.
        temp64-type = `op`.
        temp64-value = lv_three.
        INSERT temp64 INTO TABLE result.
        lv_i = lv_i + 3.
        CONTINUE.
      ENDIF.
      IF lv_two = `==` OR lv_two = `!=` OR lv_two = `<=` OR lv_two = `>=` OR lv_two = `&&` OR lv_two = `||`.

        CLEAR temp65.
        temp65-type = `op`.
        temp65-value = lv_two.
        INSERT temp65 INTO TABLE result.
        lv_i = lv_i + 2.
        CONTINUE.
      ENDIF.
      IF lv_c CA `<>+-*/%`.

        CLEAR temp66.
        temp66-type = `op`.
        temp66-value = lv_c.
        INSERT temp66 INTO TABLE result.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      IF lv_c CA `!?:().`.

        CLEAR temp67.
        temp67-type = `punct`.
        temp67-value = lv_c.
        INSERT temp67 INTO TABLE result.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      failed = abap_true.
      RETURN.
    ENDWHILE.

  ENDMETHOD.

  METHOD expression_refs.

    DATA lv_failed TYPE abap_bool.

    DATA temp68 TYPE string.
    DATA lt_token TYPE z2ui5_cl_agent_viewxml=>ty_t_token.
    DATA ls_token LIKE LINE OF lt_token.
    temp68 = val.

    lt_token = tokenize( EXPORTING val    = temp68
                               IMPORTING failed = lv_failed ).
    IF lv_failed = abap_true.
      RETURN.
    ENDIF.

    LOOP AT lt_token INTO ls_token WHERE type = `ref`. "#EC CI_SORTSEQ
      INSERT ls_token-value INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD eval_expression.

    DATA lv_failed TYPE abap_bool.
    DATA lo_eval TYPE REF TO z2ui5_cl_agent_viewxml.
    DATA temp69 TYPE string.
        DATA ls_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    result-kind = cs_kind-undefined.

    CREATE OBJECT lo_eval TYPE z2ui5_cl_agent_viewxml.

    temp69 = val.
    lo_eval->mt_token = tokenize( EXPORTING val    = temp69
                                  IMPORTING failed = lv_failed ).
    IF lv_failed = abap_true.
      RETURN.
    ENDIF.
    lo_eval->mt_ref = t_ref.
    TRY.

        ls_val = lo_eval->parse_ternary( ).
        IF lo_eval->mv_pos = lines( lo_eval->mt_token ).
          result = ls_val.
        ENDIF.
      CATCH cx_root.
        result-kind = cs_kind-undefined.
    ENDTRY.

  ENDMETHOD.

  METHOD peek.

    DATA lv_index TYPE i.
    lv_index = mv_pos + 1.
    READ TABLE mt_token INDEX lv_index INTO result.
    IF sy-subrc <> 0.
      CLEAR result.
    ENDIF.

  ENDMETHOD.

  METHOD take.
    DATA temp30 TYPE xsdboolean.

    result = peek( ).

    temp30 = boolc( result-type IS NOT INITIAL ).
    found = temp30.
    IF found = abap_true.
      mv_pos = mv_pos + 1.
    ENDIF.

  ENDMETHOD.

  METHOD fail.

    RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
      EXPORTING
        val = `expression`.

  ENDMETHOD.

  METHOD parse_ternary.

    DATA lv_found TYPE abap_bool.

    DATA ls_cond TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    DATA ls_peek TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
      DATA ls_a TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
      DATA ls_colon TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
      DATA ls_b TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
      DATA temp70 TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    ls_cond = parse_binary( 0 ).

    ls_peek = peek( ).
    IF ls_peek-value = `?` AND ls_peek-type = `punct`.
      take( ).

      ls_a = parse_ternary( ).

      ls_colon = take( IMPORTING found = lv_found ).
      IF lv_found = abap_false OR ls_colon-value <> `:`.
        fail( ).
      ENDIF.

      ls_b = parse_ternary( ).

      IF val_truthy( ls_cond ) = abap_true.
        temp70 = ls_a.
      ELSE.
        temp70 = ls_b.
      ENDIF.
      result = temp70.
      RETURN.
    ENDIF.
    result = ls_cond.

  ENDMETHOD.

  METHOD parse_binary.

    DATA lt_ops TYPE string_table.
        DATA temp71 TYPE string_table.
        DATA temp73 TYPE string_table.
        DATA temp75 TYPE string_table.
        DATA temp77 TYPE string_table.
        DATA temp79 TYPE string_table.
        DATA temp81 TYPE string_table.
      DATA ls_peek TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
      DATA temp83 LIKE sy-subrc.
      DATA ls_right TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    IF level >= 6.
      result = parse_postfix( ).
      RETURN.
    ENDIF.
    CASE level.
      WHEN 0.

        CLEAR temp71.
        INSERT `||` INTO TABLE temp71.
        lt_ops = temp71.
      WHEN 1.

        CLEAR temp73.
        INSERT `&&` INTO TABLE temp73.
        lt_ops = temp73.
      WHEN 2.

        CLEAR temp75.
        INSERT `===` INTO TABLE temp75.
        INSERT `!==` INTO TABLE temp75.
        INSERT `==` INTO TABLE temp75.
        INSERT `!=` INTO TABLE temp75.
        lt_ops = temp75.
      WHEN 3.

        CLEAR temp77.
        INSERT `<` INTO TABLE temp77.
        INSERT `>` INTO TABLE temp77.
        INSERT `<=` INTO TABLE temp77.
        INSERT `>=` INTO TABLE temp77.
        lt_ops = temp77.
      WHEN 4.

        CLEAR temp79.
        INSERT `+` INTO TABLE temp79.
        INSERT `-` INTO TABLE temp79.
        lt_ops = temp79.
      WHEN OTHERS.

        CLEAR temp81.
        INSERT `*` INTO TABLE temp81.
        INSERT `/` INTO TABLE temp81.
        INSERT `%` INTO TABLE temp81.
        lt_ops = temp81.
    ENDCASE.

    result = parse_binary( level + 1 ).
    DO.

      ls_peek = peek( ).

      READ TABLE lt_ops WITH KEY table_line = ls_peek-value TRANSPORTING NO FIELDS.
      temp83 = sy-subrc.
      IF ls_peek-type <> `op` OR NOT temp83 = 0. "#EC CI_SORTSEQ
        EXIT.
      ENDIF.
      take( ).

      ls_right = parse_binary( level + 1 ).
      result = apply_op( op = ls_peek-value
                         a  = result
                         b  = ls_right ).
    ENDDO.

  ENDMETHOD.

  METHOD parse_postfix.

    DATA lv_found TYPE abap_bool.
      DATA ls_peek TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
      DATA ls_name TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
          DATA temp84 TYPE decfloat34.

    result = parse_primary( ).
    DO.

      ls_peek = peek( ).
      IF ls_peek-value <> `.` OR ls_peek-type <> `punct`.
        EXIT.
      ENDIF.
      take( ).

      ls_name = take( IMPORTING found = lv_found ).
      IF lv_found = abap_false OR ls_name-type <> `word` OR ls_name-value <> `length`.
        fail( ).
      ENDIF.
      CASE result-kind.
        WHEN cs_kind-string.

          temp84 = strlen( result-str ).
          result = val_from_num( temp84 ).
        WHEN cs_kind-array.
          result = val_from_num( result-num ).
        WHEN OTHERS.
          CLEAR result.
          result-kind = cs_kind-undefined.
      ENDCASE.
    ENDDO.

  ENDMETHOD.

  METHOD parse_primary.

    DATA lv_found TYPE abap_bool.

    DATA ls_token TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
        DATA ls_ref TYPE z2ui5_cl_agent_viewxml=>ty_s_ref_val.
            DATA ls_close TYPE z2ui5_cl_agent_viewxml=>ty_s_token.
            DATA temp31 TYPE xsdboolean.
            DATA ls_num TYPE z2ui5_cl_agent_viewxml=>ty_s_val.
    ls_token = take( IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      fail( ).
    ENDIF.
    CASE ls_token-type.
      WHEN `ref`.

        READ TABLE mt_ref INTO ls_ref WITH KEY ref = ls_token-value. "#EC CI_SORTSEQ
        IF sy-subrc = 0.
          result = ls_ref-val.
        ENDIF.
        IF result-kind IS INITIAL.
          result-kind = cs_kind-undefined.
        ENDIF.
      WHEN `str`.
        result = val_string( ls_token-value ).
      WHEN `num`.
        result = val_number( number_normalize( ls_token-value ) ).
      WHEN `word`.
        CASE ls_token-value.
          WHEN `true`.
            result = val_boolean( abap_true ).
          WHEN `false`.
            result = val_boolean( abap_false ).
          WHEN `null`.
            result-kind = cs_kind-null.
          WHEN `undefined`.
            result-kind = cs_kind-undefined.
          WHEN OTHERS.
            fail( ).
        ENDCASE.
      WHEN OTHERS.
        CASE ls_token-value.
          WHEN `(`.
            result = parse_ternary( ).

            ls_close = take( IMPORTING found = lv_found ).
            IF lv_found = abap_false OR ls_close-value <> `)`.
              fail( ).
            ENDIF.
          WHEN `!`.

            temp31 = boolc( val_truthy( parse_postfix( ) ) = abap_false ).
            result = val_boolean( temp31 ).
          WHEN `-`.

            ls_num = val_to_number( parse_postfix( ) ).
            IF ls_num-nan = abap_true.
              result = ls_num.
            ELSE.
              result = val_from_num( 0 - ls_num-num ).
            ENDIF.
          WHEN OTHERS.
            fail( ).
        ENDCASE.
    ENDCASE.

  ENDMETHOD.

ENDCLASS.
