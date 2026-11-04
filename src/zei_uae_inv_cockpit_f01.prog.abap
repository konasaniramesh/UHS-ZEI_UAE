*&---------------------------------------------------------------------*
*& Include          ZEI_UAE_INV_COCKPIT_F01
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Form init_texts
*&---------------------------------------------------------------------*
FORM init_texts.
  t_b01 = 'Selection'.
  %_s_bukrs_%_app_%-text  = 'Company Code'.
  %_s_vbeln_%_app_%-text  = 'Document'.
  %_s_erdat_%_app_%-text  = 'Created On'.
  %_p_btype_%_app_%-text  = 'Business Type'.
  %_p_type_%_app_%-text   = 'Type'.
  %_s_status_%_app_%-text = 'Status (P/W/S/E)'.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_output
*&---------------------------------------------------------------------*
FORM display_output.

  gt_fcat = VALUE #(
    ( fieldname = 'CHECK'          scrtext_l = 'Check'       checkbox = abap_true edit = abap_true )
    ( fieldname = 'COMPANYCODE'    scrtext_l = 'Co.Code' )
    ( fieldname = 'SAPDOCUMENT'    scrtext_l = 'Document'    convexit = 'ALPHA' hotspot = abap_true )
    ( fieldname = 'FISCALYEAR'     scrtext_l = 'Year' )
    ( fieldname = 'TYPENAME'       scrtext_l = 'Type' )
    ( fieldname = 'DOCUMENTTYPE'   scrtext_l = 'Doc.Type' )
    ( fieldname = 'EINVOICETYPE'   scrtext_l = 'E-Inv Type' )
    ( fieldname = 'STATUS'         scrtext_l = 'Status'      just = 'C' icon = abap_true )
    ( fieldname = 'STATTEXT'       scrtext_l = 'E-Invoice Status' )
    ( fieldname = 'EINVOICESTATUS' scrtext_l = 'E-Invoice Status (technical)' no_out = abap_true )
    ( fieldname = 'CORNERLOG'      scrtext_l = 'Peppol Corner' hotspot = abap_true just = 'C' icon = abap_true
                                   tooltip   = 'Click to display the processing log (C1 XML - C2 our ASP - C3 customer ASP - C4 customer - C5 FTA)' )
    ( fieldname = 'CORNER'         scrtext_l = 'Peppol Corner (text)' hotspot = abap_true no_out = abap_true )
    ( fieldname = 'REFERENCEID'    scrtext_l = 'ASP Reference' no_out = abap_true )
    ( fieldname = 'RESPONSE'       scrtext_l = 'Response'    hotspot = abap_true just = 'C' icon = abap_true )
    ( fieldname = 'REQUEST'        scrtext_l = 'XML'         hotspot = abap_true just = 'C' icon = abap_true )
    ( fieldname = 'HTML'           scrtext_l = 'HTML'        hotspot = abap_true just = 'C' icon = abap_true
                                   tooltip   = 'View as HTML' )
    ( fieldname = 'CUSTOMER'       scrtext_l = 'Customer'    convexit = 'ALPHA' )
    ( fieldname = 'CUSTOMERNAME'   scrtext_l = 'Customer Name' )
    ( fieldname = 'BUSINESSTYPE'   scrtext_l = 'Bus. Type' )
    ( fieldname = 'CURRENCY'       scrtext_l = 'Currency' )
    ( fieldname = 'NETVALUE'       scrtext_l = 'Net Value'   cfieldname = 'CURRENCY' )
    ( fieldname = 'TAXVALUE'       scrtext_l = 'VAT Amount'  cfieldname = 'CURRENCY' )
    ( fieldname = 'TOTALVALUE'     scrtext_l = 'Total Value' cfieldname = 'CURRENCY' ) ).

  LOOP AT gt_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat>).
    <ls_fcat>-coltext = <ls_fcat>-scrtext_l.
    <ls_fcat>-scrtext_m = <ls_fcat>-scrtext_l.
    <ls_fcat>-scrtext_s = <ls_fcat>-scrtext_l.
  ENDLOOP.

  gs_layo-cwidth_opt = abap_true.
  gs_layo-no_rowmark = abap_true.
  gs_layo-stylefname = 'STYL'.
  gs_layo-grid_title = 'Customer E-Invoice Cockpit'.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY_LVC'
    EXPORTING
      i_callback_program       = sy-repid
      i_callback_pf_status_set = 'SET_PFSTATUS'
      i_callback_user_command  = 'USER_COMMAND'
      is_layout_lvc            = gs_layo
      it_fieldcat_lvc          = gt_fcat
    TABLES
      t_outtab                 = gt_output
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form set_pfstatus
*&---------------------------------------------------------------------*
FORM set_pfstatus USING gt_extab TYPE slis_t_extab.
  DATA(lt_extab) = gt_extab.
  APPEND VALUE #( fcode = 'HTML' ) TO lt_extab.   "View as HTML button hidden
  SET PF-STATUS 'MYSTATUS' EXCLUDING lt_extab.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form user_command
