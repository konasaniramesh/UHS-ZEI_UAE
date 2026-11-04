*----------------------------------------------------------------------*
***INCLUDE ZEINVOICE_CONFIG_TABLES_PBO.
*----------------------------------------------------------------------*

CLASS lcl_event IMPLEMENTATION.

  METHOD on_sapevent.
    "Click on an entry: remember it and continue in PAI (OK code ZOPEN),
    "so that the maintenance screens are called in normal dialog flow
    CHECK to_upper( action ) EQ 'OPEN'.
    LOOP AT query_table INTO DATA(ls_query).
      IF to_upper( condense( CONV string( ls_query-name ) ) ) EQ 'K'.
        DATA(lv_key) = to_upper( condense( CONV string( ls_query-value ) ) ).
      ENDIF.
    ENDLOOP.
    CHECK lv_key IS NOT INITIAL AND line_exists( gt_items[ key = lv_key ] ).
    gv_open = lv_key.
    cl_gui_cfw=>set_new_ok_code( new_code = gc_open ).
  ENDMETHOD.

  METHOD open_view.

    DATA: lv_viewname TYPE tabname.

    READ TABLE gt_items INTO DATA(ls_item) WITH KEY key = iv_key.
    CHECK sy-subrc EQ 0.
    lv_viewname = ls_item-view.

    IF lv_viewname IS NOT INITIAL.

      "The page covers the whole screen - hide it during the maintenance
      IF go_html IS BOUND.
        go_html->set_visible( EXPORTING visible = abap_false EXCEPTIONS OTHERS = 1 ).
      ENDIF.

      CALL FUNCTION 'VIEW_MAINTENANCE_CALL'
        EXPORTING
          action                       = 'U'
          view_name                    = lv_viewname
        EXCEPTIONS
          client_reference             = 1
          foreign_lock                 = 2
          invalid_action               = 3
          no_clientindependent_auth    = 4
          no_database_function         = 5
          no_editor_function           = 6
          no_show_auth                 = 7
          no_tvdir_entry               = 8
          no_upd_auth                  = 9
          only_show_allowed            = 10
          system_failure               = 11
          unknown_field_in_dba_sellist = 12
          view_not_found               = 13
          maintenance_prohibited       = 14
          OTHERS                       = 15.

      "Shown again (without reloading) in the PBO of screen 9000
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Module STATUS_9000 OUTPUT
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
MODULE status_9000 OUTPUT.
  SET PF-STATUS 'STATUS'.
  SET TITLEBAR 'TITLE'.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module BUILD_TREE OUTPUT - HTML start page (replaces the simple tree)
*&---------------------------------------------------------------------*
*& Performance: the page is built and loaded only once. When the screen
*& is shown again (e.g. back from a view maintenance) it is only made
*& visible - no rebuild, no reload.
*&---------------------------------------------------------------------*
MODULE build_tree OUTPUT.

  IF go_html IS BOUND.
    "Already loaded - only show it again (e.g. back from a view maintenance)
    go_html->set_visible( EXPORTING visible = abap_true EXCEPTIONS OTHERS = 1 ).
  ELSE.
    PERFORM create_page.
  ENDIF.

ENDMODULE.

*&---------------------------------------------------------------------*
*& Form CREATE_PAGE - HTML viewer on the full screen area (resizes with
*& the SAP window), event registration (once) and the page itself
*&---------------------------------------------------------------------*
FORM create_page.

  DATA lt_events TYPE cntl_simple_events.

  CREATE OBJECT go_html
    EXPORTING
      parent = cl_gui_container=>screen0
    EXCEPTIONS
      OTHERS = 1.
  IF sy-subrc NE 0.
    CLEAR go_html.
    RETURN.
  ENDIF.

  APPEND VALUE cntl_simple_event( eventid    = go_html->m_id_sapevent
                                  appl_event = abap_false ) TO lt_events.
  go_html->set_registered_events( EXPORTING events = lt_events
                                  EXCEPTIONS OTHERS = 1 ).
  CREATE OBJECT go_event.
  SET HANDLER go_event->on_sapevent FOR go_html.

  PERFORM fill_items.
  PERFORM load_page.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FILL_ITEMS - entries of the page (same texts / views as the tree)
