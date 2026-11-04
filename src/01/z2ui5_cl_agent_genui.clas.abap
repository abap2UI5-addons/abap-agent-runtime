"! Generative UI: an abap2UI5 view from a sentence - safely.
"!
"! The app decides WHAT data the view shows; the language model decides
"! only HOW: it sees the field names, types and labels of the data the app
"! hands over (a few sample rows only when the setting genui_samples is
"! on), never writes ABAP, SQL or XML, and answers a UI tree as structured
"! output (a JSON schema) in a closed vocabulary - the controls,
"! properties, aggregations and events of the abap2UI5 protocol's portable
"! view profile v1 (z2ui5_cl_agent_gen_vocab, generated from it). This
"! class validates that tree and builds the XML itself with
"! z2ui5_cl_ui5_view_builder, so every text is escaped by the framework
"! (a brace stays a brace, markup stays text). Anything outside the
"! vocabulary is rejected with a readable reason; with the setting
"! genui_repair (default on) the reasons go back to the model once.
"!
"!   DATA(genui) = z2ui5_cl_agent_genui=&gt;create( client
"!       )-&gt;add_table( name = `flights` val = t_flight description = `Flights of the week`
"!       )-&gt;add_event( event = `ROW_SELECT` description = `the user picks a flight` t_arg = VALUE #( ( `CARRID` ) ( `CONNID` ) ) ).
"!   DATA(result) = genui-&gt;generate( `the open flights as a table grouped by carrier` ).
"!   IF result-ok = abap_true.
"!     client-&gt;popup_display( result-xml_popup ).
"!   ENDIF.
"!
"! What is validated (README, "Generative UI"): every control is in the
"! vocabulary (and none of the excluded ones - sap.ui.core.HTML, Shell,
"! Dialog, Popover, CustomData, layout data); every child sits in an
"! aggregation its parent has and is of the type it takes; every property
"! is one the control has at the UI5 1.71 floor, with a literal of its type
"! (enum values, booleans, numbers, CSS sizes, sap-icon:// URIs only) or a
"! binding to a field of the data handed over - relative inside the row
"! template of a list bound to a table, absolute to a structure, with the
"! formats integer and decimal and nothing else (no expressions, no
"! formatters); list bindings go to a table, sort and group by its fields,
"! hold exactly one template and do not nest; events are events of the
"! control, mapped to an event of the app's list, with arguments only from
"! the fields that event allows. Ids, custom data, frontend actions,
"! custom controls and HTML do not exist in the tree format at all.
CLASS z2ui5_cl_agent_genui DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.

    CONSTANTS c_max_nodes TYPE i VALUE 200.
    CONSTANTS c_samples TYPE i VALUE 3.

    TYPES:
      BEGIN OF ty_s_label,
        field TYPE string,
        label TYPE string,
      END OF ty_s_label.
    TYPES ty_t_label TYPE STANDARD TABLE OF ty_s_label WITH DEFAULT KEY.

    TYPES:
      "! type: string, number, date, time or boolean.
      BEGIN OF ty_s_field,
        name  TYPE string,
        type  TYPE string,
        label TYPE string,
      END OF ty_s_field.
    TYPES ty_t_field TYPE STANDARD TABLE OF ty_s_field WITH DEFAULT KEY.

    TYPES:
      "! path: the model path of the data (/T_FLIGHT). sample: JSON of a
      "! few rows - only sent with the setting genui_samples.
      BEGIN OF ty_s_dataset,
        name        TYPE string,
        path        TYPE string,
        is_table    TYPE abap_bool,
        description TYPE string,
        t_field     TYPE ty_t_field,
        sample      TYPE string,
      END OF ty_s_dataset.
    TYPES ty_t_dataset TYPE STANDARD TABLE OF ty_s_dataset WITH DEFAULT KEY.

    TYPES:
      "! An event of the app the view may fire. t_arg: the fields its
      "! arguments may name (of the row, inside a list's template, or of a
      "! structure) - empty: no arguments.
      BEGIN OF ty_s_event,
        event       TYPE string,
        description TYPE string,
        t_arg       TYPE string_table,
      END OF ty_s_event.
    TYPES ty_t_event TYPE STANDARD TABLE OF ty_s_event WITH DEFAULT KEY.

    TYPES:
      "! ok: xml is a valid view. xml: a sap.ui.core.mvc.View for
      "! view_display / nest_view_display; xml_popup: the same content in a
      "! Dialog for popup_display. t_issue: why the tree was rejected (the
      "! last round). t_note: the report - rounds, repairs, what was checked.
      "! json: the UI tree of the last round, as the model answered it.
      BEGIN OF ty_s_result,
        ok        TYPE abap_bool,
        title     TYPE string,
        xml       TYPE string,
        xml_popup TYPE string,
        t_issue   TYPE string_table,
        t_note    TYPE string_table,
        rounds    TYPE i,
        json      TYPE string,
      END OF ty_s_result.

    "! client: the client of the app's roundtrip - it binds the data and
    "! wires the events. app: the app class, for the audit log.
    CLASS-METHODS create
      IMPORTING
        client        TYPE REF TO z2ui5_if_client
        app           TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_genui.

    "! A table the view may show. val: the app's attribute itself (it is
    "! bound with client-&gt;_bind( ) - or pass bind, the result of a
    "! _bind( ) of your own). t_label: labels of fields (default the name).
    METHODS add_table
      IMPORTING
        name          TYPE clike
        val           TYPE ANY TABLE
        bind          TYPE clike OPTIONAL
        description   TYPE clike OPTIONAL
        t_label       TYPE ty_t_label OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_genui.

    "! A structure the view may show - as add_table( ).
    METHODS add_structure
      IMPORTING
        name          TYPE clike
        val           TYPE any
        bind          TYPE clike OPTIONAL
        description   TYPE clike OPTIONAL
        t_label       TYPE ty_t_label OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_genui.

    "! An event the view may fire - see ty_s_event.
    METHODS add_event
      IMPORTING
        event         TYPE clike
        description   TYPE clike OPTIONAL
        t_arg         TYPE string_table OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_genui.

    "! Ask the language model for a view, validate it (and repair it once).
    "! Never raises: a failed call is an issue of the result.
    "! close_event: the event of the Close button of xml_popup. commit: the
    "! audit entry of every model call is written in the app's LUW, and
    "! abap2UI5 rolls back what main( ) leaves uncommitted - so generate( )
    "! commits by default; pass abap_false when the LUW holds work of the
    "! app's own, and commit it yourself.
    METHODS generate
      IMPORTING
        request       TYPE clike
        close_event   TYPE clike DEFAULT `GENUI_CLOSE`
        commit        TYPE abap_bool DEFAULT abap_true
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! Validate a UI tree (the JSON of the schema) and build its XML - what
    "! generate( ) does with each answer; for a tree an app stored.
    METHODS render
      IMPORTING
        json          TYPE clike
        close_event   TYPE clike DEFAULT `GENUI_CLOSE`
      RETURNING
        VALUE(result) TYPE ty_s_result.

    "! The JSON schema of the UI tree, as sent to the model.
    METHODS get_schema
      RETURNING
        VALUE(result) TYPE string.

    "! The system prompt, as sent to the model.
    METHODS get_system
      RETURNING
        VALUE(result) TYPE string.

    "! The datasets handed over so far.
    METHODS get_datasets
      RETURNING
        VALUE(result) TYPE ty_t_dataset.

  PROTECTED SECTION.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_s_prop,
        name    TYPE string,
        value   TYPE string,
        field   TYPE string,
        dataset TYPE string,
        format  TYPE string,
      END OF ty_s_prop.
    TYPES ty_t_prop TYPE STANDARD TABLE OF ty_s_prop WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_evt,
        name  TYPE string,
        event TYPE string,
        t_arg TYPE string_table,
      END OF ty_s_evt.
    TYPES ty_t_evt TYPE STANDARD TABLE OF ty_s_evt WITH DEFAULT KEY.

    TYPES:
      "! agg: the aggregation in effect (the parent's default when empty);
      "! scope: the table dataset whose row the node is in (a list's template).
      BEGIN OF ty_s_node,
        id          TYPE string,
        parent      TYPE string,
        aggregation TYPE string,
        control     TYPE string,
        t_prop      TYPE ty_t_prop,
        list_data   TYPE string,
        list_agg    TYPE string,
        sort_by     TYPE string,
        descending  TYPE abap_bool,
        group_by    TYPE string,
        t_evt       TYPE ty_t_evt,
        agg         TYPE string,
        scope       TYPE string,
        reached     TYPE abap_bool,
      END OF ty_s_node.
    TYPES ty_t_node TYPE STANDARD TABLE OF ty_s_node WITH DEFAULT KEY.

    DATA mo_client TYPE REF TO z2ui5_if_client.
    DATA mv_app TYPE string.
    DATA mt_dataset TYPE ty_t_dataset.
    DATA mt_event TYPE ty_t_event.
    DATA mt_vocab TYPE z2ui5_cl_agent_gen_vocab=>ty_t_entry.
    "! The icon names of the font at the floor - read on the first icon.
    TYPES temp1_a49d67c54a TYPE SORTED TABLE OF string WITH NON-UNIQUE KEY table_line.