*&---------------------------------------------------------------------*
FORM user_command USING im_ucomm  TYPE sy-ucomm
                        im_sfield TYPE slis_selfield.

  CASE im_ucomm.
    WHEN 'BACK' OR 'EXIT'.
      LEAVE TO SCREEN 0.
    WHEN 'CANCEL'.
      LEAVE PROGRAM.
  ENDCASE.

  CALL FUNCTION 'GET_GLOBALS_FROM_SLVC_FULLSCR'
    IMPORTING
      e_grid = go_alv.

  IF go_alv IS BOUND.
    go_alv->check_changed_data( ).
  ENDIF.

  CASE im_ucomm.
    WHEN 'SALL'.                      "Select all (open documents)
      lcl_app=>select_all( ).
    WHEN 'DALL'.                      "Deselect all
      LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>) WHERE check EQ abap_true.
        <ls_out>-check = abap_false.
      ENDLOOP.
    WHEN 'REFRESH'.                   "Re-read from database
      lcl_app=>get_data( ).
    WHEN 'SUBMIT'.                    "Submit / continue to completion
      lcl_app=>process( ).
    WHEN 'HTML'.                      "View as HTML (checked rows)
      PERFORM display_html_selected USING im_sfield.
    WHEN '&IC1'.
      CASE im_sfield-fieldname.
        WHEN 'SAPDOCUMENT'.
          PERFORM display_document USING im_sfield.
        WHEN 'CORNERLOG' OR 'CORNER' OR 'C1' OR 'C2' OR 'C3' OR 'C4' OR 'C5'.
          PERFORM display_messages USING im_sfield.
        WHEN 'RESPONSE'.
          PERFORM display_response USING im_sfield.
        WHEN 'REQUEST'.
          PERFORM display_request USING im_sfield.
        WHEN 'HTML'.
          PERFORM display_html USING im_sfield-tabindex.
      ENDCASE.
  ENDCASE.

  IF go_alv IS BOUND.
    go_alv->get_frontend_layout( IMPORTING es_layout = gs_layo ).
    go_alv->refresh_table_display( is_stable = VALUE #( row = abap_true col = abap_true ) ).
    gs_layo-cwidth_opt = abap_true.
    go_alv->set_frontend_layout( gs_layo ).
  ENDIF.

  im_sfield-row_stable = abap_true.
  im_sfield-col_stable = abap_true.
  im_sfield-refresh    = abap_true.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_messages  - step log / errors of the document
*&---------------------------------------------------------------------*
FORM display_messages USING im_sfield TYPE slis_selfield.

  "Processing log of one document - HTML in a popup
  TYPES: BEGIN OF ty_log,
           cls     TYPE string,
           result  TYPE string,
           step    TYPE string,
           logdate TYPE string,
           logtime TYPE string,
           message TYPE string,
           extra   TYPE string,
           full    TYPE string,
           sortkey TYPE string,
         END OF ty_log.
  DATA: lt_log   TYPE STANDARD TABLE OF ty_log WITH EMPTY KEY,
        lv_rows  TYPE string,
        lv_steps TYPE string,
        lv_level TYPE i,
        lv_fail  TYPE i,
        lv_title TYPE cl_abap_browser=>title.

  READ TABLE gt_output INTO DATA(ls_output) INDEX im_sfield-tabindex.
  CHECK sy-subrc EQ 0.

  "Rejected by Supplier's ASP: show each error once, in plain language,
  "from the stored ASP response instead of the technical log lines
  DATA(lt_ferr) = COND lcl_app=>tt_ferr(
                    WHEN ls_output-zzc2_status EQ gc_cs-rejected AND ls_output-responsepayload IS NOT INITIAL
                    THEN lcl_app=>asp_errors( ls_output-responsepayload ) ).
  DATA(ls_rej) = VALUE ty_log( ).

  LOOP AT gt_errors INTO DATA(ls_err) USING KEY doc WHERE bukrs EQ ls_output-companycode AND
                                           vbeln EQ ls_output-sapdocument AND
                                           gjahr EQ ls_output-fiscalyear  AND
                                           type  EQ ls_output-type.
    DATA(ls_log) = VALUE ty_log(
      cls    = SWITCH #( ls_err-msgty WHEN 'S' THEN 'ok' WHEN 'E' THEN 'ko' WHEN 'W' THEN 'wt' ELSE 'na' )
      result = SWITCH #( ls_err-msgty WHEN 'S' THEN 'Done' WHEN 'E' THEN 'Error' WHEN 'W' THEN 'Warning' ELSE 'Info' ) ).
    DATA(lv_msg) = CONV string( ls_err-message ).

    "Sort rank inside the same second = fixed processing order
    DATA(lv_rank) = `0`.
    FIND PCRE '^C([1-5]):' IN lv_msg SUBMATCHES DATA(lv_c).
    IF sy-subrc EQ 0.
      lv_rank = SWITCH #( lv_c WHEN '1' THEN `1` WHEN '2' THEN `2` WHEN '3' THEN `3`
                               WHEN '4' THEN `5` WHEN '5' THEN `6` ELSE `0` ).
      "Corner status: done -> accepted / delivered, error -> rejected or failed
      ls_log-step = COND #(
        WHEN ls_err-msgty EQ 'E' AND lv_msg CS 'already exists' AND lv_c EQ '2' THEN 'C2 - Document already exists in our ASP'
        WHEN ls_err-msgty EQ 'E' AND lv_msg CS 'Rejected by' AND lv_c EQ '2' THEN 'C2 - Rejected by our ASP'
        WHEN ls_err-msgty EQ 'E' AND lv_msg CS 'Rejected by' AND lv_c EQ '3' THEN |C3 - Rejected by customer's ASP|
        WHEN ls_err-msgty EQ 'E' THEN |C{ lv_c } - Failed|
        WHEN lv_c EQ '1' THEN 'C1 - XML generated'
        WHEN lv_c EQ '2' THEN 'C2 - Accepted by our ASP'
        WHEN lv_c EQ '3' THEN |C3 - Accepted by customer's ASP|
        WHEN lv_c EQ '4' THEN 'C4 - Delivered to customer'
        WHEN lv_c EQ '5' THEN 'C5 - Reported to FTA' ).
      lv_msg = substring_after( val = lv_msg sub = ':' ).
    ELSE.
      "Corner log texts: '<corner status text> = Successful / Failed ...'
      FIND PCRE '(?-x)^(.*?\(Corner [1-5]\)|Pending at Corner 2)' IN lv_msg SUBMATCHES DATA(lv_ctext).
      IF sy-subrc EQ 0 AND ls_err-msgty NE 'W'.
        lv_rank = COND #( WHEN lv_ctext CS 'Corner 1'              THEN `1`
                          WHEN lv_ctext CS 'Corner 2'              THEN `2`
                          WHEN lv_ctext CS 'Sent to Buyer'         THEN `3`
                          WHEN lv_ctext CS 'Accepted by Buyer' THEN `4`
                          WHEN lv_ctext CS 'Delivered to Buyer'    THEN `5`
                          WHEN lv_ctext CS 'Reported to FTA'       THEN `6`
                          WHEN lv_ctext CS 'Accepted by FTA'   THEN `7`
                          ELSE `0` ).
        ls_log-step = lcl_app=>disp_text( lv_ctext ).
        lv_msg = substring_after( val = lv_msg sub = lv_ctext ).
        REPLACE PCRE '^\s*[=-]\s*(Successful|Failed)?\s*' IN lv_msg WITH ``.
      ELSE.
        ls_log-step = 'Status check'.
      ENDIF.
    ENDIF.

    FIND PCRE '(\d{4})-(\d{2})-(\d{2})\s+(\d{2}:\d{2}:\d{2})' IN lv_msg
         MATCH OFFSET DATA(lv_off) MATCH LENGTH DATA(lv_len)
         SUBMATCHES DATA(lv_y) DATA(lv_m) DATA(lv_d) DATA(lv_t).
    IF sy-subrc EQ 0.
      ls_log-logdate = |{ lv_d }.{ lv_m }.{ lv_y }|.
      ls_log-logtime = lv_t.
      ls_log-sortkey = |{ lv_y }{ lv_m }{ lv_d }{ lv_t }{ lv_rank }{ ls_err-code }|.
      lv_msg = substring( val = lv_msg len = lv_off ) && substring( val = lv_msg off = lv_off + lv_len ).
    ELSE.
      ls_log-sortkey = |99999999{ ls_err-code }|.
    ENDIF.
    CONDENSE lv_msg.
    "ASP: instance identifier already submitted
    IF lv_msg CS 'already exists'.
      lv_msg = 'Document already exists in our ASP'.
    ENDIF.
    IF lt_ferr IS NOT INITIAL AND ls_err-msgty EQ 'E'.
      "Technical error detail lines (incl. split '(cont.)' lines) -> replaced by the list below
      IF find( val = lv_msg pcre = '^error \d+' ) >= 0.
        CONTINUE.
      ENDIF.
      "Rejection line: HTTP code only
      IF find( val = lv_msg pcre = '^HTTP\s+\d+' ) >= 0.
        lv_msg = |The e-invoice was rejected by the Supplier's ASP ({ replace( val = lv_msg pcre = '^(HTTP\s+\d+).*$' with = `$1` ) }).|.
        ls_rej = ls_log.
      ENDIF.
    ENDIF.
    ls_log-full    = ls_err-message.
    ls_log-message = lv_msg.
    APPEND ls_log TO lt_log.
  ENDLOOP.
  SORT lt_log BY sortkey.

  "One line per Peppol corner: entries without a corner are assigned by their text,
  "a later entry of the same corner replaces the earlier one
  DATA: lt_one  TYPE STANDARD TABLE OF ty_log WITH EMPTY KEY,
        lv_det  TYPE string,
        lv_todo TYPE string,
        lv_http TYPE string,
        lv_full TYPE string,
        lv_maxk TYPE string.
  DATA(lv_box) = `<div style="margin-top:5px;padding:5px 8px;background:#fff8e1;border-left:3px solid #e9730c;border-radius:3px">`.
  LOOP AT lt_log INTO ls_log.
    IF ls_log-step EQ 'Status check'.
      ls_log-step = COND #( WHEN ls_log-full CS 'could not be generated' THEN lcl_app=>disp_text( gc_txt-c1 )
                            WHEN ls_log-full CP 'POST outbound*'         THEN `Submission to Supplier's ASP`
                            ELSE ls_log-step ).
    ENDIF.
    READ TABLE lt_one ASSIGNING FIELD-SYMBOL(<ls_one>) WITH KEY step = ls_log-step.
    IF sy-subrc EQ 0.
      <ls_one> = ls_log.
    ELSE.
      APPEND ls_log TO lt_one.
    ENDIF.
    IF ls_log-step NE 'Status check' AND ls_log-sortkey GT lv_maxk.
      lv_maxk = ls_log-sortkey.
    ENDIF.
  ENDLOOP.
  "A status-check warning is only relevant while it is the latest event
  DELETE lt_one WHERE step EQ 'Status check' AND sortkey LT lv_maxk.

  LOOP AT lt_one INTO ls_log.
    lv_det = escape( val = ls_log-message format = cl_abap_format=>e_html_text ).
    CLEAR lv_todo.

    IF ls_log-cls EQ 'ko' AND lt_ferr IS NOT INITIAL AND ls_log-step EQ ls_rej-step.
      "Rejected by Supplier's ASP: every error with the exact action
      lv_det = |{ lv_det }<ol style="margin:6px 0 0 18px;padding:0">|.
      LOOP AT lt_ferr INTO DATA(ls_ferr).
        lv_det = |{ lv_det }<li style="margin-bottom:6px">{ escape( val = ls_ferr-text format = cl_abap_format=>e_html_text ) }| &&
                 COND string( WHEN ls_ferr-fix IS NOT INITIAL
                              THEN |{ lv_box }<b>What to do:</b> { escape( val = ls_ferr-fix format = cl_abap_format=>e_html_text ) }</div>| ) &&
                 |</li>|.
      ENDLOOP.
      lv_det = |{ lv_det }</ol>|.

    ELSEIF ls_log-cls EQ 'ko' OR ls_log-cls EQ 'wt'.
      lv_full = ls_log-full.
      CLEAR lv_http.
      FIND PCRE '(?:^|\s)HTTP\s+(\d{3})' IN lv_full SUBMATCHES lv_http.
      lv_todo = COND string(
        WHEN lv_full CS 'already exists'
          THEN `The document was already submitted to the ASP. Do not submit it again - check the existing submission in the ASP portal.`
        WHEN lv_full CS 'could not be generated'
          THEN `Maintain mapping INVOICE_TYPE_CODE_SD for this billing type (380 = invoice, 381 = credit note), then select the document and press Submit again.`
        WHEN lv_full CS 'token error'
          THEN `SAP could not log on to the ASP. Check the ASP user / client credentials and the token URL for this company code, then press Submit again.`
        WHEN lv_full CS 'no POST API'
          THEN `Maintain the POST entry for direction O (Outbound) in table ZEINVOICE_APIURL, then press Submit again.`
        WHEN lv_full CS 'No status (GET) API' OR lv_full CS 'No GET_ACK API'
          THEN `Maintain the missing GET / GET_ACK entry in table ZEINVOICE_APIURL, then press Submit again to refresh the status.`
        WHEN lv_full CS 'no response' OR lv_full CS 'timeout'
          THEN `The ASP did not answer in time. Nothing to change on the document - press Submit again later. If it continues, contact the ASP support.`
        WHEN lv_http EQ '401' OR lv_http EQ '403'
          THEN `SAP is not authorised at the ASP. Check the ASP credentials / token configuration for this company code, then press Submit again.`
        WHEN lv_http EQ '404'
          THEN `The ASP address is wrong. Check the URL maintained in table ZEINVOICE_APIURL, then press Submit again.`
        WHEN lv_http GE '500'
          THEN `The ASP service has a technical problem. Nothing to change on the document - press Submit again later. If it continues, contact the ASP support.`
        WHEN lv_full CS 'not final yet' OR lv_full CS 're-check later' OR lv_full CS 'retry later'
          THEN `The ASP is still processing the document. Press Submit again later to refresh the status.`
        WHEN lv_full CS 'Buyer'
          THEN `The buyer's ASP did not accept the document. Open Display Response for the reason and agree the correction with the customer (e.g. credit note and new invoice).`
        WHEN lv_full CS 'FTA'
          THEN `The FTA did not accept the tax data. Open Display Response for the reason; correct the document and contact the ASP support if needed.`
        WHEN ls_log-cls EQ 'ko'
          THEN `Open Display Response for the details, correct the data in SAP and press Submit again.`
        ELSE `Press Submit again later to refresh the status.` ).
      lv_det = |{ lv_det }{ lv_box }<b>What to do:</b> { escape( val = lv_todo format = cl_abap_format=>e_html_text ) }</div>|.
    ENDIF.

    lv_rows = lv_rows &&
      |<tr><td class="nw"><span class="dot { ls_log-cls }"></span>{ ls_log-result }</td>| &&
      |<td class="nw">{ escape( val = ls_log-step format = cl_abap_format=>e_html_text ) }</td>| &&
      |<td class="nw">{ ls_log-logdate }</td><td class="nw">{ ls_log-logtime }</td>| &&
      |<td>{ lv_det }</td></tr>|.
  ENDLOOP.
  IF lv_rows IS INITIAL.
    lv_rows = |<tr><td colspan="5" class="em">No processing log yet - the document has not been submitted.</td></tr>|.
  ENDIF.

  "Corner status strip - one box per stored corner status
  lv_steps = lcl_app=>corner_strip_html( ls_output ).

  DATA(lv_css) =
    '*{box-sizing:border-box}html,body{overflow-x:hidden}' &&
    'body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;line-height:1.4;color:#1d2d3e;background:#fff;margin:0;padding:12px}' &&
    'table{font-size:inherit;color:inherit;width:100%;border-collapse:collapse}' &&
    '.t{font-size:17px;font-weight:700;color:#0a6ed1}.s{color:#6a6d70;margin:2px 0 10px}' &&
    '.cs{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 12px}' &&
    '.c{flex:1 1 0;min-width:0;overflow-wrap:anywhere;border:1px solid #d9d9d9;border-radius:4px;padding:5px 6px;font-size:12px}' &&
    '.c b{display:block;font-size:13px}.c.ok{background:#e8f5e9;border-color:#2b7d2b}.c.ko{background:#fdecea;border-color:#bb0000}' &&
    '.c.wt{background:#fff8e1;border-color:#e9730c}.c.na{background:#fafafa;color:#8c8c8c}' &&
    'th{background:#0a6ed1;color:#fff;text-align:left;padding:6px;font-weight:600}' &&
    'td{padding:6px;border-bottom:1px solid #e5e5e5;vertical-align:top;overflow-wrap:anywhere;word-break:break-word}.nw{white-space:nowrap}.em{color:#6a6d70;text-align:center}' &&
    '.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}' &&
    '.dot.ok{background:#2b7d2b}.dot.ko{background:#bb0000}.dot.wt{background:#e9730c}.dot.na{background:#8c8c8c}'.

  DATA(lv_html) =
    |{ gc_html_head }{ gc_scroll_css }{ lv_css }</style></head><body><div id="scr">| &&
    |<div class="t">Processing log</div>| &&
    |<div class="s">{ ls_output-typename } document { ls_output-sapdocument ALPHA = OUT } / { ls_output-fiscalyear }| &&
    | - { escape( val = CONV string( ls_output-stattext ) format = cl_abap_format=>e_html_text ) }</div>| &&
    |<div class="cs">{ lv_steps }</div>| &&
    |<table><tr><th>Result</th><th>Peppol Corner</th><th>Date</th><th>Time</th><th>Details / What to do</th></tr>{ lv_rows }</table>| &&
    |</div></body></html>|.

  lv_title = |Processing log - Document { ls_output-sapdocument ALPHA = OUT }|.
  cl_abap_browser=>show_html( html_string = lv_html
                              title       = lv_title
                              size        = cl_abap_browser=>medium ).

ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_request - PINT AE XML
*&---------------------------------------------------------------------*
FORM display_request USING im_sfield TYPE slis_selfield.
  READ TABLE gt_output INTO DATA(ls_output) INDEX im_sfield-tabindex.
  CHECK sy-subrc EQ 0.
  DATA(lv_xml) = ls_output-requestpayload.
  IF lv_xml IS INITIAL.                   "not yet submitted -> preview
    lv_xml = lcl_app=>preview_payload( ls_output ).   "XML or JSON (switch)
  ENDIF.
  IF lv_xml IS NOT INITIAL.
    PERFORM show_xml_as_text USING lv_xml.
  ELSE.
    MESSAGE 'PINT AE XML could not be generated (check mappings)' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_response - last ASP response (JSON)