*&---------------------------------------------------------------------*
FORM fill_items.

  "Sections in display order - GRP of an entry = row number here
  gt_groups = VALUE #(
    ( icon = 'i1' color = 'g1' title = 'Company Configuration'
      descr = 'Company groups, company registration and business partner types' )
    ( icon = 'i2' color = 'g2' parent = 'Lookups' title = 'General'
      pdescr = 'Code lists and determinations used in the e-invoice'
      descr = 'Code lists shared by all business processes' )
    ( icon = 'i4' color = 'g2' parent = 'Lookups' title = 'Sales & Distribution (SD)'
      descr = 'Billing types, credit note reasons, partner functions and SD determinations' )
    ( icon = 'i5' color = 'g2' parent = 'Lookups' title = 'Financial Accounting (FI)'
      descr = 'FI document types and credit note reasons' )
    ( icon = 'i6' color = 'g2' parent = 'Lookups' title = 'Settlement Management (SM)'
      descr = 'Settlement document types and credit note reasons' )
    ( icon = 'i3' color = 'g3' title = 'API Configuration'
      descr = 'Connection to the Access Service Provider (ASP)' ) ).

  "Keys and views unchanged - only the section (GRP) is new
  gt_items = VALUE #(
    "Company Configuration
    ( key = 'R1C1'  grp = 1 text = 'Company Groups'                 view = 'ZEINV_COMPANYGRP' )
    ( key = 'R1C2'  grp = 1 text = 'Company Registration'           view = 'ZEINV_COMPANY' )
    ( key = 'R1C3'  grp = 1 text = 'Bus. Partner - Business Types'  view = 'ZEINV_BUSI_TYPE' )
    "Lookups: General (cross-process)
    ( key = 'R2C4'  grp = 2 text = 'Tax Category'                   view = 'ZEINV_TAXTYPE' )
    ( key = 'R2C5'  grp = 2 text = 'Regions'                        view = 'ZEINV_STATE' )
    ( key = 'R2C6'  grp = 2 text = 'Unit of Measure'                view = 'ZEINV_UNITCODE' )
    ( key = 'R2C7'  grp = 2 text = 'Allowance/Charge Reason Codes'  view = 'ZEINV_ALLOWANCE' )
    ( key = 'R2C8'  grp = 2 text = 'Payment Means'                  view = 'ZEINV_PAY_METHOD' )
    ( key = 'R2C9'  grp = 2 text = 'Item Types'                     view = 'ZEINV_ITEM_TYPE' )
    "Lookups: Sales & Distribution
    ( key = 'R2C1'  grp = 3 text = 'Invoice Type SD'                view = 'ZEINV_INVTYPE_SD' )
    ( key = 'R2C10' grp = 3 text = 'Credit Note Reason SD'          view = 'ZEINV_CN_RSN_SD' )
    ( key = 'R2C14' grp = 3 text = 'Customer Partner Function'      view = 'ZEINV_CUS_PF_DET' )
    ( key = 'R2C13' grp = 3 text = 'Delivery & Agent Prtn Func'     view = 'ZEINV_DLV_PF_DET' )
    ( key = 'R2C15' grp = 3 text = 'E-commerce determination'       view = 'ZEINV_DCHANNEL' )
    ( key = 'R2C16' grp = 3 text = 'Item Category (Deemed Supply)'  view = 'ZEINV_ITEM_CATEG' )
    "Lookups: Financial Accounting
    ( key = 'R2C2'  grp = 4 text = 'Invoice Type FI'                view = 'ZEINV_INVTYPE_FI' )
    ( key = 'R2C11' grp = 4 text = 'Credit Note Reason FI'          view = 'ZEINV_CN_RSN_FI' )
    "Lookups: Settlement Management
    ( key = 'R2C3'  grp = 5 text = 'Invoice Type SM'                view = 'ZEINV_INVTYPE_SM' )
    ( key = 'R2C12' grp = 5 text = 'Credit Note Reason STLM'        view = 'ZEINV_CN_RSN_SM' )
    "API Configuration
    ( key = 'R3C1'  grp = 6 text = 'Maintain API URL'               view = 'ZEINVOICE_APIURL' ) ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form LOAD_PAGE - build the HTML page and load it into the viewer
