"! What is on an abap2UI5 screen, as data an agent can act on: the layers
"! of the headless frontend simulator (z2ui5_cl_frontend_sim,
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
    TYPES ty_t_pending TYPE STANDARD TABLE OF ty_s_pending WITH DEFAULT KEY.

    TYPES:
      "! session/app: what the snapshot names; t_layer: the open layers
      "! (simulator get_layers( )); t_custom: the T_CUSTOM entries of the last
      "! response as raw JSON arrays; max_rows: rows per table (0 - 200).
      BEGIN OF ty_s_input,
        session   TYPE string,
        app       TYPE string,
        t_layer   TYPE z2ui5_cl_frontend_sim=>ty_t_layer,
        t_custom  TYPE string_table,
        t_pending TYPE ty_t_pending,
        max_rows  TYPE i,
      END OF ty_s_input.

    TYPES:
      BEGIN OF ty_s_choice,
        key  TYPE ty_s_val,
        text TYPE string,
      END OF ty_s_choice.
    TYPES ty_t_choice TYPE STANDARD TABLE OF ty_s_choice WITH DEFAULT KEY.

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
    TYPES ty_t_field TYPE STANDARD TABLE OF ty_s_field WITH DEFAULT KEY.

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
    TYPES ty_t_action TYPE STANDARD TABLE OF ty_s_action WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_column,
        name  TYPE string,
        label TYPE string,
      END OF ty_s_column.
    TYPES ty_t_column TYPE STANDARD TABLE OF ty_s_column WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_cell,
        name TYPE string,
        val  TYPE ty_s_val,
      END OF ty_s_cell.
    TYPES ty_t_cell TYPE STANDARD TABLE OF ty_s_cell WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_s_row,
        t_cell TYPE ty_t_cell,
      END OF ty_s_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_s_row WITH DEFAULT KEY.

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
    TYPES ty_t_cellspec TYPE STANDARD TABLE OF ty_s_cellspec WITH DEFAULT KEY.

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
    TYPES ty_t_table TYPE STANDARD TABLE OF ty_s_table WITH DEFAULT KEY.

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
    TYPES ty_t_message TYPE STANDARD TABLE OF ty_s_message WITH DEFAULT KEY.

    TYPES:
      "! The model paths a text of /texts was read from (absolute, or
      "! relative to its binding context) - kept beside the JSON, not in it
      "! (the snapshot is a contract), so the copilot can mask a text that
      "! shows a sensitive field.
      BEGIN OF ty_s_text_source,
        text   TYPE string,
        t_path TYPE string_table,
      END OF ty_s_text_source.
    TYPES ty_t_text_source TYPE STANDARD TABLE OF ty_s_text_source WITH DEFAULT KEY.

    TYPES:
      "! What a value key of app_act names (resolve_target): a field (its
      "! index in mt_field) or a table cell (the table's index in mt_table,
      "! the 0-based row, the column).
      BEGIN OF ty_s_target,
        is_cell TYPE abap_bool,
        field   TYPE i,
        table   TYPE i,
        row     TYPE i,
        column  TYPE string,
      END OF ty_s_target.

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

    "! The values the client changed and has not sent yet, with the model
    "! each belongs to - /pending in the JSON names the paths only.
    METHODS get_pending
      RETURNING
        VALUE(result) TYPE ty_t_pending.

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

    "! What a value key names: a field by id, by model path, by name in any
    "! case - in that order -, or a table cell "&lt;table path or
    "! id&gt;/&lt;row&gt;/&lt;COLUMN&gt;"; found is false when it names nothing.
    METHODS resolve_target
      IMPORTING
        key           TYPE clike
      EXPORTING
        found         TYPE abap_bool
      RETURNING
        VALUE(result) TYPE ty_s_target.

    "! Whether the value a key names is protected - never shown to a
    "! language model, masked in the audit log: a password field
    "! (is_secret( )), or a field or cell the app or the settings mark
    "! sensitive; a key the screen does not know by the key alone
    "! (key_sensitive( )).
    METHODS is_protected
      IMPORTING
        key           TYPE clike
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! Whether a key marks a value sensitive by itself, with no screen to
    "! resolve it against: as a path and as a name, and a name like IBAN as
    "! the path /IBAN too - the shape the sensitive rules are written in.
    CLASS-METHODS key_sensitive
      IMPORTING
        app           TYPE clike
        key           TYPE clike
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The action an event names: an action id first; else, of the actions
    "! of that event, the enabled ones (all when none is) - with a row the
    "! first row action, without one the first screen action, else the
    "! first (mcp-server lib/appclient.mjs findAction). backend_only:
    "! never a frontend action (the two client-side closes). Initial when
    "! nothing matches.
    METHODS find_action
      IMPORTING
        event         TYPE clike
        has_row       TYPE abap_bool
        backend_only  TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result) TYPE ty_s_action.

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
    TYPES ty_t_doc TYPE STANDARD TABLE OF ty_s_doc WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_model,
        key  TYPE string,
        json TYPE REF TO z2ui5_if_ajson,
      END OF ty_s_model.
    TYPES ty_t_model TYPE STANDARD TABLE OF ty_s_model WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_label,
        text     TYPE string,
        required TYPE abap_bool,
        uses     TYPE i,
      END OF ty_s_label.
    TYPES ty_t_label TYPE STANDARD TABLE OF ty_s_label WITH DEFAULT KEY.

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
    TYPES ty_t_mgr_msg TYPE STANDARD TABLE OF ty_s_mgr_msg WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_title,
        layer TYPE string,
        title TYPE string,
      END OF ty_s_title.
    TYPES ty_t_title TYPE STANDARD TABLE OF ty_s_title WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_s_cellsrc,
        node    TYPE i,
        prop    TYPE string,
        header  TYPE string,
        visible TYPE abap_bool,
      END OF ty_s_cellsrc.
    TYPES ty_t_cellsrc TYPE STANDARD TABLE OF ty_s_cellsrc WITH DEFAULT KEY.

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

    "! The value at a model path. An object or array also comes as JSON
    "! (slice and stringify - a walk over the whole model tree) unless
    "! check_json is false: then only its kind and number of members.
    METHODS model_get
      IMPORTING
        model_key     TYPE string
        path          TYPE string
        base          TYPE string OPTIONAL
        check_json    TYPE abap_bool DEFAULT abap_true
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
        default_value TYPE abap_bool
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

    CREATE OBJECT result.
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

    DATA temp66 TYPE string.
    TYPES temp1 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp1.
    DATA temp67 TYPE string.
    DATA temp68 TYPE string.
    DATA lv_first LIKE temp67.
    temp66 = path.


    SPLIT temp66 AT `/` INTO TABLE lt_seg.
    DELETE lt_seg WHERE table_line IS INITIAL.
    " read ahead: the 7.02 downport hoists a table expression out of the
    " condition, and "/" has no first segment

    CLEAR temp67.

    READ TABLE lt_seg INTO temp68 INDEX 1.
    IF sy-subrc = 0.
      temp67 = temp68.
    ENDIF.

    lv_first = temp67.
    IF lines( lt_seg ) > 1 AND lv_first = `XX`.
      DELETE lt_seg INDEX 1.
    ENDIF.
    result = concat_lines_of( table = lt_seg
                              sep   = `-` ).

  ENDMETHOD.

  METHOD layer_of_slot.

    DATA temp69 TYPE string.
    CASE slot.
      WHEN z2ui5_if_client=>cs_view-popup.
        temp69 = `popup`.
      WHEN z2ui5_if_client=>cs_view-popover.
        temp69 = `popover`.
      WHEN OTHERS.
        temp69 = `main`.
    ENDCASE.
    result = temp69.

  ENDMETHOD.

  METHOD model_init.

    " MAIN and the nested views share one model; popup and popover own a copy
    DATA ls_layer LIKE LINE OF ms_input-t_layer.
      DATA temp70 TYPE string.
      DATA lv_key LIKE temp70.
      DATA temp71 LIKE sy-subrc.
      DATA lv_model LIKE ls_layer-model.
          DATA temp72 TYPE REF TO z2ui5_if_ajson.
          DATA lo_json LIKE temp72.
          DATA temp73 TYPE REF TO z2ui5_if_ajson.
      DATA temp74 TYPE z2ui5_cl_agent_snapshot=>ty_s_model.
    DATA ls_pending LIKE LINE OF ms_input-t_pending.
      DATA lo_model TYPE REF TO z2ui5_if_ajson.
      DATA lv_tree TYPE string.
    LOOP AT ms_input-t_layer INTO ls_layer.

      CASE ls_layer-layer.
        WHEN z2ui5_if_client=>cs_view-popup.
          temp70 = cs_model-popup.
        WHEN z2ui5_if_client=>cs_view-popover.
          temp70 = cs_model-popover.
        WHEN OTHERS.
          temp70 = cs_model-main.
      ENDCASE.

      lv_key = temp70.

      READ TABLE mt_model WITH KEY key = lv_key TRANSPORTING NO FIELDS.
      temp71 = sy-subrc.
      IF temp71 = 0. "#EC CI_SORTSEQ
        CONTINUE.
      ENDIF.

      lv_model = ls_layer-model.
      IF lv_model IS INITIAL.
        lv_model = `{}`.
      ENDIF.
      TRY.

          temp72 ?= z2ui5_cl_ajson=>parse( iv_json = lv_model iv_keep_item_order = abap_true ).

          lo_json = temp72.
        CATCH cx_root.

          temp73 ?= z2ui5_cl_ajson=>create_empty( iv_keep_item_order = abap_true ).
          lo_json = temp73.
      ENDTRY.

      CLEAR temp74.
      temp74-key = lv_key.
      temp74-json = lo_json.
      INSERT temp74 INTO TABLE mt_model.
    ENDLOOP.

    " the pending edits are what the client shows - applied before reading

    LOOP AT ms_input-t_pending INTO ls_pending.

      lo_model = model_json( ls_pending-model_key ).
      IF lo_model IS NOT BOUND.
        CONTINUE.
      ENDIF.

      lv_tree = tree_path( model_key = ls_pending-model_key
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

    DATA ls_model TYPE z2ui5_cl_agent_snapshot=>ty_s_model.
    READ TABLE mt_model INTO ls_model WITH KEY key = model_key. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_model-json.
    ENDIF.

  ENDMETHOD.

  METHOD tree_path.

    DATA lv_model_key TYPE string.
    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    DATA temp75 TYPE string.
    TYPES temp2 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp2.
    DATA temp76 TYPE string.
    DATA lv_cur LIKE temp76.
    DATA lv_seg LIKE LINE OF lt_seg.
      DATA temp77 TYPE string.
      DATA lv_type TYPE z2ui5_if_ajson_types=>ty_node_type.
        DATA temp78 TYPE i.
    DATA temp79 TYPE string.

    lv_model_key = model_key.

    lo_json = model_json( lv_model_key ).
    IF lo_json IS NOT BOUND.
      RETURN.
    ENDIF.


    temp75 = path.


    SPLIT temp75 AT `/` INTO TABLE lt_seg.
    DELETE lt_seg WHERE table_line IS INITIAL.

    temp76 = base.

    lv_cur = temp76.

    LOOP AT lt_seg INTO lv_seg.

      IF lv_cur IS INITIAL.
        temp77 = `/`.
      ELSE.
        temp77 = lv_cur.
      ENDIF.

      lv_type = lo_json->get_node_type( temp77 ).
      IF lv_type = z2ui5_if_ajson_types=>node_type-array.
        IF lv_seg CN `0123456789`.
          RETURN.
        ENDIF.

        temp78 = lv_seg.
        lv_seg = |{ temp78 + 1 }|.
      ELSEIF lv_type <> z2ui5_if_ajson_types=>node_type-object.
        RETURN.
      ENDIF.
      lv_cur = |{ lv_cur }/{ lv_seg }|.
    ENDLOOP.

    IF lv_cur IS INITIAL.
      temp79 = `/`.
    ELSE.
      temp79 = lv_cur.
    ENDIF.
    result = temp79.

  ENDMETHOD.

  METHOD model_get.
    DATA lo_json TYPE REF TO z2ui5_if_ajson.
    DATA lv_tree TYPE string.
        DATA temp80 TYPE z2ui5_cl_agent_viewxml=>ty_s_val-kind.
              DATA temp81 TYPE z2ui5_cl_agent_viewxml=>ty_s_val-json.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.

    lo_json = model_json( model_key ).
    IF lo_json IS NOT BOUND.
      RETURN.
    ENDIF.

    lv_tree = tree_path( model_key = model_key
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

        IF lo_json->get_node_type( lv_tree ) = z2ui5_if_ajson_types=>node_type-array.
          temp80 = z2ui5_cl_agent_viewxml=>cs_kind-array.
        ELSE.
          temp80 = z2ui5_cl_agent_viewxml=>cs_kind-object.
        ENDIF.
        result-kind = temp80.
        IF check_json = abap_true.
          TRY.
              result-json = lo_json->slice( lv_tree )->stringify( ).
            CATCH cx_root.

              IF result-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
                temp81 = `[]`.
              ELSE.
                temp81 = `{}`.
              ENDIF.
              result-json = temp81.
          ENDTRY.
        ENDIF.
        result-num = lines( lo_json->members( lv_tree ) ).
    ENDCASE.

  ENDMETHOD.

  METHOD get_pending.

    result = ms_input-t_pending.

  ENDMETHOD.

  METHOD model_value.

    DATA lv_model_key TYPE string.
    DATA lv_base TYPE string.
      DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA temp82 TYPE string.

    lv_model_key = model_key.
    IF table_id IS NOT INITIAL AND row >= 0.

      READ TABLE mt_table INTO ls_table WITH KEY id = table_id. "#EC CI_SORTSEQ
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

    temp82 = path.
    result = model_get( model_key = lv_model_key
                        path      = temp82
                        base      = lv_base ).

  ENDMETHOD.

  METHOD is_secret.

    DATA ls_field TYPE z2ui5_cl_agent_snapshot=>ty_s_field.
    READ TABLE mt_field INTO ls_field WITH KEY id = field_id. "#EC CI_SORTSEQ
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

  METHOD resolve_target.
    DATA lv_upper TYPE string.
    DATA ls_field LIKE LINE OF mt_field.
    DATA temp83 TYPE string.
    DATA lv_key LIKE temp83.
    TYPES temp3 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
DATA lt_seg TYPE temp3.
    DATA lv_count TYPE i.
    DATA lv_column LIKE LINE OF lt_seg.
    FIELD-SYMBOLS <temp17> LIKE LINE OF lt_seg.
    DATA temp18 LIKE sy-tabix.
    DATA lv_row LIKE LINE OF lt_seg.
    FIELD-SYMBOLS <temp19> LIKE LINE OF lt_seg.
    DATA temp20 LIKE sy-tabix.
    DATA lv_table TYPE string.
    DATA ls_table LIKE LINE OF mt_table.
        DATA temp21 TYPE i.

    found = abap_false.
    LOOP AT mt_field TRANSPORTING NO FIELDS WHERE id = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.
    LOOP AT mt_field TRANSPORTING NO FIELDS WHERE path = key. "#EC CI_SORTSEQ
      found = abap_true.
      result-field = sy-tabix.
      RETURN.
    ENDLOOP.

    lv_upper = to_upper( key ).

    LOOP AT mt_field INTO ls_field.
      IF to_upper( ls_field-name ) = lv_upper.
        found = abap_true.
        result-field = sy-tabix.
        RETURN.
      ENDIF.
    ENDLOOP.

    " a table cell: /T_TAB/3/QTY or t1/3/QTY

    temp83 = key.

    lv_key = temp83.


    SPLIT lv_key AT `/` INTO TABLE lt_seg.

    lv_count = lines( lt_seg ).
    IF lv_count < 3.
      RETURN.
    ENDIF.



    temp18 = sy-tabix.
    READ TABLE lt_seg INDEX lv_count ASSIGNING <temp17>.
    sy-tabix = temp18.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_column = <temp17>.



    temp20 = sy-tabix.
    READ TABLE lt_seg INDEX lv_count - 1 ASSIGNING <temp19>.
    sy-tabix = temp20.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    lv_row = <temp19>.
    " at most 9 digits - a longer row does not fit the integer it becomes
    IF lv_row IS INITIAL OR lv_row CN `0123456789` OR strlen( lv_row ) > 9 OR lv_column IS INITIAL
        OR lv_column(1) CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_`
        OR lv_column CN `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-`.
      RETURN.
    ENDIF.

    lv_table = substring( val = lv_key
                                len = strlen( lv_key ) - strlen( lv_row ) - strlen( lv_column ) - 2 ).

    LOOP AT mt_table INTO ls_table.
      IF ls_table-path = lv_table OR ls_table-id = lv_table.
        found = abap_true.
        CLEAR result.
        result-is_cell = abap_true.
        result-table = sy-tabix.

        temp21 = lv_row.
        result-row = temp21.
        result-column = lv_column.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD is_protected.

    DATA lv_found TYPE abap_bool.

    DATA ls_target TYPE z2ui5_cl_agent_snapshot=>ty_s_target.
      DATA ls_field LIKE LINE OF mt_field.
      FIELD-SYMBOLS <temp22> LIKE LINE OF mt_field.
      DATA temp23 LIKE sy-tabix.
      DATA temp1 TYPE xsdboolean.
      DATA ls_table LIKE LINE OF mt_table.
      FIELD-SYMBOLS <temp24> LIKE LINE OF mt_table.
      DATA temp25 LIKE sy-tabix.
    ls_target = resolve_target( EXPORTING key   = key
                                      IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      result = key_sensitive( app = mv_app
                              key = key ).
    ELSEIF ls_target-is_cell = abap_false.



      temp23 = sy-tabix.
      READ TABLE mt_field INDEX ls_target-field ASSIGNING <temp22>.
      sy-tabix = temp23.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      ls_field = <temp22>.

      temp1 = boolc( is_secret( ls_field-id ) = abap_true OR z2ui5_cl_agent_settings=>check_sensitive( app = mv_app path = ls_field-path name = ls_field-name ) = abap_true ).
      result = temp1.
    ELSE.



      temp25 = sy-tabix.
      READ TABLE mt_table INDEX ls_target-table ASSIGNING <temp24>.
      sy-tabix = temp25.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      ls_table = <temp24>.
      result = z2ui5_cl_agent_settings=>check_sensitive( app  = mv_app
                                                         path = |{ ls_table-path }/{ ls_target-row }/{ ls_target-column }|
                                                         name = ls_target-column ).
    ENDIF.

  ENDMETHOD.

  METHOD key_sensitive.

    result = z2ui5_cl_agent_settings=>check_sensitive( app  = app
                                                       path = key
                                                       name = key ).
    IF result = abap_false.
      result = z2ui5_cl_agent_settings=>check_sensitive( app  = app
                                                         path = |/{ key }|
                                                         name = key ).
    ENDIF.

  ENDMETHOD.

  METHOD find_action.

    DATA lt_named TYPE ty_t_action.
    DATA lt_enabled TYPE ty_t_action.

    DATA ls_action LIKE LINE OF mt_action.
    DATA temp84 TYPE ty_t_action.
    DATA lt_pool LIKE temp84.
    FIELD-SYMBOLS <temp85> LIKE LINE OF lt_pool.
    DATA temp86 LIKE sy-tabix.
    LOOP AT mt_action INTO ls_action WHERE id = event. "#EC CI_SORTSEQ
      IF backend_only = abap_false OR ls_action-frontend IS INITIAL.
        result = ls_action.
        RETURN.
      ENDIF.
    ENDLOOP.
    LOOP AT mt_action INTO ls_action WHERE event = event. "#EC CI_SORTSEQ
      IF backend_only = abap_true AND ls_action-frontend IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      INSERT ls_action INTO TABLE lt_named.
      IF ls_action-enabled = abap_true.
        INSERT ls_action INTO TABLE lt_enabled.
      ENDIF.
    ENDLOOP.
    IF lt_named IS INITIAL.
      RETURN.
    ENDIF.

    IF lt_enabled IS NOT INITIAL.
      temp84 = lt_enabled.
    ELSE.
      temp84 = lt_named.
    ENDIF.

    lt_pool = temp84.
    IF has_row = abap_true.
      READ TABLE lt_pool INTO result WITH KEY scope = `row`. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
    ELSE.
      " without a row, a screen action of that name before a row action -
      " a "delete selected" button after a table with a DELETE per row was
      " reachable by its id only
      LOOP AT lt_pool INTO result WHERE scope <> `row`. "#EC CI_SORTSEQ
        RETURN.
      ENDLOOP.
    ENDIF.


    temp86 = sy-tabix.
    READ TABLE lt_pool INDEX 1 ASSIGNING <temp85>.
    sy-tabix = temp86.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    result = <temp85>.

  ENDMETHOD.

  METHOD table_rows.

    DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    READ TABLE mt_table INTO ls_table WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_table-row_count.
    ENDIF.

  ENDMETHOD.

  METHOD node.

    DATA ls_doc TYPE z2ui5_cl_agent_snapshot=>ty_s_doc.
    READ TABLE mt_doc INDEX doc INTO ls_doc.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE ls_doc-t_node INDEX id INTO result.

  ENDMETHOD.

  METHOD note.

    DATA temp87 LIKE sy-subrc.
    READ TABLE mt_unsupported WITH KEY table_line = val TRANSPORTING NO FIELDS.
    temp87 = sy-subrc.
    IF temp87 = 0 OR lines( mt_unsupported ) >= c_max_unsupported. "#EC CI_SORTSEQ
      RETURN.
    ENDIF.
    INSERT val INTO TABLE mt_unsupported.

  ENDMETHOD.

  METHOD text_paths.

    result = binding_paths( z2ui5_cl_agent_viewxml=>parse_binding( raw ) ).

  ENDMETHOD.

  METHOD binding_paths.

    DATA ls_binding LIKE binding.
        DATA ls_part LIKE LINE OF ls_binding-t_part.
    ls_binding = binding.
    CASE ls_binding-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-literal.
        RETURN.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-path.
        INSERT ls_binding-path INTO TABLE result.
      WHEN z2ui5_cl_agent_viewxml=>cs_binding-expression.
        result = z2ui5_cl_agent_viewxml=>expression_refs( ls_binding-expression ).
      WHEN OTHERS.

        LOOP AT ls_binding-t_part INTO ls_part WHERE is_path = abap_true. "#EC CI_SORTSEQ
          INSERT ls_part-path INTO TABLE result.
        ENDLOOP.
    ENDCASE.

  ENDMETHOD.

  METHOD add_text.

    DATA lv_text TYPE string.
    DATA temp88 LIKE sy-subrc.
      DATA temp89 TYPE z2ui5_cl_agent_snapshot=>ty_s_text_source.
    lv_text = z2ui5_cl_agent_viewxml=>clip( val ).

    READ TABLE mt_text WITH KEY table_line = lv_text TRANSPORTING NO FIELDS.
    temp88 = sy-subrc.
    IF lv_text IS INITIAL OR temp88 = 0 OR lines( mt_text ) >= c_max_texts. "#EC CI_SORTSEQ
      RETURN.
    ENDIF.
    INSERT lv_text INTO TABLE mt_text.
    IF t_path IS NOT INITIAL.

      CLEAR temp89.
      temp89-text = lv_text.
      temp89-t_path = t_path.
      INSERT temp89 INTO TABLE mt_text_source.
    ENDIF.

  ENDMETHOD.

  METHOD label_new.

    DATA temp90 TYPE z2ui5_cl_agent_snapshot=>ty_s_label.
    CLEAR temp90.
    temp90-text = text.
    temp90-required = required.
    INSERT temp90 INTO TABLE mt_label.
    result = lines( mt_label ).

  ENDMETHOD.

  METHOD where_text.

    DATA lt_last TYPE string_table.

    DATA lv_from TYPE i.
    DATA lv_where LIKE LINE OF ctx-t_where.
    lv_from = lines( ctx-t_where ) - 2.
    IF lv_from < 1.
      lv_from = 1.
    ENDIF.

    LOOP AT ctx-t_where INTO lv_where FROM lv_from.
      INSERT lv_where INTO TABLE lt_last.
    ENDLOOP.
    result = concat_lines_of( table = lt_last
                              sep   = ` > ` ).

  ENDMETHOD.

  METHOD analyze.

    DATA lt_slot TYPE string_table.
    DATA lt_text TYPE string_table.
    DATA lv_popup TYPE abap_bool.
    DATA temp26 LIKE sy-subrc.
    DATA temp27 LIKE sy-subrc.
    DATA temp28 LIKE sy-tabix.
    DATA temp2 TYPE xsdboolean.
    DATA lv_popover TYPE abap_bool.
    DATA temp29 LIKE sy-subrc.
    DATA temp30 LIKE sy-subrc.
    DATA temp31 LIKE sy-tabix.
    DATA temp3 TYPE xsdboolean.
    DATA temp91 TYPE string.
    DATA lv_slot LIKE LINE OF lt_slot.
      DATA ls_layer TYPE z2ui5_cl_frontend_sim=>ty_s_layer.
      DATA temp92 TYPE ty_s_doc.
      DATA temp32 TYPE z2ui5_cl_agent_snapshot=>ty_s_doc-model_key.
      DATA ls_doc LIKE temp92.
      DATA lv_doc TYPE i.
      DATA temp93 TYPE ty_s_ctx.
      DATA ls_ctx LIKE temp93.
      FIELD-SYMBOLS <temp94> LIKE LINE OF ls_doc-t_node.
      DATA temp95 LIKE sy-tabix.
    DATA ls_mgr LIKE LINE OF mt_mgr_msg.
      DATA temp96 TYPE ty_s_message.
      DATA temp33 TYPE z2ui5_cl_agent_snapshot=>ty_s_message-source.
      DATA ls_msg LIKE temp96.
        DATA ls_field TYPE z2ui5_cl_agent_snapshot=>ty_s_field.
        DATA temp97 TYPE z2ui5_cl_agent_snapshot=>ty_s_message-field.
    DATA ls_title TYPE z2ui5_cl_agent_snapshot=>ty_s_title.
    DATA lv_text LIKE LINE OF mt_text.
      DATA temp98 LIKE sy-subrc.

    model_init( ).

    " which layers are described: a popup (Dialog) is modal - while one is
    " open only the popup and a popover on top of it are; a popover is not
    " modal, the page stays described beside it




    temp27 = sy-subrc.
    temp28 = sy-tabix.
    READ TABLE ms_input-t_layer WITH KEY layer = z2ui5_if_client=>cs_view-popup TRANSPORTING NO FIELDS.
    temp26 = sy-subrc.
    sy-subrc = temp27.
    sy-tabix = temp28.

    temp2 = boolc( temp26 = 0 ).
    lv_popup = temp2. "#EC CI_SORTSEQ




    temp30 = sy-subrc.
    temp31 = sy-tabix.
    READ TABLE ms_input-t_layer WITH KEY layer = z2ui5_if_client=>cs_view-popover TRANSPORTING NO FIELDS.
    temp29 = sy-subrc.
    sy-subrc = temp30.
    sy-tabix = temp31.

    temp3 = boolc( temp29 = 0 ).
    lv_popover = temp3. "#EC CI_SORTSEQ
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

    IF lv_popover = abap_true.
      temp91 = `popover`.
    ELSEIF lv_popup = abap_true.
      temp91 = `popup`.
    ELSE.
      temp91 = `main`.
    ENDIF.
    mv_layer = temp91.


    LOOP AT lt_slot INTO lv_slot.

      READ TABLE ms_input-t_layer INTO ls_layer WITH KEY layer = lv_slot. "#EC CI_SORTSEQ
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      CLEAR temp92.
      temp92-layer = layer_of_slot( lv_slot ).
      temp92-slot = lv_slot.

      CASE lv_slot.
        WHEN z2ui5_if_client=>cs_view-popup.
          temp32 = cs_model-popup.
        WHEN z2ui5_if_client=>cs_view-popover.
          temp32 = cs_model-popover.
        WHEN OTHERS.
          temp32 = cs_model-main.
      ENDCASE.
      temp92-model_key = temp32.
      temp92-t_node = z2ui5_cl_agent_viewxml=>parse_xml( ls_layer-xml ).

      ls_doc = temp92.
      INSERT ls_doc INTO TABLE mt_doc.

      lv_doc = lines( mt_doc ).
      collect_label_for( lv_doc ).

      CLEAR temp93.
      temp93-doc = lv_doc.
      temp93-layer = ls_doc-layer.
      temp93-model_key = ls_doc-model_key.

      ls_ctx = temp93.


      temp95 = sy-tabix.
      READ TABLE ls_doc-t_node INDEX 1 ASSIGNING <temp94>.
      sy-tabix = temp95.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      walk_children( t_child = <temp94>-t_child
                     ctx     = ls_ctx ).
    ENDLOOP.

    " the app's message table (z2ui5.cc.MessageManager): a TARGET that is a
    " field's path points at that field - resolved once every field is known

    LOOP AT mt_mgr_msg INTO ls_mgr.

      CLEAR temp96.
      temp96-type = ls_mgr-type.
      temp96-text = ls_mgr-text.

      IF ls_mgr-target IS NOT INITIAL.
        temp33 = `field`.
      ELSE.
        temp33 = `model`.
      ENDIF.
      temp96-source = temp33.

      ls_msg = temp96.
      IF ls_mgr-target IS NOT INITIAL.

        READ TABLE mt_field INTO ls_field WITH KEY path = ls_mgr-target. "#EC CI_SORTSEQ

        IF sy-subrc = 0.
          temp97 = ls_field-id.
        ELSE.
          temp97 = ls_mgr-target.
        ENDIF.
        ls_msg-field = temp97.
      ENDIF.
      INSERT ls_msg INTO TABLE mt_message.
    ENDLOOP.

    custom_work( ).


    READ TABLE mt_title INTO ls_title WITH KEY layer = mv_layer. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      mv_title = ls_title-title.
    ELSE.
      READ TABLE mt_title INTO ls_title WITH KEY layer = `main`. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        mv_title = ls_title-title.
      ENDIF.
    ENDIF.

    " the title and the table labels are not repeated as texts

    LOOP AT mt_text INTO lv_text.

      READ TABLE mt_table WITH KEY label = lv_text TRANSPORTING NO FIELDS.
      temp98 = sy-subrc.
      IF lv_text = mv_title OR temp98 = 0. "#EC CI_SORTSEQ
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
    DATA lv_raw LIKE LINE OF ms_input-t_custom.
          DATA temp99 TYPE REF TO z2ui5_if_ajson.
          DATA lo_json LIKE temp99.
      DATA lv_base TYPE i.
      DATA lv_count TYPE i.
      DATA lv_target TYPE string.
      DATA lv_method TYPE string.
      DATA lv_method_type TYPE z2ui5_if_ajson_types=>ty_node_type.
      DATA lv_text_path TYPE string.
      DATA lv_text_type TYPE z2ui5_if_ajson_types=>ty_node_type.
      DATA lv_text TYPE string.
          DATA temp100 TYPE string.
      DATA lv_opt TYPE string.
      DATA lv_has_opt TYPE abap_bool.
      DATA temp4 TYPE xsdboolean.
          DATA temp101 TYPE z2ui5_cl_agent_snapshot=>ty_s_message.
            DATA temp102 TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
          DATA temp103 TYPE z2ui5_cl_agent_snapshot=>ty_s_message.
          DATA temp34 TYPE z2ui5_cl_agent_snapshot=>ty_s_message-type.
            DATA temp104 TYPE string_table.
            DATA lt_choice LIKE temp104.
              DATA lv_n TYPE i.
              DATA temp105 TYPE string_table.
              DATA temp35 TYPE string_table.
              DATA temp3 TYPE string_table.
            DATA temp107 TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
            DATA temp37 TYPE string_table.
            DATA temp39 TYPE z2ui5_cl_agent_viewxml=>ty_t_arg.
            DATA temp40 LIKE LINE OF temp39.
            DATA ls_ms TYPE z2ui5_cl_agent_viewxml=>ty_s_arg.
            DATA temp108 TYPE string.
            DATA lv_ms LIKE temp108.
            DATA temp109 TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
      DATA temp110 TYPE string_table.
      DATA lt_part LIKE temp110.
      DATA lv_index TYPE i.
        DATA lv_type TYPE z2ui5_if_ajson_types=>ty_node_type.
                DATA temp111 TYPE string.
    LOOP AT ms_input-t_custom INTO lv_raw.
      TRY.

          temp99 ?= z2ui5_cl_ajson=>parse( iv_json = lv_raw iv_keep_item_order = abap_true ).

          lo_json = temp99.
        CATCH cx_root.
          CONTINUE.
      ENDTRY.
      IF lo_json->get_node_type( `/` ) <> z2ui5_if_ajson_types=>node_type-array.
        CONTINUE.
      ENDIF.

      lv_base = 0.
      IF lo_json->get_string( `/1` ) = z2ui5_if_client=>cs_event-control_global.
        lv_base = 1.
      ENDIF.

      lv_count = lines( lo_json->members( `/` ) ).

      lv_target = lo_json->get_string( |/{ lv_base + 1 }| ).

      lv_method = lo_json->get_string( |/{ lv_base + 2 }| ).

      lv_method_type = lo_json->get_node_type( |/{ lv_base + 2 }| ).

      lv_text_path = |/{ lv_base + 3 }|.

      lv_text_type = lo_json->get_node_type( lv_text_path ).

      lv_text = ``.
      TRY.

          IF lv_text_type = z2ui5_if_ajson_types=>node_type-object OR lv_text_type = z2ui5_if_ajson_types=>node_type-array.
            temp100 = lo_json->slice( lv_text_path )->stringify( ).
          ELSEIF lv_text_type = z2ui5_if_ajson_types=>node_type-null OR lv_text_type IS INITIAL.
            temp100 = ``.
          ELSE.
            temp100 = lo_json->get( lv_text_path ).
          ENDIF.
          lv_text = temp100.
        CATCH z2ui5_cx_ajson_error.
          CLEAR lv_text.
      ENDTRY.

      lv_opt = |/{ lv_base + 4 }|.


      temp4 = boolc( lo_json->get_node_type( lv_opt ) = z2ui5_if_ajson_types=>node_type-object ).
      lv_has_opt = temp4.
      CLEAR lv_onclose.
      lv_benign = abap_false.
      IF lv_has_opt = abap_true AND lo_json->get_node_type( |{ lv_opt }/onClose| ) = z2ui5_if_ajson_types=>node_type-string.
        lv_onclose = lo_json->get( |{ lv_opt }/onClose| ).
      ENDIF.

      CASE lv_target.

        WHEN `MESSAGE_TOAST`.

          CLEAR temp101.
          temp101-type = `info`.
          temp101-text = z2ui5_cl_agent_viewxml=>clip( val = lv_text len = 1000 ).
          temp101-source = `toast`.
          INSERT temp101 INTO TABLE mt_message.
          IF lv_onclose IS NOT INITIAL.

            CLEAR temp102.
            temp102-event = lv_onclose.
            temp102-label = `toast closed`.
            temp102-control = `sap.m.MessageToast`.
            temp102-trigger = `close`.
            temp102-enabled = abap_true.
            temp102-scope = `screen`.
            temp102-layer = mv_layer.
            push_action( temp102 ).
          ENDIF.

        WHEN `MESSAGE_BOX`.

          CLEAR temp103.

          CASE lv_method.
            WHEN `error`.
              temp34 = `error`.
            WHEN `warning`.
              temp34 = `warning`.
            WHEN `success`.
              temp34 = `success`.
            WHEN OTHERS.
              temp34 = `info`.
          ENDCASE.
          temp103-type = temp34.
          temp103-text = z2ui5_cl_agent_viewxml=>clip( val = lv_text len = 1000 ).
          temp103-source = `box`.
          INSERT temp103 INTO TABLE mt_message.
          IF lv_onclose IS NOT INITIAL.

            CLEAR temp104.

            lt_choice = temp104.
            IF lo_json->get_node_type( |{ lv_opt }/actions| ) = z2ui5_if_ajson_types=>node_type-array.

              lv_n = lines( lo_json->members( |{ lv_opt }/actions| ) ).
              DO lv_n TIMES.
                INSERT lo_json->get( |{ lv_opt }/actions/{ sy-index }| ) INTO TABLE lt_choice.
              ENDDO.
            ENDIF.
            IF lt_choice IS INITIAL.

              CLEAR temp105.
              INSERT `OK` INTO TABLE temp105.
              INSERT `CANCEL` INTO TABLE temp105.

              CLEAR temp35.
              INSERT `OK` INTO TABLE temp35.

              IF lv_method = `confirm`.
                temp3 = temp105.
              ELSE.
                temp3 = temp35.
              ENDIF.
              lt_choice = temp3.
            ENDIF.

            CLEAR temp107.
            temp107-event = lv_onclose.

            CLEAR temp37.
            INSERT `"$action"` INTO TABLE temp37.
            temp107-t_arg_json = temp37.
            temp107-label = |close message box ({ concat_lines_of( table = lt_choice sep = ` | ` ) })|.
            temp107-control = `sap.m.MessageBox`.
            temp107-trigger = `close`.
            temp107-enabled = abap_true.
            temp107-scope = `screen`.
            temp107-layer = mv_layer.

            CLEAR temp39.

            temp40-kind = `action`.
            temp40-describe = `$action`.
            INSERT temp40 INTO TABLE temp39.
            temp107-t_wire_arg = temp39.
            temp107-has_choices = abap_true.
            temp107-t_choice = lt_choice.
            push_action( temp107 ).
          ENDIF.

        WHEN `START_TIMER`.
          IF lv_method_type = z2ui5_if_ajson_types=>node_type-string AND lv_method IS NOT INITIAL.

            ls_ms = z2ui5_cl_agent_viewxml=>describe_arg( lv_text ).

            IF ls_ms-static = abap_true AND ls_ms-val-kind = z2ui5_cl_agent_viewxml=>cs_kind-number AND ls_ms-val-num <> 0.
              temp108 = ls_ms-val-str.
            ELSE.
              temp108 = `0`.
            ENDIF.

            lv_ms = temp108.

            CLEAR temp109.
            temp109-event = lv_method.
            temp109-label = |timer ({ lv_ms } ms)|.
            temp109-control = `timer`.
            temp109-trigger = `timer`.
            temp109-enabled = abap_true.
            temp109-scope = `screen`.
            temp109-layer = mv_layer.
            push_action( temp109 ).
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

      CLEAR temp110.

      lt_part = temp110.

      lv_index = lv_base + 1.
      WHILE lv_index <= lv_count.

        lv_type = lo_json->get_node_type( |/{ lv_index }| ).
        CASE lv_type.
          WHEN z2ui5_if_ajson_types=>node_type-object OR z2ui5_if_ajson_types=>node_type-array.
            TRY.
                INSERT lo_json->slice( |/{ lv_index }| )->stringify( ) INTO TABLE lt_part.
              CATCH z2ui5_cx_ajson_error.

                IF lv_type = z2ui5_if_ajson_types=>node_type-array.
                  temp111 = `[]`.
                ELSE.
                  temp111 = `{}`.
                ENDIF.
                INSERT temp111 INTO TABLE lt_part.
            ENDTRY.
          WHEN z2ui5_if_ajson_types=>node_type-null.
            INSERT `null` INTO TABLE lt_part.
          WHEN OTHERS.
            INSERT lo_json->get( |/{ lv_index }| ) INTO TABLE lt_part.
        ENDCASE.
        lv_index = lv_index + 1.
      ENDWHILE.
      note( |frontend action { z2ui5_cl_agent_viewxml=>clip( val = concat_lines_of( table = lt_part
                                                                                    sep   = ` ` )
                                                             len = 120 ) } (runs in the browser only, not performed)| ).
    ENDLOOP.

  ENDMETHOD.

  METHOD collect_label_for.

    " a Label with labelFor names the control of that id, wherever it is
    DATA lr_doc TYPE REF TO z2ui5_cl_agent_snapshot=>ty_s_doc.
    DATA ls_node LIKE LINE OF lr_doc->t_node.
      DATA lv_for TYPE string.
      DATA ls_b TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
      DATA lv_text TYPE string.
        DATA ls_val TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
      DATA temp112 TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
    READ TABLE mt_doc INDEX doc REFERENCE INTO lr_doc.

    LOOP AT lr_doc->t_node INTO ls_node.
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true
          OR z2ui5_cl_agent_viewxml=>control_name( ls_node ) <> `sap.m.Label`.
        CONTINUE.
      ENDIF.

      lv_for = z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                  name = `labelFor` ).
      IF lv_for IS INITIAL.
        CONTINUE.
      ENDIF.

      ls_b = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                                                         name = `text` ) ).

      lv_text = ``.
      IF ls_b-kind = z2ui5_cl_agent_viewxml=>cs_binding-literal.
        lv_text = ls_b-value.
      ELSEIF ls_b-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_b-relative = abap_false AND ls_b-model IS INITIAL.

        ls_val = model_get( model_key = lr_doc->model_key
                                  path      = ls_b-path ).
        IF ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-undefined AND ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null.
          lv_text = z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).
        ENDIF.
      ENDIF.
      DELETE lr_doc->t_lblfor WHERE name = lv_for.        "#EC CI_SORTSEQ
      DELETE lr_doc->t_lblreq WHERE table_line = lv_for.  "#EC CI_SORTSEQ

      CLEAR temp112.
      temp112-name = lv_for.
      temp112-value = lv_text.
      INSERT temp112 INTO TABLE lr_doc->t_lblfor.
      IF z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                       name = `required` ) = `true`.
        INSERT lv_for INTO TABLE lr_doc->t_lblreq.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD label_for.
    DATA ls_doc TYPE z2ui5_cl_agent_snapshot=>ty_s_doc.
    DATA ls_for TYPE z2ui5_cl_agent_viewxml=>ty_s_attr.
    DATA temp113 LIKE sy-subrc.
    DATA temp5 TYPE xsdboolean.

    found = abap_false.

    READ TABLE mt_doc INDEX ctx-doc INTO ls_doc.
    IF sy-subrc <> 0 OR id IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE ls_doc-t_lblfor INTO ls_for WITH KEY name = id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    found = abap_true.
    result = ls_for-value.

    READ TABLE ls_doc-t_lblreq WITH KEY table_line = id TRANSPORTING NO FIELDS.
    temp113 = sy-subrc.

    temp5 = boolc( temp113 = 0 ).
    required = temp5. "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD resolve_ref.

    DATA lv_ref TYPE string.
    DATA lv_gt TYPE i.
      DATA lv_name TYPE string.
    lv_ref = condense( ref ).
    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.
    " a named model

    lv_gt = find( val = lv_ref
                        sub = `>` ).
    IF lv_gt > 0.

      lv_name = substring( val = lv_ref
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
        DATA temp114 TYPE string_table.
        DATA lv_ref LIKE LINE OF temp114.
          DATA temp115 TYPE z2ui5_cl_agent_viewxml=>ty_s_ref_val.
        DATA lv_known LIKE abap_false.
        DATA lv_all_text LIKE abap_true.
        DATA ls_part LIKE LINE OF binding-t_part.
            DATA temp116 TYPE ty_s_val.
            DATA ls_val LIKE temp116.

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

        temp114 = z2ui5_cl_agent_viewxml=>expression_refs( binding-expression ).

        LOOP AT temp114 INTO lv_ref.

          CLEAR temp115.
          temp115-ref = lv_ref.
          temp115-val = resolve_ref( ref = lv_ref ctx = ctx row = row ).
          INSERT temp115 INTO TABLE lt_ref.
        ENDLOOP.
        result = z2ui5_cl_agent_viewxml=>eval_expression( val   = binding-expression
                                                          t_ref = lt_ref ).

      WHEN OTHERS.

        lv_known = abap_false.

        lv_all_text = abap_true.

        LOOP AT binding-t_part INTO ls_part.
          IF ls_part-is_text = abap_true.
            lv_text = lv_text && ls_part-text.
            CONTINUE.
          ENDIF.
          lv_all_text = abap_false.
          IF ls_part-is_path = abap_true AND ls_part-model IS INITIAL AND ls_part-formatter = abap_false.

            IF ls_part-relative = abap_true.
              temp116 = resolve_ref( ref = ls_part-path ctx = ctx row = row ).
            ELSE.
              temp116 = model_get( model_key = ctx-model_key path = ls_part-path ).
            ENDIF.

            ls_val = temp116.
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

    DATA lv_raw TYPE string.
    DATA ls_val TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
    lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                           name  = name
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      result = default_value.
      RETURN.
    ENDIF.

    ls_val = resolve( raw = lv_raw
                            ctx = ctx
                            row = row ).
    CASE ls_val-kind.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-undefined OR z2ui5_cl_agent_viewxml=>cs_kind-null OR space.
        result = default_value.
      WHEN z2ui5_cl_agent_viewxml=>cs_kind-string.
        IF ls_val-str = `true`.
          result = abap_true.
        ELSEIF ls_val-str = `false` OR ls_val-str IS INITIAL.
          result = abap_false.
        ELSE.
          result = default_value.
        ENDIF.
      WHEN OTHERS.
        result = z2ui5_cl_agent_viewxml=>val_truthy( ls_val ).
    ENDCASE.

  ENDMETHOD.

  METHOD text_of_raw.

    DATA ls_val TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
    ls_val = resolve( raw = raw
                            ctx = ctx
                            row = row ).
    IF ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined OR ls_val-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.
      RETURN.
    ENDIF.
    result = z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).

  ENDMETHOD.

  METHOD text_of.

    DATA lv_found TYPE abap_bool.

    DATA lv_raw TYPE string.
    lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
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

    DATA lv_label LIKE ctx-label.
    DATA lv_child LIKE LINE OF t_child.
      DATA ls_child TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
        DATA lv_name TYPE string.
        DATA lv_for TYPE string.
      DATA ls_ctx LIKE ctx.
    lv_label = ctx-label.

    LOOP AT t_child INTO lv_child.

      ls_child = node( doc = ctx-doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_false.

        lv_name = z2ui5_cl_agent_viewxml=>control_name( ls_child ).

        lv_for = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_child
                                                               name  = `labelFor`
                                                     IMPORTING found = lv_found ).
        IF lv_name = `sap.m.Label` AND lv_for IS INITIAL.
          IF bool( node          = ls_child
                   name          = `visible`
                   ctx           = ctx
                   default_value = abap_true ) = abap_false.
            CONTINUE.
          ENDIF.
          lv_label = label_new( text     = text_of( node = ls_child
                                                    name = `text`
                                                    ctx  = ctx )
                                required = bool( node          = ls_child
                                                 name          = `required`
                                                 ctx           = ctx
                                                 default_value = abap_false ) ).
          CONTINUE.
        ENDIF.
        IF lv_name = `sap.ui.core.Title` OR lv_name = `sap.m.Title` OR ends_with( val    = lv_name
                                                                                   suffix = `Toolbar` ) = abap_true.
          lv_label = 0.
        ENDIF.
      ENDIF.

      ls_ctx = ctx.
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

    DATA ls_node TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    DATA lv_name TYPE string.
    DATA ls_c LIKE ctx.
    DATA temp117 LIKE sy-subrc.
    DATA temp118 LIKE sy-subrc.
          DATA lv_title TYPE string.
            DATA temp119 TYPE z2ui5_cl_agent_snapshot=>ty_s_title.
        DATA lv_heading TYPE i.
            DATA temp120 TYPE z2ui5_cl_agent_snapshot=>ty_s_title.
      DATA lv_label TYPE i.
      DATA lv_label_attr TYPE string.
      DATA lv_label_agg TYPE i.
        DATA lt_label_ctl TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
          DATA ls_label_ctl TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
          FIELD-SYMBOLS <temp41> LIKE LINE OF lt_label_ctl.
          DATA temp42 LIKE sy-tabix.
      DATA lv_agg_id LIKE LINE OF ls_node-t_child.
        DATA ls_fe_ctx LIKE ls_c.
      DATA lv_strip TYPE string.
        DATA lv_strip_type TYPE string.
        DATA lv_mtype TYPE string.
        DATA temp121 TYPE z2ui5_cl_agent_snapshot=>ty_s_message.
        DATA temp43 TYPE z2ui5_cl_agent_snapshot=>ty_s_message-type.
    DATA ls_spec TYPE z2ui5_cl_agent_snapshot=>ty_s_spec.
    DATA lv_field TYPE i.
      DATA lt_props TYPE string_table.
        DATA temp122 TYPE string_table.
        DATA lt_parts LIKE temp122.
        DATA temp123 TYPE string_table.
        DATA lt_source LIKE temp123.
        DATA lv_prop LIKE LINE OF lt_props.
          DATA lv_part TYPE string.
        DATA lv_text TYPE string.
          DATA ls_label TYPE z2ui5_cl_agent_snapshot=>ty_s_label.
    ls_node = node( doc = ctx-doc
                          id  = id ).
    IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true.
      walk_children( t_child = ls_node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.

    lv_name = z2ui5_cl_agent_viewxml=>control_name( ls_node ).
    IF lv_name = `sap.ui.core.mvc.View` OR lv_name = `sap.ui.core.FragmentDefinition`.
      walk_children( t_child = ls_node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.
    IF bool( node          = ls_node
             name          = `visible`
             ctx           = ctx
             default_value = abap_true ) = abap_false.
      RETURN.
    ENDIF.

    ls_c = ctx.
    INSERT ls_node-local INTO TABLE ls_c-t_where.

    " the title of the layer: Dialog / selection dialog / Popover / Page, or
    " a DynamicPageTitle


    temp118 = sy-subrc.
    READ TABLE mt_title WITH KEY layer = ctx-layer TRANSPORTING NO FIELDS.
    temp117 = sy-subrc.
    sy-subrc = temp118.
    IF NOT temp117 = 0. "#EC CI_SORTSEQ
      IF lv_name = `sap.m.Dialog` OR lv_name = `sap.m.SelectDialog` OR lv_name = `sap.m.TableSelectDialog`
          OR lv_name = `sap.m.Popover` OR lv_name = `sap.m.ResponsivePopover`
          OR lv_name = `sap.m.Page` OR lv_name = `sap.m.semantic.FullscreenPage` OR lv_name = `sap.m.Shell`.
        z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                name  = `title`
                                      IMPORTING found = lv_found ).
        IF lv_found = abap_true.

          lv_title = text_of( node = ls_node
                                    name = `title`
                                    ctx  = ctx ).
          IF lv_title IS NOT INITIAL.

            CLEAR temp119.
            temp119-layer = ctx-layer.
            temp119-title = z2ui5_cl_agent_viewxml=>clip( lv_title ).
            INSERT temp119 INTO TABLE mt_title.
          ENDIF.
        ENDIF.
      ENDIF.
      IF lv_name = `sap.f.DynamicPageTitle`.

        lv_heading = find_first( doc     = ctx-doc
                                       id      = id
                                       control = `sap.m.Title` ).
        IF lv_heading > 0.
          lv_title = text_of( node = node( doc = ctx-doc
                                           id  = lv_heading )
                              name = `text`
                              ctx  = ctx ).
          IF lv_title IS NOT INITIAL.

            CLEAR temp120.
            temp120-layer = ctx-layer.
            temp120-title = z2ui5_cl_agent_viewxml=>clip( lv_title ).
            INSERT temp120 INTO TABLE mt_title.
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

      lv_label = 0.

      lv_label_attr = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                                    name  = `label`
                                                          IMPORTING found = lv_found ).
      IF lv_found = abap_true.
        lv_label = label_new( text     = text_of_raw( raw = lv_label_attr
                                                      ctx = ctx )
                              required = abap_false ).
      ENDIF.

      lv_label_agg = child_agg( doc   = ctx-doc
                                      node  = ls_node
                                      local = `label` ).
      IF lv_label_agg > 0.

        lt_label_ctl = controls_of( doc     = ctx-doc
                                          t_child = node( doc = ctx-doc
                                                          id  = lv_label_agg )-t_child ).
        IF lt_label_ctl IS NOT INITIAL.



          temp42 = sy-tabix.
          READ TABLE lt_label_ctl INDEX 1 ASSIGNING <temp41>.
          sy-tabix = temp42.
          IF sy-subrc <> 0.
            ASSERT 1 = 0.
          ENDIF.
          ls_label_ctl = node( doc = ctx-doc
                                     id  = <temp41> ).
          lv_label = label_new( text     = text_of( node = ls_label_ctl
                                                    name = `text`
                                                    ctx  = ctx )
                                required = bool( node          = ls_label_ctl
                                                 name          = `required`
                                                 ctx           = ctx
                                                 default_value = abap_false ) ).
        ENDIF.
      ENDIF.

      LOOP AT ls_node-t_child INTO lv_agg_id.
        IF node( doc = ctx-doc
                 id  = lv_agg_id )-local = `label`.
          CONTINUE.
        ENDIF.

        ls_fe_ctx = ls_c.
        ls_fe_ctx-label = lv_label.
        walk( id  = lv_agg_id
              ctx = ls_fe_ctx ).
      ENDLOOP.
      RETURN.
    ENDIF.

    IF lv_name = `sap.m.MessageStrip`.

      lv_strip = text_of( node = ls_node
                                name = `text`
                                ctx  = ctx ).
      IF lv_strip IS NOT INITIAL.

        lv_strip_type = text_of( node = ls_node
                                       name = `type`
                                       ctx  = ctx ).
        IF lv_strip_type IS INITIAL.
          lv_strip_type = `Information`.
        ENDIF.

        lv_mtype = message_type( lv_strip_type ).

        CLEAR temp121.

        IF lv_mtype IS INITIAL.
          temp43 = `info`.
        ELSE.
          temp43 = lv_mtype.
        ENDIF.
        temp121-type = temp43.
        temp121-text = z2ui5_cl_agent_viewxml=>clip( val = lv_strip len = 1000 ).
        temp121-source = `strip`.
        INSERT temp121 INTO TABLE mt_message.
      ENDIF.
      wires( node = ls_node
             ctx  = ls_c
             name = lv_name ).
      RETURN.
    ENDIF.


    ls_spec = field_spec( lv_name ).

    lv_field = 0.
    IF ls_spec-found = abap_true AND ctx-row_table IS INITIAL.
      lv_field = field( node = ls_node
                        ctx  = ls_c
                        name = lv_name
                        spec = ls_spec ).
    ENDIF.
    IF ls_spec-found = abap_false AND ctx-row_table IS INITIAL.

      lt_props = text_props( lv_name ).
      IF lt_props IS NOT INITIAL.

        CLEAR temp122.

        lt_parts = temp122.

        CLEAR temp123.

        lt_source = temp123.

        LOOP AT lt_props INTO lv_prop.

          lv_part = text_of( node = ls_node
                                   name = lv_prop
                                   ctx  = ctx ).
          IF lv_part IS NOT INITIAL.
            INSERT lv_part INTO TABLE lt_parts.
            INSERT LINES OF text_paths( z2ui5_cl_agent_viewxml=>attr( node = ls_node
                                                                      name = lv_prop ) ) INTO TABLE lt_source.
          ENDIF.
        ENDLOOP.

        lv_text = concat_lines_of( table = lt_parts
                                         sep   = ` ` ).
        IF lv_name = `sap.m.FormattedText`.
          lv_text = strip_tags( lv_text ).
        ENDIF.
        IF lv_text IS NOT INITIAL.

          READ TABLE mt_label INDEX ctx-label INTO ls_label.
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

    DATA lv_id TYPE string.
    DATA lv_for TYPE string.
    DATA lr_label TYPE REF TO z2ui5_cl_agent_snapshot=>ty_s_label.
      DATA temp124 TYPE string.
      DATA lv_ph LIKE temp124.
      DATA temp125 TYPE string.
    DATA temp44 TYPE string_table.
    DATA temp126 LIKE temp44.
    DATA lv_prop LIKE LINE OF temp126.
    lv_id = z2ui5_cl_agent_viewxml=>attr( node = node
                                               name = `id` ).

    lv_for = label_for( EXPORTING ctx   = ctx
                                        id    = lv_id
                              IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result = lv_for.
      RETURN.
    ENDIF.


    READ TABLE mt_label INDEX ctx-label REFERENCE INTO lr_label.
    IF sy-subrc = 0 AND lr_label->text IS NOT INITIAL.
      " one form label over several fields (a first and a last name input):
      " the placeholder tells them apart
      lr_label->uses = lr_label->uses + 1.

      IF lr_label->uses > 1.
        temp124 = text_of( node = node name = `placeholder` ctx = ctx ).
      ELSE.
        CLEAR temp124.
      ENDIF.

      lv_ph = temp124.

      IF lv_ph IS NOT INITIAL.
        temp125 = |{ lr_label->text } ({ lv_ph })|.
      ELSE.
        temp125 = lr_label->text.
      ENDIF.
      result = temp125.
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


    CLEAR temp44.
    INSERT `placeholder` INTO TABLE temp44.
    INSERT `tooltip` INTO TABLE temp44.
    INSERT `ariaLabel` INTO TABLE temp44.
    INSERT `title` INTO TABLE temp44.

    temp126 = temp44.

    LOOP AT temp126 INTO lv_prop.
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

    DATA lv_candidate LIKE LINE OF spec-t_prop.
    DATA ls_value TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
    DATA lv_label TYPE string.
    DATA lv_kind TYPE string.
        DATA temp127 TYPE string.
    DATA lv_editable TYPE abap_bool.
    DATA temp6 TYPE xsdboolean.
      DATA temp7 TYPE xsdboolean.
    DATA ls_label TYPE z2ui5_cl_agent_snapshot=>ty_s_label.
    DATA lv_label_required TYPE abap_bool.
    DATA temp8 TYPE xsdboolean.
    DATA lv_required_all TYPE abap_bool.
    DATA temp9 TYPE xsdboolean.
    DATA lv_name TYPE string.
    DATA temp128 TYPE ty_s_field.
    DATA temp46 TYPE string.
    DATA temp10 TYPE xsdboolean.
    DATA ls_field LIKE temp128.
      DATA lt_values TYPE z2ui5_cl_agent_snapshot=>ty_t_choice.
    DATA lv_state TYPE string.
    DATA lv_type TYPE string.
      DATA lv_state_text TYPE string.
      DATA temp129 TYPE z2ui5_cl_agent_snapshot=>ty_s_message.
    LOOP AT spec-t_prop INTO lv_candidate.
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


    ls_value = resolve( EXPORTING raw     = z2ui5_cl_agent_viewxml=>attr( node = node
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


    lv_label = label_of( node = node
                               ctx  = ctx
                               spec = spec ).

    lv_kind = kind_from_type( ls_binding-type ).
    IF lv_kind IS INITIAL.
      lv_kind = spec-kind.
      IF lv_kind = `input`.

        CASE z2ui5_cl_agent_viewxml=>attr( node = node name = `type` ).
          WHEN `Number`.
            temp127 = `number`.
          WHEN `Date`.
            temp127 = `date`.
          WHEN `Time`.
            temp127 = `time`.
          WHEN `DateTime`.
            temp127 = `datetime`.
          WHEN OTHERS.
            temp127 = `text`.
        ENDCASE.
        lv_kind = temp127.
      ENDIF.
    ENDIF.

    " two checks: the 7.02 downport puts one xsdbool( ) on one line


    temp6 = boolc( bool( node = node name = `editable` ctx = ctx default_value = abap_true ) = abap_true AND bool( node = node name = `enabled` ctx = ctx default_value = abap_true ) = abap_true ).
    lv_editable = temp6.
    IF lv_editable = abap_true.

      temp7 = boolc( bool( node = node name = `displayOnly` ctx = ctx default_value = abap_false ) = abap_false ).
      lv_editable = temp7.
    ENDIF.
    label_for( EXPORTING ctx      = ctx
                         id       = z2ui5_cl_agent_viewxml=>attr( node = node
                                                                  name = `id` )
               IMPORTING found    = lv_found
                         required = lv_required ).

    READ TABLE mt_label INDEX ctx-label INTO ls_label.


    temp8 = boolc( sy-subrc = 0 AND ls_label-required = abap_true ).
    lv_label_required = temp8.


    temp9 = boolc( bool( node = node name = `required` ctx = ctx default_value = abap_false ) = abap_true OR ( lv_found = abap_true AND lv_required = abap_true ) OR lv_label_required = abap_true ).
    lv_required_all = temp9.


    lv_name = name_of_path( ls_binding-path ).

    CLEAR temp128.
    temp128-id = |f{ lines( mt_field ) + 1 }|.
    temp128-path = ls_binding-path.
    temp128-name = lv_name.

    IF lv_label IS NOT INITIAL.
      temp46 = lv_label.
    ELSE.
      temp46 = lv_name.
    ENDIF.
    temp128-label = z2ui5_cl_agent_viewxml=>clip( val = temp46 len = 120 ).
    temp128-control = name.
    temp128-kind = lv_kind.
    temp128-value = ls_value.
    temp128-required = lv_required_all.
    temp128-editable = lv_editable.
    temp128-layer = ctx-layer.
    temp128-model_key = ctx-model_key.
    temp128-doc = ctx-doc.
    temp128-node = node-id.

    temp10 = boolc( z2ui5_cl_agent_viewxml=>attr( node = node name = `type` ) = `Password` ).
    temp128-secret = temp10.

    ls_field = temp128.
    IF spec-items IS NOT INITIAL.

      lt_values = choice_values( EXPORTING node  = node
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


    lv_state = text_of( node = node
                              name = `valueState`
                              ctx  = ctx ).

    lv_type = message_type( lv_state ).
    IF lv_type IS NOT INITIAL.

      lv_state_text = text_of( node = node
                                     name = `valueStateText`
                                     ctx  = ctx ).
      IF lv_state_text IS INITIAL.
        lv_state_text = |{ ls_field-label }: { lv_state }|.
      ENDIF.

      CLEAR temp129.
      temp129-type = lv_type.
      temp129-text = z2ui5_cl_agent_viewxml=>clip( val = lv_state_text len = 1000 ).
      temp129-source = `field`.
      temp129-field = ls_field-id.
      INSERT temp129 INTO TABLE mt_message.
    ENDIF.

  ENDMETHOD.

  METHOD controls_of.

    DATA lv_child LIKE LINE OF t_child.
    LOOP AT t_child INTO lv_child.
      IF z2ui5_cl_agent_viewxml=>is_aggregation( node( doc = doc
                                                       id  = lv_child ) ) = abap_false.
        INSERT lv_child INTO TABLE result.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD child_agg.

    DATA lv_child LIKE LINE OF node-t_child.
    LOOP AT node-t_child INTO lv_child.
      IF node( doc = doc
               id  = lv_child )-local = local.
        result = lv_child.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD item_controls.

    DATA lv_agg TYPE i.
    DATA temp130 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    lv_agg = child_agg( doc   = ctx-doc
                              node  = node
                              local = agg ).

    IF lv_agg > 0.
      temp130 = node( doc = ctx-doc id = lv_agg )-t_child.
    ELSE.
      temp130 = node-t_child.
    ENDIF.
    result = controls_of( doc     = ctx-doc
                          t_child = temp130 ).

  ENDMETHOD.

  METHOD choice_values.

    DATA lv_found TYPE abap_bool.
    DATA temp131 TYPE string.
    DATA lt_items TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
      DATA lv_item LIKE LINE OF lt_items.
        DATA temp132 TYPE z2ui5_cl_agent_snapshot=>ty_s_choice.
    DATA lv_items_raw TYPE string.
    DATA lv_bpath TYPE string.
      DATA ls_bound TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
        DATA ls_part LIKE LINE OF ls_bound-t_part.
      DATA ls_rows TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
      DATA ls_tmpl TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      FIELD-SYMBOLS <temp47> LIKE LINE OF lt_items.
      DATA temp48 LIKE sy-tabix.
      DATA temp133 TYPE i.
      DATA lv_count LIKE temp133.
        DATA lv_row TYPE string.
        DATA lv_text TYPE string.
        DATA temp134 TYPE z2ui5_cl_agent_snapshot=>ty_s_choice.
        DATA temp49 TYPE string.
      DATA ls_item TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA temp135 TYPE z2ui5_cl_agent_snapshot=>ty_s_choice.
      DATA temp50 TYPE string.

    found = abap_false.

    IF spec-items = `index`.
      temp131 = `buttons`.
    ELSE.
      temp131 = `items`.
    ENDIF.

    lt_items = item_controls( node = node
                                    ctx  = ctx
                                    agg  = temp131 ).
    IF spec-items = `index`.
      found = abap_true.

      LOOP AT lt_items INTO lv_item.

        CLEAR temp132.
        temp132-key = z2ui5_cl_agent_viewxml=>val_number( |{ sy-tabix - 1 }| ).
        temp132-text = text_of( node = node( doc = ctx-doc id = lv_item ) name = `text` ctx = ctx ).
        INSERT temp132 INTO TABLE result.
      ENDLOOP.
      RETURN.
    ENDIF.


    lv_items_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = `items`
                                                       IMPORTING found = lv_found ).

    lv_bpath = ``.
    IF lv_found = abap_true.

      ls_bound = z2ui5_cl_agent_viewxml=>parse_binding( lv_items_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        IF ls_bound-model IS INITIAL AND ls_bound-relative = abap_false.
          lv_bpath = ls_bound-path.
        ENDIF.
      ELSE.

        LOOP AT ls_bound-t_part INTO ls_part WHERE is_path = abap_true. "#EC CI_SORTSEQ
          IF ls_part-model IS INITIAL AND ls_part-relative = abap_false.
            lv_bpath = ls_part-path.
          ENDIF.
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF lv_bpath IS NOT INITIAL.

      ls_rows = model_get( model_key  = ctx-model_key
                                 path       = lv_bpath
                                 check_json = abap_false ).
      IF ls_rows-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array OR lt_items IS INITIAL.
        RETURN.
      ENDIF.
      found = abap_true.



      temp48 = sy-tabix.
      READ TABLE lt_items INDEX 1 ASSIGNING <temp47>.
      sy-tabix = temp48.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      ls_tmpl = node( doc = ctx-doc
                            id  = <temp47> ).
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_tmpl
                                              name  = `key`
                                    IMPORTING found = lv_found ).

      temp133 = ls_rows-num.

      lv_count = temp133.
      DO lv_count TIMES.

        lv_row = tree_path( model_key = ctx-model_key
                                  path      = |{ lv_bpath }/{ sy-index - 1 }| ).

        lv_text = text_of( node = ls_tmpl
                                 name = `text`
                                 ctx  = ctx
                                 row  = lv_row ).

        CLEAR temp134.

        IF lv_found = abap_true.
          temp49 = text_of( node = ls_tmpl name = `key` ctx = ctx row = lv_row ).
        ELSE.
          temp49 = lv_text.
        ENDIF.
        temp134-key = z2ui5_cl_agent_viewxml=>val_string( temp49 ).
        temp134-text = lv_text.
        INSERT temp134 INTO TABLE result.
      ENDDO.
      RETURN.
    ENDIF.

    IF lt_items IS INITIAL.
      RETURN.
    ENDIF.
    found = abap_true.
    LOOP AT lt_items INTO lv_item.

      ls_item = node( doc = ctx-doc
                            id  = lv_item ).
      lv_text = text_of( node = ls_item
                         name = `text`
                         ctx  = ctx ).
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_item
                                              name  = `key`
                                    IMPORTING found = lv_found ).

      CLEAR temp135.

      IF lv_found = abap_true.
        temp50 = text_of( node = ls_item name = `key` ctx = ctx ).
      ELSE.
        temp50 = lv_text.
      ENDIF.
      temp135-key = z2ui5_cl_agent_viewxml=>val_string( temp50 ).
      temp135-text = lv_text.
      INSERT temp135 INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD push_action.

    DATA ls_action LIKE action.
    ls_action = action.
    ls_action-id = |a{ lines( mt_action ) + 1 }|.
    IF ls_action-scope <> `row`.
      CLEAR ls_action-table.
    ENDIF.
    INSERT ls_action INTO TABLE mt_action.

  ENDMETHOD.

  METHOD wires.

    DATA lt_desc TYPE string_table.

    DATA ls_attr LIKE LINE OF node-t_attr.
      DATA ls_wire TYPE z2ui5_cl_agent_viewxml=>ty_s_wire.
      DATA temp136 TYPE string.
      DATA lv_gate LIKE temp136.
      DATA temp137 TYPE string.
      DATA lv_label LIKE temp137.
      DATA lv_enabled TYPE abap_bool.
      DATA temp138 TYPE string.
      DATA lv_scope LIKE temp138.
        DATA temp139 TYPE string_table.
        DATA lt_static LIKE temp139.
        DATA ls_arg LIKE LINE OF ls_wire-t_arg.
          DATA temp140 TYPE string.
        DATA temp141 TYPE string.
        DATA temp142 TYPE string.
        DATA lv_slot LIKE temp141.
        DATA temp143 TYPE string.
        DATA temp144 TYPE string.
        DATA lv_static_1 LIKE temp143.
        DATA temp145 TYPE string.
        DATA temp146 TYPE string.
        DATA lv_static_2 LIKE temp145.
          DATA temp147 TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
          DATA temp51 TYPE z2ui5_cl_agent_snapshot=>ty_s_action-event.
            DATA temp148 TYPE string.
      DATA temp149 TYPE string_table.
      DATA lt_arg_json LIKE temp149.
        DATA temp150 TYPE string.
      DATA temp151 TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
    LOOP AT node-t_attr INTO ls_attr.
      IF only IS NOT INITIAL AND ls_attr-name <> only.
        CONTINUE.
      ENDIF.
      IF z2ui5_cl_agent_viewxml=>has_wire( ls_attr-value ) = abap_false.
        CONTINUE.
      ENDIF.

      ls_wire = z2ui5_cl_agent_viewxml=>parse_wire( ls_attr-value ).
      IF ls_wire-valid = abap_false.
        note( |event { ls_attr-name } on { node-local } ({ ctx-layer }) - a handler this client cannot read| ).
        CONTINUE.
      ENDIF.
      " a wire whose trigger is not shown is skipped

      CASE ls_attr-name.
        WHEN `navButtonPress`.
          temp136 = `showNavButton`.
        WHEN `valueHelpRequest`.
          temp136 = `showValueHelp`.
      ENDCASE.

      lv_gate = temp136.
      IF lv_gate IS NOT INITIAL AND bool( node          = node
                                          name          = lv_gate
                                          ctx           = ctx
                                          default_value = abap_false ) = abap_false.
        CONTINUE.
      ENDIF.

      IF override IS NOT INITIAL.
        temp137 = override.
      ELSE.
        temp137 = action_label( node = node ctx = ctx name = name trigger = ls_attr-name field = field ).
      ENDIF.

      lv_label = temp137.

      lv_enabled = bool( node          = node
                               name          = `enabled`
                               ctx           = ctx
                               default_value = abap_true ).

      IF ctx-row_table IS NOT INITIAL.
        temp138 = `row`.
      ELSE.
        temp138 = `screen`.
      ENDIF.

      lv_scope = temp138.

      IF ls_wire-fn = `eF`.

        CLEAR temp139.

        lt_static = temp139.

        LOOP AT ls_wire-t_arg INTO ls_arg.

          IF ls_arg-static = abap_true.
            temp140 = ls_arg-val-str.
          ELSE.
            temp140 = `#dynamic#`.
          ENDIF.
          INSERT temp140 INTO TABLE lt_static.
        ENDLOOP.
        " read ahead: a table expression in the condition would be hoisted in
        " front of the IF by the 7.02 downport, where no guard protects it

        CLEAR temp141.

        READ TABLE lt_static INTO temp142 INDEX 3.
        IF sy-subrc = 0.
          temp141 = temp142.
        ENDIF.

        lv_slot = temp141.

        CLEAR temp143.

        READ TABLE lt_static INTO temp144 INDEX 1.
        IF sy-subrc = 0.
          temp143 = temp144.
        ENDIF.

        lv_static_1 = temp143.

        CLEAR temp145.

        READ TABLE lt_static INTO temp146 INDEX 2.
        IF sy-subrc = 0.
          temp145 = temp146.
        ENDIF.

        lv_static_2 = temp145.
        IF ls_wire-action = z2ui5_if_client=>cs_event-control_global
            AND lv_static_1 = `VIEW_SLOTS` AND lv_static_2 = `destroy`
            AND ( lv_slot = cs_model-popup OR lv_slot = cs_model-popover ).

          CLEAR temp147.

          IF lv_slot = cs_model-popup.
            temp51 = cs_frontend_event-popup.
          ELSE.
            temp51 = cs_frontend_event-popover.
          ENDIF.
          temp147-event = temp51.
          temp147-label = lv_label.
          temp147-control = name.
          temp147-trigger = ls_attr-name.
          temp147-enabled = lv_enabled.
          temp147-scope = lv_scope.
          temp147-table = ctx-row_table.
          temp147-layer = ctx-layer.
          temp147-model_key = ctx-model_key.
          temp147-doc = ctx-doc.
          temp147-node = node-id.
          temp147-frontend = lv_slot.
          push_action( temp147 ).
        ELSE.
          CLEAR lt_desc.
          LOOP AT ls_wire-t_arg INTO ls_arg.

            IF ls_arg-static = abap_true.
              temp148 = z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val ).
            ELSE.
              temp148 = ls_arg-describe.
            ENDIF.
            INSERT temp148 INTO TABLE lt_desc.
          ENDLOOP.
          note( |frontend action { ls_wire-action }({ concat_lines_of( table = lt_desc
                                                                      sep   = `, ` ) }) on { node-local } | &&
                |"{ z2ui5_cl_agent_viewxml=>clip( val = lv_label
                                                  len = 60 ) }" ({ ctx-layer }) - runs in the browser only| ).
        ENDIF.
        CONTINUE.
      ENDIF.


      CLEAR temp149.

      lt_arg_json = temp149.
      LOOP AT ls_wire-t_arg INTO ls_arg.

        IF ls_arg-static = abap_true.
          temp150 = z2ui5_cl_agent_viewxml=>val_to_json( ls_arg-val ).
        ELSE.
          temp150 = z2ui5_cl_agent_viewxml=>json_string( ls_arg-describe ).
        ENDIF.
        INSERT temp150 INTO TABLE lt_arg_json.
      ENDLOOP.

      CLEAR temp151.
      temp151-event = ls_wire-event.
      temp151-t_arg_json = lt_arg_json.
      temp151-label = lv_label.
      temp151-control = name.
      temp151-trigger = ls_attr-name.
      temp151-enabled = lv_enabled.
      temp151-scope = lv_scope.
      temp151-table = ctx-row_table.
      temp151-layer = ctx-layer.
      temp151-model_key = ctx-model_key.
      temp151-doc = ctx-doc.
      temp151-node = node-id.
      temp151-t_wire_arg = ls_wire-t_arg.
      temp151-pick = pick.
      temp151-row_template = ctx-row_template.
      push_action( temp151 ).
    ENDLOOP.

  ENDMETHOD.

  METHOD action_label.

    DATA lv_found TYPE abap_bool.
      FIELD-SYMBOLS <temp152> LIKE LINE OF mt_field.
      DATA temp153 LIKE sy-tabix.
    DATA ls_spec TYPE z2ui5_cl_agent_snapshot=>ty_s_spec.
      DATA lv_label TYPE string.
    DATA temp52 TYPE string_table.
    DATA temp154 LIKE temp52.
    DATA lv_prop LIKE LINE OF temp154.
      DATA lv_raw TYPE string.
      DATA lv_text TYPE string.
    DATA lv_icon TYPE string.
    DATA lv_type TYPE string.

    IF trigger = `navButtonPress`.
      result = `Back`.
      RETURN.
    ENDIF.
    IF field > 0.


      temp153 = sy-tabix.
      READ TABLE mt_field INDEX field ASSIGNING <temp152>.
      sy-tabix = temp153.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      result = |{ <temp152>-label }: { trigger }|.
      RETURN.
    ENDIF.

    ls_spec = field_spec( name ).
    IF ls_spec-found = abap_true AND ctx-row_table IS INITIAL.

      lv_label = label_of( node = node
                                 ctx  = ctx
                                 spec = ls_spec ).
      IF lv_label IS NOT INITIAL.
        result = |{ z2ui5_cl_agent_viewxml=>clip( val = lv_label
                                                  len = 80 ) }: { trigger }|.
        RETURN.
      ENDIF.
    ENDIF.

    CLEAR temp52.
    INSERT `text` INTO TABLE temp52.
    INSERT `title` INTO TABLE temp52.
    INSERT `tooltip` INTO TABLE temp52.
    INSERT `headerText` INTO TABLE temp52.
    INSERT `ariaLabel` INTO TABLE temp52.

    temp154 = temp52.

    LOOP AT temp154 INTO lv_prop.

      lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
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

      lv_text = text_of_raw( raw = lv_raw
                                   ctx = ctx ).
      IF lv_text IS NOT INITIAL.
        result = z2ui5_cl_agent_viewxml=>clip( val = lv_text
                                               len = 80 ).
        RETURN.
      ENDIF.
    ENDLOOP.

    lv_icon = z2ui5_cl_agent_viewxml=>attr( node = node
                                                 name = `icon` ).
    IF lv_icon IS NOT INITIAL
        AND z2ui5_cl_agent_viewxml=>parse_binding( lv_icon )-kind = z2ui5_cl_agent_viewxml=>cs_binding-literal.
      result = icon_name( lv_icon ).
      RETURN.
    ENDIF.

    lv_type = z2ui5_cl_agent_viewxml=>attr( node = node
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

    DATA ls_b TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
    DATA ls_rows TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
    DATA temp155 TYPE i.
    DATA lv_count LIKE temp155.
      DATA lv_row TYPE string.
      DATA lv_text TYPE string.
      DATA lv_type TYPE string.
      DATA lv_target TYPE string.
      DATA temp54 TYPE string_table.
      DATA temp156 LIKE temp54.
      DATA lv_key LIKE LINE OF temp156.
        DATA temp157 TYPE ty_s_val.
        DATA ls_val LIKE temp157.
        DATA temp56 TYPE string_table.
        DATA temp1 TYPE string.
        DATA temp4 LIKE LINE OF temp56.
        DATA temp158 LIKE temp56.
        DATA lv_variant LIKE LINE OF temp158.
        DATA temp159 TYPE string.
        DATA lv_value LIKE temp159.
      DATA temp160 TYPE z2ui5_cl_agent_snapshot=>ty_s_mgr_msg.
      DATA temp58 TYPE z2ui5_cl_agent_snapshot=>ty_s_mgr_msg-type.
    ls_b = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = node
                                                                                       name = `items` ) ).
    IF ls_b-kind <> z2ui5_cl_agent_viewxml=>cs_binding-path OR ls_b-model IS NOT INITIAL OR ls_b-relative = abap_true.
      RETURN.
    ENDIF.

    ls_rows = model_get( model_key  = ctx-model_key
                               path       = ls_b-path
                               check_json = abap_false ).
    IF ls_rows-kind <> z2ui5_cl_agent_viewxml=>cs_kind-array.
      RETURN.
    ENDIF.

    temp155 = ls_rows-num.

    lv_count = temp155.
    DO lv_count TIMES.

      lv_row = tree_path( model_key = ctx-model_key
                                path      = |{ ls_b-path }/{ sy-index - 1 }| ).

      lv_text = ``.

      lv_type = ``.

      lv_target = ``.

      CLEAR temp54.
      INSERT `MESSAGE` INTO TABLE temp54.
      INSERT `TYPE` INTO TABLE temp54.
      INSERT `TARGET` INTO TABLE temp54.

      temp156 = temp54.

      LOOP AT temp156 INTO lv_key.
        " the column as written, in lower case, or capitalized

        CLEAR temp157.

        ls_val = temp157.

        CLEAR temp56.
        INSERT lv_key INTO TABLE temp56.

        temp1 = to_lower( lv_key ).
        INSERT temp1 INTO TABLE temp56.

        temp4 = lv_key(1) && to_lower( substring( val = lv_key off = 1 ) ).
        INSERT temp4 INTO TABLE temp56.

        temp158 = temp56.

        LOOP AT temp158 INTO lv_variant.
          ls_val = model_get( model_key = ctx-model_key
                              path      = lv_variant
                              base      = lv_row ).
          IF ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-undefined AND ls_val-kind <> z2ui5_cl_agent_viewxml=>cs_kind-null.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF z2ui5_cl_agent_viewxml=>val_truthy( ls_val ) = abap_true.
          temp159 = z2ui5_cl_agent_viewxml=>val_to_string( ls_val ).
        ELSE.
          CLEAR temp159.
        ENDIF.

        lv_value = temp159.
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

      CLEAR temp160.

      IF lv_type IS INITIAL.
        temp58 = `info`.
      ELSE.
        temp58 = lv_type.
      ENDIF.
      temp160-type = temp58.
      temp160-text = z2ui5_cl_agent_viewxml=>clip( val = lv_text len = 1000 ).
      temp160-target = lv_target.
      INSERT temp160 INTO TABLE mt_mgr_msg.
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
    DATA lv_source TYPE string.
    DATA temp161 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lt_items LIKE temp161.
    DATA temp162 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lv_item LIKE LINE OF temp162.
      DATA lv_item_name TYPE string.
    DATA lv_items_raw TYPE string.
      DATA lv_bpath TYPE string.
      DATA lv_bmodel TYPE string.
      DATA lv_brelative LIKE abap_false.
      DATA lv_has_bpath LIKE abap_false.
      DATA ls_bound TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
        DATA ls_part LIKE LINE OF ls_bound-t_part.
        DATA temp163 TYPE string.
        DATA ls_rows TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
        DATA temp164 TYPE i.
        DATA temp165 TYPE i.
        DATA lv_template LIKE temp164.
          DATA temp166 TYPE i.
          DATA lv_count LIKE temp166.
    DATA lv_messages TYPE i.
      DATA lv_row LIKE LINE OF lt_entry_row.
      FIELD-SYMBOLS <temp59> LIKE LINE OF lt_entry_row.
      DATA temp60 LIKE sy-tabix.
      DATA ls_item TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_type_raw TYPE string.
      DATA temp167 TYPE string.
      DATA lv_type_value LIKE temp167.
      DATA lv_type TYPE string.
        DATA temp168 TYPE string.
      DATA lv_title TYPE string.
      DATA lv_subtitle TYPE string.
      DATA lv_description TYPE string.
      DATA lv_title_clip TYPE string.
      DATA lv_subtitle_clip TYPE string.
      DATA lv_description_clip TYPE string.
      DATA temp169 TYPE z2ui5_cl_agent_snapshot=>ty_s_message.
    DATA lv_child LIKE LINE OF node-t_child.
      DATA ls_child TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    lv_source = message_source( name ).

    CLEAR temp161.

    lt_items = temp161.

    temp162 = item_controls( node = node ctx = ctx agg = `items` ).

    LOOP AT temp162 INTO lv_item.

      lv_item_name = z2ui5_cl_agent_viewxml=>control_name( node( doc = ctx-doc
                                                                       id  = lv_item ) ).
      IF lv_item_name = `sap.m.MessageItem` OR lv_item_name = `sap.m.MessagePopoverItem`.
        INSERT lv_item INTO TABLE lt_items.
      ENDIF.
    ENDLOOP.


    lv_items_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = `items`
                                                       IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      LOOP AT lt_items INTO lv_item.
        INSERT lv_item INTO TABLE lt_entry_item.
        INSERT `` INTO TABLE lt_entry_row.
      ENDLOOP.
    ELSE.

      lv_bpath = ``.

      lv_bmodel = ``.

      lv_brelative = abap_false.

      lv_has_bpath = abap_false.

      ls_bound = z2ui5_cl_agent_viewxml=>parse_binding( lv_items_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        lv_has_bpath = abap_true.
        lv_bpath = ls_bound-path.
        lv_bmodel = ls_bound-model.
        lv_brelative = ls_bound-relative.
      ELSE.

        LOOP AT ls_bound-t_part INTO ls_part WHERE is_path = abap_true. "#EC CI_SORTSEQ
          lv_has_bpath = abap_true.
          lv_bpath = ls_part-path.
          lv_bmodel = ls_part-model.
          lv_brelative = ls_part-relative.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF lv_bpath IS INITIAL OR lv_bmodel IS NOT INITIAL OR lv_brelative = abap_true.

        IF lv_has_bpath = abap_true AND lv_bmodel IS NOT INITIAL.
          temp163 = |the named model '{ lv_bmodel }'|.
        ELSE.
          temp163 = `something other than a model table`.
        ENDIF.
        note( |{ node-local } bound to { temp163 } ({ ctx-layer }) - messages not described| ).
      ELSE.

        ls_rows = model_get( model_key  = ctx-model_key
                                   path       = lv_bpath
                                   check_json = abap_false ).

        CLEAR temp164.

        READ TABLE lt_items INTO temp165 INDEX 1.
        IF sy-subrc = 0.
          temp164 = temp165.
        ENDIF.

        lv_template = temp164.
        IF ls_rows-kind = z2ui5_cl_agent_viewxml=>cs_kind-array AND lv_template > 0.

          temp166 = ls_rows-num.

          lv_count = temp166.
          DO lv_count TIMES.
            INSERT lv_template INTO TABLE lt_entry_item.
            INSERT tree_path( model_key = ctx-model_key
                              path      = |{ lv_bpath }/{ sy-index - 1 }| ) INTO TABLE lt_entry_row.
          ENDDO.
        ENDIF.
      ENDIF.
    ENDIF.


    lv_messages = 0.
    LOOP AT lt_entry_item INTO lv_item.



      temp60 = sy-tabix.
      READ TABLE lt_entry_row INDEX sy-tabix ASSIGNING <temp59>.
      sy-tabix = temp60.
      IF sy-subrc <> 0.
        ASSERT 1 = 0.
      ENDIF.
      lv_row = <temp59>.

      ls_item = node( doc = ctx-doc
                            id  = lv_item ).
      " the item's type; absent (or empty) is UI5's default, Error

      lv_type_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_item
                                                                  name  = `type`
                                                        IMPORTING found = lv_found ).

      IF lv_found = abap_false.
        temp167 = `Error`.
      ELSE.
        temp167 = text_of_raw( raw = lv_type_raw ctx = ctx row = lv_row ).
      ENDIF.

      lv_type_value = temp167.

      lv_type = message_type( lv_type_value ).
      IF lv_type IS INITIAL.

        IF lv_type_value IS INITIAL.
          temp168 = `error`.
        ELSE.
          temp168 = `info`.
        ENDIF.
        lv_type = temp168.
      ENDIF.

      lv_title = text_of( node = ls_item
                                name = `title`
                                ctx  = ctx
                                row  = lv_row ).

      lv_subtitle = text_of( node = ls_item
                                   name = `subtitle`
                                   ctx  = ctx
                                   row  = lv_row ).

      lv_description = text_of( node = ls_item
                                      name = `description`
                                      ctx  = ctx
                                      row  = lv_row ).
      IF lv_description IS NOT INITIAL AND bool( node          = ls_item
                                                 name          = `markupDescription`
                                                 ctx           = ctx
                                                 row           = lv_row
                                                 default_value = abap_false ) = abap_true.
        lv_description = strip_tags( lv_description ).
      ENDIF.
      " clipped: whitespace collapsed - empty when there is nothing but blanks

      lv_title_clip = z2ui5_cl_agent_viewxml=>clip( val = lv_title
                                                          len = 1000 ).

      lv_subtitle_clip = z2ui5_cl_agent_viewxml=>clip( val = lv_subtitle
                                                             len = 1000 ).

      lv_description_clip = z2ui5_cl_agent_viewxml=>clip( val = lv_description
                                                                len = 1000 ).
      IF lv_title_clip IS INITIAL AND lv_subtitle_clip IS INITIAL AND lv_description_clip IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_messages = lv_messages + 1.
      IF lv_messages > c_max_item_messages.
        CONTINUE.
      ENDIF.

      CLEAR temp169.
      temp169-type = lv_type.
      temp169-text = lv_title_clip.
      temp169-source = lv_source.
      temp169-subtitle = lv_subtitle_clip.
      temp169-description = lv_description_clip.
      INSERT temp169 INTO TABLE mt_message.
    ENDLOOP.
    IF lv_messages > c_max_item_messages.
      note( |{ node-local } ({ ctx-layer }): { lv_messages } messages, the first { c_max_item_messages } listed| ).
    ENDIF.

    wires( node = node
           ctx  = ctx
           name = name ).
    " what else it aggregates (a headerButton) is on the screen like any control

    LOOP AT node-t_child INTO lv_child.

      ls_child = node( doc = ctx-doc
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

    DATA lv_bound_raw TYPE string.
    DATA lv_bpath TYPE string.
    DATA lv_bmodel TYPE string.
    DATA lv_brelative LIKE abap_false.
    DATA lv_has_bpath LIKE abap_false.
      DATA ls_bound TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
        DATA ls_part LIKE LINE OF ls_bound-t_part.
        DATA temp170 TYPE string.
    DATA lv_table_id TYPE string.
    DATA lv_label TYPE string.
    DATA ls_rows TYPE z2ui5_cl_agent_snapshot=>ty_s_val.
    DATA temp171 TYPE i.
    DATA temp61 TYPE i.
    DATA lv_row_count LIKE temp61.
    DATA lv_col_agg TYPE i.
      DATA lv_items_agg TYPE i.
      DATA temp172 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
      DATA lt_tmpl TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
        FIELD-SYMBOLS <temp173> LIKE LINE OF lt_tmpl.
        DATA temp174 LIKE sy-tabix.
      DATA temp175 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
      DATA lv_col_candidate LIKE LINE OF temp175.
      DATA ls_template TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_cells_agg TYPE i.
        DATA temp176 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
        DATA lt_cell_nodes TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
        DATA lv_cell_node LIKE LINE OF lt_cell_nodes.
          DATA temp177 TYPE i.
          DATA temp178 TYPE i.
          DATA lv_col_node LIKE temp177.
          DATA temp179 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellsrc.
          DATA temp62 TYPE abap_bool.
        DATA ls_tattr LIKE LINE OF ls_template-t_attr.
          DATA ls_tb TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
          DATA lv_take LIKE abap_false.
            DATA ls_tpart LIKE LINE OF ls_tb-t_part.
            DATA temp180 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellsrc.
          DATA temp181 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
          DATA lv_desc LIKE LINE OF temp181.
            DATA lv_main TYPE string.
              DATA temp182 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellsrc.
      DATA lv_column LIKE LINE OF lt_columns.
        DATA ls_col TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
        DATA lv_tmpl_agg TYPE i.
        DATA lt_tnode TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
        DATA lv_header TYPE string.
          DATA lv_label_agg TYPE i.
          DATA temp183 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
          DATA lt_lnode TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
            FIELD-SYMBOLS <temp184> LIKE LINE OF lt_lnode.
            DATA temp185 LIKE sy-tabix.
        DATA temp186 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellsrc.
        FIELD-SYMBOLS <temp63> LIKE LINE OF lt_tnode.
        DATA temp64 LIKE sy-tabix.
    DATA temp187 TYPE ty_s_table.
    DATA ls_table LIKE temp187.
    DATA ls_cell LIKE LINE OF lt_cell.
      DATA lv_cell_index LIKE sy-tabix.
      DATA ls_cn TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA temp188 TYPE string.
      DATA lv_prop LIKE temp188.
      DATA temp189 TYPE ty_s_cellspec.
      DATA ls_spec_cell LIKE temp189.
      DATA lv_col_name TYPE string.
      DATA temp190 LIKE sy-subrc.
      DATA temp191 LIKE sy-tabix.
      DATA temp192 TYPE z2ui5_cl_agent_snapshot=>ty_s_column.
      DATA temp65 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellsrc-header.
        DATA ls_cell_field TYPE z2ui5_cl_agent_snapshot=>ty_s_spec.
          DATA temp193 TYPE z2ui5_cl_agent_snapshot=>ty_s_cellspec-field_kind.
      DATA temp194 TYPE string.
      DATA lv_mode LIKE temp194.
      DATA temp195 TYPE string.
    DATA temp196 TYPE z2ui5_cl_agent_snapshot=>ty_s_table-selection_mode.
      DATA lv_sel_raw TYPE string.
        DATA ls_sb TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.
    DATA temp197 LIKE LINE OF ls_table-t_cellspec.
    DATA lr_spec LIKE REF TO temp197.
      DATA ls_cell_node TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_ok LIKE abap_false.
    DATA temp198 LIKE sy-subrc.
    DATA lv_shown TYPE i.
      DATA lv_row TYPE string.
      DATA temp199 TYPE ty_s_row.
      DATA ls_row LIKE temp199.
      DATA ls_cs LIKE LINE OF ls_table-t_cellspec.
        DATA temp200 TYPE ty_s_val.
        DATA ls_val LIKE temp200.
        DATA temp201 TYPE z2ui5_cl_agent_snapshot=>ty_s_cell.
      DATA temp202 LIKE sy-subrc.
        DATA temp203 TYPE z2ui5_cl_agent_snapshot=>ty_s_cell.
    DATA temp11 TYPE xsdboolean.
    DATA ls_attr LIKE LINE OF node-t_attr.
      DATA lv_pick TYPE abap_bool.
      DATA temp12 TYPE xsdboolean.
      DATA ls_row_ctx LIKE ctx.
    DATA lv_child LIKE LINE OF node-t_child.
      DATA ls_child TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_is_agg TYPE abap_bool.
        DATA lv_col LIKE LINE OF ls_child-t_child.
          DATA ls_colnode TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
          DATA lv_sub LIKE LINE OF ls_colnode-t_child.
            DATA ls_sub TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
            DATA lv_sub_agg TYPE abap_bool.
            DATA temp204 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
            DATA temp66 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
            DATA lt_headers LIKE temp66.
            DATA lv_h LIKE LINE OF lt_headers.
              DATA lv_hn TYPE string.
    DATA ls_tmpl_ctx LIKE ctx.
      DATA lv_local TYPE z2ui5_cl_agent_viewxml=>ty_s_node-local.
        DATA ls_agg_ctx LIKE ls_tmpl_ctx.
    lv_bound_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                                 name  = agg
                                                       IMPORTING found = lv_found ).

    lv_bpath = ``.

    lv_bmodel = ``.

    lv_brelative = abap_false.

    lv_has_bpath = abap_false.
    IF lv_found = abap_true.

      ls_bound = z2ui5_cl_agent_viewxml=>parse_binding( lv_bound_raw ).
      IF ls_bound-kind = z2ui5_cl_agent_viewxml=>cs_binding-path.
        lv_has_bpath = abap_true.
        lv_bpath = ls_bound-path.
        lv_bmodel = ls_bound-model.
        lv_brelative = ls_bound-relative.
      ELSE.

        LOOP AT ls_bound-t_part INTO ls_part WHERE is_path = abap_true. "#EC CI_SORTSEQ
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

        IF lv_has_bpath = abap_true AND lv_bmodel IS NOT INITIAL.
          temp170 = |the named model '{ lv_bmodel }'|.
        ELSE.
          temp170 = `something other than a model table`.
        ENDIF.
        note( |{ node-local } bound to { temp170 } ({ ctx-layer }) - rows not described| ).
      ENDIF.
      wires( node = node
             ctx  = ctx
             name = name ).
      walk_children( t_child = node-t_child
                     ctx     = ctx ).
      RETURN.
    ENDIF.


    lv_table_id = |t{ lines( mt_table ) + 1 }|.

    lv_label = text_of( node = node
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

    ls_rows = model_get( model_key  = ctx-model_key
                               path       = lv_bpath
                               check_json = abap_false ).

    temp171 = ls_rows-num.

    IF ls_rows-kind = z2ui5_cl_agent_viewxml=>cs_kind-array.
      temp61 = temp171.
    ELSE.
      CLEAR temp61.
    ENDIF.

    lv_row_count = temp61.

    " the template: the one control of the bound aggregation

    lv_col_agg = child_agg( doc   = ctx-doc
                                  node  = node
                                  local = `columns` ).
    IF kind = `m`.

      lv_items_agg = child_agg( doc   = ctx-doc
                                      node  = node
                                      local = agg ).

      IF lv_items_agg > 0.
        temp172 = node( doc = ctx-doc id = lv_items_agg )-t_child.
      ELSE.
        temp172 = node-t_child.
      ENDIF.

      lt_tmpl = controls_of( doc     = ctx-doc
                                   t_child = temp172 ).
      IF lt_tmpl IS NOT INITIAL.


        temp174 = sy-tabix.
        READ TABLE lt_tmpl INDEX 1 ASSIGNING <temp173>.
        sy-tabix = temp174.
        IF sy-subrc <> 0.
          ASSERT 1 = 0.
        ENDIF.
        lv_template = <temp173>.
      ENDIF.
      IF lv_col_agg > 0.
        lt_columns = controls_of( doc     = ctx-doc
                                  t_child = node( doc = ctx-doc
                                                  id  = lv_col_agg )-t_child ).
      ENDIF.
    ELSEIF lv_col_agg > 0.
      lt_columns = controls_of( doc     = ctx-doc
                                t_child = node( doc = ctx-doc
                                                id  = lv_col_agg )-t_child ).
    ELSE.

      temp175 = controls_of( doc = ctx-doc t_child = node-t_child ).

      LOOP AT temp175 INTO lv_col_candidate.
        IF ends_with( val    = node( doc = ctx-doc
                                     id  = lv_col_candidate )-local
                      suffix = `Column` ) = abap_true.
          INSERT lv_col_candidate INTO TABLE lt_columns.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " the cells: which control, which property, which header
    IF kind = `m` AND lv_template > 0.

      ls_template = node( doc = ctx-doc
                                id  = lv_template ).

      lv_cells_agg = child_agg( doc   = ctx-doc
                                      node  = ls_template
                                      local = `cells` ).
      IF lv_cells_agg > 0 OR z2ui5_cl_agent_viewxml=>control_name( ls_template ) = `sap.m.ColumnListItem`.

        IF lv_cells_agg > 0.
          temp176 = node( doc = ctx-doc id = lv_cells_agg )-t_child.
        ELSE.
          temp176 = ls_template-t_child.
        ENDIF.

        lt_cell_nodes = controls_of( doc     = ctx-doc
                                           t_child = temp176 ).

        LOOP AT lt_cell_nodes INTO lv_cell_node.

          CLEAR temp177.

          READ TABLE lt_columns INTO temp178 INDEX sy-tabix.
          IF sy-subrc = 0.
            temp177 = temp178.
          ENDIF.

          lv_col_node = temp177.

          CLEAR temp179.
          temp179-node = lv_cell_node.
          temp179-header = column_header( ctx = ctx col = lv_col_node ).

          IF lv_col_node > 0.
            temp62 = bool( node = node( doc = ctx-doc id = lv_col_node ) name = `visible` ctx = ctx default_value = abap_true ).
          ELSE.
            temp62 = abap_true.
          ENDIF.
          temp179-visible = temp62.
          INSERT temp179 INTO TABLE lt_cell.
        ENDLOOP.
      ELSE.
        " a list item: its bound properties are the columns

        LOOP AT ls_template-t_attr INTO ls_tattr.
          IF ls_tattr-name = `selected` OR ls_tattr-name = `type` OR ls_tattr-name = `visible` OR ls_tattr-name = `highlight`
              OR ls_tattr-name = `unread` OR ls_tattr-name = `counter` OR ls_tattr-name = `navigated`
              OR ls_tattr-name = `id` OR ls_tattr-name = `class`.
            CONTINUE.
          ENDIF.
          IF z2ui5_cl_agent_viewxml=>has_wire( ls_tattr-value ) = abap_true.
            CONTINUE.
          ENDIF.

          ls_tb = z2ui5_cl_agent_viewxml=>parse_binding( ls_tattr-value ).

          lv_take = abap_false.
          IF ls_tb-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_tb-relative = abap_true AND ls_tb-model IS INITIAL.
            lv_take = abap_true.
          ELSEIF ls_tb-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.

            LOOP AT ls_tb-t_part INTO ls_tpart WHERE is_path = abap_true AND relative = abap_true. "#EC CI_SORTSEQ
              IF ls_tpart-path IS NOT INITIAL.
                lv_take = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDIF.
          IF lv_take = abap_true.

            CLEAR temp180.
            temp180-node = lv_template.
            temp180-prop = ls_tattr-name.
            temp180-header = ls_tattr-name.
            temp180-visible = abap_true.
            INSERT temp180 INTO TABLE lt_cell.
          ENDIF.
        ENDLOOP.
        IF lt_cell IS INITIAL.
          " a CustomListItem: the bound controls inside it

          temp181 = descendants( doc = ctx-doc id = lv_template ).

          LOOP AT temp181 INTO lv_desc.

            lv_main = main_prop( node( doc = ctx-doc
                                             id  = lv_desc ) ).
            IF lv_main IS NOT INITIAL.

              CLEAR temp182.
              temp182-node = lv_desc.
              temp182-prop = lv_main.
              temp182-header = lv_main.
              temp182-visible = abap_true.
              INSERT temp182 INTO TABLE lt_cell.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ELSEIF kind = `ui`.

      LOOP AT lt_columns INTO lv_column.

        ls_col = node( doc = ctx-doc
                             id  = lv_column ).

        lv_tmpl_agg = child_agg( doc   = ctx-doc
                                       node  = ls_col
                                       local = `template` ).
        IF lv_tmpl_agg = 0.
          CONTINUE.
        ENDIF.

        lt_tnode = controls_of( doc     = ctx-doc
                                      t_child = node( doc = ctx-doc
                                                      id  = lv_tmpl_agg )-t_child ).
        IF lt_tnode IS INITIAL.
          CONTINUE.
        ENDIF.

        lv_header = text_of( node = ls_col
                                   name = `label`
                                   ctx  = ctx ).
        IF lv_header IS INITIAL.
          " the label aggregation, written out or as the column's default one

          lv_label_agg = child_agg( doc   = ctx-doc
                                          node  = ls_col
                                          local = `label` ).

          IF lv_label_agg > 0.
            temp183 = node( doc = ctx-doc id = lv_label_agg )-t_child.
          ELSE.
            temp183 = ls_col-t_child.
          ENDIF.

          lt_lnode = controls_of( doc     = ctx-doc
                                        t_child = temp183 ).
          IF lt_lnode IS NOT INITIAL.


            temp185 = sy-tabix.
            READ TABLE lt_lnode INDEX 1 ASSIGNING <temp184>.
            sy-tabix = temp185.
            IF sy-subrc <> 0.
              ASSERT 1 = 0.
            ENDIF.
            lv_header = text_of( node = node( doc = ctx-doc
                                              id  = <temp184> )
                                 name = `text`
                                 ctx  = ctx ).
          ENDIF.
        ENDIF.

        CLEAR temp186.


        temp64 = sy-tabix.
        READ TABLE lt_tnode INDEX 1 ASSIGNING <temp63>.
        sy-tabix = temp64.
        IF sy-subrc <> 0.
          ASSERT 1 = 0.
        ENDIF.
        temp186-node = <temp63>.
        temp186-header = lv_header.
        temp186-visible = bool( node = ls_col name = `visible` ctx = ctx default_value = abap_true ).
        INSERT temp186 INTO TABLE lt_cell.
      ENDLOOP.
    ENDIF.

    " columns and how each one is read

    CLEAR temp187.
    temp187-id = lv_table_id.
    temp187-path = lv_bpath.
    temp187-name = name_of_path( lv_bpath ).
    temp187-label = z2ui5_cl_agent_viewxml=>clip( val = lv_label len = 120 ).
    temp187-control = name.
    temp187-row_count = lv_row_count.
    temp187-layer = ctx-layer.
    temp187-model_key = ctx-model_key.
    temp187-doc = ctx-doc.

    ls_table = temp187.

    LOOP AT lt_cell INTO ls_cell.

      lv_cell_index = sy-tabix.
      IF ls_cell-visible = abap_false.
        CONTINUE.
      ENDIF.

      ls_cn = node( doc = ctx-doc
                          id  = ls_cell-node ).

      IF ls_cell-prop IS NOT INITIAL.
        temp188 = ls_cell-prop.
      ELSE.
        temp188 = main_prop( ls_cn ).
      ENDIF.

      lv_prop = temp188.

      CLEAR temp189.
      temp189-node = ls_cell-node.
      temp189-prop = lv_prop.

      ls_spec_cell = temp189.

      lv_col_name = |COL{ lv_cell_index }|.
      IF lv_prop IS NOT INITIAL.
        ls_spec_cell-has_binding = abap_true.
        ls_spec_cell-binding = z2ui5_cl_agent_viewxml=>parse_binding( z2ui5_cl_agent_viewxml=>attr( node = ls_cn
                                                                                                     name = lv_prop ) ).
        IF ls_spec_cell-binding-kind = z2ui5_cl_agent_viewxml=>cs_binding-path
            AND ls_spec_cell-binding-relative = abap_true AND ls_spec_cell-binding-model IS INITIAL.
          lv_col_name = ls_spec_cell-binding-path.
        ENDIF.
      ENDIF.


      temp191 = sy-tabix.
      READ TABLE lt_used WITH KEY table_line = lv_col_name TRANSPORTING NO FIELDS.
      temp190 = sy-subrc.
      sy-tabix = temp191.
      IF temp190 = 0. "#EC CI_SORTSEQ
        lv_col_name = |{ lv_col_name }_{ lv_cell_index }|.
      ENDIF.
      INSERT lv_col_name INTO TABLE lt_used.
      ls_spec_cell-name = lv_col_name.

      CLEAR temp192.
      temp192-name = lv_col_name.

      IF ls_cell-header IS NOT INITIAL.
        temp65 = ls_cell-header.
      ELSE.
        temp65 = lv_col_name.
      ENDIF.
      temp192-label = z2ui5_cl_agent_viewxml=>clip( val = temp65 len = 80 ).
      INSERT temp192 INTO TABLE ls_table-t_column.
      IF ls_cell-prop IS INITIAL.

        ls_cell_field = field_spec( z2ui5_cl_agent_viewxml=>control_name( ls_cn ) ).
        IF ls_cell_field-found = abap_true.
          ls_spec_cell-has_field_spec = abap_true.

          IF ls_cell_field-kind = `input`.
            temp193 = `text`.
          ELSE.
            temp193 = ls_cell_field-kind.
          ENDIF.
          ls_spec_cell-field_kind = temp193.
        ENDIF.
      ENDIF.
      INSERT ls_spec_cell INTO TABLE ls_table-t_cellspec.
    ENDLOOP.

    " selection
    IF dialog = abap_true.
      " a selection dialog always selects: one row (a pick confirms) or several

      IF bool( node = node name = `multiSelect` ctx = ctx default_value = abap_false ) = abap_true.
        temp194 = `Multi`.
      ELSE.
        temp194 = `Single`.
      ENDIF.

      lv_mode = temp194.
    ELSEIF kind = `m`.
      lv_mode = text_of( node = node
                         name = `mode`
                         ctx  = ctx ).
    ELSE.
      z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                              name  = `selectionMode`
                                    IMPORTING found = lv_found ).

      IF lv_found = abap_true.
        temp195 = text_of( node = node name = `selectionMode` ctx = ctx ).
      ELSE.
        temp195 = `MultiToggle`.
      ENDIF.
      lv_mode = temp195.
    ENDIF.

    IF find( val = lv_mode sub = `Multi` ) >= 0.
      temp196 = `Multi`.
    ELSEIF find( val = lv_mode sub = `Single` ) >= 0.
      temp196 = `Single`.
    ELSE.
      temp196 = `None`.
    ENDIF.
    ls_table-selection_mode = temp196.
    IF lv_template > 0.

      lv_sel_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node( doc = ctx-doc
                                                                               id  = lv_template )
                                                                 name  = `selected`
                                                       IMPORTING found = lv_found ).
      IF lv_found = abap_true.

        ls_sb = z2ui5_cl_agent_viewxml=>parse_binding( lv_sel_raw ).
        IF ls_sb-kind = z2ui5_cl_agent_viewxml=>cs_binding-path AND ls_sb-relative = abap_true AND ls_sb-model IS INITIAL.
          ls_table-selection_field = ls_sb-path.
        ENDIF.
      ENDIF.
    ENDIF.

    " editable cells: an input bound to a row property, not disabled for every row


    LOOP AT ls_table-t_cellspec REFERENCE INTO lr_spec.
      IF lr_spec->has_field_spec = abap_false OR lr_spec->has_binding = abap_false
          OR lr_spec->binding-kind <> z2ui5_cl_agent_viewxml=>cs_binding-path
          OR lr_spec->binding-relative = abap_false OR lr_spec->binding-model IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      lr_spec->check_editable = abap_true.

      ls_cell_node = node( doc = ctx-doc
                                 id  = lr_spec->node ).

      lv_ok = abap_false.
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

    READ TABLE ls_table-t_editable WITH KEY table_line = ls_table-selection_field TRANSPORTING NO FIELDS.
    temp198 = sy-subrc.
    IF ls_table-selection_field IS NOT INITIAL AND NOT temp198 = 0. "#EC CI_SORTSEQ
      INSERT ls_table-selection_field INTO TABLE ls_table-t_editable.
    ENDIF.

    " the first rows

    lv_shown = nmin( val1 = lv_row_count
                           val2 = mv_rows ).
    DO lv_shown TIMES.

      lv_row = tree_path( model_key = ctx-model_key
                                path      = |{ lv_bpath }/{ sy-index - 1 }| ).

      CLEAR temp199.

      ls_row = temp199.

      LOOP AT ls_table-t_cellspec INTO ls_cs.

        CLEAR temp200.
        temp200-kind = z2ui5_cl_agent_viewxml=>cs_kind-null.

        ls_val = temp200.
        IF ls_cs-prop IS NOT INITIAL.
          ls_val = resolve( raw = z2ui5_cl_agent_viewxml=>attr( node = node( doc = ctx-doc
                                                                             id  = ls_cs-node )
                                                                name = ls_cs-prop )
                            ctx = ctx
                            row = lv_row ).
        ENDIF.

        CLEAR temp201.
        temp201-name = ls_cs-name.
        temp201-val = ls_val.
        INSERT temp201 INTO TABLE ls_row-t_cell.
      ENDLOOP.

      READ TABLE ls_row-t_cell WITH KEY name = ls_table-selection_field TRANSPORTING NO FIELDS.
      temp202 = sy-subrc.
      IF ls_table-selection_field IS NOT INITIAL AND NOT temp202 = 0. "#EC CI_SORTSEQ

        CLEAR temp203.
        temp203-name = ls_table-selection_field.
        temp203-val = model_get( model_key = ctx-model_key path = ls_table-selection_field base = lv_row ).
        INSERT temp203 INTO TABLE ls_row-t_cell.
      ENDIF.
      INSERT ls_row INTO TABLE ls_table-t_row.
    ENDDO.

    temp11 = boolc( lv_row_count > lines( ls_table-t_row ) ).
    ls_table-truncated = temp11.
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

    LOOP AT node-t_attr INTO ls_attr.
      IF z2ui5_cl_agent_viewxml=>has_wire( ls_attr-value ) = abap_false.
        CONTINUE.
      ENDIF.


      temp12 = boolc( dialog = abap_true AND ls_attr-name = `confirm` ).
      lv_pick = temp12.

      ls_row_ctx = ctx.
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

    LOOP AT node-t_child INTO lv_child.

      ls_child = node( doc = ctx-doc
                             id  = lv_child ).

      lv_is_agg = z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ).
      IF ( lv_is_agg = abap_true AND ls_child-local = agg ) OR lv_child = lv_template.
        CONTINUE.
      ENDIF.
      IF ls_child-local = `columns`.

        LOOP AT ls_child-t_child INTO lv_col.

          ls_colnode = node( doc = ctx-doc
                                   id  = lv_col ).

          LOOP AT ls_colnode-t_child INTO lv_sub.

            ls_sub = node( doc = ctx-doc
                                 id  = lv_sub ).

            lv_sub_agg = z2ui5_cl_agent_viewxml=>is_aggregation( ls_sub ).
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

            CLEAR temp204.
            INSERT lv_sub INTO TABLE temp204.

            IF lv_sub_agg = abap_true.
              temp66 = controls_of( doc = ctx-doc t_child = ls_sub-t_child ).
            ELSE.
              temp66 = temp204.
            ENDIF.

            lt_headers = temp66.

            LOOP AT lt_headers INTO lv_h.

              lv_hn = z2ui5_cl_agent_viewxml=>control_name( node( doc = ctx-doc
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

    ls_tmpl_ctx = ctx.
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

      lv_local = node( doc = ctx-doc
                             id  = lv_child )-local.
      IF lv_local = `rowActionTemplate` OR lv_local = `rowSettingsTemplate`.

        ls_agg_ctx = ls_tmpl_ctx.
        ls_agg_ctx-row_template = lv_local.
        walk_template( id  = lv_child
                       ctx = ls_agg_ctx ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD cell_ok.

    " two checks: the 7.02 downport puts one xsdbool( ) on one line
    DATA temp13 TYPE xsdboolean.
      DATA temp14 TYPE xsdboolean.
    temp13 = boolc( bool( node = node name = `editable` ctx = ctx row = row default_value = abap_true ) = abap_true AND bool( node = node name = `enabled` ctx = ctx row = row default_value = abap_true ) = abap_true ).
    result = temp13.
    IF result = abap_true.

      temp14 = boolc( bool( node = node name = `displayOnly` ctx = ctx row = row default_value = abap_false ) = abap_false ).
      result = temp14.
    ENDIF.

  ENDMETHOD.

  METHOD cell_editable.

    DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA ls_spec TYPE z2ui5_cl_agent_snapshot=>ty_s_cellspec.
      DATA temp206 LIKE sy-subrc.
      DATA temp15 TYPE xsdboolean.
    DATA temp207 TYPE ty_s_ctx.
    DATA ls_ctx LIKE temp207.
    READ TABLE mt_table INTO ls_table WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    READ TABLE ls_table-t_cellspec INTO ls_spec WITH KEY name = column. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR ls_spec-check_editable = abap_false.
      " the selection field and the cells without a probe are editable as listed

      READ TABLE ls_table-t_editable WITH KEY table_line = column TRANSPORTING NO FIELDS.
      temp206 = sy-subrc.

      temp15 = boolc( temp206 = 0 ).
      result = temp15. "#EC CI_SORTSEQ
      RETURN.
    ENDIF.

    CLEAR temp207.
    temp207-doc = ls_table-doc.
    temp207-layer = ls_table-layer.
    temp207-model_key = ls_table-model_key.

    ls_ctx = temp207.
    result = cell_ok( ctx  = ls_ctx
                      node = node( doc = ls_table-doc
                                   id  = ls_spec-node )
                      row  = tree_path( model_key = ls_table-model_key
                                        path      = |{ ls_table-path }/{ row }| ) ).

  ENDMETHOD.

  METHOD source_value.

    DATA lv_found TYPE abap_bool.
    DATA lv_row TYPE string.
    DATA ls_action TYPE z2ui5_cl_agent_snapshot=>ty_s_action.
    DATA ls_node TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    DATA lv_raw TYPE string.
      DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA temp208 TYPE ty_s_ctx.
    DATA ls_ctx LIKE temp208.
    DATA ls_binding TYPE z2ui5_cl_agent_viewxml=>ty_s_binding.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.

    READ TABLE mt_action INTO ls_action WITH KEY id = action_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR ls_action-node = 0.
      RETURN.
    ENDIF.

    ls_node = node( doc = ls_action-doc
                          id  = ls_action-node ).

    lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                           name  = prop
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    IF ls_action-table IS NOT INITIAL AND row >= 0.

      READ TABLE mt_table INTO ls_table WITH KEY id = ls_action-table. "#EC CI_SORTSEQ
      IF sy-subrc = 0.
        lv_row = tree_path( model_key = ls_table-model_key
                            path      = |{ ls_table-path }/{ row }| ).
      ENDIF.
    ENDIF.

    CLEAR temp208.
    temp208-doc = ls_action-doc.
    temp208-layer = ls_action-layer.
    temp208-model_key = ls_action-model_key.

    ls_ctx = temp208.

    ls_binding = z2ui5_cl_agent_viewxml=>parse_binding( lv_raw ).
    IF ls_binding-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.
      RETURN.
    ENDIF.
    result = resolve( raw = lv_raw
                      ctx = ls_ctx
                      row = lv_row ).

  ENDMETHOD.

  METHOD template_value.

    DATA lv_found TYPE abap_bool.
    DATA ls_table TYPE z2ui5_cl_agent_snapshot=>ty_s_table.
    DATA lv_raw TYPE string.
    DATA temp209 TYPE ty_s_ctx.
    DATA ls_ctx LIKE temp209.

    result-kind = z2ui5_cl_agent_viewxml=>cs_kind-undefined.

    READ TABLE mt_table INTO ls_table WITH KEY id = table_id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0 OR node = 0.
      RETURN.
    ENDIF.

    lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = me->node( doc = ls_table-doc
                                                                             id  = node )
                                                           name  = prop
                                                 IMPORTING found = lv_found ).
    IF lv_found = abap_false.
      RETURN.
    ENDIF.
    IF z2ui5_cl_agent_viewxml=>parse_binding( lv_raw )-kind = z2ui5_cl_agent_viewxml=>cs_binding-composite.
      RETURN.
    ENDIF.

    CLEAR temp209.
    temp209-doc = ls_table-doc.
    temp209-layer = ls_table-layer.
    temp209-model_key = ls_table-model_key.

    ls_ctx = temp209.
    result = resolve( raw = lv_raw
                      ctx = ls_ctx
                      row = tree_path( model_key = ls_table-model_key
                                       path      = |{ ls_table-path }/{ row }| ) ).

  ENDMETHOD.

  METHOD walk_template.

    DATA lv_found TYPE abap_bool.

    DATA ls_node TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_child LIKE LINE OF ls_node-t_child.
    DATA lv_visible TYPE string.
    DATA lv_name TYPE string.
    DATA ls_spec TYPE z2ui5_cl_agent_snapshot=>ty_s_spec.
    ls_node = node( doc = ctx-doc
                          id  = id ).
    IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_node ) = abap_true.

      LOOP AT ls_node-t_child INTO lv_child.
        walk_template( id  = lv_child
                       ctx = ctx ).
      ENDLOOP.
      RETURN.
    ENDIF.

    lv_visible = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_node
                                                               name  = `visible`
                                                     IMPORTING found = lv_found ).
    IF lv_found = abap_true AND condense( lv_visible ) = `false`.
      RETURN.
    ENDIF.

    lv_name = z2ui5_cl_agent_viewxml=>control_name( ls_node ).
    IF starts_sap( ls_node-ns ) = abap_false.
      note( |custom control { lv_name } in table { ctx-row_table } - not described| ).
    ENDIF.
    wires( node = ls_node
           ctx  = ctx
           name = lv_name ).

    ls_spec = field_spec( lv_name ).
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
    DATA ls_col TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    DATA lv_header TYPE string.
    DATA lv_header_agg TYPE i.
    DATA temp210 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lt_hnode TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA ls_h TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    FIELD-SYMBOLS <temp67> LIKE LINE OF lt_hnode.
    DATA temp68 LIKE sy-tabix.
    DATA temp211 TYPE string.

    IF col = 0.
      RETURN.
    ENDIF.

    ls_col = node( doc = ctx-doc
                         id  = col ).

    lv_header = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_col
                                                              name  = `header`
                                                    IMPORTING found = lv_found ).
    IF lv_found = abap_true.
      result = text_of_raw( raw = lv_header
                            ctx = ctx ).
      RETURN.
    ENDIF.

    lv_header_agg = child_agg( doc   = ctx-doc
                                     node  = ls_col
                                     local = `header` ).

    IF lv_header_agg > 0.
      temp210 = node( doc = ctx-doc id = lv_header_agg )-t_child.
    ELSE.
      temp210 = ls_col-t_child.
    ENDIF.

    lt_hnode = controls_of( doc     = ctx-doc
                                  t_child = temp210 ).
    IF lt_hnode IS INITIAL.
      RETURN.
    ENDIF.



    temp68 = sy-tabix.
    READ TABLE lt_hnode INDEX 1 ASSIGNING <temp67>.
    sy-tabix = temp68.
    IF sy-subrc <> 0.
      ASSERT 1 = 0.
    ENDIF.
    ls_h = node( doc = ctx-doc
                       id  = <temp67> ).
    z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = ls_h
                                            name  = `text`
                                  IMPORTING found = lv_found ).

    IF lv_found = abap_true.
      temp211 = `text`.
    ELSE.
      temp211 = `title`.
    ENDIF.
    result = text_of( node = ls_h
                      name = temp211
                      ctx  = ctx ).

  ENDMETHOD.

  METHOD header_title.

    DATA lv_child LIKE LINE OF node-t_child.
      DATA ls_child TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
      DATA lv_title TYPE i.
    LOOP AT node-t_child INTO lv_child.

      ls_child = node( doc = ctx-doc
                             id  = lv_child ).
      IF z2ui5_cl_agent_viewxml=>is_aggregation( ls_child ) = abap_false.
        CONTINUE.
      ENDIF.
      IF ls_child-local <> `headerToolbar` AND ls_child-local <> `extension` AND ls_child-local <> `infoToolbar`
          AND ls_child-local <> `title` AND ls_child-local <> `toolbar`.
        CONTINUE.
      ENDIF.

      lv_title = find_first( doc     = ctx-doc
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

    DATA temp212 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lv_child LIKE LINE OF temp212.
      DATA ls_child TYPE z2ui5_cl_agent_viewxml=>ty_s_node.
    temp212 = node( doc = doc id = id )-t_child.

    LOOP AT temp212 INTO lv_child.

      ls_child = node( doc = doc
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

    DATA temp213 TYPE z2ui5_cl_agent_viewxml=>ty_t_int.
    DATA lv_child LIKE LINE OF temp213.
    temp213 = node( doc = doc id = id )-t_child.

    LOOP AT temp213 INTO lv_child.
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

    DATA ls_spec TYPE z2ui5_cl_agent_snapshot=>ty_s_spec.
      DATA lv_prop LIKE LINE OF ls_spec-t_prop.
    DATA temp69 TYPE string_table.
    DATA temp214 LIKE temp69.
      DATA lv_raw TYPE string.
    ls_spec = field_spec( z2ui5_cl_agent_viewxml=>control_name( node ) ).
    IF ls_spec-found = abap_true.

      LOOP AT ls_spec-t_prop INTO lv_prop.
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

    CLEAR temp69.
    INSERT `text` INTO TABLE temp69.
    INSERT `title` INTO TABLE temp69.
    INSERT `number` INTO TABLE temp69.
    INSERT `value` INTO TABLE temp69.
    INSERT `displayValue` INTO TABLE temp69.
    INSERT `percentValue` INTO TABLE temp69.
    INSERT `state` INTO TABLE temp69.
    INSERT `selected` INTO TABLE temp69.
    INSERT `src` INTO TABLE temp69.
    INSERT `htmlText` INTO TABLE temp69.

    temp214 = temp69.
    LOOP AT temp214 INTO lv_prop.

      lv_raw = z2ui5_cl_agent_viewxml=>attr( EXPORTING node  = node
                                                             name  = lv_prop
                                                   IMPORTING found = lv_found ).
      IF lv_found = abap_true AND z2ui5_cl_agent_viewxml=>has_wire( lv_raw ) = abap_false.
        result = lv_prop.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD field_spec.
        DATA temp215 TYPE string_table.
        DATA temp217 TYPE string_table.
        DATA temp219 TYPE string_table.
        DATA temp221 TYPE string_table.
        DATA temp223 TYPE string_table.
        DATA temp225 TYPE string_table.
        DATA temp227 TYPE string_table.
        DATA temp229 TYPE string_table.
        DATA temp231 TYPE string_table.
        DATA temp233 TYPE string_table.
        DATA temp235 TYPE string_table.
        DATA temp237 TYPE string_table.
        DATA temp239 TYPE string_table.
        DATA temp241 TYPE string_table.

    " the editable value of each input-like control: which property carries
    " it, and what kind of value it is. text_label: the control's own text
    " names it when nothing else does (a CheckBox "Accept terms")
    result-found = abap_true.
    CASE name.
      WHEN `sap.m.Input`.

        CLEAR temp215.
        INSERT `value` INTO TABLE temp215.
        result-t_prop = temp215.
        result-kind = `input`.
      WHEN `sap.m.InputBase` OR `sap.m.MaskInput` OR `sap.m.SearchField` OR `sap.m.MultiInput`.

        CLEAR temp217.
        INSERT `value` INTO TABLE temp217.
        result-t_prop = temp217.
        result-kind = `text`.
      WHEN `sap.m.TextArea`.

        CLEAR temp219.
        INSERT `value` INTO TABLE temp219.
        result-t_prop = temp219.
        result-kind = `textarea`.
      WHEN `sap.m.StepInput` OR `sap.m.Slider` OR `sap.m.RangeSlider` OR `sap.m.RatingIndicator`.

        CLEAR temp221.
        INSERT `value` INTO TABLE temp221.
        result-t_prop = temp221.
        result-kind = `number`.
      WHEN `sap.m.DatePicker` OR `sap.m.DateRangeSelection`.

        CLEAR temp223.
        INSERT `value` INTO TABLE temp223.
        INSERT `dateValue` INTO TABLE temp223.
        result-t_prop = temp223.
        result-kind = `date`.
      WHEN `sap.m.TimePicker`.

        CLEAR temp225.
        INSERT `value` INTO TABLE temp225.
        INSERT `dateValue` INTO TABLE temp225.
        result-t_prop = temp225.
        result-kind = `time`.
      WHEN `sap.m.DateTimePicker`.

        CLEAR temp227.
        INSERT `value` INTO TABLE temp227.
        INSERT `dateValue` INTO TABLE temp227.
        result-t_prop = temp227.
        result-kind = `datetime`.
      WHEN `sap.m.CheckBox` OR `sap.m.RadioButton`.

        CLEAR temp229.
        INSERT `selected` INTO TABLE temp229.
        result-t_prop = temp229.
        result-kind = `boolean`.
        result-text_label = abap_true.
      WHEN `sap.m.Switch`.

        CLEAR temp231.
        INSERT `state` INTO TABLE temp231.
        result-t_prop = temp231.
        result-kind = `boolean`.
      WHEN `sap.m.ToggleButton`.

        CLEAR temp233.
        INSERT `pressed` INTO TABLE temp233.
        result-t_prop = temp233.
        result-kind = `boolean`.
        result-text_label = abap_true.
      WHEN `sap.m.Select` OR `sap.m.SegmentedButton`.

        CLEAR temp235.
        INSERT `selectedKey` INTO TABLE temp235.
        result-t_prop = temp235.
        result-kind = `choice`.
        result-items = `key`.
      WHEN `sap.m.ComboBox`.

        CLEAR temp237.
        INSERT `selectedKey` INTO TABLE temp237.
        INSERT `value` INTO TABLE temp237.
        result-t_prop = temp237.
        result-kind = `choice`.
        result-items = `key`.
      WHEN `sap.m.MultiComboBox`.

        CLEAR temp239.
        INSERT `selectedKeys` INTO TABLE temp239.
        result-t_prop = temp239.
        result-kind = `multichoice`.
        result-items = `key`.
      WHEN `sap.m.RadioButtonGroup`.

        CLEAR temp241.
        INSERT `selectedIndex` INTO TABLE temp241.
        result-t_prop = temp241.
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
    DATA temp243 TYPE string_table.
    DATA temp71 TYPE string_table.
    DATA temp5 TYPE string_table.
    DATA temp1 TYPE string_table.
    DATA temp7 TYPE string_table.
    DATA temp10 TYPE string_table.
    DATA temp2 TYPE string_table.
    CLEAR temp243.
    INSERT `text` INTO TABLE temp243.

    CLEAR temp71.
    INSERT `title` INTO TABLE temp71.
    INSERT `text` INTO TABLE temp71.

    CLEAR temp5.
    INSERT `number` INTO TABLE temp5.
    INSERT `unit` INTO TABLE temp5.

    CLEAR temp1.
    INSERT `title` INTO TABLE temp1.
    INSERT `number` INTO TABLE temp1.

    CLEAR temp7.
    INSERT `htmlText` INTO TABLE temp7.

    CLEAR temp10.
    INSERT `title` INTO TABLE temp10.
    INSERT `description` INTO TABLE temp10.

    CASE name.
      WHEN `sap.m.Text` OR `sap.m.Title` OR `sap.m.ExpandableText` OR `sap.m.GenericTag` OR `sap.ui.core.Title`.
        temp2 = temp243.
      WHEN `sap.m.ObjectStatus` OR `sap.m.ObjectAttribute` OR `sap.m.ObjectIdentifier`.
        temp2 = temp71.
      WHEN `sap.m.ObjectNumber`.
        temp2 = temp5.
      WHEN `sap.m.ObjectHeader`.
        temp2 = temp1.
      WHEN `sap.m.FormattedText`.
        temp2 = temp7.
      WHEN `sap.m.IllustratedMessage`.
        temp2 = temp10.
    ENDCASE.
    result = temp2.

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

    DATA temp245 TYPE string.
    CASE val.
      WHEN `Error`.
        temp245 = `error`.
      WHEN `Warning`.
        temp245 = `warning`.
      WHEN `Success`.
        temp245 = `success`.
      WHEN `Information`.
        temp245 = `info`.
    ENDCASE.
    result = temp245.

  ENDMETHOD.

  METHOD message_source.

    DATA temp246 TYPE string.
    CASE name.
      WHEN `sap.m.MessagePopover`.
        temp246 = `popover`.
      WHEN `sap.m.MessageView`.
        temp246 = `messageview`.
    ENDCASE.
    result = temp246.

  ENDMETHOD.

  METHOD icon_name.
      DATA lv_slash TYPE i.

    result = val.
    IF strlen( result ) >= 11 AND result(11) = `sap-icon://`.
      result = substring( val = result
                          off = 11 ).

      lv_slash = find( val = result
                             sub = `/` ).
      IF lv_slash > 0.
        result = substring( val = result
                            off = lv_slash + 1 ).
      ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF `-` IN result WITH ` `.

  ENDMETHOD.

  METHOD strip_tags.

    DATA lv_pos TYPE i.
    DATA lv_len TYPE i.
      DATA lv_lt TYPE i.
      DATA lv_gt TYPE i.
        DATA lv_next TYPE i.
    lv_pos = 0.

    lv_len = strlen( val ).
    WHILE lv_pos < lv_len.

      lv_lt = find( val = val
                          sub = `<`
                          off = lv_pos ).
      IF lv_lt < 0.
        result = result && substring( val = val
                                      off = lv_pos ).
        RETURN.
      ENDIF.

      lv_gt = find( val = val
                          sub = `>`
                          off = lv_lt ).
      IF lv_gt < 0.
        result = result && substring( val = val
                                      off = lv_pos ).
        RETURN.
      ENDIF.
      " the reference's <[^<>]*>: a tag holds no `<`, so it starts at the
      " last `<` before its `>` - what stands in front of that is text
      DO.

        lv_next = find( val = val
                              sub = `<`
                              off = lv_lt + 1 ).
        IF lv_next < 0 OR lv_next > lv_gt.
          EXIT.
        ENDIF.
        lv_lt = lv_next.
      ENDDO.
      result = result && substring( val = val
                                    off = lv_pos
                                    len = lv_lt - lv_pos ) && ` `.
      lv_pos = lv_gt + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD starts_sap.

    DATA temp16 TYPE xsdboolean.
    temp16 = boolc( strlen( ns ) >= 4 AND ns(4) = `sap.` ).
    result = temp16.

  ENDMETHOD.

  METHOD ends_with.

    DATA lv_len TYPE i.
    DATA temp17 TYPE xsdboolean.
    lv_len = strlen( val ) - strlen( suffix ).
    IF lv_len < 0.
      RETURN.
    ENDIF.

    temp17 = boolc( substring( val = val off = lv_len ) = suffix ).
    result = temp17.

  ENDMETHOD.

  METHOD set_policy.

    DATA lr_action TYPE REF TO z2ui5_cl_agent_snapshot=>ty_s_action.
    READ TABLE mt_action REFERENCE INTO lr_action WITH KEY id = id. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      lr_action->policy = policy.
    ENDIF.

  ENDMETHOD.

  METHOD get_json.

    DATA lt_part TYPE string_table.
    DATA lt_item TYPE string_table.
    DATA lt_sub TYPE string_table.

    " fields
    DATA ls_field LIKE LINE OF mt_field.
      DATA temp247 TYPE string.
      DATA temp73 TYPE string.
      DATA lv_field TYPE string.
        DATA ls_choice LIKE LINE OF ls_field-t_value.
          DATA temp248 LIKE LINE OF lt_sub.
    DATA lv_fields TYPE string.
    DATA ls_action LIKE LINE OF mt_action.
      DATA temp249 TYPE string.
      DATA lv_action TYPE string.
      DATA temp250 LIKE LINE OF lt_item.
    DATA lv_actions TYPE string.
    DATA ls_table LIKE LINE OF mt_table.
      DATA ls_column LIKE LINE OF ls_table-t_column.
        DATA temp251 LIKE LINE OF lt_sub.
      DATA lv_columns TYPE string.
      DATA ls_row LIKE LINE OF ls_table-t_row.
        DATA ls_cell LIKE LINE OF ls_row-t_cell.
          DATA temp252 LIKE LINE OF lt_part.
        DATA temp253 LIKE LINE OF lt_sub.
      DATA lv_rows TYPE string.
      DATA lv_editable LIKE LINE OF ls_table-t_editable.
      DATA temp254 TYPE string.
      DATA lv_table TYPE string.
      DATA temp255 LIKE LINE OF lt_item.
    DATA lv_tables TYPE string.
    DATA ls_message LIKE LINE OF mt_message.
      DATA lv_message TYPE string.
      DATA temp256 LIKE LINE OF lt_item.
    DATA lv_messages TYPE string.
    DATA lv_text LIKE LINE OF mt_text.
    DATA lv_texts TYPE string.
    DATA lv_unsupported LIKE LINE OF mt_unsupported.
    DATA lv_unsupported_json TYPE string.
      DATA lv_pending LIKE LINE OF mt_pending.
    LOOP AT mt_field INTO ls_field.

      IF ls_field-required = abap_true.
        temp247 = `true`.
      ELSE.
        temp247 = `false`.
      ENDIF.

      IF ls_field-editable = abap_true.
        temp73 = `true`.
      ELSE.
        temp73 = `false`.
      ENDIF.

      lv_field = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-id ) }| &&
                       |,"path":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-path ) }| &&
                       |,"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-name ) }| &&
                       |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-label ) }| &&
                       |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-control ) }| &&
                       |,"kind":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-kind ) }| &&
                       |,"value":{ z2ui5_cl_agent_viewxml=>val_to_json( ls_field-value ) }| &&
                       |,"required":{ temp247 }| &&
                       |,"editable":{ temp73 }|.
      IF ls_field-has_values = abap_true.
        CLEAR lt_sub.

        LOOP AT ls_field-t_value INTO ls_choice.

          temp248 = |\{"key":{ z2ui5_cl_agent_viewxml=>val_to_json( ls_choice-key ) },"text":{ z2ui5_cl_agent_viewxml=>json_string( ls_choice-text ) }\}|.
          INSERT temp248
                 INTO TABLE lt_sub.
        ENDLOOP.
        lv_field = |{ lv_field },"values":[{ concat_lines_of( table = lt_sub
                                                              sep   = `,` ) }]|.
      ENDIF.
      lv_field = |{ lv_field },"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_field-layer ) }\}|.
      INSERT lv_field INTO TABLE lt_item.
    ENDLOOP.

    lv_fields = concat_lines_of( table = lt_item
                                       sep   = `,` ).

    " actions
    CLEAR lt_item.

    LOOP AT mt_action INTO ls_action.

      IF ls_action-enabled = abap_true.
        temp249 = `true`.
      ELSE.
        temp249 = `false`.
      ENDIF.

      lv_action = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-id ) }| &&
                        |,"event":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-event ) }| &&
                        |,"args":[{ concat_lines_of( table = ls_action-t_arg_json
                                                     sep   = `,` ) }]| &&
                        |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-label ) }| &&
                        |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-control ) }| &&
                        |,"trigger":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-trigger ) }| &&
                        |,"enabled":{ temp249 }| &&
                        |,"scope":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-scope ) }|.
      IF ls_action-scope = `row`.
        lv_action = |{ lv_action },"table":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-table ) }|.
      ENDIF.
      lv_action = |{ lv_action },"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-layer ) }|.
      IF ls_action-policy IS NOT INITIAL AND ls_action-policy <> `allowed`.
        lv_action = |{ lv_action },"policy":{ z2ui5_cl_agent_viewxml=>json_string( ls_action-policy ) }|.
      ENDIF.

      temp250 = |{ lv_action }\}|.
      INSERT temp250 INTO TABLE lt_item.
    ENDLOOP.

    lv_actions = concat_lines_of( table = lt_item
                                        sep   = `,` ).

    " tables
    CLEAR lt_item.

    LOOP AT mt_table INTO ls_table.
      CLEAR lt_sub.

      LOOP AT ls_table-t_column INTO ls_column.

        temp251 = |\{"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_column-name ) },"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_column-label ) }\}|.
        INSERT temp251
               INTO TABLE lt_sub.
      ENDLOOP.

      lv_columns = concat_lines_of( table = lt_sub
                                          sep   = `,` ).
      CLEAR lt_sub.

      LOOP AT ls_table-t_row INTO ls_row.
        CLEAR lt_part.

        LOOP AT ls_row-t_cell INTO ls_cell.

          temp252 = |{ z2ui5_cl_agent_viewxml=>json_string( ls_cell-name ) }:{ z2ui5_cl_agent_viewxml=>val_to_json( ls_cell-val ) }|.
          INSERT temp252
                 INTO TABLE lt_part.
        ENDLOOP.

        temp253 = |\{{ concat_lines_of( table = lt_part sep = `,` ) }\}|.
        INSERT temp253 INTO TABLE lt_sub.
      ENDLOOP.

      lv_rows = concat_lines_of( table = lt_sub
                                       sep   = `,` ).
      CLEAR lt_sub.

      LOOP AT ls_table-t_editable INTO lv_editable.
        INSERT z2ui5_cl_agent_viewxml=>json_string( lv_editable ) INTO TABLE lt_sub.
      ENDLOOP.

      IF ls_table-truncated = abap_true.
        temp254 = `true`.
      ELSE.
        temp254 = `false`.
      ENDIF.

      lv_table = |\{"id":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-id ) }| &&
                       |,"path":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-path ) }| &&
                       |,"name":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-name ) }| &&
                       |,"label":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-label ) }| &&
                       |,"control":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-control ) }| &&
                       |,"columns":[{ lv_columns }]| &&
                       |,"rowCount":{ ls_table-row_count }| &&
                       |,"rows":[{ lv_rows }]| &&
                       |,"truncated":{ temp254 }| &&
                       |,"selectionMode":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-selection_mode ) }| &&
                       |,"editableCells":[{ concat_lines_of( table = lt_sub
                                                             sep   = `,` ) }]| &&
                       |,"layer":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-layer ) }|.
      IF ls_table-selection_field IS NOT INITIAL.
        lv_table = |{ lv_table },"selectionField":{ z2ui5_cl_agent_viewxml=>json_string( ls_table-selection_field ) }|.
      ENDIF.

      temp255 = |{ lv_table }\}|.
      INSERT temp255 INTO TABLE lt_item.
    ENDLOOP.

    lv_tables = concat_lines_of( table = lt_item
                                       sep   = `,` ).

    " messages
    CLEAR lt_item.

    LOOP AT mt_message INTO ls_message.

      lv_message = |\{"type":{ z2ui5_cl_agent_viewxml=>json_string( ls_message-type ) }| &&
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

      temp256 = |{ lv_message }\}|.
      INSERT temp256 INTO TABLE lt_item.
    ENDLOOP.

    lv_messages = concat_lines_of( table = lt_item
                                         sep   = `,` ).

    CLEAR lt_item.

    LOOP AT mt_text INTO lv_text.
      INSERT z2ui5_cl_agent_viewxml=>json_string( lv_text ) INTO TABLE lt_item.
    ENDLOOP.

    lv_texts = concat_lines_of( table = lt_item
                                      sep   = `,` ).

    CLEAR lt_item.

    LOOP AT mt_unsupported INTO lv_unsupported.
      INSERT z2ui5_cl_agent_viewxml=>json_string( lv_unsupported ) INTO TABLE lt_item.
    ENDLOOP.

    lv_unsupported_json = concat_lines_of( table = lt_item
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

      LOOP AT mt_pending INTO lv_pending.
        INSERT z2ui5_cl_agent_viewxml=>json_string( lv_pending ) INTO TABLE lt_item.
      ENDLOOP.
      result = |{ result },"pending":[{ concat_lines_of( table = lt_item
                                                         sep   = `,` ) }]|.
    ENDIF.
    result = |{ result }\}|.

  ENDMETHOD.

ENDCLASS.
