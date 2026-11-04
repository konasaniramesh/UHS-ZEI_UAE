*&---------------------------------------------------------------------*
*& Report ZEI_UAE_INV_COCKPIT
*&---------------------------------------------------------------------*
*& UAE E-Invoice Cockpit - PINT AE (urn:peppol:pint:billing-1@ae-1)
*& - Builds the SBDH + UBL Invoice / CreditNote XML dynamically
*&   (no Simple Transformation is used)
*& - Submits the XML to the ASP (TOKEN -> POST) and tracks the
*&   5-corner status (C1 ... C5) via the status (GET) API until
*&   completion
*& Reference : ZEI_PROCESS_COCKPIT
*& Package   : ZEI_UAE
*&---------------------------------------------------------------------*
REPORT zei_uae_inv_cockpit.

INCLUDE zei_uae_inv_cockpit_top.
INCLUDE zei_uae_inv_cockpit_sel.
INCLUDE zei_uae_inv_cockpit_c01.
INCLUDE zei_uae_inv_cockpit_f01.

*&---------------------------------------------------------------------*
*& Class lcl_cockpit - HTML cockpit (replaces the ALV grid display)
*&---------------------------------------------------------------------*
*& Selection screen 1001 (include ZEI_UAE_INV_COCKPIT_SEL) hosts an
*& HTML viewer on the full screen area. The page sends SAPEVENTs:
*&   CHK                            - check box toggled (no round trip)
*&   SALL / DALL / REFRESH / SUBMIT - toolbar functions
*&   DOC / LOG / RESP / XML / HTML  - former ALV hotspots (i = row)
*& Client state (scroll, sort, filter, columns) is kept across renders
*&---------------------------------------------------------------------*
CLASS lcl_cockpit DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      pbo,
      pai IMPORTING iv_ucomm TYPE sy-ucomm,
      free,
      on_sapevent FOR EVENT sapevent OF cl_gui_html_viewer
        IMPORTING action query_table.

  PRIVATE SECTION.
    CONSTANTS: gc_okcode TYPE sy-ucomm VALUE 'ZHTMLEVT',
               gc_cols   TYPE string VALUE `11111111101001111111111`.

    CLASS-DATA: go_viewer TYPE REF TO cl_gui_html_viewer,
                gv_action TYPE string,
                gv_row    TYPE i,
                gv_scroll TYPE i,
                gv_xscrol TYPE i,
                gv_sort   TYPE i VALUE -1,
                gv_dir    TYPE i VALUE 1,
                gv_chip   TYPE string,
                gv_cols   TYPE string,
                gv_filter TYPE string.

    CLASS-METHODS:
      render,
      build_page RETURNING VALUE(rv) TYPE string,
      css        RETURNING VALUE(rv) TYPE string,
      script     RETURNING VALUE(rv) TYPE string,
      h   IMPORTING iv TYPE any
          RETURNING VALUE(rv) TYPE string,
      led IMPORTING iv_icon TYPE icon_d
          RETURNING VALUE(rv) TYPE string,
      amt IMPORTING iv_val TYPE any
                    iv_cur TYPE any
          RETURNING VALUE(rv) TYPE string,
      raw IMPORTING iv_val TYPE any
          RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_cockpit IMPLEMENTATION.

  METHOD pbo.
    DATA lt_excl TYPE STANDARD TABLE OF sy-ucomm.
    "Selection screen status without Execute / variant functions
    lt_excl = VALUE #( ( 'ONLI' ) ( 'PRIN' ) ( 'SPOS' ) ( 'SJOB' )
                       ( 'GET' ) ( 'VDEL' ) ( 'VSHO' ) ( 'LVUV' ) ( 'CRET' ) ).
    CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
      EXPORTING
        p_status  = sy-pfkey
      TABLES
        p_exclude = lt_excl.
    render( ).
  ENDMETHOD.

  METHOD pai.
    CHECK iv_ucomm EQ gc_okcode OR sy-ucomm EQ gc_okcode.
    DATA(lv_action) = gv_action.
    CLEAR gv_action.
    DATA(ls_sfield) = VALUE slis_selfield( tabindex = gv_row ).

    "Full screen displays: hide the cockpit (it covers the whole screen
    "area), it is shown again in the PBO when returning
    IF go_viewer IS BOUND AND ( lv_action EQ 'RESP' OR lv_action EQ 'HTML' OR
                                lv_action EQ 'HTMLSEL' OR lv_action EQ 'DOC' ).
      go_viewer->set_visible( EXPORTING visible = abap_false EXCEPTIONS OTHERS = 1 ).
    ENDIF.

    CASE lv_action.
      WHEN 'SALL'.    "Select all (open documents)
        lcl_app=>select_all( ).
      WHEN 'DALL'.    "Deselect all
        LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>) WHERE check EQ abap_true.
          <ls_out>-check = abap_false.
        ENDLOOP.
      WHEN 'REFRESH'. "Re-read from database
        lcl_app=>get_data( ).
      WHEN 'SUBMIT'.  "Submit / continue to completion
        lcl_app=>process( ).
      WHEN 'HTMLSEL'. "View as HTML (checked rows)
        CLEAR ls_sfield-tabindex.
        PERFORM display_html_selected USING ls_sfield.
      WHEN 'DOC'.
        ls_sfield-fieldname = 'SAPDOCUMENT'.
        PERFORM display_document USING ls_sfield.
      WHEN 'LOG'.
        ls_sfield-fieldname = 'CORNERLOG'.
        PERFORM display_messages USING ls_sfield.
      WHEN 'RESP'.
        ls_sfield-fieldname = 'RESPONSE'.
        PERFORM display_response USING ls_sfield.
      WHEN 'XML'.
        ls_sfield-fieldname = 'REQUEST'.
        PERFORM display_request USING ls_sfield.
      WHEN 'HTML'.
        PERFORM display_html USING gv_row.
    ENDCASE.
  ENDMETHOD.

  METHOD free.
    IF go_viewer IS BOUND.
      go_viewer->free( EXCEPTIONS OTHERS = 1 ).
      FREE go_viewer.
      cl_gui_cfw=>flush( EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD on_sapevent.
    DATA: lv_chk TYPE string,
          lv_web TYPE string.

    DATA(lv_action) = to_upper( action ).
    LOOP AT query_table INTO DATA(ls_query).
      DATA(lv_value) = condense( CONV string( ls_query-value ) ).
      TRY.
          CASE to_upper( ls_query-name ).
            WHEN 'I'. gv_row    = lv_value.
            WHEN 'V'. lv_chk    = lv_value.
            WHEN 'W'. lv_web    = lv_value.
            WHEN 'Y'. gv_scroll = lv_value.
            WHEN 'X'. gv_xscrol = lv_value.
            WHEN 'K'. gv_sort   = lv_value.
            WHEN 'D'. gv_dir    = lv_value.
            WHEN 'Q'. gv_chip   = lv_value.
            WHEN 'C'. gv_cols   = lv_value.
            WHEN 'F'. gv_filter = cl_http_utility=>unescape_url( escaped = CONV #( ls_query-value ) ).
          ENDCASE.
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDLOOP.

    "Check box: update the row only - the page is already up to date
    IF lv_action EQ 'CHK'.
      READ TABLE gt_output ASSIGNING FIELD-SYMBOL(<ls_out>) INDEX gv_row.
      IF sy-subrc EQ 0 AND <ls_out>-messagetype NE 'S'.
        <ls_out>-check = xsdbool( lv_chk EQ 'X' ).
      ENDIF.
      "SAP GUI for HTML reloads the last page after each event - render again
      IF lv_web EQ '1'.
        gv_action = lv_action.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      ENDIF.
      RETURN.
    ENDIF.

    "Any other action: process in PAI of screen 1001, then re-render
    gv_action = lv_action.
    cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
  ENDMETHOD.

  METHOD render.
    DATA: lv_url  TYPE c LENGTH 255,
          lv_size TYPE i.

    IF go_viewer IS NOT BOUND.
      CREATE OBJECT go_viewer
        EXPORTING
          parent = cl_gui_container=>screen0
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc NE 0.
        MESSAGE 'HTML viewer could not be created' TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      DATA lt_events TYPE cntl_simple_events.
      APPEND VALUE cntl_simple_event( eventid    = go_viewer->m_id_sapevent
                                      appl_event = abap_false ) TO lt_events.
      go_viewer->set_registered_events( EXPORTING events = lt_events
                                        EXCEPTIONS OTHERS = 1 ).
      SET HANDLER on_sapevent FOR go_viewer.
    ENDIF.
    go_viewer->set_visible( EXPORTING visible = abap_true EXCEPTIONS OTHERS = 1 ).

    "Character table (not binary): the HTML is then processed by the
    "SAP GUI / ITS HTML control, which wires the SAPEVENT links
    TYPES ty_line TYPE c LENGTH 255.
    DATA lt_data TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA(lv_html) = build_page( ).
    lv_size = strlen( lv_html ).
    DATA(lv_off) = 0.
    WHILE lv_off LT lv_size.
      DATA(lv_len) = nmin( val1 = 255 val2 = lv_size - lv_off ).
      APPEND lv_html+lv_off(lv_len) TO lt_data.
      lv_off = lv_off + lv_len.
    ENDWHILE.

    go_viewer->load_data( EXPORTING  type         = 'text'
                                     subtype      = 'html'
                                     size         = lv_size
                          IMPORTING  assigned_url = lv_url
                          CHANGING   data_table   = lt_data
                          EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc EQ 0.
      go_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD build_page.
    TYPES: BEGIN OF ty_col,
             label TYPE string,
             cls   TYPE string,
           END OF ty_col.
    DATA: lt_col   TYPE STANDARD TABLE OF ty_col WITH EMPTY KEY,
          lv_head  TYPE string,
          lv_menu  TYPE string,
          lv_rows  TYPE string,
          lv_hide  TYPE string,
          lv_empty TYPE string,
          lv_cnt   TYPE i,
          lv_ne    TYPE i,
          lv_nw    TYPE i,
          lv_ns    TYPE i,
          lv_np    TYPE i,
          lv_nsel  TYPE i.

    "Columns - same order / texts as the former ALV field catalog
    lt_col = VALUE #(
      ( label = `Check`                        cls = `c` )
      ( label = `Co.Code` )
      ( label = `Document` )
      ( label = `Year`                         cls = `r` )
      ( label = `Type` )
      ( label = `Doc.Type` )
      ( label = `E-Inv Type` )
      ( label = `Status`                       cls = `c` )
      ( label = `E-Invoice Status` )
      ( label = `E-Invoice Status (technical)` )
      ( label = `Peppol Corner`                cls = `c` )
      ( label = `Peppol Corner (text)` )
      ( label = `ASP Reference` )
      ( label = `Response`                     cls = `c` )
      ( label = `XML`                          cls = `c` )
      ( label = `HTML`                         cls = `c` )
      ( label = `Customer` )
      ( label = `Customer Name` )
      ( label = `Bus. Type` )
      ( label = `Currency` )
      ( label = `Net Value`                    cls = `r` )
      ( label = `VAT Amount`                   cls = `r` )
      ( label = `Total Value`                  cls = `r` ) ).

    "Sanitize client state
    IF NOT matches( val = gv_cols pcre = `[01]{23}` ).
      gv_cols = gc_cols.
    ENDIF.
    IF NOT matches( val = gv_chip pcre = `[EWSPX]?` ).
      CLEAR gv_chip.
    ENDIF.
    IF gv_dir NE -1.
      gv_dir = 1.
    ENDIF.
    IF gv_sort GE lines( lt_col ) OR gv_sort LT -1.
      gv_sort = -1.
    ENDIF.
    IF gv_scroll LT 0.
      gv_scroll = 0.
    ENDIF.
    IF gv_xscrol LT 0.
      gv_xscrol = 0.
    ENDIF.

    LOOP AT lt_col INTO DATA(ls_col).
      DATA(lv_k) = sy-tabix - 1.
      IF lv_k EQ 0.
        lv_head = lv_head && |<th class="c0 c">{ ls_col-label }</th>|.
      ELSE.
        lv_head = lv_head &&
          |<th class="c{ lv_k } { ls_col-cls }" onclick="srt({ lv_k })" title="Sort">{ ls_col-label }</th>|.
        lv_menu = lv_menu &&
          |<label><input type="checkbox" id="k{ lv_k }" onclick="tog({ lv_k },this.checked)">{ ls_col-label }</label>|.
      ENDIF.
      lv_hide = lv_hide && |table.h{ lv_k } .c{ lv_k }\{display:none\}|.
    ENDLOOP.

    LOOP AT gt_output INTO DATA(ls_out).
      DATA(lv_i) = sy-tabix.
      DATA(lv_m) = SWITCH string( ls_out-messagetype WHEN 'E' THEN `E`
                                                     WHEN 'W' THEN `W`
                                                     WHEN 'S' THEN `S`
                                                     ELSE `P` ).
      CASE lv_m.
        WHEN `E`.    lv_ne = lv_ne + 1.
        WHEN `W`.    lv_nw = lv_nw + 1.
        WHEN `S`.    lv_ns = lv_ns + 1.
        WHEN OTHERS. lv_np = lv_np + 1.
      ENDCASE.
      IF ls_out-check EQ abap_true.
        lv_nsel = lv_nsel + 1.
      ENDIF.

      DATA(lv_rank) = SWITCH string( lv_m WHEN `E` THEN `1` WHEN `W` THEN `2`
                                          WHEN `P` THEN `3` ELSE `4` ).
      "Completed documents cannot be selected (former ALV cell style)
      DATA(lv_cb) = COND string( WHEN ls_out-check EQ abap_true THEN ` checked` ) &&
                    COND string( WHEN lv_m EQ `S` THEN ` disabled` ).
      DATA(lv_tr) = COND string( WHEN ls_out-check EQ abap_true THEN ` class="sel"` ).

      "Peppol corner C1..C5 progress (former icon + quick info)
      DATA(lv_bar) =
        |<i class="{ led( ls_out-c1 ) }"></i><i class="{ led( ls_out-c2 ) }"></i>| &&
        |<i class="{ led( ls_out-c3 ) }"></i><i class="{ led( ls_out-c4 ) }"></i>| &&
        |<i class="{ led( ls_out-c5 ) }"></i>|.

      DATA(lv_resp) = COND string( WHEN ls_out-responsepayload IS NOT INITIAL THEN
        |<a class="pill" title="Display the last ASP response" onclick="row('RESP',{ lv_i })">View</a>| ).
      DATA(lv_xml) = COND string( WHEN ls_out-requestpayload IS NOT INITIAL
        THEN |<a class="pill" title="Display the PINT AE XML" onclick="row('XML',{ lv_i })">XML</a>|
        ELSE |<a class="pill pv" title="Preview the PINT AE XML (not yet submitted)" onclick="row('XML',{ lv_i })">Preview</a>| ).

      lv_rows = lv_rows &&
        |<tr data-i="{ lv_i }" data-m="{ lv_m }"{ lv_tr }>| &&
        |<td class="c0 c"><input type="checkbox" onclick="chk(this,{ lv_i })"{ lv_cb }></td>| &&
        |<td class="c1">{ h( ls_out-companycode ) }</td>| &&
        |<td class="c2"><a class="lk" title="Display billing document" onclick="row('DOC',{ lv_i })">| &&
        |{ ls_out-sapdocument ALPHA = OUT }</a></td>| &&
        |<td class="c3 r">{ h( ls_out-fiscalyear ) }</td>| &&
        |<td class="c4">{ h( ls_out-typename ) }</td>| &&
        |<td class="c5">{ h( ls_out-documenttype ) }</td>| &&
        |<td class="c6">{ h( ls_out-einvoicetype ) }</td>| &&
        |<td class="c7 c" data-s="{ lv_rank }"><span class="dot { led( ls_out-status ) }" title="{ h( ls_out-stattext ) }"></span></td>| &&
        |<td class="c8">{ h( ls_out-stattext ) }</td>| &&
        |<td class="c9">{ h( ls_out-einvoicestatus ) }</td>| &&
        |<td class="c10 c" data-s="{ h( ls_out-corner ) }"><span class="cn" title="{ h( ls_out-corner ) } - click for processing log"| &&
        | onclick="row('LOG',{ lv_i })">{ lv_bar }</span></td>| &&
        |<td class="c11"><a class="lk" onclick="row('LOG',{ lv_i })">{ h( ls_out-corner ) }</a></td>| &&
        |<td class="c12">{ h( ls_out-referenceid ) }</td>| &&
        |<td class="c13 c">{ lv_resp }</td>| &&
        |<td class="c14 c">{ lv_xml }</td>| &&
        |<td class="c15 c"><a class="pill" title="View as HTML" onclick="row('HTML',{ lv_i })">View</a></td>| &&
        |<td class="c16">{ h( |{ ls_out-customer ALPHA = OUT }| ) }</td>| &&
        |<td class="c17">{ h( ls_out-customername ) }</td>| &&
        |<td class="c18">{ h( ls_out-businesstype ) }</td>| &&
        |<td class="c19">{ h( ls_out-currency ) }</td>| &&
        |<td class="c20 r" data-s="{ raw( ls_out-netvalue ) }">{ amt( iv_val = ls_out-netvalue iv_cur = ls_out-currency ) }</td>| &&
        |<td class="c21 r" data-s="{ raw( ls_out-taxvalue ) }">{ amt( iv_val = ls_out-taxvalue iv_cur = ls_out-currency ) }</td>| &&
        |<td class="c22 r" data-s="{ raw( ls_out-totalvalue ) }">{ amt( iv_val = ls_out-totalvalue iv_cur = ls_out-currency ) }</td>| &&
        |</tr>|.
    ENDLOOP.

    lv_cnt = lines( gt_output ).
    IF lv_cnt EQ 0.
      lv_empty = |<div class="mt">No documents found for the selection.</div>|.
    ENDIF.


    "Client state as JS literal
    DATA(lv_f) = replace( val = gv_filter pcre = `[[:cntrl:]]` with = `` occ = 0 ).
    REPLACE ALL OCCURRENCES OF '\' IN lv_f WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_f WITH '\"'.
    REPLACE ALL OCCURRENCES OF '<' IN lv_f WITH '<'.
    DATA(lv_state) =
      |var ST=\{y:{ gv_scroll },x:{ gv_xscrol },k:{ gv_sort },d:{ gv_dir },q:"{ gv_chip }",c:"{ gv_cols }",f:"{ lv_f }"\};|.

    rv =
      |{ gc_html_head }{ gc_scroll_css }{ css( ) }{ lv_hide }</style></head><body>| &&
      |<div id="hd">| &&
      |<div class="bar">| &&
      |<button class="btn" onclick="act('SALL')" title="Select all open documents">Select All</button>| &&
      |<button class="btn" onclick="act('DALL')" title="Deselect all documents">Deselect All</button>| &&
      |<button class="btn" onclick="act('REFRESH',1)" title="Re-read from the database">Refresh</button>| &&
      |<button class="btn pri" onclick="act('SUBMIT',1)" title="Submit / continue the selected documents to completion">Submit</button>| &&
      |<span class="sp"></span>| &&
      |<input id="q" class="srch" type="text" placeholder="Search" oninput="ST.f=this.value;flt()" onkeyup="ST.f=this.value;flt()">| &&
      |<span class="wrap"><button class="btn" onclick="cmt(event)">Columns</button><div id="cm">{ lv_menu }</div></span>| &&
      |</div><div class="chips">| &&
      |<span class="chip" data-q="" onclick="chip('')">All<b>{ lv_cnt }</b></span>| &&
      |<span class="chip" data-q="E" onclick="chip('E')"><span class="dot ko"></span>Error<b>{ lv_ne }</b></span>| &&
      |<span class="chip" data-q="W" onclick="chip('W')"><span class="dot wt"></span>In process<b>{ lv_nw }</b></span>| &&
      |<span class="chip" data-q="S" onclick="chip('S')"><span class="dot ok"></span>Success<b>{ lv_ns }</b></span>| &&
      |<span class="chip" data-q="P" onclick="chip('P')"><span class="dot na"></span>Pending<b>{ lv_np }</b></span>| &&
      |<span class="chip" data-q="X" onclick="chip('X')" title="Show selected documents"><span class="dot sl"></span>Selected<b id="nsel">{ lv_nsel }</b></span>| &&
      |</div></div>| &&
      |<div id="scr"><table id="tbl"><thead><tr id="th">{ lv_head }</tr></thead>| &&
      |<tbody id="tb">{ lv_rows }</tbody></table>{ lv_empty }</div>| &&
      |<div id="busy"><div>Processing, please wait...</div></div>| &&
      |<a id="sapev" href="SAPEVENT:NONE" style="display:none"></a>| &&
      |<script>{ lv_state }{ script( ) }</script></body></html>|.
  ENDMETHOD.

  METHOD css.
    rv =
      `*{box-sizing:border-box}` &&
      `body{font-family:"72","72full",Arial,Helvetica,sans-serif;font-size:13px;color:#1d2d3e;background:#f5f6f7}` &&
      `#hd{position:absolute;top:0;left:0;right:0;background:#fff;border-bottom:1px solid #d9d9d9;padding:10px 16px 8px;z-index:3}` &&
      `.ttl{font-size:16px;font-weight:700}.sub{color:#556b82;font-size:12px;margin-top:2px}` &&
      `.bar{display:flex;flex-wrap:wrap;align-items:center}.bar>*{margin:0 6px 4px 0}` &&
      `.btn{font:inherit;height:28px;border:1px solid #bcc3ca;background:#fff;color:#0064d9;border-radius:6px;padding:0 12px;cursor:pointer}` &&
      `.btn:hover{background:#eaecee}.btn.pri{background:#0070f2;border-color:#0070f2;color:#fff}.btn.pri:hover{background:#0064d9}` &&
      `.sp{flex:1}.srch{font:inherit;height:28px;width:220px;border:1px solid #bcc3ca;border-radius:6px;padding:0 8px}` &&
      `.wrap{position:relative;display:inline-block}` &&
      `#cm{display:none;position:absolute;right:0;top:32px;background:#fff;border:1px solid #d9d9d9;border-radius:8px;` &&
      `padding:6px;box-shadow:0 4px 16px rgba(0,0,0,.15);z-index:5;max-height:360px;overflow:auto}` &&
      `#cm label{display:block;padding:3px 6px;white-space:nowrap;cursor:pointer}#cm input{margin-right:6px}` &&
      `.chips{display:flex;flex-wrap:wrap;margin-top:4px}` &&
      `.chip{margin:0 6px 2px 0;border:1px solid #d9d9d9;border-radius:14px;padding:2px 10px;cursor:pointer;background:#fff;font-size:12px}` &&
      `.chip b{margin-left:6px}.chip .dot{margin-right:5px;width:8px;height:8px}.chip:hover{border-color:#0070f2}` &&
      `.chip.on{background:#0070f2;border-color:#0070f2;color:#fff}` &&
      `#scr{top:120px;padding:12px 16px 16px}` &&
      `table{border-collapse:separate;border-spacing:0;width:100%;background:#fff;border:1px solid #d9d9d9;border-radius:8px}` &&
      `th{position:sticky;top:-12px;background:#f5f6f7;color:#556b82;font-weight:600;text-align:left;padding:7px 8px;` &&
      `border-bottom:1px solid #d9d9d9;white-space:nowrap;cursor:pointer;z-index:1}` &&
      `th.c0{cursor:default}th:hover{color:#1d2d3e}th.asc:after{content:" \25B2";font-size:9px}th.desc:after{content:" \25BC";font-size:9px}` &&
      `td{padding:6px 8px;border-bottom:1px solid #eef0f2;white-space:nowrap;vertical-align:middle}` &&
      `tbody tr:hover td{background:#f0f7ff}tr.sel td{background:#e5f0fe}` &&
      `.r{text-align:right}th.r{text-align:right}.c{text-align:center}th.c{text-align:center}` &&
      `a.lk{color:#0064d9;text-decoration:none;cursor:pointer}a.lk:hover{text-decoration:underline}` &&
      `.dot{display:inline-block;width:10px;height:10px;border-radius:50%;vertical-align:middle}` &&
      `.dot.ok{background:#188918}.dot.ko{background:#d20a0a}.dot.wt{background:#e76500}` &&
      `.dot.na{background:transparent;border:1px solid #a9b4be}.dot.sl{background:#0070f2}.chip.on .dot.sl{background:#fff}` &&
      `.cn{display:inline-block;cursor:pointer;padding:3px;border-radius:4px;white-space:nowrap}.cn:hover{background:#e5f0fe}` &&
      `.cn i{display:inline-block;width:10px;height:10px;margin:0 1px;border-radius:2px;background:#d5dadd}` &&
      `.cn i.ok{background:#188918}.cn i.ko{background:#d20a0a}.cn i.wt{background:#e76500}` &&
      `.pill{display:inline-block;font-size:11px;font-weight:600;padding:1px 9px;border-radius:10px;border:1px solid #0064d9;` &&
      `color:#0064d9;cursor:pointer;text-decoration:none}.pill:hover{background:#0064d9;color:#fff}.pill.pv{border-style:dashed}` &&
      `.mt{color:#556b82;text-align:center;padding:24px}` &&
      `#busy{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(255,255,255,.6);z-index:9}` &&
      `#busy div{position:absolute;top:40%;left:50%;margin-left:-110px;width:220px;text-align:center;background:#fff;` &&
      `border:1px solid #d9d9d9;border-radius:8px;padding:12px;box-shadow:0 4px 16px rgba(0,0,0,.15)}`.
  ENDMETHOD.

  METHOD script.
    rv =
      `function $(i){return document.getElementById(i);}` &&
      `function trs(){return $('tb').rows;}` &&
      `function sap(a){if(window.parent&&window.parent!==window){window.parent.postMessage(JSON.stringify(` &&
      `{type:'request',service:'sap.gui.triggerSAPEvent',request_id:'ev'+(new Date()).getTime(),body:{args:{action:a}}}),'*');}` &&
      `else{var l=$('sapev');l.href='SAP'+'EVENT:'+a;l.click();}}` &&
      `function ev(a,p){var s=$('scr');` &&
      `var q='y='+(s?s.scrollTop:0)+'&x='+(s?s.scrollLeft:0)+'&k='+ST.k+'&d='+ST.d+'&q='+ST.q+'&c='+ST.c+'&f='+encodeURIComponent(ST.f);` &&
      `sap(a+'?'+(p?p+'&':'')+q);}` &&
      `function act(a,b){if(b)$('busy').style.display='block';ev(a,'');}` &&
      `function row(a,i){ev(a,'i='+i);}` &&
      `function chk(c,i){var p='i='+i+'&v='+(c.checked?'X':'');` &&
      `if(window.parent&&window.parent!==window)ev('CHK',p+'&w=1');else sap('CHK?'+p);` &&
      `c.parentNode.parentNode.className=c.checked?'sel':'';cnt();if(ST.q=='X')flt();}` &&
      `function cnt(){var n=0,r=trs();for(var i=0;r.length>i;i++){var c=r[i].cells[0].firstChild;if(c&&c.checked)n++;}` &&
      `var e=$('nsel');if(e)e.innerHTML=n;}` &&
      `function flt(){var f=(ST.f||'').toLowerCase(),r=trs(),n=0,i;for(i=0;r.length>i;i++){` &&
      `var t=(r[i].innerText||r[i].textContent||'').toLowerCase();` &&
      `var ok=(!ST.q||(ST.q=='X'?r[i].cells[0].firstChild.checked:r[i].getAttribute('data-m')==ST.q))&&(!f||t.indexOf(f)>=0);r[i].style.display=ok?'':'none';if(ok)n++;}` &&
      `var e=$('vis');if(e)e.innerHTML=n;var h=document.getElementsByTagName('span');for(i=0;h.length>i;i++){` &&
      `if(h[i].className.indexOf('chip')==0)h[i].className=(h[i].getAttribute('data-q')==ST.q)?'chip on':'chip';}}` &&
      `function chip(q){ST.q=q;flt();}` &&
      `function key(r,k){var c=r.cells[k];if(!c)return '';var v=c.getAttribute('data-s');` &&
      `if(v===null)v=(c.innerText||c.textContent||'');v=v.replace(/^\s+|\s+$/g,'');` &&
      `if(v!==''&&!isNaN(v))return parseFloat(v);return v.toLowerCase();}` &&
      `function dosort(){var h=$('th').cells,i;for(i=0;h.length>i;i++)` &&
      `h[i].className=h[i].className.replace(/ (asc|desc)/g,'')+(i==ST.k?(ST.d>0?' asc':' desc'):'');` &&
      `if(1>ST.k)return;var tb=$('tb'),r=tb.rows,a=[];for(i=0;r.length>i;i++)a.push(r[i]);` &&
      `a.sort(function(x,y){var p=key(x,ST.k),q=key(y,ST.k);if(typeof p!=typeof q){p=String(p);q=String(q);}` &&
      `return (q>p?-1:p>q?1:0)*ST.d||(x.getAttribute('data-i')-y.getAttribute('data-i'));});` &&
      `for(i=0;a.length>i;i++)tb.appendChild(a[i]);}` &&
      `function srt(k){if(ST.k==k)ST.d=-ST.d;else{ST.k=k;ST.d=1;}dosort();}` &&
      `function cols(){var c='';for(var k=0;ST.c.length>k;k++){var on=ST.c.charAt(k)=='1';if(!on)c+=' h'+k;` &&
      `var b=$('k'+k);if(b)b.checked=on;}$('tbl').className=c;}` &&
      `function tog(k,on){ST.c=ST.c.substr(0,k)+(on?'1':'0')+ST.c.substr(k+1);cols();}` &&
      `function cmt(e){var m=$('cm');m.style.display=m.style.display=='block'?'none':'block';` &&
      `e=e||window.event;if(e){e.cancelBubble=true;if(e.stopPropagation)e.stopPropagation();}}` &&
      `document.onclick=function(e){e=e||window.event;var t=e.target||e.srcElement,m=$('cm');` &&
      `while(t){if(t==m)return;t=t.parentNode;}if(m)m.style.display='none';};` &&
      `function lay(){$('scr').style.top=$('hd').offsetHeight+'px';}` &&
      `window.onresize=lay;` &&
      `function ini(){lay();$('q').value=ST.f;cols();dosort();flt();cnt();$('scr').scrollTop=ST.y;$('scr').scrollLeft=ST.x;}ini();` &&
      `if(window.addEventListener)window.addEventListener('load',lay);`.
  ENDMETHOD.

  METHOD h.
    rv = escape( val = condense( |{ iv }| ) format = cl_abap_format=>e_html_attr ).
  ENDMETHOD.

  METHOD led.
    rv = COND #( WHEN iv_icon EQ icon_led_green  THEN `ok`
                 WHEN iv_icon EQ icon_led_red    THEN `ko`
                 WHEN iv_icon EQ icon_led_yellow THEN `wt`
                 ELSE `na` ).
  ENDMETHOD.

  METHOD amt.
    DATA: lv_p   TYPE p LENGTH 16 DECIMALS 2,
          lv_cur TYPE waers.
    lv_cur = iv_cur.
    TRY.
        lv_p = iv_val.
        rv = |{ lv_p CURRENCY = lv_cur NUMBER = USER }|.
      CATCH cx_root.
        rv = |{ lv_p NUMBER = USER }|.
    ENDTRY.
  ENDMETHOD.

  METHOD raw.
    DATA lv_p TYPE p LENGTH 16 DECIMALS 2.
    TRY.
        lv_p = iv_val.
      CATCH cx_root.
        CLEAR lv_p.
    ENDTRY.
    rv = |{ lv_p NUMBER = RAW }|.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Class lcl_selscreen - HTML selection screen (screen 1000)
*&---------------------------------------------------------------------*
*& The standard selection screen 1000 is unchanged underneath, so
*& variants, background jobs, print parameters and SUBMIT ... WITH keep
*& working. In dialog an HTML viewer covers the screen area and shows the
*& same selection fields. The page sends SAPEVENTs:
*&   SYNC            - an entry was changed
*&   GO / BG / VSAVE - Execute / Execute in background / Save variant
*&   F4 / VHGO       - HTML value help of the documents (open / search)
*&   XA              - remove the variant conditions not shown on the page
*& The entries are moved into the selection fields in AT SELECTION-SCREEN
*& (after the screen field transport), i.e. before any standard function
*& (execute, variants, background, print) is processed.
*& Conditions the page cannot show (e.g. exclusions from a variant) are
*& kept unchanged unless they are removed explicitly.
*&---------------------------------------------------------------------*
CLASS lcl_selscreen DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      pbo,
      pai IMPORTING iv_ucomm TYPE sy-ucomm,
      hide,
      free,
      on_sapevent FOR EVENT sapevent OF cl_gui_html_viewer
        IMPORTING action query_table.

  PRIVATE SECTION.
    CONSTANTS gc_okcode TYPE sy-ucomm VALUE 'ZSELEVT'.

    TYPES: BEGIN OF ty_kv,
             name  TYPE string,
             value TYPE string,
           END OF ty_kv,
           tt_kv TYPE STANDARD TABLE OF ty_kv WITH EMPTY KEY,
           ty_r_vbeln TYPE RANGE OF vbrk-vbeln,
           "Restrictions of the document value help (kept for the session)
           BEGIN OF ty_vh,
             doc   TYPE string,
             from  TYPE string,
             to    TYPE string,
             kunag TYPE string,
             fkart TYPE string,
             max   TYPE i,
           END OF ty_vh,
           BEGIN OF ty_comp,
             bukrs TYPE bukrs,
             butxt TYPE string,
           END OF ty_comp,
           "Execute in Background of the page (start immediately / date + time)
           BEGIN OF ty_bg,
             imm  TYPE abap_bool,
             date TYPE string,
             time TYPE string,
           END OF ty_bg.

    CLASS-DATA: go_viewer TYPE REF TO cl_gui_html_viewer,
                gt_input  TYPE tt_kv,
                gv_focus  TYPE string,
                gv_error  TYPE string,
                gv_go     TYPE abap_bool,
                gv_std    TYPE sy-ucomm,      "standard function of the page (SPOS)
                gv_bg     TYPE abap_bool,     "Execute in Background requested
                gs_bg     TYPE ty_bg,
                gv_vh     TYPE abap_bool,     "value help requested (F4 / Go)
                gv_vh_on  TYPE abap_bool,     "value help shown in this render
                gv_vh_dat TYPE string,        "result rows (compact, see VH_SEARCH)
                gv_vh_inf TYPE string,        "info / error of the value help
                gs_vh     TYPE ty_vh,
                gt_vh_sel TYPE string_table,  "documents ticked in the value help
                gt_comp   TYPE STANDARD TABLE OF ty_comp WITH EMPTY KEY.

    CLASS-METHODS:
      render,
      vh_search,
      vh_html RETURNING VALUE(rv) TYPE string,
      parse_docs IMPORTING it_tokens TYPE string_table
                 EXPORTING et_range  TYPE ty_r_vbeln
                           ev_error  TYPE string,
      apply RETURNING VALUE(rv_error) TYPE string,
      schedule EXPORTING ev_error TYPE string
                         ev_info  TYPE string,
      build_page RETURNING VALUE(rv) TYPE string,
      css RETURNING VALUE(rv) TYPE string,
      script RETURNING VALUE(rv) TYPE string,
      h IMPORTING iv TYPE any
        RETURNING VALUE(rv) TYPE string,
      label IMPORTING iv_name    TYPE string
                      iv_default TYPE string
            RETURNING VALUE(rv)  TYPE string,
      listbox IMPORTING iv_value  TYPE any
              RETURNING VALUE(rv) TYPE string,
      chip IMPORTING iv_code   TYPE string
                     iv_text   TYPE string
                     iv_cls    TYPE string
                     iv_sel    TYPE string
           RETURNING VALUE(rv) TYPE string,
      adv_note IMPORTING iv_key   TYPE string
                         iv_count TYPE i
               RETURNING VALUE(rv) TYPE string,
      to_iso IMPORTING iv_date   TYPE d
             RETURNING VALUE(rv) TYPE string,
      parse_date IMPORTING iv      TYPE string
                 EXPORTING ev_date TYPE d
                           ev_ok   TYPE abap_bool,
      doc_in IMPORTING iv        TYPE string
             RETURNING VALUE(rv) TYPE vbrk-vbeln,
      doc_out IMPORTING iv        TYPE vbrk-vbeln
              RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_selscreen IMPLEMENTATION.

  METHOD pbo.
    "Classic screen (fallback without GUI controls): Company Code is
    "still shown as required entry - the check itself is done in PAI
    LOOP AT SCREEN INTO DATA(ls_screen).
      IF ls_screen-name EQ 'S_BUKRS-LOW'.
        ls_screen-required = '2'.
        MODIFY SCREEN FROM ls_screen.
      ENDIF.
    ENDLOOP.

    CHECK sy-batch EQ abap_false AND cl_gui_alv_grid=>offline( ) IS INITIAL.
    render( ).

    IF go_viewer IS BOUND.
      "The page replaces the standard fields: deactivate them, so they are
      "never drawn while the page is (re)loading (e.g. back from the cockpit)
      LOOP AT SCREEN INTO ls_screen.
        ls_screen-active = '0'.
        MODIFY SCREEN FROM ls_screen.
      ENDLOOP.

      "Execute is offered on the page (button Execute / Enter) - not in the toolbar
      DATA lt_excl TYPE STANDARD TABLE OF sy-ucomm WITH EMPTY KEY.
      lt_excl = VALUE #( ( 'ONLI' ) ).
      CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
        EXPORTING
          p_status  = sy-pfkey
        TABLES
          p_exclude = lt_excl.
    ENDIF.
  ENDMETHOD.

  METHOD pai.
    "Execute of the page (the function ONLI is not in the toolbar)
    "Execute in Background / Save as Variant are sent with the OK code of the
    "page as well and mapped here to SJOB / SPOS (same path as Execute)
    DATA(lv_ucomm) = COND sy-ucomm( WHEN iv_ucomm EQ gc_okcode AND gv_go EQ abap_true
                                    THEN 'ONLI'
                                    WHEN iv_ucomm EQ gc_okcode AND gv_std IS NOT INITIAL
                                    THEN gv_std
                                    ELSE iv_ucomm ).
    DATA(lv_vh) = gv_vh.
    DATA(lv_bg) = gv_bg.
    CLEAR: gv_go, gv_vh, gv_std, gv_bg.

    "Entries of the HTML page -> selection fields
    DATA(lv_error) = apply( ).
    gv_error = lv_error.
    IF lv_error IS NOT INITIAL.
      MESSAGE lv_error TYPE 'E'.
    ENDIF.

    "Company Code is a required entry (former addition OBLIGATORY)
    IF ( lv_ucomm EQ 'ONLI' OR lv_ucomm EQ 'PRIN' OR lv_ucomm EQ 'SJOB' OR lv_bg EQ abap_true ) AND
       s_bukrs[] IS INITIAL.
      gv_error = 'Fill in all required entry fields'.
      MESSAGE e055(00).
    ENDIF.

    "Execute in Background of the page: the job is scheduled directly (no
    "SAP dialog box on top of the HTML control - see SCHEDULE)
    IF lv_bg EQ abap_true.
      schedule( IMPORTING ev_error = DATA(lv_bg_error)
                          ev_info  = DATA(lv_bg_info) ).
      IF lv_bg_error IS NOT INITIAL.
        gv_error = lv_bg_error.
        MESSAGE lv_bg_error TYPE 'E'.
      ENDIF.
      MESSAGE lv_bg_info TYPE 'S'.
    ENDIF.

    "Value help of the documents (HTML dialog, shown with the next render)
    IF lv_vh EQ abap_true.
      vh_search( ).
    ENDIF.

    IF lv_ucomm NE iv_ucomm.
      sscrfields-ucomm = lv_ucomm.
    ENDIF.

    "Standard functions (execute, variants, print / background parameters)
    "open their own screens: hide the page, it is shown again in the PBO
    IF lv_ucomm NE gc_okcode.
      hide( ).
      "the page is hidden on the front end before the standard dialog is sent
      cl_gui_cfw=>flush( EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD schedule.
    "Execute in Background of the page. The job is scheduled here with the
    "same job name, program and selection values as the standard function
    "SJOB - but without the SAP dialog boxes (print parameters / start time),
    "which SAP GUI for Windows does not show on top of the HTML control (the
    "page stayed on 'Processing'). Print parameters are not needed: in
    "background the result is written to the job log (form WRITE_LIST).
    DATA: lt_params   TYPE STANDARD TABLE OF rsparams WITH EMPTY KEY,
          lv_jobname  TYPE tbtcjob-jobname,
          lv_jobcount TYPE tbtcjob-jobcount,
          lv_released TYPE btcchar1,
          lv_date     TYPE d,
          lv_time     TYPE t,
          lv_ok       TYPE abap_bool,
          lv_tm       TYPE string.

    CLEAR: ev_error, ev_info.

    "Start at date / time: check the entries
    IF gs_bg-imm EQ abap_false.
      parse_date( EXPORTING iv = gs_bg-date IMPORTING ev_date = lv_date ev_ok = lv_ok ).
      lv_tm = gs_bg-time.
      REPLACE ALL OCCURRENCES OF ':' IN lv_tm WITH ''.
      CONDENSE lv_tm NO-GAPS.
      IF strlen( lv_tm ) EQ 3.
        lv_tm = `0` && lv_tm.
      ENDIF.
      IF strlen( lv_tm ) EQ 4.
        lv_tm = lv_tm && `00`.
      ENDIF.
      IF lv_ok EQ abap_false OR lv_date IS INITIAL OR strlen( lv_tm ) NE 6 OR lv_tm CN '0123456789' OR
         lv_tm(2) GT '23' OR lv_tm+2(2) GT '59'.
        ev_error = 'Enter a valid start date and time'.
        RETURN.
      ENDIF.
      lv_time = lv_tm.
      IF lv_date LT sy-datum OR ( lv_date EQ sy-datum AND lv_time LT sy-uzeit ).
        ev_error = 'The start date / time is in the past'.
        RETURN.
      ENDIF.
    ENDIF.

    "Current entries of the selection screen (set from the page by APPLY)
    CALL FUNCTION 'RS_REFRESH_FROM_SELECTOPTIONS'
      EXPORTING
        curr_report     = sy-repid
      TABLES
        selection_table = lt_params
      EXCEPTIONS
        OTHERS          = 1.
    IF sy-subrc NE 0.
      ev_error = 'The selection could not be read for the background job'.
      RETURN.
    ENDIF.

    lv_jobname = sy-repid.
    CALL FUNCTION 'JOB_OPEN'
      EXPORTING
        jobname  = lv_jobname
      IMPORTING
        jobcount = lv_jobcount
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc NE 0.
      ev_error = 'The background job could not be created'.
      RETURN.
    ENDIF.

    DATA(lv_prog) = sy-repid.
    SUBMIT (lv_prog) WITH SELECTION-TABLE lt_params
                     VIA JOB lv_jobname NUMBER lv_jobcount
                     AND RETURN.
    IF sy-subrc NE 0.
      ev_error = |The program could not be added to the background job { lv_jobname } { lv_jobcount }|.
      RETURN.
    ENDIF.

    IF gs_bg-imm EQ abap_true.
      CALL FUNCTION 'JOB_CLOSE'
        EXPORTING
          jobcount             = lv_jobcount
          jobname              = lv_jobname
          strtimmed            = abap_true
        IMPORTING
          job_was_released     = lv_released
        EXCEPTIONS
          cant_start_immediate = 1
          OTHERS               = 2.
    ELSE.
      CALL FUNCTION 'JOB_CLOSE'
        EXPORTING
          jobcount             = lv_jobcount
          jobname              = lv_jobname
          sdlstrtdt            = lv_date
          sdlstrttm            = lv_time
        IMPORTING
          job_was_released     = lv_released
        EXCEPTIONS
          OTHERS               = 2.
    ENDIF.
    CASE sy-subrc.
      WHEN 0.
      WHEN 1.
        ev_error = 'No background work process is free at the moment - choose a start date / time'.
        RETURN.
      WHEN OTHERS.
        ev_error = |The background job { lv_jobname } { lv_jobcount } could not be scheduled|.
        RETURN.
    ENDCASE.

    IF lv_released EQ abap_false.
      ev_info = |Background job { lv_jobname } { lv_jobcount } created - not released (authorization), release it in SM37|.
    ELSEIF gs_bg-imm EQ abap_true.
      ev_info = |Background job { lv_jobname } { lv_jobcount } started - result in SM37 (job log)|.
    ELSE.
      ev_info = |Background job { lv_jobname } { lv_jobcount } scheduled for { lv_date DATE = USER } { lv_time TIME = USER }|.
    ENDIF.
  ENDMETHOD.

  METHOD hide.
    "The page is kept (not freed): when the selection screen is shown again
    "it is made visible at once instead of being created anew
    IF go_viewer IS BOUND.
      go_viewer->set_visible( EXPORTING visible = abap_false EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD free.
    IF go_viewer IS BOUND.
      go_viewer->free( EXCEPTIONS OTHERS = 1 ).
      FREE go_viewer.
      cl_gui_cfw=>flush( EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD on_sapevent.
    DATA lv_web TYPE string.

    "The page always sends all changed entries (since the last render)
    CLEAR: gt_input, gt_vh_sel, gs_bg.
    LOOP AT query_table INTO DATA(ls_query).
      DATA(lv_name) = to_upper( condense( CONV string( ls_query-name ) ) ).
      DATA(lv_value) = CONV string( ls_query-value ).
      TRY.
          lv_value = cl_http_utility=>unescape_url( escaped = lv_value ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
      CASE lv_name.
        WHEN 'W'.
          lv_web = lv_value.
        WHEN 'FO'.
          gv_focus = lv_value.
        "Start of the background job
        WHEN 'BI'.
          gs_bg-imm = abap_true.
        WHEN 'BD'.
          gs_bg-date = lv_value.
        WHEN 'BM'.
          gs_bg-time = lv_value.
        "Restrictions of the value help
        WHEN 'VD'.
          gs_vh-doc = lv_value.
        WHEN 'VF'.
          gs_vh-from = lv_value.
        WHEN 'VT'.
          gs_vh-to = lv_value.
        WHEN 'VK'.
          gs_vh-kunag = lv_value.
        WHEN 'VB'.
          gs_vh-fkart = lv_value.
        WHEN 'VM'.
          gs_vh-max = COND #( WHEN condense( lv_value ) CO '0123456789' AND lv_value IS NOT INITIAL
                              THEN condense( lv_value ) ELSE 0 ).
        WHEN OTHERS.
          IF lv_name CP 'VS*'.             "ticked documents (VS0, VS1, ...)
            APPEND lv_value TO gt_vh_sel.
          ELSE.
            APPEND VALUE #( name = lv_name value = lv_value ) TO gt_input.
          ENDIF.
      ENDCASE.
    ENDLOOP.

    CASE to_upper( action ).
      WHEN 'GO'.
        gv_go = abap_true.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      WHEN 'F4' OR 'VHGO'.
        gv_vh = abap_true.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      WHEN 'BG'.
        gv_bg = abap_true.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      WHEN 'VSAVE'.
        gv_std = 'SPOS'.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      WHEN 'XA'.
        cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
      WHEN OTHERS.
        "SYNC: SAP GUI for Windows keeps the page - the entries are applied
        "with the next function. SAP GUI for HTML reloads the page after
        "each event - apply and render again
        IF lv_web EQ '1'.
          cl_gui_cfw=>set_new_ok_code( new_code = gc_okcode ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD render.
    DATA: lv_url  TYPE c LENGTH 255,
          lv_size TYPE i.

    IF go_viewer IS NOT BOUND.
      CREATE OBJECT go_viewer
        EXPORTING
          parent = cl_gui_container=>screen0
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc NE 0.
        CLEAR go_viewer. "the classic selection screen stays usable
        RETURN.
      ENDIF.
      DATA lt_events TYPE cntl_simple_events.
      APPEND VALUE cntl_simple_event( eventid    = go_viewer->m_id_sapevent
                                      appl_event = abap_false ) TO lt_events.
      go_viewer->set_registered_events( EXPORTING events = lt_events
                                        EXCEPTIONS OTHERS = 1 ).
      SET HANDLER on_sapevent FOR go_viewer.
    ENDIF.
    go_viewer->set_visible( EXPORTING visible = abap_true EXCEPTIONS OTHERS = 1 ).

    TYPES ty_line TYPE c LENGTH 255.
    DATA lt_data TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA(lv_html) = build_page( ).
    CLEAR gv_focus.
    lv_size = strlen( lv_html ).
    DATA(lv_off) = 0.
    WHILE lv_off LT lv_size.
      DATA(lv_len) = nmin( val1 = 255 val2 = lv_size - lv_off ).
      APPEND lv_html+lv_off(lv_len) TO lt_data.
      lv_off = lv_off + lv_len.
    ENDWHILE.

    go_viewer->load_data( EXPORTING type         = 'text'
                                    subtype      = 'html'
                                    size         = lv_size
                          IMPORTING assigned_url = lv_url
                          CHANGING  data_table   = lt_data
                          EXCEPTIONS OTHERS      = 1 ).
    IF sy-subrc EQ 0.
      go_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD vh_search.
    "Document value help: one database access with all restrictions,
    "only the displayed columns, sorted and limited in the database.
    "Filter / sort / selection then run in the browser without round trip
    DATA: lt_tok   TYPE string_table,
          lr_fkdat TYPE RANGE OF vbrk-fkdat,
          lr_kunag TYPE RANGE OF vbrk-kunag,
          lr_fkart TYPE RANGE OF vbrk-fkart,
          lv_kunag TYPE vbrk-kunag.

    gv_vh_on = abap_true.
    CLEAR: gv_vh_dat, gv_vh_inf.
    IF gs_vh-max LE 0.
      gs_vh-max = 500.
    ELSEIF gs_vh-max GT 5000.
      gs_vh-max = 5000.
    ENDIF.

    "Document: single values, ranges and patterns as in the selection field
    SPLIT gs_vh-doc AT ',' INTO TABLE lt_tok.
    parse_docs( EXPORTING it_tokens = lt_tok
                IMPORTING et_range  = DATA(lr_vbeln)
                          ev_error  = gv_vh_inf ).
    CHECK gv_vh_inf IS INITIAL.

    parse_date( EXPORTING iv = gs_vh-from IMPORTING ev_date = DATA(lv_dfrom) ev_ok = DATA(lv_ok1) ).
    parse_date( EXPORTING iv = gs_vh-to   IMPORTING ev_date = DATA(lv_dto)   ev_ok = DATA(lv_ok2) ).
    IF lv_ok1 EQ abap_false OR lv_ok2 EQ abap_false.
      gv_vh_inf = 'Billing date: enter a valid date (DD.MM.YYYY)'.
      RETURN.
    ENDIF.
    IF lv_dto IS NOT INITIAL.
      lr_fkdat = VALUE #( ( sign = 'I' option = 'BT' low = lv_dfrom high = lv_dto ) ).
    ELSEIF lv_dfrom IS NOT INITIAL.
      lr_fkdat = VALUE #( ( sign = 'I' option = 'GE' low = lv_dfrom ) ).
    ENDIF.

    DATA(lv_cust) = to_upper( condense( gs_vh-kunag ) ).
    IF lv_cust CA '*+'.
      lr_kunag = VALUE #( ( sign = 'I' option = 'CP' low = lv_cust ) ).
    ELSEIF lv_cust IS NOT INITIAL.
      lv_kunag = lv_cust.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = lv_kunag
        IMPORTING
          output = lv_kunag.
      lr_kunag = VALUE #( ( sign = 'I' option = 'EQ' low = lv_kunag ) ).
    ENDIF.

    DATA(lv_fkart) = to_upper( condense( gs_vh-fkart ) ).
    IF lv_fkart IS NOT INITIAL.
      lr_fkart = VALUE #( ( sign = 'I' option = COND #( WHEN lv_fkart CA '*+' THEN 'CP' ELSE 'EQ' )
                            low = lv_fkart ) ).
    ENDIF.

    DATA(lv_max) = gs_vh-max.
    SELECT vbeln, fkart, kunag, kunrg, fkdat, vkorg, vtweg, rfbsk
      FROM vbrk
      WHERE bukrs IN @s_bukrs
        AND vbeln IN @lr_vbeln
        AND fkdat IN @lr_fkdat
        AND kunag IN @lr_kunag
        AND fkart IN @lr_fkart
        "Only e-invoice relevant documents (same rule as the cockpit selection)
        AND EXISTS ( SELECT sapdocument FROM zi_einvoice_header
                       WHERE sapdocument     EQ vbrk~vbeln
                         AND einvoiceenabled EQ @abap_true )
      ORDER BY vbeln
      INTO TABLE @DATA(lt_vbrk)
      UP TO @lv_max ROWS.

    IF lines( lt_vbrk ) EQ lv_max.
      gv_vh_inf = |Only the first { lv_max } documents are shown - narrow the restrictions or raise Max. hits.|.
    ENDIF.

    "Compact rows: fields separated by ~, rows by ^ (no HTML from the server)
    LOOP AT lt_vbrk INTO DATA(ls_vbrk).
      gv_vh_dat = gv_vh_dat &&
        |{ ls_vbrk-vbeln ALPHA = OUT }~{ ls_vbrk-fkart }~{ ls_vbrk-kunag ALPHA = OUT }~| &&
        |{ ls_vbrk-kunrg ALPHA = OUT }~{ ls_vbrk-fkdat }~{ ls_vbrk-vkorg }~{ ls_vbrk-vtweg }~{ ls_vbrk-rfbsk }^|.
    ENDLOOP.
    gv_vh_dat = escape( val = gv_vh_dat format = cl_abap_format=>e_json_string ).
  ENDMETHOD.

  METHOD vh_html.
    "Value help dialog of the documents - rows are built by the script (VHI)
    DATA: lv_sel  TYPE string,
          lv_comp TYPE string.
    CHECK gv_vh_on EQ abap_true.
    CLEAR gv_vh_on.

    LOOP AT gt_vh_sel INTO DATA(lv_s).
      lv_sel = COND #( WHEN lv_sel IS INITIAL THEN lv_s ELSE |{ lv_sel },{ lv_s }| ).
    ENDLOOP.
    CLEAR gt_vh_sel.
    lv_sel = escape( val = lv_sel format = cl_abap_format=>e_json_string ).

    READ TABLE s_bukrs INTO DATA(ls_bukrs) INDEX 1.
    lv_comp = COND #( WHEN sy-subrc NE 0 THEN 'All company codes'
                      ELSE |Company Code { condense( CONV string( ls_bukrs-low ) ) }| ) &&
              ' - e-invoice relevant documents only'.

    "Date format of the user (placeholders, applied in the script)
    DATA(lv_df) = |{ CONV d( '20261231' ) DATE = USER }|.
    REPLACE '2026' IN lv_df WITH 'YYYY'.
    REPLACE '12' IN lv_df WITH 'MM'.
    REPLACE '31' IN lv_df WITH 'DD'.

    rv =
      |<div id="vh" class="ov"><div class="dlg">| &&
      |<div class="dh"><span class="dti">{ label( iv_name = 'S_VBELN' iv_default = 'Document' ) }</span>| &&
      |<button class="x" onclick="vhx()" title="Close (Esc)">&times;</button></div>| &&
      |<div class="dr">| &&
      |<div class="rf w"><label class="l" for="vd">Document</label>| &&
      |<input class="i" id="vd" value="{ h( gs_vh-doc ) }" placeholder="e.g. 9000*"></div>| &&
      |<div class="rf w"><label class="l" for="vf">Bill. Date</label><div class="rg">| &&
      |<input class="i dt" id="vf" value="{ h( gs_vh-from ) }"><span>to</span>| &&
      |<input class="i dt" id="vt" value="{ h( gs_vh-to ) }"></div></div>| &&
      |<div class="rf"><label class="l" for="vk">Sold-to</label><input class="i" id="vk" value="{ h( gs_vh-kunag ) }"></div>| &&
      |<div class="rf s"><label class="l" for="vb">Bill. Type</label><input class="i" id="vb" value="{ h( gs_vh-fkart ) }"></div>| &&
      |<div class="rf s"><label class="l" for="vm">Max. hits</label><input class="i" id="vm" value="{ gs_vh-max }"></div>| &&
      |<button class="btn pri" onclick="vhgo()" title="Search with the restrictions (Enter)">Go</button></div>| &&
      |<div class="dbar"><b>Items (<span id="vhn">0</span>)</b><span class="cmp">{ h( lv_comp ) }</span>| &&
      |<span class="sp"></span><input class="i srch" id="vhq" placeholder="Filter the items" autocomplete="off"></div>| &&
      COND string( WHEN gv_vh_inf IS NOT INITIAL THEN |<div class="vinf">{ h( gv_vh_inf ) }</div>| ) &&
      |<div class="dtb"><table id="vtab"><thead><tr id="vth">| &&
      |<th class="c"><input type="checkbox" id="vha" onclick="vhall(this.checked)" title="Select all"></th>| &&
      |<th class="asc" onclick="vsrt(0)" title="Billing Document">Bill. Doc.</th>| &&
      |<th onclick="vsrt(1)" title="Billing Type">BillT</th>| &&
      |<th onclick="vsrt(2)" title="Sold-to Party">Sold-to</th>| &&
      |<th onclick="vsrt(3)" title="Payer">Payer</th>| &&
      |<th onclick="vsrt(4)" title="Billing Date">Bill. Date</th>| &&
      |<th onclick="vsrt(5)" title="Sales Organization">SOrg.</th>| &&
      |<th onclick="vsrt(6)" title="Distribution Channel">DChl</th>| &&
      |<th onclick="vsrt(7)" title="Posting Status">PsSt</th>| &&
      |</tr></thead><tbody id="vhb"></tbody></table><div class="mt" id="vhe">No documents found</div></div>| &&
      |<div class="df"><span id="vhc">0 selected</span><span class="sp"></span>| &&
      |<button class="btn pri" onclick="vhok()">OK</button><button class="btn" onclick="vhx()">Cancel</button></div>| &&
      |</div></div>| &&
      |<script>var VHD="{ gv_vh_dat }",VHS="{ lv_sel }",VDF="{ lv_df }";</script>|.
    CLEAR gv_vh_dat.
  ENDMETHOD.

  METHOD parse_docs.
    "Documents - single values, ranges (a-b) and patterns (*)
    CLEAR: et_range, ev_error.
    LOOP AT it_tokens INTO DATA(lv_doc).
      lv_doc = to_upper( condense( lv_doc ) ).
      CHECK lv_doc IS NOT INITIAL.
      IF lv_doc CA '*+'.
        IF strlen( lv_doc ) GT 10.
          ev_error = |Document { lv_doc } is not valid|.
          RETURN.
        ENDIF.
        APPEND VALUE #( sign = 'I' option = 'CP' low = lv_doc ) TO et_range.
        CONTINUE.
      ENDIF.
      SPLIT lv_doc AT '-' INTO DATA(lv_lo) DATA(lv_hi).
      IF strlen( lv_lo ) GT 10 OR strlen( lv_hi ) GT 10 OR
         ( lv_lo IS INITIAL AND lv_hi IS NOT INITIAL ).
        ev_error = |Document { lv_doc } is not valid|.
        RETURN.
      ENDIF.
      IF lv_hi IS INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = doc_in( lv_lo ) ) TO et_range.
      ELSE.
        DATA(lv_vlo) = doc_in( lv_lo ).
        DATA(lv_vhi) = doc_in( lv_hi ).
        IF lv_vlo GT lv_vhi.
          ev_error = |Document { lv_doc }: lower limit is greater than upper limit|.
          RETURN.
        ENDIF.
        APPEND VALUE #( sign = 'I' option = 'BT' low = lv_vlo high = lv_vhi ) TO et_range.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD apply.
    DATA: lt_changed TYPE string_table,
          lt_drop    TYPE string_table,
          lt_docs    TYPE string_table,
          lt_stat    TYPE string_table,
          lv_bukrs   TYPE string,
          lv_from    TYPE string,
          lv_to      TYPE string,
          lv_btype   TYPE string,
          lv_type    TYPE string.

    CHECK gt_input IS NOT INITIAL.
    DATA(lt_input) = gt_input.
    CLEAR gt_input.

    "Parameter names are unique (SAP GUI for HTML keeps one value per name):
    "documents are sent as DN0, DN1, ..., the statuses as one value (e.g. 'SP')
    LOOP AT lt_input INTO DATA(ls_in).
      CASE COND string( WHEN ls_in-name CP 'DN*' THEN 'DN' ELSE ls_in-name ).
        WHEN 'CH'.
          SPLIT ls_in-value AT ',' INTO TABLE lt_changed.
        WHEN 'XA'.
          APPEND to_upper( ls_in-value ) TO lt_drop.
        WHEN 'B'.
          lv_bukrs = ls_in-value.
        WHEN 'DN'.
          APPEND ls_in-value TO lt_docs.
        WHEN 'EF'.
          lv_from = ls_in-value.
        WHEN 'ET'.
          lv_to = ls_in-value.
        WHEN 'BT'.
          lv_btype = ls_in-value.
        WHEN 'TY'.
          lv_type = ls_in-value.
        WHEN 'ST'.
          DATA(lv_stv) = to_upper( condense( ls_in-value ) ).
          DO strlen( lv_stv ) TIMES.
            APPEND substring( val = lv_stv off = sy-index - 1 len = 1 ) TO lt_stat.
          ENDDO.
      ENDCASE.
    ENDLOOP.

    "Company Code - one single value (NO-EXTENSION, NO INTERVALS)
    IF line_exists( lt_changed[ table_line = 'B' ] ).
      lv_bukrs = to_upper( condense( lv_bukrs ) ).
      IF strlen( lv_bukrs ) GT 4.
        rv_error = |Company Code { lv_bukrs } is not valid|.
        RETURN.
      ENDIF.
      CLEAR: s_bukrs, s_bukrs[].
      IF lv_bukrs IS NOT INITIAL.
        APPEND VALUE #( sign   = 'I'
                        option = COND #( WHEN lv_bukrs CA '*+' THEN 'CP' ELSE 'EQ' )
                        low    = lv_bukrs ) TO s_bukrs.
      ENDIF.
    ENDIF.

    "Documents - single values, ranges (a-b) and patterns (*)
    IF line_exists( lt_changed[ table_line = 'DN' ] ).
      parse_docs( EXPORTING it_tokens = lt_docs
                  IMPORTING et_range  = DATA(lt_vbeln)
                            ev_error  = rv_error ).
      IF rv_error IS NOT INITIAL.
        RETURN.
      ENDIF.
      DELETE s_vbeln WHERE sign EQ 'I' AND ( option EQ 'EQ' OR option EQ 'BT' OR option EQ 'CP' ).
      APPEND LINES OF lt_vbeln TO s_vbeln.
    ENDIF.

    "Created On - one single value or interval (NO-EXTENSION)
    IF line_exists( lt_changed[ table_line = 'ED' ] ).
      parse_date( EXPORTING iv = lv_from IMPORTING ev_date = DATA(lv_dfrom) ev_ok = DATA(lv_ok1) ).
      parse_date( EXPORTING iv = lv_to   IMPORTING ev_date = DATA(lv_dto)   ev_ok = DATA(lv_ok2) ).
      IF lv_ok1 EQ abap_false OR lv_ok2 EQ abap_false.
        rv_error = 'Created On: enter a valid date (DD.MM.YYYY)'.
        RETURN.
      ENDIF.
      IF lv_dto IS NOT INITIAL AND lv_dfrom GT lv_dto.
        rv_error = 'Created On: lower limit is greater than upper limit'.
        RETURN.
      ENDIF.
      CLEAR: s_erdat, s_erdat[].
      IF lv_dto IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'BT' low = lv_dfrom high = lv_dto ) TO s_erdat.
      ELSEIF lv_dfrom IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_dfrom ) TO s_erdat.
      ENDIF.
    ENDIF.

    IF line_exists( lt_changed[ table_line = 'BT' ] ).
      p_btype = to_upper( condense( lv_btype ) ).
    ENDIF.
    IF line_exists( lt_changed[ table_line = 'TY' ] ).
      p_type = to_upper( condense( lv_type ) ).
    ENDIF.

    "Status - P / W / S / E
    IF line_exists( lt_changed[ table_line = 'ST' ] ).
      DELETE s_status WHERE sign EQ 'I' AND option EQ 'EQ' AND
                            ( low EQ 'P' OR low EQ 'W' OR low EQ 'S' OR low EQ 'E' ).
      LOOP AT lt_stat INTO DATA(lv_st).
        lv_st = to_upper( condense( lv_st ) ).
        IF strlen( lv_st ) EQ 1 AND lv_st CA 'PWSE'.
          APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_st ) TO s_status.
        ENDIF.
      ENDLOOP.
    ENDIF.

    "Remove conditions the page cannot show (e.g. exclusions of a variant)
    LOOP AT lt_drop INTO DATA(lv_drop).
      CASE lv_drop.
        WHEN 'B'.
          DELETE s_bukrs WHERE NOT ( sign EQ 'I' AND ( option EQ 'EQ' OR option EQ 'CP' ) ).
        WHEN 'DN'.
          DELETE s_vbeln WHERE NOT ( sign EQ 'I' AND ( option EQ 'EQ' OR option EQ 'BT' OR option EQ 'CP' ) ).
        WHEN 'ED'.
          DELETE s_erdat WHERE NOT ( sign EQ 'I' AND ( option EQ 'EQ' OR option EQ 'BT' ) ).
        WHEN 'ST'.
          DELETE s_status WHERE NOT ( sign EQ 'I' AND option EQ 'EQ' AND
                                      ( low EQ 'P' OR low EQ 'W' OR low EQ 'S' OR low EQ 'E' ) ).
      ENDCASE.
    ENDLOOP.

    "Header lines = first row (shown in the fields of the standard screen)
    CLEAR: s_bukrs, s_vbeln, s_erdat, s_status.
    READ TABLE s_bukrs INTO s_bukrs INDEX 1.
    READ TABLE s_vbeln INTO s_vbeln INDEX 1.
    READ TABLE s_erdat INTO s_erdat INDEX 1.
    READ TABLE s_status INTO s_status INDEX 1.
  ENDMETHOD.

  METHOD build_page.
    DATA: lv_bukrs TYPE string,
          lv_docs  TYPE string,
          lv_tok   TYPE string,
          lv_from  TYPE string,
          lv_to    TYPE string,
          lv_stat  TYPE string,
          lv_list  TYPE string,
          lv_nb    TYPE i,
          lv_nd    TYPE i,
          lv_ne    TYPE i,
          lv_ns    TYPE i.

    LOOP AT s_bukrs INTO DATA(ls_bukrs).
      IF lv_bukrs IS INITIAL AND ls_bukrs-sign EQ 'I' AND
         ( ls_bukrs-option EQ 'EQ' OR ls_bukrs-option EQ 'CP' ).
        lv_bukrs = ls_bukrs-low.
      ELSE.
        lv_nb = lv_nb + 1.
      ENDIF.
    ENDLOOP.

    "Shown in document order (independent of the order of the entries)
    DATA(lt_vbeln) = s_vbeln[].
    SORT lt_vbeln BY option low high.
    LOOP AT lt_vbeln INTO DATA(ls_vbeln).
      IF ls_vbeln-sign EQ 'I' AND ls_vbeln-option EQ 'EQ'.
        lv_tok = doc_out( ls_vbeln-low ).
      ELSEIF ls_vbeln-sign EQ 'I' AND ls_vbeln-option EQ 'CP'.
        lv_tok = condense( CONV string( ls_vbeln-low ) ).
      ELSEIF ls_vbeln-sign EQ 'I' AND ls_vbeln-option EQ 'BT'.
        lv_tok = |{ doc_out( ls_vbeln-low ) }-{ doc_out( ls_vbeln-high ) }|.
      ELSE.
        lv_nd = lv_nd + 1.
        CONTINUE.
      ENDIF.
      lv_docs = COND #( WHEN lv_docs IS INITIAL THEN lv_tok ELSE |{ lv_docs }, { lv_tok }| ).
    ENDLOOP.

    LOOP AT s_erdat INTO DATA(ls_erdat).
      IF sy-tabix EQ 1 AND ls_erdat-sign EQ 'I' AND
         ( ls_erdat-option EQ 'EQ' OR ls_erdat-option EQ 'BT' ).
        lv_from = to_iso( ls_erdat-low ).
        IF ls_erdat-option EQ 'BT'.
          lv_to = to_iso( ls_erdat-high ).
        ENDIF.
      ELSE.
        lv_ne = lv_ne + 1.
      ENDIF.
    ENDLOOP.

    LOOP AT s_status INTO DATA(ls_stat).
      IF ls_stat-sign EQ 'I' AND ls_stat-option EQ 'EQ' AND ls_stat-low CA 'PWSE'.
        lv_stat = lv_stat && ls_stat-low.
      ELSE.
        lv_ns = lv_ns + 1.
      ENDIF.
    ENDLOOP.

    "Company Codes registered for e-invoicing (read once per session)
    IF gt_comp IS INITIAL.
      SELECT bukrs, butxt FROM zeinv_company ORDER BY bukrs INTO CORRESPONDING FIELDS OF TABLE @gt_comp.
    ENDIF.
    DATA(lv_found) = xsdbool( lv_bukrs IS INITIAL ).
    LOOP AT gt_comp INTO DATA(ls_comp).
      DATA(lv_csel) = COND string( WHEN ls_comp-bukrs EQ lv_bukrs THEN ' selected' ).
      IF lv_csel IS NOT INITIAL.
        lv_found = abap_true.
      ENDIF.
      lv_list = lv_list && |<option value="{ h( ls_comp-bukrs ) }"{ lv_csel }>{ h( ls_comp-bukrs ) }| &&
                |{ COND string( WHEN ls_comp-butxt IS NOT INITIAL THEN | - { h( ls_comp-butxt ) }| ) }</option>|.
    ENDLOOP.
    "Value of a variant / SUBMIT that is not registered (e.g. a pattern)
    IF lv_found EQ abap_false.
      lv_list = |<option value="{ h( lv_bukrs ) }" selected>{ h( lv_bukrs ) }</option>| && lv_list.
    ENDIF.
    lv_list = |<option value="">- Select -</option>| && lv_list.

    "Proposal for a start at date / time: now + 10 minutes (system time)
    DATA(lv_bg_d) = sy-datum.
    DATA(lv_bg_tt) = CONV t( sy-uzeit + 600 ).
    IF lv_bg_tt LT sy-uzeit.
      lv_bg_d = lv_bg_d + 1.
    ENDIF.
    DATA(lv_bg_t) = substring( val = |{ lv_bg_tt TIME = ISO }| len = 5 ).

    rv =
      |{ gc_html_head }{ gc_scroll_css }{ css( ) }</style></head>| &&
      |<body data-fo="{ h( gv_focus ) }"><div id="scr"><div class="pg">| &&
      |<div class="msg" id="msg"{ COND string( WHEN gv_error IS INITIAL THEN ' style="display:none"' ) }>| &&
      |{ h( gv_error ) }</div>| &&
      |<div class="card"><div class="ct">{ h( t_b01 ) }</div><div class="grid">| &&
      "Row 1: the short fields (25% each) - row 2: Document and Status (50% each)
      |<div class="f"><label class="l" for="b">{ label( iv_name = 'S_BUKRS' iv_default = 'Company Code' ) }| &&
      |<span class="req">*</span></label>| &&
      |<select class="i" id="b">{ lv_list }</select>{ adv_note( iv_key = 'B' iv_count = lv_nb ) }</div>| &&
      |<div class="f"><label class="l" for="ef">{ label( iv_name = 'S_ERDAT' iv_default = 'Created On' ) }</label>| &&
      |<div class="rg"><input class="i dt" id="ef" value="{ lv_from }"><span>to</span>| &&
      |<input class="i dt" id="et" value="{ lv_to }"></div>{ adv_note( iv_key = 'ED' iv_count = lv_ne ) }</div>| &&
      |<div class="f"><label class="l" for="bt">{ label( iv_name = 'P_BTYPE' iv_default = 'Business Type' ) }</label>| &&
      |<select class="i" id="bt">{ listbox( p_btype ) }</select></div>| &&
      |<div class="f"><label class="l" for="ty">{ label( iv_name = 'P_TYPE' iv_default = 'Type' ) }</label>| &&
      |<select class="i" id="ty">{ listbox( p_type ) }</select></div>| &&
      |<div class="f w2"><label class="l" for="dn">{ label( iv_name = 'S_VBELN' iv_default = 'Document' ) }</label>| &&
      |<div class="ih"><input class="i" id="dn" autocomplete="off" value="{ h( lv_docs ) }"| &&
      | placeholder="e.g. 90000001, 90000010-90000020, 9000*">| &&
      |<button type="button" class="vh" onclick="f4()" title="Value help (F4)">| &&
      |<svg viewBox="0 0 16 16"><path fill="none" stroke="currentColor" stroke-width="1.6" | &&
      |d="M10.5 10.5L14.5 14.5M11.5 6.5a5 5 0 1 1-10 0a5 5 0 1 1 10 0z"/></svg></button></div>| &&
      |<div class="hint">Separate several documents with commas, use a hyphen for a range and * as wildcard</div>| &&
      |{ adv_note( iv_key = 'DN' iv_count = lv_nd ) }</div>| &&
      |<div class="f w2"><label class="l">{ label( iv_name = 'S_STATUS' iv_default = 'Status' ) }</label><div class="seg">| &&
      chip( iv_code = 'E' iv_text = 'Error' iv_cls = 'ko' iv_sel = lv_stat ) &&
      chip( iv_code = 'W' iv_text = 'In process' iv_cls = 'wt' iv_sel = lv_stat ) &&
      chip( iv_code = 'S' iv_text = 'Success' iv_cls = 'ok' iv_sel = lv_stat ) &&
      chip( iv_code = 'P' iv_text = 'Pending' iv_cls = 'na' iv_sel = lv_stat ) &&
      |</div><div class="hint">No status selected = all statuses</div>| &&
      |{ adv_note( iv_key = 'ST' iv_count = lv_ns ) }</div>| &&
      |</div></div>| &&
      |</div></div>| &&
      |<div id="ft"><button class="btn gh" onclick="clr()" title="Clear all entries">Clear</button>| &&
      |<span class="sp"></span>| &&
      |<button class="btn" onclick="go('VSAVE')" title="Save the entries as variant">Save as Variant</button>| &&
      |<button class="btn" onclick="bgo()" title="Execute in background">Execute in Background</button>| &&
      |<button class="btn pri" onclick="go('GO')" title="Execute (Enter)">Execute</button></div>| &&
      vh_html( ) &&
      "Execute in Background: start immediately or at date / time (system time)
      |<div id="bg" class="ov" style="display:none"><div class="dlg sm">| &&
      |<div class="dh"><span class="dti">Execute in Background</span>| &&
      |<button class="x" onclick="bgx()" title="Close (Esc)">&times;</button></div>| &&
      |<div class="bgb"><label class="ro"><input type="radio" name="bgs" id="bgi" checked onclick="bgm()">| &&
      |Start immediately</label><label class="ro"><input type="radio" name="bgs" id="bgl" onclick="bgm()">| &&
      |Start on</label><div class="rg"><input class="i dt" id="bgd" value="{ to_iso( lv_bg_d ) }" disabled>| &&
      |<span>at</span><input class="i" id="bgt" type="time" value="{ lv_bg_t }" disabled></div>| &&
      |<div class="hint">System time. The result of the job is written to the job log (SM37).</div></div>| &&
      |<div class="df"><span class="sp"></span><button class="btn pri" onclick="bgs()">Schedule</button>| &&
      |<button class="btn" onclick="bgx()">Cancel</button></div></div></div>| &&
      |<div id="busy"><div>Processing, please wait...</div></div>| &&
      |<a id="sapev" href="SAPEVENT:NONE" style="display:none"></a>| &&
      |<script>{ script( ) }</script></body></html>|.
  ENDMETHOD.

  METHOD css.
    rv =
      '*{box-sizing:border-box}' &&
      'body{font-family:"72","72full",Arial,Helvetica,sans-serif;font-size:13px;color:#1d2d3e;background:#f5f6f7}' &&
      '#scr{bottom:56px}.pg{padding:16px 20px 4px}' &&
      '.card{background:#fff;border:1px solid #d9d9d9;border-radius:8px;padding:14px 16px 4px;margin:0 0 12px}' &&
      '.ct{font-size:14px;font-weight:700;margin:0 0 12px}' &&
      '.grid{display:flex;flex-wrap:wrap;margin:0 -8px}' &&
      '.f{width:25%;padding:0 8px 14px}.f.w2{width:50%}' &&
      '@media (max-width:1100px){.f{width:50%}.f.w2{width:100%}}' &&
      '@media (max-width:700px){.f,.f.w2{width:100%}}' &&
      '.l{display:block;color:#556b82;font-size:12px;margin:0 0 4px}.req{color:#d20a0a;margin-left:2px}' &&
      '.i{font:inherit;width:100%;height:32px;border:1px solid #bcc3ca;border-radius:6px;padding:0 8px;' &&
      'background:#fff;color:#1d2d3e}' &&
      '.i:focus{outline:none;border-color:#0070f2;box-shadow:0 0 0 2px rgba(0,112,242,.2)}' &&
      '.i.bad{border-color:#d20a0a;background:#fff4f4}' &&
      '.ih{position:relative}.ih .i{padding-right:40px}' &&
      '.vh{position:absolute;top:1px;right:1px;width:36px;height:30px;border:0;border-left:1px solid #e5e5e5;' &&
      'border-radius:0 6px 6px 0;background:#fff;color:#0064d9;cursor:pointer;padding:0}' &&
      '.vh:hover{background:#eaecee}.vh svg{width:16px;height:16px;vertical-align:middle}' &&
      '.rg{display:flex;align-items:center}.rg .i{flex:1;min-width:0}.rg span{padding:0 8px;color:#556b82}' &&
      '.seg{display:flex;flex-wrap:wrap}' &&
      '.tg{display:inline-flex;align-items:center;height:32px;border:1px solid #bcc3ca;border-radius:16px;' &&
      'padding:0 12px;margin:0 6px 6px 0;cursor:pointer;background:#fff}' &&
      '.tg:hover{border-color:#0070f2}.tg.on{border-color:#0070f2;background:#e5f0fe}.tg input{margin:0 6px 0 0}' &&
      '.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}' &&
      '.ok{background:#188918}.ko{background:#d20a0a}.wt{background:#e76500}.na{border:1px solid #a9b4be}' &&
      '.hint{color:#6a6d70;font-size:11px;margin-top:4px}' &&
      '.adv{margin-top:6px;font-size:11px;color:#8d5b00;background:#fff8e1;border-left:3px solid #e76500;' &&
      'border-radius:3px;padding:4px 8px}.adv a{color:#0064d9;cursor:pointer;margin-left:8px;text-decoration:underline}' &&
      '.msg{background:#fdecea;border:1px solid #d20a0a;color:#a00;border-radius:6px;padding:8px 12px;margin:0 0 12px}' &&
      '#ft{position:absolute;left:0;right:0;bottom:0;height:56px;background:#fff;border-top:1px solid #d9d9d9;' &&
      'display:flex;align-items:center;padding:0 16px}.sp{flex:1}' &&
      '.btn{font:inherit;height:32px;border:1px solid #bcc3ca;background:#fff;color:#0064d9;border-radius:6px;' &&
      'padding:0 14px;margin-left:8px;cursor:pointer}.btn:hover{background:#eaecee}' &&
      '.btn.pri{background:#0070f2;border-color:#0070f2;color:#fff;font-weight:600}.btn.pri:hover{background:#0064d9}' &&
      '.btn.gh{margin-left:0;border-color:transparent}' &&
      '.ov{position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.35);z-index:8;' &&
      'display:flex;align-items:center;justify-content:center}' &&
      '.dlg{background:#fff;border-radius:10px;box-shadow:0 8px 32px rgba(0,0,0,.3);width:96%;max-width:1280px;' &&
      'height:92%;display:flex;flex-direction:column;overflow:hidden}' &&
      '.dh{display:flex;align-items:center;padding:10px 16px;border-bottom:1px solid #e5e5e5}' &&
      '.dti{flex:1;font-size:15px;font-weight:700}' &&
      '.x{border:0;background:transparent;font-size:22px;line-height:22px;cursor:pointer;color:#556b82;' &&
      'padding:2px 8px;border-radius:6px}.x:hover{background:#eaecee}' &&
      '.dr{display:flex;flex-wrap:wrap;align-items:flex-end;padding:10px 16px 2px;background:#f7f8f9;' &&
      'border-bottom:1px solid #e5e5e5}' &&
      '.rf{width:140px;margin:0 10px 8px 0}.rf.w{width:230px}.rf.s{width:90px}' &&
      '.rf .i,.dr .btn,.dbar .i{height:30px}.dr .btn{margin:0 0 8px 0}' &&
      '.dbar{display:flex;align-items:center;padding:8px 16px}.cmp{color:#556b82;font-size:12px;margin-left:12px}' &&
      '.srch{width:260px}' &&
      '.vinf{margin:0 16px 8px;padding:6px 10px;font-size:12px;color:#8d5b00;background:#fff8e1;' &&
      'border-left:3px solid #e76500;border-radius:3px}' &&
      '.dtb{flex:1;overflow:auto;margin:0 16px;border:1px solid #d9d9d9;border-radius:6px}' &&
      '#vtab{width:100%;border-collapse:separate;border-spacing:0}' &&
      '#vtab th{position:sticky;top:0;z-index:1;background:#f5f6f7;color:#556b82;font-weight:600;text-align:left;' &&
      'padding:6px 10px;border-bottom:1px solid #d9d9d9;white-space:nowrap;cursor:pointer}#vtab th:hover{color:#1d2d3e}' &&
      '#vtab th.asc:after{content:" \25B2";font-size:9px}#vtab th.desc:after{content:" \25BC";font-size:9px}' &&
      '#vtab td{padding:4px 10px;border-bottom:1px solid #eef0f2;white-space:nowrap;cursor:pointer}' &&
      '#vtab tbody tr:hover td{background:#f0f7ff}#vtab tr.sel td{background:#e5f0fe}' &&
      '#vtab td.k{color:#0064d9;font-weight:600}#vtab .c{text-align:center;width:40px}' &&
      '.mt{display:none;color:#556b82;text-align:center;padding:24px}' &&
      '.df{display:flex;align-items:center;padding:10px 16px;border-top:1px solid #e5e5e5;margin-top:10px}' &&
      '#vhc{color:#556b82}.df .btn{margin-left:8px}' &&
      '.dlg.sm{max-width:460px;height:auto}.bgb{padding:14px 16px 0}' &&
      '.ro{display:flex;align-items:center;margin:0 0 10px;cursor:pointer}.ro input{margin:0 8px 0 0}' &&
      '.bgb .rg{margin:0 0 4px 24px}.bgb .hint{margin:10px 0 0}.i:disabled{background:#f5f6f7;color:#8396a8}' &&
      '#busy{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(255,255,255,.6);z-index:9}' &&
      '#busy div{position:absolute;top:40%;left:50%;margin-left:-110px;width:220px;text-align:center;background:#fff;' &&
      'border:1px solid #d9d9d9;border-radius:8px;padding:12px;box-shadow:0 4px 16px rgba(0,0,0,.15)}'.
  ENDMETHOD.

  METHOD script.
    "Only double quotes and no less-than sign in the script
    rv =
      'function $(i){return document.getElementById(i);}' &&
      'var WEB=!!(window.parent&&window.parent!==window),BUSY=false,I={},K=["B","DN","ED","BT","TY","ST"];' &&
      'function sap(a){if(WEB){window.parent.postMessage(JSON.stringify({type:"request",' &&
      'service:"sap.gui.triggerSAPEvent",request_id:"ev"+(new Date()).getTime(),body:{args:{action:a}}}),"*");}' &&
      'else{var l=$("sapev");l.href="SAP"+"EVENT:"+a;l.click();}}' &&
      'function enc(v){return encodeURIComponent(v);}' &&
      'function toks(){var s=$("dn").value.split(/[,;\s]+/),r=[],i;for(i=0;s.length>i;i++)if(s[i])r.push(s[i]);return r;}' &&
      'function sts(){var c="PWSE",r="",i;for(i=0;c.length>i;i++)if($("st"+c.charAt(i)).checked)r+=c.charAt(i);return r;}' &&
      'function val(k){switch(k){case "B":return $("b").value;case "DN":return toks().join(",");' &&
      'case "ED":return $("ef").value+"~"+$("et").value;case "BT":return $("bt").value;' &&
      'case "TY":return $("ty").value;case "ST":return sts();}return "";}' &&
      'function snap(){for(var i=0;K.length>i;i++)I[K[i]]=val(K[i]);}' &&
      'function qry(){var ch=[],p=[],i,j,k,t;for(i=0;K.length>i;i++){k=K[i];if(val(k)===I[k])continue;ch.push(k);' &&
      'if(k=="B")p.push("b="+enc($("b").value.toUpperCase()));' &&
      'else if(k=="DN"){t=toks();for(j=0;t.length>j;j++)p.push("dn"+j+"="+enc(t[j]));}' &&
      'else if(k=="ED"){p.push("ef="+enc($("ef").value));p.push("et="+enc($("et").value));}' &&
      'else if(k=="BT")p.push("bt="+enc($("bt").value));' &&
      'else if(k=="TY")p.push("ty="+enc($("ty").value));' &&
      'else if(k=="ST")p.push("st="+sts());}' &&
      'p.unshift("ch="+ch.join(","));return p.join("&");}' &&
      'function ev(a,x){sap(a+"?"+qry()+(x?"&"+x:""));}' &&
      'function sync(){if(BUSY)return;if(!WEB){ev("SYNC","");return;}' &&
      'setTimeout(function(){var e=document.activeElement;if(BUSY||(e&&e.tagName=="BUTTON"))return;BUSY=true;' &&
      'ev("SYNC","w=1&fo="+(e&&e.id?e.id:""));},0);}' &&
      'function msg(t){var m=$("msg");m.innerHTML=t;m.style.display=t?"block":"none";}' &&
      'function bad(id,on){var e=$(id);e.className=e.className.replace(/ bad/g,"")+(on?" bad":"");}' &&
      'function okd(v){return !v||/^\d{4}-\d{1,2}-\d{1,2}$/.test(v)||/^\d{1,2}[.\/]\d{1,2}[.\/]\d{4}$/.test(v)||' &&
      '/^\d{8}$/.test(v);}' &&
      'function valid(req){var f="",t="Check the highlighted entries";bad("b",false);bad("dn",false);' &&
      'bad("ef",false);bad("et",false);' &&
      'if(req&&!$("b").value.replace(/\s/g,"")){bad("b",true);f="b";t="Fill in all required entry fields";}' &&
      'if(!/^[0-9A-Za-z*+,;\s-]*$/.test($("dn").value)){bad("dn",true);f=f||"dn";}' &&
      'if(!okd($("ef").value)){bad("ef",true);f=f||"ef";}' &&
      'if(!okd($("et").value)){bad("et",true);f=f||"et";}' &&
      'if(f){$(f).focus();msg(t);return false;}return true;}' &&
      'function go(a){if(BUSY)return;if(!valid(a!="VSAVE"))return;BUSY=true;$("busy").style.display="block";ev(a,"");}' &&
      'function bgv(){var v=$("bg");return !!v&&v.style.display!="none";}' &&
      'function bgo(){if(BUSY)return;if(!valid(true))return;msg("");$("bg").style.display="flex";bgm();' &&
      'try{$("bgi").checked?$("bgi").focus():$("bgd").focus();}catch(x){}}' &&
      'function bgx(){$("bg").style.display="none";}' &&
      'function bgm(){var l=$("bgl").checked;$("bgd").disabled=!l;$("bgt").disabled=!l;}' &&
      'function bgs(){if(BUSY)return;var x="bi=X",d,t,a,b;bad("bgd",false);bad("bgt",false);' &&
      'if($("bgl").checked){d=$("bgd").value;t=$("bgt").value;a=!!d&&okd(d);b=/^\d{1,2}:\d{2}/.test(t);' &&
      'bad("bgd",!a);bad("bgt",!b);if(!a||!b)return;x="bd="+enc(d)+"&bm="+enc(t);}' &&
      'bgx();BUSY=true;$("busy").style.display="block";ev("BG",x);}' &&
      'function xa(k){if(BUSY)return;BUSY=true;ev("XA","xa="+k);}' &&
      'function f4(){if(BUSY)return;BUSY=true;$("busy").style.display="block";ev("F4","");}' &&
      'var LT=String.fromCharCode(60),VR=[],VV=[],VSEL={},VK=0,VDIR=1;' &&
      'function vho(){var v=$("vh");return !!v&&v.style.display!="none";}' &&
      'function fdt(v){if(!v||v=="00000000")return "";' &&
      'return VDF.replace("YYYY",v.substr(0,4)).replace("MM",v.substr(4,2)).replace("DD",v.substr(6,2));}' &&
      'function vtd(v,c){return LT+"td"+(c?" class="+c:"")+">"+v+LT+"/td>";}' &&
      'function vhr(){var q=($("vhq").value||"").toLowerCase(),h=[],i,r,s;VV=[];' &&
      'for(i=0;VR.length>i;i++){r=VR[i];if(q&&(r.join(" ")+" "+fdt(r[4])).toLowerCase().indexOf(q)==-1)continue;' &&
      'VV.push(i);s=!!VSEL[r[0]];' &&
      'h.push(LT+"tr data-i="+i+(s?" class=sel":"")+">"+vtd(LT+"input type=checkbox"+(s?" checked":"")+">","c")+' &&
      'vtd(r[0],"k")+vtd(r[1])+vtd(r[2])+vtd(r[3])+vtd(fdt(r[4]))+vtd(r[5])+vtd(r[6])+vtd(r[7])+LT+"/tr>");}' &&
      '$("vhb").innerHTML=h.join("");$("vhn").innerHTML=VV.length;' &&
      '$("vhe").style.display=VV.length?"none":"block";vhcnt();}' &&
      'function vhcnt(){var n=0,a=VV.length>0,i;for(var k in VSEL)n++;' &&
      'for(i=0;VV.length>i;i++)if(!VSEL[VR[VV[i]][0]]){a=false;break;}' &&
      '$("vhc").innerHTML=n+" selected";$("vha").checked=a;}' &&
      'function vtr(e){e=e||window.event;var t=e.target||e.srcElement;while(t&&t.tagName!="TR")t=t.parentNode;return t;}' &&
      'function vhall(on){for(var i=0;VV.length>i;i++){var d=VR[VV[i]][0];if(on)VSEL[d]=1;else delete VSEL[d];}vhr();}' &&
      'function vsrt(k){if(VK==k)VDIR=-VDIR;else{VK=k;VDIR=1;}' &&
      'VR.sort(function(a,b){var x=a[k],y=b[k];if(x!==""&&y!==""&&!isNaN(x)&&!isNaN(y)){x=+x;y=+y;}' &&
      'return (x>y?1:y>x?-1:0)*VDIR;});' &&
      'var h=$("vth").cells;for(var i=1;h.length>i;i++)h[i].className=(i-1==k)?(VDIR>0?"asc":"desc"):"";vhr();}' &&
      'function vhx(){var v=$("vh");if(v)v.style.display="none";try{$("dn").focus();}catch(x){}}' &&
      'function vhok(){var t=toks(),o=[],ld={},i;for(i=0;VR.length>i;i++)ld[VR[i][0]]=1;' &&
      'for(i=0;t.length>i;i++)if(/[*+-]/.test(t[i])||!ld[t[i]])o.push(t[i]);' &&
      'for(var k in VSEL)if(o.indexOf(k)==-1)o.push(k);' &&
      '$("dn").value=o.join(", ");vhx();sync();}' &&
      'function vhgo(){if(BUSY)return;if(!okd($("vf").value)||!okd($("vt").value)){' &&
      'bad("vf",!okd($("vf").value));bad("vt",!okd($("vt").value));return;}' &&
      'BUSY=true;var p=["vd="+enc(toks2($("vd").value)),"vf="+enc($("vf").value),"vt="+enc($("vt").value),' &&
      '"vk="+enc($("vk").value),"vb="+enc($("vb").value),"vm="+enc($("vm").value)],j=0;' &&
      'for(var k in VSEL)p.push("vs"+(j++)+"="+enc(k));$("busy").style.display="block";ev("VHGO",p.join("&"));}' &&
      'function toks2(v){return v.split(/[,;\s]+/).join(",");}' &&
      'function vhi(){if(!$("vh")||typeof VHD=="undefined")return;var d=VHD.split("^"),i,s;' &&
      'for(i=0;d.length>i;i++)if(d[i])VR.push(d[i].split("~"));' &&
      's=toks();for(i=0;s.length>i;i++)VSEL[s[i]]=1;s=VHS?VHS.split(","):[];for(i=0;s.length>i;i++)if(s[i])VSEL[s[i]]=1;' &&
      '$("vhq").onkeyup=vhr;' &&
      '$("vhb").onclick=function(e){var t=vtr(e);if(!t)return;var d=VR[t.getAttribute("data-i")][0];' &&
      'if(VSEL[d])delete VSEL[d];else VSEL[d]=1;var s=!!VSEL[d];t.className=s?"sel":"";' &&
      't.cells[0].firstChild.checked=s;vhcnt();};' &&
      '$("vhb").ondblclick=function(e){var t=vtr(e);if(!t)return;VSEL={};VSEL[VR[t.getAttribute("data-i")][0]]=1;vhok();};' &&
      'vhr();try{$("vhq").focus();}catch(x){}}' &&
      'function tgs(){var c="PWSE";for(var i=0;c.length>i;i++){var e=$("st"+c.charAt(i));' &&
      'e.parentNode.className=e.checked?"tg on":"tg";}}' &&
      'function clr(){var d=["b","dn","ef","et","bt","ty"],c="PWSE",i;for(i=0;d.length>i;i++)$(d[i]).value="";' &&
      'for(i=0;c.length>i;i++)$("st"+c.charAt(i)).checked=false;tgs();msg("");sync();}' &&
      'function dsup(){var t=document.createElement("input");try{t.setAttribute("type","date");}catch(e){return false;}' &&
      'return t.type=="date";}' &&
      'function ini(){var d=["ef","et","vf","vt","bgd"],i,e,m,f,n=["b","dn","ef","et","bt","ty","stE","stW","stS","stP"];' &&
      'var ds=dsup();for(i=0;d.length>i;i++){e=$(d[i]);if(!e)continue;if(ds)e.setAttribute("type","date");' &&
      'else{m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(e.value);if(m)e.value=m[3]+"."+m[2]+"."+m[1];' &&
      'e.setAttribute("placeholder","DD.MM.YYYY");}}' &&
      'for(i=0;n.length>i;i++)$(n[i]).onchange=function(){tgs();sync();};' &&
      'document.onkeydown=function(e){e=e||window.event;var t=e.target||e.srcElement;' &&
      'if(bgv()){if(e.keyCode==27){bgx();return false;}if(e.keyCode==13){bgs();return false;}return;}' &&
      'if(vho()){if(e.keyCode==27){vhx();return false;}' &&
      'if(e.keyCode==13){if(t&&t.id!="vhq"&&t.tagName=="INPUT")vhgo();return false;}return;}' &&
      'if(e.keyCode==115&&t&&t.id=="dn"){f4();return false;}' &&
      'if(e.keyCode==13&&t&&(t.tagName=="INPUT"||t.tagName=="SELECT")){go("GO");return false;}};' &&
      'tgs();snap();f=document.body.getAttribute("data-fo")||"b";if($(f)){try{$(f).focus();}catch(x){}}vhi();}ini();'.
  ENDMETHOD.

  METHOD h.
    rv = escape( val = condense( |{ iv }| ) format = cl_abap_format=>e_html_attr ).
  ENDMETHOD.

  METHOD label.
    "Labels = selection texts of the standard screen (see form INIT_TEXTS)
    DATA lv_empty TYPE string.
    DATA(lv_name) = |%_{ iv_name }_%_APP_%-TEXT|.
    ASSIGN (lv_name) TO FIELD-SYMBOL(<lv_text>).
    IF sy-subrc EQ 0.
      rv = condense( CONV string( <lv_text> ) ).
    ENDIF.
    IF rv IS INITIAL.
      rv = iv_default.
    ENDIF.
    "Format hints like '(P/W/S/E)' are shown as options on the page
    rv = h( replace( val = rv pcre = '\s*\([^)]*\)\s*$' with = lv_empty ) ).
  ENDMETHOD.

  METHOD listbox.
    "Values of the listbox = fixed values of the domain (as on the screen)
    DATA lt_fix TYPE ddfixvalues.
    DATA(lv_cur) = condense( CONV string( iv_value ) ).
    DATA(lv_found) = xsdbool( lv_cur IS INITIAL ).
    rv = '<option value="">All</option>'.
    DATA(lo_elem) = CAST cl_abap_elemdescr( cl_abap_typedescr=>describe_by_data( iv_value ) ).
    IF lo_elem->is_ddic_type( ) EQ abap_true.
      lt_fix = lo_elem->get_ddic_fixed_values( ).
    ENDIF.
    LOOP AT lt_fix INTO DATA(ls_fix) WHERE option EQ 'EQ'.
      DATA(lv_low) = condense( CONV string( ls_fix-low ) ).
      DATA(lv_sel) = COND string( WHEN lv_low EQ lv_cur THEN ' selected' ).
      IF lv_low EQ lv_cur.
        lv_found = abap_true.
      ENDIF.
      rv = rv && |<option value="{ h( lv_low ) }"{ lv_sel }>{ h( lv_low ) } - { h( ls_fix-ddtext ) }</option>|.
    ENDLOOP.
    IF lv_found EQ abap_false.
      rv = rv && |<option value="{ h( lv_cur ) }" selected>{ h( lv_cur ) }</option>|.
    ENDIF.
  ENDMETHOD.


  METHOD chip.
    DATA(lv_on) = xsdbool( iv_sel CS iv_code ).
    rv = |<label class="tg{ COND string( WHEN lv_on EQ abap_true THEN ' on' ) }">| &&
         |<input type="checkbox" id="st{ iv_code }"{ COND string( WHEN lv_on EQ abap_true THEN ' checked' ) }>| &&
         |<span class="dot { iv_cls }"></span>{ iv_text }</label>|.
  ENDMETHOD.

  METHOD adv_note.
    CHECK iv_count GT 0.
    rv = |<div class="adv">+ { iv_count } further condition(s) of the variant (e.g. exclusions) are kept| &&
         |<a onclick="xa('{ iv_key }')">Remove</a></div>|.
  ENDMETHOD.

  METHOD to_iso.
    CHECK iv_date IS NOT INITIAL.
    rv = |{ iv_date+0(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
  ENDMETHOD.

  METHOD parse_date.
    DATA: lv_y TYPE string,
          lv_m TYPE string,
          lv_d TYPE string.
    CLEAR ev_date.
    ev_ok = abap_true.
    DATA(lv) = condense( iv ).
    CHECK lv IS NOT INITIAL.
    FIND PCRE '^(\d{4})-(\d{1,2})-(\d{1,2})$' IN lv SUBMATCHES lv_y lv_m lv_d.
    IF sy-subrc NE 0.
      FIND PCRE '^(\d{1,2})[./](\d{1,2})[./](\d{4})$' IN lv SUBMATCHES lv_d lv_m lv_y.
    ENDIF.
    IF sy-subrc NE 0.
      FIND PCRE '^(\d{4})(\d{2})(\d{2})$' IN lv SUBMATCHES lv_y lv_m lv_d.
    ENDIF.
    IF sy-subrc NE 0.
      ev_ok = abap_false.
      RETURN.
    ENDIF.
    ev_date = |{ lv_y }{ lv_m ALIGN = RIGHT PAD = '0' WIDTH = 2 }{ lv_d ALIGN = RIGHT PAD = '0' WIDTH = 2 }|.
    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date                      = ev_date
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc NE 0.
      CLEAR ev_date.
      ev_ok = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD doc_in.
    rv = iv.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = rv
      IMPORTING
        output = rv.
  ENDMETHOD.

  METHOD doc_out.
    rv = |{ iv ALPHA = OUT }|.
    CONDENSE rv.
  ENDMETHOD.

ENDCLASS.

INITIALIZATION.
  PERFORM init_texts.
  t_1001 = 'E-Invoice - Customer Cockpit'.

"HTML cockpit (screen 1001) - replaces the former ALV grid
AT SELECTION-SCREEN OUTPUT.
  "HTML selection screen (screen 1000) - covers the standard selection screen
  IF sy-dynnr EQ '1000'.
    lcl_selscreen=>pbo( ).
  ENDIF.
  IF sy-dynnr EQ '1001'.
    lcl_cockpit=>pbo( ).
  ENDIF.

AT SELECTION-SCREEN.
  IF sy-dynnr EQ '1000'.
    lcl_selscreen=>pai( sscrfields-ucomm ).
  ENDIF.
  IF sy-dynnr EQ '1001'.
    lcl_cockpit=>pai( sscrfields-ucomm ).
  ENDIF.

START-OF-SELECTION.
  lcl_selscreen=>hide( ).

  lcl_app=>get_data( ).

  "Background mode: process every open document
  IF sy-batch EQ abap_true.
    lcl_app=>select_all( ).
    lcl_app=>process( ).
  ENDIF.

  PERFORM display_cockpit.

*&---------------------------------------------------------------------*
*& Form display_cockpit - HTML cockpit (screen 1001), replaces the ALV
*&---------------------------------------------------------------------*
FORM display_cockpit.

  "Background: no GUI controls - write a list to the spool instead
  IF sy-batch EQ abap_true.
    PERFORM write_list.
    RETURN.
  ENDIF.

  CALL SELECTION-SCREEN 1001.
  lcl_cockpit=>free( ).

ENDFORM.
*&---------------------------------------------------------------------*
*& Form write_list - result of the background processing
*&---------------------------------------------------------------------*
*& The result is written to the job log (SM37 - Job Log) instead of a
*& spool list: no spool request has to be created, so the job finishes
*& right after the processing and does not depend on the spool system
*& (a full / faulty spool made the job wait and end with the runtime
*& error SPOOL_INTERNAL_ERROR at the first WRITE).
*&---------------------------------------------------------------------*
FORM write_list.
  MESSAGE |Customer E-Invoice Cockpit: { lines( gt_output ) } document(s)| TYPE 'S'.
  LOOP AT gt_output INTO DATA(ls_out).
    MESSAGE |{ ls_out-companycode } { ls_out-sapdocument ALPHA = OUT } { ls_out-fiscalyear } | &&
            |{ ls_out-documenttype } { ls_out-einvoicetype } { ls_out-messagetype } { ls_out-stattext } | &&
            |{ ls_out-totalvalue CURRENCY = ls_out-currency } { ls_out-currency }| TYPE 'S'.
  ENDLOOP.
ENDFORM.
