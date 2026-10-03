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

ENDCLASS.
