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
    TYPES ty_t_label TYPE STANDARD TABLE OF ty_s_label WITH EMPTY KEY.

    TYPES:
      "! type: string, number, date, time or boolean.
      BEGIN OF ty_s_field,
        name  TYPE string,
        type  TYPE string,
        label TYPE string,
      END OF ty_s_field.
    TYPES ty_t_field TYPE STANDARD TABLE OF ty_s_field WITH EMPTY KEY.

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
    TYPES ty_t_dataset TYPE STANDARD TABLE OF ty_s_dataset WITH EMPTY KEY.

    TYPES:
      "! An event of the app the view may fire. t_arg: the fields its
      "! arguments may name (of the row, inside a list's template, or of a
      "! structure) - empty: no arguments.
      BEGIN OF ty_s_event,
        event       TYPE string,
        description TYPE string,
        t_arg       TYPE string_table,
      END OF ty_s_event.
    TYPES ty_t_event TYPE STANDARD TABLE OF ty_s_event WITH EMPTY KEY.

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
    TYPES ty_t_prop TYPE STANDARD TABLE OF ty_s_prop WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_evt,
        name  TYPE string,
        event TYPE string,
        t_arg TYPE string_table,
      END OF ty_s_evt.
    TYPES ty_t_evt TYPE STANDARD TABLE OF ty_s_evt WITH EMPTY KEY.

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
    TYPES ty_t_node TYPE STANDARD TABLE OF ty_s_node WITH EMPTY KEY.

    DATA mo_client TYPE REF TO z2ui5_if_client.
    DATA mv_app TYPE string.
    DATA mt_dataset TYPE ty_t_dataset.
    DATA mt_event TYPE ty_t_event.
    DATA mt_vocab TYPE z2ui5_cl_agent_gen_vocab=>ty_t_entry.
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

    result = NEW #( ).
    result->mo_client = client.
    result->mv_app = to_upper( app ).
    result->mt_vocab = z2ui5_cl_agent_gen_vocab=>get( ).

  ENDMETHOD.

  METHOD add_table.

    dataset_add( name        = name
                 val         = val
                 bind        = COND string( WHEN bind IS NOT INITIAL THEN bind ELSE mo_client->_bind( val ) )
                 description = description
                 t_label     = t_label
                 is_table    = abap_true ).
    result = me.

  ENDMETHOD.

  METHOD add_structure.

    dataset_add( name        = name
                 val         = val
                 bind        = COND string( WHEN bind IS NOT INITIAL THEN bind ELSE mo_client->_bind( val ) )
                 description = description
                 t_label     = t_label
                 is_table    = abap_false ).
    result = me.

  ENDMETHOD.

  METHOD add_event.

    DATA ls_event TYPE ty_s_event.

    ls_event-event = to_upper( event ).
    ls_event-description = description.
    LOOP AT t_arg INTO DATA(lv_arg).
      INSERT to_upper( lv_arg ) INTO TABLE ls_event-t_arg.
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

    DATA(ls_dataset) = VALUE ty_s_dataset( name        = to_lower( name )
                                           path        = bind
                                           is_table    = is_table
                                           description = description
                                           t_field     = fields_of( val     = val
                                                                    t_label = t_label ) ).
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
            LOOP AT <table> ASSIGNING FIELD-SYMBOL(<row>).
              IF lines( <sample> ) >= c_samples.
                EXIT.
              ENDIF.
              INSERT <row> INTO TABLE <sample>.
            ENDLOOP.
            DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
            lo_json->set( iv_path = `/`
                          iv_val  = <sample> ).
          ELSE.
            lo_json = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
            lo_json->set( iv_path = `/`
                          iv_val  = val ).
          ENDIF.
          ls_dataset-sample = lo_json->stringify( ).
        CATCH cx_root.
          CLEAR ls_dataset-sample.
      ENDTRY.
    ENDIF.
    INSERT ls_dataset INTO TABLE mt_dataset.

  ENDMETHOD.

  METHOD fields_of.

    DATA lo_struct TYPE REF TO cl_abap_structdescr.

    TRY.
        DATA(lo_type) = cl_abap_typedescr=>describe_by_data( val ).
        IF lo_type->kind = cl_abap_typedescr=>kind_table.
          lo_struct ?= CAST cl_abap_tabledescr( lo_type )->get_table_line_type( ).
        ELSE.
          lo_struct ?= lo_type.
        ENDIF.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    LOOP AT lo_struct->get_components( ) INTO DATA(ls_comp).
      IF ls_comp-name IS INITIAL OR ls_comp-type IS NOT BOUND.
        CONTINUE.
      ENDIF.
      DATA(lv_type) = SWITCH string( ls_comp-type->type_kind
                                     WHEN cl_abap_typedescr=>typekind_int OR cl_abap_typedescr=>typekind_int1
                                       OR cl_abap_typedescr=>typekind_int2 OR `8`
                                       OR cl_abap_typedescr=>typekind_packed OR cl_abap_typedescr=>typekind_float
                                       OR cl_abap_typedescr=>typekind_decfloat16 OR cl_abap_typedescr=>typekind_decfloat34
                                       THEN `number`
                                     WHEN cl_abap_typedescr=>typekind_date THEN `date`
                                     WHEN cl_abap_typedescr=>typekind_time THEN `time`
                                     WHEN cl_abap_typedescr=>typekind_char OR cl_abap_typedescr=>typekind_string
                                       OR cl_abap_typedescr=>typekind_num
                                       THEN `string` ).
      IF lv_type IS INITIAL.
        " nested tables, structures, references: not a field a view shows
        CONTINUE.
      ENDIF.
      IF ls_comp-type->absolute_name = `\TYPE=ABAP_BOOL` OR ls_comp-type->absolute_name = `\TYPE=XSDBOOLEAN`
          OR ls_comp-type->absolute_name = `\TYPE=ABAP_BOOLEAN`.
        lv_type = `boolean`.
      ENDIF.
      " a 7.02 key operand takes no built-in function - the lower case ahead
      DATA(lv_lower) = to_lower( ls_comp-name ).
      READ TABLE t_label INTO DATA(ls_label) WITH KEY field = ls_comp-name. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.
        READ TABLE t_label INTO ls_label WITH KEY field = lv_lower. "#EC CI_SORTSEQ
      ENDIF.
      INSERT VALUE #( name  = ls_comp-name
                      type  = lv_type
                      label = COND #( WHEN sy-subrc = 0 THEN ls_label-label ELSE ls_comp-name ) ) INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD enum_json.

    DATA lt_quoted TYPE string_table.

    LOOP AT t_value INTO DATA(lv_value).
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

    LOOP AT mt_vocab INTO DATA(ls_entry) WHERE kind = `T`. "#EC CI_SORTSEQ
      IF ls_entry-control = ls_entry-name AND check_excluded( ls_entry-control ) = abap_false.
        INSERT ls_entry-control INTO TABLE lt_control.
      ENDIF.
    ENDLOOP.
    SORT lt_control.
    INSERT `` INTO TABLE lt_field.
    INSERT `` INTO TABLE lt_dataset.
    LOOP AT mt_dataset INTO DATA(ls_dataset).
      INSERT ls_dataset-name INTO TABLE lt_dataset.
      LOOP AT ls_dataset-t_field INTO DATA(ls_field).
        IF NOT line_exists( lt_field[ table_line = ls_field-name ] ).
          INSERT ls_field-name INTO TABLE lt_field.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT mt_event INTO DATA(ls_event).
      INSERT ls_event-event INTO TABLE lt_event.
    ENDLOOP.

    DATA(lv_event) = COND string( WHEN lt_event IS INITIAL THEN `{"type":"string"}`
                                  ELSE |\{"type":"string","enum":{ enum_json( lt_event ) }\}| ).
    DATA(lv_field) = |\{"type":"string","enum":{ enum_json( lt_field ) }\}|.
    DATA(lv_dataset) = |\{"type":"string","enum":{ enum_json( lt_dataset ) }\}|.

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

    INSERT `You design SAPUI5 screens for abap2UI5 apps. You answer one UI tree as JSON in the given schema - ` &&
           `nothing else, no ABAP, no SQL, no XML, no JavaScript. The app owns the data: use only the datasets ` &&
           `and fields listed below and never invent data, fields or values from them.` INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    INSERT `How the tree works:` INTO TABLE lt_line.
    INSERT `- nodes is a flat list. Exactly one node has parent "" (the root, usually a sap.m.VBox, sap.m.Page or ` &&
           `sap.m.Panel). Every other node names its parent's id and the aggregation it sits in ("" = the ` &&
           `parent's default aggregation).` INTO TABLE lt_line.
    INSERT `- properties: a literal in value (field and dataset ""), or a binding: field = a field name. Inside ` &&
           `the template of a list (see list) a field of that list's table; elsewhere set dataset to a structure ` &&
           `dataset. format "integer" or "decimal" formats a numeric binding; anything else is not possible. ` &&
           `A binding fits its property: B a boolean field, I and F a number field, C and E a string field.` INTO TABLE lt_line.
    INSERT `- list binds an aggregation (default: the control's default aggregation) to a table dataset: that ` &&
           `aggregation then has exactly ONE child node, the row template (e.g. sap.m.ColumnListItem in a ` &&
           `sap.m.Table, sap.m.StandardListItem in a sap.m.List, sap.ui.core.Item in a sap.m.Select). sort_by ` &&
           `and group_by are fields of that table (group_by also sorts). No list inside a template. ` &&
           `Leave list.dataset "" on nodes without a list.` INTO TABLE lt_line.
    INSERT `- A sap.m.Table needs columns (sap.m.Column with a sap.m.Text or sap.m.Label as header) and one ` &&
           `cell per column in the ColumnListItem template (its cells aggregation).` INTO TABLE lt_line.
    INSERT `- events: name = an event of the control, event = one of the app events below, args = fields the ` &&
           `app allows for that event (row fields inside a template).` INTO TABLE lt_line.
    INSERT `- Literal values must fit the property type (enum values as listed, true/false, numbers, CSS sizes ` &&
           `such as 10rem, icons only as an icon URI of the SAP icon font, e.g. sap-icon://add). Texts are shown as they are.` INTO TABLE lt_line.
    INSERT `- Universal properties: tooltip (text), class (sapUiSmallMargin and the other ` &&
           `sapUi margin/padding classes only).` INTO TABLE lt_line.
    INSERT `- Filtering the data is not possible in the view - a filter control can fire an app event that ` &&
           `takes its value only if the app offers one.` INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    INSERT |The controls (portable profile { z2ui5_cl_agent_gen_vocab=>c_profile }, UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }) - | &&
           `properties with their type (S text, B boolean, I integer, F number, C CSS size, U icon, E: the ` &&
           `values), aggregations [* many | 1 one: the type a child must be], default aggregation, events:` INTO TABLE lt_line.

    LOOP AT mt_vocab INTO DATA(ls_entry).
      IF ls_entry-control <> lv_control.
        IF lv_control IS NOT INITIAL AND check_excluded( lv_control ) = abap_false.
          INSERT |{ lv_control }: { concat_lines_of( table = lt_prop
                                                      sep   = ` ` ) } \| { concat_lines_of( table = lt_agg
                                                                                             sep   = ` ` ) }| &&
                 |{ COND #( WHEN lv_default IS NOT INITIAL THEN | default { lv_default }| ) }| &&
                 |{ COND #( WHEN lt_evt IS NOT INITIAL THEN | \| events { concat_lines_of( table = lt_evt
                                                                                           sep   = ` ` ) }| ) }| INTO TABLE lt_line.
        ENDIF.
        lv_control = ls_entry-control.
        CLEAR: lt_prop, lt_agg, lt_evt, lv_default.
      ENDIF.
      CASE ls_entry-kind.
        WHEN `P`.
          IF ls_entry-type = `O`.
            CONTINUE.
          ENDIF.
          INSERT |{ ls_entry-name }({ COND #( WHEN ls_entry-type = `E` THEN |E:{ ls_entry-info }| ELSE ls_entry-type ) })| INTO TABLE lt_prop.
        WHEN `A`.
          INSERT |{ ls_entry-name }[{ COND #( WHEN ls_entry-type = `M` THEN `*` ELSE `1` ) }:{ ls_entry-info }]| INTO TABLE lt_agg.
        WHEN `D`.
          lv_default = ls_entry-name.
        WHEN `E`.
          INSERT ls_entry-name INTO TABLE lt_evt.
      ENDCASE.
    ENDLOOP.
    IF lv_control IS NOT INITIAL AND check_excluded( lv_control ) = abap_false.
      INSERT |{ lv_control }: { concat_lines_of( table = lt_prop
                                                  sep   = ` ` ) } \| { concat_lines_of( table = lt_agg
                                                                                         sep   = ` ` ) }| &&
             |{ COND #( WHEN lv_default IS NOT INITIAL THEN | default { lv_default }| ) }| &&
             |{ COND #( WHEN lt_evt IS NOT INITIAL THEN | \| events { concat_lines_of( table = lt_evt
                                                                                       sep   = ` ` ) }| ) }| INTO TABLE lt_line.
    ENDIF.
    INSERT `A child can stand in for a type when it is that control, inherits from it or implements it ` &&
           `(any control is a sap.ui.core.Control; sap.m.Toolbar and sap.m.Bar are sap.m.IBar; ` &&
           `sap.m.ColumnListItem, sap.m.StandardListItem and sap.m.CustomListItem are sap.m.ListItemBase).` INTO TABLE lt_line.
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

    INSERT |The user asks: { request }| INTO TABLE lt_line.
    INSERT `` INTO TABLE lt_line.
    INSERT `Datasets (the data the app hands over - the only data the view may show):` INTO TABLE lt_line.
    LOOP AT mt_dataset INTO DATA(ls_dataset).
      DATA(lt_field) = VALUE string_table( ).
      LOOP AT ls_dataset-t_field INTO DATA(ls_field).
        INSERT |{ ls_field-name } ({ ls_field-type }{ COND #( WHEN ls_field-label <> ls_field-name THEN |, "{ ls_field-label }"| ) })| INTO TABLE lt_field.
      ENDLOOP.
      INSERT |- { ls_dataset-name }: a { COND #( WHEN ls_dataset-is_table = abap_true THEN `table` ELSE `structure` ) }| &&
             |{ COND #( WHEN ls_dataset-description IS NOT INITIAL THEN | - { ls_dataset-description }| ) }; fields: | &&
             |{ concat_lines_of( table = lt_field
                                 sep   = `, ` ) }| INTO TABLE lt_line.
      IF ls_dataset-sample IS NOT INITIAL.
        INSERT |  sample: { ls_dataset-sample }| INTO TABLE lt_line.
      ENDIF.
    ENDLOOP.
    INSERT `` INTO TABLE lt_line.
    IF mt_event IS INITIAL.
      INSERT `App events: none - the view has no events.` INTO TABLE lt_line.
    ELSE.
      INSERT `App events the view may fire:` INTO TABLE lt_line.
      LOOP AT mt_event INTO DATA(ls_event).
        INSERT |- { ls_event-event }{ COND #( WHEN ls_event-description IS NOT INITIAL THEN |: { ls_event-description }| ) }| &&
               |{ COND #( WHEN ls_event-t_arg IS NOT INITIAL
                          THEN |; args may be { concat_lines_of( table = ls_event-t_arg
                                                                 sep   = `, ` ) }|
                          ELSE `; no args` ) }| INTO TABLE lt_line.
      ENDLOOP.
    ENDIF.
    INSERT VALUE #( role    = z2ui5_if_agent_llm=>cs_role-user
                    content = concat_lines_of( table = lt_line
                                               sep   = cl_abap_char_utilities=>newline ) ) INTO TABLE lt_message.

    DATA(lv_rounds) = COND i( WHEN z2ui5_cl_agent_settings=>check_llm( item    = z2ui5_cl_agent_settings=>cs_llm-genui_repair
                                                                       default = abap_true ) = abap_true
                              THEN 2 ELSE 1 ).
    DATA(lv_system) = get_system( ).
    DATA(lv_schema) = get_schema( ).
    DO lv_rounds TIMES.
      DATA(lv_round) = sy-index.
      result-rounds = lv_round.
      TRY.
          DATA(ls_answer) = z2ui5_cl_agent_llm=>create( )->chat( VALUE #( purpose   = `genui`
                                                                           app       = mv_app
                                                                           system    = lv_system
                                                                           t_message = lt_message
                                                                           schema    = lv_schema ) ).
        CATCH z2ui5_cx_agent_llm INTO DATA(lx).
          result-ok = abap_false.
          INSERT |the language model call failed ({ lx->kind }): { lx->get_text( ) }| INTO TABLE result-t_issue.
          INSERT |round { lv_round }: no answer| INTO TABLE result-t_note.
          RETURN.
      ENDTRY.
      DATA(lt_note) = result-t_note.
      result = render( json        = ls_answer-text
                       close_event = close_event ).
      result-rounds = lv_round.
      " the notes of the earlier rounds first
      INSERT LINES OF result-t_note INTO TABLE lt_note.
      result-t_note = lt_note.
      IF result-ok = abap_true.
        INSERT |round { lv_round }: the UI tree is valid ({ lines( mt_node ) } nodes)| INTO TABLE result-t_note.
        RETURN.
      ENDIF.
      INSERT |round { lv_round }: rejected - { lines( result-t_issue ) } issue(s)| INTO TABLE result-t_note.
      IF lv_round < lv_rounds.
        INSERT VALUE #( role    = z2ui5_if_agent_llm=>cs_role-assistant
                        content = ls_answer-text ) INTO TABLE lt_message.
        INSERT VALUE #( role    = z2ui5_if_agent_llm=>cs_role-user
                        content = |The UI tree was rejected:{ cl_abap_char_utilities=>newline }| &&
                                  |{ concat_lines_of( table = result-t_issue
                                                      sep   = cl_abap_char_utilities=>newline ) }| &&
                                  |{ cl_abap_char_utilities=>newline }Answer the whole corrected UI tree.| ) INTO TABLE lt_message.
        INSERT `repair: the issues went back to the language model` INTO TABLE result-t_note.
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD render.

    CLEAR: mt_node, mt_issue, mv_title.
    result-json = json.
    parse( CONV string( json ) ).
    IF mt_issue IS INITIAL.
      validate( ).
    ENDIF.
    result-t_issue = mt_issue.
    IF mt_issue IS NOT INITIAL.
      RETURN.
    ENDIF.
    TRY.
        build( EXPORTING close_event = CONV #( close_event )
               IMPORTING xml         = result-xml
                         xml_popup   = result-xml_popup
                         title       = result-title ).
        result-ok = abap_true.
        INSERT |checked against { z2ui5_cl_agent_gen_vocab=>c_profile } (UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }, | &&
               |profile sha256 { substring( val = z2ui5_cl_agent_gen_vocab=>c_source
                                            len = 12 ) }): | &&
               |controls, aggregations, properties and their literals, bindings to the given fields, events| INTO TABLE result-t_note.
      CATCH cx_root INTO DATA(lx).
        INSERT |the view cannot be built: { lx->get_text( ) }| INTO TABLE result-t_issue.
    ENDTRY.

  ENDMETHOD.

  METHOD issue.

    IF node IS SUPPLIED.
      INSERT |node "{ node-id }" ({ node-control }): { text }| INTO TABLE mt_issue.
    ELSE.
      INSERT text INTO TABLE mt_issue.
    ENDIF.

  ENDMETHOD.

  METHOD parse.

    DATA lo_json TYPE REF TO z2ui5_if_ajson.

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
        DATA(lv_count) = lines( lo_json->members( `/nodes` ) ).
        IF lv_count = 0.
          issue( `the UI tree has no nodes` ).
          RETURN.
        ENDIF.
        IF lv_count > c_max_nodes.
          issue( |the UI tree has { lv_count } nodes - at most { c_max_nodes } are allowed| ).
          RETURN.
        ENDIF.
        DO lv_count TIMES.
          DATA(lv_n) = |/nodes/{ sy-index }|.
          DATA(ls_node) = VALUE ty_s_node( id          = condense( lo_json->get_string( |{ lv_n }/id| ) )
                                           parent      = condense( lo_json->get_string( |{ lv_n }/parent| ) )
                                           aggregation = condense( lo_json->get_string( |{ lv_n }/aggregation| ) )
                                           control     = condense( lo_json->get_string( |{ lv_n }/control| ) )
                                           list_data   = to_lower( condense( lo_json->get_string( |{ lv_n }/list/dataset| ) ) )
                                           list_agg    = condense( lo_json->get_string( |{ lv_n }/list/aggregation| ) )
                                           sort_by     = to_upper( condense( lo_json->get_string( |{ lv_n }/list/sort_by| ) ) )
                                           descending  = lo_json->get_boolean( |{ lv_n }/list/descending| )
                                           group_by    = to_upper( condense( lo_json->get_string( |{ lv_n }/list/group_by| ) ) ) ).
          DATA(lv_props) = lines( lo_json->members( |{ lv_n }/properties| ) ).
          DO lv_props TIMES.
            DATA(lv_p) = |{ lv_n }/properties/{ sy-index }|.
            INSERT VALUE #( name    = condense( lo_json->get_string( |{ lv_p }/name| ) )
                            value   = lo_json->get_string( |{ lv_p }/value| )
                            field   = to_upper( condense( lo_json->get_string( |{ lv_p }/field| ) ) )
                            dataset = to_lower( condense( lo_json->get_string( |{ lv_p }/dataset| ) ) )
                            format  = to_lower( condense( lo_json->get_string( |{ lv_p }/format| ) ) ) ) INTO TABLE ls_node-t_prop.
          ENDDO.
          DATA(lv_events) = lines( lo_json->members( |{ lv_n }/events| ) ).
          DO lv_events TIMES.
            DATA(lv_e) = |{ lv_n }/events/{ sy-index }|.
            DATA(ls_evt) = VALUE ty_s_evt( name  = condense( lo_json->get_string( |{ lv_e }/name| ) )
                                           event = to_upper( condense( lo_json->get_string( |{ lv_e }/event| ) ) ) ).
            DATA(lv_args) = lines( lo_json->members( |{ lv_e }/args| ) ).
            DO lv_args TIMES.
              INSERT to_upper( condense( lo_json->get_string( |{ lv_e }/args/{ sy-index }| ) ) ) INTO TABLE ls_evt-t_arg.
            ENDDO.
            INSERT ls_evt INTO TABLE ls_node-t_evt.
          ENDDO.
          INSERT ls_node INTO TABLE mt_node.
        ENDDO.
      CATCH cx_root INTO DATA(lx).
        issue( |the UI tree does not follow the schema - { lx->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.

  METHOD check_excluded.

    " raw HTML, the app shell, the popup slots' own roots, custom data and
    " layout data: never part of a generated view
    result = xsdbool( control = `sap.ui.core.HTML` OR control = `sap.m.Shell` OR control = `sap.m.Dialog`
                      OR control = `sap.m.Popover` OR control = `sap.ui.core.CustomData`
                      OR line_exists( mt_vocab[ control = control kind = `L` ] ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD vocab.

    READ TABLE mt_vocab INTO result WITH KEY control = control kind = kind name = name. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      CLEAR result.
    ENDIF.

  ENDMETHOD.

  METHOD field_of.

    READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = dataset. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = xsdbool( line_exists( ls_dataset-t_field[ name = field ] ) ). "#EC CI_SORTSEQ
    ENDIF.

  ENDMETHOD.

  METHOD type_of.

    READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = dataset. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      READ TABLE ls_dataset-t_field INTO DATA(ls_field) WITH KEY name = field. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        result = ls_field-type.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD validate.

    DATA lt_id TYPE string_table.
    DATA lt_queue TYPE string_table.

    " ids unique, one root, every parent known
    LOOP AT mt_node INTO DATA(ls_node).
      IF ls_node-id IS INITIAL.
        issue( node = ls_node
               text = `a node without id` ).
      ELSEIF line_exists( lt_id[ table_line = ls_node-id ] ).
        issue( node = ls_node
               text = `the id is used twice` ).
      ENDIF.
      INSERT ls_node-id INTO TABLE lt_id.
    ENDLOOP.
    DATA(lv_roots) = 0.
    LOOP AT mt_node INTO ls_node.
      IF ls_node-parent IS INITIAL.
        lv_roots = lv_roots + 1.
        INSERT ls_node-id INTO TABLE lt_queue.
      ELSEIF NOT line_exists( lt_id[ table_line = ls_node-parent ] ).
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
      DATA(lv_id) = lt_queue[ 1 ].
      DELETE lt_queue INDEX 1.
      READ TABLE mt_node REFERENCE INTO DATA(lr_parent) WITH KEY id = lv_id. "#EC CI_SORTSEQ
      lr_parent->reached = abap_true.
      LOOP AT mt_node REFERENCE INTO DATA(lr_child) WHERE parent = lv_id AND reached = abap_false. "#EC CI_SORTSEQ
        lr_child->agg = lr_child->aggregation.
        IF lr_child->agg IS INITIAL.
          READ TABLE mt_vocab INTO DATA(ls_default) WITH KEY control = lr_parent->control kind = `D`. "#EC CI_SORTSEQ
          IF sy-subrc = 0.
            lr_child->agg = ls_default-name.
          ENDIF.
        ENDIF.
        lr_child->scope = lr_parent->scope.
        IF lr_parent->list_data IS NOT INITIAL.
          DATA(lv_list_agg) = COND string( WHEN lr_parent->list_agg IS NOT INITIAL THEN lr_parent->list_agg ).
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

    LOOP AT mt_node REFERENCE INTO DATA(lr_node).
      validate_node( CHANGING node = lr_node->* ).
    ENDLOOP.

  ENDMETHOD.

  METHOD validate_node.

    DATA lt_seen TYPE string_table.

    " the control
    IF NOT line_exists( mt_vocab[ control = node-control kind = `T` name = node-control ] ). "#EC CI_SORTSEQ
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
    IF node-parent IS NOT INITIAL.
      READ TABLE mt_node INTO DATA(ls_parent) WITH KEY id = node-parent. "#EC CI_SORTSEQ
      IF line_exists( mt_vocab[ control = ls_parent-control kind = `T` name = ls_parent-control ] ). "#EC CI_SORTSEQ
        DATA(ls_agg) = vocab( control = ls_parent-control
                              kind    = `A`
                              name    = node-agg ).
        IF ls_agg IS INITIAL.
          issue( node = node
                 text = |{ ls_parent-control } has no aggregation "{ node-agg }"| ).
        ELSEIF NOT line_exists( mt_vocab[ control = node-control kind = `T` name = ls_agg-info ] ). "#EC CI_SORTSEQ
          issue( node = node
                 text = |the aggregation { node-agg } of { ls_parent-control } takes a { ls_agg-info }, not a { node-control }| ).
        ELSEIF ls_agg-type = `S`.
          DATA(lv_siblings) = 0.
          DATA(lv_first) = ``.
          LOOP AT mt_node INTO DATA(ls_sibling) WHERE parent = node-parent AND agg = node-agg. "#EC CI_SORTSEQ
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
    ELSEIF NOT line_exists( mt_vocab[ control = node-control kind = `T` name = `sap.ui.core.Control` ] ). "#EC CI_SORTSEQ
      " the root goes into the content of the view and of the dialog
      issue( node = node
             text = `the root sits in the content of a view - it must be a sap.ui.core.Control` ).
    ENDIF.

    " the properties
    LOOP AT node-t_prop INTO DATA(ls_prop).
      IF line_exists( lt_seen[ table_line = ls_prop-name ] ).
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
      READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = node-list_data. "#EC CI_SORTSEQ
      DATA(lv_list_agg) = COND string( WHEN node-list_agg IS NOT INITIAL THEN node-list_agg ).
      IF lv_list_agg IS INITIAL.
        READ TABLE mt_vocab INTO DATA(ls_default) WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ
        IF sy-subrc = 0.
          lv_list_agg = ls_default-name.
        ENDIF.
      ENDIF.
      DATA(ls_list_agg) = vocab( control = node-control
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
        DATA(lv_templates) = 0.
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

    CASE prop-name.
      WHEN `tooltip`.
        lv_type = `S`.
      WHEN `class`.
        lv_type = `K`.
      WHEN OTHERS.
        DATA(ls_entry) = vocab( control = node-control
                                kind    = `P`
                                name    = prop-name ).
        IF ls_entry IS INITIAL.
          issue( node = node
                 text = |unknown property "{ prop-name }" - not one of { node-control } in the portable profile at UI5 { z2ui5_cl_agent_gen_vocab=>c_floor }| ).
          RETURN.
        ENDIF.
        lv_type = ls_entry-type.
        lv_info = ls_entry-info.
    ENDCASE.

    IF prop-field IS INITIAL.
      IF prop-format IS NOT INITIAL OR prop-dataset IS NOT INITIAL.
        issue( node = node
               text = |{ prop-name }: format and dataset belong to a binding (field)| ).
        RETURN.
      ENDIF.
      DATA(lv_error) = check_literal( type  = lv_type
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
      READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = prop-dataset. "#EC CI_SORTSEQ
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
    DATA(lv_field_type) = type_of( dataset = lv_dataset
                                   field   = prop-field ).
    DATA(lv_takes) = SWITCH string( lv_type
                                    WHEN `B` THEN `boolean`
                                    WHEN `I` OR `F` THEN `number`
                                    WHEN `C` OR `E` THEN `string` ).
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
        ENDIF.
      WHEN `E`.
        SPLIT info AT `|` INTO TABLE lt_value.
        IF NOT line_exists( lt_value[ table_line = value ] ).
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

    LOOP AT node-t_evt INTO DATA(ls_evt).
      IF vocab( control = node-control
                kind    = `E`
                name    = ls_evt-name ) IS INITIAL.
        issue( node = node
               text = |"{ ls_evt-name }" is no event of { node-control } in the portable profile| ).
        CONTINUE.
      ENDIF.
      READ TABLE mt_event INTO DATA(ls_event) WITH KEY event = ls_evt-event. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.
        DATA(lt_name) = VALUE string_table( ).
        LOOP AT mt_event INTO ls_event.
          INSERT ls_event-event INTO TABLE lt_name.
        ENDLOOP.
        issue( node = node
               text = |{ ls_evt-name } fires "{ ls_evt-event }" - not an event of the app| &&
                      |{ COND #( WHEN lt_name IS NOT INITIAL THEN |; allowed: { concat_lines_of( table = lt_name
                                                                                                sep   = `, ` ) }|
                                 ELSE `; the app allows none` ) }| ).
        CONTINUE.
      ENDIF.
      LOOP AT ls_evt-t_arg INTO DATA(lv_arg).
        IF NOT line_exists( ls_event-t_arg[ table_line = lv_arg ] ).
          issue( node = node
                 text = |the event { ls_evt-event } takes no argument "{ lv_arg }"| &&
                        |{ COND #( WHEN ls_event-t_arg IS NOT INITIAL THEN |; allowed: { concat_lines_of( table = ls_event-t_arg
                                                                                                         sep   = `, ` ) }|
                                   ELSE `; it takes none` ) }| ).
          CONTINUE.
        ENDIF.
        IF node-scope IS NOT INITIAL.
          IF field_of( dataset = node-scope
                       field   = lv_arg ) = abap_false.
            issue( node = node
                   text = |the argument "{ lv_arg }" is no field of { node-scope }, the table of this row| ).
          ENDIF.
        ELSE.
          DATA(lv_found) = abap_false.
          LOOP AT mt_dataset INTO DATA(ls_dataset) WHERE is_table = abap_false. "#EC CI_SORTSEQ
            IF line_exists( ls_dataset-t_field[ name = lv_arg ] ). "#EC CI_SORTSEQ
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

    DATA(lv_off) = find( val  = control
                         sub  = `.`
                         occ  = -1 ).
    lv_ns = control(lv_off).
    local = substring( val = control
                       off = lv_off + 1 ).
    prefix = SWITCH #( lv_ns
                       WHEN `sap.m` THEN ``
                       WHEN `sap.ui.core` THEN `core`
                       WHEN `sap.ui.layout` THEN `layout`
                       WHEN `sap.ui.layout.form` THEN `form`
                       WHEN `sap.tnt` THEN `tnt`
                       ELSE `unknown` ).

  ENDMETHOD.

  METHOD binding_of.

    DATA lv_path TYPE string.

    IF node-scope IS NOT INITIAL AND prop-dataset IS INITIAL.
      lv_path = prop-field.
    ELSE.
      READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = prop-dataset. "#EC CI_SORTSEQ
      lv_path = |{ ls_dataset-path }/{ prop-field }|.
    ENDIF.
    result = SWITCH #( prop-format
                       WHEN `integer` THEN |\{path:'{ lv_path }',type:'sap.ui.model.type.Integer'\}|
                       WHEN `decimal` THEN |\{path:'{ lv_path }',type:'sap.ui.model.type.Float',| &&
                                           |formatOptions:\{minFractionDigits:2,maxFractionDigits:2\}\}|
                       ELSE |\{{ lv_path }\}| ).

  ENDMETHOD.

  METHOD build.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory( ).
    DATA(root) = view->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`        v = `sap.m`
        )->a( n = `xmlns:mvc`    v = `sap.ui.core.mvc`
        )->a( n = `xmlns:core`   v = `sap.ui.core`
        )->a( n = `xmlns:layout` v = `sap.ui.layout`
        )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
        )->a( n = `xmlns:tnt`    v = `sap.tnt`
        )->a( n = `displayBlock` v = `true`
        )->a( n = `height`       v = `100%` ).

    READ TABLE mt_node INTO DATA(ls_root) WITH KEY parent = ``. "#EC CI_SORTSEQ
    build_node( parent = root
                node   = ls_root ).
    xml = view->stringify( ).

    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory( ).
    DATA(dialog) = popup->ele( n = `FragmentDefinition` ns = `core`
        )->a( n = `xmlns`        v = `sap.m`
        )->a( n = `xmlns:core`   v = `sap.ui.core`
        )->a( n = `xmlns:layout` v = `sap.ui.layout`
        )->a( n = `xmlns:form`   v = `sap.ui.layout.form`
        )->a( n = `xmlns:tnt`    v = `sap.tnt`
        )->ele( `Dialog`
            )->a( n = `title`        t = COND #( WHEN mv_title IS NOT INITIAL THEN mv_title ELSE `Generated view` )
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

    ns_of( EXPORTING control = node-control
           IMPORTING prefix  = lv_prefix
                     local   = lv_local ).
    DATA(element) = parent->ele( n  = lv_local
                                 ns = lv_prefix ).

    " attributes first - the builder writes them before the children
    LOOP AT node-t_prop INTO DATA(ls_prop).
      IF ls_prop-field IS NOT INITIAL.
        element->a( n = ls_prop-name
                    v = binding_of( node = node
                                    prop = ls_prop ) ).
      ELSE.
        DATA(ls_entry) = vocab( control = node-control
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
      READ TABLE mt_dataset INTO DATA(ls_dataset) WITH KEY name = node-list_data. "#EC CI_SORTSEQ
      DATA(lv_list_agg) = node-list_agg.
      IF lv_list_agg IS INITIAL.
        READ TABLE mt_vocab INTO DATA(ls_default) WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ
        lv_list_agg = ls_default-name.
      ENDIF.
      DATA(lv_sort) = COND string( WHEN node-group_by IS NOT INITIAL THEN node-group_by ELSE node-sort_by ).
      element->a( n = lv_list_agg
                  v = COND #( WHEN lv_sort IS INITIAL
                              THEN |\{path:'{ ls_dataset-path }',templateShareable:false\}|
                              ELSE |\{path:'{ ls_dataset-path }',templateShareable:false,sorter:\{path:'{ lv_sort }'| &&
                                   |,descending:{ COND #( WHEN node-descending = abap_true THEN `true` ELSE `false` ) }| &&
                                   |{ COND #( WHEN node-group_by IS NOT INITIAL THEN `,group:true` ) }\}\}| ) ).
    ENDIF.

    LOOP AT node-t_evt INTO DATA(ls_evt).
      CLEAR lt_arg.
      LOOP AT ls_evt-t_arg INTO DATA(lv_arg).
        IF node-scope IS NOT INITIAL.
          INSERT |$\{{ lv_arg }\}| INTO TABLE lt_arg.
        ELSE.
          LOOP AT mt_dataset INTO DATA(ls_struct) WHERE is_table = abap_false. "#EC CI_SORTSEQ
            IF line_exists( ls_struct-t_field[ name = lv_arg ] ). "#EC CI_SORTSEQ
              INSERT |$\{{ ls_struct-path }/{ lv_arg }\}| INTO TABLE lt_arg.
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
    LOOP AT mt_node INTO DATA(ls_child) WHERE parent = node-id. "#EC CI_SORTSEQ
      IF NOT line_exists( lt_agg[ table_line = ls_child-agg ] ).
        INSERT ls_child-agg INTO TABLE lt_agg.
      ENDIF.
    ENDLOOP.
    READ TABLE mt_vocab INTO ls_default WITH KEY control = node-control kind = `D`. "#EC CI_SORTSEQ
    DATA(lv_default) = COND string( WHEN sy-subrc = 0 THEN ls_default-name ).
    LOOP AT lt_agg INTO DATA(lv_agg).
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
