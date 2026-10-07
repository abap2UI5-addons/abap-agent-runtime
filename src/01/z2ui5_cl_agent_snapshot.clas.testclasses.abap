"! The snapshot builder on recorded real sessions: the view XML and model of
"! abap2UI5/samples apps as abap2UI5/mcp-server recorded them
"! (test/fixtures/agent), folded the way the frontend folds them. Each case
"! asserts the parts its reference test names - and the WHOLE snapshot
"! against the reference implementation's output (lib/snapshot.mjs), byte
"! for byte: the shape is a contract shared with the Node MCP server and the
"! VS Code extension.
CLASS ltcl_snapshot DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    METHODS form_381     FOR TESTING.
    METHODS table_011    FOR TESTING.
    METHODS list_048     FOR TESTING.
    METHODS popup_009    FOR TESTING.
    METHODS popup_012    FOR TESTING.
    METHODS messages_467 FOR TESTING.
    METHODS pending      FOR TESTING.
    METHODS select_623      FOR TESTING.
    METHODS cgui_f4_06      FOR TESTING.
    METHODS messages_452    FOR TESTING.
    METHODS cgui_popover_07 FOR TESTING.
    METHODS message_lists   FOR TESTING.
    METHODS select_dialogs  FOR TESTING.
    METHODS secret_path     FOR TESTING.
    METHODS named_model_key FOR TESTING.
    METHODS text_sources    FOR TESTING.

    METHODS synthetic
      IMPORTING
        xml           TYPE string
        model         TYPE string
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_agent_snapshot.

    METHODS field_by_label
      IMPORTING
        io_snap       TYPE REF TO z2ui5_cl_agent_snapshot
        label         TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_field.

    METHODS action_by_event
      IMPORTING
        io_snap       TYPE REF TO z2ui5_cl_agent_snapshot
        event         TYPE string
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_action.

    METHODS input_form_381
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_form_381
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_table_011
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_table_011
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_list_048
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_list_048
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_popup_009
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_popup_009
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_popup_012
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_popup_012
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_messages_467
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_messages_467
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_select_623
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_select_623
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_cgui_f4_06
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_cgui_f4_06
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_messages_452
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_messages_452
      RETURNING
        VALUE(result) TYPE string.
    METHODS input_cgui_popover_07
      RETURNING
        VALUE(result) TYPE z2ui5_cl_agent_snapshot=>ty_s_input.
    METHODS expected_cgui_popover_07
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS ltcl_snapshot IMPLEMENTATION.

  METHOD field_by_label.

    READ TABLE io_snap->mt_field INTO result WITH KEY label = label. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_subrc( msg = |no field labelled { label }| ).

  ENDMETHOD.

  METHOD action_by_event.

    READ TABLE io_snap->mt_action INTO result WITH KEY event = event. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_subrc( msg = |no action { event }| ).

  ENDMETHOD.

  METHOD form_381.

    " inputs, a number input, selects with static items, checkboxes, labels from the SimpleForm
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_form_381( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_form_381( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `abap2UI5 - Message - MessageToast via the Global Object`
                                        act = lo_snap->mv_title ).
    DATA(ls_field) = field_by_label( io_snap = lo_snap
                                     label   = `Message` ).
    cl_abap_unit_assert=>assert_equals( exp = `f1`
                                        act = ls_field-id ).
    cl_abap_unit_assert=>assert_equals( exp = `/MESSAGE`
                                        act = ls_field-path ).
    cl_abap_unit_assert=>assert_equals( exp = `This is a message toast.`
                                        act = ls_field-value-str ).
    cl_abap_unit_assert=>assert_equals( exp = `number`
                                        act = field_by_label( io_snap = lo_snap
                                                              label   = `Duration (ms)` )-kind ).
    ls_field = field_by_label( io_snap = lo_snap
                               label   = `my` ).
    cl_abap_unit_assert=>assert_equals( exp = `choice`
                                        act = ls_field-kind ).
    cl_abap_unit_assert=>assert_equals( exp = 15
                                        act = lines( ls_field-t_value ) ).
    " the nav button is hidden (showNavButton false): no Back action
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_snap->mt_action ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Show Message Toast`
                                        act = action_by_event( io_snap = lo_snap
                                                               event   = `SHOW` )-label ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lo_snap->mt_text[ table_line = `the onclose event: no toast closed yet` ] ) ) ). "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_equals( exp = `strip`
                                        act = lo_snap->mt_message[ 1 ]-source ).

  ENDMETHOD.

  METHOD table_011.

    " columns from the headers, selection bound to SELKZ, editable cells follow the row data
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_table_011( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_table_011( )
                                        act = lo_snap->get_json( ) ).

    DATA(ls_table) = lo_snap->mt_table[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `/T_TAB`
                                        act = ls_table-path ).
    cl_abap_unit_assert=>assert_equals( exp = 6
                                        act = ls_table-row_count ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ls_table-t_row ) ).
    cl_abap_unit_assert=>assert_true( ls_table-truncated ).
    cl_abap_unit_assert=>assert_equals( exp = `Multi`
                                        act = ls_table-selection_mode ).
    cl_abap_unit_assert=>assert_equals( exp = `SELKZ`
                                        act = ls_table-selection_field ).
    " enabled="{EDITABLE}" is false in every row
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SELKZ` ) )
                                        act = ls_table-t_editable ).
    cl_abap_unit_assert=>assert_false( lo_snap->cell_editable( table_id = `t1`
                                                               column   = `TITLE`
                                                               row      = 0 ) ).

  ENDMETHOD.

  METHOD list_048.

    " template wires are row scope with $row arguments
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_list_048( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_list_048( )
                                        act = lo_snap->get_json( ) ).

    DATA(ls_edit) = action_by_event( io_snap = lo_snap
                                     event   = `EDIT` ).
    cl_abap_unit_assert=>assert_equals( exp = `row`
                                        act = ls_edit-scope ).
    cl_abap_unit_assert=>assert_equals( exp = `t1`
                                        act = ls_edit-table ).
    cl_abap_unit_assert=>assert_equals( exp = `row detailPress (Detail)`
                                        act = ls_edit-label ).
    cl_abap_unit_assert=>assert_equals( exp = `"$row:TITLE"`
                                        act = ls_edit-t_arg_json[ 1 ] ).
    " a row event on the list itself
    cl_abap_unit_assert=>assert_equals( exp = `row`
                                        act = action_by_event( io_snap = lo_snap
                                                               event   = `SELCHANGE` )-scope ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.List`
                                        act = lo_snap->mt_table[ 1 ]-control ).
    " the row value an argument reads
    cl_abap_unit_assert=>assert_equals( exp = lo_snap->mt_table[ 1 ]-t_row[ 2 ]-t_cell[ 1 ]-val-str
                                        act = lo_snap->model_value( model_key = `MAIN`
                                                                    path      = `TITLE`
                                                                    table_id  = `t1`
                                                                    row       = 1 )-str ).

  ENDMETHOD.

  METHOD popup_009.

    " only the popup layer is actionable, its table selection is a cell
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_popup_009( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_popup_009( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->mv_layer ).
    cl_abap_unit_assert=>assert_equals( exp = `abap2UI5 - Value Help`
                                        act = lo_snap->mv_title ).
    cl_abap_unit_assert=>assert_initial( lo_snap->mt_field ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_snap->mt_action ) ).
    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->mt_action[ 1 ]-layer ).
    cl_abap_unit_assert=>assert_equals( exp = `Single`
                                        act = lo_snap->mt_table[ 1 ]-selection_mode ).
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = lo_snap->mt_table[ 1 ]-model_key ).

  ENDMETHOD.

  METHOD popup_012.

    " the eF close wire is the @CLOSE_POPUP action
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_popup_012( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_popup_012( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->mv_layer ).
    cl_abap_unit_assert=>assert_equals( exp = z2ui5_cl_agent_snapshot=>cs_frontend_event-popup
                                        act = lo_snap->mt_action[ 1 ]-event ).
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = lo_snap->mt_action[ 1 ]-frontend ).
    cl_abap_unit_assert=>assert_initial( lo_snap->mt_unsupported ).

  ENDMETHOD.

  METHOD messages_467.

    " the MessageManager table targets its field, typed bindings refine the kind
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_messages_467( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_messages_467( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `number`
                                        act = field_by_label( io_snap = lo_snap
                                                              label   = `Amount (integer only - validation collected automatically)` )-kind ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lo_snap->mt_message[ source = `field` field = `f1` type = `error` ] ) ) ). "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lo_snap->mt_message[ source = `model` type = `info` ] ) ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD pending.

    " a pending value is what the client shows, and is listed
    DATA(ls_input) = input_form_381( ).
    ls_input-t_pending = VALUE #( ( model_key = `MAIN`
                                    path      = `/MESSAGE`
                                    val       = z2ui5_cl_agent_viewxml=>val_string( `typed` ) ) ).
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( ls_input ).
    cl_abap_unit_assert=>assert_equals( exp = `typed`
                                        act = lo_snap->mt_field[ 1 ]-value-str ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"pending":["/MESSAGE"]}`
                                         act = lo_snap->get_json( ) ).

  ENDMETHOD.

  METHOD select_623.

    " a SelectDialog value help (samples-controls 623, after a search): its
    " items are a table, confirm is the row pick, search a screen action
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_select_623( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_select_623( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `popup`
                                        act = lo_snap->mv_layer ).
    cl_abap_unit_assert=>assert_equals( exp = `Products`
                                        act = lo_snap->mv_title ).
    DATA(ls_table) = lo_snap->mt_table[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.SelectDialog`
                                        act = ls_table-control ).
    cl_abap_unit_assert=>assert_equals( exp = `Single`
                                        act = ls_table-selection_mode ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = ls_table-row_count ).
    DATA(ls_confirm) = action_by_event( io_snap = lo_snap
                                        event   = `VH_CONFIRM` ).
    cl_abap_unit_assert=>assert_equals( exp = `row`
                                        act = ls_confirm-scope ).
    cl_abap_unit_assert=>assert_equals( exp = `t1`
                                        act = ls_confirm-table ).
    cl_abap_unit_assert=>assert_true( ls_confirm-pick ).
    cl_abap_unit_assert=>assert_equals( exp = `Products: confirm`
                                        act = ls_confirm-label ).
    cl_abap_unit_assert=>assert_equals( exp = `screen`
                                        act = action_by_event( io_snap = lo_snap
                                                               event   = `VH_SEARCH` )-scope ).
    " getTitle( ) of the picked item: the template's title in the row
    cl_abap_unit_assert=>assert_equals( exp = `Notebook Professional 17`
                                        act = lo_snap->template_value( table_id = `t1`
                                                                       node     = ls_table-template
                                                                       prop     = `title`
                                                                       row      = 1 )-str ).

  ENDMETHOD.

  METHOD cgui_f4_06.

    " a TableSelectDialog (abap-cloud-gui F4 through the popups addon):
    " cells and column headers, ZZSELKZ the selection field, the rows of a
    " data reference (/MR_TAB_POPUP/*)
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_cgui_f4_06( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_cgui_f4_06( )
                                        act = lo_snap->get_json( ) ).

    DATA(ls_table) = lo_snap->mt_table[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.TableSelectDialog`
                                        act = ls_table-control ).
    cl_abap_unit_assert=>assert_equals( exp = `/MR_TAB_POPUP/*`
                                        act = ls_table-path ).
    cl_abap_unit_assert=>assert_equals( exp = `ZZSELKZ`
                                        act = ls_table-selection_field ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( ls_table-t_cellnode ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Single Select`
                                        act = lo_snap->mv_title ).
    cl_abap_unit_assert=>assert_true( action_by_event( io_snap = lo_snap
                                                       event   = `CONFIRM` )-pick ).

  ENDMETHOD.

  METHOD messages_452.

    " MessageView items are messages (samples 452): type, title, subtitle,
    " description - an empty subtitle is left out, nothing repeated as text
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_messages_452( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_messages_452( )
                                        act = lo_snap->get_json( ) ).

    DATA(lv_view) = 0.
    LOOP AT lo_snap->mt_message INTO DATA(ls_message) WHERE source = `messageview`. "#EC CI_SORTSEQ
      lv_view = lv_view + 1.
      cl_abap_unit_assert=>assert_true( xsdbool( strlen( ls_message-description ) <= 1000 ) ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( exp = 11
                                        act = lv_view ).
    ls_message = lo_snap->mt_message[ 2 ].
    cl_abap_unit_assert=>assert_equals( exp = `Account 801 requires an assignment`
                                        act = ls_message-text ).
    cl_abap_unit_assert=>assert_equals( exp = `Role is invalid`
                                        act = ls_message-subtitle ).
    cl_abap_unit_assert=>assert_initial( lo_snap->mt_message[ 4 ]-subtitle ).

  ENDMETHOD.

  METHOD cgui_popover_07.

    " a MessagePopover in dependents (abap-cloud-gui): the run's messages,
    " while the popover itself opens in the browser only
    DATA(lo_snap) = z2ui5_cl_agent_snapshot=>create( input_cgui_popover_07( ) ).
    cl_abap_unit_assert=>assert_equals( exp = expected_cgui_popover_07( )
                                        act = lo_snap->get_json( ) ).

    cl_abap_unit_assert=>assert_equals( exp = `Number 42 is a warning`
                                        act = lo_snap->mt_message[ source = `popover` ]-text ). "#EC CI_SORTSEQ
    DATA(ls_focus) = action_by_event( io_snap = lo_snap
                                      event   = `CGUI_MESSAGE_FOCUS` ).
    cl_abap_unit_assert=>assert_equals( exp = `activeTitlePress`
                                        act = ls_focus-trigger ).
    cl_abap_unit_assert=>assert_equals( exp = `sap.m.MessagePopover`
                                        act = ls_focus-control ).

  ENDMETHOD.

  METHOD synthetic.

    result = z2ui5_cl_agent_snapshot=>create( VALUE #(
        session  = `D1`
        app      = `Z_T`
        max_rows = 20
        t_layer  = VALUE #( ( layer = `MAIN`
                              xml   = |<mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc"><Page title="T">{ xml }</Page></mvc:View>|
                              model = model ) ) ) ).

  ENDMETHOD.

  METHOD message_lists.

    " static items, UI5's default type Error, None as info, markup stripped,
    " the 50-item cut, a list bound to a named model noted
    DATA(lt_row) = VALUE string_table( ).
    DO 52 TIMES.
      INSERT |\{"T":"m{ sy-index - 1 }"\}| INTO TABLE lt_row.
    ENDDO.
    DATA(lo_snap) = synthetic(
        xml   = `<MessagePopover><items><MessageItem title="no type"/><MessageItem type="None" title="none"/>` &&
                `<MessageItem type="Success" title="ok" description="&lt;b&gt;bold&lt;/b&gt; text" markupDescription="true"/>` &&
                `<MessageItem type="Warning"/></items></MessagePopover>` &&
                `<MessageView items="{/T_M}"><MessageItem type="Information" title="{T}"/></MessageView>` &&
                `<MessageView items="{message>/}"><MessageItem title="{message}"/></MessageView>`
        model = |\{"T_M":[{ concat_lines_of( table = lt_row
                                              sep   = `,` ) }]\}| ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"messages":[{"type":"error","text":"no type","source":"popover"},` &&
                                               `{"type":"info","text":"none","source":"popover"},` &&
                                               `{"type":"success","text":"ok","source":"popover","description":"bold text"},` &&
                                               `{"type":"info","text":"m0","source":"messageview"},*`
                                         act = lo_snap->get_json( ) ).
    DATA(lv_view) = 0.
    LOOP AT lo_snap->mt_message TRANSPORTING NO FIELDS WHERE source = `messageview`. "#EC CI_SORTSEQ
      lv_view = lv_view + 1.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( exp = 50
                                        act = lv_view ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lo_snap->mt_unsupported[ table_line = `MessageView (main): 52 messages, the first 50 listed` ] ) ) ). "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
        lo_snap->mt_unsupported[ table_line = `MessageView bound to the named model 'message' (main) - messages not described` ] ) ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD secret_path.

    " a second field on the path of a password input shows the password
    DATA(lo_snap) = synthetic( xml   = `<Input type="Password" value="{/PW}"/><Input value="{/PW}" editable="false"/>` &&
                                       `<Input value="{/NAME}"/>`
                               model = `{"PW":"secret","NAME":"Ann"}` ).
    cl_abap_unit_assert=>assert_equals( exp = 3
                                        act = lines( lo_snap->mt_field ) ).
    cl_abap_unit_assert=>assert_true( lo_snap->is_secret( `f1` ) ).
    cl_abap_unit_assert=>assert_true( lo_snap->is_secret( `f2` ) ).
    cl_abap_unit_assert=>assert_false( lo_snap->is_secret( `f3` ) ).

  ENDMETHOD.

  METHOD text_sources.

    " a text keeps the paths it was read from, beside the JSON - the
    " copilot masks "IBAN: DE89..." by them; a literal text keeps none
    DATA(lo_snap) = synthetic( xml   = `<ObjectAttribute title="IBAN" text="{/IBAN}"/>` &&
                                       `<Text text="{/NAME} ({/CITY})"/><Text text="plain"/>`
                               model = `{"IBAN":"DE89370400440532013000","NAME":"Ann","CITY":"Bonn"}` ).
    DATA(lt_source) = lo_snap->mt_text_source.
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( lt_source ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*DE89370400440532013000*`
                                         act = lt_source[ 1 ]-text ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `/IBAN` ) )
                                        act = lt_source[ 1 ]-t_path ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `/NAME` ) ( `/CITY` ) )
                                        act = lt_source[ 2 ]-t_path ).
    " and the JSON - the contract - is unchanged by it
    cl_abap_unit_assert=>assert_equals( exp = -1
                                        act = find( val = lo_snap->get_json( )
                                                    sub = `t_path` ) ).

  ENDMETHOD.

  METHOD named_model_key.

    " bound to another model by the object syntax's model: neither a field
    " nor an editable table of the default model, where a value would land
    DATA(lo_snap) = synthetic( xml   = `<Input value="{path:'/A', model:'other'}"/>` &&
                                       `<Table items="{path:'/T', model:'other'}"><columns><Column><Text text="N"/></Column></columns>` &&
                                       `<items><ColumnListItem><cells><Input value="{N}"/></cells></ColumnListItem></items></Table>`
                               model = `{"A":"a","T":[{"N":1}]}` ).
    cl_abap_unit_assert=>assert_initial( lo_snap->mt_field ).
    cl_abap_unit_assert=>assert_initial( lo_snap->mt_table ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*field Input bound to the named model 'other'*`
                                         act = lo_snap->get_json( ) ).

  ENDMETHOD.

  METHOD select_dialogs.

    " multiSelect is Multi, a bound selected the selectionField, confirm a
    " row action (the pick), cancel a screen action; on the page, the page
    " titles the layer
    DATA(lo_snap) = synthetic(
        xml   = `<TableSelectDialog title="Pick" multiSelect="true" items="{/T}" ` &&
                `confirm=".eB(['OK'], ${$parameters>/selectedContexts/0/sPath})" cancel=".eB(['NO'])">` &&
                `<ColumnListItem selected="{SEL}"><cells><Text text="{A}"/><ObjectIdentifier title="{B}"/></cells></ColumnListItem>` &&
                `<columns><Column><header><Text text="Col A"/></header></Column><Column><header><Text text="Col B"/></header></Column></columns>` &&
                `</TableSelectDialog>`
        model = `{"T":[{"A":"a1","B":"b1","SEL":false},{"A":"a2","B":"b2","SEL":true}]}` ).
    DATA(ls_table) = lo_snap->mt_table[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `Multi`
                                        act = ls_table-selection_mode ).
    cl_abap_unit_assert=>assert_equals( exp = `SEL`
                                        act = ls_table-selection_field ).
    cl_abap_unit_assert=>assert_equals( exp = `Pick`
                                        act = ls_table-label ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SEL` ) )
                                        act = ls_table-t_editable ).
    cl_abap_unit_assert=>assert_equals( exp = `Col A`
                                        act = ls_table-t_column[ 1 ]-label ).
    DATA(ls_ok) = action_by_event( io_snap = lo_snap
                                   event   = `OK` ).
    cl_abap_unit_assert=>assert_equals( exp = `row`
                                        act = ls_ok-scope ).
    cl_abap_unit_assert=>assert_equals( exp = `Pick: confirm`
                                        act = ls_ok-label ).
    cl_abap_unit_assert=>assert_true( ls_ok-pick ).
    cl_abap_unit_assert=>assert_equals( exp = `screen`
                                        act = action_by_event( io_snap = lo_snap
                                                               event   = `NO` )-scope ).
    cl_abap_unit_assert=>assert_equals( exp = `T`
                                        act = lo_snap->mv_title ).

  ENDMETHOD.

  METHOD input_form_381.

    " form-381#1/rows20: form-381#1/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `27AE5ED0967341D6AD1D4677521E89E6`.
    result-app = `Z2UI5_CL_SMP_APP_381`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:core="sap.ui.core"` &&
                              ` xmlns:form="sap.ui.layout.form"><Shell><Page title="abap2UI5 - Message - MessageToast via the Global Object" ` &&
                              `showNavButton="false" navButtonPress=".eB(['___ZZZ_NAL'])"><MessageStrip text="Two ways to a toast, and this i` &&
                              `s the UI5 one: follow_up_action( cs_event-control_global ) calls sap.m.MessageToast.show( ) itself, and its la` &&
                              `st argument is the option object of that API 1:1 - position, collision, animation, autoClose. Configure them b` &&
                              `elow and watch the object travel. The other way is client-&gt;message_toast_display( ), which carries no UI5 o` &&
                              `ption at all: it carries what an ABAP app decides, and Z2UI5_CL_SMP_APP_502 shows that side for the message bo` &&
                              `x." type="Information" showIcon="true" class="sapUiSmallMargin"/><core:HTML content="&lt;style&gt;.myToast \{ ` &&
                              `background-color: #0a6ed1; color: #fff; \}&lt;/style&gt;&lt;div id=&quot;toastAnchor&quot; class=&quot;sapUiSm` &&
                              `allMargin&quot; style=&quot;border: 2px dashed #0a6ed1; padding: 0.5rem; width: 14rem;&quot;&gt;the anchor box` &&
                              ` (id toastAnchor)&lt;/div&gt;"/><headerContent><Link text="UI5 Demo Kit" target="_blank" href="https://sdk.ope` &&
                              `nui5.org/entity/sap.m.MessageToast/sample/sap.m.sample.MessageToast"/></headerContent><Panel headerText="Messa` &&
                              `ge Toast Configuration"><form:SimpleForm title="Settings" editable="true"><form:content><Label text="Message"/` &&
                              `><Input value="{/MESSAGE}"/><Label text="Duration (ms)"/><Input type="Number" value="{/DURATION}"/><Label text` &&
                              `="Width"/><Input value="{/WIDTH}"/><Label text="my"/><Select selectedKey="{/MY}"><core:Item key="begin top" te` &&
                              `xt="begin top"/><core:Item key="begin center" text="begin center"/><core:Item key="begin bottom" text="begin b` &&
                              `ottom"/><core:Item key="left top" text="left top"/><core:Item key="left center" text="left center"/><core:Item` &&
                              ` key="left bottom" text="left bottom"/><core:Item key="center top" text="center top"/><core:Item key="center c` &&
                              `enter" text="center center"/><core:Item key="center bottom" text="center bottom"/><core:Item key="right top" t` &&
                              `ext="right top"/><core:Item key="right center" text="right center"/><core:Item key="right bottom" text="right ` &&
                              `bottom"/><core:Item key="end top" text="end top"/><core:Item key="end center" text="end center"/><core:Item ke` &&
                              `y="end bottom" text="end bottom"/></Select><Label text="at"/><Select selectedKey="{/AT}"><core:Item key="begin` &&
                              ` top" text="begin top"/><core:Item key="begin center" text="begin center"/><core:Item key="begin bottom" text=` &&
                              `"begin bottom"/><core:Item key="left top" text="left top"/><core:Item key="left center" text="left center"/><c` &&
                              `ore:Item key="left bottom" text="left bottom"/><core:Item key="center top" text="center top"/><core:Item key="` &&
                              `center center" text="center center"/><core:Item key="center bottom" text="center bottom"/><core:Item key="righ` &&
                              `t top" text="right top"/><core:Item key="right center" text="right center"/><core:Item key="right bottom" text` &&
                              `="right bottom"/><core:Item key="end top" text="end top"/><core:Item key="end center" text="end center"/><core` &&
                              `:Item key="end bottom" text="end bottom"/></Select><Label text="of - dock to the anchor box instead of the win` &&
                              `dow"/><CheckBox selected="{/DOCK_TO_ANCHOR}"/><Label text="offset"/><Input value="{/OFFSET}"/><Label text="col` &&
                              `lision"/><Select selectedKey="{/COLLISION}"><core:Item key="fit fit" text="fit fit - shift into the viewport"/` &&
                              `><core:Item key="flip flip" text="flip flip - flip to the opposite side"/><core:Item key="flipfit flipfit" tex` &&
                              `t="flipfit flipfit - flip first, then shift"/><core:Item key="none none" text="none none - stay where told"/><` &&
                              `/Select><Label text="animationTimingFunction"/><Select selectedKey="{/ANIMATION_TIMING}"><core:Item key="ease"` &&
                              ` text="ease"/><core:Item key="linear" text="linear"/><core:Item key="ease-in" text="ease-in"/><core:Item key="` &&
                              `ease-out" text="ease-out"/><core:Item key="ease-in-out" text="ease-in-out"/></Select><Label text="animationDur` &&
                              `ation (ms)"/><Input type="Number" value="{/ANIMATION_DURATION}"/><Label text="autoClose"/><CheckBox selected="` &&
                              `{/AUTOCLOSE}"/><Label text="closeOnBrowserNavigation"/><CheckBox selected="{/CLOSE_ON_NAVIGATION}"/><Label tex` &&
                              `t="onclose - report the closing as a backend event"/><CheckBox selected="{/NOTIFY_CLOSE}"/><Label text="class ` &&
                              `- a CSS class for the toast (myToast is styled above)"/><Input value="{/CSS_CLASS}"/><Button press=".eB(['SHOW` &&
                              `'])" text="Show Message Toast" type="Emphasized"/><Label text="the onclose event"/><Text text="{/CLOSED_TEXT}"` &&
                              `/><Label text="wired, no round-trip - the text is composed on the client"/><Button text="Compose on the client` &&
                              `" press=".eF('CONTROL_GLOBAL', 'MESSAGE_TOAST', 'show', '{0} - composed on the client, the backend never saw t` &&
                              `his press', ${$source&gt;/text})"/></form:content></form:SimpleForm></Panel></Page></Shell></mvc:View>`
                      model = `{"ANIMATION_DURATION":"1000","ANIMATION_TIMING":"ease","AT":"center bottom","AUTOCLOSE":true,"CLOSED_TEXT":"no` &&
                              ` toast closed yet","CLOSE_ON_NAVIGATION":true,"COLLISION":"fit fit","CSS_CLASS":"myToast","DOCK_TO_ANCHOR":fal` &&
                              `se,"DURATION":"3000","MESSAGE":"This is a message toast.","MY":"center bottom","NOTIFY_CLOSE":true,"OFFSET":"0` &&
                              ` 0","WIDTH":"15em"}` ) ).

  ENDMETHOD.

  METHOD expected_form_381.

    result = `{"snapshotVersion":1,"session":"27AE5ED0967341D6AD1D4677521E89E6","app":"Z2UI5_CL_SMP_APP_381","title":"abap2U` &&
             `I5 - Message - MessageToast via the Global Object","layer":"main","fields":[{"id":"f1","path":"/MESSAGE","name` &&
             `":"MESSAGE","label":"Message","control":"sap.m.Input","kind":"text","value":"This is a message toast.","requir` &&
             `ed":false,"editable":true,"layer":"main"},{"id":"f2","path":"/DURATION","name":"DURATION","label":"Duration (m` &&
             `s)","control":"sap.m.Input","kind":"number","value":"3000","required":false,"editable":true,"layer":"main"},{"` &&
             `id":"f3","path":"/WIDTH","name":"WIDTH","label":"Width","control":"sap.m.Input","kind":"text","value":"15em","` &&
             `required":false,"editable":true,"layer":"main"},{"id":"f4","path":"/MY","name":"MY","label":"my","control":"sa` &&
             `p.m.Select","kind":"choice","value":"center bottom","required":false,"editable":true,"values":[{"key":"begin t` &&
             `op","text":"begin top"},{"key":"begin center","text":"begin center"},{"key":"begin bottom","text":"begin botto` &&
             `m"},{"key":"left top","text":"left top"},{"key":"left center","text":"left center"},{"key":"left bottom","text` &&
             `":"left bottom"},{"key":"center top","text":"center top"},{"key":"center center","text":"center center"},{"key` &&
             `":"center bottom","text":"center bottom"},{"key":"right top","text":"right top"},{"key":"right center","text":` &&
             `"right center"},{"key":"right bottom","text":"right bottom"},{"key":"end top","text":"end top"},{"key":"end ce` &&
             `nter","text":"end center"},{"key":"end bottom","text":"end bottom"}],"layer":"main"},{"id":"f5","path":"/AT","` &&
             `name":"AT","label":"at","control":"sap.m.Select","kind":"choice","value":"center bottom","required":false,"edi` &&
             `table":true,"values":[{"key":"begin top","text":"begin top"},{"key":"begin center","text":"begin center"},{"ke` &&
             `y":"begin bottom","text":"begin bottom"},{"key":"left top","text":"left top"},{"key":"left center","text":"lef` &&
             `t center"},{"key":"left bottom","text":"left bottom"},{"key":"center top","text":"center top"},{"key":"center ` &&
             `center","text":"center center"},{"key":"center bottom","text":"center bottom"},{"key":"right top","text":"righ` &&
             `t top"},{"key":"right center","text":"right center"},{"key":"right bottom","text":"right bottom"},{"key":"end ` &&
             `top","text":"end top"},{"key":"end center","text":"end center"},{"key":"end bottom","text":"end bottom"}],"lay` &&
             `er":"main"},{"id":"f6","path":"/DOCK_TO_ANCHOR","name":"DOCK_TO_ANCHOR","label":"of - dock to the anchor box i` &&
             `nstead of the window","control":"sap.m.CheckBox","kind":"boolean","value":false,"required":false,"editable":tr` &&
             `ue,"layer":"main"},{"id":"f7","path":"/OFFSET","name":"OFFSET","label":"offset","control":"sap.m.Input","kind"` &&
             `:"text","value":"0 0","required":false,"editable":true,"layer":"main"},{"id":"f8","path":"/COLLISION","name":"` &&
             `COLLISION","label":"collision","control":"sap.m.Select","kind":"choice","value":"fit fit","required":false,"ed` &&
             `itable":true,"values":[{"key":"fit fit","text":"fit fit - shift into the viewport"},{"key":"flip flip","text":` &&
             `"flip flip - flip to the opposite side"},{"key":"flipfit flipfit","text":"flipfit flipfit - flip first, then s` &&
             `hift"},{"key":"none none","text":"none none - stay where told"}],"layer":"main"},{"id":"f9","path":"/ANIMATION` &&
             `_TIMING","name":"ANIMATION_TIMING","label":"animationTimingFunction","control":"sap.m.Select","kind":"choice",` &&
             `"value":"ease","required":false,"editable":true,"values":[{"key":"ease","text":"ease"},{"key":"linear","text":` &&
             `"linear"},{"key":"ease-in","text":"ease-in"},{"key":"ease-out","text":"ease-out"},{"key":"ease-in-out","text":` &&
             `"ease-in-out"}],"layer":"main"},{"id":"f10","path":"/ANIMATION_DURATION","name":"ANIMATION_DURATION","label":"` &&
             `animationDuration (ms)","control":"sap.m.Input","kind":"number","value":"1000","required":false,"editable":tru` &&
             `e,"layer":"main"},{"id":"f11","path":"/AUTOCLOSE","name":"AUTOCLOSE","label":"autoClose","control":"sap.m.Chec` &&
             `kBox","kind":"boolean","value":true,"required":false,"editable":true,"layer":"main"},{"id":"f12","path":"/CLOS` &&
             `E_ON_NAVIGATION","name":"CLOSE_ON_NAVIGATION","label":"closeOnBrowserNavigation","control":"sap.m.CheckBox","k` &&
             `ind":"boolean","value":true,"required":false,"editable":true,"layer":"main"},{"id":"f13","path":"/NOTIFY_CLOSE` &&
             `","name":"NOTIFY_CLOSE","label":"onclose - report the closing as a backend event","control":"sap.m.CheckBox","` &&
             `kind":"boolean","value":true,"required":false,"editable":true,"layer":"main"},{"id":"f14","path":"/CSS_CLASS",` &&
             `"name":"CSS_CLASS","label":"class - a CSS class for the toast (myToast is styled above)","control":"sap.m.Inpu` &&
             `t","kind":"text","value":"myToast","required":false,"editable":true,"layer":"main"}],"actions":[{"id":"a1","ev` &&
             `ent":"SHOW","args":[],"label":"Show Message Toast","control":"sap.m.Button","trigger":"press","enabled":true,"` &&
             `scope":"screen","layer":"main"}],"tables":[],"messages":[{"type":"info","text":"Two ways to a toast, and this ` &&
             `is the UI5 one: follow_up_action( cs_event-control_global ) calls sap.m.MessageToast.show( ) itself, and its l` &&
             `ast argument is the option object of that API 1:1 - position, collision, animation, autoClose. Configure them ` &&
             `below and watch the object travel. The other way is client->message_toast_display( ), which carries no UI5 opt` &&
             `ion at all: it carries what an ABAP app decides, and Z2UI5_CL_SMP_APP_502 shows that side for the message box.` &&
             `","source":"strip"}],"texts":["the onclose event: no toast closed yet"],"unsupported":["raw HTML (sap.ui.core.` &&
             `HTML, main: Shell > Page > HTML) - not described","frontend action CONTROL_GLOBAL(\"MESSAGE_TOAST\", \"show\",` &&
             ` \"{0} - composed on the client, the backend never saw this press\", $source:text) on Button \"Compose on the ` &&
             `client\" (main) - runs in the browser only"]}`.

  ENDMETHOD.

  METHOD input_table_011.

    " table-011#1/rows2: table-011#1/rows2 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `62A9FB6AB2324062B816013E727E79AF`.
    result-app = `Z2UI5_CL_SMP_APP_011`.
    result-max_rows = 2.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc"><Shell><Page title="abap` &&
                              `2UI5 - Table - Editable Cells, Add and Delete Rows" showNavButton="false" navButtonPress=".eB(['___ZZZ_NAL'])"` &&
                              ` id="test2"><MessageStrip text="A MultiSelect table whose input cells switch between display and edit mode via` &&
                              ` the toolbar, which also adds new rows and deletes the currently selected ones." type="Information" showIcon="` &&
                              `true" class="sapUiSmallMargin"/><Table items="{path: '/T_TAB', templateShareable: false}" mode="MultiSelect"><` &&
                              `headerToolbar><OverflowToolbar><Title text="title of the table"/><Button press=".eB(['BUTTON_TEST'])" text="te` &&
                              `st"/><ToolbarSpacer/><Button press=".eB(['BUTTON_DELETE'])" text="delete selected row" icon="sap-icon://delete` &&
                              `"/><Button press=".eB(['BUTTON_ADD'])" text="add" icon="sap-icon://add"/><Button press=".eB(['BUTTON_EDIT'])" ` &&
                              `text="edit" tooltip="Switch the cells between display and edit mode" icon="sap-icon://edit"/></OverflowToolbar` &&
                              `></headerToolbar><columns><Column><Text text="Title"/></Column><Column><Text text="Color"/></Column><Column><T` &&
                              `ext text="Info"/></Column><Column><Text text="Description"/></Column><Column><Text text="Checkbox"/></Column><` &&
                              `/columns><items><ColumnListItem selected="{SELKZ}"><cells><Input id="test" enabled="{EDITABLE}" value="{TITLE}` &&
                              `"/><Input enabled="{EDITABLE}" value="{VALUE}"/><Input enabled="{EDITABLE}" value="{INFO}"/><Input enabled="{E` &&
                              `DITABLE}" value="{DESCR}"/><CheckBox selected="{CHECKBOX}" enabled="{EDITABLE}"/></cells></ColumnListItem></it` &&
                              `ems></Table></Page></Shell></mvc:View>`
                      model = `{"T_TAB":[{"CHECKBOX":true,"DESCR":"this is a description","EDITABLE":false,"ICON":"","INFO":"completed","SELK` &&
                              `Z":false,"TITLE":"entry 01","VALUE":"red"},{"CHECKBOX":true,"DESCR":"this is a description","EDITABLE":false,"` &&
                              `ICON":"","INFO":"completed","SELKZ":false,"TITLE":"entry 02","VALUE":"blue"},{"CHECKBOX":true,"DESCR":"this is` &&
                              ` a description","EDITABLE":false,"ICON":"","INFO":"completed","SELKZ":false,"TITLE":"entry 03","VALUE":"green"` &&
                              `},{"CHECKBOX":true,"DESCR":"","EDITABLE":false,"ICON":"","INFO":"completed","SELKZ":false,"TITLE":"entry 04","` &&
                              `VALUE":"orange"},{"CHECKBOX":true,"DESCR":"this is a description","EDITABLE":false,"ICON":"","INFO":"completed` &&
                              `","SELKZ":false,"TITLE":"entry 05","VALUE":"grey"},{"CHECKBOX":false,"DESCR":"","EDITABLE":false,"ICON":"","IN` &&
                              `FO":"","SELKZ":false,"TITLE":"","VALUE":""}]}` ) ).

  ENDMETHOD.

  METHOD expected_table_011.

    result = `{"snapshotVersion":1,"session":"62A9FB6AB2324062B816013E727E79AF","app":"Z2UI5_CL_SMP_APP_011","title":"abap2U` &&
             `I5 - Table - Editable Cells, Add and Delete Rows","layer":"main","fields":[],"actions":[{"id":"a1","event":"BU` &&
             `TTON_TEST","args":[],"label":"test","control":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen"` &&
             `,"layer":"main"},{"id":"a2","event":"BUTTON_DELETE","args":[],"label":"delete selected row","control":"sap.m.B` &&
             `utton","trigger":"press","enabled":true,"scope":"screen","layer":"main"},{"id":"a3","event":"BUTTON_ADD","args` &&
             `":[],"label":"add","control":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen","layer":"main"},` &&
             `{"id":"a4","event":"BUTTON_EDIT","args":[],"label":"edit","control":"sap.m.Button","trigger":"press","enabled"` &&
             `:true,"scope":"screen","layer":"main"}],"tables":[{"id":"t1","path":"/T_TAB","name":"T_TAB","label":"title of ` &&
             `the table","control":"sap.m.Table","columns":[{"name":"TITLE","label":"Title"},{"name":"VALUE","label":"Color"` &&
             `},{"name":"INFO","label":"Info"},{"name":"DESCR","label":"Description"},{"name":"CHECKBOX","label":"Checkbox"}` &&
             `],"rowCount":6,"rows":[{"TITLE":"entry 01","VALUE":"red","INFO":"completed","DESCR":"this is a description","C` &&
             `HECKBOX":true,"SELKZ":false},{"TITLE":"entry 02","VALUE":"blue","INFO":"completed","DESCR":"this is a descript` &&
             `ion","CHECKBOX":true,"SELKZ":false}],"truncated":true,"selectionMode":"Multi","editableCells":["SELKZ"],"layer` &&
             `":"main","selectionField":"SELKZ"}],"messages":[{"type":"info","text":"A MultiSelect table whose input cells s` &&
             `witch between display and edit mode via the toolbar, which also adds new rows and deletes the currently select` &&
             `ed ones.","source":"strip"}],"texts":[],"unsupported":[]}`.

  ENDMETHOD.

  METHOD input_list_048.

    " list-048#1/rows20: list-048#1/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `4A581D5A923D40049E26C855FC45A644`.
    result-app = `Z2UI5_CL_SMP_APP_048`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc"><Shell><Page title="abap` &&
                              `2UI5 - List - StandardListItem, Highlight and Events" showNavButton="false" navButtonPress=".eB(['___ZZZ_NAL']` &&
                              `)"><MessageStrip text="A List of generic StandardListItems showing highlight bars, colored infoState and wrapp` &&
                              `ing texts; the detail button and selection changes raise backend events with message boxes." type="Information` &&
                              `" showIcon="true" class="sapUiSmallMargin"/><List headerText="List Output" items="{/T_TAB}" mode="SingleSelect` &&
                              `Master" selectionChange=".eB(['SELCHANGE'])"><StandardListItem title="{TITLE}" description="{DESCR}" icon="{IC` &&
                              `ON}" iconInset="false" highlight="{HIGHLIGHT}" info="{INFO}" infoState="{HIGHLIGHT}" type="Detail" wrapping="t` &&
                              `rue" selected="{SELECTED}" detailPress=".eB(['EDIT'], ${TITLE}, ${DESCR}, ${ICON}, ${HIGHLIGHT}, ${INFO}, ${SE` &&
                              `LECTED})"/></List></Page></Shell></mvc:View>`
                      model = `{"T_TAB":[{"CHECKBOX":false,"DESCR":"this is a description1 1234567890 1234567890","HIGHLIGHT":"Information","` &&
                              `ICON":"sap-icon://badge","INFO":"Information","SELECTED":false,"TITLE":"entry_01","VALUE":""},{"CHECKBOX":fals` &&
                              `e,"DESCR":"this is a description2 1234567890 1234567890","HIGHLIGHT":"Success","ICON":"sap-icon://favorite","I` &&
                              `NFO":"Success","SELECTED":false,"TITLE":"entry_02","VALUE":""},{"CHECKBOX":false,"DESCR":"this is a descriptio` &&
                              `n3 1234567890 1234567890","HIGHLIGHT":"Warning","ICON":"sap-icon://employee","INFO":"Warning","SELECTED":false` &&
                              `,"TITLE":"entry_03","VALUE":""},{"CHECKBOX":false,"DESCR":"this is a description4 1234567890 1234567890","HIGH` &&
                              `LIGHT":"Error","ICON":"sap-icon://accept","INFO":"Error","SELECTED":false,"TITLE":"entry_04","VALUE":""},{"CHE` &&
                              `CKBOX":false,"DESCR":"this is a description5 1234567890 1234567890","HIGHLIGHT":"None","ICON":"sap-icon://acti` &&
                              `vities","INFO":"None","SELECTED":false,"TITLE":"entry_05","VALUE":""},{"CHECKBOX":false,"DESCR":"this is a des` &&
                              `cription6 1234567890 1234567890","HIGHLIGHT":"Information","ICON":"sap-icon://account","INFO":"Information","S` &&
                              `ELECTED":false,"TITLE":"entry_06","VALUE":""}]}` ) ).

  ENDMETHOD.

  METHOD expected_list_048.

    result = `{"snapshotVersion":1,"session":"4A581D5A923D40049E26C855FC45A644","app":"Z2UI5_CL_SMP_APP_048","title":"abap2U` &&
             `I5 - List - StandardListItem, Highlight and Events","layer":"main","fields":[],"actions":[{"id":"a1","event":"` &&
             `SELCHANGE","args":[],"label":"List Output: selectionChange","control":"sap.m.List","trigger":"selectionChange"` &&
             `,"enabled":true,"scope":"row","table":"t1","layer":"main"},{"id":"a2","event":"EDIT","args":["$row:TITLE","$ro` &&
             `w:DESCR","$row:ICON","$row:HIGHLIGHT","$row:INFO","$row:SELECTED"],"label":"row detailPress (Detail)","control` &&
             `":"sap.m.StandardListItem","trigger":"detailPress","enabled":true,"scope":"row","table":"t1","layer":"main"}],` &&
             `"tables":[{"id":"t1","path":"/T_TAB","name":"T_TAB","label":"List Output","control":"sap.m.List","columns":[{"` &&
             `name":"TITLE","label":"title"},{"name":"DESCR","label":"description"},{"name":"ICON","label":"icon"},{"name":"` &&
             `INFO","label":"info"},{"name":"HIGHLIGHT","label":"infoState"}],"rowCount":6,"rows":[{"TITLE":"entry_01","DESC` &&
             `R":"this is a description1 1234567890 1234567890","ICON":"sap-icon://badge","INFO":"Information","HIGHLIGHT":"` &&
             `Information","SELECTED":false},{"TITLE":"entry_02","DESCR":"this is a description2 1234567890 1234567890","ICO` &&
             `N":"sap-icon://favorite","INFO":"Success","HIGHLIGHT":"Success","SELECTED":false},{"TITLE":"entry_03","DESCR":` &&
             `"this is a description3 1234567890 1234567890","ICON":"sap-icon://employee","INFO":"Warning","HIGHLIGHT":"Warn` &&
             `ing","SELECTED":false},{"TITLE":"entry_04","DESCR":"this is a description4 1234567890 1234567890","ICON":"sap-` &&
             `icon://accept","INFO":"Error","HIGHLIGHT":"Error","SELECTED":false},{"TITLE":"entry_05","DESCR":"this is a des` &&
             `cription5 1234567890 1234567890","ICON":"sap-icon://activities","INFO":"None","HIGHLIGHT":"None","SELECTED":fa` &&
             `lse},{"TITLE":"entry_06","DESCR":"this is a description6 1234567890 1234567890","ICON":"sap-icon://account","I` &&
             `NFO":"Information","HIGHLIGHT":"Information","SELECTED":false}],"truncated":false,"selectionMode":"Single","ed` &&
             `itableCells":["SELECTED"],"layer":"main","selectionField":"SELECTED"}],"messages":[{"type":"info","text":"A Li` &&
             `st of generic StandardListItems showing highlight bars, colored infoState and wrapping texts; the detail butto` &&
             `n and selection changes raise backend events with message boxes.","source":"strip"}],"texts":[],"unsupported":` &&
             `[]}`.

  ENDMETHOD.

  METHOD input_popup_009.

    " popup-009#2/rows20: popup-009#2/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `BB1198D42E6942EFB4A3351C6965E85F`.
    result-app = `Z2UI5_CL_SMP_APP_009`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:core="sap.ui.core"` &&
                              ` xmlns:form="sap.ui.layout.form" xmlns:layout="sap.ui.layout"><Shell><Page title="abap2UI5 - Popup - Value Hel` &&
                              `p: Suggestions and F4 Dialog" showNavButton="false" navButtonPress=".eB(['___ZZZ_NAL'])"><MessageStrip text="F` &&
                              `our value-help patterns: inline suggestions, numeric-only input, a value-help popup with a selectable table, a` &&
                              `nd a custom popup with a city search. Fill the fields, then Clear resets the view and Send simulates a submit.` &&
                              `" type="Information" showIcon="true" class="sapUiSmallMargin"/><layout:Grid defaultSpan="L7 M7 S7"><layout:con` &&
                              `tent><form:SimpleForm title="Input with Value Help" editable="true"><form:content><Label text="Input with sugg` &&
                              `estion items"/><Input placeholder="fill in your favorite colour" value="{/S_SCREEN/COLOR_01}" suggestionItems=` &&
                              `"{/T_SUGGESTION}" showSuggestion="true"><suggestionItems><core:ListItem text="{VALUE}" additionalText="{DESCR}` &&
                              `"/></suggestionItems></Input><Label text="Input only numbers allowed"/><Input placeholder="quantity" type="Num` &&
                              `ber" value="{/S_SCREEN/QUANTITY}"/><Label text="Input with value"/><Input placeholder="fill in your favorite c` &&
                              `olour" value="{/S_SCREEN/COLOR_02}" valueHelpRequest=".eB(['POPUP_TABLE_VALUE'])" showValueHelp="true"/><Label` &&
                              ` text="Custom value Popup"/><Input placeholder="name" value="{/S_SCREEN/NAME}" valueHelpRequest=".eB(['POPUP_T` &&
                              `ABLE_VALUE_CUSTOM'])" showValueHelp="true"/><Input placeholder="lastname" value="{/S_SCREEN/LASTNAME}" valueHe` &&
                              `lpRequest=".eB(['POPUP_TABLE_VALUE_CUSTOM'])" showValueHelp="true"/></form:content></form:SimpleForm></layout:` &&
                              `content></layout:Grid><footer><OverflowToolbar><ToolbarSpacer/><Button press=".eB(['BUTTON_CLEAR'])" text="Cle` &&
                              `ar" icon="sap-icon://delete" type="Reject"/><Button press=".eB(['BUTTON_SEND'])" text="Send to Server" icon="s` &&
                              `ap-icon://paper-plane" type="Accept"/></OverflowToolbar></footer></Page></Shell></mvc:View>`
                      model = `{"S_SCREEN":{"COLOR_01":"","COLOR_02":"","LASTNAME":"","NAME":"Smith","QUANTITY":"3"},"T_SUGGESTION":[{"DESCR"` &&
                              `:"this is the color Green","SELKZ":false,"VALUE":"GREEN"},{"DESCR":"this is the color Blue","SELKZ":false,"VAL` &&
                              `UE":"BLUE"},{"DESCR":"this is the color Black","SELKZ":false,"VALUE":"BLACK"},{"DESCR":"this is the color Grey` &&
                              `","SELKZ":false,"VALUE":"GREY"},{"DESCR":"this is the color Blue2","SELKZ":false,"VALUE":"BLUE2"},{"DESCR":"th` &&
                              `is is the color Blue3","SELKZ":false,"VALUE":"BLUE3"}],"T_SUGGESTION_SEL":[{"DESCR":"this is the color Green",` &&
                              `"SELKZ":false,"VALUE":"GREEN"},{"DESCR":"this is the color Blue","SELKZ":false,"VALUE":"BLUE"},{"DESCR":"this ` &&
                              `is the color Black","SELKZ":false,"VALUE":"BLACK"},{"DESCR":"this is the color Grey","SELKZ":false,"VALUE":"GR` &&
                              `EY"},{"DESCR":"this is the color Blue2","SELKZ":false,"VALUE":"BLUE2"},{"DESCR":"this is the color Blue3","SEL` &&
                              `KZ":false,"VALUE":"BLUE3"}]}` )
                        ( layer = `POPUP`
                      xml   = `<core:FragmentDefinition xmlns="sap.m" xmlns:core="sap.ui.core"><Dialog title="abap2UI5 - Value Help"><Table i` &&
                              `tems="{/T_SUGGESTION_SEL}" mode="SingleSelectLeft"><columns><Column width="20rem"><Text text="Color"/></Column` &&
                              `><Column><Text text="Description"/></Column></columns><items><ColumnListItem selected="{SELKZ}"><cells><Text t` &&
                              `ext="{VALUE}"/><Text text="{DESCR}"/></cells></ColumnListItem></items></Table><buttons><Button press=".eB(['PO` &&
                              `PUP_TABLE_VALUE_CONTINUE'])" text="continue" type="Emphasized"/></buttons></Dialog></core:FragmentDefinition>`
                      model = `{"S_SCREEN":{"COLOR_01":"","COLOR_02":"","LASTNAME":"","NAME":"Smith","QUANTITY":"3"},"T_SUGGESTION":[{"DESCR"` &&
                              `:"this is the color Green","SELKZ":false,"VALUE":"GREEN"},{"DESCR":"this is the color Blue","SELKZ":false,"VAL` &&
                              `UE":"BLUE"},{"DESCR":"this is the color Black","SELKZ":false,"VALUE":"BLACK"},{"DESCR":"this is the color Grey` &&
                              `","SELKZ":false,"VALUE":"GREY"},{"DESCR":"this is the color Blue2","SELKZ":false,"VALUE":"BLUE2"},{"DESCR":"th` &&
                              `is is the color Blue3","SELKZ":false,"VALUE":"BLUE3"}],"T_SUGGESTION_SEL":[{"DESCR":"this is the color Green",` &&
                              `"SELKZ":false,"VALUE":"GREEN"},{"DESCR":"this is the color Blue","SELKZ":false,"VALUE":"BLUE"},{"DESCR":"this ` &&
                              `is the color Black","SELKZ":false,"VALUE":"BLACK"},{"DESCR":"this is the color Grey","SELKZ":false,"VALUE":"GR` &&
                              `EY"},{"DESCR":"this is the color Blue2","SELKZ":false,"VALUE":"BLUE2"},{"DESCR":"this is the color Blue3","SEL` &&
                              `KZ":false,"VALUE":"BLUE3"}]}` ) ).

  ENDMETHOD.

  METHOD expected_popup_009.

    result = `{"snapshotVersion":1,"session":"BB1198D42E6942EFB4A3351C6965E85F","app":"Z2UI5_CL_SMP_APP_009","title":"abap2U` &&
             `I5 - Value Help","layer":"popup","fields":[],"actions":[{"id":"a1","event":"POPUP_TABLE_VALUE_CONTINUE","args"` &&
             `:[],"label":"continue","control":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen","layer":"pop` &&
             `up"}],"tables":[{"id":"t1","path":"/T_SUGGESTION_SEL","name":"T_SUGGESTION_SEL","label":"T_SUGGESTION_SEL","co` &&
             `ntrol":"sap.m.Table","columns":[{"name":"VALUE","label":"Color"},{"name":"DESCR","label":"Description"}],"rowC` &&
             `ount":6,"rows":[{"VALUE":"GREEN","DESCR":"this is the color Green","SELKZ":false},{"VALUE":"BLUE","DESCR":"thi` &&
             `s is the color Blue","SELKZ":false},{"VALUE":"BLACK","DESCR":"this is the color Black","SELKZ":false},{"VALUE"` &&
             `:"GREY","DESCR":"this is the color Grey","SELKZ":false},{"VALUE":"BLUE2","DESCR":"this is the color Blue2","SE` &&
             `LKZ":false},{"VALUE":"BLUE3","DESCR":"this is the color Blue3","SELKZ":false}],"truncated":false,"selectionMod` &&
             `e":"Single","editableCells":["SELKZ"],"layer":"popup","selectionField":"SELKZ"}],"messages":[],"texts":[],"uns` &&
             `upported":[]}`.

  ENDMETHOD.

  METHOD input_popup_012.

    " popup-012#2/rows20: popup-012#2/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `D41A1D24B3404492AE80ABBCD2917D06`.
    result-app = `Z2UI5_CL_SMP_APP_012`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:form="sap.ui.layou` &&
                              `t.form" xmlns:layout="sap.ui.layout"><Shell><Page title="abap2UI5 - Popup - Ways to Open a Dialog" showNavButt` &&
                              `on="false" navButtonPress=".eB(['___ZZZ_NAL'])"><MessageStrip text="Shows different ways to open a popup - ins` &&
                              `ide the same app or as a sub-app - and how the background view is kept, destroyed or re-rendered." type="Infor` &&
                              `mation" showIcon="true" class="sapUiSmallMargin"/><layout:Grid defaultSpan="L7 M12 S12"><layout:content><form:` &&
                              `SimpleForm title="Popup in same App" editable="true"><form:content><Label text="Demo"/><Button press=".eB(['BU` &&
                              `TTON_POPUP_01'])" text="popup rendering, no background rendering"/><Label text="Demo"/><Button press=".eB(['BU` &&
                              `TTON_POPUP_02'])" text="popup rendering, background destroyed and rerendering"/><Label text="Demo"/><Button pr` &&
                              `ess=".eB(['BUTTON_POPUP_03'])" text="popup, background unchanged (default) - close (no roundtrip)"/><Label tex` &&
                              `t="Demo"/><Button press=".eB(['BUTTON_POPUP_04'])" text="popup, background unchanged (default) - close with se` &&
                              `rver"/></form:content></form:SimpleForm><form:SimpleForm title="Popup in new App" editable="true"><form:conten` &&
                              `t><Label text="Demo"/><Button press=".eB(['BUTTON_POPUP_05'])" text="popup rendering, no background"/><Label t` &&
                              `ext="Demo"/><Button press=".eB(['BUTTON_POPUP_06'])" text="popup rendering, hold previous view"/></form:conten` &&
                              `t></form:SimpleForm></layout:content></layout:Grid></Page></Shell></mvc:View>`
                      model = `{}` )
                        ( layer = `POPUP`
                      xml   = `<core:FragmentDefinition xmlns="sap.m" xmlns:core="sap.ui.core"><Dialog title="Popup - Info"><VBox><Text text=` &&
                              `"this is an information, press close to go back to the main view without a server roundtrip"/></VBox><buttons>` &&
                              `<Button press=".eF('CONTROL_GLOBAL', 'VIEW_SLOTS', 'destroy', 'POPUP')" text="close" type="Emphasized"/></butt` &&
                              `ons></Dialog></core:FragmentDefinition>`
                      model = `{}` ) ).

  ENDMETHOD.

  METHOD expected_popup_012.

    result = `{"snapshotVersion":1,"session":"D41A1D24B3404492AE80ABBCD2917D06","app":"Z2UI5_CL_SMP_APP_012","title":"Popup ` &&
             `- Info","layer":"popup","fields":[],"actions":[{"id":"a1","event":"@CLOSE_POPUP","args":[],"label":"close","co` &&
             `ntrol":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen","layer":"popup"}],"tables":[],"message` &&
             `s":[],"texts":["this is an information, press close to go back to the main view without a server roundtrip"],"` &&
             `unsupported":[]}`.

  ENDMETHOD.

  METHOD input_messages_467.

    " messages-467#1/rows20: messages-467#1/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `CFD1509889C741D285AA0CE7F5723821`.
    result-app = `Z2UI5_CL_SMP_APP_467`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:z2ui5="z2ui5.cc"><` &&
                              `Shell><Page title="abap2UI5 - Message - Message Model and MessageManager" showNavButton="false" navButtonPress` &&
                              `=".eB(['___ZZZ_NAL'])"><MessageStrip text="Both sources of the central message&gt; model in one page: the Name` &&
                              ` messages are AUTHORED BY THE APP (pushed from an ABAP table by the invisible z2ui5.cc.MessageManager companio` &&
                              `n - the Error targets the Name field and colours it), while typing letters into the Amount field collects the ` &&
                              `failed Integer validation AUTOMATICALLY - no app code, no roundtrip. Both render in the list below." type="Inf` &&
                              `ormation" showIcon="true" class="sapUiSmallMargin"/><z2ui5:MessageManager items="{/T_MESSAGES}"/><VBox class="` &&
                              `sapUiSmallMargin"><Label text="Name (message authored by the app)"/><Input value="{/NAME}"/><Label text="Amoun` &&
                              `t (integer only - validation collected automatically)"/><Input value="{ path: '/AMOUNT', type: 'sap.ui.model.t` &&
                              `ype.Integer' }" width="12rem"/></VBox><List headerText="Collected messages (message&gt; model)" items="{messag` &&
                              `e&gt;/}" class="sapUiSmallMargin" noDataText="no messages"><StandardListItem title="{message&gt;message}" desc` &&
                              `ription="{message&gt;additionalText}" info="{message&gt;type}"/></List></Page></Shell></mvc:View>`
                      model = `{"AMOUNT":42,"NAME":"","T_MESSAGES":[{"ADDITIONALTEXT":"Name","DESCRIPTION":"","MESSAGE":"Please enter a valid` &&
                              ` name","TARGET":"/NAME","TYPE":"Error"},{"ADDITIONALTEXT":"Autosave","DESCRIPTION":"","MESSAGE":"Draft saved a` &&
                              `utomatically","TARGET":"","TYPE":"Information"}]}` ) ).

  ENDMETHOD.

  METHOD expected_messages_467.

    result = `{"snapshotVersion":1,"session":"CFD1509889C741D285AA0CE7F5723821","app":"Z2UI5_CL_SMP_APP_467","title":"abap2U` &&
             `I5 - Message - Message Model and MessageManager","layer":"main","fields":[{"id":"f1","path":"/NAME","name":"NA` &&
             `ME","label":"Name (message authored by the app)","control":"sap.m.Input","kind":"text","value":"","required":f` &&
             `alse,"editable":true,"layer":"main"},{"id":"f2","path":"/AMOUNT","name":"AMOUNT","label":"Amount (integer only` &&
             ` - validation collected automatically)","control":"sap.m.Input","kind":"number","value":42,"required":false,"e` &&
             `ditable":true,"layer":"main"}],"actions":[],"tables":[],"messages":[{"type":"info","text":"Both sources of the` &&
             ` central message> model in one page: the Name messages are AUTHORED BY THE APP (pushed from an ABAP table by t` &&
             `he invisible z2ui5.cc.MessageManager companion - the Error targets the Name field and colours it), while typin` &&
             `g letters into the Amount field collects the failed Integer validation AUTOMATICALLY - no app code, no roundtr` &&
             `ip. Both render in the list below.","source":"strip"},{"type":"error","text":"Please enter a valid name","sour` &&
             `ce":"field","field":"f1"},{"type":"info","text":"Draft saved automatically","source":"model"}],"texts":[],"uns` &&
             `upported":["List bound to the named model 'message' (main) - rows not described"]}`.

  ENDMETHOD.

  METHOD input_select_623.

    " select-623#3/rows20: select-623#3/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `52BACFFE4EA045F2BBB5CED8493CD147`.
    result-app = `Z2UI5_CL_SMPC_APP_623`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View xmlns="sap.m" xmlns:l="sap.ui.layout" xmlns:mvc="sap.ui.core.mvc"><l:VerticalLayout class="sapUiCont` &&
                              `entPadding" width="100%"><l:content><Label text="Product not editable" labelFor="InputNoEdit"/><Input id="Inpu` &&
                              `tNoEdit" class="sapUiSmallMarginBottom" type="Text" placeholder="Product" enabled="true" editable="false"/><La` &&
                              `bel text="Product not enabled" labelFor="InputDisabled"/><Input id="InputDisabled" class="sapUiSmallMarginBott` &&
                              `om" type="Text" placeholder="Product" enabled="false"/><Label text="Product editable" labelFor="InputEdit"/><I` &&
                              `nput id="InputEdit" class="sapUiSmallMarginBottom" type="Text" placeholder="Enter product" enabled="true" edit` &&
                              `able="true"/><Label text="Product with Value Help" labelFor="InputValueHelp"/><Input id="InputValueHelp" class` &&
                              `="sapUiSmallMarginBottom" type="Text" placeholder="Enter product" enabled="true" editable="true" showValueHelp` &&
                              `="true" value="{/VALUE_HELP}" valueHelpRequest=".eB(['VALUE_HELP'])"/></l:content></l:VerticalLayout></mvc:Vie` &&
                              `w>`
                      model = `{"T_PRODUCTS":[{"NAME":"Notebook Basic 17","PICURL":"https://sdk.openui5.org/test-resources/sap/ui/documentati` &&
                              `on/sdk/images/HT-1001.jpg","PRODUCTID":"HT-1001"},{"NAME":"Notebook Professional 17","PICURL":"https://sdk.ope` &&
                              `nui5.org/test-resources/sap/ui/documentation/sdk/images/HT-1011.jpg","PRODUCTID":"HT-1011"}],"VALUE_HELP":""}` )
                        ( layer = `POPUP`
                      xml   = `<core:FragmentDefinition xmlns:core="sap.ui.core" xmlns="sap.m"><SelectDialog title="Products" items="{/T_PROD` &&
                              `UCTS}" search=".eB(['VH_SEARCH'], ${$parameters&gt;/value})" confirm=".eB(['VH_CONFIRM'], ${$parameters&gt;/se` &&
                              `lectedItem}.getTitle())" cancel=".eB(['VH_CANCEL'])"><items><StandardListItem icon="{PICURL}" iconDensityAware` &&
                              `="false" iconInset="false" title="{NAME}" description="{PRODUCTID}"/></items></SelectDialog></core:FragmentDef` &&
                              `inition>`
                      model = `{"T_PRODUCTS":[{"NAME":"Notebook Basic 17","PICURL":"https://sdk.openui5.org/test-resources/sap/ui/documentati` &&
                              `on/sdk/images/HT-1001.jpg","PRODUCTID":"HT-1001"},{"NAME":"Notebook Professional 17","PICURL":"https://sdk.ope` &&
                              `nui5.org/test-resources/sap/ui/documentation/sdk/images/HT-1011.jpg","PRODUCTID":"HT-1011"}],"VALUE_HELP":""}` ) ).

  ENDMETHOD.

  METHOD expected_select_623.

    result = `{"snapshotVersion":1,"session":"52BACFFE4EA045F2BBB5CED8493CD147","app":"Z2UI5_CL_SMPC_APP_623","title":"Produ` &&
             `cts","layer":"popup","fields":[],"actions":[{"id":"a1","event":"VH_SEARCH","args":["$parameters:value"],"label` &&
             `":"Products: search","control":"sap.m.SelectDialog","trigger":"search","enabled":true,"scope":"screen","layer"` &&
             `:"popup"},{"id":"a2","event":"VH_CONFIRM","args":["$expr:${$parameters>/selectedItem}.getTitle()"],"label":"Pr` &&
             `oducts: confirm","control":"sap.m.SelectDialog","trigger":"confirm","enabled":true,"scope":"row","table":"t1",` &&
             `"layer":"popup"},{"id":"a3","event":"VH_CANCEL","args":[],"label":"Products: cancel","control":"sap.m.SelectDi` &&
             `alog","trigger":"cancel","enabled":true,"scope":"screen","layer":"popup"}],"tables":[{"id":"t1","path":"/T_PRO` &&
             `DUCTS","name":"T_PRODUCTS","label":"Products","control":"sap.m.SelectDialog","columns":[{"name":"PICURL","labe` &&
             `l":"icon"},{"name":"NAME","label":"title"},{"name":"PRODUCTID","label":"description"}],"rowCount":2,"rows":[{"` &&
             `PICURL":"https://sdk.openui5.org/test-resources/sap/ui/documentation/sdk/images/HT-1001.jpg","NAME":"Notebook ` &&
             `Basic 17","PRODUCTID":"HT-1001"},{"PICURL":"https://sdk.openui5.org/test-resources/sap/ui/documentation/sdk/im` &&
             `ages/HT-1011.jpg","NAME":"Notebook Professional 17","PRODUCTID":"HT-1011"}],"truncated":false,"selectionMode":` &&
             `"Single","editableCells":[],"layer":"popup"}],"messages":[],"texts":[],"unsupported":[]}`.

  ENDMETHOD.

  METHOD input_cgui_f4_06.

    " cgui-f4-06#3/rows2: cgui-f4-06#3/rows2 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `88A2ACD4D3444A23AAC5E25D0DD6A109`.
    result-app = `Z2UI5_CL_POPUP_TO_SELECT`.
    result-max_rows = 2.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:z2ui5="z2ui5.cc" displayBlock="true" height="100%"><` &&
                              `Page title="Dynamic Selection Screen" showNavButton="false" navButtonPress=".eB(['CGUI_BACK'])"><z2ui5:Storage` &&
                              ` type="local" prefix="z2ui5_cgui_variants" key="Z2UI5_CL_CGUI_R2C_06" value="{/MV_CGUI_VARIANTS}" finished=".e` &&
                              `B(['CGUI_VARIANTS_LOADED',false,false,false,true])"/><form:SimpleForm xmlns:form="sap.ui.layout.form" editable` &&
                              `="true" layout="ResponsiveGridLayout" labelSpanXL="3" labelSpanL="3" labelSpanM="3" emptySpanXL="4" emptySpanL` &&
                              `="4" emptySpanM="2" columnsXL="1" columnsL="1" columnsM="1" title="Mode"><Label text="" required="false"/><Rad` &&
                              `ioButton text="Display material" groupName="MODE" selected="{/P_DISP}" editable="true"/><Label text="" require` &&
                              `d="false"/><RadioButton text="Create material" groupName="MODE" selected="{/P_CREA}" editable="true" select=".` &&
                              `eB(['MODE'])"/></form:SimpleForm><form:SimpleForm xmlns:form="sap.ui.layout.form" editable="true" layout="Resp` &&
                              `onsiveGridLayout" labelSpanXL="3" labelSpanL="3" labelSpanM="3" emptySpanXL="4" emptySpanL="4" emptySpanM="2" ` &&
                              `columnsXL="1" columnsL="1" columnsM="1" title="Material"><Label text="Material" required="false"/><Input value` &&
                              `="{/P_MATNR}" required="false" editable="true" id="cgui_f_p_matnr" maxLength="18"/><Label text="Unit of measur` &&
                              `e"/><HBox alignItems="Center"><Label text="P_UNIT" required="false" class="sapUiSmallMarginBegin sapUiTinyMarg` &&
                              `inEnd"/><Input value="{/P_UNIT}" required="false" editable="true" id="cgui_f_p_unit" maxLength="3"/></HBox></f` &&
                              `orm:SimpleForm><form:SimpleForm xmlns:form="sap.ui.layout.form" editable="true" layout="ResponsiveGridLayout" ` &&
                              `labelSpanXL="3" labelSpanL="3" labelSpanM="3" emptySpanXL="4" emptySpanL="4" emptySpanM="2" columnsXL="1" colu` &&
                              `mnsL="1" columnsM="1" title="Expert settings"><Label text="" required="false"/><CheckBox text="Expert settings` &&
                              `" selected="{/P_EXPERT}" editable="true" id="cgui_f_p_expert" select=".eB(['EXPERT'])"/><Label text="Plant" re` &&
                              `quired="false"/><Input value="{/P_PLANT}" required="false" editable="true" id="cgui_f_p_plant" maxLength="4" s` &&
                              `howValueHelp="true" valueHelpRequest=".eB(['CGUI_VALUE_REQUEST'], 'P_PLANT')"/><Label text="Access token" requ` &&
                              `ired="false"/><Input value="{/P_TOKEN}" required="false" editable="true" id="cgui_f_p_token" type="Password" m` &&
                              `axLength="32"/><Label text="" required="false"/><Button text="Reset" icon="" enabled="true" press=".eB(['RESET` &&
                              `'])"/></form:SimpleForm><footer><OverflowToolbar><Button text="Get Variant" icon="sap-icon://open-folder" pres` &&
                              `s=".eB(['CGUI_VARIANT_GET'])"/><Button text="Save as Variant" icon="sap-icon://save" press=".eB(['CGUI_VARIANT` &&
                              `_SAVE'])"/><Button text="Delete Variant" icon="sap-icon://delete" press=".eB(['CGUI_VARIANT_DELETE'])"/><Toolb` &&
                              `arSpacer/><Button text="Execute" icon="sap-icon://begin" type="Emphasized" press=".eB(['CGUI_EXECUTE'])"/></Ov` &&
                              `erflowToolbar></footer></Page></mvc:View>`
                      model = `{"MV_CGUI_VARIANTS":"","P_CREA":false,"P_DISP":true,"P_EXPERT":true,"P_MATNR":"","P_NAME":"","P_PLANT":"","P_Q` &&
                              `TY":0,"P_SOURCE":"ZR2C_06_DYNAMIC","P_TOKEN":"","P_UNIT":"PC"}` )
                        ( layer = `POPUP`
                      xml   = `<core:FragmentDefinition xmlns="sap.m" xmlns:core="sap.ui.core"><TableSelectDialog items="{path:'/MR_TAB_POPUP` &&
                              `/*', sorter : { path : '', descending : false } }" cancel=".eB(['CANCEL'])" search=".eB(['SEARCH'], ${$paramet` &&
                              `ers&gt;/value}, ${$parameters&gt;/clearButtonPressed})" confirm=".eB(['CONFIRM'], ${$parameters&gt;/selectedCo` &&
                              `ntexts[0]/sPath})" growing="true" contentWidth="" contentHeight="" growingThreshold="" title="Single Select" m` &&
                              `ultiSelect="false"><ColumnListItem vAlign="Top" selected="{ZZSELKZ}"><cells><Text text="{WERKS}"/><Text text="` &&
                              `{NAME}"/></cells></ColumnListItem><columns><Column width="8rem"><header><Text text="WERKS"/></header></Column>` &&
                              `<Column width="8rem"><header><Text text="NAME"/></header></Column></columns></TableSelectDialog></core:Fragmen` &&
                              `tDefinition>`
                      model = `{"MR_TAB_POPUP":{"*":[{"NAME":"Hamburg","WERKS":"1000","ZZSELKZ":false},{"NAME":"Walldorf","WERKS":"2000","ZZS` &&
                              `ELKZ":false},{"NAME":"Berlin","WERKS":"3000","ZZSELKZ":false}]}}` ) ).

  ENDMETHOD.

  METHOD expected_cgui_f4_06.

    result = `{"snapshotVersion":1,"session":"88A2ACD4D3444A23AAC5E25D0DD6A109","app":"Z2UI5_CL_POPUP_TO_SELECT","title":"Si` &&
             `ngle Select","layer":"popup","fields":[],"actions":[{"id":"a1","event":"CANCEL","args":[],"label":"Single Sele` &&
             `ct: cancel","control":"sap.m.TableSelectDialog","trigger":"cancel","enabled":true,"scope":"screen","layer":"po` &&
             `pup"},{"id":"a2","event":"SEARCH","args":["$parameters:value","$parameters:clearButtonPressed"],"label":"Singl` &&
             `e Select: search","control":"sap.m.TableSelectDialog","trigger":"search","enabled":true,"scope":"screen","laye` &&
             `r":"popup"},{"id":"a3","event":"CONFIRM","args":["$parameters:selectedContexts[0]/sPath"],"label":"Single Sele` &&
             `ct: confirm","control":"sap.m.TableSelectDialog","trigger":"confirm","enabled":true,"scope":"row","table":"t1"` &&
             `,"layer":"popup"}],"tables":[{"id":"t1","path":"/MR_TAB_POPUP/*","name":"MR_TAB_POPUP-*","label":"Single Selec` &&
             `t","control":"sap.m.TableSelectDialog","columns":[{"name":"WERKS","label":"WERKS"},{"name":"NAME","label":"NAM` &&
             `E"}],"rowCount":3,"rows":[{"WERKS":"1000","NAME":"Hamburg","ZZSELKZ":false},{"WERKS":"2000","NAME":"Walldorf",` &&
             `"ZZSELKZ":false}],"truncated":true,"selectionMode":"Single","editableCells":["ZZSELKZ"],"layer":"popup","selec` &&
             `tionField":"ZZSELKZ"}],"messages":[],"texts":[],"unsupported":[]}`.

  ENDMETHOD.

  METHOD input_messages_452.

    " messages-452#1/rows20: messages-452#1/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `908D30A986074441893595DDC602A526`.
    result-app = `Z2UI5_CL_SMP_APP_452`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View displayBlock="true" height="100%" xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc"><Shell><Page title="abap` &&
                              `2UI5 - Message - MessageView and MessagePopover" showNavButton="false" navButtonPress=".eB(['___ZZZ_NAL'])"><M` &&
                              `essageStrip text="This free-style demo combines the sap.m message controls: one bound message table is rendere` &&
                              `d three ways - as a full-page MessageView with grouped items, inside a dialog and as a MessagePopover. It is n` &&
                              `ot a 1:1 demo kit rebuild (those live in the samples-controls repository) and stays within the UI5 1.71 contro` &&
                              `l set." type="Information" showIcon="true" class="sapUiSmallMargin"/><MessageView items="{/T_MSG}" groupItems=` &&
                              `"true"><MessageItem type="{TYPE}" title="{TITLE}" subtitle="{SUBTITLE}" description="{DESCRIPTION}" groupName=` &&
                              `"{GROUP}"><Link text="Show more information" target="_blank" href="https://sap.com"/></MessageItem></MessageVi` &&
                              `ew><footer><OverflowToolbar><Button press=".eB(['POPUP'])" text="5" icon="sap-icon://message-error" tooltip="S` &&
                              `how the messages"/><ToolbarSpacer/><Button press=".eB(['POPOVER'])" text="Message Popover" id="messagePopoverB` &&
                              `tn"/></OverflowToolbar></footer></Page></Shell></mvc:View>`
                      model = `{"T_MSG":[{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing` &&
                              ` elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostru` &&
                              `d exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit` &&
                              ` in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proiden` &&
                              `t, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"Purchase Order 450001","SUBTITLE":` &&
                              `"Role is invalid","TITLE":"Account 801 requires an assignment","TYPE":"Error"},{"DESCRIPTION":"First Error mes` &&
                              `sage description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt u` &&
                              `t labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut al` &&
                              `iquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu` &&
                              ` fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mol` &&
                              `lit anim id est laborum.","GROUP":"Purchase Order 450001","SUBTITLE":"Undefined task","TITLE":"Account 821 req` &&
                              `uires a check","TYPE":"Warning"},{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit amet, ` &&
                              `consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad mi` &&
                              `nim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure` &&
                              ` dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaeca` &&
                              `t cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"Purchase Or` &&
                              `der 450002","SUBTITLE":"","TITLE":"Enter a text with maximum 6 characters length","TYPE":"Warning"},{"DESCRIPT` &&
                              `ION":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmo` &&
                              `d tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullam` &&
                              `co laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit ` &&
                              `esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui` &&
                              ` officia deserunt mollit anim id est laborum.","GROUP":"Purchase Order 450002","SUBTITLE":"","TITLE":"Enter a ` &&
                              `text with maximum 8 characters length","TYPE":"Warning"},{"DESCRIPTION":"First Error message description. Lore` &&
                              `m ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore mag` &&
                              `na aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo co` &&
                              `nsequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur` &&
                              `. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laboru` &&
                              `m.","GROUP":"Purchase Order 450002","SUBTITLE":"Role is invalid","TITLE":"Account 802 requires an assignment",` &&
                              `"TYPE":"Error"},{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipi` &&
                              `sicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis ` &&
                              `nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehe` &&
                              `nderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non p` &&
                              `roident, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"Purchase Order 450002","SUBT` &&
                              `ITLE":"Information type subtitle","TITLE":"Account 804 requires an assignment","TYPE":"Information"},{"DESCRIP` &&
                              `TION":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusm` &&
                              `od tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ulla` &&
                              `mco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit` &&
                              ` esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qu` &&
                              `i officia deserunt mollit anim id est laborum.","GROUP":"General","SUBTITLE":"","TITLE":"Technical message wit` &&
                              `hout object relation","TYPE":"Error"},{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit a` &&
                              `met, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ` &&
                              `ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute ` &&
                              `irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint oc` &&
                              `caecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"Genera` &&
                              `l","SUBTITLE":"","TITLE":"Global System will be down on Sunday","TYPE":"Warning"},{"DESCRIPTION":"First Error ` &&
                              `message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididun` &&
                              `t ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut` &&
                              ` aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore` &&
                              ` eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt ` &&
                              `mollit anim id est laborum.","GROUP":"General","SUBTITLE":"","TITLE":"Global System will be down on Sunday","T` &&
                              `YPE":"Error"},{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisi` &&
                              `cing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis no` &&
                              `strud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehend` &&
                              `erit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non pro` &&
                              `ident, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"","SUBTITLE":"Ungrouped messag` &&
                              `e","TITLE":"An Error","TYPE":"Error"},{"DESCRIPTION":"First Error message description. Lorem ipsum dolor sit a` &&
                              `met, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ` &&
                              `ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute ` &&
                              `irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint oc` &&
                              `caecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.","GROUP":"","SUB` &&
                              `TITLE":"Ungrouped message","TITLE":"A Warning","TYPE":"Warning"}]}` ) ).

  ENDMETHOD.

  METHOD expected_messages_452.

    result = `{"snapshotVersion":1,"session":"908D30A986074441893595DDC602A526","app":"Z2UI5_CL_SMP_APP_452","title":"abap2U` &&
             `I5 - Message - MessageView and MessagePopover","layer":"main","fields":[],"actions":[{"id":"a1","event":"POPUP` &&
             `","args":[],"label":"5","control":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen","layer":"ma` &&
             `in"},{"id":"a2","event":"POPOVER","args":[],"label":"Message Popover","control":"sap.m.Button","trigger":"pres` &&
             `s","enabled":true,"scope":"screen","layer":"main"}],"tables":[],"messages":[{"type":"info","text":"This free-s` &&
             `tyle demo combines the sap.m message controls: one bound message table is rendered three ways - as a full-page` &&
             ` MessageView with grouped items, inside a dialog and as a MessagePopover. It is not a 1:1 demo kit rebuild (th` &&
             `ose live in the samples-controls repository) and stays within the UI5 1.71 control set.","source":"strip"},{"t` &&
             `ype":"error","text":"Account 801 requires an assignment","source":"messageview","subtitle":"Role is invalid","` &&
             `description":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed d` &&
             `o eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitati` &&
             `on ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptat` &&
             `e velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in c` &&
             `ulpa qui officia deserunt mollit anim id est laborum."},{"type":"warning","text":"Account 821 requires a check` &&
             `","source":"messageview","subtitle":"Undefined task","description":"First Error message description. Lorem ips` &&
             `um dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna al` &&
             `iqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequ` &&
             `at. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Exc` &&
             `epteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."},` &&
             `{"type":"warning","text":"Enter a text with maximum 6 characters length","source":"messageview","description":` &&
             `"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tem` &&
             `por incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco la` &&
             `boris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse ` &&
             `cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui offi` &&
             `cia deserunt mollit anim id est laborum."},{"type":"warning","text":"Enter a text with maximum 8 characters le` &&
             `ngth","source":"messageview","description":"First Error message description. Lorem ipsum dolor sit amet, conse` &&
             `ctetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim v` &&
             `eniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolo` &&
             `r in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cup` &&
             `idatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."},{"type":"error","text":"` &&
             `Account 802 requires an assignment","source":"messageview","subtitle":"Role is invalid","description":"First E` &&
             `rror message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor inci` &&
             `didunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris ni` &&
             `si ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum d` &&
             `olore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia dese` &&
             `runt mollit anim id est laborum."},{"type":"info","text":"Account 804 requires an assignment","source":"messag` &&
             `eview","subtitle":"Information type subtitle","description":"First Error message description. Lorem ipsum dolo` &&
             `r sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. U` &&
             `t enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Dui` &&
             `s aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur ` &&
             `sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."},{"type"` &&
             `:"error","text":"Technical message without object relation","source":"messageview","description":"First Error ` &&
             `message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididun` &&
             `t ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut` &&
             ` aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore` &&
             ` eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt ` &&
             `mollit anim id est laborum."},{"type":"warning","text":"Global System will be down on Sunday","source":"messag` &&
             `eview","description":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing eli` &&
             `t, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud ex` &&
             `ercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in ` &&
             `voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, s` &&
             `unt in culpa qui officia deserunt mollit anim id est laborum."},{"type":"error","text":"Global System will be ` &&
             `down on Sunday","source":"messageview","description":"First Error message description. Lorem ipsum dolor sit a` &&
             `met, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ` &&
             `ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute ` &&
             `irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint oc` &&
             `caecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."},{"type":"error` &&
             `","text":"An Error","source":"messageview","subtitle":"Ungrouped message","description":"First Error message d` &&
             `escription. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labo` &&
             `re et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ` &&
             `ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugia` &&
             `t nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit an` &&
             `im id est laborum."},{"type":"warning","text":"A Warning","source":"messageview","subtitle":"Ungrouped message` &&
             `","description":"First Error message description. Lorem ipsum dolor sit amet, consectetur adipisicing elit, se` &&
             `d do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercit` &&
             `ation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in volup` &&
             `tate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt i` &&
             `n culpa qui officia deserunt mollit anim id est laborum."}],"texts":[],"unsupported":[]}`.

  ENDMETHOD.

  METHOD input_cgui_popover_07.

    " cgui-popover-07#2/rows20: cgui-popover-07#2/rows20 - recorded by abap2UI5/mcp-server test/fixtures/agent
    result-session = `1BAE966A76CC4CF8A5B8D79C696D3AC0`.
    result-app = `Z2UI5_CL_CGUI_R2C_07`.
    result-max_rows = 20.
    result-t_layer = VALUE #( ( layer = `MAIN`
                      xml   = `<mvc:View xmlns="sap.m" xmlns:mvc="sap.ui.core.mvc" xmlns:z2ui5="z2ui5.cc" displayBlock="true" height="100%"><` &&
                              `Page title="Z2UI5_CL_CGUI_R2C_07" showNavButton="true" navButtonPress=".eB(['CGUI_BACK'])"><z2ui5:Storage type` &&
                              `="local" prefix="z2ui5_cgui_variants" key="Z2UI5_CL_CGUI_R2C_07" value="{/MV_CGUI_VARIANTS}" finished=".eB(['C` &&
                              `GUI_VARIANTS_LOADED',false,false,false,true])"/><VBox class="sapUiSmallMargin"><HBox alignItems="Center"><Text` &&
                              ` text="Last message:" renderWhitespace="true" wrapping="false" class="sapUiTinyMarginEnd"/><Text text="Number ` &&
                              `42 processed" renderWhitespace="true" wrapping="false" class="sapUiTinyMarginEnd"/></HBox></VBox><footer><Over` &&
                              `flowToolbar><Button id="cgui_messages" icon="sap-icon://message-warning" type="Default" text="1" tooltip="Mess` &&
                              `ages" press=".eF('CONTROL_BY_ID', 'cgui_message_popover', '', 'toggleBy', 'cgui_messages')"/><ToolbarSpacer/><` &&
                              `Button text="Back" icon="sap-icon://nav-back" type="Emphasized" press=".eB(['CGUI_BACK'])"/></OverflowToolbar>` &&
                              `</footer><dependents><MessagePopover id="cgui_message_popover" placement="Top" activeTitlePress=".eB(['CGUI_ME` &&
                              `SSAGE_FOCUS'], ${$parameters&gt;/item})"><items><MessageItem id="cgui_msg_1" type="Warning" title="Number 42 i` &&
                              `s a warning" subtitle="" activeTitle="false"/></items></MessagePopover></dependents></Page></mvc:View>`
                      model = `{"MV_CGUI_VARIANTS":"","P_NUM":42,"P_TYPE":"W"}` ) ).
    result-t_custom = VALUE #( ( `["MESSAGE_TOAST","show","Number 42 processed"]` ) ( `["START_TIMER","CGUI_MESSAGES_OPEN","0","X"]` ) ).

  ENDMETHOD.

  METHOD expected_cgui_popover_07.

    result = `{"snapshotVersion":1,"session":"1BAE966A76CC4CF8A5B8D79C696D3AC0","app":"Z2UI5_CL_CGUI_R2C_07","title":"Z2UI5_` &&
             `CL_CGUI_R2C_07","layer":"main","fields":[],"actions":[{"id":"a1","event":"CGUI_BACK","args":[],"label":"Back",` &&
             `"control":"sap.m.Page","trigger":"navButtonPress","enabled":true,"scope":"screen","layer":"main"},{"id":"a2","` &&
             `event":"CGUI_VARIANTS_LOADED","args":[],"label":"finished","control":"z2ui5.cc.Storage","trigger":"finished","` &&
             `enabled":true,"scope":"screen","layer":"main"},{"id":"a3","event":"CGUI_BACK","args":[],"label":"Back","contro` &&
             `l":"sap.m.Button","trigger":"press","enabled":true,"scope":"screen","layer":"main"},{"id":"a4","event":"CGUI_M` &&
             `ESSAGE_FOCUS","args":["$parameters:item"],"label":"activeTitlePress","control":"sap.m.MessagePopover","trigger` &&
             `":"activeTitlePress","enabled":true,"scope":"screen","layer":"main"},{"id":"a5","event":"CGUI_MESSAGES_OPEN","` &&
             `args":[],"label":"timer (0 ms)","control":"timer","trigger":"timer","enabled":true,"scope":"screen","layer":"m` &&
             `ain"}],"tables":[],"messages":[{"type":"warning","text":"Number 42 is a warning","source":"popover"},{"type":"` &&
             `info","text":"Number 42 processed","source":"toast"}],"texts":["Last message:","Number 42 processed"],"unsuppo` &&
             `rted":["custom control z2ui5.cc.Storage (main: Page > Storage) - not described","frontend action CONTROL_BY_ID` &&
             `(\"cgui_message_popover\", \"\", \"toggleBy\", \"cgui_messages\") on Button \"1\" (main) - runs in the browser` &&
             ` only"]}`.

  ENDMETHOD.

ENDCLASS.