*&---------------------------------------------------------------------*
FORM display_response USING im_sfield TYPE slis_selfield.
  READ TABLE gt_output INTO DATA(ls_output) INDEX im_sfield-tabindex.
  CHECK sy-subrc EQ 0.
  "Full screen display (resizes with the SAP window, back with F3)
  cl_abap_browser=>show_html( html_string = lcl_app=>build_response_html( ls_output )
                              title       = |ASP Response - Document { ls_output-sapdocument ALPHA = OUT }|
                              dialog      = abap_false ).
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_document
*&---------------------------------------------------------------------*
FORM display_document USING im_sfield TYPE slis_selfield.
  READ TABLE gt_output INTO DATA(ls_output) INDEX im_sfield-tabindex.
  IF sy-subrc EQ 0.
    SET PARAMETER ID 'VF' FIELD ls_output-sapdocument.
    CALL TRANSACTION 'VF03' AND SKIP FIRST SCREEN.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_html - HTML preview of the e-invoice
*&---------------------------------------------------------------------*
FORM display_html USING iv_index TYPE i.
  READ TABLE gt_output INTO DATA(ls_output) INDEX iv_index.
  CHECK sy-subrc EQ 0.
  DATA(lv_html) = lcl_app=>build_html( ls_output ).
  IF lv_html IS INITIAL.
    MESSAGE 'PINT AE XML could not be generated (check mappings)' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  "Full screen display (resizes with the SAP window, back with F3)
  cl_abap_browser=>show_html( html_string = lv_html
                              title       = |Customer Invoice { ls_output-sapdocument ALPHA = OUT } - HTML preview|
                              dialog      = abap_false ).
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_html_selected - button "View as HTML"
*&---------------------------------------------------------------------*
FORM display_html_selected USING im_sfield TYPE slis_selfield.
  DATA: lv_found TYPE abap_bool,
        lv_index TYPE i.
  LOOP AT gt_output INTO DATA(ls_output) WHERE check EQ abap_true.
    lv_found = abap_true.
    lv_index = sy-tabix.
    PERFORM display_html USING lv_index.
  ENDLOOP.
  IF lv_found EQ abap_false.
    IF im_sfield-tabindex GT 0.
      lv_index = im_sfield-tabindex.
      PERFORM display_html USING lv_index.
    ELSE.
      MESSAGE 'Select a document (Check) to view it as HTML' TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form show_xml_as_text - PINT AE XML shown in an HTML page as XML text