DATA mt_icon TYPE temp1_a49d67c54a.
    DATA mt_node TYPE ty_t_node.
    DATA mt_issue TYPE string_table.

    METHODS dataset_add
      IMPORTING
        name        TYPE clike
        val         TYPE any
        bind        TYPE clike
        description TYPE clike
        t_label     TYPE ty_t_label
        is_table    TYPE abap_bool.

    CLASS-METHODS fields_of
      IMPORTING
        val           TYPE any
        t_label       TYPE ty_t_label
      RETURNING
        VALUE(result) TYPE ty_t_field.

    METHODS issue
      IMPORTING
        node TYPE ty_s_node OPTIONAL
        text TYPE string.

    METHODS parse
      IMPORTING
        json TYPE string.

    METHODS validate.

    METHODS rounds
      IMPORTING
        request       TYPE clike
        close_event   TYPE clike
      RETURNING
        VALUE(result) TYPE ty_s_result.

    METHODS validate_node
      CHANGING
        node TYPE ty_s_node.

    METHODS validate_prop
      IMPORTING
        node TYPE ty_s_node
        prop TYPE ty_s_prop.

    METHODS validate_events
      IMPORTING
        node TYPE ty_s_node.

    METHODS check_literal
      IMPORTING
        type          TYPE string
        info          TYPE string
        value         TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS vocab
      IMPORTING
        control       TYPE string
        kind          TYPE string
        name          TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.

    METHODS check_excluded
      IMPORTING
        control       TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    METHODS field_of
      IMPORTING
        dataset       TYPE string
        field         TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The type of a field (ty_s_field-type) - empty when there is none.
    METHODS type_of
      IMPORTING
        dataset       TYPE string
        field         TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS build
      IMPORTING
        close_event   TYPE string
      EXPORTING
        xml           TYPE string
        xml_popup     TYPE string
        title         TYPE string.

    METHODS build_node
      IMPORTING
        parent TYPE REF TO z2ui5_cl_ui5_view_builder
        node   TYPE ty_s_node.

    METHODS binding_of
      IMPORTING
        node          TYPE ty_s_node
        prop          TYPE ty_s_prop
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS ns_of
      IMPORTING
        control       TYPE string
      EXPORTING
        prefix        TYPE string
        local         TYPE string.

    CLASS-METHODS enum_json
      IMPORTING
        t_value       TYPE string_table
      RETURNING
        VALUE(result) TYPE string.

    DATA mv_title TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_genui IMPLEMENTATION.

  METHOD create.

    CREATE OBJECT result.
    result->mo_client = client.
    result->mv_app = to_upper( app ).
    result->mt_vocab = z2ui5_cl_agent_gen_vocab=>get( ).

  ENDMETHOD.

  METHOD add_table.

    DATA temp34 TYPE string.
    IF bind IS NOT INITIAL.
      temp34 = bind.
    ELSE.
      temp34 = mo_client->_bind( val ).
    ENDIF.
    dataset_add( name        = name
                 val         = val
                 bind        = temp34
                 description = description
                 t_label     = t_label
                 is_table    = abap_true ).
    result = me.

  ENDMETHOD.

  METHOD add_structure.

    DATA temp35 TYPE string.
    IF bind IS NOT INITIAL.
      temp35 = bind.
    ELSE.
      temp35 = mo_client->_bind( val ).
    ENDIF.
    dataset_add( name        = name
                 val         = val
                 bind        = temp35
                 description = description
                 t_label     = t_label
                 is_table    = abap_false ).
    result = me.

  ENDMETHOD.

  METHOD add_event.

    DATA ls_event TYPE ty_s_event.
    DATA lv_arg LIKE LINE OF t_arg.
      DATA temp1 TYPE string.

    ls_event-event = to_upper( event ).
    ls_event-description = description.

    LOOP AT t_arg INTO lv_arg.

      temp1 = to_upper( lv_arg ).
      INSERT temp1 INTO TABLE ls_event-t_arg.
    ENDLOOP.
    INSERT ls_event INTO TABLE mt_event.
    result = me.

  ENDMETHOD.

  METHOD get_datasets.

    result = mt_dataset.

  ENDMETHOD.

  METHOD dataset_add.

    FIELD-SYMBOLS <table> TYPE ANY TABLE.
    FIELD-SYMBOLS <sample> TYPE ANY TABLE.
    DATA lr_sample TYPE REF TO data.

    DATA temp36 TYPE ty_s_dataset.
    DATA ls_dataset LIKE temp36.
            FIELD-SYMBOLS <row> TYPE ANY.
            DATA temp37 TYPE REF TO z2ui5_if_ajson.
            DATA lo_json LIKE temp37.
            DATA temp38 TYPE REF TO z2ui5_if_ajson.
          DATA temp39 TYPE string_table.
          DATA temp7 TYPE string_table.
          DATA lt_row LIKE temp7.
          DATA lv_row LIKE LINE OF lt_row.
            DATA temp41 TYPE string.
            DATA lv_base LIKE temp41.
            DATA temp42 TYPE i.
            DATA temp8 TYPE string.
            DATA lv_model LIKE temp8.
            DATA lt_member TYPE string_table.
            DATA lv_member LIKE LINE OF lt_member.
              DATA lv_name TYPE string.
              DATA temp43 LIKE sy-subrc.
    CLEAR temp36.
    temp36-name = to_lower( name ).
    temp36-path = bind.
    temp36-is_table = is_table.
    temp36-description = description.
    temp36-t_field = fields_of( val = val t_label = t_label ).

    ls_dataset = temp36.
    " the model path - {/T_FLIGHT} or /T_FLIGHT
    REPLACE ALL OCCURRENCES OF `{` IN ls_dataset-path WITH ``.
    REPLACE ALL OCCURRENCES OF `}` IN ls_dataset-path WITH ``.
    CONDENSE ls_dataset-path NO-GAPS.

    " a few rows - only when an administrator allows it (privacy)
    IF z2ui5_cl_agent_settings=>check_llm( z2ui5_cl_agent_settings=>cs_llm-genui_samples ) = abap_true.
      TRY.
          IF is_table = abap_true.
            ASSIGN val TO <table>.
            CREATE DATA lr_sample LIKE <table>.
            ASSIGN lr_sample->* TO <sample>.

            LOOP AT <table> ASSIGNING <row>.
              IF lines( <sample> ) >= c_samples.
                EXIT.
              ENDIF.
              INSERT <row> INTO TABLE <sample>.
            ENDLOOP.

            temp37 ?= z2ui5_cl_ajson=>create_empty( ).

            lo_json = temp37.
            lo_json->set( iv_path = `/`
                          iv_val  = <sample> ).
          ELSE.

            temp38 ?= z2ui5_cl_ajson=>create_empty( ).
            lo_json = temp38.
            lo_json->set( iv_path = `/`
                          iv_val  = val ).
          ENDIF.
          " only what the field list names, and a sensitive field masked:
          " whole rows carried the nested tables fields_of( ) leaves out,
          " and the IBAN the app marks sensitive went to the model as it was

          CLEAR temp39.
          INSERT `` INTO TABLE temp39.

          IF is_table = abap_true.
            temp7 = lo_json->members( `/` ).
          ELSE.
            temp7 = temp39.
          ENDIF.

          lt_row = temp7.

          LOOP AT lt_row INTO lv_row.

            IF is_table = abap_true.
              temp41 = |/{ lv_row }/|.
            ELSE.
              temp41 = `/`.
            ENDIF.

            lv_base = temp41.

            temp42 = lv_row.

            IF is_table = abap_true.
              temp8 = |{ ls_dataset-path }/{ temp42 - 1 }/|.
            ELSE.
              temp8 = |{ ls_dataset-path }/|.
            ENDIF.

            lv_model = temp8.

            lt_member = lo_json->members( lv_base ).

            LOOP AT lt_member INTO lv_member.

              lv_name = to_upper( lv_member ).

              READ TABLE ls_dataset-t_field WITH KEY name = lv_name TRANSPORTING NO FIELDS.
              temp43 = sy-subrc.
              IF NOT temp43 = 0. "#EC CI_SORTSEQ
                lo_json->delete( |{ lv_base }{ lv_member }| ).
              ELSEIF z2ui5_cl_agent_settings=>check_sensitive( app  = mv_app
                                                               path = |{ lv_model }{ lv_name }|
                                                               name = lv_name ) = abap_true.
                lo_json->set_string( iv_path = |{ lv_base }{ lv_member }|
                                     iv_val  = z2ui5_cl_agent_audit=>c_mask ).
              ENDIF.
            ENDLOOP.
          ENDLOOP.
          ls_dataset-sample = lo_json->stringify( ).
        CATCH cx_root.
          CLEAR ls_dataset-sample.
      ENDTRY.
    ENDIF.
    INSERT ls_dataset INTO TABLE mt_dataset.

  ENDMETHOD.

  METHOD fields_of.

    DATA lo_struct TYPE REF TO cl_abap_structdescr.
        DATA lo_type TYPE REF TO cl_abap_typedescr.
          DATA temp44 TYPE REF TO cl_abap_tabledescr.
    DATA temp45 TYPE abap_component_tab.
    DATA ls_comp LIKE LINE OF temp45.
      DATA temp46 TYPE string.
      DATA lv_type LIKE temp46.
      DATA lv_lower TYPE string.
      DATA ls_label TYPE z2ui5_cl_agent_genui=>ty_s_label.
      DATA temp47 TYPE z2ui5_cl_agent_genui=>ty_s_field.
      DATA temp9 TYPE z2ui5_cl_agent_genui=>ty_s_field-label.

    TRY.

        lo_type = cl_abap_typedescr=>describe_by_data( val ).
        IF lo_type->kind = cl_abap_typedescr=>kind_table.

          temp44 ?= lo_type.
          lo_struct ?= temp44->get_table_line_type( ).
        ELSE.
          lo_struct ?= lo_type.
        ENDIF.
      CATCH cx_root.
        RETURN.
    ENDTRY.


    temp45 = lo_struct->get_components( ).

    LOOP AT temp45 INTO ls_comp.
      IF ls_comp-name IS INITIAL OR ls_comp-type IS NOT BOUND.
        CONTINUE.
      ENDIF.

      CASE ls_comp-type->type_kind.
        WHEN cl_abap_typedescr=>typekind_int OR cl_abap_typedescr=>typekind_int1 OR cl_abap_typedescr=>typekind_int2 OR `8`.
          temp46 = `number`.
        WHEN cl_abap_typedescr=>typekind_packed OR cl_abap_typedescr=>typekind_float OR cl_abap_typedescr=>typekind_decfloat16 OR cl_abap_typedescr=>typekind_decfloat34.
          temp46 = `number`.
        WHEN cl_abap_typedescr=>typekind_date.
          temp46 = `date`.
        WHEN cl_abap_typedescr=>typekind_time.
          temp46 = `time`.
        WHEN cl_abap_typedescr=>typekind_char OR cl_abap_typedescr=>typekind_string OR cl_abap_typedescr=>typekind_num.
          temp46 = `string`.
      ENDCASE.

      lv_type = temp46.
      IF lv_type IS INITIAL.
        " nested tables, structures, references: not a field a view shows
        CONTINUE.
      ENDIF.
      IF ls_comp-type->absolute_name = `\TYPE=ABAP_BOOL` OR ls_comp-type->absolute_name = `\TYPE=XSDBOOLEAN`
          OR ls_comp-type->absolute_name = `\TYPE=ABAP_BOOLEAN`.
        lv_type = `boolean`.
      ENDIF.
      " a 7.02 key operand takes no built-in function - the lower case ahead

      lv_lower = to_lower( ls_comp-name ).

      READ TABLE t_label INTO ls_label WITH KEY field = ls_comp-name. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.
        READ TABLE t_label INTO ls_label WITH KEY field = lv_lower. "#EC CI_SORTSEQ
      ENDIF.

      CLEAR temp47.
      temp47-name = ls_comp-name.
      temp47-type = lv_type.

      IF sy-subrc = 0.
        temp9 = ls_label-label.
      ELSE.
        temp9 = ls_comp-name.
      ENDIF.
      temp47-label = temp9.
      INSERT temp47 INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD enum_json.

    DATA lt_quoted TYPE string_table.

    DATA lv_value LIKE LINE OF t_value.
    LOOP AT t_value INTO lv_value.
      INSERT z2ui5_cl_agent_viewxml=>json_string( lv_value ) INTO TABLE lt_quoted.
    ENDLOOP.
    result = |[{ concat_lines_of( table = lt_quoted
                                  sep   = `,` ) }]|.

  ENDMETHOD.

  METHOD get_schema.

    DATA lt_control TYPE string_table.
    DATA lt_field TYPE string_table.
    DATA lt_dataset TYPE string_table.
    DATA lt_event TYPE string_table.

    DATA ls_entry LIKE LINE OF mt_vocab.
    DATA ls_dataset LIKE LINE OF mt_dataset.
      DATA ls_field LIKE LINE OF ls_dataset-t_field.
        DATA temp48 LIKE sy-subrc.
    DATA ls_event LIKE LINE OF mt_event.
    DATA temp49 TYPE string.
    DATA lv_event LIKE temp49.
    DATA lv_field TYPE string.
    DATA lv_dataset TYPE string.
    LOOP AT mt_vocab INTO ls_entry WHERE kind = `T`. "#EC CI_SORTSEQ
      IF ls_entry-control = ls_entry-name AND check_excluded( ls_entry-control ) = abap_false.
        INSERT ls_entry-control INTO TABLE lt_control.
      ENDIF.
    ENDLOOP.
    SORT lt_control.
    INSERT `` INTO TABLE lt_field.
    INSERT `` INTO TABLE lt_dataset.

    LOOP AT mt_dataset INTO ls_dataset.
      INSERT ls_dataset-name INTO TABLE lt_dataset.

      LOOP AT ls_dataset-t_field INTO ls_field.

        READ TABLE lt_field WITH KEY table_line = ls_field-name TRANSPORTING NO FIELDS.
        temp48 = sy-subrc.
        IF NOT temp48 = 0.
          INSERT ls_field-name INTO TABLE lt_field.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT mt_event INTO ls_event.
      INSERT ls_event-event INTO TABLE lt_event.
    ENDLOOP.


    IF lt_event IS INITIAL.
      temp49 = `{"type":"string"}`.
    ELSE.
      temp49 = |\{"type":"string","enum":{ enum_json( lt_event ) }\}|.
    ENDIF.

    lv_event = temp49.

    lv_field = |\{"type":"string","enum":{ enum_json( lt_field ) }\}|.

    lv_dataset = |\{"type":"string","enum":{ enum_json( lt_dataset ) }\}|.

    result = `{"type":"object","additionalProperties":false,"required":["title","nodes"],"properties":{` &&
             `"title":{"type":"string"},` &&
             `"nodes":{"type":"array","items":{"type":"object","additionalProperties":false,` &&
             `"required":["id","parent","aggregation","control","properties","list","events"],"properties":{` &&
             `"id":{"type":"string"},"parent":{"type":"string"},"aggregation":{"type":"string"},` &&
             |"control":\{"type":"string","enum":{ enum_json( lt_control ) }\},| &&
             `"properties":{"type":"array","items":{"type":"object","additionalProperties":false,` &&
             `"required":["name","value","field","dataset","format"],"properties":{` &&
             |"name":\{"type":"string"\},"value":\{"type":"string"\},"field":{ lv_field },"dataset":{ lv_dataset },| &&
             `"format":{"type":"string","enum":["","integer","decimal"]}}}},` &&
             `"list":{"type":"object","additionalProperties":false,` &&
             `"required":["dataset","aggregation","sort_by","descending","group_by"],"properties":{` &&
             |"dataset":{ lv_dataset },"aggregation":\{"type":"string"\},"sort_by":{ lv_field },| &&
             |"descending":\{"type":"boolean"\},"group_by":{ lv_field }\}\},| &&
             `"events":{"type":"array","items":{"type":"object","additionalProperties":false,` &&
             `"required":["name","event","args"],"properties":{` &&
             |"name":\{"type":"string"\},"event":{ lv_event },"args":\{"type":"array","items":{ lv_field }\}| &&
             `}}}}}}}}`.

  ENDMETHOD.

  METHOD get_system.

    DATA lt_line TYPE string_table.
    DATA lv_control TYPE string.
    DATA lt_prop TYPE string_table.
    DATA lt_agg TYPE string_table.
    DATA lt_evt TYPE string_table.
    DATA lv_default TYPE string.
    DATA lv_text TYPE string.
    DATA ls_entry LIKE LINE OF mt_vocab.
          DATA temp50 TYPE string.
          DATA temp10 TYPE string.
          DATA temp1 LIKE LINE OF lt_line.
          DATA temp51 TYPE string.
          DATA temp11 LIKE LINE OF lt_prop.
          DATA temp52 TYPE string.
          DATA temp12 LIKE LINE OF lt_agg.
      DATA temp53 TYPE string.
      DATA temp13 TYPE string.
      DATA temp2 LIKE LINE OF lt_line.

    lv_text = `You design SAPUI5 screens for abap2UI5 apps. You answer one UI tree as JSON in the given schema - ` &&
              `nothing else, no ABAP, no SQL, no XML, no JavaScript. The app owns the data: use only the datasets ` &&
              `and fields listed below and never invent data, fields or values from them.`.
    INSERT lv_text INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    INSERT `How the tree works:` INTO TABLE lt_line.
    lv_text = `- nodes is a flat list. Exactly one node has parent "" (the root, usually a sap.m.VBox, sap.m.Page or ` &&
              `sap.m.Panel). Every other node names its parent's id and the aggregation it sits in ("" = the ` &&
              `parent's default aggregation).`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- properties: a literal in value (field and dataset ""), or a binding: field = a field name. Inside ` &&
              `the template of a list (see list) a field of that list's table; elsewhere set dataset to a structure ` &&
              `dataset. format "integer" or "decimal" formats a numeric binding; anything else is not possible. ` &&
              `A binding fits its property: B a boolean field, I and F a number field, C and E a string field.`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- list binds an aggregation (default: the control's default aggregation) to a table dataset: that ` &&
              `aggregation then has exactly ONE child node, the row template (e.g. sap.m.ColumnListItem in a ` &&
              `sap.m.Table, sap.m.StandardListItem in a sap.m.List, sap.ui.core.Item in a sap.m.Select). sort_by ` &&
              `and group_by are fields of that table (group_by also sorts). No list inside a template. ` &&
              `Leave list.dataset "" on nodes without a list.`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- A sap.m.Table needs columns (sap.m.Column with a sap.m.Text or sap.m.Label as header) and one ` &&
              `cell per column in the ColumnListItem template (its cells aggregation).`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- events: name = an event of the control, event = one of the app events below, args = fields the ` &&
              `app allows for that event (row fields inside a template).`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- Literal values must fit the property type (enum values as listed, true/false, numbers, CSS sizes ` &&
              `such as 10rem, icons only as an icon URI of the SAP icon font, e.g. sap-icon://add). Texts are shown as they are.`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- Universal properties: tooltip (text), class (sapUiSmallMargin and the other ` &&
              `sapUi margin/padding classes only).`.
    INSERT lv_text INTO TABLE lt_line.
    lv_text = `- Filtering the data is not possible in the view - a filter control can fire an app event that ` &&
              `takes its value only if the app offers one.`.
    INSERT lv_text INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    lv_text = |The controls (portable profile { z2ui5_cl_agent_gen_vocab=>c_profile }, UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }) - | &&
              `properties with their type (S text, B boolean, I integer, F number, C CSS size, U icon, E: the ` &&
              `values), aggregations [* many | 1 one: the type a child must be], default aggregation, events:`.
    INSERT lv_text INTO TABLE lt_line.


    LOOP AT mt_vocab INTO ls_entry.
      IF ls_entry-control <> lv_control.
        IF lv_control IS NOT INITIAL AND check_excluded( lv_control ) = abap_false.

          IF lv_default IS NOT INITIAL.
            temp50 = | default { lv_default }|.
          ELSE.
            CLEAR temp50.
          ENDIF.

          IF lt_evt IS NOT INITIAL.
            temp10 = | \| events { concat_lines_of( table = lt_evt sep = ` ` ) }|.
          ELSE.
            CLEAR temp10.
          ENDIF.

          temp1 = |{ lv_control }: { concat_lines_of( table = lt_prop sep = ` ` ) } \| { concat_lines_of( table = lt_agg sep = ` ` ) }| && |{ temp50 }| && |{ temp10 }|.
          INSERT temp1 INTO TABLE lt_line.
        ENDIF.
        lv_control = ls_entry-control.
        CLEAR: lt_prop, lt_agg, lt_evt, lv_default.
      ENDIF.
      CASE ls_entry-kind.
        WHEN `P`.
          IF ls_entry-type = `O`.
            CONTINUE.
          ENDIF.

          IF ls_entry-type = `E`.
            temp51 = |E:{ ls_entry-info }|.
          ELSE.
            temp51 = ls_entry-type.
          ENDIF.

          temp11 = |{ ls_entry-name }({ temp51 })|.
          INSERT temp11 INTO TABLE lt_prop.
        WHEN `A`.

          IF ls_entry-type = `M`.
            temp52 = `*`.
          ELSE.
            temp52 = `1`.
          ENDIF.

          temp12 = |{ ls_entry-name }[{ temp52 }:{ ls_entry-info }]|.
          INSERT temp12 INTO TABLE lt_agg.
        WHEN `D`.
          lv_default = ls_entry-name.
        WHEN `E`.
          INSERT ls_entry-name INTO TABLE lt_evt.
      ENDCASE.
    ENDLOOP.
    IF lv_control IS NOT INITIAL AND check_excluded( lv_control ) = abap_false.

      IF lv_default IS NOT INITIAL.
        temp53 = | default { lv_default }|.
      ELSE.
        CLEAR temp53.
      ENDIF.

      IF lt_evt IS NOT INITIAL.
        temp13 = | \| events { concat_lines_of( table = lt_evt sep = ` ` ) }|.
      ELSE.
        CLEAR temp13.
      ENDIF.

      temp2 = |{ lv_control }: { concat_lines_of( table = lt_prop sep = ` ` ) } \| { concat_lines_of( table = lt_agg sep = ` ` ) }| && |{ temp53 }| && |{ temp13 }|.
      INSERT temp2 INTO TABLE lt_line.
    ENDIF.
    lv_text = `A child can stand in for a type when it is that control, inherits from it or implements it ` &&
              `(any control is a sap.ui.core.Control; sap.m.Toolbar and sap.m.Bar are sap.m.IBar; ` &&
              `sap.m.ColumnListItem, sap.m.StandardListItem and sap.m.CustomListItem are sap.m.ListItemBase).`.
    INSERT lv_text INTO TABLE lt_line.
    result = concat_lines_of( table = lt_line
                              sep   = cl_abap_char_utilities=>newline ).

  ENDMETHOD.

  METHOD generate.

    result = rounds( request     = request
                     close_event = close_event ).
    IF commit = abap_true.
      COMMIT WORK.
    ENDIF.

  ENDMETHOD.

  METHOD rounds.

    DATA lt_line TYPE string_table.
    DATA lt_message TYPE z2ui5_if_agent_llm=>ty_t_message.

    DATA temp54 LIKE LINE OF lt_line.
    DATA ls_dataset LIKE LINE OF mt_dataset.
      DATA temp55 TYPE string_table.
      DATA lt_field LIKE temp55.
      DATA ls_field LIKE LINE OF ls_dataset-t_field.
        DATA temp56 TYPE string.
        DATA temp14 LIKE LINE OF lt_field.
      DATA temp57 TYPE string.
      DATA temp15 TYPE string.
      DATA temp3 LIKE LINE OF lt_line.
        DATA temp58 LIKE LINE OF lt_line.
      DATA ls_event LIKE LINE OF mt_event.
        DATA temp59 TYPE string.
        DATA temp16 TYPE string.
        DATA temp4 LIKE LINE OF lt_line.
    DATA temp60 TYPE z2ui5_if_agent_llm=>ty_s_message.
    DATA temp61 TYPE i.
    DATA lv_rounds LIKE temp61.
    DATA lv_system TYPE string.
    DATA lv_schema TYPE string.
      DATA lv_round LIKE sy-index.
          DATA temp62 TYPE z2ui5_if_agent_llm=>ty_s_request.
          DATA ls_answer TYPE z2ui5_if_agent_llm=>ty_s_response.
          DATA lx TYPE REF TO z2ui5_cx_agent_llm.
          DATA temp63 LIKE LINE OF result-t_issue.
          DATA temp64 LIKE LINE OF result-t_note.
      DATA lt_note LIKE result-t_note.
        DATA temp65 LIKE LINE OF result-t_note.
      DATA temp66 LIKE LINE OF result-t_note.
        DATA temp67 TYPE z2ui5_if_agent_llm=>ty_s_message.
        DATA temp68 TYPE z2ui5_if_agent_llm=>ty_s_message.
    temp54 = |The user asks: { request }|.
    INSERT temp54 INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    INSERT `Datasets (the data the app hands over - the only data the view may show):` INTO TABLE lt_line.

    LOOP AT mt_dataset INTO ls_dataset.

      CLEAR temp55.

      lt_field = temp55.

      LOOP AT ls_dataset-t_field INTO ls_field.

        IF ls_field-label <> ls_field-name.
          temp56 = |, "{ ls_field-label }"|.
        ELSE.
          CLEAR temp56.
        ENDIF.

        temp14 = |{ ls_field-name } ({ ls_field-type }{ temp56 })|.
        INSERT temp14 INTO TABLE lt_field.
      ENDLOOP.

      IF ls_dataset-is_table = abap_true.
        temp57 = `table`.
      ELSE.
        temp57 = `structure`.
      ENDIF.

      IF ls_dataset-description IS NOT INITIAL.
        temp15 = | - { ls_dataset-description }|.
      ELSE.
        CLEAR temp15.
      ENDIF.

      temp3 = |- { ls_dataset-name }: a { temp57 }| && |{ temp15 }; fields: | && |{ concat_lines_of( table = lt_field sep = `, ` ) }|.
      INSERT temp3 INTO TABLE lt_line.
      IF ls_dataset-sample IS NOT INITIAL.

        temp58 = |  sample: { ls_dataset-sample }|.
        INSERT temp58 INTO TABLE lt_line.
      ENDIF.
    ENDLOOP.
    INSERT `` INTO TABLE lt_line.
    IF mt_event IS INITIAL.
      INSERT `App events: none - the view has no events.` INTO TABLE lt_line.
    ELSE.
      INSERT `App events the view may fire:` INTO TABLE lt_line.

      LOOP AT mt_event INTO ls_event.

        IF ls_event-description IS NOT INITIAL.
          temp59 = |: { ls_event-description }|.
        ELSE.
          CLEAR temp59.
        ENDIF.

        IF ls_event-t_arg IS NOT INITIAL.
          temp16 = |; args may be { concat_lines_of( table = ls_event-t_arg sep = `, ` ) } - in this order, leave out only from the end|.
        ELSE.
          temp16 = `; no args`.
        ENDIF.

        temp4 = |- { ls_event-event }{ temp59 }| && |{ temp16 }|.
        INSERT temp4 INTO TABLE lt_line.
      ENDLOOP.
    ENDIF.

    CLEAR temp60.
    temp60-role = z2ui5_if_agent_llm=>cs_role-user.
    temp60-content = concat_lines_of( table = lt_line sep = cl_abap_char_utilities=>newline ).
    INSERT temp60 INTO TABLE lt_message.


    IF z2ui5_cl_agent_settings=>check_llm( item = z2ui5_cl_agent_settings=>cs_llm-genui_repair default_value = abap_true ) = abap_true.
      temp61 = 2.
    ELSE.
      temp61 = 1.
    ENDIF.

    lv_rounds = temp61.

    lv_system = get_system( ).

    lv_schema = get_schema( ).
    DO lv_rounds TIMES.

      lv_round = sy-index.
      result-rounds = lv_round.
      TRY.

          CLEAR temp62.
          temp62-purpose = `genui`.
          temp62-app = mv_app.
          temp62-system = lv_system.
          temp62-t_message = lt_message.
          temp62-schema = lv_schema.

          ls_answer = z2ui5_cl_agent_llm=>create( )->chat( temp62 ).

        CATCH z2ui5_cx_agent_llm INTO lx.
          result-ok = abap_false.

          temp63 = |the language model call failed ({ lx->kind }): { lx->get_text( ) }|.
          INSERT temp63 INTO TABLE result-t_issue.

          temp64 = |round { lv_round }: no answer|.
          INSERT temp64 INTO TABLE result-t_note.
          RETURN.
      ENDTRY.

      lt_note = result-t_note.
      result = render( json        = ls_answer-text
                       close_event = close_event ).
      result-rounds = lv_round.
      " the notes of the earlier rounds first
      INSERT LINES OF result-t_note INTO TABLE lt_note.
      result-t_note = lt_note.
      IF result-ok = abap_true.

        temp65 = |round { lv_round }: the UI tree is valid ({ lines( mt_node ) } nodes)|.
        INSERT temp65 INTO TABLE result-t_note.
        RETURN.
      ENDIF.

      temp66 = |round { lv_round }: rejected - { lines( result-t_issue ) } issue(s)|.
      INSERT temp66 INTO TABLE result-t_note.
      IF lv_round < lv_rounds.

        CLEAR temp67.
        temp67-role = z2ui5_if_agent_llm=>cs_role-assistant.
        temp67-content = ls_answer-text.
        INSERT temp67 INTO TABLE lt_message.

        CLEAR temp68.
        temp68-role = z2ui5_if_agent_llm=>cs_role-user.
        temp68-content = |The UI tree was rejected:{ cl_abap_char_utilities=>newline }| && |{ concat_lines_of( table = result-t_issue sep = cl_abap_char_utilities=>newline ) }| && |{ cl_abap_char_utilities=>newline }Answer the whole corrected UI tree.|.
        INSERT temp68 INTO TABLE lt_message.
        INSERT `repair: the issues went back to the language model` INTO TABLE result-t_note.
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD render.

    DATA lv_note TYPE string.
    DATA temp69 TYPE string.
        DATA temp70 TYPE string.
        DATA lx TYPE REF TO cx_root.
        DATA temp71 LIKE LINE OF result-t_issue.

    CLEAR: mt_node, mt_issue, mv_title.
    result-json = json.

    temp69 = json.
    parse( temp69 ).
    IF mt_issue IS INITIAL.
      validate( ).
    ENDIF.
    result-t_issue = mt_issue.
    IF mt_issue IS NOT INITIAL.
      RETURN.
    ENDIF.
    TRY.

        temp70 = close_event.
        build( EXPORTING close_event = temp70
               IMPORTING xml         = result-xml
                         xml_popup   = result-xml_popup
                         title       = result-title ).
        result-ok = abap_true.
        lv_note = |checked against { z2ui5_cl_agent_gen_vocab=>c_profile } (UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }, | &&
                  |profile sha256 { substring( val = z2ui5_cl_agent_gen_vocab=>c_source
                                               len = 12 ) }): | &&
                  |controls, aggregations, properties and their literals, bindings to the given fields, events|.
        INSERT lv_note INTO TABLE result-t_note.

      CATCH cx_root INTO lx.

        temp71 = |the view cannot be built: { lx->get_text( ) }|.
        INSERT temp71 INTO TABLE result-t_issue.
    ENDTRY.

  ENDMETHOD.

  METHOD issue.
      DATA temp72 LIKE LINE OF mt_issue.

    IF node IS SUPPLIED.

      temp72 = |node "{ node-id }" ({ node-control }): { text }|.
      INSERT temp72 INTO TABLE mt_issue.
    ELSE.
      INSERT text INTO TABLE mt_issue.
    ENDIF.

  ENDMETHOD.

  METHOD parse.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.
        DATA lv_count TYPE i.
          DATA lv_n TYPE string.
          DATA temp73 TYPE ty_s_node.
          DATA ls_node LIKE temp73.
          DATA lv_props TYPE i.
            DATA lv_p TYPE string.
            DATA temp74 TYPE z2ui5_cl_agent_genui=>ty_s_prop.
          DATA lv_events TYPE i.
            DATA lv_e TYPE string.
            DATA temp75 TYPE ty_s_evt.
            DATA ls_evt LIKE temp75.
            DATA lv_args TYPE i.
              DATA temp1 TYPE string.
        DATA lx TYPE REF TO cx_root.

    TRY.
        lo_json = z2ui5_cl_ajson=>parse( iv_json            = json
                                         iv_keep_item_order = abap_true ).
      CATCH cx_root.
        issue( `the answer is no JSON` ).
        RETURN.
    ENDTRY.

    TRY.
        mv_title = lo_json->get_string( `/title` ).
        IF lo_json->get_node_type( `/nodes` ) <> z2ui5_if_ajson_types=>node_type-array.
          issue( `the answer has no nodes array` ).
          RETURN.
        ENDIF.

        lv_count = lines( lo_json->members( `/nodes` ) ).
        IF lv_count = 0.
          issue( `the UI tree has no nodes` ).
          RETURN.
        ENDIF.
        IF lv_count > c_max_nodes.
          issue( |the UI tree has { lv_count } nodes - at most { c_max_nodes } are allowed| ).
          RETURN.
        ENDIF.
        DO lv_count TIMES.

          lv_n = |/nodes/{ sy-index }|.

          CLEAR temp73.
          temp73-id = condense( lo_json->get_string( |{ lv_n }/id| ) ).
          temp73-parent = condense( lo_json->get_string( |{ lv_n }/parent| ) ).
          temp73-aggregation = condense( lo_json->get_string( |{ lv_n }/aggregation| ) ).
          temp73-control = condense( lo_json->get_string( |{ lv_n }/control| ) ).
          temp73-list_data = to_lower( condense( lo_json->get_string( |{ lv_n }/list/dataset| ) ) ).
          temp73-list_agg = condense( lo_json->get_string( |{ lv_n }/list/aggregation| ) ).
          temp73-sort_by = to_upper( condense( lo_json->get_string( |{ lv_n }/list/sort_by| ) ) ).
          temp73-descending = lo_json->get_boolean( |{ lv_n }/list/descending| ).
          temp73-group_by = to_upper( condense( lo_json->get_string( |{ lv_n }/list/group_by| ) ) ).

          ls_node = temp73.

          lv_props = lines( lo_json->members( |{ lv_n }/properties| ) ).
          DO lv_props TIMES.

            lv_p = |{ lv_n }/properties/{ sy-index }|.

            CLEAR temp74.
            temp74-name = condense( lo_json->get_string( |{ lv_p }/name| ) ).
            temp74-value = lo_json->get_string( |{ lv_p }/value| ).
            temp74-field = to_upper( condense( lo_json->get_string( |{ lv_p }/field| ) ) ).
            temp74-dataset = to_lower( condense( lo_json->get_string( |{ lv_p }/dataset| ) ) ).
            temp74-format = to_lower( condense( lo_json->get_string( |{ lv_p }/format| ) ) ).
            INSERT temp74 INTO TABLE ls_node-t_prop.
          ENDDO.

          lv_events = lines( lo_json->members( |{ lv_n }/events| ) ).
          DO lv_events TIMES.

            lv_e = |{ lv_n }/events/{ sy-index }|.

            CLEAR temp75.
            temp75-name = condense( lo_json->get_string( |{ lv_e }/name| ) ).
            temp75-event = to_upper( condense( lo_json->get_string( |{ lv_e }/event| ) ) ).

            ls_evt = temp75.

            lv_args = lines( lo_json->members( |{ lv_e }/args| ) ).
            DO lv_args TIMES.

              temp1 = to_upper( condense( lo_json->get_string( |{ lv_e }/args/{ sy-index }| ) ) ).
              INSERT temp1 INTO TABLE ls_evt-t_arg.
            ENDDO.
            INSERT ls_evt INTO TABLE ls_node-t_evt.
          ENDDO.
          INSERT ls_node INTO TABLE mt_node.
        ENDDO.

      CATCH cx_root INTO lx.
        issue( |the UI tree does not follow the schema - { lx->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.

  METHOD check_excluded.

    " raw HTML, the app shell, the popup slots' own roots, custom data and
    " layout data: never part of a generated view
    DATA temp76 LIKE sy-subrc.
    DATA temp1 TYPE xsdboolean.
    READ TABLE mt_vocab WITH KEY control = control kind = `L` TRANSPORTING NO FIELDS.
    temp76 = sy-subrc.

    temp1 = boolc( control = `sap.ui.core.HTML` OR control = `sap.m.Shell` OR control = `sap.m.Dialog` OR control = `sap.m.Popover` OR control = `sap.ui.core.CustomData` OR temp76 = 0 ).
    result = temp1. "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD vocab.

    READ TABLE mt_vocab INTO result WITH KEY control = control kind = kind name = name. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      CLEAR result.
    ENDIF.

  ENDMETHOD.

  METHOD field_of.

    DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
      DATA temp77 LIKE sy-subrc.
      DATA temp2 TYPE xsdboolean.
    READ TABLE mt_dataset INTO ls_dataset WITH KEY name = dataset. "#EC CI_SORTSEQ
    IF sy-subrc = 0.

      READ TABLE ls_dataset-t_field WITH KEY name = field TRANSPORTING NO FIELDS.
      temp77 = sy-subrc.

      temp2 = boolc( temp77 = 0 ).
      result = temp2. "#EC CI_SORTSEQ
    ENDIF.

  ENDMETHOD.

  METHOD type_of.

    DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
      DATA ls_field TYPE z2ui5_cl_agent_genui=>ty_s_field.
    READ TABLE mt_dataset INTO ls_dataset WITH KEY name = dataset. "#EC CI_SORTSEQ
    IF sy-subrc = 0.

      READ TABLE ls_dataset-t_field INTO ls_field WITH KEY name = field. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        result = ls_field-type.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD validate.

    DATA lt_id TYPE string_table.
    DATA lt_queue TYPE string_table.

    " ids unique, one root, every parent known
    DATA ls_node LIKE LINE OF mt_node.
      DATA temp78 LIKE sy-subrc.
      DATA temp79 LIKE sy-subrc.
    DATA lv_roots TYPE i.
      DATA temp80 LIKE sy-subrc.
      DATA temp81 LIKE sy-subrc.
      DATA lv_id LIKE LINE OF lt_queue.
      FIELD-SYMBOLS <temp17> LIKE LINE OF lt_queue.
      DATA temp18 LIKE sy-tabix.
      DATA lr_parent TYPE REF TO z2ui5_cl_agent_genui=>ty_s_node.
      DATA temp82 LIKE LINE OF mt_node.
      DATA lr_child LIKE REF TO temp82.
          DATA ls_default TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
          DATA temp83 TYPE string.
          DATA lv_list_agg LIKE temp83.
    DATA temp84 LIKE LINE OF mt_node.
    DATA lr_node LIKE REF TO temp84.
    LOOP AT mt_node INTO ls_node.


      temp79 = sy-subrc.
      READ TABLE lt_id WITH KEY table_line = ls_node-id TRANSPORTING NO FIELDS.
      temp78 = sy-subrc.
      sy-subrc = temp79.
      IF ls_node-id IS INITIAL.
        issue( node = ls_node
               text = `a node without id` ).
      ELSEIF temp78 = 0.
        issue( node = ls_node
               text = `the id is used twice` ).
      ENDIF.
      INSERT ls_node-id INTO TABLE lt_id.
    ENDLOOP.

    lv_roots = 0.
    LOOP AT mt_node INTO ls_node.


      temp81 = sy-subrc.
      READ TABLE lt_id WITH KEY table_line = ls_node-parent TRANSPORTING NO FIELDS.
      temp80 = sy-subrc.
      sy-subrc = temp81.
      IF ls_node-parent IS INITIAL.
        lv_roots = lv_roots + 1.
        INSERT ls_node-id INTO TABLE lt_queue.
      ELSEIF NOT temp80 = 0.
        issue( node = ls_node
               text = |the parent "{ ls_node-parent }" does not exist| ).
      ENDIF.
    ENDLOOP.
    IF lv_roots <> 1.
      issue( |the UI tree needs exactly one root node (parent ""), it has { lv_roots }| ).
    ENDIF.
    IF mt_issue IS NOT INITIAL.
      RETURN.
    ENDIF.

    " walk from the root - the effective aggregation and the row scope of
    " every node; a node never reached sits in a cycle
    WHILE lt_queue IS NOT INITIAL.



      temp18 = sy-tabix.
      READ TABLE lt_queue INDEX 1 ASSIGNING <temp17>.
      sy-tabix = temp18.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      lv_id = <temp17>.
      DELETE lt_queue INDEX 1.

      READ TABLE mt_node REFERENCE INTO lr_parent WITH KEY id = lv_id. "#EC CI_SORTSEQ
      lr_parent->reached = abap_true.


      LOOP AT mt_node REFERENCE INTO lr_child WHERE parent = lv_id AND reached = abap_false. "#EC CI_SORTSEQ
        lr_child->agg = lr_child->aggregation.
        IF lr_child->agg IS INITIAL.

          READ TABLE mt_vocab INTO ls_default WITH KEY control = lr_parent->control kind = `D`. "#EC CI_SORTSEQ
          IF sy-subrc = 0.
            lr_child->agg = ls_default-name.
          ENDIF.
        ENDIF.
        lr_child->scope = lr_parent->scope.
        IF lr_parent->list_data IS NOT INITIAL.

          IF lr_parent->list_agg IS NOT INITIAL.
            temp83 = lr_parent->list_agg.
          ELSE.
            CLEAR temp83.
          ENDIF.

          lv_list_agg = temp83.
          IF lv_list_agg IS INITIAL.
            READ TABLE mt_vocab INTO ls_default WITH KEY control = lr_parent->control kind = `D`. "#EC CI_SORTSEQ
            IF sy-subrc = 0.
              lv_list_agg = ls_default-name.
            ENDIF.
          ENDIF.
          IF lr_child->agg = lv_list_agg.
            lr_child->scope = lr_parent->list_data.
          ENDIF.
        ENDIF.
        INSERT lr_child->id INTO TABLE lt_queue.
      ENDLOOP.
    ENDWHILE.
    LOOP AT mt_node INTO ls_node WHERE reached = abap_false. "#EC CI_SORTSEQ
      issue( node = ls_node
             text = `the node is not reachable from the root (a cycle of parents)` ).
    ENDLOOP.
    IF mt_issue IS NOT INITIAL.
      RETURN.
    ENDIF.



    LOOP AT mt_node REFERENCE INTO lr_node.
      validate_node( CHANGING node = lr_node->* ).
    ENDLOOP.

  ENDMETHOD.

  METHOD validate_node.

    DATA lt_seen TYPE string_table.

    " the control
    DATA temp85 LIKE sy-subrc.
    DATA temp86 LIKE sy-subrc.
    DATA temp91 LIKE sy-subrc.
    DATA temp92 LIKE sy-subrc.
      DATA ls_parent TYPE z2ui5_cl_agent_genui=>ty_s_node.
      DATA temp87 LIKE sy-subrc.
      DATA temp88 LIKE sy-subrc.
        DATA ls_agg TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
        DATA temp89 LIKE sy-subrc.
        DATA temp90 LIKE sy-subrc.
          DATA lv_siblings TYPE i.
          DATA lv_first TYPE string.
          DATA ls_sibling LIKE LINE OF mt_node.
    DATA ls_prop LIKE LINE OF node-t_prop.
      DATA temp93 LIKE sy-subrc.
      DATA temp94 LIKE sy-subrc.
      DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
      DATA temp95 TYPE string.
      DATA lv_list_agg LIKE temp95.
        DATA ls_default TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
      DATA ls_list_agg TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
        DATA lv_templates TYPE i.
    temp86 = sy-subrc.
    READ TABLE mt_vocab WITH KEY control = node-control kind = `T` name = node-control TRANSPORTING NO FIELDS.
    temp85 = sy-subrc.
    sy-subrc = temp86.
    IF NOT temp85 = 0. "#EC CI_SORTSEQ
      issue( node = node
             text = |unknown control - only the controls of the portable profile v1 are allowed| ).
      RETURN.
    ENDIF.
    IF check_excluded( node-control ) = abap_true.
      issue( node = node
             text = `this control is not allowed in a generated view` ).
      RETURN.
    ENDIF.

    " where it sits


    temp92 = sy-subrc.
    READ TABLE mt_vocab WITH KEY control = node-control kind = `T` name = `sap.ui.core.Control` TRANSPORTING NO FIELDS.
    temp91 = sy-subrc.
    sy-subrc = temp92.
    IF node-parent IS NOT INITIAL.

      READ TABLE mt_node INTO ls_parent WITH KEY id = node-parent. "#EC CI_SORTSEQ


      temp88 = sy-subrc.
      READ TABLE mt_vocab WITH KEY control = ls_parent-control kind = `T` name = ls_parent-control TRANSPORTING NO FIELDS.
      temp87 = sy-subrc.
      sy-subrc = temp88.
      IF temp87 = 0. "#EC CI_SORTSEQ

        ls_agg = vocab( control = ls_parent-control
                              kind    = `A`
                              name    = node-agg ).


        temp90 = sy-subrc.
        READ TABLE mt_vocab WITH KEY control = node-control kind = `T` name = ls_agg-info TRANSPORTING NO FIELDS.
        temp89 = sy-subrc.
        sy-subrc = temp90.
        IF ls_agg IS INITIAL.
          issue( node = node
                 text = |{ ls_parent-control } has no aggregation "{ node-agg }"| ).
        ELSEIF NOT temp89 = 0. "#EC CI_SORTSEQ
          issue( node = node
                 text = |the aggregation { node-agg } of { ls_parent-control } takes a { ls_agg-info }, not a { node-control }| ).
        ELSEIF ls_agg-type = `S`.

          lv_siblings = 0.

          lv_first = ``.

          LOOP AT mt_node INTO ls_sibling WHERE parent = node-parent AND agg = node-agg. "#EC CI_SORTSEQ
            lv_siblings = lv_siblings + 1.
            IF lv_first IS INITIAL.
              lv_first = ls_sibling-id.
            ENDIF.
          ENDLOOP.
          " reported once, on the first of them
          IF lv_siblings > 1 AND lv_first = node-id.
            issue( node = node
                   text = |the aggregation { node-agg } of { ls_parent-control } takes one child, it has { lv_siblings }| ).
          ENDIF.
        ENDIF.
        " a sap.m.Bar is no flex container before UI5 1.76: a spacer there
        " starts a new line and the bar cuts away the controls after it -
        " so does the Page headerContent, which goes into such a bar
        IF node-control = `sap.m.ToolbarSpacer` AND ( ls_parent-control = `sap.m.Bar`
            OR ( ls_parent-control = `sap.m.Page` AND node-agg = `headerContent` ) ).
          issue( node = node
                 text = |a sap.m.ToolbarSpacer belongs in a toolbar - in { ls_parent-control } { node-agg } it hides the controls after it| ).
        ENDIF.
      ENDIF.
    ELSEIF NOT temp91 = 0. "#EC CI_SORTSEQ
      " the root goes into the content of the view and of the dialog
      issue( node = node
             text = `the root sits in the content of a view - it must be a sap.ui.core.Control` ).
    ENDIF.

    " the properties

    LOOP AT node-t_prop INTO ls_prop.


      temp94 = sy-subrc.
      READ TABLE lt_seen WITH KEY table_line = ls_prop-name TRANSPORTING NO FIELDS.
      temp93 = sy-subrc.
      sy-subrc = temp94.
      IF temp93 = 0.
        issue( node = node
               text = |the property { ls_prop-name } is set twice| ).
        CONTINUE.
      ENDIF.
      INSERT ls_prop-name INTO TABLE lt_seen.
      validate_prop( node = node
                     prop = ls_prop ).
    ENDLOOP.

    " the list binding
    IF node-list_data IS NOT INITIAL.

      READ TABLE mt_dataset INTO ls_dataset WITH KEY name = node-list_data. "#EC CI_SORTSEQ

      IF node-list_agg IS NOT INITIAL.
        temp95 = node-list_agg.
      ELSE.
        CLEAR temp95.
      ENDIF.

      lv_list_agg = temp95.
      IF lv_list_agg IS INITIAL.

        READ TABLE mt_vocab INTO ls_default WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ
        IF sy-subrc = 0.
          lv_list_agg = ls_default-name.
        ENDIF.
      ENDIF.

      ls_list_agg = vocab( control = node-control
                                 kind    = `A`
                                 name    = lv_list_agg ).
      IF ls_dataset IS INITIAL.
        issue( node = node
               text = |the list binds to "{ node-list_data }" - no such dataset| ).
      ELSEIF ls_dataset-is_table = abap_false.
        issue( node = node
               text = |the list binds to "{ node-list_data }", a structure - a list binds to a table| ).
      ELSEIF ls_list_agg IS INITIAL OR ls_list_agg-type <> `M`.
        issue( node = node
               text = |"{ lv_list_agg }" is no aggregation of { node-control } a list can bind| ).
      ELSE.
        IF node-scope IS NOT INITIAL.
          issue( node = node
                 text = `a list inside the row template of another list is not allowed` ).
        ENDIF.

        lv_templates = 0.
        LOOP AT mt_node TRANSPORTING NO FIELDS WHERE parent = node-id AND agg = lv_list_agg. "#EC CI_SORTSEQ
          lv_templates = lv_templates + 1.
        ENDLOOP.
        IF lv_templates <> 1.
          issue( node = node
                 text = |a list needs exactly one row template in { lv_list_agg }, it has { lv_templates }| ).
        ENDIF.
        IF node-sort_by IS NOT INITIAL AND field_of( dataset = node-list_data
                                                      field   = node-sort_by ) = abap_false.
          issue( node = node
                 text = |sort_by "{ node-sort_by }" is no field of { node-list_data }| ).
        ENDIF.
        IF node-group_by IS NOT INITIAL AND field_of( dataset = node-list_data
                                                       field   = node-group_by ) = abap_false.
          issue( node = node
                 text = |group_by "{ node-group_by }" is no field of { node-list_data }| ).
        ENDIF.
      ENDIF.
    ENDIF.

    validate_events( node ).

  ENDMETHOD.

  METHOD validate_prop.

    DATA lv_type TYPE string.
    DATA lv_info TYPE string.
    DATA lv_dataset TYPE string.
        DATA ls_entry TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
      DATA lv_error TYPE string.
      DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
    DATA lv_field_type TYPE string.
    DATA temp96 TYPE string.
    DATA lv_takes LIKE temp96.

    CASE prop-name.
      WHEN `tooltip`.
        lv_type = `S`.
      WHEN `class`.
        lv_type = `K`.
      WHEN OTHERS.

        ls_entry = vocab( control = node-control
                                kind    = `P`
                                name    = prop-name ).
        IF ls_entry IS INITIAL.
          issue( node = node
                 text = |unknown property "{ prop-name }" - not one of { node-control } in the portable profile at UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }| ).
          RETURN.
        ENDIF.
        lv_type = ls_entry-type.
        lv_info = ls_entry-info.
        " a URL property is an icon URI, whatever the profile types it
        " (sap.m.SegmentedButtonItem's icon is a string there): any other
        " URL is a request the browser sends - with data in it, if a prompt
        " asked for that
        IF prop-name = `icon` OR prop-name = `src` OR prop-name = `href`.
          lv_type = `U`.
        ENDIF.
    ENDCASE.

    IF prop-field IS INITIAL.
      IF prop-format IS NOT INITIAL OR prop-dataset IS NOT INITIAL.
        issue( node = node
               text = |{ prop-name }: format and dataset belong to a binding (field)| ).
        RETURN.
      ENDIF.

      lv_error = check_literal( type  = lv_type
                                      info  = lv_info
                                      value = prop-value ).
      IF lv_error IS NOT INITIAL.
        issue( node = node
               text = |{ prop-name } = "{ prop-value }": { lv_error }| ).
      ENDIF.
      RETURN.
    ENDIF.

    " a binding
    IF prop-value IS NOT INITIAL.
      issue( node = node
             text = |{ prop-name }: a literal value and a binding at the same time| ).
      RETURN.
    ENDIF.
    IF lv_type = `O` OR lv_type = `U` OR lv_type = `K`.
      issue( node = node
             text = |{ prop-name } takes no binding in a generated view| ).
      RETURN.
    ENDIF.
    IF prop-format IS NOT INITIAL AND prop-format <> `integer` AND prop-format <> `decimal`.
      issue( node = node
             text = |{ prop-name }: format "{ prop-format }" - only integer and decimal exist| ).
      RETURN.
    ENDIF.
    IF node-scope IS NOT INITIAL AND prop-dataset IS INITIAL.
      IF field_of( dataset = node-scope
                   field   = prop-field ) = abap_false.
        issue( node = node
               text = |{ prop-name } binds to "{ prop-field }" - no field of { node-scope }, the table of this row| ).
        RETURN.
      ENDIF.
      lv_dataset = node-scope.
    ELSE.

      READ TABLE mt_dataset INTO ls_dataset WITH KEY name = prop-dataset. "#EC CI_SORTSEQ
      IF sy-subrc <> 0 OR prop-dataset IS INITIAL.
        issue( node = node
               text = |{ prop-name } binds to "{ prop-field }" outside a row template without a structure dataset| ).
        RETURN.
      ELSEIF ls_dataset-is_table = abap_true.
        issue( node = node
               text = |{ prop-name } binds to the table { prop-dataset } outside its row template - bind a list instead| ).
        RETURN.
      ELSEIF field_of( dataset = prop-dataset
                       field   = prop-field ) = abap_false.
        issue( node = node
               text = |{ prop-name } binds to "{ prop-field }" - no field of { prop-dataset }| ).
        RETURN.
      ENDIF.
      lv_dataset = prop-dataset.
    ENDIF.

    " the value as the property takes it - UI5 throws on a boolean, a
    " number, a size or an enum value of another type (validateProperty),
    " and a format formats a number

    lv_field_type = type_of( dataset = lv_dataset
                                   field   = prop-field ).

    CASE lv_type.
      WHEN `B`.
        temp96 = `boolean`.
      WHEN `I` OR `F`.
        temp96 = `number`.
      WHEN `C` OR `E`.
        temp96 = `string`.
    ENDCASE.

    lv_takes = temp96.
    IF lv_takes IS NOT INITIAL AND lv_field_type <> lv_takes.
      issue( node = node
             text = |{ prop-name } takes a { lv_takes } field - "{ prop-field }" is a { lv_field_type } field| ).
    ELSEIF prop-format IS NOT INITIAL AND lv_field_type <> `number`.
      issue( node = node
             text = |{ prop-name }: format { prop-format } formats a number field - "{ prop-field }" is a { lv_field_type } field| ).
    ENDIF.

  ENDMETHOD.

  METHOD check_literal.

    DATA lt_value TYPE string_table.
        DATA lv_icon TYPE string.
        DATA temp97 LIKE sy-subrc.
        DATA temp98 LIKE sy-subrc.
        DATA temp99 LIKE sy-subrc.
        DATA temp100 LIKE sy-subrc.

    " ^ and $ of a POSIX regex match at every line: "10rem" + a line break +
    " "{/OTHER/PATH}" passed the size check as its first line, and the
    " value, written as it is, was a binding over any path of the model
    IF type <> `S` AND ( value CA cl_abap_char_utilities=>cr_lf OR value CA '{}' ).
      result = `a single value - no line breaks, no braces`.
      RETURN.
    ENDIF.

    CASE type.
      WHEN `S`.
        " any text - escaped as a literal when the view is built
        RETURN.
      WHEN `B`.
        IF value <> `true` AND value <> `false`.
          result = `true or false`.
        ENDIF.
      WHEN `I`.
        " a sign only in front - "5-" or "-" is no int and the view fails to load
        FIND REGEX `^-?[0-9]{1,9}$` IN value ##REGEX_POSIX.
        IF sy-subrc <> 0.
          result = `an integer`.
        ENDIF.
      WHEN `F`.
        " digits on both sides of the point - ".5" is no float to the linter
        FIND REGEX `^-?[0-9]+(\.[0-9]+)?$` IN value ##REGEX_POSIX.
        IF sy-subrc <> 0 OR strlen( value ) > 15.
          result = `a number`.
        ENDIF.
      WHEN `C`.
        FIND REGEX `^(auto|inherit|0|[0-9]{1,4}(\.[0-9]{1,2})?(px|em|rem|%|vw|vh|pt))$` IN value ##REGEX_POSIX.
        IF sy-subrc <> 0.
          result = `a CSS size such as 10rem, 50% or auto`.
        ENDIF.
      WHEN `U`.
        FIND REGEX `^sap-icon://[a-z0-9-]{1,60}$` IN value ##REGEX_POSIX.
        IF sy-subrc <> 0.
          result = `only an icon URI of the SAP icon font, e.g. sap-icon://add`.
          RETURN.
        ENDIF.
        " a name the font does not have renders no icon at all - silently
        IF mt_icon IS INITIAL.
          mt_icon = z2ui5_cl_agent_gen_vocab=>get_icons( ).
        ENDIF.

        lv_icon = substring_after( val = value
                                         sub = `sap-icon://` ).


        temp98 = sy-subrc.
        READ TABLE mt_icon WITH KEY table_line = lv_icon TRANSPORTING NO FIELDS.
        temp97 = sy-subrc.
        sy-subrc = temp98.
        IF NOT temp97 = 0.
          result = |no icon of the SAP icon font at UI5 { z2ui5_cl_agent_gen_vocab=>c_floor } - e.g. sap-icon://add|.
        ENDIF.
      WHEN `E`.
        SPLIT info AT `|` INTO TABLE lt_value.


        temp100 = sy-subrc.
        READ TABLE lt_value WITH KEY table_line = value TRANSPORTING NO FIELDS.
        temp99 = sy-subrc.
        sy-subrc = temp100.
        IF NOT temp99 = 0.
          result = |one of { concat_lines_of( table = lt_value
                                              sep   = `, ` ) }|.
        ENDIF.
      WHEN `K`.
        FIND REGEX `^((sapUi(Tiny|Small|Medium|Large)?(Margin|Padding)(Top|Bottom|Begin|End|BeginEnd|TopBottom)?|sapUiContentPadding|sapUiResponsiveMargin|sapUiNoMargin[A-Za-z]*|sapUiNoContentPadding) ?)+$` IN value ##REGEX_POSIX.
        IF sy-subrc <> 0.
          result = `only the sapUi margin and padding classes`.
        ENDIF.
      WHEN OTHERS.
        result = `takes no literal in a generated view`.
    ENDCASE.

  ENDMETHOD.

  METHOD validate_events.

    DATA ls_evt LIKE LINE OF node-t_evt.
      DATA ls_event TYPE z2ui5_cl_agent_genui=>ty_s_event.
        DATA temp101 TYPE string_table.
        DATA lt_name LIKE temp101.
        DATA temp102 TYPE string.
      DATA lv_arg LIKE LINE OF ls_evt-t_arg.
        DATA lv_pos LIKE sy-tabix.
        DATA temp103 LIKE sy-subrc.
        DATA temp104 LIKE sy-subrc.
        DATA temp105 LIKE sy-tabix.
          DATA temp106 TYPE string.
        DATA temp107 TYPE string.
        DATA lv_declared LIKE temp107.
          DATA lv_found LIKE abap_false.
          DATA ls_dataset LIKE LINE OF mt_dataset.
            DATA temp108 LIKE sy-subrc.
            DATA temp109 LIKE sy-subrc.
            DATA temp110 LIKE sy-tabix.
    LOOP AT node-t_evt INTO ls_evt.
      IF vocab( control = node-control
                kind    = `E`
                name    = ls_evt-name ) IS INITIAL.
        issue( node = node
               text = |"{ ls_evt-name }" is no event of { node-control } in the portable profile| ).
        CONTINUE.
      ENDIF.

      READ TABLE mt_event INTO ls_event WITH KEY event = ls_evt-event. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.

        CLEAR temp101.

        lt_name = temp101.
        LOOP AT mt_event INTO ls_event.
          INSERT ls_event-event INTO TABLE lt_name.
        ENDLOOP.

        IF lt_name IS NOT INITIAL.
          temp102 = |; allowed: { concat_lines_of( table = lt_name sep = `, ` ) }|.
        ELSE.
          temp102 = `; the app allows none`.
        ENDIF.
        issue( node = node
               text = |{ ls_evt-name } fires "{ ls_evt-event }" - not an event of the app| &&
                      |{ temp102 }| ).
        CONTINUE.
      ENDIF.

      LOOP AT ls_evt-t_arg INTO lv_arg.

        lv_pos = sy-tabix.



        temp104 = sy-subrc.
        temp105 = sy-tabix.
        READ TABLE ls_event-t_arg WITH KEY table_line = lv_arg TRANSPORTING NO FIELDS.
        temp103 = sy-subrc.
        sy-subrc = temp104.
        sy-tabix = temp105.
        IF NOT temp103 = 0.

          IF ls_event-t_arg IS NOT INITIAL.
            temp106 = |; allowed: { concat_lines_of( table = ls_event-t_arg sep = `, ` ) }|.
          ELSE.
            temp106 = `; it takes none`.
          ENDIF.
          issue( node = node
                 text = |the event { ls_evt-event } takes no argument "{ lv_arg }"| &&
                        |{ temp106 }| ).
          CONTINUE.
        ENDIF.
        " the app reads its arguments by position (get_event_arg( 1 )): in
        " another order, or with a gap, it read the date as the carrier

        CLEAR temp107.

        lv_declared = temp107.
        READ TABLE ls_event-t_arg INTO lv_declared INDEX lv_pos.
        IF lv_declared <> lv_arg.
          issue( node = node
                 text = |the event { ls_evt-event } takes its arguments in this order: | &&
                        |{ concat_lines_of( table = ls_event-t_arg
                                            sep   = `, ` ) } - leave out only from the end| ).
          CONTINUE.
        ENDIF.
        IF node-scope IS NOT INITIAL.
          IF field_of( dataset = node-scope
                       field   = lv_arg ) = abap_false.
            issue( node = node
                   text = |the argument "{ lv_arg }" is no field of { node-scope }, the table of this row| ).
          ENDIF.
        ELSE.

          lv_found = abap_false.

          LOOP AT mt_dataset INTO ls_dataset WHERE is_table = abap_false. "#EC CI_SORTSEQ



            temp109 = sy-subrc.
            temp110 = sy-tabix.
            READ TABLE ls_dataset-t_field WITH KEY name = lv_arg TRANSPORTING NO FIELDS.
            temp108 = sy-subrc.
            sy-subrc = temp109.
            sy-tabix = temp110.
            IF temp108 = 0. "#EC CI_SORTSEQ
              lv_found = abap_true.
            ENDIF.
          ENDLOOP.
          IF lv_found = abap_false.
            issue( node = node
                   text = |the argument "{ lv_arg }" is outside a row template and no field of a structure dataset| ).
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

  METHOD ns_of.

    DATA lv_ns TYPE string.

    DATA lv_off TYPE i.
    DATA temp111 TYPE string.
    lv_off = find( val  = control
                         sub  = `.`
                         occ  = -1 ).
    lv_ns = control(lv_off).
    local = substring( val = control
                       off = lv_off + 1 ).

    CASE lv_ns.
      WHEN `sap.m`.
        temp111 = ``.
      WHEN `sap.ui.core`.
        temp111 = `core`.
      WHEN `sap.ui.layout`.
        temp111 = `layout`.
      WHEN `sap.ui.layout.form`.
        temp111 = `form`.
      WHEN `sap.tnt`.
        temp111 = `tnt`.
      WHEN OTHERS.
        temp111 = `unknown`.
    ENDCASE.
    prefix = temp111.

  ENDMETHOD.

  METHOD binding_of.

    DATA lv_path TYPE string.
      DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
    DATA temp112 TYPE string.

    IF node-scope IS NOT INITIAL AND prop-dataset IS INITIAL.
      lv_path = prop-field.
    ELSE.

      READ TABLE mt_dataset INTO ls_dataset WITH KEY name = prop-dataset. "#EC CI_SORTSEQ
      lv_path = |{ ls_dataset-path }/{ prop-field }|.
    ENDIF.

    CASE prop-format.
      WHEN `integer`.
        temp112 = |\{path:'{ lv_path }',type:'sap.ui.model.type.Integer'\}|.
      WHEN `decimal`.
        temp112 = |\{path:'{ lv_path }',type:'sap.ui.model.type.Float',| && |formatOptions:\{minFractionDigits:2,maxFractionDigits:2\}\}|.
      WHEN OTHERS.
        temp112 = |\{{ lv_path }\}|.
    ENDCASE.
    result = temp112.

  ENDMETHOD.

  METHOD build.

    DATA view TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA root TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA ls_root TYPE z2ui5_cl_agent_genui=>ty_s_node.
    DATA popup TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA temp113 TYPE string.
    DATA dialog TYPE REF TO z2ui5_cl_ui5_view_builder.
    view = z2ui5_cl_ui5_view_builder=>factory( ).

    root = view->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`        v = `sap.m`
        )->a( n = `xmlns:mvc`    v = `sap.ui.core.mvc`
        )->a( n = `xmlns:core`   v = `sap.ui.core`
        )->a( n = `xmlns:layout` v = `sap.ui.layout`
        )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
        )->a( n = `xmlns:tnt`    v = `sap.tnt`
        )->a( n = `displayBlock` v = `true`
        )->a( n = `height`       v = `100%` ).


    READ TABLE mt_node INTO ls_root WITH KEY parent = ``. "#EC CI_SORTSEQ
    build_node( parent = root
                node   = ls_root ).
    xml = view->stringify( ).


    popup = z2ui5_cl_ui5_view_builder=>factory( ).

    IF mv_title IS NOT INITIAL.
      temp113 = mv_title.
    ELSE.
      temp113 = `Generated view`.
    ENDIF.

    dialog = popup->ele( n = `FragmentDefinition` ns = `core`
        )->a( n = `xmlns`        v = `sap.m`
        )->a( n = `xmlns:core`   v = `sap.ui.core`
        )->a( n = `xmlns:layout` v = `sap.ui.layout`
        )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
        )->a( n = `xmlns:tnt`    v = `sap.tnt`
        )->ele( `Dialog`
            )->a( n = `title`        t = temp113
            )->a( n = `contentWidth` v = `80%`
            )->a( n = `resizable`    v = `true` ).
    build_node( parent = dialog->ele( `content` )
                node   = ls_root ).
    dialog->ele( `endButton`
        )->tag( `Button`
            )->a( n = `text`  v = `Close`
            )->a( n = `press` v = mo_client->_event( close_event ) ).
    xml_popup = popup->stringify( ).
    title = mv_title.

  ENDMETHOD.

  METHOD build_node.

    DATA lv_prefix TYPE string.
    DATA lv_local TYPE string.
    DATA lt_agg TYPE string_table.
    DATA lt_arg TYPE string_table.
    DATA target TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA element TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA ls_prop LIKE LINE OF node-t_prop.
        DATA ls_entry TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
      DATA ls_dataset TYPE z2ui5_cl_agent_genui=>ty_s_dataset.
      DATA lv_list_agg LIKE node-list_agg.
        DATA ls_default TYPE z2ui5_cl_agent_gen_vocab=>ty_s_entry.
      DATA temp114 TYPE string.
      DATA lv_sort LIKE temp114.
      DATA temp115 TYPE string.
        DATA temp19 TYPE string.
        DATA temp5 TYPE string.
    DATA ls_evt LIKE LINE OF node-t_evt.
      DATA lv_arg LIKE LINE OF ls_evt-t_arg.
          DATA temp116 LIKE LINE OF lt_arg.
          DATA ls_struct LIKE LINE OF mt_dataset.
            DATA temp117 LIKE sy-subrc.
            DATA temp118 LIKE sy-subrc.
              DATA temp119 LIKE LINE OF lt_arg.
    DATA ls_child LIKE LINE OF mt_node.
      DATA temp120 LIKE sy-subrc.
      DATA temp121 LIKE sy-subrc.
    DATA temp122 TYPE string.
    DATA lv_default LIKE temp122.
    DATA lv_agg LIKE LINE OF lt_agg.

    ns_of( EXPORTING control = node-control
           IMPORTING prefix  = lv_prefix
                     local   = lv_local ).

    element = parent->ele( n  = lv_local
                                 ns = lv_prefix ).

    " attributes first - the builder writes them before the children

    LOOP AT node-t_prop INTO ls_prop.
      IF ls_prop-field IS NOT INITIAL.
        element->a( n = ls_prop-name
                    v = binding_of( node = node
                                    prop = ls_prop ) ).
      ELSE.

        ls_entry = vocab( control = node-control
                                kind    = `P`
                                name    = ls_prop-name ).
        IF ls_entry-type = `S` OR ls_prop-name = `tooltip`.
          " text from the model: always a literal - escaped by the framework
          element->a( n = ls_prop-name
                      t = ls_prop-value ).
        ELSE.
          " validated: an enum value, a number, a boolean, a size, an icon, a class
          element->a( n = ls_prop-name
                      v = ls_prop-value ).
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF node-list_data IS NOT INITIAL.

      READ TABLE mt_dataset INTO ls_dataset WITH KEY name = node-list_data. "#EC CI_SORTSEQ

      lv_list_agg = node-list_agg.
      IF lv_list_agg IS INITIAL.

        READ TABLE mt_vocab INTO ls_default WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ
        lv_list_agg = ls_default-name.
      ENDIF.

      IF node-group_by IS NOT INITIAL.
        temp114 = node-group_by.
      ELSE.
        temp114 = node-sort_by.
      ENDIF.

      lv_sort = temp114.

      IF lv_sort IS INITIAL.
        temp115 = |\{path:'{ ls_dataset-path }',templateShareable:false\}|.
      ELSE.

        IF node-descending = abap_true.
          temp19 = `true`.
        ELSE.
          temp19 = `false`.
        ENDIF.

        IF node-group_by IS NOT INITIAL.
          temp5 = `,group:true`.
        ELSE.
          CLEAR temp5.
        ENDIF.
        temp115 = |\{path:'{ ls_dataset-path }',templateShareable:false,sorter:\{path:'{ lv_sort }'| && |,descending:{ temp19 }| && |{ temp5 }\}\}|.
      ENDIF.
      element->a( n = lv_list_agg
                  v = temp115 ).
    ENDIF.


    LOOP AT node-t_evt INTO ls_evt.
      CLEAR lt_arg.

      LOOP AT ls_evt-t_arg INTO lv_arg.
        IF node-scope IS NOT INITIAL.

          temp116 = |$\{{ lv_arg }\}|.
          INSERT temp116 INTO TABLE lt_arg.
        ELSE.

          LOOP AT mt_dataset INTO ls_struct WHERE is_table = abap_false. "#EC CI_SORTSEQ


            temp118 = sy-subrc.
            READ TABLE ls_struct-t_field WITH KEY name = lv_arg TRANSPORTING NO FIELDS.
            temp117 = sy-subrc.
            sy-subrc = temp118.
            IF temp117 = 0. "#EC CI_SORTSEQ

              temp119 = |$\{{ ls_struct-path }/{ lv_arg }\}|.
              INSERT temp119 INTO TABLE lt_arg.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
      element->a( n = ls_evt-name
                  v = mo_client->_event( val   = ls_evt-event
                                         t_arg = lt_arg ) ).
    ENDLOOP.

    " the children, by aggregation in their order; the default aggregation
    " without its element

    LOOP AT mt_node INTO ls_child WHERE parent = node-id. "#EC CI_SORTSEQ


      temp121 = sy-subrc.
      READ TABLE lt_agg WITH KEY table_line = ls_child-agg TRANSPORTING NO FIELDS.
      temp120 = sy-subrc.
      sy-subrc = temp121.
      IF NOT temp120 = 0.
        INSERT ls_child-agg INTO TABLE lt_agg.
      ENDIF.
    ENDLOOP.
    READ TABLE mt_vocab INTO ls_default WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ

    IF sy-subrc = 0.
      temp122 = ls_default-name.
    ELSE.
      CLEAR temp122.
    ENDIF.

    lv_default = temp122.

    LOOP AT lt_agg INTO lv_agg.
      IF lv_agg = lv_default.
        target = element.
      ELSE.
        target = element->ele( n  = lv_agg
                               ns = lv_prefix ).
      ENDIF.
      LOOP AT mt_node INTO ls_child WHERE parent = node-id AND agg = lv_agg. "#EC CI_SORTSEQ
        build_node( parent = target
                    node   = ls_child ).
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