*&---------------------------------------------------------------------*
FORM load_page.

  TYPES: ty_line TYPE c LENGTH 255,
         BEGIN OF ty_sec,              "tiles of one section
           tiles TYPE string,
           cnt   TYPE i,
         END OF ty_sec.
  DATA: lt_data TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY,
        lt_sec  TYPE STANDARD TABLE OF ty_sec WITH EMPTY KEY,
        lv_url  TYPE c LENGTH 255,
        lv_html TYPE string,
        lv_secs TYPE string,
        lv_size TYPE i.

  "Search icon in the header (inline SVG - no files to load)
  DATA(lv_svg) = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"' &&
                 ' stroke-linecap="round" stroke-linejoin="round">'.

  "Section icons as an SVG sprite: each path is sent once, the tiles only
  "reference it (<use>) - keeps the page small whatever the number of entries
  DATA(lv_sprite) =
    `<svg class="sv" aria-hidden="true">` &&
    `<symbol id="i1" viewBox="0 0 24 24"><path d="M3 21h18M5 21V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16"/>` &&
    `<path d="M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2"/></symbol>` &&
    `<symbol id="i2" viewBox="0 0 24 24"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></symbol>` &&
    `<symbol id="i3" viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5"/>` &&
    `<path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5"/></symbol>` &&
    `<symbol id="i4" viewBox="0 0 24 24"><circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/>` &&
    `<path d="M2 3h3l2.7 11.4a2 2 0 0 0 2 1.6h8.6a2 2 0 0 0 2-1.6L22 7H6"/></symbol>` &&
    `<symbol id="i5" viewBox="0 0 24 24"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>` &&
    `<path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></symbol>` &&
    `<symbol id="i6" viewBox="0 0 24 24"><path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/>` &&
    `<path d="M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></symbol></svg>`.

  "One pass over the entries: tiles are collected per section (row = GRP)
  DO lines( gt_groups ) TIMES.
    APPEND INITIAL LINE TO lt_sec.
  ENDDO.
  LOOP AT gt_items ASSIGNING FIELD-SYMBOL(<ls_item>).
    ASSIGN lt_sec[ <ls_item>-grp ] TO FIELD-SYMBOL(<ls_sec>).
    CHECK sy-subrc EQ 0.
    ASSIGN gt_groups[ <ls_item>-grp ] TO FIELD-SYMBOL(<ls_grp>).
    <ls_sec>-cnt = <ls_sec>-cnt + 1.
    <ls_sec>-tiles = <ls_sec>-tiles &&
      |<button class="t" data-k="{ <ls_item>-key }" onclick="op(this)" title="Maintain { <ls_item>-view }">| &&
      |<span class="ic { <ls_grp>-color }"><svg><use xlink:href="#{ <ls_grp>-icon }"/></svg></span>| &&
      |<span class="tt">{ escape( val = <ls_item>-text format = cl_abap_format=>e_html_text ) }</span>| &&
      |<span class="tv">{ <ls_item>-view }</span></button>|.
  ENDLOOP.

  "Sections in the order of GT_GROUPS (empty ones are not rendered).
  "Consecutive sections with the same PARENT are wrapped in one <article>
  "with the parent as main title and the sections as sub-titles.
  DATA: lv_par   TYPE string,
        lv_pdesc TYPE string,
        lv_kids  TYPE string,
        lv_kcnt  TYPE i.
  LOOP AT gt_groups ASSIGNING <ls_grp>.
    ASSIGN lt_sec[ sy-tabix ] TO <ls_sec>.
    CHECK <ls_sec>-cnt GT 0.
    IF <ls_grp>-parent NE lv_par.
      IF lv_par IS NOT INITIAL.
        lv_secs = lv_secs &&
          |<article><h2>{ escape( val = lv_par format = cl_abap_format=>e_html_text ) }<em>{ lv_kcnt }</em></h2>| &&
          |<div class="sd">{ escape( val = lv_pdesc format = cl_abap_format=>e_html_text ) }</div>{ lv_kids }</article>|.
      ENDIF.
      CLEAR: lv_kids, lv_kcnt.
      lv_par   = <ls_grp>-parent.
      lv_pdesc = <ls_grp>-pdescr.
    ENDIF.
    DATA(lv_h) = COND string( WHEN <ls_grp>-parent IS INITIAL THEN `h2` ELSE `h3` ).
    DATA(lv_one) =
      |<section><{ lv_h }>{ escape( val = <ls_grp>-title format = cl_abap_format=>e_html_text ) }| &&
      |<em>{ <ls_sec>-cnt }</em></{ lv_h }>| &&
      |<div class="sd">{ escape( val = <ls_grp>-descr format = cl_abap_format=>e_html_text ) }</div>| &&
      |<div class="gr">{ <ls_sec>-tiles }</div></section>|.
    IF <ls_grp>-parent IS INITIAL.
      lv_secs = lv_secs && lv_one.
    ELSE.
      lv_kids = lv_kids && lv_one.
      lv_kcnt = lv_kcnt + <ls_sec>-cnt.
    ENDIF.
  ENDLOOP.
  IF lv_par IS NOT INITIAL.
    lv_secs = lv_secs &&
      |<article><h2>{ escape( val = lv_par format = cl_abap_format=>e_html_text ) }<em>{ lv_kcnt }</em></h2>| &&
      |<div class="sd">{ escape( val = lv_pdesc format = cl_abap_format=>e_html_text ) }</div>{ lv_kids }</article>|.
  ENDIF.

  lv_html =
    |<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">| &&
    |<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>| &&
    '*{box-sizing:border-box}html,body{margin:0;padding:0}' &&
    'body{font-family:"72","72full",Arial,Helvetica,sans-serif;font-size:13px;color:#1d2d3e;background:#f5f6f7}' &&
    '.hd{position:sticky;top:0;z-index:2;display:flex;flex-wrap:wrap;align-items:center;background:#fff;' &&
    'border-bottom:1px solid #d9d9d9;padding:10px 24px}' &&
    '.sp{flex:1}.nc{color:#556b82;font-size:12px}.nc b{color:#1d2d3e}' &&
    '.sb{position:relative;margin:6px 0}.sb svg{position:absolute;left:12px;top:10px;width:14px;height:14px;color:#556b82}' &&
    '.sb input{font:inherit;width:320px;max-width:80vw;height:34px;border:1px solid #bcc3ca;border-radius:17px;' &&
    'padding:0 14px 0 34px;background:#fff;color:#1d2d3e}' &&
    '.sb input:focus{outline:none;border-color:#0070f2;box-shadow:0 0 0 2px rgba(0,112,242,.2)}' &&
    '.ct{padding:18px 24px 24px}section{margin:0 0 24px}' &&
    'h2{font-size:14px;font-weight:700;margin:0 0 2px}' &&
    'h2 em{font-style:normal;font-weight:600;font-size:11px;color:#556b82;background:#eaecee;border-radius:10px;' &&
    'padding:1px 8px;margin-left:8px;vertical-align:middle}' &&
    '.sd{color:#6a6d70;font-size:12px;margin:0 0 10px}' &&
    '.gr{display:flex;flex-wrap:wrap;margin:0 -6px}' &&
    '.t{font:inherit;color:inherit;text-align:left;width:230px;margin:6px;padding:14px;min-height:100px;background:#fff;' &&
    'border:1px solid #d9d9d9;border-radius:10px;cursor:pointer;display:flex;flex-direction:column;align-items:flex-start;' &&
    'transition:box-shadow .15s,border-color .15s,transform .15s}' &&
    '@supports (display:grid){.gr{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;' &&
    'margin:0}.t{width:auto;margin:0}}' &&
    '.t:hover{border-color:#0070f2;box-shadow:0 4px 14px rgba(0,0,0,.10);transform:translateY(-1px)}' &&
    '.t:focus{outline:none;border-color:#0070f2;box-shadow:0 0 0 2px rgba(0,112,242,.25)}.t.on{opacity:.55}' &&
    '.ic{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;justify-content:center;margin:0 0 10px}' &&
    '.ic svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}' &&
    '.sv{position:absolute;width:0;height:0;overflow:hidden}' &&
    'article{margin:0 0 24px}article>section{margin:14px 0 0}' &&
    'h3{font-size:13px;font-weight:700;margin:0 0 2px}h3 em{font-style:normal;font-weight:600;font-size:11px;color:#556b82;' &&
    'background:#eaecee;border-radius:10px;padding:1px 8px;margin-left:8px;vertical-align:middle}' &&
    '.g1{background:#e5f0fe;color:#0064d9}.g2{background:#eaf5ea;color:#188918}.g3{background:#fff3e5;color:#c35500}' &&
    '.tt{font-weight:600;line-height:1.3}.tv{color:#6a6d70;font-size:11px;margin-top:4px;font-family:Consolas,monospace}' &&
    '#nm{display:none;color:#556b82;text-align:center;padding:40px}' &&
    '@media (min-width:1600px){body{font-size:14px}.ct,.hd{padding-left:32px;padding-right:32px}' &&
    '.gr{grid-template-columns:repeat(auto-fill,minmax(250px,1fr))}.t{min-height:108px}}' &&
    '@media (max-width:640px){.hd,.ct{padding-left:12px;padding-right:12px}.sb input{width:100%}}' &&
    "--- Fiori Launchpad (Horizon) look - CSS override only, functionality unchanged ---
    'html{background:#f5f6f7;min-height:100%}' &&
    'body{min-height:100vh}' &&
    'body{font-family:"72","72full",Arial,Helvetica,sans-serif;background:#f5f6f7;' &&
    'background-image:linear-gradient(180deg,#eaecee 0,#f5f6f7 260px);color:#1d2d3e}' &&
    '.hd{background:#fff;border-bottom:0;box-shadow:0 0 .125rem 0 rgba(34,53,72,.15),0 .125rem .5rem 0 rgba(34,53,' &&
    '72,.15);padding:0 1rem;min-height:3.25rem}' &&
    '.tv{display:none}' &&
    '.sb{margin:.5rem 0}' &&
    '.sb input{height:2.25rem;width:22rem;border:none;border-radius:1.125rem;background:#eff1f2;' &&
    'box-shadow:inset 0 0 0 1px rgba(85,107,130,.25);color:#1d2d3e}' &&
    '.sb input:hover{background:#e5e8eb}' &&
    '.sb input:focus{background:#fff;box-shadow:inset 0 0 0 1px #0064d9,0 0 0 2px rgba(0,100,217,.25)}' &&
    '.nc{background:#eff1f2;border-radius:1rem;padding:.25rem .75rem}' &&
    '.ct{padding:1.5rem 2rem 2rem}' &&
    'section,article{margin:0 0 2rem}' &&
    'article>section{margin:0 0 1.5rem}' &&
    'h2{font-size:1.25rem;font-weight:700;color:#1d2d3e;margin:0 0 .25rem}' &&
    'h3{font-size:1rem;font-weight:700;color:#1d2d3e;margin:.75rem 0 .25rem}' &&
    'h2 em,h3 em{background:#fff;color:#556b82;box-shadow:inset 0 0 0 1px #d9d9d9;border-radius:.625rem;' &&
    'font-size:.75rem;font-weight:600}' &&
    '.sd{color:#556b82;font-size:.875rem;margin:0 0 .75rem}' &&
    '.gr{display:flex;flex-wrap:wrap;gap:.5rem;margin:0}' &&
    '@supports (display:grid){.gr{display:grid;grid-template-columns:repeat(auto-fill,11rem);gap:.5rem;margin:0}}' &&
    '.t{width:11rem;height:11rem;min-height:11rem;margin:0;padding:1rem;background:#fff;border:none;' &&
    'border-radius:1rem;' &&
    'box-shadow:0 0 .125rem 0 rgba(34,53,72,.2),0 .125rem .25rem 0 rgba(34,53,72,.2);' &&
    'display:flex;flex-direction:column;align-items:flex-start;overflow:hidden;' &&
    'transition:box-shadow .15s ease,transform .15s ease}' &&
    '.t:hover{box-shadow:0 0 .125rem 0 rgba(34,53,72,.2),0 .5rem 1rem 0 rgba(34,53,72,.2);transform:none;' &&
    'border:none}' &&
    '.t:active{background:#ebf8ff}' &&
    '.t:focus{outline:none;box-shadow:0 0 0 .125rem #0032a5,0 .125rem .25rem 0 rgba(34,53,72,.2)}' &&
    '.t.on{opacity:.55}' &&
    '.tt{order:1;font-size:1rem;font-weight:700;line-height:1.25rem;color:#1d2d3e;max-height:3.75rem;' &&
    'overflow:hidden}' &&
    '.tv{order:2;font-size:.75rem;font-family:"72",Arial,sans-serif;color:#556b82;margin-top:.25rem;' &&
    'word-break:break-all}' &&
    '.ic{order:3;margin:auto 0 0 0;width:2.5rem;height:2.5rem;border-radius:.75rem}' &&
    '.ic svg{width:1.5rem;height:1.5rem}' &&
    '@media (min-width:1600px){.gr{grid-template-columns:repeat(auto-fill,11rem)}.t{min-height:11rem}}' &&
    '@media (max-width:640px){.ct{padding:1rem}.hd::before{display:none}.sb input{width:100%}.gr{' &&
    'grid-template-columns:repeat(auto-fill,minmax(9.5rem,1fr))}.t{width:auto;height:9.5rem;min-height:9.5rem}}' &&
    "--- Fiori Launchpad tabs + plain icons (CSS only) ---
    '.sp{display:none}' &&
    '.hd{padding:0 1rem 0 0;align-items:center}' &&
    '.tb{order:1;flex:1 1 auto;display:flex;align-items:stretch;min-width:0;overflow-x:auto;height:3rem;' &&
    'margin-right:1rem}' &&
    '.sb{order:2}.nc{order:3;margin-left:.75rem}.sb input{width:16rem}' &&
    '.ti{display:flex;align-items:center;padding:0 1rem;font-size:.875rem;font-weight:600;color:#1d2d3e;' &&
    'cursor:pointer;white-space:nowrap;position:relative}' &&
    '.ti:hover{background:#eaecee}.ti.sel{color:#0064d9}' &&
    '.ti.sel:after{content:"";position:absolute;left:.75rem;right:.75rem;bottom:0;height:.1875rem;' &&
    'background:#0064d9;border-radius:.125rem .125rem 0 0}' &&
    '.ti:focus{outline:2px solid #0032a5;outline-offset:-2px}' &&
    '.tdv{width:1px;background:#d9d9d9;margin:.75rem .25rem;flex:none}' &&
    '.ct>.off{display:none}' &&
    '.ic,.ic.g1,.ic.g2,.ic.g3{background:none;color:#5b738b;width:auto;height:2.5rem;justify-content:flex-start;' &&
    'border-radius:0}' &&
    '.ic svg{width:2rem;height:2rem}' &&
    '.tt{font-weight:600}' &&
    "--- Group title, count and description hidden - the tab shows the group ---
    '.ct>section>h2,.ct>section>h2+.sd,.ct>article>h2,.ct>article>h2+.sd{display:none}' &&
    'article>section>h3+.sd{display:none}' &&
    '@media (max-width:640px){.tb{flex-basis:100%;margin-right:0}.sb{flex:1;margin-left:1rem}}' &&
    |</style></head><body>{ lv_sprite }| &&
    |<div class="hd"><div class="sb">{ lv_svg }<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>| &&
    |<input id="q" type="text" placeholder="Search configuration" autocomplete="off" oninput="flt()" onkeyup="flt()"></div>| &&
    |<span class="sp"></span><span class="nc"><b id="nt">{ lines( gt_items ) }</b><i id="nw" style="font-style:normal"> entries</i></span></div>| &&
    |<div class="ct">{ lv_secs }<div id="nm">No entry matches the search</div></div>| &&
    |<a id="sapev" href="SAPEVENT:NONE" style="display:none"></a><script>| &&
    'function $(i){return document.getElementById(i);}' &&
    'var WEB=!!(window.parent&&window.parent!==window),BUSY=false;' &&
    'function sap(a){if(WEB){window.parent.postMessage(JSON.stringify({type:"request",' &&
    'service:"sap.gui.triggerSAPEvent",request_id:"ev"+(new Date()).getTime(),body:{args:{action:a}}}),"*");}' &&
    'else{var l=$("sapev");l.href="SAP"+"EVENT:"+a;l.click();}}' &&
    'function op(b){if(BUSY)return;BUSY=true;b.className="t on";sap("OPEN?k="+b.getAttribute("data-k"));' &&
    'setTimeout(function(){BUSY=false;b.className="t";},1500);}' &&
    'function flt(){var q=$("q").value.toLowerCase().replace(/^\s+|\s+$/g,""),s=document.getElementsByTagName("section"),' &&
    'n=0,i,j,t,v,ok;for(i=0;s.length>i;i++){t=s[i].getElementsByTagName("button");v=0;' &&
    'for(j=0;t.length>j;j++){ok=!q||(t[j].textContent||t[j].innerText).toLowerCase().indexOf(q)!=-1;' &&
    't[j].style.display=ok?"":"none";if(ok)v++;}s[i].style.display=v?"":"none";' &&
    'var c=s[i].getElementsByTagName("em")[0];if(c)c.innerHTML=v;n+=v;}$("nm").style.display=n?"none":"block";' &&
    'var g=document.getElementsByTagName("article");for(i=0;g.length>i;i++){t=g[i].getElementsByTagName("button");v=0;' &&
    'for(j=0;t.length>j;j++)if(t[j].style.display!="none")v++;g[i].style.display=v?"":"none";' &&
    'g[i].getElementsByTagName("em")[0].innerHTML=v;}' &&
    '$("nt").innerHTML=n;$("nw").innerHTML=(n==1?" entry":" entries");}' &&
    'document.onkeydown=function(e){e=e||window.event;var t=e.target||e.srcElement;if(!t||t.id!="q")return;' &&
    'if(e.keyCode==27){t.value="";flt();return false;}' &&
    'if(e.keyCode==13){var b=document.getElementsByTagName("button"),f=null,c=0,i;' &&
    'for(i=0;b.length>i;i++)if(b[i].style.display!="none"){c++;if(!f)f=b[i];}if(c==1)op(f);return false;}};' &&
    "--- Fiori Launchpad tabs: one tab per group; search shows all; existing flt()/op() untouched ---
    '(function(){var hd=document.querySelector(".hd"),ct=document.querySelector(".ct");' &&
    'if(!hd||!ct)return;var P=[],T=[],cur=0,i,c;' &&
    'for(i=0;i<ct.children.length;i++){c=ct.children[i];if(c.id!=="nm")P.push(c);}' &&
    'if(!P.length)return;' &&
    'var nav=document.createElement("nav");nav.className="tb";' &&
    'nav.setAttribute("role","tablist");' &&
    'function qv(){var q=$("q");return q?q.value.replace(/^\s+|\s+$/g,""):"";}' &&
    'function apply(){var s=qv(),k;for(k=0;k<P.length;k++)P[k].className=(!s&&k!==cur)?"off":"";' &&
    'for(k=0;k<T.length;k++){T[k].className=(!s&&k===cur)?"ti sel":"ti";' &&
    'T[k].setAttribute("aria-selected",(!s&&k===cur)?"true":"false");}}' &&
    'function sel(k){cur=k;try{if(qv()){$("q").value="";flt();}}catch(e){}apply();' &&
    'try{window.scrollTo(0,0);}catch(e){}}' &&
    'for(i=0;i<P.length;i++){var h=P[i].getElementsByTagName("h2")[0],a=document.createElement("a");' &&
    'a.textContent=h?((h.firstChild&&h.firstChild.nodeValue)||h.textContent).replace(/^\s+|\s+$/g,""):"";' &&
    'a.className="ti";a.setAttribute("role","tab");' &&
    'a.setAttribute("tabindex","0");' &&
    '(function(k,a){a.onclick=function(){sel(k);return false;};' &&
    'a.onkeydown=function(e){e=e||window.event;if(e.keyCode===13||e.keyCode===32){sel(k);return false;}};})(i,a);' &&
    'nav.appendChild(a);T.push(a);}' &&
    'var q=$("q");if(q&&q.addEventListener){q.addEventListener("input",apply);q.addEventListener("keyup",apply);}' &&
    'hd.insertBefore(nav,hd.firstChild);apply();})();' &&
    |</script></body></html>|.

  "Character table (not binary): the SAP GUI / ITS HTML control wires the
  "SAPEVENT links of a page loaded this way
  lv_size = strlen( lv_html ).
  DATA(lv_off) = 0.
  WHILE lv_off LT lv_size.
    DATA(lv_len) = nmin( val1 = 255 val2 = lv_size - lv_off ).
    APPEND lv_html+lv_off(lv_len) TO lt_data.
    lv_off = lv_off + lv_len.
  ENDWHILE.

  go_html->load_data( EXPORTING type         = 'text'
                                subtype      = 'html'
                                size         = lv_size
                      IMPORTING assigned_url = lv_url
                      CHANGING  data_table   = lt_data
                      EXCEPTIONS OTHERS      = 1 ).
  IF sy-subrc EQ 0.
    go_html->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
  ENDIF.

ENDFORM.