*&---------------------------------------------------------------------*
FORM show_xml_as_text USING iv_xml TYPE string.

  "Pretty print (line breaks + indentation) - the XML is kept unchanged
  "if it cannot be parsed
  DATA(lv_xml) = iv_xml.
  DATA(lv_is_json) = xsdbool( find( val = iv_xml pcre = '^\s*[\{\[]' ) EQ 0 ).
  TRY.
      DATA(lo_reader) = cl_sxml_string_reader=>create( cl_abap_codepage=>convert_to( iv_xml ) ).
      DATA lo_writer TYPE REF TO if_sxml_writer.
      IF lv_is_json EQ abap_true.
        lo_writer = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).
      ELSE.
        lo_writer = cl_sxml_string_writer=>create( ).
      ENDIF.
      lo_writer->set_option( option = if_sxml_writer=>co_opt_linebreaks ).
      lo_writer->set_option( option = if_sxml_writer=>co_opt_indent ).
      lo_reader->next_node( ).
      lo_reader->skip_node( lo_writer ).
      lv_xml = cl_abap_codepage=>convert_from(
                 CAST cl_sxml_string_writer( lo_writer )->get_output( ) ).
      "Keep the XML declaration of the original
      FIND PCRE '^\s*(<\?xml[^>]*\?>)' IN iv_xml SUBMATCHES DATA(lv_decl).
      IF sy-subrc EQ 0 AND lv_xml NP '<?xml*'.
        lv_xml = lv_decl && cl_abap_char_utilities=>newline && lv_xml.
      ENDIF.
    CATCH cx_root.
      lv_xml = iv_xml.
  ENDTRY.

  "XML only: escaped text in a <pre> block, tags shown as they are
  DATA(lv_html) =
    `<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">` &&
    `<meta charset="utf-8"><style>body{margin:0;background:#fff}` &&
    `pre{margin:0;padding:8px;font:12px Consolas,monospace;white-space:pre}</style></head><body><pre>` &&
    escape( val = lv_xml format = cl_abap_format=>e_html_text ) &&
    `</pre></body></html>`.

  cl_abap_browser=>show_html( html_string = lv_html
                              title = COND #( WHEN lv_is_json EQ abap_true THEN 'E-invoice JSON' ELSE 'PINT AE XML' ) ).
ENDFORM.
