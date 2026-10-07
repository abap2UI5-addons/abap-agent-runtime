"! What is on an abap2UI5 screen, as data an agent can act on: the layers
"! of the headless frontend simulator (z2ui5_cl_frontend_simulator,
"! get_layers( )) and the client work of the last response (get_actions( ))
"! -&gt; "agent snapshot v1", the JSON shape docs/agent-snapshot.md of
"! abap2UI5/mcp-server specifies and lib/snapshot.mjs there implements.
"! This class is a port of that module; for the same input it produces the
"! same shape (README, "Snapshot parity" lists the measured differences).
"!
"! Besides the JSON, an instance keeps the INDEX an act needs - which model
"! a field writes into, how a dynamic event argument resolves, whether a
"! cell is editable in a given row - see z2ui5_cl_agent_session.
"!
"! Ids (f1, a1, t1, ...) are assigned in document order and are stable
"! within one snapshot only.
CLASS z2ui5_cl_agent_snapshot DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_version TYPE i VALUE 1.
    CONSTANTS c_max_rows_default TYPE i VALUE 20.
    CONSTANTS c_max_rows_limit TYPE i VALUE 200.

    CONSTANTS:
      "! The two frontend-only wires the client performs itself: closing the
      "! popup or the popover (_event_client( cs_event-popup_close ), written as
      "! eF('CONTROL_GLOBAL','VIEW_SLOTS','destroy','POPUP')). The @ keeps them
      "! apart from every backend event name.
      BEGIN OF cs_frontend_event,
        popup   TYPE string VALUE `@CLOSE_POPUP`,
        popover TYPE string VALUE `@CLOSE_POPOVER`,
      END OF cs_frontend_event.

    CONSTANTS:
      "! The model keys: MAIN (shared by the nested views), POPUP, POPOVER.
      BEGIN OF cs_model,
        main    TYPE string VALUE `MAIN`,
        popup   TYPE string VALUE `POPUP`,
        popover TYPE string VALUE `POPOVER`,
      END OF cs_model.

    TYPES ty_s_val TYPE z2ui5_cl_agent_viewxml=>ty_s_val.

    TYPES:
      "! A value the client changed and has not sent yet - applied to the
      "! model before the screen is analysed, listed under pending.
      BEGIN OF ty_s_pending,
        model_key TYPE string,
        path      TYPE string,
        val       TYPE ty_s_val,
      END OF ty_s_pending.
    TYPES ty_t_pending TYPE STANDARD TABLE OF ty_s_pending WITH EMPTY KEY.

    TYPES:
      "! session/app: what the snapshot names; t_layer: the open layers
      "! (simulator get_layers( )); t_custom: the T_CUSTOM entries of the last
      "! response as raw JSON arrays; max_rows: rows per table (0 - 200).
      BEGIN OF ty_s_input,
        session   TYPE string,
        app       TYPE string,
        t_layer   TYPE z2ui5_cl_frontend_simulator=>ty_t_layer,
        t_custom  TYPE string_table,
        t_pending TYPE ty_t_pending,
        max_rows  TYPE i,
      END OF ty_s_input.

    TYPES:
      BEGIN OF ty_s_choice,
        key  TYPE ty_s_val,
        text TYPE string,
      END OF ty_s_choice.
    TYPES ty_t_choice TYPE STANDARD TABLE OF ty_s_choice WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_field,
        id         TYPE string,
        path       TYPE string,
        name       TYPE string,
        label      TYPE string,
        control    TYPE string,
        kind       TYPE string,
        value      TYPE ty_s_val,
        required   TYPE abap_bool,
        editable   TYPE abap_bool,
        has_values TYPE abap_bool,
        t_value    TYPE ty_t_choice,
        layer      TYPE string,
        model_key  TYPE string,
        doc        TYPE i,
        node       TYPE i,
        secret     TYPE abap_bool,
      END OF ty_s_field.
    TYPES ty_t_field TYPE STANDARD TABLE OF ty_s_field WITH EMPTY KEY.

    TYPES:
      "! An action. t_arg_json: the args of the snapshot as JSON literals;
      "! t_wire_arg: the descriptors behind them; frontend: POPUP / POPOVER for
      "! the two client-side closes; t_choice: the choices of a message box
      "! $action argument. policy is set by the session (allowed / confirm /
      "! forbidden) and written only when it is not allowed. pick: a selection
      "! dialog's confirm (the pick of a row); row_template: the row template
      "! aggregation the wire sits in (rowActionTemplate, ...).
      BEGIN OF ty_s_action,
        id          TYPE string,
        event       TYPE string,
        t_arg_json  TYPE string_table,
        label       TYPE string,
        control     TYPE string,
        trigger     TYPE string,
        enabled     TYPE abap_bool,
        scope       TYPE string,
        table       TYPE string,
        layer       TYPE string,
        policy      TYPE string,
        model_key   TYPE string,
        doc         TYPE i,
        node        TYPE i,
        t_wire_arg  TYPE z2ui5_cl_agent_viewxml=>ty_t_arg,
        frontend    TYPE string,
        has_choices  TYPE abap_bool,
        t_choice     TYPE string_table,
        pick         TYPE abap_bool,
        row_template TYPE string,
      END OF ty_s_action.
    TYPES ty_t_action TYPE STANDARD TABLE OF ty_s_action WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_column,
        name  TYPE string,
        label TYPE string,
      END OF ty_s_column.
    TYPES ty_t_column TYPE STANDARD TABLE OF ty_s_column WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_cell,
        name TYPE string,
        val  TYPE ty_s_val,
      END OF ty_s_cell.
    TYPES ty_t_cell TYPE STANDARD TABLE OF ty_s_cell WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_s_row,
        t_cell TYPE ty_t_cell,
      END OF ty_s_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_s_row WITH EMPTY KEY.

    TYPES:
      "! How one column is read: the cell control, its main property and
      "! binding, and the field kind when the cell is input-like.
      BEGIN OF ty_s_cellspec,
        name           TYPE string,
        node           TYPE i,
        prop           TYPE string,
        has_binding    TYPE abap_bool,
        binding        TYPE z2ui5_cl_agent_viewxml=>ty_s_binding,
        has_field_spec TYPE abap_bool,
        field_kind     TYPE string,
        check_editable TYPE abap_bool,
      END OF ty_s_cellspec.
    TYPES ty_t_cellspec TYPE STANDARD TABLE OF ty_s_cellspec WITH EMPTY KEY.

    TYPES:
      "! A table. The index for a row event's $parameters: node (the table
      "! control), kind (m: sap.m, ui: sap.ui.table), dialog (a selection
      "! dialog), template (the item template of sap.m) and t_cellnode (what
      "! getCells( ) of a row counts: every cell of a ColumnListItem, the
      "! visible columns' templates of a grid table row).
      BEGIN OF ty_s_table,
        id              TYPE string,
        path            TYPE string,
        name            TYPE string,
        label           TYPE string,
        control         TYPE string,
        t_column        TYPE ty_t_column,
        row_count       TYPE i,
        t_row           TYPE ty_t_row,
        truncated       TYPE abap_bool,
        selection_mode  TYPE string,
        t_editable      TYPE string_table,
        layer           TYPE string,
        selection_field TYPE string,
        model_key       TYPE string,
        doc             TYPE i,
        t_cellspec      TYPE ty_t_cellspec,
        node            TYPE i,
        kind            TYPE string,
        dialog          TYPE abap_bool,
        template        TYPE i,
        t_cellnode      TYPE z2ui5_cl_agent_viewxml=>ty_t_int,
      END OF ty_s_table.
    TYPES ty_t_table TYPE STANDARD TABLE OF ty_s_table WITH EMPTY KEY.

    TYPES:
      "! A message - subtitle and description only for the items of a
      "! MessagePopover / MessageView.
      BEGIN OF ty_s_message,
        type        TYPE string,
        text        TYPE string,
        source      TYPE string,
        field       TYPE string,
        subtitle    TYPE string,
        description TYPE string,
      END OF ty_s_message.
    TYPES ty_t_message TYPE STANDARD TABLE OF ty_s_message WITH EMPTY KEY.

    TYPES:
      "! The model paths a text of /texts was read from (absolute, or
      "! relative to its binding context) - kept beside the JSON, not in it
      "! (the snapshot is a contract), so the copilot can mask a text that
      "! shows a sensitive field.
      BEGIN OF ty_s_text_source,
        text   TYPE string,
        t_path TYPE string_table,
      END OF ty_s_text_source.
    TYPES ty_t_text_source TYPE STANDARD TABLE OF ty_s_text_source WITH EMPTY KEY.

    DATA mt_field       TYPE ty_t_field READ-ONLY.
    DATA mt_action      TYPE ty_t_action READ-ONLY.
    DATA mt_table       TYPE ty_t_table READ-ONLY.
    DATA mt_message     TYPE ty_t_message READ-ONLY.
    DATA mt_text        TYPE string_table READ-ONLY.
    DATA mt_text_source TYPE ty_t_text_source READ-ONLY.
    DATA mt_unsupported TYPE string_table READ-ONLY.
    DATA mv_title       TYPE string READ-ONLY.
    DATA mv_layer       TYPE string READ-ONLY.
    DATA mv_session     TYPE string READ-ONLY.
    DATA mv_app         TYPE string READ-ONLY.

    "! Analyse the screen - the instance holds the snapshot and its index.
    CLASS-METHODS create
      IMPORTING
        is_input      TYPE ty_s_input
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_snapshot.

    "! The snapshot v1 as JSON.
    METHODS get_json
      RETURNING
        VALUE(result) TYPE string.

    "! Mark an action allowed / confirm / forbidden (see ty_s_action).
    METHODS set_policy
      IMPORTING
        id     TYPE clike
        policy TYPE clike.

    "! The model value at an absolute path (or a path relative to a row of
    "! a table) of one model - pending values applied.
    METHODS model_value
      IMPORTING
        model_key     TYPE clike
        path          TYPE clike
        table_id      TYPE clike OPTIONAL
        row           TYPE i     DEFAULT -1
      RETURNING
        VALUE(result) TYPE ty_s_val.

    "! Whether a field holds a password: a password input (type Password),
    "! or any other field bound to the same model path as one - its value is
    "! never written to the audit log.
    METHODS is_secret
      IMPORTING
        field_id      TYPE clike
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The number of rows of a table of this snapshot.
    METHODS table_rows
      IMPORTING
        table_id      TYPE clike
      RETURNING
        VALUE(result) TYPE i.

    "! Whether the cell column is editable in the given row (0-based).
    METHODS cell_editable
      IMPORTING
        table_id      TYPE clike
        column        TYPE clike
        row           TYPE i
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The value of a property of the control an action sits on, resolved
    "! in the given row ($source:&lt;prop&gt;); undefined when it cannot be read.
    METHODS source_value
      IMPORTING
        action_id     TYPE clike
        prop          TYPE clike
        row           TYPE i DEFAULT -1
      RETURNING
        VALUE(result) TYPE ty_s_val.

    "! The value of a property of a control of a table's template (the item
    "! template or a cell, by node), resolved in the given row; undefined
    "! when it cannot be read - what get&lt;Prop&gt;( ) of a row event's item
    "! answers.
    METHODS template_value
      IMPORTING
        table_id      TYPE clike
        node          TYPE i
        prop          TYPE clike
        row           TYPE i
      RETURNING
        VALUE(result) TYPE ty_s_val.

    "! A UI5 model path ("/T_TAB/0/NAME") as a path of the model tree
    "! (array indexes are 1-based there); empty when it cannot be reached.
    METHODS tree_path
      IMPORTING
        model_key     TYPE clike
        path          TYPE clike
        base          TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    "! "/MS_HEAD/KUNNR" -&gt; "MS_HEAD-KUNNR"; the old /XX/ prefix is dropped.
    CLASS-METHODS name_of_path
      IMPORTING
        path          TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! The model paths a binding reads - a path, the parts of a composite
    "! binding, the references of an expression (the copilot masks a cell
    "! or a text by them).
    CLASS-METHODS binding_paths
      IMPORTING
        binding       TYPE z2ui5_cl_agent_viewxml=>ty_s_binding
      RETURNING
        VALUE(result) TYPE string_table.

    "! binding_paths( ) of a raw attribute value.
    CLASS-METHODS text_paths
      IMPORTING
        raw           TYPE string
      RETURNING
        VALUE(result) TYPE string_table.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CONSTANTS c_max_texts TYPE i VALUE 30.
    CONSTANTS c_max_unsupported TYPE i VALUE 30.
    CONSTANTS c_max_values TYPE i VALUE 100.
    CONSTANTS c_max_item_messages TYPE i VALUE 50.

    TYPES:
      BEGIN OF ty_s_doc,
        layer     TYPE string,
        slot      TYPE string,
        model_key TYPE string,
        t_node    TYPE z2ui5_cl_agent_viewxml=>ty_t_node,
        t_lblfor  TYPE z2ui5_cl_agent_viewxml=>ty_t_attr,
        t_lblreq  TYPE string_table,
      END OF ty_s_doc.
    TYPES ty_t_doc TYPE STANDARD TABLE OF ty_s_doc WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_model,
        key  TYPE string,
        json TYPE REF TO z2ui5_if_ajson,
      END OF ty_s_model.
    TYPES ty_t_model TYPE STANDARD TABLE OF ty_s_model WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_label,
        text     TYPE string,
        required TYPE abap_bool,
        uses     TYPE i,
      END OF ty_s_label.
    TYPES ty_t_label TYPE STANDARD TABLE OF ty_s_label WITH EMPTY KEY.

    TYPES:
      "! The walk context. row_table: the table id inside a row template
      "! (row_template: which aggregation of the grid table it is);
      "! row: the tree path of the row data values resolve against (the
      "! editable probe of a cell), empty for none.
      BEGIN OF ty_s_ctx,
        doc          TYPE i,
        layer        TYPE string,
        model_key    TYPE string,
        row_table    TYPE string,
        row_template TYPE string,
        row       TYPE string,
        label     TYPE i,
        t_where   TYPE string_table,
      END OF ty_s_ctx.

    TYPES:
      BEGIN OF ty_s_spec,
        found      TYPE abap_bool,
        t_prop     TYPE string_table,
        kind       TYPE string,
        text_label TYPE abap_bool,
        items      TYPE string,
      END OF ty_s_spec.

    TYPES:
      BEGIN OF ty_s_mgr_msg,
        type   TYPE string,
        text   TYPE string,
        target TYPE string,
      END OF ty_s_mgr_msg.
    TYPES ty_t_mgr_msg TYPE STANDARD TABLE OF ty_s_mgr_msg WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_title,
        layer TYPE string,
        title TYPE string,
      END OF ty_s_title.
    TYPES ty_t_title TYPE STANDARD TABLE OF ty_s_title WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_cellsrc,
        node    TYPE i,
        prop    TYPE string,
        header  TYPE string,
        visible TYPE abap_bool,
      END OF ty_s_cellsrc.
    TYPES ty_t_cellsrc TYPE STANDARD TABLE OF ty_s_cellsrc WITH EMPTY KEY.

    DATA ms_input   TYPE ty_s_input.
    DATA mv_rows    TYPE i.
    DATA mt_doc     TYPE ty_t_doc.
    DATA mt_model   TYPE ty_t_model.
    DATA mt_label   TYPE ty_t_label.
    DATA mt_title   TYPE ty_t_title.
    DATA mt_mgr_msg TYPE ty_t_mgr_msg.
    DATA mt_pending TYPE string_table.

    METHODS analyze.

    METHODS model_init.

    METHODS model_get
      IMPORTING
        model_key     TYPE string
        path          TYPE string
        base          TYPE string OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_s_val.

    METHODS model_json
      IMPORTING
        model_key     TYPE string
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_if_ajson.

    METHODS custom_work.

    METHODS note
      IMPORTING
        val TYPE string.

    METHODS add_text
      IMPORTING
        val    TYPE string
        t_path TYPE string_table OPTIONAL.

    METHODS node
      IMPORTING
        doc           TYPE i
        id            TYPE i
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_s_node.

    METHODS label_new
      IMPORTING
        text          TYPE string
        required      TYPE abap_bool
      RETURNING
        VALUE(result) TYPE i.

    METHODS resolve_ref
      IMPORTING
        ref           TYPE string
        ctx           TYPE ty_s_ctx
        row           TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_val.

    METHODS resolve
      IMPORTING
        raw           TYPE string
        ctx           TYPE ty_s_ctx
        row           TYPE string OPTIONAL
      EXPORTING
        binding       TYPE z2ui5_cl_agent_viewxml=>ty_s_binding
      RETURNING
        VALUE(result) TYPE ty_s_val.

    METHODS bool
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        name          TYPE string
        ctx           TYPE ty_s_ctx
        row           TYPE string OPTIONAL
        default       TYPE abap_bool
      RETURNING
        VALUE(result) TYPE abap_bool.

    METHODS text_of
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        name          TYPE string
        ctx           TYPE ty_s_ctx
        row           TYPE string OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    METHODS text_of_raw
      IMPORTING
        raw           TYPE string
        ctx           TYPE ty_s_ctx
        row           TYPE string OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    METHODS walk_children
      IMPORTING
        t_child TYPE z2ui5_cl_agent_viewxml=>ty_t_int
        ctx     TYPE ty_s_ctx.

    METHODS walk
      IMPORTING
        id  TYPE i
        ctx TYPE ty_s_ctx.

    METHODS field
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
        name          TYPE string
        spec          TYPE ty_s_spec
      RETURNING
        VALUE(result) TYPE i.

    METHODS label_of
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
        spec          TYPE ty_s_spec
      RETURNING
        VALUE(result) TYPE string.

    METHODS label_for
      IMPORTING
        ctx           TYPE ty_s_ctx
        id            TYPE string
      EXPORTING
        found         TYPE abap_bool
        required      TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.

    METHODS choice_values
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
        spec          TYPE ty_s_spec
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_t_choice.

    METHODS item_controls
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
        agg           TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    METHODS wires
      IMPORTING
        node     TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx      TYPE ty_s_ctx
        name     TYPE string
        field    TYPE i      OPTIONAL
        only     TYPE string    OPTIONAL
        override TYPE string    OPTIONAL
        pick     TYPE abap_bool OPTIONAL.

    METHODS action_label
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
        name          TYPE string
        trigger       TYPE string
        field         TYPE i
      RETURNING
        VALUE(result) TYPE string.

    METHODS push_action
      IMPORTING
        action TYPE ty_s_action.

    METHODS message_manager
      IMPORTING
        node TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx  TYPE ty_s_ctx.

    METHODS message_list
      IMPORTING
        node TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx  TYPE ty_s_ctx
        name TYPE string.

    METHODS table
      IMPORTING
        node   TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx    TYPE ty_s_ctx
        name   TYPE string
        agg    TYPE string
        kind   TYPE string
        dialog TYPE abap_bool.

    METHODS walk_template
      IMPORTING
        id  TYPE i
        ctx TYPE ty_s_ctx.

    METHODS column_header
      IMPORTING
        ctx           TYPE ty_s_ctx
        col           TYPE i
      RETURNING
        VALUE(result) TYPE string.

    METHODS header_title
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        ctx           TYPE ty_s_ctx
      RETURNING
        VALUE(result) TYPE string.

    METHODS find_first
      IMPORTING
        doc           TYPE i
        id            TYPE i
        control       TYPE string
      RETURNING
        VALUE(result) TYPE i.

    METHODS descendants
      IMPORTING
        doc           TYPE i
        id            TYPE i
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    METHODS main_prop
      IMPORTING
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
      RETURNING
        VALUE(result) TYPE string.

    METHODS child_agg
      IMPORTING
        doc           TYPE i
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        local         TYPE string
      RETURNING
        VALUE(result) TYPE i.

    METHODS controls_of
      IMPORTING
        doc           TYPE i
        t_child       TYPE z2ui5_cl_agent_viewxml=>ty_t_int
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    METHODS collect_label_for
      IMPORTING
        doc TYPE i.

    METHODS cell_ok
      IMPORTING
        ctx           TYPE ty_s_ctx
        node          TYPE z2ui5_cl_agent_viewxml=>ty_s_node
        row           TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    METHODS where_text
      IMPORTING
        ctx           TYPE ty_s_ctx
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS field_spec
      IMPORTING
        name          TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_spec.

    CLASS-METHODS table_spec
      IMPORTING
        name          TYPE string
      EXPORTING
        agg           TYPE string
        kind          TYPE string
        dialog        TYPE abap_bool
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS text_props
      IMPORTING
        name          TYPE string
      RETURNING
        VALUE(result) TYPE string_table.

    CLASS-METHODS kind_from_type
      IMPORTING
        type          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS message_type
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE string.

    "! The source of the items of a sap.m message list, empty for any other control.
    CLASS-METHODS message_source
      IMPORTING
        name          TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS icon_name
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS strip_tags
      IMPORTING
        val           TYPE string
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS starts_sap
      IMPORTING
        ns            TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS ends_with
      IMPORTING
        val           TYPE string
        suffix        TYPE string
      RETURNING
        VALUE(result) TYPE abap_bool.

    CLASS-METHODS layer_of_slot
      IMPORTING
        slot          TYPE string
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_agent_snapshot IMPLEMENTATION.

  METHOD create.

    result = NEW #( ).
    result->ms_input = is_input.
    result->mv_rows = is_input-max_rows.
    IF result->mv_rows < 0.
      result->mv_rows = 0.
    ELSEIF result->mv_rows > c_max_rows_limit.
      result->mv_rows = c_max_rows_limit.
    ENDIF.
    result->mv_session = is_input-session.
    result->mv_app = is_input-app.
    result->analyze( ).

  ENDMETHOD.

  METHOD name_of_path.

    SPLIT CONV string( path ) AT `/` INTO TABLE DATA(lt_seg).
    DELETE lt_seg WHERE table_line IS INITIAL.
    " read ahead: the 7.02 downport hoists a table expression out of the
    " condition, and "/" has no first segment
    DATA(lv_first) = VALUE string( lt_seg[ 1 ] OPTIONAL ).
    IF lines( lt_seg ) > 1 AND lv_first = `XX`.
      DELETE lt_seg INDEX 1.
    ENDIF.
    result = concat_lines_of( table = lt_seg
                              sep   = `-` ).

  ENDMETHOD.

  METHOD layer_of_slot.

    result = SWITCH #( slot
                       WHEN z2ui5_if_client=>cs_view-popup   THEN `popup`
                       WHEN z2ui5_if_client=>cs_view-popover THEN `popover`
                       ELSE `main` ).

  ENDMETHOD.

  METHOD model_init.

    " MAIN and the nested views share one model; popup and popover own a copy
    LOOP AT ms_input-t_layer INTO DATA(ls_layer).
      DATA(lv_key) = SWITCH string( ls_layer-layer
                                    WHEN z2ui5_if_client=>cs_view-popup   THEN cs_model-popup
                                    WHEN z2ui5_if_client=>cs_view-popover THEN cs_model-popover
                                    ELSE cs_model-main ).
      IF line_exists( mt_model[ key = lv_key ] ). "#EC CI_SORTSEQ
        CONTINUE.
      ENDIF.
      DATA(lv_model) = ls_layer-model.
      IF lv_model IS INITIAL.
        lv_model = `{}`.
      ENDIF.
      TRY.
          DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( iv_json            = lv_model
                                                                      iv_keep_item_order = abap_true ) ).
        CATCH cx_root.
          lo_json = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( iv_keep_item_order = abap_true ) ).
      ENDTRY.
      INSERT VALUE #( key  = lv_key
                      json = lo_json ) INTO TABLE mt_model.
    ENDLOOP.

    " the pending edits are what the client shows - applied before reading
    LOOP AT ms_input-t_pending INTO DATA(ls_pending).
      DATA(lo_model) = model_json( ls_pending-model_key ).
      IF lo_model IS NOT BOUND.
        CONTINUE.
      ENDIF.
      DATA(lv_tree) = tree_path( model_key = ls_pending-model_key
                                 path      = ls_pending-path ).
      IF lv_tree IS INITIAL.
        CONTINUE.
      ENDIF.
      TRY.
          CASE ls_pending-val-kind.
            WHEN z2ui5_cl_agent_viewxml=>cs_kind-string.
              lo_model->set( iv_path         = lv_tree
                             iv_val          = ls_pending-val-str
                             iv_ignore_empty = abap_false
                             iv_node_type    = z2ui5_if_ajson_types=>node_type-string ).
            WHEN z2ui5_cl_agent_viewxml=>cs_kind-number.
              lo_model->set( iv_path      = lv_tree
                             iv_val       = ls_pending-val-str
                             iv_node_type = z2ui5_if_ajson_types=>node_type-number ).
            WHEN z2ui5_cl_agent_viewxml=>cs_kind-boolean.
              lo_model->set( iv_path      = lv_tree
                             iv_val       = ls_pending-val-str
                             iv_node_type = z2ui5_if_ajson_types=>node_type-boolean ).
            WHEN z2ui5_cl_agent_viewxml=>cs_kind-object OR z2ui5_cl_agent_viewxml=>cs_kind-array.
              lo_model->set( iv_path = lv_tree
                             iv_val  = z2ui5_cl_ajson=>parse( ls_pending-val-json ) ).
            WHEN OTHERS.
              lo_model->set_null( lv_tree ).
          ENDCASE.
          INSERT ls_pending-path INTO TABLE mt_pending.
        CATCH cx_root ##NO_HANDLER.
          " a value the tree refuses stays out of the screen - the session
          " validated it against the snapshot it was typed into
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.

  METHOD model_json.

    READ TABLE mt_model INTO DATA(ls_model) WITH KEY key = model_key. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_model-json.
    ENDIF.

  ENDMETHOD.

  METHOD tree_path.

    DATA lv_model_key TYPE string.

    lv_model_key = model_key.
    DATA(lo_json) = model_json( lv_model_key ).
    IF lo_json IS NOT BOUND.
      RETURN.
    ENDIF.

    SPLIT CONV string( path ) AT `/` INTO TABLE DATA(lt_seg).
    DELETE lt_seg WHERE table_line IS INITIAL.
    DATA(lv_cur) = CONV string( base ).
    LOOP AT lt_seg INTO DATA(lv_seg).
      DATA(lv_type) = lo_json->get_node_type( COND #( WHEN lv_cur IS INITIAL THEN `/` ELSE lv_cur ) ).
      IF lv_type = z2ui5_if_ajson_types=>node_type-array.
        IF lv_seg CN `0123456789`.
          RETURN.
        ENDIF.
        lv_seg = |{ CONV i( lv_seg ) + 1 }|.
      ELSEIF lv_type <> z2ui5_if_ajson_types=>node_type-object.
        RETURN.
      ENDIF.
      lv_cur = |{ lv_cur }/{ lv_seg }|.
    ENDLOOP.
    result = COND #( WHEN lv_cur IS INITIAL THEN `/` ELSE lv_cur ).

  ENDMETHOD.

  METHOD model_get.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
    DATA(lo_json) = model_json( model_key ).
    IF lo_json IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA(lv_tree) = tree_path( model_key = model_key
                               path      = path
                               base      = base ).
    IF lv_tree IS INITIAL.
      RETURN.
    ENDIF.
    CASE lo_json->get_node_type( lv_tree ).
      WHEN z2ui5_if_ajson_types=>node_type-string.
        result = z2ui5_cl_agent_viewxml=>val_string( lo_json->get( lv_tree ) ).
      WHEN z2ui5_if_ajson_types=>node_type-number.
        result = z2ui5_cl_agent_viewxml=>val_number( lo_json->get( lv_tree ) ).
      WHEN z2ui5_if_ajson_types=>node_type-boolean.
        result = z2ui5_cl_agent_viewxml=>val_boolean( lo_json->get_boolean( lv_tree ) ).
      WHEN z2ui5_if_ajson_types=>node_type-null.
        result-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
      WHEN z2ui5_if_ajson_types=>node_type-object OR z2ui5_if_ajson_types=>node_type-array.
        result-kind = COND #( WHEN lo_json->get_node_type( lv_tree ) = z2ui5_if_ajson_types=>node_type-array
                              THEN z2ui5_cl_agent_viewxml=>cs_kind-array
                              ELSE z2ui5_cl_agent_viewxml=>cs_kind-object ).
        TRY.
            result-json = lo_json->slice( lv_tree )->stringify( ).
          CATCH cx_root.
            result-json = COND #( WHEN result-kind = z2ui5_cl_agent_viewxml=>cs_kind-array THEN `[]` ELSE `{}` ).
        ENDTRY.
        result-num = lines( lo_json->members( lv_tree ) ).
    ENDCASE.

  ENDMETHOD.

  METHOD model_value.

    DATA lv_model_key TYPE string.
    DATA lv_base TYPE string.

    lv_model_key = model_key.
    IF table_id IS NOT INITIAL AND row >= 0.
      READ TABLE mt_table INTO DATA(ls_table) WITH KEY id = table_id. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        lv_base = tree_path( model_key = ls_table-model_key
                             path      = |{ ls_table-path }/{ row }| ).
        lv_model_key = ls_table-model_key.
        IF lv_base IS INITIAL.
          result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.
    result = model_get( model_key = lv_model_key
                        path      = CONV #( path )
                        base      = lv_base ).

  ENDMETHOD.

  METHOD is_secret.

    READ TABLE mt_field INTO DATA(ls_field) WITH KEY id = field_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    " a Text or a second input showing the password's path shows the password
    LOOP AT mt_field TRANSPORTING NO FIELDS
         WHERE model_key = ls_field-model_key AND path = ls_field-path AND secret = abap_true. "#EC CI_SORTSEQ
      result = abap_true.
      RETURN.
    ENDLOOP.

  ENDMETHOD.

  METHOD table_rows.

    READ TABLE mt_table INTO DATA(ls_table) WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_table-row_count.
    ENDIF.

  ENDMETHOD.

  METHOD node.

    READ TABLE mt_doc INDEX doc INTO DATA(ls_doc).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE ls_doc-t_node INDEX id INTO result.

  ENDMETHOD.

  METHOD note.

    IF line_exists( mt_unsupported[ table_line = val ] ) OR lines( mt_unsupported ) >= c_max_unsupported. "#EC CI_SORTSEQ
      RETURN.
    ENDIF.
    INSERT val INTO TABLE mt_unsupported.

  ENDMETHOD.

  METHOD text_paths.

    result = binding_paths( z2ui5_cl_agent_viewxml=>parse_binding( raw ) ).

  ENDMETHOD.

  METHOD binding_paths.

    DATA(ls_binding) = binding.
    CASE ls_binding-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-literal.
        RETURN.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-path.
        INSERT ls_binding-path INTO TABLE result.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-expression.
        result = z2ui5_cl_agent_viewxml=>expression_refs( ls_binding-expression ).
      WHEN OTHERS.
        LOOP AT ls_binding-t_part INTO DATA(ls_part) WHERE is_path = abap_true. "#EC CI_SORTSEQ
          INSERT ls_part-path INTO TABLE result.
        ENDLOOP.
    ENDCASE.

  ENDMETHOD.

  METHOD add_text.

    DATA(lv_text) = z2ui5_cl_agent_viewxml=>clip( val ).
    IF lv_text IS INITIAL OR line_exists( mt_text[ table_line = lv_text ] ) OR lines( mt_text ) >= c_max_texts. "#EC CI_SORTSEQ
      RETURN.
    ENDIF.
    INSERT lv_text INTO TABLE mt_text.
    IF t_path IS NOT INITIAL.
      INSERT VALUE #( text   = lv_text
                      t_path = t_path ) INTO TABLE mt_text_source.
    ENDIF.

  ENDMETHOD.

  METHOD label_new.

    INSERT VALUE #( text     = text
                    required = required ) INTO TABLE mt_label.
    result = lines( mt_label ).

  ENDMETHOD.

  METHOD where_text.

    DATA lt_last TYPE string_table.

    DATA(lv_from) = lines( ctx-t_where ) - 2.
    IF lv_from < 1.
      lv_from = 1.
    ENDIF.
    LOOP AT ctx-t_where INTO DATA(lv_where) FROM lv_from.
      INSERT lv_where INTO TABLE lt_last.
    ENDLOOP.
    result = concat_lines_of( table = lt_last
                              sep   = ` > ` ).

  ENDMETHOD.

  METHOD analyze.

    DATA lt_slot TYPE string_table.
    DATA lt_text TYPE string_table.

    model_init( ).

    " which layers are described: a popup (Dialog) is modal - while one is
    " open only the popup and a popover on top of it are; a popover is not
    " modal, the page stays described beside it
    DATA(lv_popup) = xsdbool( line_exists( ms_input-t_layer[ layer = z2ui5_if_client=>cs_view-popup ] ) ). "#EC CI_SORTSEQ
    DATA(lv_popover) = xsdbool( line_exists( ms_input-t_layer[ layer = z2ui5_if_client=>cs_view-popover ] ) ). "#EC CI_SORTSEQ
    IF lv_popup = abap_true.
      INSERT z2ui5_if_client=>cs_view-popup INTO TABLE lt_slot.
    ELSE.
      INSERT z2ui5_if_client=>cs_view-main INTO TABLE lt_slot.
      INSERT z2ui5_if_client=>cs_view-nested INTO TABLE lt_slot.
      INSERT z2ui5_if_client=>cs_view-nested2 INTO TABLE lt_slot.
    ENDIF.
    IF lv_popover = abap_true.
      INSERT z2ui5_if_client=>cs_view-popover INTO TABLE lt_slot.
    ENDIF.
    mv_layer = COND #( WHEN lv_popover = abap_true THEN `popover`
                       WHEN lv_popup = abap_true THEN `popup`
                       ELSE `main` ).

    LOOP AT lt_slot INTO DATA(lv_slot).
      READ TABLE ms_input-t_layer INTO DATA(ls_layer) WITH KEY layer = lv_slot. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(ls_doc) = VALUE ty_s_doc( layer     = layer_of_slot( lv_slot )
                                     slot      = lv_slot
                                     model_key = SWITCH #( lv_slot
                                                           WHEN z2ui5_if_client=>cs_view-popup   THEN cs_model-popup
                                                           WHEN z2ui5_if_client=>cs_view-popover THEN cs_model-popover
                                                           ELSE cs_model-main )
                                     t_node    = z2ui5_cl_agent_viewxml=>parse_xml( ls_layer-xml ) ).
      INSERT ls_doc INTO TABLE mt_doc.
      DATA(lv_doc) = lines( mt_doc ).
      collect_label_for( lv_doc ).
      DATA(ls_ctx) = VALUE ty_s_ctx( doc       = lv_doc
                                     layer     = ls_doc-layer
                                     model_key = ls_doc-model_key ).
      walk_children( t_child = ls_doc-t_node[ 1 ]-t_child
                     ctx     = ls_ctx ).
    ENDLOOP.

    " the app's message table (z2ui5.cc.MessageManager): a TARGET that is a
    " field's path points at that field - resolved once every field is known
    LOOP AT mt_mgr_msg INTO DATA(ls_mgr).
      DATA(ls_msg) = VALUE ty_s_message( type   = ls_mgr-type
                                         text   = ls_mgr-text
                                         source = COND #( WHEN ls_mgr-target IS NOT INITIAL THEN `field` ELSE `model` ) ).
      IF ls_mgr-target IS NOT INITIAL.
        READ TABLE mt_field INTO DATA(ls_field) WITH KEY path = ls_mgr-target. "#EC CI_SORTSEQ
        ls_msg-field = COND #( WHEN sy-subrc = 0 THEN ls_field-id ELSE ls_mgr-target ).
      ENDIF.
      INSERT ls_msg INTO TABLE mt_message.
    ENDLOOP.

    custom_work( ).

    READ TABLE mt_title INTO DATA(ls_title) WITH KEY layer = mv_layer. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      mv_title = ls_title-title.
    ELSE.
      READ TABLE mt_title INTO ls_title WITH KEY layer = `main`. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        mv_title = ls_title-title.
      ENDIF.
    ENDIF.

    " the title and the table labels are not repeated as texts
    LOOP AT mt_text INTO DATA(lv_text).
      IF lv_text = mv_title OR line_exists( mt_table[ label = lv_text ] ). "#EC CI_SORTSEQ
        CONTINUE.
      ENDIF.
      INSERT lv_text INTO TABLE lt_text.
    ENDLOOP.
    mt_text = lt_text.

  ENDMETHOD.

  METHOD custom_work.

    DATA lv_onclose TYPE string.
    DATA lv_benign TYPE abap_bool.

    " what the last response asked the client to do besides the views
    LOOP AT ms_input-t_custom INTO DATA(lv_raw).
      TRY.
          DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( iv_json            = lv_raw
                                                                      iv_keep_item_order = abap_true ) ).
        CATCH cx_root.
          CONTINUE.
      ENDTRY.
      IF lo_json->get_node_type( `/` ) <> z2ui5_if_ajson_types=>node_type-array.
        CONTINUE.
      ENDIF.
      DATA(lv_base) = 0.
      IF lo_json->get_string( `/1` ) = z2ui5_if_client=>cs_event-control_global.
        lv_base = 1.
      ENDIF.
      DATA(lv_count) = lines( lo_json->members( `/` ) ).
      DATA(lv_target) = lo_json->get_string( |/{ lv_base + 1 }| ).
      DATA(lv_method) = lo_json->get_string( |/{ lv_base + 2 }| ).
      DATA(lv_method_type) = lo_json->get_node_type( |/{ lv_base + 2 }| ).
      DATA(lv_text_path) = |/{ lv_base + 3 }|.
      DATA(lv_text_type) = lo_json->get_node_type( lv_text_path ).
      DATA(lv_text) = COND string( WHEN lv_text_type = z2ui5_if_ajson_types=>node_type-object
                                     OR lv_text_type = z2ui5_if_ajson_types=>node_type-array
                                   THEN lo_json->slice( lv_text_path )->stringify( )
                                   WHEN lv_text_type = z2ui5_if_ajson_types=>node_type-null
                                     OR lv_text_type IS INITIAL
                                   THEN ``
                                   ELSE lo_json->get( lv_text_path ) ).
      DATA(lv_opt) = |/{ lv_base + 4 }|.
      DATA(lv_has_opt) = xsdbool( lo_json->get_node_type( lv_opt ) = z2ui5_if_ajson_types=>node_type-object ).
      CLEAR lv_onclose.
      lv_benign = abap_false.
      IF lv_has_opt = abap_true AND lo_json->get_node_type( |{ lv_opt }/onClose| ) = z2ui5_if_ajson_types=>node_type-string.
        lv_onclose = lo_json->get( |{ lv_opt }/onClose| ).
      ENDIF.

      CASE lv_target.

        WHEN `MESSAGE_TOAST`.
          INSERT VALUE #( type   = `info`
                          text   = z2ui5_cl_agent_viewxml=>clip( val = lv_text
                                                                 len = 1000 )
                          source = `toast` ) INTO TABLE mt_message.
          IF lv_onclose IS NOT INITIAL.
            push_action( VALUE #( event   = lv_onclose
                                  label   = `toast closed`
                                  control = `sap.m.MessageToast`
                                  trigger = `close`
                                  enabled = abap_true
                                  scope   = `screen`
                                  layer   = mv_layer ) ).
          ENDIF.

        WHEN `MESSAGE_BOX`.
          INSERT VALUE #( type   = SWITCH #( lv_method
                                             WHEN `error`       THEN `error`
                                             WHEN `warning`     THEN `warning`
                                             WHEN `success`     THEN `success`
                                             ELSE `info` )
                          text   = z2ui5_cl_agent_viewxml=>clip( val = lv_text
                                                                 len = 1000 )
                          source = `box` ) INTO TABLE mt_message.
          IF lv_onclose IS NOT INITIAL.
            DATA(lt_choice) = VALUE string_table( ).
            IF lo_json->get_node_type( |{ lv_opt }/actions| ) = z2ui5_if_ajson_types=>node_type-array.
              DATA(lv_n) = lines( lo_json->members( |{ lv_opt }/actions| ) ).
              DO lv_n TIMES.
                INSERT lo_json->get( |{ lv_opt }/actions/{ sy-index }| ) INTO TABLE lt_choice.
              ENDDO.
            ENDIF.
            IF lt_choice IS INITIAL.
              lt_choice = COND #( WHEN lv_method = `confirm`
                                  THEN VALUE #( ( `OK` ) ( `CANCEL` ) )
                                  ELSE VALUE #( ( `OK` ) ) ).
            ENDIF.
            push_action( VALUE #( event       = lv_onclose
                                  t_arg_json  = VALUE #( ( `"$action"` ) )
                                  label       = |close message box ({ concat_lines_of( table = lt_choice
                                                                                       sep   = ` | ` ) })|
                                  control     = `sap.m.MessageBox`
                                  trigger     = `close`
                                  enabled     = abap_true
                                  scope       = `screen`
                                  layer       = mv_layer
                                  t_wire_arg  = VALUE #( ( kind = `action` describe = `$action` ) )
                                  has_choices = abap_true
                                  t_choice    = lt_choice ) ).
          ENDIF.

        WHEN `START_TIMER`.
          IF lv_method_type = z2ui5_if_ajson_types=>node_type-string AND lv_method IS NOT INITIAL.
            DATA(ls_ms) = z2ui5_cl_agent_viewxml=>describe_arg( lv_text ).
            DATA(lv_ms) = COND string( WHEN ls_ms-static = abap_true AND ls_ms-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number
                                         AND ls_ms-val-num <> 0
                                       THEN ls_ms-val-str
                                       ELSE `0` ).
            push_action( VALUE #( event   = lv_method
                                  label   = |timer ({ lv_ms } ms)|
                                  control = `timer`
                                  trigger = `timer`
                                  enabled = abap_true
                                  scope   = `screen`
                                  layer   = mv_layer ) ).
            CONTINUE.
          ENDIF.

        WHEN `SET_FOCUS` OR `SCROLL_TO` OR `SCROLL_INTO_VIEW` OR `SET_SIZE_LIMIT` OR `SET_TITLE` OR `SET_FAVICON`
          OR `BUSY_INDICATOR` OR `ROUTER` OR `ICON_POOL` OR `THEMING` OR `FORMATTING` OR `POPUP` OR `SET_TITLE_LAUNCHPAD`.
          lv_benign = abap_true.

      ENDCASE.

      IF lv_target = `MESSAGE_TOAST` OR lv_target = `MESSAGE_BOX` OR lv_benign = abap_true.
        CONTINUE.
      ENDIF.

      " anything else runs in the browser only - listed, not performed
      DATA(lt_part) = VALUE string_table( ).
      DATA(lv_index) = lv_base + 1.
      WHILE lv_index <= lv_count.
        DATA(lv_type) = lo_json->get_node_type( |/{ lv_index }| ).
        IF lv_type = z2ui5_if_ajson_types=>node_type-object OR lv_type = z2ui5_if_ajson_types=>node_type-array.
          INSERT lo_json->slice( |/{ lv_index }| )->stringify( ) INTO TABLE lt_part.
        ELSEIF lv_type = z2ui5_if_ajson_types=>node_type-null.
          INSERT `null` INTO TABLE lt_part.
        ELSE.
          INSERT lo_json->get( |/{ lv_index }| ) INTO TABLE lt_part.
        ENDIF.
        lv_index = lv_index + 1.
      ENDWHILE.
      note( |frontend action { z2ui5_cl_agent_viewxml=>clip( val = concat_lines_of( table = lt_part
                                                                                    sep   = ` ` )
                                                             len = 120 ) } (runs in the browser only, not performed)| ).
    ENDLOOP.

  ENDMETHOD.

  METHOD collect_label_for.

    " a Label with labelFor names the control of that id, wherever it is
    READ TABLE mt_doc INDEX doc REFERENCE INTO DATA(lr_doc).
    LOOP AT lr_doc->t_node INTO DATA(ls_node).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true
          OR z2ui5_cl_agent_viewxml=>control_name( ls_node ) <> `sap.m.Label`.
        CONTINUE.
      ENDIF.
      DATA(lv_for) = z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                  name = `labelFor` ).
      IF lv_for IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(ls_b) = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                                                         name = `text` ) ).
      DATA(lv_text) = ``.
      IF ls_b-kind = z2ui5_cl_agent_viewxml=>cs_binding-literal.
        lv_text = ls_b-value.
      ELSEIF ls_b-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_b-relative = abap_false AND ls_b-model IS INITIAL.
        DATA(ls_val) = model_get( model_key = lr_doc->model_key
                                  path      = ls_b-path ).
        IF ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-undefined AND ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null.
          lv_text = z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).
        ENDIF.
      ENDIF.
      DELETE lr_doc->t_lblfor WHERE name = lv_for.        "#EC CI_SORTSEQ
      DELETE lr_doc->t_lblreq WHERE table_line = lv_for.  "#EC CI_SORTSEQ
      INSERT VALUE #( name  = lv_for
                      value = lv_text ) INTO TABLE lr_doc->t_lblfor.
      IF z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                       name = `required` ) = `true`.
        INSERT lv_for INTO TABLE lr_doc->t_lblreq.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD label_for.

    found = abap_false.
    READ TABLE mt_doc INDEX ctx-doc INTO DATA(ls_doc).
    IF sy-subrc <> 0 OR id IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE ls_doc-t_lblfor INTO DATA(ls_for) WITH KEY name = id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    found = abap_true.
    result = ls_for-value.
    required = xsdbool( line_exists( ls_doc-t_lblreq[ table_line = id ] ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD resolve_ref.

    DATA(lv_ref) = condense( ref ).
    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
    " a named model
    DATA(lv_gt) = find( val = lv_ref
                        sub = `>` ).
    IF lv_gt > 0.
      DATA(lv_name) = substring( val = lv_ref
                                 len = lv_gt ).
      IF lv_name(1) CA `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`
          AND lv_name CO `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-`.
        RETURN.
      ENDIF.
    ENDIF.
    IF strlen( lv_ref ) > 0 AND lv_ref(1) = `/`.
      result = model_get( model_key = ctx-model_key
                          path      = lv_ref ).
      RETURN.
    ENDIF.
    IF row IS NOT INITIAL.
      result = model_get( model_key = ctx-model_key
                          path      = lv_ref
                          base      = row ).
    ENDIF.

  ENDMETHOD.

  METHOD resolve.

    DATA lt_ref TYPE z2ui5_cl_agent_viewxml=>ty_t_ref_val.
    DATA lv_text TYPE string.

    binding = z2ui5_cl_agent_viewxml=>parse_binding( raw ).
    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.

    CASE binding-kind.

      WHEN z2ui5_cl_agent_viewxml=>cs_binding-literal.
        result = z2ui5_cl_agent_viewxml=>val_string( binding-value ).

      WHEN z2ui5_cl_agent_viewxml=>cs_binding-path.
        IF binding-model IS NOT INITIAL.
          RETURN.
        ENDIF.
        IF binding-relative = abap_true.
          result = resolve_ref( ref = binding-path
                                ctx = ctx
                                row = row ).
        ELSE.
          result = model_get( model_key = ctx-model_key
                              path      = binding-path ).
        ENDIF.

      WHEN z2ui5_cl_agent_viewxml=>cs_binding-expression.
        LOOP AT z2ui5_cl_agent_viewxml=>expression_refs( binding-expression ) INTO DATA(lv_ref).
          INSERT VALUE #( ref = lv_ref
                          val = resolve_ref( ref = lv_ref
                                             ctx = ctx
                                             row = row ) ) INTO TABLE lt_ref.
        ENDLOOP.
        result = z2ui5_cl_agent_viewxml=>eval_expression( val   = binding-expression
                                                          t_ref = lt_ref ).

      WHEN OTHERS.
        DATA(lv_known) = abap_false.
        DATA(lv_all_text) = abap_true.
        LOOP AT binding-t_part INTO DATA(ls_part).
          IF ls_part-is_text = abap_true.
            lv_text = lv_text && ls_part-text.
            CONTINUE.
          ENDIF.
          lv_all_text = abap_false.
          IF ls_part-is_path = abap_true AND ls_part-model IS INITIAL AND ls_part-formatter = abap_false.
            DATA(ls_val) = COND ty_s_val( WHEN ls_part-relative = abap_true
                                          THEN resolve_ref( ref = ls_part-path
                                                            ctx = ctx
                                                            row = row )
                                          ELSE model_get( model_key = ctx-model_key
                                                          path      = ls_part-path ) ).
            IF ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-undefined AND ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null.
              lv_known = abap_true.
              lv_text = lv_text && z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF lv_known = abap_true OR lv_all_text = abap_true.
          result = z2ui5_cl_agent_viewxml=>val_string( lv_text ).
        ENDIF.

    ENDCASE.

  ENDMETHOD.

  METHOD bool.

    DATA lv_found TYPE abap_bool.

    DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                           name  = name
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      result = default.
      RETURN.
    ENDIF.
    DATA(ls_val) = resolve( raw = lv_raw
                            ctx = ctx
                            row = row ).
    CASE ls_val-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-undefined OR z2ui5_cl_agent_viewxml=>cs_kind-null OR space.
        result = default.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-string.
        IF ls_val-str = `true`.
          result = abap_true.
        ELSEIF ls_val-str = `false` OR ls_val-str IS INITIAL.
          result = abap_false.
        ELSE.
          result = default.
        ENDIF.
      WHEN OTHERS.
        result = z2ui5_cl_agent_viewxml=>val_truthy( ls_val ).
    ENDCASE.

  ENDMETHOD.

  METHOD text_of_raw.

    DATA(ls_val) = resolve( raw = raw
                            ctx = ctx
                            row = row ).
    IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
      RETURN.
    ENDIF.
    result = z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).

  ENDMETHOD.

  METHOD text_of.

    DATA lv_found TYPE abap_bool.

    DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                           name  = name
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    result = text_of_raw( raw = lv_raw
                          ctx = ctx
                          row = row ).

  ENDMETHOD.

  METHOD walk_children.

    DATA lv_found TYPE abap_bool.

    DATA(lv_label) = ctx-label.
    LOOP AT t_child INTO DATA(lv_child).
      DATA(ls_child) = node( doc = ctx-doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_false.
        DATA(lv_name) = z2ui5_cl_agent_viewxml=>control_name( ls_child ).
        DATA(lv_for) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_child
                                                               name  = `labelFor`
                                                     IMPORTING found = lv_found ).
        IF lv_name = `sap.m.Label` AND lv_for IS INITIAL.
          IF bool( node    = ls_child
                   name    = `visible`
                   ctx     = ctx
                   default = abap_true ) = abap_false.
            CONTINUE.
          ENDIF.
          lv_label = label_new( text     = text_of( node = ls_child
                                                    name = `text`
                                                    ctx  = ctx )
                                required = bool( node    = ls_child
                                                 name    = `required`
                                                 ctx     = ctx
                                                 default = abap_false ) ).
          CONTINUE.
        ENDIF.
        IF lv_name = `sap.ui.core.Title` OR lv_name = `sap.m.Title` OR ends_with( val    = lv_name
                                                                                   suffix = `Toolbar` ) = abap_true.
          lv_label = 0.
        ENDIF.
      ENDIF.
      DATA(ls_ctx) = ctx.
      ls_ctx-label = lv_label.
      walk( id  = lv_child
            ctx = ls_ctx ).
    ENDLOOP.

  ENDMETHOD.

  METHOD walk.

    DATA lv_found TYPE abap_bool.
    DATA lv_agg TYPE string.
    DATA lv_kind TYPE string.
    DATA lv_dialog TYPE abap_bool.

    DATA(ls_node) = node( doc = ctx-doc
                          id  = id ).
    IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true.
      walk_children( t_child = ls_node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.
    DATA(lv_name) = z2ui5_cl_agent_viewxml=>control_name( ls_node ).
    IF lv_name = `sap.ui.core.mvc.View` OR lv_name = `sap.ui.core.FragmentDefinition`.
      walk_children( t_child = ls_node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.
    IF bool( node    = ls_node
             name    = `visible`
             ctx     = ctx
             default = abap_true ) = abap_false.
      RETURN.
    ENDIF.
    DATA(ls_c) = ctx.
    INSERT ls_node-local INTO TABLE ls_c-t_where.

    " the title of the layer: Dialog / selection dialog / Popover / Page, or
    " a DynamicPageTitle
    IF NOT line_exists( mt_title[ layer = ctx-layer ] ). "#EC CI_SORTSEQ
      IF lv_name = `sap.m.Dialog` OR lv_name = `sap.m.SelectDialog` OR lv_name = `sap.m.TableSelectDialog`
          OR lv_name = `sap.m.Popover` OR lv_name = `sap.m.ResponsivePopover`
          OR lv_name = `sap.m.Page` OR lv_name = `sap.m.semantic.FullscreenPage` OR lv_name = `sap.m.Shell`.
        z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                name  = `title`
                                      IMPORTING found = lv_found ).
        IF lv_found = abap_true.
          DATA(lv_title) = text_of( node = ls_node
                                    name = `title`
                                    ctx  = ctx ).
          IF lv_title IS NOT INITIAL.
            INSERT VALUE #( layer = ctx-layer
                            title = z2ui5_cl_agent_viewxml=>clip( lv_title ) ) INTO TABLE mt_title.
          ENDIF.
        ENDIF.
      ENDIF.
      IF lv_name = `sap.f.DynamicPageTitle`.
        DATA(lv_heading) = find_first( doc     = ctx-doc
                                       id      = id
                                       control = `sap.m.Title` ).
        IF lv_heading > 0.
          lv_title = text_of( node = node( doc = ctx-doc
                                           id  = lv_heading )
                              name = `text`
                              ctx  = ctx ).
          IF lv_title IS NOT INITIAL.
            INSERT VALUE #( layer = ctx-layer
                            title = z2ui5_cl_agent_viewxml=>clip( lv_title ) ) INTO TABLE mt_title.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    IF starts_sap( ls_node-ns ) = abap_false.
      IF ls_node-ns = `z2ui5.cc` AND ls_node-local = `MessageManager`.
        message_manager( node = ls_node
                         ctx  = ls_c ).
        RETURN.
      ENDIF.
      note( |custom control { lv_name } ({ ctx-layer }: { where_text( ls_c ) }) - not described| ).
      wires( node = ls_node
             ctx  = ls_c
             name = lv_name ).
      walk_children( t_child = ls_node-t_child
                     ctx     = ls_c ).
      RETURN.
    ENDIF.
    IF lv_name = `sap.ui.core.HTML`.
      note( |raw HTML (sap.ui.core.HTML, { ctx-layer }: { where_text( ls_c ) }) - not described| ).
      RETURN.
    ENDIF.

    IF message_source( lv_name ) IS NOT INITIAL AND ctx-row_table IS INITIAL.
      message_list( node = ls_node
                    ctx  = ls_c
                    name = lv_name ).
      RETURN.
    ENDIF.

    IF table_spec( EXPORTING name   = lv_name
                   IMPORTING agg    = lv_agg
                             kind   = lv_kind
                             dialog = lv_dialog ) = abap_true AND ctx-row_table IS INITIAL.
      table( node   = ls_node
             ctx    = ls_c
             name   = lv_name
             agg    = lv_agg
             kind   = lv_kind
             dialog = lv_dialog ).
      RETURN.
    ENDIF.

    IF lv_name = `sap.ui.layout.form.FormElement`.
      DATA(lv_label) = 0.
      DATA(lv_label_attr) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                                    name  = `label`
                                                          IMPORTING found = lv_found ).
      IF lv_found = abap_true.
        lv_label = label_new( text     = text_of_raw( raw = lv_label_attr
                                                      ctx = ctx )
                              required = abap_false ).
      ENDIF.
      DATA(lv_label_agg) = child_agg( doc   = ctx-doc
                                      node  = ls_node
                                      local = `label` ).
      IF lv_label_agg > 0.
        DATA(lt_label_ctl) = controls_of( doc     = ctx-doc
                                          t_child = node( doc = ctx-doc
                                                          id  = lv_label_agg )-t_child ).
        IF lt_label_ctl IS NOT INITIAL.
          DATA(ls_label_ctl) = node( doc = ctx-doc
                                     id  = lt_label_ctl[ 1 ] ).
          lv_label = label_new( text     = text_of( node = ls_label_ctl
                                                    name = `text`
                                                    ctx  = ctx )
                                required = bool( node    = ls_label_ctl
                                                 name    = `required`
                                                 ctx     = ctx
                                                 default = abap_false ) ).
        ENDIF.
      ENDIF.
      LOOP AT ls_node-t_child INTO DATA(lv_agg_id).
        IF node( doc = ctx-doc
                 id  = lv_agg_id )-local = `label`.
          CONTINUE.
        ENDIF.
        DATA(ls_fe_ctx) = ls_c.
        ls_fe_ctx-label = lv_label.
        walk( id  = lv_agg_id
              ctx = ls_fe_ctx ).
      ENDLOOP.
      RETURN.
    ENDIF.

    IF lv_name = `sap.m.MessageStrip`.
      DATA(lv_strip) = text_of( node = ls_node
                                name = `text`
                                ctx  = ctx ).
      IF lv_strip IS NOT INITIAL.
        DATA(lv_strip_type) = text_of( node = ls_node
                                       name = `type`
                                       ctx  = ctx ).
        IF lv_strip_type IS INITIAL.
          lv_strip_type = `Information`.
        ENDIF.
        DATA(lv_mtype) = message_type( lv_strip_type ).
        INSERT VALUE #( type   = COND #( WHEN lv_mtype IS INITIAL THEN `info` ELSE lv_mtype )
                        text   = z2ui5_cl_agent_viewxml=>clip( val = lv_strip
                                                               len = 1000 )
                        source = `strip` ) INTO TABLE mt_message.
      ENDIF.
      wires( node = ls_node
             ctx  = ls_c
             name = lv_name ).
      RETURN.
    ENDIF.

    DATA(ls_spec) = field_spec( lv_name ).
    DATA(lv_field) = 0.
    IF ls_spec-found = abap_true AND ctx-row_table IS INITIAL.
      lv_field = field( node = ls_node
                        ctx  = ls_c
                        name = lv_name
                        spec = ls_spec ).
    ENDIF.
    IF ls_spec-found = abap_false AND ctx-row_table IS INITIAL.
      DATA(lt_props) = text_props( lv_name ).
      IF lt_props IS NOT INITIAL.
        DATA(lt_parts) = VALUE string_table( ).
        DATA(lt_source) = VALUE string_table( ).
        LOOP AT lt_props INTO DATA(lv_prop).
          DATA(lv_part) = text_of( node = ls_node
                                   name = lv_prop
                                   ctx  = ctx ).
          IF lv_part IS NOT INITIAL.
            INSERT lv_part INTO TABLE lt_parts.
            INSERT LINES OF text_paths( z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                                      name = lv_prop ) ) INTO TABLE lt_source.
          ENDIF.
        ENDLOOP.
        DATA(lv_text) = concat_lines_of( table = lt_parts
                                         sep   = ` ` ).
        IF lv_name = `sap.m.FormattedText`.
          lv_text = strip_tags( lv_text ).
        ENDIF.
        IF lv_text IS NOT INITIAL.
          READ TABLE mt_label INDEX ctx-label INTO DATA(ls_label).
          IF sy-subrc = 0 AND ls_label-text IS NOT INITIAL.
            add_text( val    = |{ ls_label-text }: { lv_text }|
                      t_path = lt_source ).
          ELSE.
            add_text( val    = lv_text
                      t_path = lt_source ).
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    wires( node  = ls_node
           ctx   = ls_c
           name  = lv_name
           field = lv_field ).
    " the items of a choice control are its values, not controls to walk
    IF ls_spec-found = abap_true AND ls_spec-items IS NOT INITIAL.
      RETURN.
    ENDIF.
    walk_children( t_child = ls_node-t_child
                   ctx     = ls_c ).

  ENDMETHOD.

  METHOD label_of.

    DATA lv_found TYPE abap_bool.

    DATA(lv_id) = z2ui5_cl_agent_viewxml=>attr( node = node
                                               name = `id` ).
    DATA(lv_for) = label_for( EXPORTING ctx   = ctx
                                        id    = lv_id
                              IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result = lv_for.
      RETURN.
    ENDIF.

    READ TABLE mt_label INDEX ctx-label REFERENCE INTO DATA(lr_label).
    IF sy-subrc = 0 AND lr_label->text IS NOT INITIAL.
      " one form label over several fields (a first and a last name input):
      " the placeholder tells them apart
      lr_label->uses = lr_label->uses + 1.
      DATA(lv_ph) = COND string( WHEN lr_label->uses > 1 THEN text_of( node = node
                                                                       name = `placeholder`
                                                                       ctx  = ctx ) ).
      result = COND #( WHEN lv_ph IS NOT INITIAL THEN |{ lr_label->text } ({ lv_ph })| ELSE lr_label->text ).
      RETURN.
    ENDIF.

    IF spec-text_label = abap_true AND z2ui5_cl_agent_viewxml=>attr( node = node
                                                                     name = `text` ) IS NOT INITIAL.
      result = text_of( node = node
                        name = `text`
                        ctx  = ctx ).
      IF result IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.

    LOOP AT VALUE string_table( ( `placeholder` ) ( `tooltip` ) ( `ariaLabel` ) ( `title` ) ) INTO DATA(lv_prop).
      result = text_of( node = node
                        name = lv_prop
                        ctx  = ctx ).
      IF result IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD field.

    DATA lv_found TYPE abap_bool.
    DATA lv_prop TYPE string.
    DATA ls_binding TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
    DATA lv_required TYPE abap_bool.

    LOOP AT spec-t_prop INTO DATA(lv_candidate).
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                              name  = lv_candidate
                                    IMPORTING found = lv_found ).
      IF lv_found = abap_true.
        lv_prop = lv_candidate.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_prop IS INITIAL.
      RETURN.
    ENDIF.

    DATA(ls_value) = resolve( EXPORTING raw     = z2ui5_cl_agent_viewxml=>attr( node = node
                                                                               name = lv_prop )
                                        ctx     = ctx
                              IMPORTING binding = ls_binding ).
    IF ls_binding-kind <> z2ui5_cl_agent_viewxml=>cs_binding-path.
      " a literal or computed value: nothing to fill
      RETURN.
    ENDIF.
    IF ls_binding-model IS NOT INITIAL.
      note( |field { node-local } bound to the named model '{ ls_binding-model }' ({ ctx-layer }) - not editable here| ).
      RETURN.
    ENDIF.
    IF ls_binding-relative = abap_true.
      note( |field { node-local } bound relatively (\{{ ls_binding-path }\}, { ctx-layer }: element binding) - not editable here| ).
      RETURN.
    ENDIF.

    DATA(lv_label) = label_of( node = node
                               ctx  = ctx
                               spec = spec ).
    DATA(lv_kind) = kind_from_type( ls_binding-type ).
    IF lv_kind IS INITIAL.
      lv_kind = spec-kind.
      IF lv_kind = `input`.
        lv_kind = SWITCH #( z2ui5_cl_agent_viewxml=>attr( node = node
                                                          name = `type` )
                            WHEN `Number`   THEN `number`
                            WHEN `Date`     THEN `date`
                            WHEN `Time`     THEN `time`
                            WHEN `DateTime` THEN `datetime`
                            ELSE `text` ).
      ENDIF.
    ENDIF.

    DATA(lv_editable) = xsdbool( bool( node    = node
                                       name    = `editable`
                                       ctx     = ctx
                                       default = abap_true ) = abap_true
                             AND bool( node    = node
                                       name    = `enabled`
                                       ctx     = ctx
                                       default = abap_true ) = abap_true
                             AND bool( node    = node
                                       name    = `displayOnly`
                                       ctx     = ctx
                                       default = abap_false ) = abap_false ).
    label_for( EXPORTING ctx      = ctx
                         id       = z2ui5_cl_agent_viewxml=>attr( node = node
                                                                  name = `id` )
               IMPORTING found    = lv_found
                         required = lv_required ).
    READ TABLE mt_label INDEX ctx-label INTO DATA(ls_label).
    DATA(lv_label_required) = xsdbool( sy-subrc = 0 AND ls_label-required = abap_true ).
    DATA(lv_required_all) = xsdbool( bool( node    = node
                                           name    = `required`
                                           ctx     = ctx
                                           default = abap_false ) = abap_true
                                     OR ( lv_found = abap_true AND lv_required = abap_true )
                                     OR lv_label_required = abap_true ).

    DATA(lv_name) = name_of_path( ls_binding-path ).
    DATA(ls_field) = VALUE ty_s_field( id        = |f{ lines( mt_field ) + 1 }|
                                       path      = ls_binding-path
                                       name      = lv_name
                                       label     = z2ui5_cl_agent_viewxml=>clip( val = COND #( WHEN lv_label IS NOT INITIAL THEN lv_label ELSE lv_name )
                                                                                 len = 120 )
                                       control   = name
                                       kind      = lv_kind
                                       value     = ls_value
                                       required  = lv_required_all
                                       editable  = lv_editable
                                       layer     = ctx-layer
                                       model_key = ctx-model_key
                                       doc       = ctx-doc
                                       node      = node-id
                                       secret    = xsdbool( z2ui5_cl_agent_viewxml=>attr( node = node
                                                                                          name = `type` ) = `Password` ) ).
    IF spec-items IS NOT INITIAL.
      DATA(lt_values) = choice_values( EXPORTING node  = node
                                                 ctx   = ctx
                                                 spec  = spec
                                       IMPORTING found = lv_found ).
      IF lv_found = abap_true.
        IF lines( lt_values ) > c_max_values.
          note( |field { ls_field-id } ({ ls_field-label }): { lines( lt_values ) } choices, the first { c_max_values } listed| ).
          DELETE lt_values FROM c_max_values + 1.
        ENDIF.
        ls_field-has_values = abap_true.
        ls_field-t_value = lt_values.
      ENDIF.
    ENDIF.
    INSERT ls_field INTO TABLE mt_field.
    result = lines( mt_field ).

    DATA(lv_state) = text_of( node = node
                              name = `valueState`
                              ctx  = ctx ).
    DATA(lv_type) = message_type( lv_state ).
    IF lv_type IS NOT INITIAL.
      DATA(lv_state_text) = text_of( node = node
                                     name = `valueStateText`
                                     ctx  = ctx ).
      IF lv_state_text IS INITIAL.
        lv_state_text = |{ ls_field-label }: { lv_state }|.
      ENDIF.
      INSERT VALUE #( type   = lv_type
                      text   = z2ui5_cl_agent_viewxml=>clip( val = lv_state_text
                                                             len = 1000 )
                      source = `field`
                      field  = ls_field-id ) INTO TABLE mt_message.
    ENDIF.

  ENDMETHOD.

  METHOD controls_of.

    LOOP AT t_child INTO DATA(lv_child).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( node( doc = doc
                                                       id  = lv_child ) ) = abap_false.
        INSERT lv_child INTO TABLE result.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD child_agg.

    LOOP AT node-t_child INTO DATA(lv_child).
      IF node( doc = doc
               id  = lv_child )-local = local.
        result = lv_child.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD item_controls.

    DATA(lv_agg) = child_agg( doc   = ctx-doc
                              node  = node
                              local = agg ).
    result = controls_of( doc     = ctx-doc
                          t_child = COND #( WHEN lv_agg > 0
                                            THEN node( doc = ctx-doc
                                                       id  = lv_agg )-t_child
                                            ELSE node-t_child ) ).

  ENDMETHOD.

  METHOD choice_values.

    DATA lv_found TYPE abap_bool.

    found = abap_false.
    DATA(lt_items) = item_controls( node = node
                                    ctx  = ctx
                                    agg  = COND #( WHEN spec-items = `index` THEN `buttons` ELSE `items` ) ).
    IF spec-items = `index`.
      found = abap_true.
      LOOP AT lt_items INTO DATA(lv_item).
        INSERT VALUE #( key  = z2ui5_cl_agent_viewxml=>val_number( |{ sy-tabix - 1 }| )
                        text = text_of( node = node( doc = ctx-doc
                                                     id  = lv_item )
                                        name = `text`
                                        ctx  = ctx ) ) INTO TABLE result.
      ENDLOOP.
      RETURN.
    ENDIF.

    DATA(lv_items_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = `items`
                                                       IMPORTING found = lv_found ).
    DATA(lv_bpath) = ``.
    IF lv_found = abap_true.
      DATA(ls_bound) = z2ui5_cl_agent_viewxml=>parse_binding( lv_items_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        IF ls_bound-model IS INITIAL AND ls_bound-relative = abap_false.
          lv_bpath = ls_bound-path.
        ENDIF.
      ELSE.
        LOOP AT ls_bound-t_part INTO DATA(ls_part) WHERE is_path = abap_true. "#EC CI_SORTSEQ
          IF ls_part-model IS INITIAL AND ls_part-relative = abap_false.
            lv_bpath = ls_part-path.
          ENDIF.
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF lv_bpath IS NOT INITIAL.
      DATA(ls_rows) = model_get( model_key = ctx-model_key
                                 path      = lv_bpath ).
      IF ls_rows-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array OR lt_items IS INITIAL.
        RETURN.
      ENDIF.
      found = abap_true.
      DATA(ls_tmpl) = node( doc = ctx-doc
                            id  = lt_items[ 1 ] ).
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_tmpl
                                              name  = `key`
                                    IMPORTING found = lv_found ).
      DATA(lv_count) = CONV i( ls_rows-num ).
      DO lv_count TIMES.
        DATA(lv_row) = tree_path( model_key = ctx-model_key
                                  path      = |{ lv_bpath }/{ sy-index - 1 }| ).
        DATA(lv_text) = text_of( node = ls_tmpl
                                 name = `text`
                                 ctx  = ctx
                                 row  = lv_row ).
        INSERT VALUE #( key  = z2ui5_cl_agent_viewxml=>val_string( COND #( WHEN lv_found = abap_true
                                                                           THEN text_of( node = ls_tmpl
                                                                                         name = `key`
                                                                                         ctx  = ctx
                                                                                         row  = lv_row )
                                                                           ELSE lv_text ) )
                        text = lv_text ) INTO TABLE result.
      ENDDO.
      RETURN.
    ENDIF.

    IF lt_items IS INITIAL.
      RETURN.
    ENDIF.
    found = abap_true.
    LOOP AT lt_items INTO lv_item.
      DATA(ls_item) = node( doc = ctx-doc
                            id  = lv_item ).
      lv_text = text_of( node = ls_item
                         name = `text`
                         ctx  = ctx ).
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_item
                                              name  = `key`
                                    IMPORTING found = lv_found ).
      INSERT VALUE #( key  = z2ui5_cl_agent_viewxml=>val_string( COND #( WHEN lv_found = abap_true
                                                                         THEN text_of( node = ls_item
                                                                                       name = `key`
                                                                                       ctx  = ctx )
                                                                         ELSE lv_text ) )
                      text = lv_text ) INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD push_action.

    DATA(ls_action) = action.
    ls_action-id = |a{ lines( mt_action ) + 1 }|.
    IF ls_action-scope <> `row`.
      CLEAR ls_action-table.
    ENDIF.
    INSERT ls_action INTO TABLE mt_action.

  ENDMETHOD.

  METHOD wires.

    DATA lt_desc TYPE string_table.

    LOOP AT node-t_attr INTO DATA(ls_attr).
      IF only IS NOT INITIAL AND ls_attr-name <> only.
        CONTINUE.
      ENDIF.
      IF z2ui5_cl_agent_viewxml=>has_wire( ls_attr-value ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(ls_wire) = z2ui5_cl_agent_viewxml=>parse_wire( ls_attr-value ).
      IF ls_wire-valid = abap_false.
        note( |event { ls_attr-name } on { node-local } ({ ctx-layer }) - a handler this client cannot read| ).
        CONTINUE.
      ENDIF.
      " a wire whose trigger is not shown is skipped
      DATA(lv_gate) = SWITCH string( ls_attr-name
                                     WHEN `navButtonPress`   THEN `showNavButton`
                                     WHEN `valueHelpRequest` THEN `showValueHelp` ).
      IF lv_gate IS NOT INITIAL AND bool( node    = node
                                          name    = lv_gate
                                          ctx     = ctx
                                          default = abap_false ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(lv_label) = COND string( WHEN override IS NOT INITIAL THEN override
                                    ELSE action_label( node    = node
                                                       ctx     = ctx
                                                       name    = name
                                                       trigger = ls_attr-name
                                                       field   = field ) ).
      DATA(lv_enabled) = bool( node    = node
                               name    = `enabled`
                               ctx     = ctx
                               default = abap_true ).
      DATA(lv_scope) = COND string( WHEN ctx-row_table IS NOT INITIAL THEN `row` ELSE `screen` ).

      IF ls_wire-fn = `eF`.
        DATA(lt_static) = VALUE string_table( ).
        LOOP AT ls_wire-t_arg INTO DATA(ls_arg).
          INSERT COND #( WHEN ls_arg-static = abap_true THEN ls_arg-val-str ELSE `#dynamic#` ) INTO TABLE lt_static.
        ENDLOOP.
        " read ahead: a table expression in the condition would be hoisted in
        " front of the IF by the 7.02 downport, where no guard protects it
        DATA(lv_slot) = VALUE string( lt_static[ 3 ] OPTIONAL ).
        DATA(lv_static_1) = VALUE string( lt_static[ 1 ] OPTIONAL ).
        DATA(lv_static_2) = VALUE string( lt_static[ 2 ] OPTIONAL ).
        IF ls_wire-action = z2ui5_if_client=>cs_event-control_global
            AND lv_static_1 = `VIEW_SLOTS` AND lv_static_2 = `destroy`
            AND ( lv_slot = cs_model-popup OR lv_slot = cs_model-popover ).
          push_action( VALUE #( event     = COND #( WHEN lv_slot = cs_model-popup
                                                    THEN cs_frontend_event-popup
                                                    ELSE cs_frontend_event-popover )
                                label     = lv_label
                                control   = name
                                trigger   = ls_attr-name
                                enabled   = lv_enabled
                                scope     = lv_scope
                                table     = ctx-row_table
                                layer     = ctx-layer
                                model_key = ctx-model_key
                                doc       = ctx-doc
                                node      = node-id
                                frontend  = lv_slot ) ).
        ELSE.
          CLEAR lt_desc.
          LOOP AT ls_wire-t_arg INTO ls_arg.
            INSERT COND #( WHEN ls_arg-static = abap_true
                           THEN z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val )
                           ELSE ls_arg-describe ) INTO TABLE lt_desc.
          ENDLOOP.
          note( |frontend action { ls_wire-action }({ concat_lines_of( table = lt_desc
                                                                      sep   = `, ` ) }) on { node-local } | &&
                |"{ z2ui5_cl_agent_viewxml=>clip( val = lv_label
                                                  len = 60 ) }" ({ ctx-layer }) - runs in the browser only| ).
        ENDIF.
        CONTINUE.
      ENDIF.

      DATA(lt_arg_json) = VALUE string_table( ).
      LOOP AT ls_wire-t_arg INTO ls_arg.
        INSERT COND #( WHEN ls_arg-static = abap_true
                       THEN z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val )
                       ELSE z2ui5_cl_agent_viewxml=>json_string( ls_arg-describe ) ) INTO TABLE lt_arg_json.
      ENDLOOP.
      push_action( VALUE #( event        = ls_wire-event
                            t_arg_json   = lt_arg_json
                            label        = lv_label
                            control      = name
                            trigger      = ls_attr-name
                            enabled      = lv_enabled
                            scope        = lv_scope
                            table        = ctx-row_table
                            layer        = ctx-layer
                            model_key    = ctx-model_key
                            doc          = ctx-doc
                            node         = node-id
                            t_wire_arg   = ls_wire-t_arg
                            pick         = pick
                            row_template = ctx-row_template ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD action_label.

    DATA lv_found TYPE abap_bool.

    IF trigger = `navButtonPress`.
      result = `Back`.
      RETURN.
    ENDIF.
    IF field > 0.
      result = |{ mt_field[ field ]-label }: { trigger }|.
      RETURN.
    ENDIF.
    DATA(ls_spec) = field_spec( name ).
    IF ls_spec-found = abap_true AND ctx-row_table IS INITIAL.
      DATA(lv_label) = label_of( node = node
                                 ctx  = ctx
                                 spec = ls_spec ).
      IF lv_label IS NOT INITIAL.
        result = |{ z2ui5_cl_agent_viewxml=>clip( val = lv_label
                                                  len = 80 ) }: { trigger }|.
        RETURN.
      ENDIF.
    ENDIF.
    LOOP AT VALUE string_table( ( `text` ) ( `title` ) ( `tooltip` ) ( `headerText` ) ( `ariaLabel` ) ) INTO DATA(lv_prop).
      DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                             name  = lv_prop
                                                   IMPORTING found = lv_found ).
      IF lv_found = abap_false.
        CONTINUE.
      ENDIF.
      " in a row template a bound text differs per row: not a label
      IF ctx-row_table IS NOT INITIAL
          AND z2ui5_cl_agent_viewxml=>parse_binding( lv_raw )-kind <> z2ui5_cl_agent_viewxml=>cs_binding-literal.
        CONTINUE.
      ENDIF.
      DATA(lv_text) = text_of_raw( raw = lv_raw
                                   ctx = ctx ).
      IF lv_text IS NOT INITIAL.
        result = z2ui5_cl_agent_viewxml=>clip( val = lv_text
                                               len = 80 ).
        RETURN.
      ENDIF.
    ENDLOOP.
    DATA(lv_icon) = z2ui5_cl_agent_viewxml=>attr( node = node
                                                 name = `icon` ).
    IF lv_icon IS NOT INITIAL
        AND z2ui5_cl_agent_viewxml=>parse_binding( lv_icon )-kind = z2ui5_cl_agent_viewxml=>cs_binding-literal.
      result = icon_name( lv_icon ).
      RETURN.
    ENDIF.
    DATA(lv_type) = z2ui5_cl_agent_viewxml=>attr( node = node
                                                 name = `type` ).
    IF ctx-row_table IS NOT INITIAL AND lv_type IS NOT INITIAL
        AND z2ui5_cl_agent_viewxml=>parse_binding( lv_type )-kind = z2ui5_cl_agent_viewxml=>cs_binding-literal.
      result = |row { trigger } ({ lv_type })|.
      RETURN.
    ENDIF.
    IF ctx-row_table IS NOT INITIAL.
      result = |row { trigger }|.
      RETURN.
    ENDIF.
    result = trigger.

  ENDMETHOD.

  METHOD message_manager.

    DATA(ls_b) = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = node
                                                                                       name = `items` ) ).
    IF ls_b-kind <> z2ui5_cl_agent_viewxml=>cs_binding-path OR ls_b-model IS NOT INITIAL OR ls_b-relative = abap_true.
      RETURN.
    ENDIF.
    DATA(ls_rows) = model_get( model_key = ctx-model_key
                               path      = ls_b-path ).
    IF ls_rows-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array.
      RETURN.
    ENDIF.
    DATA(lv_count) = CONV i( ls_rows-num ).
    DO lv_count TIMES.
      DATA(lv_row) = tree_path( model_key = ctx-model_key
                                path      = |{ ls_b-path }/{ sy-index - 1 }| ).
      DATA(lv_text) = ``.
      DATA(lv_type) = ``.
      DATA(lv_target) = ``.
      LOOP AT VALUE string_table( ( `MESSAGE` ) ( `TYPE` ) ( `TARGET` ) ) INTO DATA(lv_key).
        " the column as written, in lower case, or capitalized
        DATA(ls_val) = VALUE ty_s_val( ).
        LOOP AT VALUE string_table( ( lv_key )
                                    ( to_lower( lv_key ) )
                                    ( lv_key(1) && to_lower( substring( val = lv_key
                                                                         off = 1 ) ) ) ) INTO DATA(lv_variant).
          ls_val = model_get( model_key = ctx-model_key
                              path      = lv_variant
                              base      = lv_row ).
          IF ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-undefined AND ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null.
            EXIT.
          ENDIF.
        ENDLOOP.
        DATA(lv_value) = COND string( WHEN z2ui5_cl_agent_viewxml=>val_truthy( ls_val ) = abap_true
                                      THEN z2ui5_cl_agent_viewxml=>val_to_string( ls_val ) ).
        CASE lv_key.
          WHEN `MESSAGE`.
            lv_text = lv_value.
          WHEN `TYPE`.
            lv_type = message_type( lv_value ).
          WHEN OTHERS.
            lv_target = lv_value.
        ENDCASE.
      ENDLOOP.
      IF lv_text IS INITIAL.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( type   = COND #( WHEN lv_type IS INITIAL THEN `info` ELSE lv_type )
                      text   = z2ui5_cl_agent_viewxml=>clip( val = lv_text
                                                             len = 1000 )
                      target = lv_target ) INTO TABLE mt_mgr_msg.
    ENDDO.

  ENDMETHOD.

  METHOD message_list.

    DATA lv_found TYPE abap_bool.
    DATA lt_entry_item TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lt_entry_row TYPE string_table.

    " a MessagePopover or MessageView: every MessageItem is a message, open
    " or not (a MessagePopover in dependents opens in the browser only - the
    " messages are what the app shows there). Static items, or the template
    " of a bound items resolved per row
    DATA(lv_source) = message_source( name ).
    DATA(lt_items) = VALUE z2ui5_cl_agent_viewxml=>ty_t_int( ).
    LOOP AT item_controls( node = node
                           ctx  = ctx
                           agg  = `items` ) INTO DATA(lv_item).
      DATA(lv_item_name) = z2ui5_cl_agent_viewxml=>control_name( node( doc = ctx-doc
                                                                       id  = lv_item ) ).
      IF lv_item_name = `sap.m.MessageItem` OR lv_item_name = `sap.m.MessagePopoverItem`.
        INSERT lv_item INTO TABLE lt_items.
      ENDIF.
    ENDLOOP.

    DATA(lv_items_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = `items`
                                                       IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      LOOP AT lt_items INTO lv_item.
        INSERT lv_item INTO TABLE lt_entry_item.
        INSERT `` INTO TABLE lt_entry_row.
      ENDLOOP.
    ELSE.
      DATA(lv_bpath) = ``.
      DATA(lv_bmodel) = ``.
      DATA(lv_brelative) = abap_false.
      DATA(lv_has_bpath) = abap_false.
      DATA(ls_bound) = z2ui5_cl_agent_viewxml=>parse_binding( lv_items_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        lv_has_bpath = abap_true.
        lv_bpath = ls_bound-path.
        lv_bmodel = ls_bound-model.
        lv_brelative = ls_bound-relative.
      ELSE.
        LOOP AT ls_bound-t_part INTO DATA(ls_part) WHERE is_path = abap_true. "#EC CI_SORTSEQ
          lv_has_bpath = abap_true.
          lv_bpath = ls_part-path.
          lv_bmodel = ls_part-model.
          lv_brelative = ls_part-relative.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF lv_bpath IS INITIAL OR lv_bmodel IS NOT INITIAL OR lv_brelative = abap_true.
        note( |{ node-local } bound to { COND #( WHEN lv_has_bpath = abap_true AND lv_bmodel IS NOT INITIAL
                                                THEN |the named model '{ lv_bmodel }'|
                                                ELSE `something other than a model table` ) } ({ ctx-layer }) - messages not described| ).
      ELSE.
        DATA(ls_rows) = model_get( model_key = ctx-model_key
                                   path      = lv_bpath ).
        DATA(lv_template) = VALUE i( lt_items[ 1 ] OPTIONAL ).
        IF ls_rows-kind = z2ui5_cl_agent_viewxml=>cs_kind-array AND lv_template > 0.
          DATA(lv_count) = CONV i( ls_rows-num ).
          DO lv_count TIMES.
            INSERT lv_template INTO TABLE lt_entry_item.
            INSERT tree_path( model_key = ctx-model_key
                              path      = |{ lv_bpath }/{ sy-index - 1 }| ) INTO TABLE lt_entry_row.
          ENDDO.
        ENDIF.
      ENDIF.
    ENDIF.

    DATA(lv_messages) = 0.
    LOOP AT lt_entry_item INTO lv_item.
      DATA(lv_row) = lt_entry_row[ sy-tabix ].
      DATA(ls_item) = node( doc = ctx-doc
                            id  = lv_item ).
      " the item's type; absent (or empty) is UI5's default, Error
      DATA(lv_type_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_item
                                                                  name  = `type`
                                                        IMPORTING found = lv_found ).
      DATA(lv_type_value) = COND string( WHEN lv_found = abap_false THEN `Error`
                                         ELSE text_of_raw( raw = lv_type_raw
                                                           ctx = ctx
                                                           row = lv_row ) ).
      DATA(lv_type) = message_type( lv_type_value ).
      IF lv_type IS INITIAL.
        lv_type = COND #( WHEN lv_type_value IS INITIAL THEN `error` ELSE `info` ).
      ENDIF.
      DATA(lv_title) = text_of( node = ls_item
                                name = `title`
                                ctx  = ctx
                                row  = lv_row ).
      DATA(lv_subtitle) = text_of( node = ls_item
                                   name = `subtitle`
                                   ctx  = ctx
                                   row  = lv_row ).
      DATA(lv_description) = text_of( node = ls_item
                                      name = `description`
                                      ctx  = ctx
                                      row  = lv_row ).
      IF lv_description IS NOT INITIAL AND bool( node    = ls_item
                                                 name    = `markupDescription`
                                                 ctx     = ctx
                                                 row     = lv_row
                                                 default = abap_false ) = abap_true.
        lv_description = strip_tags( lv_description ).
      ENDIF.
      " clipped: whitespace collapsed - empty when there is nothing but blanks
      DATA(lv_title_clip) = z2ui5_cl_agent_viewxml=>clip( val = lv_title
                                                          len = 1000 ).
      DATA(lv_subtitle_clip) = z2ui5_cl_agent_viewxml=>clip( val = lv_subtitle
                                                             len = 1000 ).
      DATA(lv_description_clip) = z2ui5_cl_agent_viewxml=>clip( val = lv_description
                                                                len = 1000 ).
      IF lv_title_clip IS INITIAL AND lv_subtitle_clip IS INITIAL AND lv_description_clip IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_messages = lv_messages + 1.
      IF lv_messages > c_max_item_messages.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( type        = lv_type
                      text        = lv_title_clip
                      source      = lv_source
                      subtitle    = lv_subtitle_clip
                      description = lv_description_clip ) INTO TABLE mt_message.
    ENDLOOP.
    IF lv_messages > c_max_item_messages.
      note( |{ node-local } ({ ctx-layer }): { lv_messages } messages, the first { c_max_item_messages } listed| ).
    ENDIF.

    wires( node = node
           ctx  = ctx
           name = name ).
    " what else it aggregates (a headerButton) is on the screen like any control
    LOOP AT node-t_child INTO DATA(lv_child).
      DATA(ls_child) = node( doc = ctx-doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_true AND ls_child-local <> `items`.
        walk( id  = lv_child
              ctx = ctx ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD table.

    DATA lv_found TYPE abap_bool.
    DATA lt_cell TYPE ty_t_cellsrc.
    DATA lt_used TYPE string_table.
    DATA lv_template TYPE i.
    DATA lt_columns TYPE z2ui5_cl_agent_viewxml=>ty_t_int.

    DATA(lv_bound_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = agg
                                                       IMPORTING found = lv_found ).
    DATA(lv_bpath) = ``.
    DATA(lv_bmodel) = ``.
    DATA(lv_brelative) = abap_false.
    DATA(lv_has_bpath) = abap_false.
    IF lv_found = abap_true.
      DATA(ls_bound) = z2ui5_cl_agent_viewxml=>parse_binding( lv_bound_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        lv_has_bpath = abap_true.
        lv_bpath = ls_bound-path.
        lv_bmodel = ls_bound-model.
        lv_brelative = ls_bound-relative.
      ELSE.
        LOOP AT ls_bound-t_part INTO DATA(ls_part) WHERE is_path = abap_true. "#EC CI_SORTSEQ
          lv_has_bpath = abap_true.
          lv_bpath = ls_part-path.
          lv_bmodel = ls_part-model.
          lv_brelative = ls_part-relative.
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDIF.
    IF lv_bpath IS INITIAL OR lv_bmodel IS NOT INITIAL OR lv_brelative = abap_true.
      IF lv_found = abap_true.
        note( |{ node-local } bound to { COND #( WHEN lv_has_bpath = abap_true AND lv_bmodel IS NOT INITIAL
                                                THEN |the named model '{ lv_bmodel }'|
                                                ELSE `something other than a model table` ) } ({ ctx-layer }) - rows not described| ).
      ENDIF.
      wires( node = node
             ctx  = ctx
             name = name ).
      walk_children( t_child = node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.

    DATA(lv_table_id) = |t{ lines( mt_table ) + 1 }|.
    DATA(lv_label) = text_of( node = node
                              name = `headerText`
                              ctx  = ctx ).
    IF lv_label IS INITIAL.
      lv_label = text_of( node = node
                          name = `title`
                          ctx  = ctx ).
    ENDIF.
    IF lv_label IS INITIAL.
      lv_label = header_title( node = node
                               ctx  = ctx ).
    ENDIF.
    IF lv_label IS INITIAL.
      lv_label = name_of_path( lv_bpath ).
    ENDIF.
    DATA(ls_rows) = model_get( model_key = ctx-model_key
                               path      = lv_bpath ).
    DATA(lv_row_count) = COND i( WHEN ls_rows-kind = z2ui5_cl_agent_viewxml=>cs_kind-array THEN CONV i( ls_rows-num ) ).

    " the template: the one control of the bound aggregation
    DATA(lv_col_agg) = child_agg( doc   = ctx-doc
                                  node  = node
                                  local = `columns` ).
    IF kind = `m`.
      DATA(lv_items_agg) = child_agg( doc   = ctx-doc
                                      node  = node
                                      local = agg ).
      DATA(lt_tmpl) = controls_of( doc     = ctx-doc
                                   t_child = COND #( WHEN lv_items_agg > 0
                                                     THEN node( doc = ctx-doc
                                                                id  = lv_items_agg )-t_child
                                                     ELSE node-t_child ) ).
      IF lt_tmpl IS NOT INITIAL.
        lv_template = lt_tmpl[ 1 ].
      ENDIF.
      IF lv_col_agg > 0.
        lt_columns = controls_of( doc     = ctx-doc
                                  t_child = node( doc = ctx-doc
                                                  id  = lv_col_agg )-t_child ).
      ENDIF.
    ELSE.
      IF lv_col_agg > 0.
        lt_columns = controls_of( doc     = ctx-doc
                                  t_child = node( doc = ctx-doc
                                                  id  = lv_col_agg )-t_child ).
      ELSE.
        LOOP AT controls_of( doc     = ctx-doc
                             t_child = node-t_child ) INTO DATA(lv_col_candidate).
          IF ends_with( val    = node( doc = ctx-doc
                                       id  = lv_col_candidate )-local
                        suffix = `Column` ) = abap_true.
            INSERT lv_col_candidate INTO TABLE lt_columns.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " the cells: which control, which property, which header
    IF kind = `m` AND lv_template > 0.
      DATA(ls_template) = node( doc = ctx-doc
                                id  = lv_template ).
      DATA(lv_cells_agg) = child_agg( doc   = ctx-doc
                                      node  = ls_template
                                      local = `cells` ).
      IF lv_cells_agg > 0 OR z2ui5_cl_agent_viewxml=>control_name( ls_template ) = `sap.m.ColumnListItem`.
        DATA(lt_cell_nodes) = controls_of( doc     = ctx-doc
                                           t_child = COND #( WHEN lv_cells_agg > 0
                                                             THEN node( doc = ctx-doc
                                                                        id  = lv_cells_agg )-t_child
                                                             ELSE ls_template-t_child ) ).
        LOOP AT lt_cell_nodes INTO DATA(lv_cell_node).
          DATA(lv_col_node) = VALUE i( lt_columns[ sy-tabix ] OPTIONAL ).
          INSERT VALUE #( node    = lv_cell_node
                          header  = column_header( ctx = ctx
                                                   col = lv_col_node )
                          visible = COND #( WHEN lv_col_node > 0
                                            THEN bool( node    = node( doc = ctx-doc
                                                                       id  = lv_col_node )
                                                       name    = `visible`
                                                       ctx     = ctx
                                                       default = abap_true )
                                            ELSE abap_true ) ) INTO TABLE lt_cell.
        ENDLOOP.
      ELSE.
        " a list item: its bound properties are the columns
        LOOP AT ls_template-t_attr INTO DATA(ls_tattr).
          IF ls_tattr-name = `selected` OR ls_tattr-name = `type` OR ls_tattr-name = `visible` OR ls_tattr-name = `highlight`
              OR ls_tattr-name = `unread` OR ls_tattr-name = `counter` OR ls_tattr-name = `navigated`
              OR ls_tattr-name = `id` OR ls_tattr-name = `class`.
            CONTINUE.
          ENDIF.
          IF z2ui5_cl_agent_viewxml=>has_wire( ls_tattr-value ) = abap_true.
            CONTINUE.
          ENDIF.
          DATA(ls_tb) = z2ui5_cl_agent_viewxml=>parse_binding( ls_tattr-value ).
          DATA(lv_take) = abap_false.
          IF ls_tb-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_tb-relative = abap_true AND ls_tb-model IS INITIAL.
            lv_take = abap_true.
          ELSEIF ls_tb-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.
            LOOP AT ls_tb-t_part INTO DATA(ls_tpart) WHERE is_path = abap_true AND relative = abap_true. "#EC CI_SORTSEQ
              IF ls_tpart-path IS NOT INITIAL.
                lv_take = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDIF.
          IF lv_take = abap_true.
            INSERT VALUE #( node    = lv_template
                            prop    = ls_tattr-name
                            header  = ls_tattr-name
                            visible = abap_true ) INTO TABLE lt_cell.
          ENDIF.
        ENDLOOP.
        IF lt_cell IS INITIAL.
          " a CustomListItem: the bound controls inside it
          LOOP AT descendants( doc = ctx-doc
                               id  = lv_template ) INTO DATA(lv_desc).
            DATA(lv_main) = main_prop( node( doc = ctx-doc
                                             id  = lv_desc ) ).
            IF lv_main IS NOT INITIAL.
              INSERT VALUE #( node    = lv_desc
                              prop    = lv_main
                              header  = lv_main
                              visible = abap_true ) INTO TABLE lt_cell.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ELSEIF kind = `ui`.
      LOOP AT lt_columns INTO DATA(lv_column).
        DATA(ls_col) = node( doc = ctx-doc
                             id  = lv_column ).
        DATA(lv_tmpl_agg) = child_agg( doc   = ctx-doc
                                       node  = ls_col
                                       local = `template` ).
        IF lv_tmpl_agg = 0.
          CONTINUE.
        ENDIF.
        DATA(lt_tnode) = controls_of( doc     = ctx-doc
                                      t_child = node( doc = ctx-doc
                                                      id  = lv_tmpl_agg )-t_child ).
        IF lt_tnode IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(lv_header) = text_of( node = ls_col
                                   name = `label`
                                   ctx  = ctx ).
        IF lv_header IS INITIAL.
          " the label aggregation, written out or as the column's default one
          DATA(lv_label_agg) = child_agg( doc   = ctx-doc
                                          node  = ls_col
                                          local = `label` ).
          DATA(lt_lnode) = controls_of( doc     = ctx-doc
                                        t_child = COND #( WHEN lv_label_agg > 0
                                                          THEN node( doc = ctx-doc
                                                                     id  = lv_label_agg )-t_child
                                                          ELSE ls_col-t_child ) ).
          IF lt_lnode IS NOT INITIAL.
            lv_header = text_of( node = node( doc = ctx-doc
                                              id  = lt_lnode[ 1 ] )
                                 name = `text`
                                 ctx  = ctx ).
          ENDIF.
        ENDIF.
        INSERT VALUE #( node    = lt_tnode[ 1 ]
                        header  = lv_header
                        visible = bool( node    = ls_col
                                        name    = `visible`
                                        ctx     = ctx
                                        default = abap_true ) ) INTO TABLE lt_cell.
      ENDLOOP.
    ENDIF.

    " columns and how each one is read
    DATA(ls_table) = VALUE ty_s_table( id        = lv_table_id
                                       path      = lv_bpath
                                       name      = name_of_path( lv_bpath )
                                       label     = z2ui5_cl_agent_viewxml=>clip( val = lv_label
                                                                                 len = 120 )
                                       control   = name
                                       row_count = lv_row_count
                                       layer     = ctx-layer
                                       model_key = ctx-model_key
                                       doc       = ctx-doc ).
    LOOP AT lt_cell INTO DATA(ls_cell).
      DATA(lv_cell_index) = sy-tabix.
      IF ls_cell-visible = abap_false.
        CONTINUE.
      ENDIF.
      DATA(ls_cn) = node( doc = ctx-doc
                          id  = ls_cell-node ).
      DATA(lv_prop) = COND string( WHEN ls_cell-prop IS NOT INITIAL THEN ls_cell-prop ELSE main_prop( ls_cn ) ).
      DATA(ls_spec_cell) = VALUE ty_s_cellspec( node = ls_cell-node
                                                prop = lv_prop ).
      DATA(lv_col_name) = |COL{ lv_cell_index }|.
      IF lv_prop IS NOT INITIAL.
        ls_spec_cell-has_binding = abap_true.
        ls_spec_cell-binding = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = ls_cn
                                                                                                     name = lv_prop ) ).
        IF ls_spec_cell-binding-kind = z2ui5_cl_agent_viewxml=>cs_binding-path
            AND ls_spec_cell-binding-relative = abap_true AND ls_spec_cell-binding-model IS INITIAL.
          lv_col_name = ls_spec_cell-binding-path.
        ENDIF.
      ENDIF.
      IF line_exists( lt_used[ table_line = lv_col_name ] ). "#EC CI_SORTSEQ
        lv_col_name = |{ lv_col_name }_{ lv_cell_index }|.
      ENDIF.
      INSERT lv_col_name INTO TABLE lt_used.
      ls_spec_cell-name = lv_col_name.
      INSERT VALUE #( name  = lv_col_name
                      label = z2ui5_cl_agent_viewxml=>clip( val = COND #( WHEN ls_cell-header IS NOT INITIAL THEN ls_cell-header ELSE lv_col_name )
                                                            len = 80 ) ) INTO TABLE ls_table-t_column.
      IF ls_cell-prop IS INITIAL.
        DATA(ls_cell_field) = field_spec( z2ui5_cl_agent_viewxml=>control_name( ls_cn ) ).
        IF ls_cell_field-found = abap_true.
          ls_spec_cell-has_field_spec = abap_true.
          ls_spec_cell-field_kind = COND #( WHEN ls_cell_field-kind = `input` THEN `text` ELSE ls_cell_field-kind ).
        ENDIF.
      ENDIF.
      INSERT ls_spec_cell INTO TABLE ls_table-t_cellspec.
    ENDLOOP.

    " selection
    IF dialog = abap_true.
      " a selection dialog always selects: one row (a pick confirms) or several
      DATA(lv_mode) = COND string( WHEN bool( node    = node
                                              name    = `multiSelect`
                                              ctx     = ctx
                                              default = abap_false ) = abap_true
                                   THEN `Multi`
                                   ELSE `Single` ).
    ELSEIF kind = `m`.
      lv_mode = text_of( node = node
                         name = `mode`
                         ctx  = ctx ).
    ELSE.
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                              name  = `selectionMode`
                                    IMPORTING found = lv_found ).
      lv_mode = COND #( WHEN lv_found = abap_true
                        THEN text_of( node = node
                                      name = `selectionMode`
                                      ctx  = ctx )
                        ELSE `MultiToggle` ).
    ENDIF.
    ls_table-selection_mode = COND #( WHEN find( val = lv_mode
                                                 sub = `Multi` ) >= 0 THEN `Multi`
                                      WHEN find( val = lv_mode
                                                 sub = `Single` ) >= 0 THEN `Single`
                                      ELSE `None` ).
    IF lv_template > 0.
      DATA(lv_sel_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node( doc = ctx-doc
                                                                               id  = lv_template )
                                                                 name  = `selected`
                                                       IMPORTING found = lv_found ).
      IF lv_found = abap_true.
        DATA(ls_sb) = z2ui5_cl_agent_viewxml=>parse_binding( lv_sel_raw ).
        IF ls_sb-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_sb-relative = abap_true AND ls_sb-model IS INITIAL.
          ls_table-selection_field = ls_sb-path.
        ENDIF.
      ENDIF.
    ENDIF.

    " editable cells: an input bound to a row property, not disabled for every row
    LOOP AT ls_table-t_cellspec REFERENCE INTO DATA(lr_spec).
      IF lr_spec->has_field_spec = abap_false OR lr_spec->has_binding = abap_false
          OR lr_spec->binding-kind <> z2ui5_cl_agent_viewxml=>cs_binding-path
          OR lr_spec->binding-relative = abap_false OR lr_spec->binding-model IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      lr_spec->check_editable = abap_true.
      DATA(ls_cell_node) = node( doc = ctx-doc
                                 id  = lr_spec->node ).
      DATA(lv_ok) = abap_false.
      IF lv_row_count = 0.
        lv_ok = cell_ok( ctx  = ctx
                         node = ls_cell_node
                         row  = `` ).
      ELSE.
        DO lv_row_count TIMES.
          IF cell_ok( ctx  = ctx
                      node = ls_cell_node
                      row  = tree_path( model_key = ctx-model_key
                                        path      = |{ lv_bpath }/{ sy-index - 1 }| ) ) = abap_true.
            lv_ok = abap_true.
            EXIT.
          ENDIF.
        ENDDO.
      ENDIF.
      IF lv_ok = abap_true.
        INSERT lr_spec->name INTO TABLE ls_table-t_editable.
      ENDIF.
    ENDLOOP.
    IF ls_table-selection_mode = `None`.
      CLEAR ls_table-selection_field.
    ENDIF.
    IF ls_table-selection_field IS NOT INITIAL AND NOT line_exists( ls_table-t_editable[ table_line = ls_table-selection_field ] ). "#EC CI_SORTSEQ
      INSERT ls_table-selection_field INTO TABLE ls_table-t_editable.
    ENDIF.

    " the first rows
    DATA(lv_shown) = nmin( val1 = lv_row_count
                           val2 = mv_rows ).
    DO lv_shown TIMES.
      DATA(lv_row) = tree_path( model_key = ctx-model_key
                                path      = |{ lv_bpath }/{ sy-index - 1 }| ).
      DATA(ls_row) = VALUE ty_s_row( ).
      LOOP AT ls_table-t_cellspec INTO DATA(ls_cs).
        DATA(ls_val) = VALUE ty_s_val( kind = z2ui5_cl_agent_viewxml=>cs_kind-null ).
        IF ls_cs-prop IS NOT INITIAL.
          ls_val = resolve( raw = z2ui5_cl_agent_viewxml=>attr( node = node( doc = ctx-doc
                                                                             id  = ls_cs-node )
                                                                name = ls_cs-prop )
                            ctx = ctx
                            row = lv_row ).
        ENDIF.
        INSERT VALUE #( name = ls_cs-name
                        val  = ls_val ) INTO TABLE ls_row-t_cell.
      ENDLOOP.
      IF ls_table-selection_field IS NOT INITIAL AND NOT line_exists( ls_row-t_cell[ name = ls_table-selection_field ] ). "#EC CI_SORTSEQ
        INSERT VALUE #( name = ls_table-selection_field
                        val  = model_get( model_key = ctx-model_key
                                          path      = ls_table-selection_field
                                          base      = lv_row ) ) INTO TABLE ls_row-t_cell.
      ENDIF.
      INSERT ls_row INTO TABLE ls_table-t_row.
    ENDDO.
    ls_table-truncated = xsdbool( lv_row_count > lines( ls_table-t_row ) ).
    " what the session needs to fill a row event's $parameters: the item
    " template and its cells (getCells( )[n] counts every cell of a
    " ColumnListItem; a grid table's row has the visible columns' templates)
    ls_table-node = node-id.
    ls_table-kind = kind.
    ls_table-dialog = dialog.
    ls_table-template = lv_template.
    LOOP AT lt_cell INTO ls_cell.
      IF ( kind = `m` AND ls_cell-prop IS INITIAL ) OR ( kind <> `m` AND ls_cell-visible = abap_true ).
        INSERT ls_cell-node INTO TABLE ls_table-t_cellnode.
      ENDIF.
    ENDLOOP.
    INSERT ls_table INTO TABLE mt_table.

    " the table's own events: a row event on the table is row scope, and so
    " is a selection dialog's confirm - the pick of a row
    LOOP AT node-t_attr INTO DATA(ls_attr).
      IF z2ui5_cl_agent_viewxml=>has_wire( ls_attr-value ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(lv_pick) = xsdbool( dialog = abap_true AND ls_attr-name = `confirm` ).
      DATA(ls_row_ctx) = ctx.
      IF ls_attr-name = `itemPress` OR ls_attr-name = `selectionChange` OR ls_attr-name = `rowSelectionChange`
          OR ls_attr-name = `cellClick` OR ls_attr-name = `rowPress` OR ls_attr-name = `delete`
          OR ls_attr-name = `beforeOpenContextMenu` OR lv_pick = abap_true.
        ls_row_ctx-row_table = lv_table_id.
      ENDIF.
      wires( node     = node
             ctx      = ls_row_ctx
             name     = name
             only     = ls_attr-name
             override = |{ z2ui5_cl_agent_viewxml=>clip( val = ls_table-label
                                                         len = 60 ) }: { ls_attr-name }|
             pick     = lv_pick ).
    ENDLOOP.

    " everything but the template: toolbars, the columns' own controls, ...
    LOOP AT node-t_child INTO DATA(lv_child).
      DATA(ls_child) = node( doc = ctx-doc
                             id  = lv_child ).
      DATA(lv_is_agg) = z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ).
      IF ( lv_is_agg = abap_true AND ls_child-local = agg ) OR lv_child = lv_template.
        CONTINUE.
      ENDIF.
      IF ls_child-local = `columns`.
        LOOP AT ls_child-t_child INTO DATA(lv_col).
          DATA(ls_colnode) = node( doc = ctx-doc
                                   id  = lv_col ).
          LOOP AT ls_colnode-t_child INTO DATA(lv_sub).
            DATA(ls_sub) = node( doc = ctx-doc
                                 id  = lv_sub ).
            DATA(lv_sub_agg) = z2ui5_cl_agent_viewxml=>is_aggregation( ls_sub ).
            IF lv_sub_agg = abap_true AND ls_sub-local = `template`.
              CONTINUE.
            ENDIF.
            " the header: its text is the column's label; a header that is
            " more than text (a select-all CheckBox, a sort Button) is on the
            " screen like any control
            IF lv_sub_agg = abap_true AND ls_sub-local <> `label` AND ls_sub-local <> `header`.
              walk( id  = lv_sub
                    ctx = ctx ).
              CONTINUE.
            ENDIF.
            DATA(lt_headers) = COND z2ui5_cl_agent_viewxml=>ty_t_int( WHEN lv_sub_agg = abap_true
                                                                       THEN controls_of( doc     = ctx-doc
                                                                                         t_child = ls_sub-t_child )
                                                                       ELSE VALUE #( ( lv_sub ) ) ).
            LOOP AT lt_headers INTO DATA(lv_h).
              DATA(lv_hn) = z2ui5_cl_agent_viewxml=>control_name( node( doc = ctx-doc
                                                                         id  = lv_h ) ).
              IF text_props( lv_hn ) IS NOT INITIAL OR lv_hn = `sap.m.Label`.
                CONTINUE.
              ENDIF.
              walk( id  = lv_h
                    ctx = ctx ).
            ENDLOOP.
          ENDLOOP.
          wires( node = ls_colnode
                 ctx  = ctx
                 name = z2ui5_cl_agent_viewxml=>control_name( ls_colnode ) ).
        ENDLOOP.
        CONTINUE.
      ENDIF.
      IF ls_child-local = `rowActionTemplate` OR ls_child-local = `rowSettingsTemplate`.
        CONTINUE.
      ENDIF.
      walk( id  = lv_child
            ctx = ctx ).
    ENDLOOP.

    " the template's wires, once, as row actions
    DATA(ls_tmpl_ctx) = ctx.
    ls_tmpl_ctx-row_table = lv_table_id.
    ls_tmpl_ctx-label = 0.
    IF lv_template > 0.
      walk_template( id  = lv_template
                     ctx = ls_tmpl_ctx ).
    ENDIF.
    IF kind = `ui`.
      LOOP AT lt_cell INTO ls_cell.
        walk_template( id  = ls_cell-node
                       ctx = ls_tmpl_ctx ).
      ENDLOOP.
    ENDIF.
    LOOP AT node-t_child INTO lv_child.
      DATA(lv_local) = node( doc = ctx-doc
                             id  = lv_child )-local.
      IF lv_local = `rowActionTemplate` OR lv_local = `rowSettingsTemplate`.
        DATA(ls_agg_ctx) = ls_tmpl_ctx.
        ls_agg_ctx-row_template = lv_local.
        walk_template( id  = lv_child
                       ctx = ls_agg_ctx ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD cell_ok.

    result = xsdbool( bool( node    = node
                            name    = `editable`
                            ctx     = ctx
                            row     = row
                            default = abap_true ) = abap_true
                  AND bool( node    = node
                            name    = `enabled`
                            ctx     = ctx
                            row     = row
                            default = abap_true ) = abap_true
                  AND bool( node    = node
                            name    = `displayOnly`
                            ctx     = ctx
                            row     = row
                            default = abap_false ) = abap_false ).

  ENDMETHOD.

  METHOD cell_editable.

    READ TABLE mt_table INTO DATA(ls_table) WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE ls_table-t_cellspec INTO DATA(ls_spec) WITH KEY name = column. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR ls_spec-check_editable = abap_false.
      " the selection field and the cells without a probe are editable as listed
      result = xsdbool( line_exists( ls_table-t_editable[ table_line = column ] ) ). "#EC CI_SORTSEQ
      RETURN.
    ENDIF.
    DATA(ls_ctx) = VALUE ty_s_ctx( doc       = ls_table-doc
                                   layer     = ls_table-layer
                                   model_key = ls_table-model_key ).
    result = cell_ok( ctx  = ls_ctx
                      node = node( doc = ls_table-doc
                                   id  = ls_spec-node )
                      row  = tree_path( model_key = ls_table-model_key
                                        path      = |{ ls_table-path }/{ row }| ) ).

  ENDMETHOD.

  METHOD source_value.

    DATA lv_found TYPE abap_bool.
    DATA lv_row TYPE string.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
    READ TABLE mt_action INTO DATA(ls_action) WITH KEY id = action_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR ls_action-node = 0.
      RETURN.
    ENDIF.
    DATA(ls_node) = node( doc = ls_action-doc
                          id  = ls_action-node ).
    DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                           name  = prop
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    IF ls_action-table IS NOT INITIAL AND row >= 0.
      READ TABLE mt_table INTO DATA(ls_table) WITH KEY id = ls_action-table. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        lv_row = tree_path( model_key = ls_table-model_key
                            path      = |{ ls_table-path }/{ row }| ).
      ENDIF.
    ENDIF.
    DATA(ls_ctx) = VALUE ty_s_ctx( doc       = ls_action-doc
                                   layer     = ls_action-layer
                                   model_key = ls_action-model_key ).
    DATA(ls_binding) = z2ui5_cl_agent_viewxml=>parse_binding( lv_raw ).
    IF ls_binding-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.
      RETURN.
    ENDIF.
    result = resolve( raw = lv_raw
                      ctx = ls_ctx
                      row = lv_row ).

  ENDMETHOD.

  METHOD template_value.

    DATA lv_found TYPE abap_bool.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
    READ TABLE mt_table INTO DATA(ls_table) WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR node = 0.
      RETURN.
    ENDIF.
    DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = me->node( doc = ls_table-doc
                                                                             id  = node )
                                                           name  = prop
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    IF z2ui5_cl_agent_viewxml=>parse_binding( lv_raw )-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.
      RETURN.
    ENDIF.
    DATA(ls_ctx) = VALUE ty_s_ctx( doc       = ls_table-doc
                                   layer     = ls_table-layer
                                   model_key = ls_table-model_key ).
    result = resolve( raw = lv_raw
                      ctx = ls_ctx
                      row = tree_path( model_key = ls_table-model_key
                                       path      = |{ ls_table-path }/{ row }| ) ).

  ENDMETHOD.

  METHOD walk_template.

    DATA lv_found TYPE abap_bool.

    DATA(ls_node) = node( doc = ctx-doc
                          id  = id ).
    IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true.
      LOOP AT ls_node-t_child INTO DATA(lv_child).
        walk_template( id  = lv_child
                       ctx = ctx ).
      ENDLOOP.
      RETURN.
    ENDIF.
    DATA(lv_visible) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                               name  = `visible`
                                                     IMPORTING found = lv_found ).
    IF lv_found = abap_true AND condense( lv_visible ) = `false`.
      RETURN.
    ENDIF.
    DATA(lv_name) = z2ui5_cl_agent_viewxml=>control_name( ls_node ).
    IF starts_sap( ls_node-ns ) = abap_false.
      note( |custom control { lv_name } in table { ctx-row_table } - not described| ).
    ENDIF.
    wires( node = ls_node
           ctx  = ctx
           name = lv_name ).
    DATA(ls_spec) = field_spec( lv_name ).
    IF ls_spec-found = abap_true AND ls_spec-items IS NOT INITIAL.
      RETURN.
    ENDIF.
    LOOP AT ls_node-t_child INTO lv_child.
      walk_template( id  = lv_child
                     ctx = ctx ).
    ENDLOOP.

  ENDMETHOD.

  METHOD column_header.

    DATA lv_found TYPE abap_bool.

    IF col = 0.
      RETURN.
    ENDIF.
    DATA(ls_col) = node( doc = ctx-doc
                         id  = col ).
    DATA(lv_header) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_col
                                                              name  = `header`
                                                    IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result = text_of_raw( raw = lv_header
                            ctx = ctx ).
      RETURN.
    ENDIF.
    DATA(lv_header_agg) = child_agg( doc   = ctx-doc
                                     node  = ls_col
                                     local = `header` ).
    DATA(lt_hnode) = controls_of( doc     = ctx-doc
                                  t_child = COND #( WHEN lv_header_agg > 0
                                                    THEN node( doc = ctx-doc
                                                               id  = lv_header_agg )-t_child
                                                    ELSE ls_col-t_child ) ).
    IF lt_hnode IS INITIAL.
      RETURN.
    ENDIF.
    DATA(ls_h) = node( doc = ctx-doc
                       id  = lt_hnode[ 1 ] ).
    z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_h
                                            name  = `text`
                                  IMPORTING found = lv_found ).
    result = text_of( node = ls_h
                      name = COND #( WHEN lv_found = abap_true THEN `text` ELSE `title` )
                      ctx  = ctx ).

  ENDMETHOD.

  METHOD header_title.

    LOOP AT node-t_child INTO DATA(lv_child).
      DATA(ls_child) = node( doc = ctx-doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_false.
        CONTINUE.
      ENDIF.
      IF ls_child-local <> `headerToolbar` AND ls_child-local <> `extension` AND ls_child-local <> `infoToolbar`
          AND ls_child-local <> `title` AND ls_child-local <> `toolbar`.
        CONTINUE.
      ENDIF.
      DATA(lv_title) = find_first( doc     = ctx-doc
                                   id      = lv_child
                                   control = `sap.m.Title` ).
      IF lv_title > 0.
        result = text_of( node = node( doc = ctx-doc
                                       id  = lv_title )
                          name = `text`
                          ctx  = ctx ).
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD find_first.

    LOOP AT node( doc = doc
                  id  = id )-t_child INTO DATA(lv_child).
      DATA(ls_child) = node( doc = doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_false
          AND z2ui5_cl_agent_viewxml=>control_name( ls_child ) = control.
        result = lv_child.
        RETURN.
      ENDIF.
      result = find_first( doc     = doc
                           id      = lv_child
                           control = control ).
      IF result > 0.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD descendants.

    LOOP AT node( doc = doc
                  id  = id )-t_child INTO DATA(lv_child).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( node( doc = doc
                                                       id  = lv_child ) ) = abap_false.
        INSERT lv_child INTO TABLE result.
      ENDIF.
      INSERT LINES OF descendants( doc = doc
                                   id  = lv_child ) INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD main_prop.

    DATA lv_found TYPE abap_bool.

    DATA(ls_spec) = field_spec( z2ui5_cl_agent_viewxml=>control_name( node ) ).
    IF ls_spec-found = abap_true.
      LOOP AT ls_spec-t_prop INTO DATA(lv_prop).
        z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                name  = lv_prop
                                      IMPORTING found = lv_found ).
        IF lv_found = abap_true.
          result = lv_prop.
          RETURN.
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDIF.
    LOOP AT VALUE string_table( ( `text` ) ( `title` ) ( `number` ) ( `value` ) ( `displayValue` ) ( `percentValue` )
                                ( `state` ) ( `selected` ) ( `src` ) ( `htmlText` ) ) INTO lv_prop.
      DATA(lv_raw) = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                             name  = lv_prop
                                                   IMPORTING found = lv_found ).
      IF lv_found = abap_true AND z2ui5_cl_agent_viewxml=>has_wire( lv_raw ) = abap_false.
        result = lv_prop.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD field_spec.

    " the editable value of each input-like control: which property carries
    " it, and what kind of value it is. text_label: the control's own text
    " names it when nothing else does (a CheckBox "Accept terms")
    result-found = abap_true.
    CASE name.
      WHEN `sap.m.Input`.
        result-t_prop = VALUE #( ( `value` ) ).
        result-kind = `input`.
      WHEN `sap.m.InputBase` OR `sap.m.MaskInput` OR `sap.m.SearchField` OR `sap.m.MultiInput`.
        result-t_prop = VALUE #( ( `value` ) ).
        result-kind = `text`.
      WHEN `sap.m.TextArea`.
        result-t_prop = VALUE #( ( `value` ) ).
        result-kind = `textarea`.
      WHEN `sap.m.StepInput` OR `sap.m.Slider` OR `sap.m.RangeSlider` OR `sap.m.RatingIndicator`.
        result-t_prop = VALUE #( ( `value` ) ).
        result-kind = `number`.
      WHEN `sap.m.DatePicker` OR `sap.m.DateRangeSelection`.
        result-t_prop = VALUE #( ( `value` ) ( `dateValue` ) ).
        result-kind = `date`.
      WHEN `sap.m.TimePicker`.
        result-t_prop = VALUE #( ( `value` ) ( `dateValue` ) ).
        result-kind = `time`.
      WHEN `sap.m.DateTimePicker`.
        result-t_prop = VALUE #( ( `value` ) ( `dateValue` ) ).
        result-kind = `datetime`.
      WHEN `sap.m.CheckBox` OR `sap.m.RadioButton`.
        result-t_prop = VALUE #( ( `selected` ) ).
        result-kind = `boolean`.
        result-text_label = abap_true.
      WHEN `sap.m.Switch`.
        result-t_prop = VALUE #( ( `state` ) ).
        result-kind = `boolean`.
      WHEN `sap.m.ToggleButton`.
        result-t_prop = VALUE #( ( `pressed` ) ).
        result-kind = `boolean`.
        result-text_label = abap_true.
      WHEN `sap.m.Select` OR `sap.m.SegmentedButton`.
        result-t_prop = VALUE #( ( `selectedKey` ) ).
        result-kind = `choice`.
        result-items = `key`.
      WHEN `sap.m.ComboBox`.
        result-t_prop = VALUE #( ( `selectedKey` ) ( `value` ) ).
        result-kind = `choice`.
        result-items = `key`.
      WHEN `sap.m.MultiComboBox`.
        result-t_prop = VALUE #( ( `selectedKeys` ) ).
        result-kind = `multichoice`.
        result-items = `key`.
      WHEN `sap.m.RadioButtonGroup`.
        result-t_prop = VALUE #( ( `selectedIndex` ) ).
        result-kind = `choice`.
        result-items = `index`.
      WHEN OTHERS.
        CLEAR result.
    ENDCASE.

  ENDMETHOD.

  METHOD table_spec.

    " the list controls whose bound aggregation is a table of rows
    result = abap_true.
    CASE name.
      WHEN `sap.m.Table` OR `sap.m.List` OR `sap.m.Tree` OR `sap.m.GridList` OR `sap.m.ListBase`.
        agg = `items`.
        kind = `m`.
      WHEN `sap.m.SelectDialog` OR `sap.m.TableSelectDialog`.
        " the selection dialogs: a list of rows to pick from; confirm is the
        " pick (a row event), multiSelect the selection mode
        agg = `items`.
        kind = `m`.
        dialog = abap_true.
      WHEN `sap.ui.table.Table` OR `sap.ui.table.TreeTable` OR `sap.ui.table.AnalyticalTable`.
        agg = `rows`.
        kind = `ui`.
      WHEN OTHERS.
        result = abap_false.
    ENDCASE.

  ENDMETHOD.

  METHOD text_props.

    " controls whose text is context worth handing an agent (outside tables)
    result = SWITCH #( name
                       WHEN `sap.m.Text` OR `sap.m.Title` OR `sap.m.ExpandableText` OR `sap.m.GenericTag` OR `sap.ui.core.Title`
                         THEN VALUE #( ( `text` ) )
                       WHEN `sap.m.ObjectStatus` OR `sap.m.ObjectAttribute` OR `sap.m.ObjectIdentifier`
                         THEN VALUE #( ( `title` ) ( `text` ) )
                       WHEN `sap.m.ObjectNumber`
                         THEN VALUE #( ( `number` ) ( `unit` ) )
                       WHEN `sap.m.ObjectHeader`
                         THEN VALUE #( ( `title` ) ( `number` ) )
                       WHEN `sap.m.FormattedText`
                         THEN VALUE #( ( `htmlText` ) )
                       WHEN `sap.m.IllustratedMessage`
                         THEN VALUE #( ( `title` ) ( `description` ) ) ).

  ENDMETHOD.

  METHOD kind_from_type.

    " a model type in a binding refines the kind (sap.ui.model.type.Integer)
    IF type IS INITIAL.
      RETURN.
    ENDIF.
    IF find( val = type
             sub = `Integer` ) >= 0 OR find( val = type
                                             sub = `Float` ) >= 0
        OR find( val = type
                 sub = `Decimal` ) >= 0 OR find( val = type
                                                 sub = `Currency` ) >= 0
        OR find( val = type
                 sub = `Unit` ) >= 0.
      result = `number`.
    ELSEIF find( val = type
                 sub = `DateTime` ) >= 0.
      result = `datetime`.
    ELSEIF find( val = type
                 sub = `Time` ) >= 0.
      result = `time`.
    ELSEIF find( val = type
                 sub = `Date` ) >= 0.
      result = `date`.
    ELSEIF find( val = type
                 sub = `Boolean` ) >= 0.
      result = `boolean`.
    ENDIF.

  ENDMETHOD.

  METHOD message_type.

    result = SWITCH #( val
                       WHEN `Error`       THEN `error`
                       WHEN `Warning`     THEN `warning`
                       WHEN `Success`     THEN `success`
                       WHEN `Information` THEN `info` ).

  ENDMETHOD.

  METHOD message_source.

    result = SWITCH #( name
                       WHEN `sap.m.MessagePopover` THEN `popover`
                       WHEN `sap.m.MessageView`    THEN `messageview` ).

  ENDMETHOD.

  METHOD icon_name.

    result = val.
    IF strlen( result ) >= 11 AND result(11) = `sap-icon://`.
      result = substring( val = result
                          off = 11 ).
      DATA(lv_slash) = find( val = result
                             sub = `/` ).
      IF lv_slash > 0.
        result = substring( val = result
                            off = lv_slash + 1 ).
      ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF `-` IN result WITH ` `.

  ENDMETHOD.

  METHOD strip_tags.

    DATA(lv_pos) = 0.
    DATA(lv_len) = strlen( val ).
    WHILE lv_pos < lv_len.
      DATA(lv_lt) = find( val = val
                          sub = `<`
                          off = lv_pos ).
      IF lv_lt < 0.
        result = result && substring( val = val
                                      off = lv_pos ).
        RETURN.
      ENDIF.
      DATA(lv_gt) = find( val = val
                          sub = `>`
                          off = lv_lt ).
      IF lv_gt < 0.
        result = result && substring( val = val
                                      off = lv_pos ).
        RETURN.
      ENDIF.
      result = result && substring( val = val
                                    off = lv_pos
                                    len = lv_lt - lv_pos ) && ` `.
      lv_pos = lv_gt + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD starts_sap.

    result = xsdbool( strlen( ns ) >= 4 AND ns(4) = `sap.` ).

  ENDMETHOD.

  METHOD ends_with.

    DATA(lv_len) = strlen( val ) - strlen( suffix ).
    IF lv_len < 0.
      RETURN.
    ENDIF.
    result = xsdbool( substring( val = val
                                 off = lv_len ) = suffix ).

  ENDMETHOD.

  METHOD set_policy.

    READ TABLE mt_action REFERENCE INTO DATA(lr_action) WITH KEY id = id. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      lr_action->policy = policy.
    ENDIF.

  ENDMETHOD.

  METHOD get_json.

    DATA lt_part TYPE string_table.
    DATA lt_item TYPE string_table.
    DATA lt_sub TYPE string_table.

    " fields
    LOOP AT mt_field INTO DATA(ls_field).
      DATA(lv_field) = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-id ) }| &&
                       |,"path":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-path ) }| &&
                       |,"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-name ) }| &&
                       |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-label ) }| &&
                       |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-control ) }| &&
                       |,"kind":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-kind ) }| &&
                       |,"value":{ z2ui5_cl_agent_viewxml=>val_to_json( ls_field-value ) }| &&
                       |,"required":{ COND #( WHEN ls_field-required = abap_true THEN `true` ELSE `false` ) }| &&
                       |,"editable":{ COND #( WHEN ls_field-editable = abap_true THEN `true` ELSE `false` ) }|.
      IF ls_field-has_values = abap_true.
        CLEAR lt_sub.
        LOOP AT ls_field-t_value INTO DATA(ls_choice).
          INSERT |\{"key":{ z2ui5_cl_agent_viewxml=>val_to_json( ls_choice-key ) },"text":{ z2ui5_cl_agent_viewxml=>json_string( ls_choice-text ) }\}|
                 INTO TABLE lt_sub.
        ENDLOOP.
        lv_field = |{ lv_field },"values":[{ concat_lines_of( table = lt_sub
                                                              sep   = `,` ) }]|.
      ENDIF.
      lv_field = |{ lv_field },"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-layer ) }\}|.
      INSERT lv_field INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_fields) = concat_lines_of( table = lt_item
                                       sep   = `,` ).

    " actions
    CLEAR lt_item.
    LOOP AT mt_action INTO DATA(ls_action).
      DATA(lv_action) = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-id ) }| &&
                        |,"event":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-event ) }| &&
                        |,"args":[{ concat_lines_of( table = ls_action-t_arg_json
                                                     sep   = `,` ) }]| &&
                        |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-label ) }| &&
                        |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-control ) }| &&
                        |,"trigger":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-trigger ) }| &&
                        |,"enabled":{ COND #( WHEN ls_action-enabled = abap_true THEN `true` ELSE `false` ) }| &&
                        |,"scope":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-scope ) }|.
      IF ls_action-scope = `row`.
        lv_action = |{ lv_action },"table":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-table ) }|.
      ENDIF.
      lv_action = |{ lv_action },"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-layer ) }|.
      IF ls_action-policy IS NOT INITIAL AND ls_action-policy <> `allowed`.
        lv_action = |{ lv_action },"policy":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-policy ) }|.
      ENDIF.
      INSERT |{ lv_action }\}| INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_actions) = concat_lines_of( table = lt_item
                                        sep   = `,` ).

    " tables
    CLEAR lt_item.
    LOOP AT mt_table INTO DATA(ls_table).
      CLEAR lt_sub.
      LOOP AT ls_table-t_column INTO DATA(ls_column).
        INSERT |\{"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_column-name ) },"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_column-label ) }\}|
               INTO TABLE lt_sub.
      ENDLOOP.
      DATA(lv_columns) = concat_lines_of( table = lt_sub
                                          sep   = `,` ).
      CLEAR lt_sub.
      LOOP AT ls_table-t_row INTO DATA(ls_row).
        CLEAR lt_part.
        LOOP AT ls_row-t_cell INTO DATA(ls_cell).
          INSERT |{ z2ui5_cl_agent_viewxml=>json_string( ls_cell-name ) }:{ z2ui5_cl_agent_viewxml=>val_to_json( ls_cell-val ) }|
                 INTO TABLE lt_part.
        ENDLOOP.
        INSERT |\{{ concat_lines_of( table = lt_part
                                     sep   = `,` ) }\}| INTO TABLE lt_sub.
      ENDLOOP.
      DATA(lv_rows) = concat_lines_of( table = lt_sub
                                       sep   = `,` ).
      CLEAR lt_sub.
      LOOP AT ls_table-t_editable INTO DATA(lv_editable).
        INSERT z2ui5_cl_agent_viewxml=>json_string( lv_editable ) INTO TABLE lt_sub.
      ENDLOOP.
      DATA(lv_table) = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-id ) }| &&
                       |,"path":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-path ) }| &&
                       |,"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-name ) }| &&
                       |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-label ) }| &&
                       |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-control ) }| &&
                       |,"columns":[{ lv_columns }]| &&
                       |,"rowCount":{ ls_table-row_count }| &&
                       |,"rows":[{ lv_rows }]| &&
                       |,"truncated":{ COND #( WHEN ls_table-truncated = abap_true THEN `true` ELSE `false` ) }| &&
                       |,"selectionMode":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-selection_mode ) }| &&
                       |,"editableCells":[{ concat_lines_of( table = lt_sub
                                                             sep   = `,` ) }]| &&
                       |,"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-layer ) }|.
      IF ls_table-selection_field IS NOT INITIAL.
        lv_table = |{ lv_table },"selectionField":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-selection_field ) }|.
      ENDIF.
      INSERT |{ lv_table }\}| INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_tables) = concat_lines_of( table = lt_item
                                       sep   = `,` ).

    " messages
    CLEAR lt_item.
    LOOP AT mt_message INTO DATA(ls_message).
      DATA(lv_message) = |\{"type":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-type ) }| &&
                         |,"text":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-text ) }| &&
                         |,"source":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-source ) }|.
      IF ls_message-field IS NOT INITIAL.
        lv_message = |{ lv_message },"field":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-field ) }|.
      ENDIF.
      IF ls_message-subtitle IS NOT INITIAL.
        lv_message = |{ lv_message },"subtitle":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-subtitle ) }|.
      ENDIF.
      IF ls_message-description IS NOT INITIAL.
        lv_message = |{ lv_message },"description":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-description ) }|.
      ENDIF.
      INSERT |{ lv_message }\}| INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_messages) = concat_lines_of( table = lt_item
                                         sep   = `,` ).

    CLEAR lt_item.
    LOOP AT mt_text INTO DATA(lv_text).
      INSERT z2ui5_cl_agent_viewxml=>json_string( lv_text ) INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_texts) = concat_lines_of( table = lt_item
                                      sep   = `,` ).

    CLEAR lt_item.
    LOOP AT mt_unsupported INTO DATA(lv_unsupported).
      INSERT z2ui5_cl_agent_viewxml=>json_string( lv_unsupported ) INTO TABLE lt_item.
    ENDLOOP.
    DATA(lv_unsupported_json) = concat_lines_of( table = lt_item
                                                 sep   = `,` ).

    result = |\{"snapshotVersion":{ c_version }| &&
             |,"session":{ z2ui5_cl_agent_viewxml=>json_string( mv_session ) }| &&
             |,"app":{ z2ui5_cl_agent_viewxml=>json_string( mv_app ) }| &&
             |,"title":{ z2ui5_cl_agent_viewxml=>json_string( mv_title ) }| &&
             |,"layer":{ z2ui5_cl_agent_viewxml=>json_string( mv_layer ) }| &&
             |,"fields":[{ lv_fields }]| &&
             |,"actions":[{ lv_actions }]| &&
             |,"tables":[{ lv_tables }]| &&
             |,"messages":[{ lv_messages }]| &&
             |,"texts":[{ lv_texts }]| &&
             |,"unsupported":[{ lv_unsupported_json }]|.
    IF mt_pending IS NOT INITIAL.
      CLEAR lt_item.
      LOOP AT mt_pending INTO DATA(lv_pending).
        INSERT z2ui5_cl_agent_viewxml=>json_string( lv_pending ) INTO TABLE lt_item.
      ENDLOOP.
      result = |{ result },"pending":[{ concat_lines_of( table = lt_item
                                                         sep   = `,` ) }]|.
    ENDIF.
    result = |{ result }\}|.

  ENDMETHOD.

ENDCLASS.
