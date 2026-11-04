*&---------------------------------------------------------------------*
*& Include          ZEI_UAE_INV_COCKPIT_C01
*&---------------------------------------------------------------------*
*& LCL_XML : lightweight dynamic XML writer (replaces CALL TRANSFORMATION)
*& LCL_APP : data selection, PINT AE XML build, ASP integration and
*&           5-corner status tracking
*&---------------------------------------------------------------------*
CLASS lcl_xml DEFINITION FINAL.
  PUBLIC SECTION.
    DATA mv_xml TYPE string READ-ONLY.

    METHODS:
      open  IMPORTING iv_tag  TYPE csequence
                      iv_attr TYPE string OPTIONAL,
      close IMPORTING iv_tag TYPE csequence,
      elem  IMPORTING iv_tag   TYPE csequence
                      iv_val   TYPE any
                      iv_attr  TYPE string OPTIONAL
                      iv_force TYPE abap_bool DEFAULT abap_false,
      amt   IMPORTING iv_tag TYPE csequence
                      iv_val TYPE any
                      iv_cur TYPE any.

    CLASS-METHODS:
      attr IMPORTING iv_name     TYPE csequence
                     iv_val      TYPE any
           RETURNING VALUE(rv_s) TYPE string,
      num  IMPORTING iv_val      TYPE any
           RETURNING VALUE(rv_s) TYPE string,
      qty  IMPORTING iv_val      TYPE any
           RETURNING VALUE(rv_s) TYPE string,
      str  IMPORTING iv_val      TYPE any
           RETURNING VALUE(rv_s) TYPE string.
ENDCLASS.

CLASS lcl_xml IMPLEMENTATION.

  METHOD open.
    mv_xml = |{ mv_xml }<{ iv_tag }{ iv_attr }>|.
  ENDMETHOD.

  METHOD close.
    mv_xml = |{ mv_xml }</{ iv_tag }>|.
  ENDMETHOD.

  METHOD elem.
    DATA(lv_val) = str( iv_val ).
    IF lv_val IS INITIAL AND iv_force = abap_false.
      RETURN.
    ENDIF.
    mv_xml = |{ mv_xml }<{ iv_tag }{ iv_attr }>| &&
             escape( val = lv_val format = cl_abap_format=>e_xml_text ) &&
             |</{ iv_tag }>|.
  ENDMETHOD.

  METHOD amt.
    elem( iv_tag   = iv_tag
          iv_val   = num( iv_val )
          iv_attr  = attr( iv_name = 'currencyID' iv_val = iv_cur )
          iv_force = abap_true ).
  ENDMETHOD.

  METHOD attr.
    DATA(lv_val) = str( iv_val ).
    rv_s = | { iv_name }="| &&
           escape( val = lv_val format = cl_abap_format=>e_xml_attr ) &&
           |"|.
  ENDMETHOD.

  METHOD num.
    DATA lv_p TYPE p LENGTH 16 DECIMALS 2.
    TRY.
        lv_p = iv_val.
      CATCH cx_root.
        CLEAR lv_p.
    ENDTRY.
    rv_s = |{ lv_p DECIMALS = 2 }|.
  ENDMETHOD.

  METHOD qty.
    DATA lv_p TYPE p LENGTH 16 DECIMALS 3.
    TRY.
        lv_p = iv_val.
      CATCH cx_root.
        CLEAR lv_p.
    ENDTRY.
    rv_s = |{ lv_p NUMBER = RAW }|.
  ENDMETHOD.

  METHOD str.
    rv_s = |{ iv_val }|.
    SHIFT rv_s LEFT DELETING LEADING space.
    SHIFT rv_s RIGHT DELETING TRAILING space.
    SHIFT rv_s LEFT DELETING LEADING space.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      get_data,
      select_all,
      process,
      set_row_display CHANGING cs_out TYPE ty_output,
      corner_level IMPORTING iv_status TYPE clike
                   EXPORTING ev_level  TYPE i
                             ev_failed TYPE i,
      disp_text         IMPORTING iv        TYPE clike
                        RETURNING VALUE(rv) TYPE string,
      corner_strip_html IMPORTING is_out    TYPE ty_output
                        RETURNING VALUE(rv) TYPE string,
      build_xml IMPORTING is_out        TYPE ty_output
                RETURNING VALUE(rv_xml) TYPE string,
      preview_xml IMPORTING is_out        TYPE ty_output
                  RETURNING VALUE(rv_xml) TYPE string,
      build_html  IMPORTING is_out         TYPE ty_output
                  RETURNING VALUE(rv_html) TYPE string,
      build_response_html IMPORTING is_out         TYPE ty_output
                          RETURNING VALUE(rv_html) TYPE string.
    "Processing log: technical message -> plain-language sentence (HTML)
    CLASS-METHODS log_html IMPORTING iv_msg    TYPE string
                                     iv_full   TYPE string OPTIONAL
                           RETURNING VALUE(rv) TYPE string.
    "ASP error text / response JSON -> readable errors for end users
    TYPES: BEGIN OF ty_ferr,
             text TYPE string,
             fix  TYPE string,
           END OF ty_ferr,
           tt_ferr TYPE STANDARD TABLE OF ty_ferr WITH EMPTY KEY.
    CLASS-METHODS friendly_errors IMPORTING iv_text   TYPE string
                                  RETURNING VALUE(rt) TYPE tt_ferr.
    CLASS-METHODS asp_errors      IMPORTING iv_json   TYPE string
                                  RETURNING VALUE(rt) TYPE tt_ferr.
  "--- JSON (TaxLab) ------------------------------------------------
  CLASS-METHODS json_mode    RETURNING VALUE(rv) TYPE abap_bool.
  CLASS-METHODS build_json   IMPORTING is_out TYPE ty_output
                             RETURNING VALUE(rv_json) TYPE string.
  "XML or JSON preview, depending on the switch (display_request)
  CLASS-METHODS preview_payload IMPORTING is_out TYPE ty_output
                                RETURNING VALUE(rv) TYPE string.

  PRIVATE SECTION.
    "Performance: requests to the ASP sent in parallel packages
    TYPES tt_idx TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    CONSTANTS gc_par_max TYPE i VALUE 10.
  CLASS-DATA go_json TYPE REF TO zcl_ei_json_builder.
  CLASS-METHODS:
    is_json        IMPORTING is_out TYPE ty_output
                   RETURNING VALUE(rv) TYPE abap_bool,
    json_name_map  RETURNING VALUE(rt) TYPE zcl_ei_json_builder=>tt_name_map,
    json_builder   RETURNING VALUE(ro) TYPE REF TO zcl_ei_json_builder,
    json_parser    RETURNING VALUE(ro) TYPE REF TO zcl_ei_json_parser,
    json_party     IMPORTING iv_vat      TYPE any
                             iv_name     TYPE any
                             iv_street   TYPE any
                             iv_street2  TYPE any
                             iv_city     TYPE any
                             iv_postcode TYPE any
                             iv_region   TYPE any
                             iv_country  TYPE any
                             iv_legalid  TYPE any
                   RETURNING VALUE(rs) TYPE ty_j_party_wrap,
    json_address   IMPORTING iv_street   TYPE any
                             iv_street2  TYPE any
                             iv_city     TYPE any
                             iv_postcode TYPE any
                             iv_region   TYPE any
                             iv_country  TYPE any
                             iv_line     TYPE any OPTIONAL
                   RETURNING VALUE(rs) TYPE ty_j_address,
    json_taxcat    IMPORTING iv_taxcode TYPE any
                             iv_percent TYPE any
                   RETURNING VALUE(rs) TYPE ty_j_taxcat,
    add_line_ac    IMPORTING is_prcd TYPE zi_einvoice_conditions
                             iv_cur  TYPE string
                   CHANGING  cs_ac   TYPE ty_j_line_ac,
    post_result_json IMPORTING iv_code   TYPE i
                               iv_reason TYPE string
                               iv_body   TYPE string
                     CHANGING  cs_out    TYPE ty_output,
    poll_result_json IMPORTING iv_code   TYPE i
                               iv_reason TYPE string
                               iv_body   TYPE string
                               iv_token  TYPE string
                     CHANGING  cs_out    TYPE ty_output,
    tdd_status     IMPORTING iv_token TYPE string
                   EXPORTING ev_body  TYPE string
                   CHANGING  cs_out   TYPE ty_output,
    taxlab_errors  IMPORTING iv_json TYPE string
                   RETURNING VALUE(rt) TYPE tt_ferr,
    drop_token     IMPORTING iv_bukrs TYPE bukrs.
    CLASS-METHODS:
      load_process_data,
      submit_document CHANGING cs_out TYPE ty_output,
      post_outbound   IMPORTING iv_token TYPE string
                      CHANGING  cs_out   TYPE ty_output,
      poll_status     IMPORTING iv_after_post TYPE abap_bool DEFAULT abap_false
                      CHANGING  cs_out        TYPE ty_output,
      "--- performance: parallel POST / GET (per document logic unchanged) --
      prepare_document EXPORTING ev_ok  TYPE abap_bool
                       CHANGING  cs_out TYPE ty_output,
      post_result IMPORTING iv_code   TYPE i
                            iv_reason TYPE string
                            iv_body   TYPE string
                  CHANGING  cs_out    TYPE ty_output,
      post_parallel IMPORTING it_idx     TYPE tt_idx
                    EXPORTING ev_sent_at TYPE i,
      poll_prepare EXPORTING ev_go    TYPE abap_bool
                             ev_url   TYPE string
                             es_api   TYPE zeinvoice_apiurl
                             ev_token TYPE string
                   CHANGING  cs_out   TYPE ty_output,
      poll_result IMPORTING iv_code   TYPE i
                            iv_reason TYPE string
                            iv_body   TYPE string
                            iv_token  TYPE string
                  CHANGING  cs_out    TYPE ty_output,
      poll_parallel IMPORTING it_idx TYPE tt_idx,
      "--- 5-corner status model (new) ---------------------------------
      load_corner_status IMPORTING iv_only_checked TYPE abap_bool DEFAULT abap_false,
      migrate_legacy     CHANGING cs_out TYPE ty_output,
      derive_overall     CHANGING cs_out TYPE ty_output,
      legacy_pstatus     IMPORTING is_out           TYPE ty_output
                         RETURNING VALUE(rv_status) TYPE zde_ei_pstatus,
      set_corner         IMPORTING is_out    TYPE ty_output
                                   iv_new    TYPE clike
                                   iv_code   TYPE clike
                                   iv_text   TYPE clike
                                   iv_info   TYPE string OPTIONAL
                                   ir_errors TYPE REF TO data OPTIONAL
                         CHANGING  cv_field  TYPE clike,
      corner_responses_html IMPORTING is_out    TYPE ty_output
                            RETURNING VALUE(rv) TYPE string,
      fmt_iso            IMPORTING iv        TYPE clike
                         RETURNING VALUE(rv) TYPE string,
      combine_status     IMPORTING iv_a      TYPE clike
                                   iv_b      TYPE clike
                         RETURNING VALUE(rv) TYPE char1,
      corner_icon        IMPORTING iv_value   TYPE clike
                         EXPORTING ev_icon    TYPE icon_d
                         CHANGING  cv_waiting TYPE abap_bool,
      parse_status_array IMPORTING iv_json    TYPE string
                         EXPORTING et_entries TYPE tt_tx_entry
                                   ev_error   TYPE string,
      get_ack            IMPORTING is_out            TYPE ty_output
                                   iv_token          TYPE string
                                   iv_transaction_id TYPE string
                                   iv_corner_text    TYPE clike
                         EXPORTING ev_code           TYPE string
                                   ev_ok             TYPE abap_bool,
      parse_ack_code     IMPORTING iv_xml   TYPE string
                         EXPORTING ev_code  TYPE string
                                   ev_error TYPE string,
      log_error_details  IMPORTING is_out     TYPE ty_output
                                   iv_prefix  TYPE clike
                                   ir_details TYPE REF TO data,
      "--- unchanged helpers --------------------------------------------
      get_token IMPORTING iv_bukrs        TYPE bukrs
                EXPORTING ev_error        TYPE string
                RETURNING VALUE(rv_token) TYPE string,
      "--- performance: HTTP send / receive split (parallel requests) ---
      http_send    IMPORTING iv_url    TYPE string
                             iv_method TYPE string
                             is_api    TYPE zeinvoice_apiurl
                             iv_token  TYPE string OPTIONAL
                             iv_ctype  TYPE string OPTIONAL
                             iv_body   TYPE string OPTIONAL
                             it_form   TYPE tihttpnvp OPTIONAL
                             iv_ssl    TYPE abap_bool DEFAULT abap_true
                   EXPORTING eo_http   TYPE REF TO if_http_client
                             ev_reason TYPE string,
      http_receive IMPORTING io_http   TYPE REF TO if_http_client
                             iv_method TYPE string
                             iv_url    TYPE string
                   EXPORTING ev_code   TYPE i
                             ev_reason TYPE string
                             ev_body   TYPE string,
      ack_send     IMPORTING iv_token          TYPE string
                             iv_transaction_id TYPE string
                   EXPORTING eo_http           TYPE REF TO if_http_client
                             ev_reason         TYPE string
                             ev_url            TYPE string,
      ack_receive  IMPORTING is_out            TYPE ty_output
                             io_http           TYPE REF TO if_http_client
                             iv_reason         TYPE string
                             iv_url            TYPE string
                             iv_transaction_id TYPE string
                             iv_corner_text    TYPE clike
                   EXPORTING ev_code           TYPE string
                             ev_ok             TYPE abap_bool,
      http_call IMPORTING iv_url    TYPE string
                          iv_method TYPE string
                          is_api    TYPE zeinvoice_apiurl
                          iv_token  TYPE string OPTIONAL
                          iv_ctype  TYPE string OPTIONAL
                          iv_body   TYPE string OPTIONAL
                          it_form   TYPE tihttpnvp OPTIONAL
                          iv_ssl    TYPE abap_bool DEFAULT abap_true
                EXPORTING ev_code   TYPE i
                          ev_reason TYPE string
                          ev_body   TYPE string,
      add_log IMPORTING is_out   TYPE ty_output
                        iv_msgty TYPE clike
                        iv_code  TYPE clike
                        iv_text  TYPE string,
      save_document IMPORTING is_out TYPE ty_output,
      corner_status IMPORTING iv_level         TYPE i
                    RETURNING VALUE(rv_status) TYPE zde_ei_pstatus,
      corner_text   IMPORTING iv_level       TYPE i
                    RETURNING VALUE(rv_text) TYPE string,
      map IMPORTING iv_map        TYPE clike
                    iv_int        TYPE any
                    iv_ext2       TYPE abap_bool DEFAULT abap_false
          RETURNING VALUE(rv_ext) TYPE string,
      is_mapped IMPORTING iv_map         TYPE clike
                          iv_int         TYPE any
                RETURNING VALUE(rv_bool) TYPE abap_bool,
      fmt_date IMPORTING iv_date     TYPE d
               RETURNING VALUE(rv_s) TYPE string,
      fmt_time IMPORTING iv_time     TYPE t
               RETURNING VALUE(rv_s) TYPE string,
      write_party IMPORTING io_xml      TYPE REF TO lcl_xml
                            iv_vat      TYPE any
                            iv_name     TYPE any
                            iv_street   TYPE any
                            iv_street2  TYPE any
                            iv_city     TYPE any
                            iv_postcode TYPE any
                            iv_region   TYPE any
                            iv_country  TYPE any
                            iv_legalid  TYPE any
                            iv_peppol   TYPE any OPTIONAL,
      write_address IMPORTING io_xml      TYPE REF TO lcl_xml
                              iv_tag      TYPE csequence
                              iv_street   TYPE any
                              iv_street2  TYPE any
                              iv_city     TYPE any
                              iv_postcode TYPE any
                              iv_region   TYPE any
                              iv_country  TYPE any
                              iv_line     TYPE any OPTIONAL,
      write_taxcat IMPORTING io_xml     TYPE REF TO lcl_xml
                             iv_tag     TYPE csequence
                             iv_taxcode TYPE any
                             iv_percent TYPE any,
      x_name IMPORTING iv_name   TYPE csequence
             RETURNING VALUE(rv) TYPE string,
      x_child IMPORTING io_node   TYPE REF TO if_ixml_node
                        iv_name   TYPE csequence
              RETURNING VALUE(ro) TYPE REF TO if_ixml_node,
      x_list IMPORTING io_node   TYPE REF TO if_ixml_node
                       iv_name   TYPE csequence
             RETURNING VALUE(rt) TYPE tt_nodes,
      x_path IMPORTING io_node   TYPE REF TO if_ixml_node
                       iv_path   TYPE csequence
             RETURNING VALUE(ro) TYPE REF TO if_ixml_node,
      x_val IMPORTING io_node   TYPE REF TO if_ixml_node
                      iv_path   TYPE csequence
            RETURNING VALUE(rv) TYPE string,
      x_attr IMPORTING io_node   TYPE REF TO if_ixml_node
                       iv_path   TYPE csequence
                       iv_attr   TYPE csequence
             RETURNING VALUE(rv) TYPE string,
      h IMPORTING iv        TYPE any
        RETURNING VALUE(rv) TYPE string,
      html_party IMPORTING io_party  TYPE REF TO if_ixml_node
                           iv_title  TYPE csequence
                           iv_pid    TYPE string OPTIONAL
                 RETURNING VALUE(rv) TYPE string,
      resp_label IMPORTING iv_key    TYPE string
                 RETURNING VALUE(rv) TYPE string,
      resp_value IMPORTING iv_key    TYPE string
                           iv_val    TYPE string
                 RETURNING VALUE(rv) TYPE string,
      rule_errors_html IMPORTING it_msg    TYPE string_table
                                 iv_cn     TYPE abap_bool
                       RETURNING VALUE(rv) TYPE string,
      rule_hint IMPORTING iv_id     TYPE string
                RETURNING VALUE(rv) TYPE string,
      xsd_label IMPORTING iv_el     TYPE string
                RETURNING VALUE(rv) TYPE string,
      xsd_hint  IMPORTING iv_code     TYPE string
                          iv_expected TYPE string
                RETURNING VALUE(rv)   TYPE string,
      xsd_text  IMPORTING iv_code   TYPE string
                          iv_text   TYPE string
                RETURNING VALUE(rv) TYPE string,
      log_asp_errors IMPORTING is_out    TYPE ty_output
                               iv_prefix TYPE clike
                               it_err    TYPE tt_ferr,
      rule_title IMPORTING iv_id     TYPE string
                 RETURNING VALUE(rv) TYPE string,
      pint_term IMPORTING iv_term   TYPE string
                RETURNING VALUE(rv) TYPE string,
      fit_script RETURNING VALUE(rv) TYPE string,
      sap_uom IMPORTING iv_code   TYPE string
              RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

*----------------------------------------------------------------------*
* Data selection (same sources as ZEI_PROCESS_COCKPIT)
*----------------------------------------------------------------------*
  METHOD get_data.

    REFRESH: s_btype, s_type.
    CLEAR: s_btype, s_type.
    IF p_btype IS NOT INITIAL.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = p_btype ) TO s_btype.
    ENDIF.
    IF p_type IS NOT INITIAL.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = p_type ) TO s_type.
    ENDIF.

    CLEAR: gt_output, gt_errors.

    SELECT *
           FROM zi_einvoice_header
           WHERE companycode     IN @s_bukrs   AND
                 sapdocument     IN @s_vbeln   AND
                 creationdate    IN @s_erdat   AND
                 einvoiceenabled EQ @abap_true AND
                 businesstype    IN @s_btype   AND
                 type            IN @s_type    AND
                 messagetype     IN @s_status
           ORDER BY companycode ASCENDING, sapdocument ASCENDING, fiscalyear ASCENDING
           INTO CORRESPONDING FIELDS OF TABLE @gt_output.

    IF gt_output IS NOT INITIAL.

      SELECT *
             FROM zeinvoice_error
             FOR ALL ENTRIES IN @gt_output
             WHERE bukrs EQ @gt_output-companycode AND
                   vbeln EQ @gt_output-sapdocument AND
                   gjahr EQ @gt_output-fiscalyear
             INTO TABLE @gt_errors.

    ENDIF.

*    SELECT *
*      FROM /aif/t_mvmapval5
*      WHERE ns EQ @gc_map_ns
*      ORDER BY vmapname ASCENDING, vmapvalnr ASCENDING
*      INTO TABLE @gt_mapping.

    SELECT *
           FROM zeinvoice_apiurl
           WHERE direction EQ 'O'
           INTO TABLE @gt_apiurl.

    "Separate corner statuses (C1 .. C5 Ack + Overall)
    load_corner_status( ).

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      set_row_display( CHANGING cs_out = <ls_out> ).
    ENDLOOP.

  ENDMETHOD.

  METHOD preview_xml.
    "Build the PINT AE XML for one document without sending it
    DATA(lt_backup) = gt_output.
    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      <ls_out>-check = xsdbool( <ls_out>-companycode EQ is_out-companycode AND
                                <ls_out>-sapdocument EQ is_out-sapdocument AND
                                <ls_out>-fiscalyear  EQ is_out-fiscalyear ).
    ENDLOOP.
    load_process_data( ).
    READ TABLE gt_output INTO DATA(ls_cur)
         WITH KEY companycode = is_out-companycode
                  sapdocument = is_out-sapdocument
                  fiscalyear  = is_out-fiscalyear.
    IF sy-subrc EQ 0.
      rv_xml = build_xml( ls_cur ).
    ENDIF.
    gt_output = lt_backup.
  ENDMETHOD.

  METHOD select_all.
    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>) WHERE messagetype NE 'S'.
      <ls_out>-check = abap_true.
    ENDLOOP.
  ENDMETHOD.

  METHOD load_process_data.

    DATA(lt_sel) = gt_output.
    DELETE lt_sel WHERE check EQ abap_false.
    CHECK lt_sel IS NOT INITIAL.

    "Fresh header data for the selected documents - join on the document keys
    "(instead of FOR ALL ENTRIES: no DISTINCT over the LOB payload columns)
    TYPES: BEGIN OF lty_key,
             companycode TYPE ty_output-companycode,
             sapdocument TYPE ty_output-sapdocument,
             fiscalyear  TYPE ty_output-fiscalyear,
           END OF lty_key.
    DATA lt_key TYPE STANDARD TABLE OF lty_key WITH EMPTY KEY.
    lt_key = CORRESPONDING #( lt_sel ).
    SORT lt_key BY companycode sapdocument fiscalyear.
    DELETE ADJACENT DUPLICATES FROM lt_key COMPARING companycode sapdocument fiscalyear.
    SELECT h~*
      FROM zi_einvoice_header AS h
      INNER JOIN @lt_key AS k
         ON  h~companycode EQ k~companycode
         AND h~sapdocument EQ k~sapdocument
         AND h~fiscalyear  EQ k~fiscalyear
      INTO TABLE @DATA(lt_header).

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>)
                                WHERE check EQ abap_true.
      READ TABLE lt_header INTO DATA(ls_header)
                           WITH KEY companycode = <ls_out>-companycode
                                    sapdocument = <ls_out>-sapdocument
                                    fiscalyear  = <ls_out>-fiscalyear.
      IF sy-subrc EQ 0.
        MOVE-CORRESPONDING ls_header TO <ls_out>.
      ENDIF.
    ENDLOOP.

    "Fresh corner statuses for the selected documents
    load_corner_status( iv_only_checked = abap_true ).

    SELECT *
           FROM zi_einvoice_items
           FOR ALL ENTRIES IN @lt_sel
           WHERE companycode EQ @lt_sel-companycode AND
                 sapdocument EQ @lt_sel-sapdocument AND
                 fiscalyear  EQ @lt_sel-fiscalyear
           INTO TABLE @gt_items.
    "gt_items is a sorted table (sapdocument sapdocitem) - no SORT needed

    SELECT *
           FROM zi_einvoice_conditions
           FOR ALL ENTRIES IN @lt_sel
           WHERE conditionno EQ @lt_sel-conditionno
           INTO TABLE @gt_prcd.
    "gt_prcd is a sorted table (conditionno item conditiontype) - no SORT needed

  ENDMETHOD.

*----------------------------------------------------------------------*
* Process selected documents - run every step until completion
*----------------------------------------------------------------------*
  METHOD process.

    "Performance: Step 1/2 (generate + POST) for all selected documents
    "first, then ONE wait for the ASP, then Step 3 (status GET) for all.
    "Before, every document waited 2 seconds after its own POST.
    "Per document the logic and the results are unchanged.

    DATA: lv_wait TYPE abap_bool.

    DATA: lt_sub     TYPE tt_idx,  "documents to submit (generated + POST in parallel)

          lt_poll    TYPE tt_idx,  "documents to poll (status GET in parallel)

          lv_sent_at TYPE i,

          lv_now     TYPE i,

          lv_rest    TYPE p LENGTH 8 DECIMALS 3.

    "Document lock (lock object EZEINV_DOC): the cockpit and the background
    "job must never generate / POST / poll the same document at the same
    "time (risk of a duplicate submission to the ASP). Every selected
    "document is locked BEFORE its status is re-read from the database;
    "a document already locked by another user / job is skipped.
    "_scope '1': the lock survives the COMMIT WORKs inside the processing
    "and is released explicitly at the end (or when the program ends).
    TYPES: BEGIN OF lty_lock,
             bukrs TYPE zeinvoice_detail-bukrs,
             vbeln TYPE zeinvoice_detail-vbeln,
             gjahr TYPE zeinvoice_detail-gjahr,
           END OF lty_lock.
    DATA: lt_locked    TYPE STANDARD TABLE OF lty_lock WITH EMPTY KEY,
          lv_skipped   TYPE i,
          lv_skip_docs TYPE string,
          lv_lock_user TYPE string.

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_lock>) WHERE check EQ abap_true.
      CALL FUNCTION 'ENQUEUE_EZEINV_DOC'
        EXPORTING
          mode_zeinvoice_detail = 'E'
          mandt                 = sy-mandt
          bukrs                 = <ls_lock>-companycode
          vbeln                 = <ls_lock>-sapdocument
          gjahr                 = <ls_lock>-fiscalyear
          _scope                = '1'
        EXCEPTIONS
          foreign_lock          = 1
          system_failure        = 2
          OTHERS                = 3.
      IF sy-subrc EQ 0.
        APPEND VALUE #( bukrs = <ls_lock>-companycode
                        vbeln = <ls_lock>-sapdocument
                        gjahr = <ls_lock>-fiscalyear ) TO lt_locked.
      ELSE.
        lv_lock_user = COND #( WHEN sy-subrc EQ 1 THEN sy-msgv1 ELSE `lock server error` ).
        <ls_lock>-check = abap_false.          "skip - processed elsewhere
        lv_skipped   = lv_skipped + 1.
        lv_skip_docs = |{ lv_skip_docs } { <ls_lock>-sapdocument ALPHA = OUT }|.
      ENDIF.
    ENDLOOP.

    IF lv_skipped GT 0.
      MESSAGE |{ lv_skipped } document(s) skipped - currently processed by { lv_lock_user }:{ lv_skip_docs }|
              TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.

    load_process_data( ).

    "Phase 1 - generate / submit
    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>) WHERE check EQ abap_true.

      DATA(lv_tabix) = sy-tabix.

      IF sy-batch              EQ abap_true AND
         <ls_out>-messagetype  EQ 'P'       AND "Not yet processed
         <ls_out>-autoeinvoice EQ abap_false.
        CONTINUE.
      ENDIF.

      CASE <ls_out>-zzoverall_status.

        WHEN gc_ov-success.
          CONTINUE.                     "final - nothing to do

        WHEN gc_ov-failed.
          IF <ls_out>-zzc2_status NE gc_cs-rejected.
            "Failed after acceptance at C2 - final, never POST again.
            "Corners set to Failed are re-opened so that phase 2 re-reads their
            "real status from the ASP (e.g. C5 was still PROCESSING at the FTA).
            "A real ASP error sets them to Failed again.
            IF <ls_out>-zzc2_status EQ gc_cs-accepted.
              IF <ls_out>-zzc3_sent_status EQ gc_cs-failed. CLEAR <ls_out>-zzc3_sent_status. ENDIF.
              IF <ls_out>-zzc3_ack_status  EQ gc_cs-failed. CLEAR <ls_out>-zzc3_ack_status.  ENDIF.
              IF <ls_out>-zzc4_status      EQ gc_cs-failed. CLEAR <ls_out>-zzc4_status.      ENDIF.
              IF <ls_out>-zzc5_rep_status  EQ gc_cs-failed. CLEAR <ls_out>-zzc5_rep_status.  ENDIF.
              IF <ls_out>-zzc5_ack_status  EQ gc_cs-failed. CLEAR <ls_out>-zzc5_ack_status.  ENDIF.
              derive_overall( CHANGING cs_out = <ls_out> ).
            ENDIF.
            CONTINUE.
          ENDIF.
          "Rejected by Supplier's ASP (VALIDATION_ERROR): the corrected
          "document may be submitted again by an explicit user action
          APPEND lv_tabix TO lt_sub.   "submitted below - all together (POST_PARALLEL)

        WHEN OTHERS.                    "not yet submitted / IN PROGRESS
          IF <ls_out>-zzc2_status NE gc_cs-accepted.
            APPEND lv_tabix TO lt_sub.   "submitted below - all together (POST_PARALLEL)
          ENDIF.

      ENDCASE.

    ENDLOOP.

    "Step 1 / 2 for all collected documents: generation, ONE commit, then the
    "POST requests in parallel (results per document as before)
    post_parallel( EXPORTING it_idx = lt_sub IMPORTING ev_sent_at = lv_sent_at ).
    LOOP AT lt_sub INTO DATA(lv_sub_idx).
      ASSIGN gt_output[ lv_sub_idx ] TO <ls_out>.
      IF <ls_out>-zzc2_status EQ gc_cs-accepted.
        lv_wait = abap_true.
      ELSEIF <ls_out>-zzc1_status IS NOT INITIAL.
        "Rejected by Supplier's ASP (VALIDATION_ERROR) or not sent:
        "phase 2 handles C2 = Accepted only -> save the ASP response
        "payload and the step log (ZEINVOICE_ERROR) now. COMMIT below.
        set_row_display( CHANGING cs_out = <ls_out> ).
        save_document( <ls_out> ).
      ENDIF.
    ENDLOOP.

    "Give the ASP a moment after sending - once for all documents. Only
    "the part of the 2 seconds not already passed since the last POST
    IF lv_wait EQ abap_true.
      GET RUN TIME FIELD lv_now.
      lv_rest = 2 - ( lv_now - lv_sent_at ) / 1000000.
      IF lv_rest GT 2 OR lv_now LT lv_sent_at.
        lv_rest = 2.
      ENDIF.
      IF lv_rest GT 0.
        WAIT UP TO lv_rest SECONDS.
      ENDIF.
    ENDIF.

    "Phase 2 - status GET (in parallel), save, display
    LOOP AT gt_output TRANSPORTING NO FIELDS
         WHERE check       EQ abap_true AND
               zzc2_status EQ 'A'.
      APPEND sy-tabix TO lt_poll.
    ENDLOOP.
    poll_parallel( lt_poll ).
    LOOP AT lt_poll INTO DATA(lv_poll_idx).
      ASSIGN gt_output[ lv_poll_idx ] TO <ls_out>.
      save_document( <ls_out> ).
      set_row_display( CHANGING cs_out = <ls_out> ).
    ENDLOOP.

    COMMIT WORK AND WAIT.

    "Release the document locks set at the beginning
    LOOP AT lt_locked INTO DATA(ls_locked).
      CALL FUNCTION 'DEQUEUE_EZEINV_DOC'
        EXPORTING
          mode_zeinvoice_detail = 'E'
          mandt                 = sy-mandt
          bukrs                 = ls_locked-bukrs
          vbeln                 = ls_locked-vbeln
          gjahr                 = ls_locked-gjahr
          _scope                = '1'.
    ENDLOOP.

  ENDMETHOD.

  METHOD prepare_document.

    "Step 1 of the submission (generation, C1) - split from SUBMIT_DOCUMENT
    "so that several documents can be generated before they are sent.
    "Logic unchanged; EV_OK = abap_true when the XML was generated and saved
    CLEAR ev_ok.

    "New submission -> reset the step log and ALL corner statuses
    DELETE gt_errors WHERE bukrs EQ cs_out-companycode AND
                           vbeln EQ cs_out-sapdocument AND
                           gjahr EQ cs_out-fiscalyear  AND
                           type  EQ cs_out-type.
    CLEAR: cs_out-referenceid, cs_out-responsepayload, cs_out-requestpayload,
           cs_out-zzc1_status, cs_out-zzc2_status,
           cs_out-zzc3_sent_status, cs_out-zzc3_ack_status,
           cs_out-zzc4_status,
           cs_out-zzc5_rep_status, cs_out-zzc5_ack_status,
           cs_out-zzoverall_status.
    "Payload format from the switch ZEINVOICE_APIURL (O / POST)-DFORMAT
  cs_out-requestformat = COND #( WHEN json_mode( ) EQ abap_true THEN gc_format_json ELSE gc_format ).
  cs_out-einvoicestatus = gc_st-pending.

  "Step 1 - Generation (C1)
  DATA(lv_xml) = COND string( WHEN cs_out-requestformat EQ gc_format_json
                              THEN build_json( cs_out )
                              ELSE build_xml( cs_out ) ).
  IF lv_xml IS INITIAL.
    "Not a corner status of the spec: log it; no corner is set, so the
    "document can simply be submitted again after correcting the data
    "(text 'could not be generated' is evaluated by DISPLAY_MESSAGES)
    add_log( is_out = cs_out iv_msgty = 'E' iv_code = 'E'
             iv_text = |{ COND string( WHEN cs_out-requestformat EQ gc_format_json THEN `E-invoice JSON`
                                       ELSE `PINT AE XML` ) } could not be generated | &&
                       |(check mapping INVOICE_TYPE_CODE_SD for { cs_out-documenttype })| ).
      cs_out-messagetype = 'E'.
      cs_out-status      = icon_led_red.
      RETURN.
    ENDIF.
    cs_out-requestpayload = lv_xml.
    set_corner( EXPORTING is_out  = cs_out
                          iv_new  = gc_cs-generated
                          iv_code = 'C1'
                          iv_text = gc_txt-c1
                          iv_info = |{ strlen( lv_xml ) } characters|
                CHANGING  cv_field = cs_out-zzc1_status ).
    derive_overall( CHANGING cs_out = cs_out ).

    "Keep the generated XML even if the transmission fails
    save_document( cs_out ).
    ev_ok = abap_true.

  ENDMETHOD.

  METHOD submit_document.

    DATA lv_error TYPE string.

    "Step 1 - Generation (C1) - see PREPARE_DOCUMENT
    prepare_document( IMPORTING ev_ok = DATA(lv_ok) CHANGING cs_out = cs_out ).
    CHECK lv_ok EQ abap_true.
    COMMIT WORK AND WAIT.

    "Step 2 - POST outbound (C2)
    DATA(lv_token) = get_token( EXPORTING iv_bukrs = cs_out-companycode
                                IMPORTING ev_error = lv_error ).
    IF lv_token IS INITIAL.
      "Technical error: keep previous status, allow retry
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |POST outbound not sent - token error: { lv_error } - status unchanged, retry possible| ).
      RETURN.
    ENDIF.

    post_outbound( EXPORTING iv_token = lv_token
                   CHANGING  cs_out   = cs_out ).

  ENDMETHOD.

  METHOD post_parallel.

    "Performance: Step 1 (generation) for all documents, ONE commit, then
    "Step 2 (POST outbound) sent in parallel packages of GC_PAR_MAX requests
    "and the answers read afterwards - the ASP works on them at the same
    "time instead of one after the other. Per document the checks, the
    "statuses and the log texts are exactly those of SUBMIT_DOCUMENT.
    "If the ASP does not answer at all (connection error / timeout), the
    "documents of the following packages are not sent in this run (same
    "result as before: status unchanged, retry possible) instead of each
    "one waiting for the timeout.
    TYPES: BEGIN OF lty_req,
             idx    TYPE i,
             token  TYPE string,
             http   TYPE REF TO if_http_client,
             reason TYPE string,
           END OF lty_req.
    DATA: lt_req    TYPE STANDARD TABLE OF lty_req WITH EMPTY KEY,
          lv_error  TYPE string,
          lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string,
          lv_down   TYPE string.

    CLEAR ev_sent_at.
    CHECK it_idx IS NOT INITIAL.

    "Step 1 - Generation (C1) for all documents
    LOOP AT it_idx INTO DATA(lv_idx).
      ASSIGN gt_output[ lv_idx ] TO FIELD-SYMBOL(<ls_out>).
      CHECK sy-subrc EQ 0.
      prepare_document( IMPORTING ev_ok = DATA(lv_ok) CHANGING cs_out = <ls_out> ).
      IF lv_ok EQ abap_true.
        APPEND VALUE #( idx = lv_idx ) TO lt_req.
      ENDIF.
    ENDLOOP.
    "Keep the generated XML even if the transmission fails
    COMMIT WORK AND WAIT.
    CHECK lt_req IS NOT INITIAL.

    "Step 2 - POST outbound (C2): token per company code (buffered)
    LOOP AT lt_req ASSIGNING FIELD-SYMBOL(<ls_req>).
      ASSIGN gt_output[ <ls_req>-idx ] TO <ls_out>.
      <ls_req>-token = get_token( EXPORTING iv_bukrs = <ls_out>-companycode
                                  IMPORTING ev_error = lv_error ).
      IF <ls_req>-token IS INITIAL.
        "Technical error: keep previous status, allow retry
        add_log( is_out = <ls_out> iv_msgty = 'W' iv_code = 'W'
                 iv_text = |POST outbound not sent - token error: { lv_error } - status unchanged, retry possible| ).
      ENDIF.
    ENDLOOP.
    DELETE lt_req WHERE token IS INITIAL.
    CHECK lt_req IS NOT INITIAL.

    READ TABLE gt_apiurl INTO DATA(ls_api)
         WITH KEY direction = 'O' method = 'POST'.
    IF sy-subrc NE 0 OR ls_api-apiurl IS INITIAL.
      LOOP AT lt_req ASSIGNING <ls_req>.
        ASSIGN gt_output[ <ls_req>-idx ] TO <ls_out>.
        add_log( is_out = <ls_out> iv_msgty = 'W' iv_code = 'W'
                 iv_text = |POST outbound not sent - no POST API maintained in ZEINVOICE_APIURL for direction O (Outbound) - status unchanged| ).
      ENDLOOP.
      RETURN.
    ENDIF.
    DATA(lv_url) = CONV string( ls_api-apiurl ).

    DATA(lv_from) = 1.
    WHILE lv_from LE lines( lt_req ).
      DATA(lv_to) = nmin( val1 = lv_from + gc_par_max - 1 val2 = lines( lt_req ) ).

      "Send the package ...
      LOOP AT lt_req ASSIGNING <ls_req> FROM lv_from TO lv_to.
        IF lv_down IS NOT INITIAL.
          <ls_req>-reason = lv_down.
          CONTINUE.
        ENDIF.
        ASSIGN gt_output[ <ls_req>-idx ] TO <ls_out>.
        http_send( EXPORTING iv_url    = lv_url
                             iv_method = 'POST'
                             is_api    = ls_api
                             iv_token  = <ls_req>-token
                             iv_ctype  = COND #( WHEN <ls_out>-requestformat EQ gc_format_json THEN `application/json` ELSE `application/xml` )
                             iv_body   = <ls_out>-requestpayload
                   IMPORTING eo_http   = <ls_req>-http
                             ev_reason = <ls_req>-reason ).
        GET RUN TIME FIELD ev_sent_at.
      ENDLOOP.

      "... then read and evaluate the answers (same evaluation as before)
      LOOP AT lt_req ASSIGNING <ls_req> FROM lv_from TO lv_to.
        ASSIGN gt_output[ <ls_req>-idx ] TO <ls_out>.
        CLEAR: lv_code, lv_body.
        lv_reason = <ls_req>-reason.
        IF <ls_req>-http IS BOUND.
          http_receive( EXPORTING io_http   = <ls_req>-http
                                  iv_method = 'POST'
                                  iv_url    = lv_url
                        IMPORTING ev_code   = lv_code
                                  ev_reason = lv_reason
                                  ev_body   = lv_body ).
          CLEAR <ls_req>-http.
        ENDIF.
        IF lv_code EQ 0 AND lv_down IS INITIAL.
          lv_down = |ASP not reachable in this run ({ lv_reason }) - not sent|.
        ENDIF.
        post_result( EXPORTING iv_code   = lv_code
                               iv_reason = lv_reason
                               iv_body   = lv_body
                     CHANGING  cs_out    = <ls_out> ).
      ENDLOOP.

      lv_from = lv_to + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD poll_parallel.

    "Performance: Step 3 (status GET) for all documents - the requests are
    "sent in parallel packages of GC_PAR_MAX and the answers evaluated
    "afterwards with POLL_RESULT (same checks / statuses / log texts as
    "POLL_STATUS). If the ASP does not answer at all, the documents of the
    "following packages are not polled in this run (statuses unchanged,
    "retry later - as before) instead of each one waiting for the timeout.
    TYPES: BEGIN OF lty_req,
             idx    TYPE i,
             go     TYPE abap_bool,
             url    TYPE string,
             api    TYPE zeinvoice_apiurl,
             token  TYPE string,
             http   TYPE REF TO if_http_client,
             reason TYPE string,
           END OF lty_req.
    DATA: lt_req    TYPE STANDARD TABLE OF lty_req WITH EMPTY KEY,
          lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string,
          lv_down   TYPE string.

    CHECK it_idx IS NOT INITIAL.

    "Checks and status URL per document (unchanged logic)
    LOOP AT it_idx INTO DATA(lv_idx).
      ASSIGN gt_output[ lv_idx ] TO FIELD-SYMBOL(<ls_out>).
      CHECK sy-subrc EQ 0.
      APPEND VALUE #( idx = lv_idx ) TO lt_req ASSIGNING FIELD-SYMBOL(<ls_req>).
      poll_prepare( IMPORTING ev_go    = <ls_req>-go
                              ev_url   = <ls_req>-url
                              es_api   = <ls_req>-api
                              ev_token = <ls_req>-token
                    CHANGING  cs_out   = <ls_out> ).
    ENDLOOP.
    DELETE lt_req WHERE go EQ abap_false.

    DATA(lv_from) = 1.
    WHILE lv_from LE lines( lt_req ).
      DATA(lv_to) = nmin( val1 = lv_from + gc_par_max - 1 val2 = lines( lt_req ) ).

      "Send the package ...
      LOOP AT lt_req ASSIGNING <ls_req> FROM lv_from TO lv_to.
        IF lv_down IS NOT INITIAL.
          <ls_req>-reason = lv_down.
          CONTINUE.
        ENDIF.
        http_send( EXPORTING iv_url    = <ls_req>-url
                             iv_method = 'GET'
                             is_api    = <ls_req>-api
                             iv_token  = <ls_req>-token
                             iv_ctype  = 'application/json'
                   IMPORTING eo_http   = <ls_req>-http
                             ev_reason = <ls_req>-reason ).
      ENDLOOP.

      "... then read and evaluate the answers
      LOOP AT lt_req ASSIGNING <ls_req> FROM lv_from TO lv_to.
        ASSIGN gt_output[ <ls_req>-idx ] TO <ls_out>.
        CLEAR: lv_code, lv_body.
        lv_reason = <ls_req>-reason.
        IF <ls_req>-http IS BOUND.
          http_receive( EXPORTING io_http   = <ls_req>-http
                                  iv_method = 'GET'
                                  iv_url    = <ls_req>-url
                        IMPORTING ev_code   = lv_code
                                  ev_reason = lv_reason
                                  ev_body   = lv_body ).
          CLEAR <ls_req>-http.
        ENDIF.
        IF lv_code EQ 0 AND lv_down IS INITIAL.
          lv_down = |ASP not reachable in this run ({ lv_reason }) - not polled|.
        ENDIF.
        poll_result( EXPORTING iv_code   = lv_code
                               iv_reason = lv_reason
                               iv_body   = lv_body
                               iv_token  = <ls_req>-token
                     CHANGING  cs_out    = <ls_out> ).
      ENDLOOP.

      lv_from = lv_to + 1.
    ENDWHILE.

  ENDMETHOD.

  METHOD post_outbound.

    DATA: lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string.

    READ TABLE gt_apiurl INTO DATA(ls_api)
         WITH KEY direction = 'O' method = 'POST'.
    IF sy-subrc NE 0 OR ls_api-apiurl IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |POST outbound not sent - no POST API maintained in ZEINVOICE_APIURL for direction O (Outbound) - status unchanged| ).
      RETURN.
    ENDIF.

    http_call( EXPORTING iv_url    = CONV #( ls_api-apiurl )
                         iv_method = 'POST'
                         is_api    = ls_api
                         iv_token  = iv_token
                         iv_ctype  = COND #( WHEN cs_out-requestformat EQ gc_format_json THEN `application/json` ELSE `application/xml` )
                         iv_body   = cs_out-requestpayload
               IMPORTING ev_code   = lv_code
                         ev_reason = lv_reason
                         ev_body   = lv_body ).

    post_result( EXPORTING iv_code   = lv_code
                           iv_reason = lv_reason
                           iv_body   = lv_body
                 CHANGING  cs_out    = cs_out ).

  ENDMETHOD.

  METHOD post_result.

    "Evaluation of the POST outbound answer - split from POST_OUTBOUND
    "(logic unchanged), also used for the parallel requests (POST_PARALLEL)
    DATA: ls_result TYPE ty_post_result,
          lv_jerr   TYPE string,
          lv_err    TYPE string ##NEEDED.
    DATA(lv_code)   = iv_code.
    DATA(lv_reason) = iv_reason.
    DATA(lv_body)   = iv_body.

    "TaxLab JSON document -> own evaluation (same corners, logs, statuses)
    IF is_json( cs_out ) EQ abap_true.
      post_result_json( EXPORTING iv_code   = iv_code
                                  iv_reason = iv_reason
                                  iv_body   = iv_body
                        CHANGING  cs_out    = cs_out ).
      RETURN.
    ENDIF.

    cs_out-responsepayload = lv_body.

    "No HTTP response at all (connection error / timeout) -> technical
    IF lv_code EQ 0.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |POST outbound: no response / timeout - { lv_reason } - status unchanged, retry possible| ).
      RETURN.
    ENDIF.

    IF lv_body IS NOT INITIAL.
      TRY.
          /ui2/cl_json=>deserialize( EXPORTING json = lv_body
                                     CHANGING  data = ls_result ).
        CATCH cx_root INTO DATA(lx_json).
          lv_jerr = lx_json->get_text( ).
      ENDTRY.
    ENDIF.

    DATA(lv_status) = to_upper( condense( ls_result-response-status ) ).

    "VALIDATION_ERROR -> Rejected by Supplier's ASP (Corner 2) -> FAILED, stop
    IF lv_status EQ gc_status_valerr.
      cs_out-referenceid = ls_result-response-id.
      set_corner( EXPORTING is_out    = cs_out
                            iv_new    = gc_cs-rejected
                            iv_code   = 'C2'
                            iv_text   = gc_txt-c2_rej
                            iv_info   = |HTTP { lv_code }|
                            ir_errors = ls_result-response-errordetails
                  CHANGING  cv_field  = cs_out-zzc2_status ).
      IF ls_result-response-errordetails IS NOT BOUND.
        "errorDetails not where expected: readable errors from the whole response
        log_asp_errors( is_out    = cs_out
                        iv_prefix = gc_txt-c2_rej
                        it_err    = asp_errors( lv_body ) ).
      ENDIF.
      derive_overall( CHANGING cs_out = cs_out ).          "-> FAILED
      RETURN.
    ENDIF.

    "SUCCESS (HTTP 2xx) -> Accepted by Supplier's ASP (Corner 2)
    IF lv_status EQ gc_status_success AND lv_code BETWEEN 200 AND 299.
      cs_out-referenceid = COND #( WHEN ls_result-response-id IS NOT INITIAL
                                   THEN ls_result-response-id
                                   ELSE ls_result-response-messageid ).
      set_corner( EXPORTING is_out  = cs_out
                            iv_new  = gc_cs-accepted
                            iv_code = 'C2'
                            iv_text = gc_txt-c2_acc
                            iv_info = |ASP id { cs_out-referenceid }, message id { ls_result-response-messageid }|
                  CHANGING  cv_field = cs_out-zzc2_status ).
      derive_overall( CHANGING cs_out = cs_out ).          "-> IN PROGRESS
      RETURN.
    ENDIF.

    "Any other status value / HTTP error -> technical error (NOT rejected)
    add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
             iv_text = |POST outbound technical error: HTTP { lv_code } { lv_reason }, status "{ lv_status }" { ls_result-message }| &&
                       |{ COND string( WHEN lv_jerr IS NOT INITIAL THEN | - JSON: { lv_jerr }| ) } - status unchanged, retry possible| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
* Corner 3 / 4 / 5 status tracking via the status (GET) API
*----------------------------------------------------------------------*
  METHOD poll_prepare.

    "Checks, token and status URL of the status (GET) API - split from
    "POLL_STATUS (logic unchanged). EV_GO = abap_true: the GET is to be sent
    DATA: lv_error TYPE string,
          lv_sent  TYPE string.
    CLEAR: ev_go, ev_url, es_api, ev_token.

    "Step 3 only if Step 2 = Accepted by Supplier's ASP
    IF cs_out-zzc2_status NE gc_cs-accepted.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status check skipped - "{ gc_txt-c2_acc }" not reached| ).
      RETURN.
    ENDIF.

    "Polling stops when the overall status is final
    IF cs_out-zzoverall_status EQ gc_ov-success OR
       cs_out-zzoverall_status EQ gc_ov-failed.
      RETURN.
    ENDIF.

    READ TABLE gt_apiurl INTO DATA(ls_api)
                         WITH KEY direction = 'O'
                                  method    = 'GET'.
    IF sy-subrc NE 0 OR ls_api-apiurl IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |No status (GET) API maintained for { cs_out-companycode } - statuses unchanged| ).
      RETURN.
    ENDIF.

    DATA(lv_token) = get_token( EXPORTING iv_bukrs = cs_out-companycode
                                IMPORTING ev_error = lv_error ).
    IF lv_token IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status check - token error: { lv_error } - statuses unchanged, retry later| ).
      RETURN.
    ENDIF.

    "Status URL (unchanged logic): use the InstanceIdentifier actually sent
    DATA(lv_ref)  = lcl_xml=>str( cs_out-referenceid ).
    DATA(lv_inst) = |{ cs_out-supplierpeppolid }-{ cs_out-companycode }-{ cs_out-sapdocument }-{ cs_out-fiscalyear }|.
    IF is_json( cs_out ) EQ abap_true.
      "TaxLab: identifier = document UUID returned by the POST
      lv_inst = lv_ref.
    ELSE.
      FIND PCRE 'InstanceIdentifier>([^<]+)<' IN cs_out-requestpayload SUBMATCHES lv_sent.
      IF sy-subrc EQ 0 AND lv_sent IS NOT INITIAL.
        lv_inst = lv_sent.
      ENDIF.
    ENDIF.
    DATA(lv_url) = lcl_xml=>str( ls_api-apiurl ).
    IF lv_url CS '{'.
      REPLACE ALL OCCURRENCES OF '{ID}'          IN lv_url WITH lv_ref.
      REPLACE ALL OCCURRENCES OF '{REFERENCEID}' IN lv_url WITH lv_ref.
      REPLACE ALL OCCURRENCES OF '{INSTANCE}'    IN lv_url WITH lv_inst.
      REPLACE ALL OCCURRENCES OF '{DOCUMENT}'    IN lv_url WITH lcl_xml=>str( cs_out-sapdocument ).
    ELSE.
      lv_url = |{ lv_url }/{ lv_inst }|.
    ENDIF.

    ev_go    = abap_true.
    ev_url   = lv_url.
    es_api   = ls_api.
    ev_token = lv_token.

  ENDMETHOD.

  METHOD poll_status.

    DATA: lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string.

    poll_prepare( IMPORTING ev_go    = DATA(lv_go)
                            ev_url   = DATA(lv_url)
                            es_api   = DATA(ls_api)
                            ev_token = DATA(lv_token)
                  CHANGING  cs_out   = cs_out ).
    CHECK lv_go EQ abap_true.

    IF iv_after_post EQ abap_true.      "give the ASP a moment after sending
      WAIT UP TO 2 SECONDS.
    ENDIF.

    http_call( EXPORTING iv_url    = lv_url
                         iv_method = 'GET'
                         is_api    = ls_api
                         iv_token  = lv_token
                         iv_ctype  = 'application/json'
               IMPORTING ev_code   = lv_code
                         ev_reason = lv_reason
                         ev_body   = lv_body ).

    poll_result( EXPORTING iv_code   = lv_code
                           iv_reason = lv_reason
                           iv_body   = lv_body
                           iv_token  = lv_token
                 CHANGING  cs_out    = cs_out ).

  ENDMETHOD.

  METHOD poll_result.

    "Evaluation of the status (GET) answer incl. acknowledgements - split
    "from POLL_STATUS (logic unchanged), also used by POLL_PARALLEL
    DATA: lv_error   TYPE string,
          lv_result  TYPE c LENGTH 1,
          lv_ack     TYPE string,
          lv_ok      TYPE abap_bool,
          lt_entries TYPE tt_tx_entry.
    DATA(lv_code)   = iv_code.
    DATA(lv_reason) = iv_reason.
    DATA(lv_body)   = iv_body.
    DATA(lv_token)  = iv_token.

    "TaxLab JSON document: MLS messages (C3/C4/C5 ack) + TDD report (C5)
    IF is_json( cs_out ) EQ abap_true.
      poll_result_json( EXPORTING iv_code   = iv_code
                                  iv_reason = iv_reason
                                  iv_body   = iv_body
                                  iv_token  = iv_token
                        CHANGING  cs_out    = cs_out ).
      RETURN.
    ENDIF.

    "HTTP error -> log, keep current statuses, retry later
    IF lv_code EQ 0.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: no response / timeout - { lv_reason } - statuses unchanged, retry later| ).
      RETURN.
    ELSEIF lv_code LT 200 OR lv_code GT 299.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: HTTP { lv_code } { lv_reason } - statuses unchanged, retry later| ).
      RETURN.
    ENDIF.

    cs_out-responsepayload = lv_body.

    parse_status_array( EXPORTING iv_json    = lv_body
                        IMPORTING et_entries = lt_entries
                                  ev_error   = lv_error ).

    SORT: lt_entries BY transmissiontype ASCENDING status ASCENDING.
    READ TABLE lt_entries TRANSPORTING NO FIELDS
                          WITH KEY transmissiontype = 'outbound'
                                   status           = 'SUCCESS'.
    IF sy-subrc EQ 0.
      DELETE lt_entries WHERE transmissiontype EQ 'outbound' AND
                              status           EQ 'VALIDATION_ERROR'.
    ENDIF.

    IF lv_error IS NOT INITIAL.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |{ lv_error } - statuses unchanged, retry later| ).
      RETURN.
    ENDIF.

    "Empty array -> Pending at Corner 2, re-poll later
    IF lt_entries IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'C2P'
               iv_text = |{ gc_txt-c2_pend } { sy-datum DATE = ISO } { sy-uzeit TIME = ISO }| ).
      derive_overall( CHANGING cs_out = cs_out ).
      RETURN.
    ENDIF.

    "Normalise transmissionType once (case / blanks)
    LOOP AT lt_entries ASSIGNING FIELD-SYMBOL(<ls_norm>).
      <ls_norm>-transmissiontype = to_lower( condense( <ls_norm>-transmissiontype ) ).
    ENDLOOP.

    "Loop over EVERY entry - each corner status is stored independently.
    "Fixed processing order (independent of the order returned by the API):
    "  1. outbound  2. mls_inbound  3. c2_tdd_outbound  4. c2_tdd_mls_inbound
    DATA(lt_order) = VALUE string_table( ( CONV string( gc_tt-outbound ) )
                                         ( CONV string( gc_tt-mls_inbound ) )
                                         ( CONV string( gc_tt-c2_tdd_outbound ) )
                                         ( CONV string( gc_tt-c2_tdd_mls_inbound ) ) ).

    "Performance: the GET_ACK requests needed in this run (C3 Accepted
    "and C5 Accepted) are sent together first and their answers read
    "afterwards - the ASP works on them at the same time instead of one
    "after the other. The results are applied below in the fixed order,
    "exactly as before (same checks, same statuses, same log texts).
    TYPES: BEGIN OF ty_ack,
             ttype  TYPE string,
             tid    TYPE string,
             corner TYPE string,
             http   TYPE REF TO if_http_client,
             reason TYPE string,
             url    TYPE string,
             code   TYPE string,
             ok     TYPE abap_bool,
             done   TYPE abap_bool,
           END OF ty_ack.
    DATA lt_ack TYPE STANDARD TABLE OF ty_ack WITH EMPTY KEY.
    FIELD-SYMBOLS <ls_ack> TYPE ty_ack.

    "Acknowledgements (mls_inbound / c2_tdd_mls_inbound) only in background
    IF sy-batch EQ abap_true AND
       line_exists( gt_apiurl[ direction = 'O' method = gc_api_get_ack ] ).

      LOOP AT lt_order INTO DATA(lv_pre_type)
                       WHERE table_line EQ gc_tt-mls_inbound OR
                             table_line EQ gc_tt-c2_tdd_mls_inbound.
        DATA(lv_open) = xsdbool( ( lv_pre_type EQ gc_tt-mls_inbound AND
                                   cs_out-zzc3_ack_status NE gc_cs-successful ) OR
                                 ( lv_pre_type EQ gc_tt-c2_tdd_mls_inbound AND
                                   cs_out-zzc5_ack_status NE gc_cs-successful ) ).
        CHECK lv_open EQ abap_true.
        "first SUCCESS entry of this type (same entry the loop below uses first)
        LOOP AT lt_entries ASSIGNING FIELD-SYMBOL(<ls_pre>) WHERE transmissiontype EQ lv_pre_type.
          IF to_upper( condense( <ls_pre>-status ) ) EQ gc_status_success AND
             <ls_pre>-transactionid IS NOT INITIAL.
            APPEND VALUE #( ttype  = lv_pre_type
                            tid    = <ls_pre>-transactionid
                            corner = COND #( WHEN lv_pre_type EQ gc_tt-mls_inbound
                                             THEN gc_txt-c3_ack ELSE gc_txt-c5_ack ) ) TO lt_ack.
          ENDIF.
          EXIT.
        ENDLOOP.
      ENDLOOP.
      "Send all requests ...
      LOOP AT lt_ack ASSIGNING <ls_ack>.
        ack_send( EXPORTING iv_token          = lv_token
                            iv_transaction_id = <ls_ack>-tid
                  IMPORTING eo_http           = <ls_ack>-http
                            ev_reason         = <ls_ack>-reason
                            ev_url            = <ls_ack>-url ).
      ENDLOOP.
      "... then read all answers
      LOOP AT lt_ack ASSIGNING <ls_ack>.
        ack_receive( EXPORTING is_out            = cs_out
                               io_http           = <ls_ack>-http
                               iv_reason         = <ls_ack>-reason
                               iv_url            = <ls_ack>-url
                               iv_transaction_id = <ls_ack>-tid
                               iv_corner_text    = <ls_ack>-corner
                     IMPORTING ev_code           = <ls_ack>-code
                               ev_ok             = <ls_ack>-ok ).
      ENDLOOP.
    ENDIF.

    LOOP AT lt_order INTO DATA(lv_type).

      "Acknowledgement legs (C3 Accepted / C4 and C5 Accepted) are
      "processed in background processing only - in dialog they stay open
      IF ( lv_type  EQ gc_tt-mls_inbound          OR
           lv_type  EQ gc_tt-c2_tdd_mls_inbound ) AND
           sy-batch EQ abap_false.
        CONTINUE.
      ENDIF.

      LOOP AT lt_entries ASSIGNING FIELD-SYMBOL(<ls_entry>)
                                   WHERE transmissiontype EQ lv_type.

        DATA(lv_status) = to_upper( condense( <ls_entry>-status ) ).
        "Only SUCCESS is successful and only an explicit error status is
        "Failed. PROCESSING / PENDING / IN_PROGRESS etc. mean the ASP (or the
        "FTA for C5) has not answered yet -> keep the corner open, re-check later
        IF lv_status EQ gc_status_success.
          lv_result = gc_cs-successful.
        ELSEIF lv_status EQ 'FAILED'  OR lv_status EQ 'FAILURE' OR
               lv_status EQ 'ERROR'   OR lv_status EQ 'REJECTED' OR
               lv_status EQ 'VALIDATION_ERROR'.
          lv_result = gc_cs-failed.
        ELSE.
          add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'S'
                   iv_text = |{ lv_type }: ASP status { lv_status } (transactionId { <ls_entry>-transactionid }) - not final yet, re-check later| ).
          CONTINUE.
        ENDIF.
        DATA(lv_info) = |status { lv_status }, transactionId { <ls_entry>-transactionid }|.

        CASE lv_type.

          WHEN gc_tt-outbound.                              "1 -> 3.1
            set_corner( EXPORTING is_out    = cs_out
                                  iv_new    = lv_result
                                  iv_code   = 'C3S'
                                  iv_text   = gc_txt-c3_sent
                                  iv_info   = lv_info
                                  ir_errors = <ls_entry>-errordetails
                        CHANGING  cv_field  = cs_out-zzc3_sent_status ).

          WHEN gc_tt-mls_inbound.                           "2 -> 3.2
            IF lv_result EQ gc_cs-failed.
              set_corner( EXPORTING is_out    = cs_out
                                    iv_new    = gc_cs-failed
                                    iv_code   = 'C3A'
                                    iv_text   = gc_txt-c3_ack
                                    iv_info   = lv_info
                                    ir_errors = <ls_entry>-errordetails
                          CHANGING  cv_field  = cs_out-zzc3_ack_status ).
              CONTINUE.
            ENDIF.
            IF cs_out-zzc3_ack_status EQ gc_cs-successful.
              CONTINUE.                 "already acknowledged (AP) earlier
            ENDIF.
            "GET_ACK answer already read above (sent together) - else call now
            READ TABLE lt_ack ASSIGNING <ls_ack>
                 WITH KEY ttype = lv_type tid = <ls_entry>-transactionid done = abap_false.
            IF sy-subrc EQ 0.
              lv_ack = <ls_ack>-code.
              lv_ok  = <ls_ack>-ok.
              <ls_ack>-done = abap_true.
            ELSE.
              get_ack( EXPORTING is_out            = cs_out
                                 iv_token          = lv_token
                                 iv_transaction_id = <ls_entry>-transactionid
                                 iv_corner_text    = gc_txt-c3_ack
                       IMPORTING ev_code           = lv_ack
                                 ev_ok             = lv_ok ).
            ENDIF.
            IF lv_ok EQ abap_false.
              CONTINUE.                 "technical error - logged, retry later
            ENDIF.
            IF lv_ack EQ 'AP' OR
               lv_ack EQ 'AB'.
              set_corner( EXPORTING is_out  = cs_out
                                    iv_new  = gc_cs-successful
                                    iv_code = 'C3A'
                                    iv_text = gc_txt-c3_ack
                                    iv_info = |Document Response Code { lv_ack }|
                          CHANGING  cv_field = cs_out-zzc3_ack_status ).
              set_corner( EXPORTING is_out  = cs_out
                                    iv_new  = gc_cs-successful
                                    iv_code = 'C4'
                                    iv_text = gc_txt-c4
                                    iv_info = |Document Response Code { lv_ack }|
                          CHANGING  cv_field = cs_out-zzc4_status ).
            ELSE.
              set_corner( EXPORTING is_out  = cs_out
                                    iv_new  = gc_cs-failed
                                    iv_code = 'C3A'
                                    iv_text = gc_txt-c3_ack
                                    iv_info = |Document Response Code { lv_ack }|
                          CHANGING  cv_field = cs_out-zzc3_ack_status ).
            ENDIF.

          WHEN gc_tt-c2_tdd_outbound.                       "3 -> 3.3
            set_corner( EXPORTING is_out    = cs_out
                                  iv_new    = lv_result
                                  iv_code   = 'C5R'
                                  iv_text   = gc_txt-c5_rep
                                  iv_info   = lv_info
                                  ir_errors = <ls_entry>-errordetails
                        CHANGING  cv_field  = cs_out-zzc5_rep_status ).

          WHEN gc_tt-c2_tdd_mls_inbound.                    "4 -> 3.4
            IF lv_result EQ gc_cs-failed.
              set_corner( EXPORTING is_out    = cs_out
                                    iv_new    = gc_cs-failed
                                    iv_code   = 'C5A'
                                    iv_text   = gc_txt-c5_ack
                                    iv_info   = lv_info
                                    ir_errors = <ls_entry>-errordetails
                          CHANGING  cv_field  = cs_out-zzc5_ack_status ).
              CONTINUE.
            ENDIF.
            IF cs_out-zzc5_ack_status EQ gc_cs-successful.
              CONTINUE.                 "already acknowledged (AP) earlier
            ENDIF.
            "GET_ACK answer already read above (sent together) - else call now
            READ TABLE lt_ack ASSIGNING <ls_ack>
                 WITH KEY ttype = lv_type tid = <ls_entry>-transactionid done = abap_false.
            IF sy-subrc EQ 0.
              lv_ack = <ls_ack>-code.
              lv_ok  = <ls_ack>-ok.
              <ls_ack>-done = abap_true.
            ELSE.
              get_ack( EXPORTING is_out            = cs_out
                                 iv_token          = lv_token
                                 iv_transaction_id = <ls_entry>-transactionid
                                 iv_corner_text    = gc_txt-c5_ack
                       IMPORTING ev_code           = lv_ack
                                 ev_ok             = lv_ok ).
            ENDIF.
            IF lv_ok EQ abap_false.
              CONTINUE.                 "technical error - logged, retry later
            ENDIF.
            set_corner( EXPORTING is_out  = cs_out
                                  iv_new  = COND char1( WHEN lv_ack EQ 'AP' OR lv_ack EQ 'AB'
                                                        THEN gc_cs-successful
                                                        ELSE gc_cs-failed )
                                  iv_code = 'C5A'
                                  iv_text = gc_txt-c5_ack
                                  iv_info = |Document Response Code { lv_ack }|
                        CHANGING  cv_field = cs_out-zzc5_ack_status ).

        ENDCASE.

      ENDLOOP.
    ENDLOOP.

    "Unknown transmissionType: log it and ignore (no status changed)
    LOOP AT lt_entries ASSIGNING FIELD-SYMBOL(<ls_unknown>).
      IF NOT line_exists( lt_order[ table_line = <ls_unknown>-transmissiontype ] ).
        add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
                 iv_text = |Unknown transmissionType "{ <ls_unknown>-transmissiontype }" (status { <ls_unknown>-status }, transactionId { <ls_unknown>-transactionid }) ignored - no status changed| ).
      ENDIF.
    ENDLOOP.

    derive_overall( CHANGING cs_out = cs_out ).

  ENDMETHOD.

  METHOD parse_status_array.

    "Accepted shapes: [ ... ]
    "                 { "transactionDetailFlow": [ ... ] }
    "                 { "response": { "transactionDetailFlow": [ ... ] } }  (Taxilla)
    TYPES: BEGIN OF ty_inner,
             transactiondetailflow TYPE tt_tx_entry,
           END OF ty_inner,
           BEGIN OF ty_wrap,
             transactiondetailflow TYPE tt_tx_entry,
             response              TYPE ty_inner,
           END OF ty_wrap.
    DATA: ls_wrap  TYPE ty_wrap,
          lv_first TYPE string.

    CLEAR: et_entries, ev_error.

    FIND PCRE '^\s*([\[\{])' IN iv_json SUBMATCHES lv_first.
    IF sy-subrc NE 0.
      ev_error = |Status (GET) API: response is not JSON (array expected)|.
      RETURN.
    ENDIF.

    TRY.
        IF lv_first EQ '['.
          /ui2/cl_json=>deserialize( EXPORTING json = iv_json
                                     CHANGING  data = et_entries ).
        ELSEIF iv_json CS 'transactionDetailFlow'.
          "Same array wrapped in an object
          /ui2/cl_json=>deserialize( EXPORTING json = iv_json
                                     CHANGING  data = ls_wrap ).
          et_entries = COND #( WHEN ls_wrap-response-transactiondetailflow IS NOT INITIAL
                               THEN ls_wrap-response-transactiondetailflow
                               ELSE ls_wrap-transactiondetailflow ).
        ELSE.
          ev_error = |Status (GET) API: unexpected JSON object (array expected)|.
        ENDIF.
      CATCH cx_root INTO DATA(lx_json).
        ev_error = |Status (GET) API: JSON could not be parsed - { lx_json->get_text( ) }|.
        CLEAR et_entries.
    ENDTRY.

  ENDMETHOD.

  METHOD get_ack.

    "GET_ACK by transactionId + Document Response Code (synchronous)
    "ev_ok = abap_false -> technical problem (already logged), keep status
    DATA: lo_http   TYPE REF TO if_http_client,
          lv_reason TYPE string,
          lv_url    TYPE string.

    CLEAR: ev_code, ev_ok.

    IF iv_transaction_id IS INITIAL.
      add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |{ iv_corner_text }: transactionId missing in status entry - GET_ACK not called, status unchanged| ).
      RETURN.
    ENDIF.

    READ TABLE gt_apiurl TRANSPORTING NO FIELDS
         WITH KEY direction = 'O' method = gc_api_get_ack.
    IF sy-subrc NE 0.
      add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |No GET_ACK API maintained in ZEINVOICE_APIURL for direction O (Outbound) - { iv_corner_text } unchanged| ).
      RETURN.
    ENDIF.

    ack_send( EXPORTING iv_token          = iv_token
                        iv_transaction_id = iv_transaction_id
              IMPORTING eo_http           = lo_http
                        ev_reason         = lv_reason
                        ev_url            = lv_url ).
    ack_receive( EXPORTING is_out            = is_out
                           io_http           = lo_http
                           iv_reason         = lv_reason
                           iv_url            = lv_url
                           iv_transaction_id = iv_transaction_id
                           iv_corner_text    = iv_corner_text
                 IMPORTING ev_code           = ev_code
                           ev_ok             = ev_ok ).

  ENDMETHOD.

  METHOD ack_send.

    "Send the GET_ACK request (answer read with ack_receive)
    "e.g. .../accesspoint/v1/artifacts/transaction-stream?transactionId=<id>
    CLEAR: eo_http, ev_reason, ev_url.

    READ TABLE gt_apiurl INTO DATA(ls_api)
         WITH KEY direction = 'O' method = gc_api_get_ack.
    IF sy-subrc NE 0 OR ls_api-apiurl IS INITIAL.
      ev_reason = |No GET_ACK API maintained in ZEINVOICE_APIURL|.
      RETURN.
    ENDIF.

    DATA(lv_id) = escape( val = iv_transaction_id format = cl_abap_format=>e_url_full ).
    ev_url = lcl_xml=>str( ls_api-apiurl ).
    IF ev_url CS '{TRANSACTIONID}'.
      REPLACE ALL OCCURRENCES OF '{TRANSACTIONID}' IN ev_url WITH lv_id.
    ELSEIF ev_url CP '*transactionId='.
      ev_url = |{ ev_url }{ lv_id }|.
    ELSEIF ev_url CS '?'.
      ev_url = |{ ev_url }&transactionId={ lv_id }|.
    ELSE.
      ev_url = |{ ev_url }?transactionId={ lv_id }|.
    ENDIF.

    http_send( EXPORTING iv_url    = ev_url
                         iv_method = 'GET'
                         is_api    = ls_api
                         iv_token  = iv_token
               IMPORTING eo_http   = eo_http
                         ev_reason = ev_reason ).

  ENDMETHOD.

  METHOD ack_receive.

    "Read the GET_ACK answer and the Document Response Code
    "ev_ok = abap_false -> technical problem (logged), keep status
    DATA: lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string,
          lv_error  TYPE string.

    CLEAR: ev_code, ev_ok.

    lv_reason = iv_reason.
    IF io_http IS BOUND.
      http_receive( EXPORTING io_http   = io_http
                              iv_method = 'GET'
                              iv_url    = iv_url
                    IMPORTING ev_code   = lv_code
                              ev_reason = lv_reason
                              ev_body   = lv_body ).
    ENDIF.

    IF lv_code EQ 0.
      add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |GET_ACK ({ iv_corner_text }, transactionId { iv_transaction_id }): no response / timeout - { lv_reason } - status unchanged, retry later| ).
      RETURN.
    ELSEIF lv_code LT 200 OR lv_code GT 299.
      add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |GET_ACK ({ iv_corner_text }, transactionId { iv_transaction_id }): HTTP { lv_code } { lv_reason } - status unchanged, retry later| ).
      RETURN.
    ENDIF.

    parse_ack_code( EXPORTING iv_xml   = lv_body
                    IMPORTING ev_code  = ev_code
                              ev_error = lv_error ).
    IF lv_error IS NOT INITIAL.
      add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |GET_ACK ({ iv_corner_text }, transactionId { iv_transaction_id }): { lv_error } - status unchanged, retry later| ).
      CLEAR ev_code.
      RETURN.
    ENDIF.

    ev_ok = abap_true.

  ENDMETHOD.

  METHOD parse_ack_code.

    DATA lv_xstr TYPE xstring.

    CLEAR: ev_code, ev_error.

    IF iv_xml IS INITIAL.
      ev_error = |Document Response Code: empty GET_ACK response|.
      RETURN.
    ENDIF.

    TRY.
        lv_xstr = cl_abap_codepage=>convert_to( source = iv_xml codepage = `UTF-8` ).
      CATCH cx_root INTO DATA(lx_cp).
        ev_error = |Document Response Code: response could not be converted to UTF-8 - { lx_cp->get_text( ) }|.
        RETURN.
    ENDTRY.

    DATA(lo_ixml)   = cl_ixml=>create( ).
    DATA(lo_sf)     = lo_ixml->create_stream_factory( ).
    DATA(lo_doc)    = lo_ixml->create_document( ).
    DATA(lo_parser) = lo_ixml->create_parser( stream_factory = lo_sf
                                              istream        = lo_sf->create_istream_xstring( lv_xstr )
                                              document       = lo_doc ).
    IF lo_parser->parse( ) NE 0.
      DATA(lo_perr) = lo_parser->get_error( index = 0 ).
      ev_error = |Document Response Code: XML parsing failed - | &&
                 COND string( WHEN lo_perr IS BOUND
                              THEN |{ lo_perr->get_reason( ) } (line { lo_perr->get_line( ) })|
                              ELSE `unknown parser error` ).
      RETURN.
    ENDIF.

    DATA(lo_coll) = lo_doc->get_elements_by_tag_name_ns( name = 'ResponseCode'
                                                         uri  = gc_ns_cbc ).
    IF lo_coll IS BOUND.
      DATA(lo_iter) = lo_coll->create_iterator( ).
      DATA(lo_node) = lo_iter->get_next( ).
      WHILE lo_node IS BOUND.
        DATA(lo_resp) = lo_node->get_parent( ).
        IF lo_resp IS BOUND AND lo_resp->get_name( ) EQ 'Response'.
          DATA(lo_docresp) = lo_resp->get_parent( ).
          IF lo_docresp IS BOUND AND lo_docresp->get_name( ) EQ 'DocumentResponse'.
            ev_code = to_upper( condense( lo_node->get_value( ) ) ).
            IF ev_code IS INITIAL.
              ev_error = |Document Response Code is empty|.
            ENDIF.
            RETURN.
          ENDIF.
        ENDIF.
        lo_node = lo_iter->get_next( ).
      ENDWHILE.
    ENDIF.

    ev_error = |Document Response Code (DocumentResponse/Response/ResponseCode) not found in GET_ACK response|.

  ENDMETHOD.

  METHOD set_corner.

    CHECK iv_new NE cv_field.          "log only real changes
    cv_field = iv_new.

    DATA(lv_bad)    = xsdbool( iv_new EQ gc_cs-failed OR iv_new EQ gc_cs-rejected ).
    DATA(lv_suffix) = COND string( WHEN iv_new EQ gc_cs-failed     THEN ` = Failed`
                                   WHEN iv_new EQ gc_cs-successful THEN ` = Successful` ).

    add_log( is_out   = is_out
             iv_msgty = COND char1( WHEN lv_bad EQ abap_true THEN 'E' ELSE 'S' )
             iv_code  = COND string( WHEN lv_bad EQ abap_true THEN `E` ELSE iv_code )
             iv_text  = |{ iv_text }{ lv_suffix } { sy-datum DATE = ISO } { sy-uzeit TIME = ISO } { iv_info }| ).

    IF lv_bad EQ abap_true AND ir_errors IS BOUND.
      log_error_details( is_out = is_out iv_prefix = iv_text ir_details = ir_errors ).
    ENDIF.

  ENDMETHOD.

  METHOD log_error_details.

    FIELD-SYMBOLS <lv_any> TYPE any.

    CHECK ir_details IS BOUND.
    ASSIGN ir_details->* TO <lv_any>.
    CHECK sy-subrc EQ 0.

    TRY.
        DATA(lv_json) = /ui2/cl_json=>serialize( data        = <lv_any>
                                                 pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
      CATCH cx_root INTO DATA(lx_err).
        add_log( is_out = is_out iv_msgty = 'W' iv_code = 'W'
                 iv_text = |{ iv_prefix } - error details could not be read: { lx_err->get_text( ) }| ).
        RETURN.
    ENDTRY.

    "Readable error lines (string, object or array of error details)
    log_asp_errors( is_out    = is_out
                    iv_prefix = iv_prefix
                    it_err    = asp_errors( |\{"errorDetails":{ lv_json }\}| ) ).

  ENDMETHOD.

  METHOD derive_overall.

    DATA(lv_any_failed) = xsdbool( cs_out-zzc3_sent_status EQ gc_cs-failed OR
                                   cs_out-zzc3_ack_status  EQ gc_cs-failed OR
                                   cs_out-zzc4_status      EQ gc_cs-failed OR
                                   cs_out-zzc5_rep_status  EQ gc_cs-failed OR
                                   cs_out-zzc5_ack_status  EQ gc_cs-failed ).

    cs_out-zzoverall_status = COND #( WHEN cs_out-zzc2_status EQ gc_cs-rejected OR
                                           lv_any_failed      EQ abap_true
                                      THEN gc_ov-failed
                                      "SUCCESS only when every corner is completed: C2 Accepted and C3 (Sent +
                                      "Accepted), C4 Optional and C5 (Reported + Accepted) all Successful -
                                      "otherwise the document stays IN PROGRESS (message type W)
                                      WHEN     cs_out-zzc2_status      EQ gc_cs-accepted           AND

                                           ( ( cs_out-zzc3_sent_status EQ gc_cs-successful         AND
                                               cs_out-zzc3_ack_status  EQ gc_cs-successful         AND
                                               cs_out-suppliercountry  EQ cs_out-customercountry ) OR

                                               cs_out-suppliercountry  NE cs_out-customercountry ) AND

                                               cs_out-zzc5_rep_status  EQ gc_cs-successful         AND
                                               cs_out-zzc5_ack_status  EQ gc_cs-successful
                                      THEN gc_ov-success
                                      WHEN cs_out-zzc1_status IS NOT INITIAL
                                      THEN gc_ov-in_progress
                                      ELSE space ).

    "Message type / LED (ZEINVOICE_DETAIL-MSGTY, selection S_STATUS)
    CASE cs_out-zzoverall_status.
      WHEN gc_ov-success.
        cs_out-messagetype = 'S'.
        cs_out-status      = icon_led_green.
      WHEN gc_ov-failed.
        cs_out-messagetype = 'E'.
        cs_out-status      = icon_led_red.
      WHEN gc_ov-in_progress.
        cs_out-messagetype = 'W'.
        cs_out-status      = icon_led_yellow.
      WHEN OTHERS.
        "not generated yet - keep the stored message type
    ENDCASE.

    "Legacy single status kept only as a derived summary (other reports)
    cs_out-einvoicestatus = legacy_pstatus( cs_out ).

  ENDMETHOD.

  METHOD legacy_pstatus.

    rv_status = COND #(
      WHEN is_out-zzc2_status      EQ gc_cs-rejected   THEN 'REJECTED_C2'
      WHEN is_out-zzc5_rep_status  EQ gc_cs-failed OR
           is_out-zzc5_ack_status  EQ gc_cs-failed     THEN 'FAILED_C5'
      WHEN is_out-zzc4_status      EQ gc_cs-failed     THEN 'FAILED_C4'
      WHEN is_out-zzc3_sent_status EQ gc_cs-failed OR
           is_out-zzc3_ack_status  EQ gc_cs-failed     THEN 'FAILED_C3'
      WHEN is_out-zzc5_ack_status  EQ gc_cs-successful THEN gc_st-c5
      WHEN is_out-zzc4_status      EQ gc_cs-successful THEN gc_st-c4
      WHEN is_out-zzc3_sent_status EQ gc_cs-successful OR
           is_out-zzc3_ack_status  EQ gc_cs-successful THEN gc_st-c3
      WHEN is_out-zzc2_status      EQ gc_cs-accepted   THEN gc_st-c2
      WHEN is_out-zzc1_status      EQ gc_cs-generated  THEN gc_st-c1
      ELSE is_out-einvoicestatus ).

  ENDMETHOD.

  METHOD load_corner_status.

    CHECK gt_output IS NOT INITIAL.

    SELECT bukrs, vbeln, gjahr,
           zzc1_status, zzc2_status, zzc3_sent_status, zzc3_ack_status,
           zzc4_status, zzc5_rep_status, zzc5_ack_status,
           zzoverall_status
      FROM zeinvoice_detail
      FOR ALL ENTRIES IN @gt_output
      WHERE bukrs EQ @gt_output-companycode AND
            vbeln EQ @gt_output-sapdocument AND
            gjahr EQ @gt_output-fiscalyear
      INTO TABLE @DATA(lt_detail).

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      IF iv_only_checked EQ abap_true AND <ls_out>-check EQ abap_false.
        CONTINUE.
      ENDIF.

      READ TABLE lt_detail INTO DATA(ls_detail)
           WITH KEY bukrs = <ls_out>-companycode
                    vbeln = <ls_out>-sapdocument
                    gjahr = <ls_out>-fiscalyear.
      IF sy-subrc NE 0.
        CLEAR ls_detail.
      ENDIF.
      <ls_out>-zzc1_status      = ls_detail-zzc1_status.
      <ls_out>-zzc2_status      = ls_detail-zzc2_status.
      <ls_out>-zzc3_sent_status = ls_detail-zzc3_sent_status.
      <ls_out>-zzc3_ack_status  = ls_detail-zzc3_ack_status.
      <ls_out>-zzc4_status      = ls_detail-zzc4_status.
      <ls_out>-zzc5_rep_status  = ls_detail-zzc5_rep_status.
      <ls_out>-zzc5_ack_status  = ls_detail-zzc5_ack_status.
      <ls_out>-zzoverall_status = ls_detail-zzoverall_status.

      "Documents processed before the separate corner fields existed
      IF <ls_out>-zzc1_status IS INITIAL AND <ls_out>-zzc2_status IS INITIAL.
        migrate_legacy( CHANGING cs_out = <ls_out> ).
      ENDIF.

      derive_overall( CHANGING cs_out = <ls_out> ).
    ENDLOOP.

  ENDMETHOD.

  METHOD migrate_legacy.

    DATA: lv_level TYPE i,
          lv_fail  TYPE i.

    corner_level( EXPORTING iv_status = cs_out-einvoicestatus
                  IMPORTING ev_level  = lv_level
                            ev_failed = lv_fail ).

    IF cs_out-einvoicestatus EQ 'REJECTED_C2'.
      cs_out-zzc1_status = gc_cs-generated.
      cs_out-zzc2_status = gc_cs-rejected.
    ELSEIF lv_fail GE 3 OR ( lv_fail EQ 0 AND lv_level GE 2 ).
      cs_out-zzc1_status = gc_cs-generated.
      cs_out-zzc2_status = gc_cs-accepted.
    ELSEIF lv_fail EQ 0 AND lv_level EQ 1.
      cs_out-zzc1_status = gc_cs-generated.
    ENDIF.
    "FAILED_C1 / FAILED_C2 / EXISTS_C2 / PENDING: nothing accepted yet

  ENDMETHOD.

  METHOD corner_icon.
    IF iv_value EQ gc_cs-generated OR iv_value EQ gc_cs-accepted OR
       iv_value EQ gc_cs-successful.
      ev_icon = icon_led_green.
    ELSEIF iv_value EQ gc_cs-rejected OR iv_value EQ gc_cs-failed.
      ev_icon = icon_led_red.
    ELSEIF iv_value EQ 'P' OR cv_waiting EQ abap_true.   "partially done / next open corner
      ev_icon    = icon_led_yellow.
      cv_waiting = abap_false.
    ELSE.
      ev_icon = icon_led_inactive.
    ENDIF.
  ENDMETHOD.

  METHOD corner_strip_html.

    "Five corner boxes (used by Display HTML, Display Response and the
    "processing log). Sequence: C1, C2, C3 Sent, C3 Accepted, C4,
    "C5 Reported, C5 Accepted - C3 and C5 each hold two statuses.
    TYPES: BEGIN OF ty_line,
             text  TYPE string,
             value TYPE c LENGTH 1,
           END OF ty_line,
           tt_line TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY,
           BEGIN OF ty_box,
             label TYPE string,
             lines TYPE tt_line,
           END OF ty_box.
    DATA lt_box TYPE STANDARD TABLE OF ty_box WITH EMPTY KEY.

    lt_box = VALUE #(
      ( label = `C1` lines = VALUE #( ( text = gc_txt-c1 value = is_out-zzc1_status ) ) )
      ( label = `C2` lines = VALUE #( ( text  = COND #( WHEN is_out-zzc2_status EQ gc_cs-rejected
                                                        THEN gc_txt-c2_rej ELSE gc_txt-c2_acc )
                                        value = is_out-zzc2_status ) ) )
      ( label = `C3` lines = VALUE #( ( text = gc_txt-c3_sent value = is_out-zzc3_sent_status )
                                      ( text = gc_txt-c3_ack  value = is_out-zzc3_ack_status ) ) )
      ( label = `C4` lines = VALUE #( ( text = gc_txt-c4 value = is_out-zzc4_status ) ) )
      ( label = `C5` lines = VALUE #( ( text = gc_txt-c5_rep value = is_out-zzc5_rep_status )
                                      ( text = gc_txt-c5_ack value = is_out-zzc5_ack_status ) ) ) ).

    DATA(lv_wait) = xsdbool( is_out-zzoverall_status EQ gc_ov-in_progress ).

    LOOP AT lt_box INTO DATA(ls_box).
      DATA(lv_v1) = ls_box-lines[ 1 ]-value.
      DATA(lv_v2) = COND char1( WHEN lines( ls_box-lines ) GT 1
                                THEN ls_box-lines[ 2 ]-value ELSE lv_v1 ).
      DATA(lv_value) = combine_status( iv_a = lv_v1 iv_b = lv_v2 ).
      DATA(lv_cls) = COND string(
        WHEN lv_value EQ gc_cs-generated OR lv_value EQ gc_cs-accepted OR
             lv_value EQ gc_cs-successful                               THEN `ok`
        WHEN lv_value EQ gc_cs-rejected OR lv_value EQ gc_cs-failed    THEN `ko`
        WHEN lv_value EQ 'P' OR lv_wait EQ abap_true                   THEN `wt`
        ELSE `na` ).
      IF lv_cls EQ `wt`.
        lv_wait = abap_false.
      ENDIF.

      "One line per status - no 'Successful' label, only Failed / Awaiting
      DATA(lv_lines) = ``.
      LOOP AT ls_box-lines INTO DATA(ls_line).
        DATA(lv_note) = COND string(
          WHEN ls_line-value IS INITIAL AND lv_cls EQ `wt`    THEN `Awaiting`
          ELSE `` ).
        lv_lines = lv_lines && COND string( WHEN lv_lines IS NOT INITIAL THEN `<br>` ) &&
                   h( disp_text( ls_line-text ) ) &&
                   COND string( WHEN lv_note IS NOT INITIAL THEN | <i>({ lv_note })</i>| ).
      ENDLOOP.

      rv = rv && |<div class="c { lv_cls }"><b>{ ls_box-label }</b><span>{ lv_lines }</span></div>|.
    ENDLOOP.

  ENDMETHOD.

  METHOD combine_status.
    "Two statuses of one corner box: equal -> that value, any Failed ->
    "Failed, otherwise partially done -> 'P' (in progress)
    IF iv_a EQ iv_b.
      rv = iv_a.
    ELSEIF iv_a EQ gc_cs-failed OR iv_b EQ gc_cs-failed.
      rv = gc_cs-failed.
    ELSE.
      rv = 'P'.
    ENDIF.
  ENDMETHOD.

  METHOD disp_text.
    "Display text: status text without '(Corner n)'
    rv = iv.
    REPLACE ALL OCCURRENCES OF PCRE '(?-x)\s*\(Corner [1-5]\)' IN rv WITH ``.
  ENDMETHOD.

  METHOD corner_responses_html.

    "All corner responses in the processing sequence - C1, C2, C3 Sent,
    "C3 Accepted, C4, C5 Reported, C5 Accepted - in plain language
    TYPES: BEGIN OF ty_step,
             corner  TYPE string,
             text    TYPE string,
             value   TYPE c LENGTH 1,
             code    TYPE string,
             ttype   TYPE string,
             meaning TYPE string,
           END OF ty_step.
    DATA: lt_steps   TYPE STANDARD TABLE OF ty_step WITH EMPTY KEY,
          lt_entries TYPE tt_tx_entry,
          lv_error   TYPE string,
          lv_rows    TYPE string,
          lv_when    TYPE string,
          lv_resp    TYPE string.
    FIELD-SYMBOLS <ls_e> TYPE ty_tx_entry.

    "Transmission entries of the last status (GET) response
    IF is_out-responsepayload CS 'transmissionType'.
      parse_status_array( EXPORTING iv_json    = is_out-responsepayload
                          IMPORTING et_entries = lt_entries
                                    ev_error   = lv_error ).
      LOOP AT lt_entries ASSIGNING FIELD-SYMBOL(<ls_norm>).
        <ls_norm>-transmissiontype = to_lower( condense( <ls_norm>-transmissiontype ) ).
      ENDLOOP.
    ENDIF.

    DATA(lv_rej) = xsdbool( is_out-zzc2_status EQ gc_cs-rejected ).
    lt_steps = VALUE #(
      ( corner = `C1` text = gc_txt-c1 value = is_out-zzc1_status code = `C1`
        meaning = `The PINT AE XML of the document was created and stored in SAP.` )
      ( corner = `C2` value = is_out-zzc2_status code = `C2`
        text    = COND #( WHEN lv_rej EQ abap_true THEN gc_txt-c2_rej ELSE gc_txt-c2_acc )
        meaning = COND #( WHEN lv_rej EQ abap_true
                          THEN `Our ASP rejected the document (validation error) - see the messages above.`
                          ELSE `Our ASP validated the document and accepted it for transmission.` ) )
      ( corner = `C3` text = gc_txt-c3_sent value = is_out-zzc3_sent_status code = `C3S`
        ttype = gc_tt-outbound
        meaning = `Our ASP sent the document to the buyer's ASP over the Peppol network.` )
      ( corner = `C3` text = gc_txt-c3_ack value = is_out-zzc3_ack_status code = `C3A`
        ttype = gc_tt-mls_inbound
        meaning = `The buyer's ASP confirmed receipt of the document (response code AP = accepted).` )
      ( corner = `C4` text = gc_txt-c4 value = is_out-zzc4_status code = `C4`
        ttype = gc_tt-mls_inbound
        meaning = `The document is available to the buyer (confirmed by the buyer's ASP acknowledgement).` )
      ( corner = `C5` text = gc_txt-c5_rep value = is_out-zzc5_rep_status code = `C5R`
        ttype = gc_tt-c2_tdd_outbound
        meaning = `Our ASP reported the tax data of the document to the FTA.` )
      ( corner = `C5` text = gc_txt-c5_ack value = is_out-zzc5_ack_status code = `C5A`
        ttype = gc_tt-c2_tdd_mls_inbound
        meaning = `The FTA confirmed receipt of the tax data (response code AP = accepted).` ) ).

    LOOP AT lt_steps INTO DATA(ls_step).
      DATA(lv_no) = sy-tabix.

      "Result of the step
      DATA(lv_cls) = COND string(
        WHEN ls_step-value EQ gc_cs-generated OR ls_step-value EQ gc_cs-accepted OR
             ls_step-value EQ gc_cs-successful                                 THEN `ok`
        WHEN ls_step-value EQ gc_cs-rejected OR ls_step-value EQ gc_cs-failed THEN `ko`
        WHEN is_out-zzoverall_status EQ gc_ov-in_progress                     THEN `wt`
        ELSE `na` ).
      DATA(lv_res) = SWITCH string( lv_cls WHEN `ok` THEN `Done`
                                           WHEN `ko` THEN `Error`
                                           WHEN `wt` THEN `Pending`
                                           ELSE `Not reached` ).

      "Log line of the step (date / time, response code)
      DATA(lv_logmsg) = ``.
      LOOP AT gt_errors INTO DATA(ls_log) USING KEY doc
           WHERE bukrs = is_out-companycode AND vbeln = is_out-sapdocument AND
                 gjahr = is_out-fiscalyear  AND type  = is_out-type.
        "C2 rejection is logged with code E00n, not 'C2'
        CHECK ls_log-code EQ ls_step-code OR
              ( ls_step-code EQ `C2` AND lv_rej EQ abap_true AND ls_log-message CS gc_txt-c2_rej ).
        lv_logmsg = ls_log-message.
        EXIT.
      ENDLOOP.

      "ASP transmission entry of the step
      UNASSIGN <ls_e>.
      IF ls_step-ttype IS NOT INITIAL.
        ASSIGN lt_entries[ transmissiontype = ls_step-ttype ] TO <ls_e>.
      ENDIF.

      CLEAR: lv_when, lv_resp.
      IF <ls_e> IS ASSIGNED AND <ls_e>-createddate IS NOT INITIAL.
        lv_when = |{ fmt_iso( <ls_e>-createddate ) } (ASP, UTC)|.
      ELSEIF lv_logmsg IS NOT INITIAL.
        lv_when = fmt_iso( lv_logmsg ).
        IF lv_when IS NOT INITIAL.
          lv_when = |{ lv_when } (SAP)|.
        ENDIF.
      ENDIF.

      IF <ls_e> IS ASSIGNED.
        lv_resp = |ASP status { h( <ls_e>-status ) }|.
        IF <ls_e>-receiverparticipantid IS NOT INITIAL AND
           ( ls_step-code EQ `C3S` OR ls_step-code EQ `C5R` ).
          lv_resp = |{ lv_resp }<br>Sent to { h( <ls_e>-receiverparticipantid ) }|.
        ENDIF.
        lv_resp = |{ lv_resp }<br><span class="sm">transactionId { h( <ls_e>-transactionid ) }</span>|.
        IF to_upper( condense( <ls_e>-status ) ) NE gc_status_success AND <ls_e>-errordetails IS BOUND.
          TRY.
              DATA(lv_err) = /ui2/cl_json=>serialize( data = <ls_e>-errordetails ).
            CATCH cx_root.
              CLEAR lv_err.
          ENDTRY.
          IF lv_err IS NOT INITIAL AND lv_err NE `""`.
            lv_resp = |{ lv_resp }<br><span style="color:#bb0000">{ h( lv_err ) }</span>|.
          ENDIF.
        ENDIF.
      ENDIF.

      CASE ls_step-code.
        WHEN `C1`.
          FIND PCRE '(\d+)\scharacters' IN lv_logmsg SUBMATCHES DATA(lv_len).
          IF sy-subrc EQ 0.
            lv_resp = |PINT AE XML stored in SAP ({ lv_len } characters)|.
          ENDIF.
        WHEN `C2`.
          IF is_out-referenceid IS NOT INITIAL.
            lv_resp = |ASP reference { h( is_out-referenceid ) }|.
          ENDIF.
          IF lv_rej EQ abap_true.
            lv_resp = |{ lv_resp }{ COND string( WHEN lv_resp IS NOT INITIAL THEN `<br>` ) }| &&
                      |<span style="color:#bb0000">Validation failed - see "What went wrong" above</span>|.
          ENDIF.
        WHEN `C3A` OR `C4` OR `C5A`.
          "Document Response Code read from the GET_ACK response
          FIND PCRE 'Response\sCode\s(\w+)' IN lv_logmsg SUBMATCHES DATA(lv_rc).
          IF sy-subrc EQ 0.
            lv_resp = |Document Response Code <b>{ h( lv_rc ) }</b>| &&
                      COND string( WHEN lv_rc EQ 'AP' OR
                                        lv_rc EQ 'AB'
                                   THEN ` (accepted)`
                                   WHEN lv_rc EQ 'RE'
                                   THEN ` (rejected)` ) &&
                      COND string( WHEN lv_resp IS NOT INITIAL THEN |<br>{ lv_resp }| ).
          ENDIF.
      ENDCASE.

      lv_rows = lv_rows &&
        |<tr><td>{ lv_no }</td><td><b>{ ls_step-corner }</b></td>| &&
        |<td><b>{ h( disp_text( ls_step-text ) ) }</b><div class="cat">{ h( ls_step-meaning ) }</div></td>| &&
        |<td class="nw"><span class="dot { lv_cls }"></span>{ lv_res }</td>| &&
        |<td class="nw">{ h( lv_when ) }</td><td>{ lv_resp }</td></tr>|.
    ENDLOOP.

    rv = |<table class="seq"><tr><th>#</th><th>Corner</th><th>Status</th><th>Result</th>| &&
         |<th>Date / time</th><th>ASP response</th></tr>{ lv_rows }</table>|.

  ENDMETHOD.

  METHOD fmt_iso.
    "ISO date/time (2026-10-20T06:22:56 / 2026-10-20 06:22:56) -> 20.10.2026 06:22:56
    FIND PCRE '(\d{4})-(\d{2})-(\d{2})[T\s]+(\d{2}:\d{2}:\d{2})' IN iv
         SUBMATCHES DATA(lv_y) DATA(lv_m) DATA(lv_d) DATA(lv_t).
    IF sy-subrc EQ 0.
      rv = |{ lv_d }.{ lv_m }.{ lv_y } { lv_t }|.
    ENDIF.
  ENDMETHOD.






  METHOD corner_status.
    rv_status = SWITCH #( iv_level
                          WHEN 1 THEN gc_st-c1
                          WHEN 2 THEN gc_st-c2
                          WHEN 3 THEN gc_st-c3
                          WHEN 4 THEN gc_st-c4
                          WHEN 5 THEN gc_st-c5
                          ELSE gc_st-pending ).
  ENDMETHOD.

  METHOD corner_text.
    rv_text = SWITCH string( iv_level
                WHEN 1 THEN gc_txt-c1
                WHEN 2 THEN gc_txt-c2_acc
                WHEN 3 THEN gc_txt-c3_sent
                WHEN 4 THEN gc_txt-c4
                WHEN 5 THEN gc_txt-c5_ack ).
  ENDMETHOD.

  METHOD corner_level.
    DATA(lv_status) = to_upper( lcl_xml=>str( iv_status ) ).
    CLEAR: ev_level, ev_failed.
    IF lv_status CP 'FAILED_C*' OR lv_status CP 'REJECTED_C*' OR lv_status CP 'EXISTS_C*'.
      ev_failed = substring( val = lv_status off = strlen( lv_status ) - 1 len = 1 ).
      ev_level  = ev_failed - 1.
      RETURN.
    ENDIF.
    ev_level = COND #( WHEN lv_status CP 'C5*' THEN 5
                       WHEN lv_status CP 'C4*' THEN 4
                       WHEN lv_status CP 'C3*' OR lv_status EQ 'SUCCESS' THEN 3
                       WHEN lv_status CP 'C2*' THEN 2
                       WHEN lv_status CP 'C1*' THEN 1
                       ELSE 0 ).
  ENDMETHOD.

  METHOD set_row_display.

    DATA lv_wait TYPE abap_bool.

    derive_overall( CHANGING cs_out = cs_out ).

    "One LED per corner C1..C5 (C3 = Sent + Accepted, C5 = Reported + Accepted)
    lv_wait = xsdbool( cs_out-zzoverall_status EQ gc_ov-in_progress ).
    corner_icon( EXPORTING iv_value = cs_out-zzc1_status IMPORTING ev_icon = cs_out-c1 CHANGING cv_waiting = lv_wait ).
    corner_icon( EXPORTING iv_value = cs_out-zzc2_status IMPORTING ev_icon = cs_out-c2 CHANGING cv_waiting = lv_wait ).
    corner_icon( EXPORTING iv_value = combine_status( iv_a = cs_out-zzc3_sent_status iv_b = cs_out-zzc3_ack_status )
                 IMPORTING ev_icon  = cs_out-c3 CHANGING cv_waiting = lv_wait ).
    corner_icon( EXPORTING iv_value = cs_out-zzc4_status IMPORTING ev_icon = cs_out-c4 CHANGING cv_waiting = lv_wait ).
    corner_icon( EXPORTING iv_value = combine_status( iv_a = cs_out-zzc5_rep_status iv_b = cs_out-zzc5_ack_status )
                 IMPORTING ev_icon  = cs_out-c5 CHANGING cv_waiting = lv_wait ).
    CLEAR: cs_out-c3a, cs_out-c5a.

    "Latest corner status text: a failure first, otherwise furthest corner
    "Latest corner status (failure first, otherwise furthest corner) -
    "shown without '(Corner n)' and without Successful / Failed
    DATA(lv_text) = disp_text( COND string(
      WHEN cs_out-zzc2_status      EQ gc_cs-rejected   THEN gc_txt-c2_rej
      WHEN cs_out-zzc3_sent_status EQ gc_cs-failed     THEN gc_txt-c3_sent
      WHEN cs_out-zzc3_ack_status  EQ gc_cs-failed     THEN gc_txt-c3_ack
      WHEN cs_out-zzc4_status      EQ gc_cs-failed     THEN gc_txt-c4
      WHEN cs_out-zzc5_rep_status  EQ gc_cs-failed     THEN gc_txt-c5_rep
      WHEN cs_out-zzc5_ack_status  EQ gc_cs-failed     THEN gc_txt-c5_ack
      WHEN cs_out-zzc5_ack_status  EQ gc_cs-successful THEN gc_txt-c5_ack
      WHEN cs_out-zzc5_rep_status  EQ gc_cs-successful THEN gc_txt-c5_rep
      WHEN cs_out-zzc4_status      EQ gc_cs-successful THEN gc_txt-c4
      WHEN cs_out-zzc3_ack_status  EQ gc_cs-successful THEN gc_txt-c3_ack
      WHEN cs_out-zzc3_sent_status EQ gc_cs-successful THEN gc_txt-c3_sent
      WHEN cs_out-zzc2_status      EQ gc_cs-accepted AND
           cs_out-responsepayload  CS 'transactionDetailFlow' THEN gc_txt-c2_pend
      WHEN cs_out-zzc2_status      EQ gc_cs-accepted   THEN gc_txt-c2_acc
      WHEN cs_out-zzc1_status      EQ gc_cs-generated  THEN gc_txt-c1
      ELSE `Not yet submitted` ) ).

    cs_out-corner = lv_text.

    "Peppol Corner column: log icon, latest corner status as quick info
    CALL FUNCTION 'ICON_CREATE'
      EXPORTING
        name                  = 'ICON_PROTOCOL'
        info                  = |{ cs_out-corner } - click for processing log|
        add_stdinf            = space
      IMPORTING
        result                = cs_out-cornerlog
      EXCEPTIONS
        icon_not_found        = 1
        outputfield_too_short = 2
        OTHERS                = 3.
    IF sy-subrc NE 0.
      cs_out-cornerlog = icon_protocol.
    ENDIF.

    cs_out-stattext = lv_text.

    cs_out-request  = COND #( WHEN cs_out-requestpayload IS NOT INITIAL THEN icon_display ELSE icon_xml_doc ).
    cs_out-response = COND #( WHEN cs_out-responsepayload IS NOT INITIAL THEN icon_display ).

    cs_out-html = icon_url.

    CLEAR cs_out-styl.
    IF cs_out-messagetype EQ 'S'.
      cs_out-check = abap_false.
      cs_out-styl  = VALUE #( ( fieldname = 'CHECK' style = cl_gui_alv_grid=>mc_style_disabled ) ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Persistence: ZEINVOICE_DETAIL (status) / ZEINVOICE_ERROR (step log)
*----------------------------------------------------------------------*
  METHOD save_document.

    DATA(ls_detail) = VALUE zeinvoice_detail(
                        bukrs            = is_out-companycode
                        vbeln            = is_out-sapdocument
                        gjahr            = is_out-fiscalyear
                        type             = is_out-type
                        xblnr            = is_out-headerreference
                        msgty            = is_out-messagetype
                        dformat = COND #( WHEN is_out-requestformat IS NOT INITIAL THEN is_out-requestformat ELSE gc_format )
                        request_payload  = is_out-requestpayload
                        pstatus          = is_out-einvoicestatus
                        referenceid      = is_out-referenceid
                        response_payload = is_out-responsepayload
                        zzc1_status      = is_out-zzc1_status
                        zzc2_status      = is_out-zzc2_status
                        zzc3_sent_status = is_out-zzc3_sent_status
                        zzc3_ack_status  = is_out-zzc3_ack_status
                        zzc4_status      = is_out-zzc4_status
                        zzc5_rep_status  = is_out-zzc5_rep_status
                        zzc5_ack_status  = is_out-zzc5_ack_status
                        zzoverall_status = is_out-zzoverall_status ).
    MODIFY zeinvoice_detail FROM ls_detail.

    DELETE FROM zeinvoice_error WHERE bukrs EQ is_out-companycode AND
                                      vbeln EQ is_out-sapdocument AND
                                      gjahr EQ is_out-fiscalyear  AND
                                      type  EQ is_out-type.

    DATA lt_log TYPE STANDARD TABLE OF zeinvoice_error.
    LOOP AT gt_errors INTO DATA(ls_err) USING KEY doc WHERE bukrs EQ is_out-companycode AND
                                              vbeln EQ is_out-sapdocument AND
                                              gjahr EQ is_out-fiscalyear  AND
                                              type  EQ is_out-type.
      APPEND ls_err TO lt_log.
    ENDLOOP.
    IF lt_log IS NOT INITIAL.
      MODIFY zeinvoice_error FROM TABLE lt_log.
    ENDIF.

  ENDMETHOD.

  METHOD add_log.

    DATA: lv_code TYPE zecode,
          lv_cnt  TYPE i.

    lv_code = iv_code.
    IF iv_msgty EQ 'E' OR iv_msgty EQ 'W'.
      LOOP AT gt_errors TRANSPORTING NO FIELDS USING KEY doc WHERE bukrs EQ is_out-companycode AND
                                                     vbeln EQ is_out-sapdocument AND
                                                     gjahr EQ is_out-fiscalyear  AND
                                                     type  EQ is_out-type        AND
                                                     msgty EQ iv_msgty.
        lv_cnt = lv_cnt + 1.
      ENDLOOP.
      lv_cnt = lv_cnt + 1.
      lv_code = |{ iv_code }{ lv_cnt WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ENDIF.

    DATA(ls_err) = VALUE zeinvoice_error( bukrs   = is_out-companycode
                                          vbeln   = is_out-sapdocument
                                          gjahr   = is_out-fiscalyear
                                          type    = is_out-type
                                          msgty   = iv_msgty
                                          msgid   = gc_msgid
                                          msgno   = gc_msgno
                                          code    = lv_code
                                          message = iv_text ).
    "Update the existing log line (same key) or add a new one -
    "keyed access via secondary key DOC instead of a full table scan
    DATA(lv_found) = abap_false.
    LOOP AT gt_errors ASSIGNING FIELD-SYMBOL(<ls_old>) USING KEY doc
         WHERE bukrs = ls_err-bukrs AND vbeln = ls_err-vbeln AND gjahr = ls_err-gjahr AND
               type  = ls_err-type  AND msgty = ls_err-msgty AND msgid = ls_err-msgid AND
               msgno = ls_err-msgno AND code  = ls_err-code.
      <ls_old>-message = ls_err-message.   "key fields are identical
      lv_found = abap_true.
      EXIT.
    ENDLOOP.
    IF lv_found EQ abap_false.
      APPEND ls_err TO gt_errors.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
* ASP communication
*----------------------------------------------------------------------*
  METHOD get_token.

    DATA: ls_resp   TYPE ty_token_resp,
          lv_code   TYPE i,
          lv_reason TYPE string,
          lv_body   TYPE string.

    CLEAR ev_error.

    READ TABLE gt_tokens INTO DATA(ls_token) WITH KEY bukrs = iv_bukrs.
    IF sy-subrc EQ 0.
      rv_token = ls_token-token.
      RETURN.
    ENDIF.

    "Performance: the token is also kept in the shared buffer of the
    "application server until 2 minutes before it expires, so a new
    "cockpit session does not need a new token call at the ASP
    DATA: lv_buf_token TYPE string,
          lv_buf_exp   TYPE timestampl,
          lv_now       TYPE timestampl.
    DATA(lv_buf_id) = CONV indx_srtfd( |ZEINVTOK{ iv_bukrs }| ).
    GET TIME STAMP FIELD lv_now.
    TRY.
        IMPORT token = lv_buf_token expiry = lv_buf_exp
               FROM SHARED BUFFER indx(zt) ID lv_buf_id.
        IF sy-subrc EQ 0 AND lv_buf_token IS NOT INITIAL AND lv_buf_exp GT lv_now.
          rv_token = lv_buf_token.
          APPEND VALUE #( bukrs = iv_bukrs token = rv_token ) TO gt_tokens.
          RETURN.
        ENDIF.
      CATCH cx_root.
        "buffer not available - get a new token below
    ENDTRY.

    READ TABLE gt_apiurl INTO DATA(ls_api) WITH KEY direction = 'O' method = 'TOKEN'.
    IF sy-subrc NE 0.
      ev_error = |No TOKEN API maintained in ZEINVOICE_APIURL for direction O (Outbound)|.
      RETURN.
    ENDIF.

    IF ls_api-dformat EQ gc_format_json.
    "TaxLab: POST /api/external-auth/token, JSON body (client_credentials)
    DATA(lv_req) = json_builder( )->serialize( VALUE ty_j_token_req(
                                                 grant_type    = `client_credentials`
                                                 client_id     = ls_api-client_id
                                                 client_secret = ls_api-client_sid ) ).
    http_call( EXPORTING iv_url    = CONV #( ls_api-apiurl )
                         iv_method = 'POST'
                         is_api    = ls_api
                         iv_ctype  = `application/json`
                         iv_body   = lv_req
                         iv_ssl    = abap_false
               IMPORTING ev_code   = lv_code
                         ev_reason = lv_reason
                         ev_body   = lv_body ).
    IF lv_code NE 200 AND lv_code NE 201.
      DATA ls_terr TYPE ty_j_submit_resp.
      TRY.
          json_parser( )->deserialize( EXPORTING iv_json = lv_body CHANGING ca_data = ls_terr ).
        CATCH zcx_ei_json.
          CLEAR ls_terr.
      ENDTRY.
      ev_error = |HTTP { lv_code } { lv_reason } { ls_terr-message }|.
      RETURN.
    ENDIF.
    TRY.
        json_parser( )->deserialize( EXPORTING iv_json = lv_body CHANGING ca_data = ls_resp ).
      CATCH zcx_ei_json.
        CLEAR ls_resp.
    ENDTRY.
  ELSE.
    "Unchanged (XML ASP): form fields
    DATA(lt_form) = VALUE tihttpnvp( ( name = 'client_id'     value = ls_api-client_id )
                                     ( name = 'client_secret' value = ls_api-client_sid )
                                     ( name = 'grant_type'    value = 'client_credentials' ) ).

    http_call( EXPORTING iv_url    = CONV #( ls_api-apiurl )
                         iv_method = 'POST'
                         is_api    = ls_api
                         iv_ctype  = 'application/x-www-form-urlencoded'
                         it_form   = lt_form
                         iv_ssl    = abap_false
               IMPORTING ev_code   = lv_code
                         ev_reason = lv_reason
                         ev_body   = lv_body ).

    IF lv_code NE 200.
      ev_error = |HTTP { lv_code } { lv_reason }|.
      RETURN.
    ENDIF.

    TRY.
        cl_fdt_json=>json_to_data( EXPORTING iv_json = lv_body
                                   CHANGING  ca_data = ls_resp ).
      CATCH cx_root.
        CLEAR ls_resp.
    ENDTRY.
  ENDIF.

    rv_token = ls_resp-access_token.
    IF rv_token IS INITIAL.
      ev_error = |No access_token returned|.
      RETURN.
    ENDIF.

    APPEND VALUE #( bukrs = iv_bukrs token = rv_token ) TO gt_tokens.

    "Keep the token for later sessions (only when the ASP returns expires_in).
    "expires_in may be a lifetime in seconds or an absolute epoch time
    "(seconds or milliseconds) - 2 minutes safety margin in both cases
    TRY.
        DATA: lv_num   TYPE p LENGTH 16 DECIMALS 0,
              lv_epoch TYPE timestampl VALUE '19700101000000'.
        DATA(lv_exp_in) = condense( ls_resp-expires_in ).
        IF lv_exp_in IS NOT INITIAL AND lv_exp_in CO '0123456789'.
          lv_num = lv_exp_in.
          IF lv_num GT 100000000000.            "epoch milliseconds
            lv_num = lv_num DIV 1000.
          ENDIF.
          IF lv_num GT 1000000000.              "absolute epoch seconds
            lv_buf_exp = cl_abap_tstmp=>add( tstmp = lv_epoch secs = lv_num - 120 ).
          ELSE.                                 "lifetime in seconds
            lv_buf_exp = cl_abap_tstmp=>add( tstmp = lv_now secs = lv_num - 120 ).
          ENDIF.
          IF lv_buf_exp GT lv_now.
            EXPORT token = rv_token expiry = lv_buf_exp
                   TO SHARED BUFFER indx(zt) ID lv_buf_id.
          ENDIF.
        ENDIF.
      CATCH cx_root.
        "not buffered - next session gets a new token as before
    ENDTRY.

  ENDMETHOD.

  METHOD http_call.
    "Synchronous call = send + receive (unchanged behaviour)
    DATA lo_http TYPE REF TO if_http_client.

    CLEAR: ev_code, ev_reason, ev_body.
    http_send( EXPORTING iv_url    = iv_url
                         iv_method = iv_method
                         is_api    = is_api
                         iv_token  = iv_token
                         iv_ctype  = iv_ctype
                         iv_body   = iv_body
                         it_form   = it_form
                         iv_ssl    = iv_ssl
               IMPORTING eo_http   = lo_http
                         ev_reason = ev_reason ).
    CHECK lo_http IS BOUND.
    http_receive( EXPORTING io_http   = lo_http
                            iv_method = iv_method
                            iv_url    = iv_url
                  IMPORTING ev_code   = ev_code
                            ev_reason = ev_reason
                            ev_body   = ev_body ).
  ENDMETHOD.

  METHOD http_send.
    "Create the client and send the request - the answer is read with
    "http_receive, so several requests can be on their way at once
    DATA: lv_msg TYPE string,
          lv_rc  TYPE i.

    CLEAR: eo_http, ev_reason.

    IF iv_ssl EQ abap_true.
      cl_http_client=>create_by_url(
        EXPORTING
          url                = iv_url
          proxy_host         = CONV #( is_api-proxy_host )
          proxy_service      = CONV #( is_api-proxy_service )
          ssl_id             = 'ANONYM'
        IMPORTING
          client             = eo_http
        EXCEPTIONS
          argument_not_found = 1
          plugin_not_active  = 2
          internal_error     = 3
          OTHERS             = 4 ).
    ELSE.
      cl_http_client=>create_by_url(
        EXPORTING
          url                = iv_url
        IMPORTING
          client             = eo_http
        EXCEPTIONS
          argument_not_found = 1
          plugin_not_active  = 2
          internal_error     = 3
          OTHERS             = 4 ).
    ENDIF.
    IF sy-subrc NE 0 OR eo_http IS NOT BOUND.
      ev_reason = |HTTP client could not be created for { iv_url } (rc { sy-subrc })|.
      CLEAR eo_http.
      RETURN.
    ENDIF.

    eo_http->propertytype_logon_popup = if_http_client=>co_disabled.
    eo_http->request->set_method( iv_method ).
    "TaxLab (Postman): Accept: application/json - XML ASP unchanged
  eo_http->request->set_header_field(
    name  = 'Accept'
    value = COND #( WHEN json_mode( ) EQ abap_true AND iv_ctype CS 'json'
                    THEN `application/json` ELSE `*/*` ) ).

    IF iv_token IS NOT INITIAL.
      eo_http->request->set_header_field( name = 'Authorization' value = |Bearer { iv_token }| ).
    ENDIF.
    IF iv_ctype IS NOT INITIAL.
      eo_http->request->set_header_field( name = 'Content-Type' value = iv_ctype ).
      eo_http->request->set_content_type( iv_ctype ).
    ENDIF.
    IF it_form IS NOT INITIAL.
      eo_http->request->set_form_fields( it_form ).
    ENDIF.
    IF iv_body IS NOT INITIAL.
      eo_http->request->set_cdata( iv_body ).
    ENDIF.

    eo_http->send( EXPORTING  timeout                    = gc_http_timeout
                   EXCEPTIONS http_communication_failure = 1
                              http_invalid_state         = 2
                              http_processing_failed     = 3
                              http_invalid_timeout       = 4
                              OTHERS                     = 5 ).
    IF sy-subrc NE 0.
      eo_http->get_last_error( IMPORTING code    = lv_rc
                                         message = lv_msg ).
      ev_reason = |{ iv_method } { iv_url } failed (rc { lv_rc }): { lv_msg }|.
      eo_http->close( ).
      CLEAR eo_http.
    ENDIF.
  ENDMETHOD.

  METHOD http_receive.
    "Wait for the answer of a request sent with http_send
    DATA: lv_msg TYPE string,
          lv_rc  TYPE i.

    CLEAR: ev_code, ev_reason, ev_body.
    CHECK io_http IS BOUND.

    io_http->receive( EXCEPTIONS http_communication_failure = 1
                                 http_invalid_state         = 2
                                 http_processing_failed     = 3
                                 OTHERS                     = 4 ).
    IF sy-subrc NE 0.
      io_http->get_last_error( IMPORTING code    = lv_rc
                                         message = lv_msg ).
      ev_reason = |{ iv_method } { iv_url } failed (rc { lv_rc }): { lv_msg }|.
      io_http->close( ).
      RETURN.
    ENDIF.

    io_http->response->get_status( IMPORTING code   = ev_code
                                             reason = ev_reason ).
    ev_body = io_http->response->get_cdata( ).
    io_http->close( ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Helpers
*----------------------------------------------------------------------*
  METHOD map.
    DATA(lv_int) = lcl_xml=>str( iv_int ).
    DATA(lv_map) = CONV /aif/t_mvmapval5-vmapname( iv_map ).   "typed -> binary search on sorted key
    LOOP AT gt_mapping INTO DATA(ls_map) WHERE vmapname EQ lv_map.
      IF lcl_xml=>str( ls_map-int_value ) EQ lv_int.
        rv_ext = COND #( WHEN iv_ext2 EQ abap_true
                         THEN lcl_xml=>str( ls_map-ext_value2 )
                         ELSE lcl_xml=>str( ls_map-ext_value1 ) ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_mapped.
    DATA(lv_int) = lcl_xml=>str( iv_int ).
    DATA(lv_map) = CONV /aif/t_mvmapval5-vmapname( iv_map ).   "typed -> binary search on sorted key
    LOOP AT gt_mapping INTO DATA(ls_map) WHERE vmapname EQ lv_map.
      IF lcl_xml=>str( ls_map-int_value ) EQ lv_int.
        rv_bool = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD fmt_date.
    IF iv_date IS NOT INITIAL.
      rv_s = |{ iv_date+0(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    ENDIF.
  ENDMETHOD.

  METHOD fmt_time.
    rv_s = |{ iv_time+0(2) }:{ iv_time+2(2) }:{ iv_time+4(2) }|.
  ENDMETHOD.

  METHOD write_address.
    io_xml->open( iv_tag ).
    io_xml->elem( iv_tag = 'cbc:StreetName'           iv_val = iv_street ).
    io_xml->elem( iv_tag = 'cbc:AdditionalStreetName' iv_val = iv_street2 ).
    io_xml->elem( iv_tag = 'cbc:CityName'             iv_val = iv_city ).
    io_xml->elem( iv_tag = 'cbc:PostalZone'           iv_val = iv_postcode ).
    io_xml->elem( iv_tag = 'cbc:CountrySubentity'     iv_val = iv_region ).
    IF lcl_xml=>str( iv_line ) IS NOT INITIAL.
      io_xml->open( 'cac:AddressLine' ).
      io_xml->elem( iv_tag = 'cbc:Line' iv_val = iv_line ).
      io_xml->close( 'cac:AddressLine' ).
    ENDIF.
    io_xml->open( 'cac:Country' ).
    io_xml->elem( iv_tag = 'cbc:IdentificationCode' iv_val = iv_country iv_force = abap_true ).
    io_xml->close( 'cac:Country' ).
    io_xml->close( iv_tag ).
  ENDMETHOD.

  METHOD write_party.

    DATA: lv_agency TYPE string,
          lv_regno  TYPE string.

    io_xml->open( 'cac:Party' ).

    "Electronic address = TRN with scheme 0235 (as in ZEI_PROCESS_COCKPIT)
    io_xml->elem( iv_tag   = 'cbc:EndpointID'
                  iv_val   = iv_vat
                  iv_attr  = lcl_xml=>attr( iv_name = 'schemeID' iv_val = gc_scheme_tin )
                  iv_force = abap_true ).

    io_xml->open( 'cac:PartyName' ).
    io_xml->elem( iv_tag = 'cbc:Name' iv_val = iv_name iv_force = abap_true ).
    io_xml->close( 'cac:PartyName' ).

    write_address( io_xml      = io_xml
                   iv_tag      = 'cac:PostalAddress'
                   iv_street   = iv_street
                   iv_street2  = iv_street2
                   iv_city     = iv_city
                   iv_postcode = iv_postcode
                   iv_region   = iv_region
                   iv_country  = iv_country ).

    io_xml->open( 'cac:PartyTaxScheme' ).
    io_xml->elem( iv_tag = 'cbc:CompanyID' iv_val = iv_vat iv_force = abap_true ).
    io_xml->open( 'cac:TaxScheme' ).
    io_xml->elem( iv_tag = 'cbc:ID' iv_val = 'VAT' ).
    io_xml->close( 'cac:TaxScheme' ).
    io_xml->close( 'cac:PartyTaxScheme' ).

    io_xml->open( 'cac:PartyLegalEntity' ).
    io_xml->elem( iv_tag = 'cbc:RegistrationName' iv_val = iv_name iv_force = abap_true ).
    DATA(lv_legal) = lcl_xml=>str( iv_legalid ).
    SPLIT lv_legal AT ':' INTO lv_agency lv_regno.
    IF lv_regno IS NOT INITIAL.
      io_xml->elem( iv_tag  = 'cbc:CompanyID'
                    iv_val  = lv_regno
                    iv_attr = lcl_xml=>attr( iv_name = 'schemeAgencyID' iv_val = lv_agency ) &&
                              lcl_xml=>attr( iv_name = 'schemeAgencyName'
                                             iv_val  = SWITCH string( lv_agency
                                                                      WHEN 'TL'  THEN 'Trade License issuing Authority'
                                                                      WHEN 'PAS' THEN 'Passport issuing Authority'
                                                                      ELSE '' ) ) ).
    ENDIF.
    io_xml->close( 'cac:PartyLegalEntity' ).

    io_xml->close( 'cac:Party' ).

  ENDMETHOD.

  METHOD write_taxcat.
    io_xml->open( iv_tag ).
    io_xml->elem( iv_tag = 'cbc:ID'      iv_val = iv_taxcode iv_force = abap_true ).
    io_xml->elem( iv_tag = 'cbc:Percent' iv_val = iv_percent iv_force = abap_true ).
    io_xml->open( 'cac:TaxScheme' ).
    io_xml->elem( iv_tag = 'cbc:ID' iv_val = 'VAT' ).
    io_xml->close( 'cac:TaxScheme' ).
    io_xml->close( iv_tag ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* PINT AE XML (SBDH + UBL 2.1 Invoice / CreditNote) - built dynamically
*----------------------------------------------------------------------*
  METHOD build_xml.

    DATA: lt_tax     TYPE tt_taxsum,
          lv_allow   TYPE vfprc_element_value,
          lv_charge  TYPE vfprc_element_value,
          lv_taxamt  TYPE vfprc_element_value,
          lv_value   TYPE vfprc_element_value,
          lv_absval  TYPE vfprc_element_value,
          ls_hdrtax  TYPE zi_einvoice_conditions,
          ls_itemtax TYPE zi_einvoice_conditions,
          lv_uuid    TYPE string,
          lv_origdoc TYPE vbeln_vf.

    DATA(lv_typecode) = is_out-einvoicetype.
    CHECK lv_typecode IS NOT INITIAL.
    DATA(lv_doctype) = SWITCH #( lv_typecode
                                 WHEN '381' THEN 'CreditNote'
                                 WHEN '380' THEN 'Invoice'
                               ).

    DATA(lv_cn) = xsdbool( lv_typecode EQ '381' OR lv_doctype EQ 'CreditNote' ).
    IF lv_doctype IS INITIAL.
      lv_doctype = COND #( WHEN lv_cn EQ abap_true THEN 'CreditNote' ELSE 'Invoice' ).
    ENDIF.

    DATA(lv_root)    = COND string( WHEN lv_cn EQ abap_true THEN 'CreditNote'           ELSE 'doc:Invoice' ).
    DATA(lv_linetag) = COND string( WHEN lv_cn EQ abap_true THEN 'cac:CreditNoteLine'   ELSE 'cac:InvoiceLine' ).
    DATA(lv_qtytag)  = COND string( WHEN lv_cn EQ abap_true THEN 'cbc:CreditedQuantity' ELSE 'cbc:InvoicedQuantity' ).
    DATA(lv_cur)     = lcl_xml=>str( is_out-currency ).
    DATA(lv_docid)   = lcl_xml=>str( is_out-sapdocument ).
    "Invoice number used in cbc:ID, cbc:PaymentID and SBDH InstanceIdentifier
    DATA(lv_invno)   = |{ is_out-supplierpeppolid }-{ is_out-companycode }-{ lv_docid }-{ is_out-fiscalyear }|.

    "Tax summary per tax code + header level allowances / charges
    LOOP AT gt_prcd INTO DATA(ls_prcd) WHERE conditionno EQ is_out-conditionno.

      IF ls_prcd-accountkey     EQ 'MWS' AND
         ls_prcd-conditionclass EQ 'D'   AND
         ls_prcd-taxcode        IS NOT INITIAL.
        COLLECT VALUE ty_taxsum( taxcode   = ls_prcd-taxcode
                                 taxrate   = ls_prcd-taxrate
                                 eitaxtype = ls_prcd-einvoicetaxtype
                                 base      = ls_prcd-baseamount
                                 amount    = ls_prcd-value ) INTO lt_tax.
        lv_taxamt = lv_taxamt + ls_prcd-value.
        IF ls_hdrtax IS INITIAL.
          ls_hdrtax = ls_prcd.
        ENDIF.
      ENDIF.

      IF   ls_prcd-item  IS INITIAL     AND
           ls_prcd-value IS NOT INITIAL AND
         ( ls_prcd-allowancetype EQ 'A' OR
           ls_prcd-allowancetype EQ 'C' ).
        IF ls_prcd-value GT 0.
          lv_charge = lv_charge + ls_prcd-value.
        ELSE.
          lv_allow = lv_allow - ls_prcd-value.
        ENDIF.
      ENDIF.

    ENDLOOP.

    DATA(lo) = NEW lcl_xml( ).

    "=== Standard Business Document Header ===
    lo->open( iv_tag  = 'StandardBusinessDocument'
              iv_attr = lcl_xml=>attr( iv_name = 'xmlns'     iv_val = gc_ns_sbdh ) &&
                        lcl_xml=>attr( iv_name = 'xmlns:xsi' iv_val = gc_ns_xsi ) &&
                        lcl_xml=>attr( iv_name = 'xsi:schemaLocation' iv_val = |{ gc_ns_sbdh } { gc_sbdh_xsd }| ) ).
    lo->open( 'StandardBusinessDocumentHeader' ).
    lo->elem( iv_tag = 'HeaderVersion' iv_val = '1.0' ).
    lo->open( 'Sender' ).
    lo->elem( iv_tag = 'Identifier' iv_val = is_out-supplierpeppolid iv_force = abap_true
              iv_attr = lcl_xml=>attr( iv_name = 'Authority' iv_val = gc_authority ) ).
    lo->close( 'Sender' ).
    lo->open( 'Receiver' ).
    lo->elem( iv_tag = 'Identifier' iv_val = is_out-customerpeppolid iv_force = abap_true
              iv_attr = lcl_xml=>attr( iv_name = 'Authority' iv_val = gc_authority ) ).
    lo->close( 'Receiver' ).
    lo->open( 'DocumentIdentification' ).
    lo->elem( iv_tag = 'Standard'            iv_val = |urn:oasis:names:specification:ubl:schema:xsd:{ lv_doctype }-2| ).
    lo->elem( iv_tag = 'TypeVersion'         iv_val = '2.1' ).
    lo->elem( iv_tag = 'InstanceIdentifier'  iv_val = lv_invno ).
    lo->elem( iv_tag = 'Type'                iv_val = lv_doctype ).
    lo->elem( iv_tag = 'CreationDateAndTime' iv_val = |{ fmt_date( is_out-creationdate ) }T{ fmt_time( is_out-creationtime ) }| ).
    lo->close( 'DocumentIdentification' ).

    TYPES: BEGIN OF ty_scope,
             type  TYPE string,
             inst  TYPE string,
             ident TYPE string,
           END OF ty_scope,
           tt_scope TYPE STANDARD TABLE OF ty_scope WITH DEFAULT KEY.
    DATA(lt_scope) = VALUE tt_scope(
      ( type = 'DOCUMENTID' ident = 'peppol-doctype-wildcard'
        inst = |urn:oasis:names:specification:ubl:schema:xsd:{ lv_doctype }-2::{ lv_doctype }##{ gc_custid }::2.1| )
      ( type = 'PROCESSID'  inst = gc_profile ident = 'cenbii-procid-ubl' )
      ( type = 'COUNTRY_C1' inst = 'AE' )
      ( type = 'MLS_TO'     inst = is_out-supplieraspid ident = gc_authority )
      ( type = 'MLS_TYPE'   inst = 'ALWAYS_SEND' ) ).
    lo->open( 'BusinessScope' ).
    LOOP AT lt_scope INTO DATA(ls_scope).
      lo->open( 'Scope' ).
      lo->elem( iv_tag = 'Type'               iv_val = ls_scope-type ).
      lo->elem( iv_tag = 'InstanceIdentifier' iv_val = ls_scope-inst ).
      lo->elem( iv_tag = 'Identifier'         iv_val = ls_scope-ident ).
      lo->close( 'Scope' ).
    ENDLOOP.
    lo->close( 'BusinessScope' ).
    lo->close( 'StandardBusinessDocumentHeader' ).

    "=== UBL document ===
    IF lv_cn EQ abap_true.
      lo->open( iv_tag  = lv_root
                iv_attr = lcl_xml=>attr( iv_name = 'xmlns'     iv_val = gc_ns_cn ) &&
                          lcl_xml=>attr( iv_name = 'xmlns:cac' iv_val = gc_ns_cac ) &&
                          lcl_xml=>attr( iv_name = 'xmlns:cbc' iv_val = gc_ns_cbc ) ).
    ELSE.
      lo->open( iv_tag  = lv_root
                iv_attr = lcl_xml=>attr( iv_name = 'xmlns:doc' iv_val = gc_ns_inv ) &&
                          lcl_xml=>attr( iv_name = 'xmlns:cbc' iv_val = gc_ns_cbc ) &&
                          lcl_xml=>attr( iv_name = 'xmlns:cac' iv_val = gc_ns_cac ) &&
                          lcl_xml=>attr( iv_name = 'xsi:schemaLocation' iv_val = |{ gc_ns_inv } { gc_inv_xsd }| ) ).
    ENDIF.

    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_c36_static( ).
      CATCH cx_uuid_error.
        CLEAR lv_uuid.
    ENDTRY.

    lo->elem( iv_tag = 'cbc:CustomizationID'    iv_val = gc_custid ).
    lo->elem( iv_tag = 'cbc:ProfileID'          iv_val = gc_profile ).
    lo->elem( iv_tag = 'cbc:ProfileExecutionID' iv_val = '00000000' ).
    lo->elem( iv_tag = 'cbc:ID'                 iv_val = lv_invno ).
    lo->elem( iv_tag = 'cbc:UUID'               iv_val = to_lower( lv_uuid ) ).
    lo->elem( iv_tag = 'cbc:IssueDate'          iv_val = fmt_date( is_out-creationdate ) ).
    IF lv_cn EQ abap_false.
      lo->elem( iv_tag = 'cbc:DueDate'         iv_val = fmt_date( is_out-billingdate ) ).
      lo->elem( iv_tag = 'cbc:InvoiceTypeCode' iv_val = lv_typecode ).
    ELSE.
      lo->elem( iv_tag = 'cbc:CreditNoteTypeCode' iv_val = lv_typecode ).
    ENDIF.
    lo->elem( iv_tag = 'cbc:Note'                 iv_val = |This is { lv_doctype }| ).
    lo->elem( iv_tag = 'cbc:DocumentCurrencyCode' iv_val = lv_cur ).

    IF lv_cn EQ abap_false.
      DATA(lv_from) = COND d( WHEN is_out-billingdate IS NOT INITIAL AND is_out-billingdate LT is_out-creationdate
                              THEN is_out-billingdate ELSE is_out-creationdate ).
      DATA(lv_to)   = COND d( WHEN is_out-billingdate GT is_out-creationdate
                              THEN is_out-billingdate ELSE is_out-creationdate ).
      lo->open( 'cac:InvoicePeriod' ).
      lo->elem( iv_tag = 'cbc:StartDate' iv_val = fmt_date( lv_from ) ).
      lo->elem( iv_tag = 'cbc:EndDate'   iv_val = fmt_date( lv_to ) ).
      lo->close( 'cac:InvoicePeriod' ).
    ELSE.
      lo->open( 'cac:DiscrepancyResponse' ).
      lo->elem( iv_tag = 'cbc:ResponseCode' iv_val = is_out-einvoicecreditnotereason ).
      lo->close( 'cac:DiscrepancyResponse' ).
    ENDIF.

    IF is_out-salesdocument IS NOT INITIAL.
      lo->open( 'cac:OrderReference' ).
      lo->elem( iv_tag = 'cbc:ID'           iv_val = is_out-customerreference ).
      lo->elem( iv_tag = 'cbc:SalesOrderID' iv_val = is_out-salesdocument ).
      lo->close( 'cac:OrderReference' ).
    ENDIF.

    "Credit note -> preceding invoice (VBRK-XBLNR) via ZI_EINVOICE_HEADER
    IF lv_cn EQ abap_true AND is_out-headerreference IS NOT INITIAL.
      lo->open( 'cac:BillingReference' ).
      lo->open( 'cac:InvoiceDocumentReference' ).
      lo->elem( iv_tag = 'cbc:ID'        iv_val = |{ is_out-OriginalCompanyCode }-{ is_out-OriginalDocument }-{ is_out-OriginalFiscalYear }| ).
      lo->elem( iv_tag = 'cbc:IssueDate' iv_val = fmt_date( is_out-OriginalCreationDate ) ).
      lo->close( 'cac:InvoiceDocumentReference' ).
      lo->close( 'cac:BillingReference' ).
    ENDIF.

    "Supplier (seller)
    lo->open( 'cac:AccountingSupplierParty' ).
    write_party( io_xml      = lo
                 iv_vat      = is_out-suppliervatregistrationcode
                 iv_name     = is_out-suppliername
                 iv_street   = is_out-supplierstreetname
                 iv_street2  = is_out-supplieradditionalstreetname
                 iv_city     = is_out-suppliercityname
                 iv_postcode = is_out-supplierpostalcode
                 iv_region   = is_out-supplierregion
                 iv_country  = is_out-suppliercountry
                 iv_legalid  = is_out-supplierlegalregistrationid
                 iv_peppol   = is_out-supplierpeppolid ).
    lo->close( 'cac:AccountingSupplierParty' ).

    "Customer (buyer)
    lo->open( 'cac:AccountingCustomerParty' ).
    write_party( io_xml      = lo
                 iv_vat      = is_out-customervatregistrationcode
                 iv_name     = is_out-customername
                 iv_street   = is_out-customerstreetname
                 iv_street2  = is_out-customeradditionalstreetname
                 iv_city     = is_out-customercityname
                 iv_postcode = is_out-customerpostalcode
                 iv_region   = is_out-customerregion
                 iv_country  = is_out-customercountry
                 iv_legalid  = is_out-customerlegalregistrationid
                 iv_peppol   = is_out-customerpeppolid ).
    lo->close( 'cac:AccountingCustomerParty' ).

    "Delivery (ship-to)
    IF is_out-shiptoname IS NOT INITIAL.
      lo->open( 'cac:Delivery' ).
      lo->elem( iv_tag = 'cbc:ActualDeliveryDate' iv_val = fmt_date( is_out-billingdate ) ).
      lo->open( 'cac:DeliveryLocation' ).
      lo->elem( iv_tag  = 'cbc:ID' iv_val = is_out-shiptovatregistrationcode
                iv_attr = lcl_xml=>attr( iv_name = 'schemeID' iv_val = gc_scheme_tin ) ).
      write_address( io_xml      = lo
                     iv_tag      = 'cac:Address'
                     iv_street   = is_out-shiptostreetname
                     iv_street2  = is_out-shiptoadditionalstreetname
                     iv_city     = is_out-shiptocityname
                     iv_postcode = is_out-shiptopostalcode
                     iv_region   = is_out-shiptoregion
                     iv_country  = is_out-shiptocountry
                     iv_line     = is_out-shiptoadditionalstreetname ).
      lo->close( 'cac:DeliveryLocation' ).
      lo->open( 'cac:DeliveryParty' ).
      lo->open( 'cac:PartyName' ).
      lo->elem( iv_tag = 'cbc:Name' iv_val = is_out-shiptoname ).
      lo->close( 'cac:PartyName' ).
      lo->close( 'cac:DeliveryParty' ).
      lo->close( 'cac:Delivery' ).
    ENDIF.

    "Payment means (invoice) - credit transfer
    IF lv_cn EQ abap_false.

      IF is_out-einvoicepaymentmethod IS NOT INITIAL.
        DATA(lv_pmethod) = is_out-einvoicepaymentmethod.
        DATA(lv_pmname)  = is_out-einvoicepaymentmethodname.
      ELSEIF is_out-CustomerPaymentMethod IS NOT INITIAL.
        lv_pmethod = is_out-CustomerPaymentMethod.
        lv_pmname  = is_out-CustomerPaymentMethodName.
      ELSE.
        lv_pmethod = is_out-SupplierPaymentMethod.
        lv_pmname  = is_out-SupplierPaymentMethodName.
      ENDIF.

      IF is_out-iban IS NOT INITIAL.
        DATA(lv_iban)  = is_out-iban.
        DATA(lv_accnm) = is_out-accountname.
        DATA(lv_bic)   = is_out-swiftcode.
      ELSEIF is_out-customeriban IS NOT INITIAL.
        lv_iban  = is_out-customeriban.
        lv_accnm = is_out-customeraccountname.
        lv_bic   = is_out-customerswiftcode.
      ELSEIF is_out-supplieriban IS NOT INITIAL.
        lv_iban  = is_out-supplieriban.
        lv_accnm = is_out-supplieraccountname.
        lv_bic   = is_out-supplierswiftcode.
      ENDIF.

      lo->open( 'cac:PaymentMeans' ).
      lo->elem( iv_tag  = 'cbc:PaymentMeansCode' iv_val = lv_pmethod
                iv_attr = lcl_xml=>attr( iv_name = 'name' iv_val = lv_pmname ) ).
      lo->elem( iv_tag = 'cbc:PaymentID' iv_val = lv_invno ).
      lo->open( 'cac:PayeeFinancialAccount' ).
      lo->elem( iv_tag = 'cbc:ID'   iv_val = lv_iban ).
      lo->elem( iv_tag = 'cbc:Name' iv_val = lv_accnm ).
      lo->open( 'cac:FinancialInstitutionBranch' ).
      lo->elem( iv_tag = 'cbc:ID' iv_val = lv_bic ).
      lo->close( 'cac:FinancialInstitutionBranch' ).
      lo->close( 'cac:PayeeFinancialAccount' ).
      lo->close( 'cac:PaymentMeans' ).
    ENDIF.

    IF is_out-paymentterms IS NOT INITIAL.
      lo->open( 'cac:PaymentTerms' ).
      lo->elem( iv_tag = 'cbc:Note' iv_val = is_out-paymentterms ).
      lo->close( 'cac:PaymentTerms' ).
    ENDIF.

    "Document level allowances / charges
    LOOP AT gt_prcd INTO ls_prcd WHERE   conditionno EQ is_out-conditionno AND
                                         item        IS INITIAL            AND
                                         value       IS NOT INITIAL        AND
                                       ( allowancetype EQ 'A'              OR
                                         allowancetype EQ 'C' ).
      lv_absval = abs( ls_prcd-value ).
      lo->open( 'cac:AllowanceCharge' ).
      lo->elem( iv_tag = 'cbc:ChargeIndicator'           iv_val = COND string( WHEN ls_prcd-value GT 0 THEN 'true' ELSE 'false' ) ).
      lo->elem( iv_tag = 'cbc:AllowanceChargeReasonCode' iv_val = ls_prcd-allowancecode ).
      lo->elem( iv_tag = 'cbc:AllowanceChargeReason'     iv_val = ls_prcd-allowancename ).
      IF ls_prcd-calculationtype EQ 'A'.
        lo->elem( iv_tag = 'cbc:MultiplierFactorNumeric' iv_val = lcl_xml=>num( abs( ls_prcd-amount ) ) ).
      ENDIF.
      lo->amt( iv_tag = 'cbc:Amount' iv_val = lv_absval iv_cur = lv_cur ).
      IF ls_prcd-calculationtype EQ 'A'.
        lo->amt( iv_tag = 'cbc:BaseAmount' iv_val = ls_prcd-baseamount iv_cur = lv_cur ).
      ENDIF.
      write_taxcat( io_xml = lo iv_tag = 'cac:TaxCategory' iv_taxcode = ls_hdrtax-einvoicetaxtype iv_percent = ls_hdrtax-taxrate ).
      lo->close( 'cac:AllowanceCharge' ).
    ENDLOOP.

    "Tax total
    lo->open( 'cac:TaxTotal' ).
    lo->amt( iv_tag = 'cbc:TaxAmount' iv_val = lv_taxamt iv_cur = lv_cur ).
    LOOP AT lt_tax INTO DATA(ls_tax).
      lo->open( 'cac:TaxSubtotal' ).
      lo->amt( iv_tag = 'cbc:TaxableAmount' iv_val = ls_tax-base   iv_cur = lv_cur ).
      lo->amt( iv_tag = 'cbc:TaxAmount'     iv_val = ls_tax-amount iv_cur = lv_cur ).
      write_taxcat( io_xml = lo iv_tag = 'cac:TaxCategory' iv_taxcode = ls_tax-eitaxtype iv_percent = ls_tax-taxrate ).
      lo->close( 'cac:TaxSubtotal' ).
    ENDLOOP.
    lo->close( 'cac:TaxTotal' ).

    "Legal monetary total
    lv_value = is_out-netvalue + lv_allow - lv_charge.
    lo->open( 'cac:LegalMonetaryTotal' ).
    lo->amt( iv_tag = 'cbc:LineExtensionAmount'  iv_val = lv_value          iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:TaxExclusiveAmount'   iv_val = is_out-netvalue   iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:TaxInclusiveAmount'   iv_val = is_out-totalvalue iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:AllowanceTotalAmount' iv_val = lv_allow          iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:ChargeTotalAmount'    iv_val = lv_charge         iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:PrepaidAmount'        iv_val = 0                 iv_cur = lv_cur ).
    lo->amt( iv_tag = 'cbc:PayableAmount'        iv_val = is_out-totalvalue iv_cur = lv_cur ).
    lo->close( 'cac:LegalMonetaryTotal' ).

    "Lines
    LOOP AT gt_items INTO DATA(ls_item)
                     WHERE companycode EQ is_out-companycode AND
                           sapdocument EQ is_out-sapdocument AND
                           fiscalyear  EQ is_out-fiscalyear.

      CLEAR: ls_itemtax.
      LOOP AT gt_prcd INTO ls_prcd WHERE conditionno    EQ is_out-conditionno AND
                                         item           EQ ls_item-sapdocitem AND
                                         accountkey     EQ 'MWS'              AND
                                         conditionclass EQ 'D'                AND
                                         taxcode        IS NOT INITIAL.
        ls_itemtax = ls_prcd.
        EXIT.
      ENDLOOP.
      IF ls_itemtax IS INITIAL.
        ls_itemtax = ls_hdrtax.
      ENDIF.

      lo->open( lv_linetag ).
      lo->elem( iv_tag = 'cbc:ID' iv_val = ls_item-sapdocitem ).
      lo->elem( iv_tag   = lv_qtytag
                iv_val   = lcl_xml=>qty( ls_item-quantity )
                iv_attr  = lcl_xml=>attr( iv_name = 'unitCode' iv_val = ls_item-einvoiceunit )
                iv_force = abap_true ).
      lo->amt( iv_tag = 'cbc:LineExtensionAmount' iv_val = ls_item-netvalue iv_cur = lv_cur ).

      IF ls_item-salesorderitem IS NOT INITIAL.
        lo->open( 'cac:OrderLineReference' ).
        lo->elem( iv_tag = 'cbc:LineID' iv_val = ls_item-salesorderitem ).
        lo->close( 'cac:OrderLineReference' ).
      ENDIF.
      IF ls_item-salesorder IS NOT INITIAL.
        lo->open( 'cac:DocumentReference' ).
        lo->elem( iv_tag  = 'cbc:ID' iv_val = ls_item-salesorder
                  iv_attr = lcl_xml=>attr( iv_name = 'schemeID' iv_val = 'AWV' ) ).
        lo->close( 'cac:DocumentReference' ).
      ENDIF.

      "Line level allowances / charges
      LOOP AT gt_prcd INTO ls_prcd WHERE   conditionno EQ is_out-conditionno AND
                                           item        EQ ls_item-sapdocitem AND
                                           value       IS NOT INITIAL        AND
                                         ( allowancetype EQ 'A'              OR
                                           allowancetype EQ 'C' ).
        lv_absval = abs( ls_prcd-value ).
        lo->open( 'cac:AllowanceCharge' ).
        lo->elem( iv_tag = 'cbc:ChargeIndicator'           iv_val = COND string( WHEN ls_prcd-value GT 0 THEN 'true' ELSE 'false' ) ).
        lo->elem( iv_tag = 'cbc:AllowanceChargeReasonCode' iv_val = ls_prcd-allowancecode ).
        lo->elem( iv_tag = 'cbc:AllowanceChargeReason'     iv_val = ls_prcd-allowancename ).
        IF ls_prcd-calculationtype EQ 'A'.
          lo->elem( iv_tag = 'cbc:MultiplierFactorNumeric' iv_val = lcl_xml=>num( abs( ls_prcd-amount ) ) ).
        ENDIF.
        lo->amt( iv_tag = 'cbc:Amount' iv_val = lv_absval iv_cur = lv_cur ).
        IF ls_prcd-calculationtype EQ 'A'.
          lo->amt( iv_tag = 'cbc:BaseAmount' iv_val = ls_prcd-baseamount iv_cur = lv_cur ).
        ENDIF.
        lo->close( 'cac:AllowanceCharge' ).
      ENDLOOP.

      "Item
      lo->open( 'cac:Item' ).
      lo->elem( iv_tag = 'cbc:Description' iv_val = ls_item-materialdescription ).
      lo->elem( iv_tag = 'cbc:Name'        iv_val = ls_item-materialdescription iv_force = abap_true ).
      lo->open( 'cac:BuyersItemIdentification' ).
      lo->elem( iv_tag = 'cbc:ID' iv_val = ls_item-material ).
      lo->close( 'cac:BuyersItemIdentification' ).
      lo->open( 'cac:SellersItemIdentification' ).
      lo->elem( iv_tag = 'cbc:ID' iv_val = ls_item-material ).
      lo->close( 'cac:SellersItemIdentification' ).
      lo->open( 'cac:StandardItemIdentification' ).
      lo->elem( iv_tag  = 'cbc:ID' iv_val = ls_item-material
                iv_attr = lcl_xml=>attr( iv_name = 'schemeID' iv_val = '0088' ) ).
      lo->close( 'cac:StandardItemIdentification' ).
      IF ls_item-origincountry IS NOT INITIAL.
        lo->open( 'cac:OriginCountry' ).
        lo->elem( iv_tag = 'cbc:IdentificationCode' iv_val = ls_item-origincountry ).
        lo->close( 'cac:OriginCountry' ).
      ENDIF.
      write_taxcat( io_xml = lo iv_tag = 'cac:ClassifiedTaxCategory' iv_taxcode = ls_itemtax-einvoicetaxtype iv_percent = ls_itemtax-taxrate ).
      lo->close( 'cac:Item' ).

      "Price (gross price condition PPR0 / ZPR1)
      CLEAR lv_value.
      DATA(lv_puom) = ls_item-einvoiceunit.
      LOOP AT gt_prcd INTO ls_prcd WHERE conditionno   EQ is_out-conditionno AND
                                         item          EQ ls_item-sapdocitem AND
                                       ( conditiontype EQ 'PPR0'             OR
                                         conditiontype EQ 'ZPR1' ).
        lv_value = ls_prcd-value.
        IF ls_prcd-conditionunit IS NOT INITIAL.
          lv_puom = ls_prcd-einvoiceunit.
        ENDIF.
        EXIT.
      ENDLOOP.

      lo->open( 'cac:Price' ).
      lo->amt( iv_tag = 'cbc:PriceAmount' iv_val = lv_value iv_cur = lv_cur ).
      lo->elem( iv_tag   = 'cbc:BaseQuantity'
                iv_val   = lcl_xml=>qty( ls_item-quantity )
                iv_attr  = lcl_xml=>attr( iv_name = 'unitCode' iv_val = lv_puom )
                iv_force = abap_true ).
      lo->open( 'cac:AllowanceCharge' ).
      lo->elem( iv_tag = 'cbc:ChargeIndicator' iv_val = 'false' ).
      lo->amt( iv_tag = 'cbc:Amount'     iv_val = 0        iv_cur = lv_cur ).
      lo->amt( iv_tag = 'cbc:BaseAmount' iv_val = lv_value iv_cur = lv_cur ).
      lo->close( 'cac:AllowanceCharge' ).
      lo->close( 'cac:Price' ).

      "UAE extension: line amount incl. VAT and line VAT amount
      lo->open( 'cac:ItemPriceExtension' ).
      lo->amt( iv_tag = 'cbc:Amount' iv_val = ls_item-totalvalue iv_cur = lv_cur ).
      lo->open( 'cac:TaxTotal' ).
      lo->amt( iv_tag = 'cbc:TaxAmount' iv_val = ls_item-taxvalue iv_cur = lv_cur ).
      lo->close( 'cac:TaxTotal' ).
      lo->close( 'cac:ItemPriceExtension' ).

      lo->close( lv_linetag ).

    ENDLOOP.

    lo->close( lv_root ).
    lo->close( 'StandardBusinessDocument' ).

    rv_xml = lo->mv_xml.

  ENDMETHOD.


*----------------------------------------------------------------------*
* HTML preview of the PINT AE XML (parsed dynamically with iXML)
*----------------------------------------------------------------------*

*----------------------------------------------------------------------*
* TaxLab JSON - switch, builder, parser
*----------------------------------------------------------------------*
  METHOD json_mode.
    "Switch: ZEINVOICE_APIURL direction O / method POST / DFORMAT = JSON
    READ TABLE gt_apiurl INTO DATA(ls_api) WITH KEY direction = 'O' method = 'POST'.
    rv = xsdbool( sy-subrc EQ 0 AND ls_api-dformat EQ gc_format_json ).
  ENDMETHOD.

  METHOD is_json.
    "Format the document was generated in; not yet generated -> switch
    rv = xsdbool( is_out-requestformat EQ gc_format_json OR
                  ( is_out-requestformat IS INITIAL AND json_mode( ) EQ abap_true ) ).
  ENDMETHOD.

  METHOD json_name_map.
    "JSON keys that are longer than an ABAP component name (30)
    rt = VALUE #(
      ( abap = `LINE_EXT_AMT_CUR`     json = `line_extension_amount_currency_code` )
      ( abap = `TAX_EXCL_AMT_CUR`     json = `tax_exclusive_amount_currency_code` )
      ( abap = `TAX_INCL_AMT_CUR`     json = `tax_inclusive_amount_currency_code` )
      ( abap = `ALLOW_TOTAL_AMT_CUR`  json = `allowance_total_amount_currency_code` )
      ( abap = `CHARGE_TOTAL_AMT_CUR` json = `charge_total_amount_currency_code` ) ).
  ENDMETHOD.

  METHOD json_builder.
    IF go_json IS NOT BOUND.
      go_json = NEW zcl_ei_json_builder(
        is_options  = VALUE #( name_case         = zcl_ei_json_builder=>co_case-snake
                               skip_initial      = abap_true
                               pretty            = abap_false   "compact for sending
                               trim_decimals     = abap_true
                               escape_slash      = abap_true
                               null_initial_date = abap_true )
        it_name_map = json_name_map( )
        "Mandatory (Postman 'Required = Yes') or amounts that are sent
        "even when 0 - as the XML did (lcl_xml->amt always forced)
        it_always   = VALUE #( ( `INVOICE_NUMBER` ) ( `ISSUE_DATE` ) ( `INVOICE_TYPE_CODE` )
                               ( `CURRENCY_CODE` ) ( `ENDPOINT_ID` ) ( `ENDPOINT_SCHEME_ID` )
                               ( `REGISTRATION_NAME` ) ( `IDENTIFICATION_CODE` )
                               ( `TAX_AMOUNT` ) ( `TAXABLE_AMOUNT` ) ( `PERCENT` )
                               ( `LINE_EXTENSION_AMOUNT` ) ( `TAX_EXCLUSIVE_AMOUNT` )
                               ( `TAX_INCLUSIVE_AMOUNT` ) ( `ALLOWANCE_TOTAL_AMOUNT` )
                               ( `CHARGE_TOTAL_AMOUNT` ) ( `PREPAID_AMOUNT` ) ( `PAYABLE_AMOUNT` )
                               ( `INVOICED_QUANTITY` ) ( `AMOUNT` ) ( `GROSS_PRICE` )
                               ( `DOCUMENTS-INVOICE_LINE-ITEM-NAME` ) ) ).
    ENDIF.
    ro = go_json.
  ENDMETHOD.

  METHOD json_parser.
    ro = NEW zcl_ei_json_parser( it_name_map = json_name_map( ) ).
  ENDMETHOD.

  METHOD preview_payload.
    IF json_mode( ) EQ abap_true.
      "same data load as PREVIEW_XML
      DATA(lt_backup) = gt_output.
      LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
        <ls_out>-check = xsdbool( <ls_out>-companycode EQ is_out-companycode AND
                                  <ls_out>-sapdocument EQ is_out-sapdocument AND
                                  <ls_out>-fiscalyear  EQ is_out-fiscalyear ).
      ENDLOOP.
      load_process_data( ).
      READ TABLE gt_output INTO DATA(ls_cur)
           WITH KEY companycode = is_out-companycode
                    sapdocument = is_out-sapdocument
                    fiscalyear  = is_out-fiscalyear.
      IF sy-subrc EQ 0.
        rv = build_json( ls_cur ).
      ENDIF.
      gt_output = lt_backup.
    ELSE.
      rv = preview_xml( is_out ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* TaxLab JSON request - same data sources as BUILD_XML
*----------------------------------------------------------------------*
  METHOD json_address.
    rs = VALUE #( street_name            = lcl_xml=>str( iv_street )
                  additional_street_name = lcl_xml=>str( iv_street2 )
                  city_name              = lcl_xml=>str( iv_city )
                  postal_zone            = lcl_xml=>str( iv_postcode )
                  country_subentity      = lcl_xml=>str( iv_region )
                  address_line           = VALUE #( line = lcl_xml=>str( iv_line ) )
                  country                = VALUE #( identification_code = lcl_xml=>str( iv_country ) ) ).
  ENDMETHOD.

  METHOD json_party.
    DATA: lv_agency TYPE string,
          lv_regno  TYPE string.

    DATA(lv_legal) = lcl_xml=>str( iv_legalid ).
    SPLIT lv_legal AT ':' INTO lv_agency lv_regno.

    rs-party = VALUE #(
      "Electronic address = TRN with scheme 0235 (as in the XML)
      endpoint_id        = lcl_xml=>str( iv_vat )
      endpoint_scheme_id = gc_scheme_tin
      party_name         = VALUE #( name = lcl_xml=>str( iv_name ) )
      postal_address     = json_address( iv_street   = iv_street
                                         iv_street2  = iv_street2
                                         iv_city     = iv_city
                                         iv_postcode = iv_postcode
                                         iv_region   = iv_region
                                         iv_country  = iv_country )
      party_tax_scheme   = VALUE #( company_id = lcl_xml=>str( iv_vat )
                                    tax_scheme = VALUE #( id = `VAT` ) )
      party_legal_entity = VALUE #(
        registration_name  = lcl_xml=>str( iv_name )
        company_id         = lv_regno
        scheme_agency_id   = COND #( WHEN lv_regno IS NOT INITIAL THEN lv_agency )
        scheme_agency_name = COND #( WHEN lv_regno IS NOT INITIAL
                                     THEN SWITCH string( lv_agency
                                                         WHEN 'TL'  THEN `Trade License issuing Authority`
                                                         WHEN 'PAS' THEN `Passport issuing Authority` ) ) ) ).
  ENDMETHOD.

  METHOD json_taxcat.
    rs = VALUE #( id         = lcl_xml=>str( iv_taxcode )
                  percent    = zcl_ei_json_builder=>format_number( iv_percent )   "5.00 -> "5"
                  tax_scheme = VALUE #( id = `VAT` ) ).
  ENDMETHOD.

  METHOD add_line_ac.
    "Postman: invoice_line[].allowances / .charges are single objects.
    "Several SAP conditions of the same kind are summed into one object;
    "reason / factor / base amount are taken from the first condition.
    DATA(lv_abs) = abs( is_prcd-value ).
    IF cs_ac IS INITIAL.
      cs_ac-charge_indicator = xsdbool( is_prcd-value GT 0 ).
      IF cs_ac-charge_indicator EQ abap_true.
        cs_ac-charge_reason_code = lcl_xml=>str( is_prcd-allowancecode ).
        cs_ac-charge_reason      = lcl_xml=>str( is_prcd-allowancename ).
      ELSE.
        cs_ac-allowance_charge_reason_code = lcl_xml=>str( is_prcd-allowancecode ).
        cs_ac-allowance_charge_reason      = lcl_xml=>str( is_prcd-allowancename ).
      ENDIF.
      IF is_prcd-calculationtype EQ 'A'.
        DATA(lv_mult) = abs( is_prcd-amount ).
        cs_ac-multiplier_factor_numeric = zcl_ei_json_builder=>format_number( lv_mult ).
        cs_ac-base_amount               = is_prcd-baseamount.
        cs_ac-base_amount_currency_code = iv_cur.
      ENDIF.
      cs_ac-amount_currency_code = iv_cur.
    ENDIF.
    cs_ac-amount = cs_ac-amount + lv_abs.
  ENDMETHOD.

  METHOD build_json.

    DATA: ls_doc     TYPE ty_j_invoice,
          lt_tax     TYPE tt_taxsum,
          lv_allow   TYPE vfprc_element_value,
          lv_charge  TYPE vfprc_element_value,
          lv_taxamt  TYPE vfprc_element_value,
          lv_value   TYPE vfprc_element_value,
          ls_hdrtax  TYPE zi_einvoice_conditions,
          ls_itemtax TYPE zi_einvoice_conditions,
          lv_pmethod TYPE string,
          lv_pmname  TYPE string,
          lv_pmcode  TYPE i,
          lv_iban    TYPE string,
          lv_accnm   TYPE string,
          lv_bic     TYPE string.

    DATA(lv_typecode) = is_out-einvoicetype.
    CHECK lv_typecode IS NOT INITIAL.
    DATA(lv_cn)    = xsdbool( lv_typecode EQ '381' ).
    DATA(lv_cur)   = lcl_xml=>str( is_out-currency ).
    DATA(lv_docid) = lcl_xml=>str( is_out-sapdocument ).
    "Invoice number - identical to cbc:ID / InstanceIdentifier of the XML
    DATA(lv_invno) = |{ is_out-supplierpeppolid }-{ is_out-companycode }-{ lv_docid }-{ is_out-fiscalyear }|.

    "Tax summary per tax code + header allowances / charges (as BUILD_XML)
    LOOP AT gt_prcd INTO DATA(ls_prcd) WHERE conditionno EQ is_out-conditionno.
      IF ls_prcd-accountkey     EQ 'MWS' AND
         ls_prcd-conditionclass EQ 'D'   AND
         ls_prcd-taxcode        IS NOT INITIAL.
        COLLECT VALUE ty_taxsum( taxcode   = ls_prcd-taxcode
                                 taxrate   = ls_prcd-taxrate
                                 eitaxtype = ls_prcd-einvoicetaxtype
                                 base      = ls_prcd-baseamount
                                 amount    = ls_prcd-value ) INTO lt_tax.
        lv_taxamt = lv_taxamt + ls_prcd-value.
        IF ls_hdrtax IS INITIAL.
          ls_hdrtax = ls_prcd.
        ENDIF.
      ENDIF.
      IF ls_prcd-item IS INITIAL AND ls_prcd-value IS NOT INITIAL AND
         ( ls_prcd-allowancetype EQ 'A' OR ls_prcd-allowancetype EQ 'C' ).
        IF ls_prcd-value GT 0.
          lv_charge = lv_charge + ls_prcd-value.
        ELSE.
          lv_allow = lv_allow - ls_prcd-value.
        ENDIF.
      ENDIF.
    ENDLOOP.

    "=== Header ===
    ls_doc = VALUE #(
      profile_execution_id = '00000000'
      invoice_number       = lv_invno
      issue_date           = is_out-creationdate
      issue_time           = is_out-creationtime
      due_date             = COND #( WHEN lv_cn EQ abap_false THEN is_out-billingdate )
      invoice_type_code    = lcl_xml=>str( lv_typecode )
      note                 = |This is { COND string( WHEN lv_cn EQ abap_true THEN `CreditNote` ELSE `Invoice` ) }|
      currency_code        = lv_cur ).

    IF lv_cn EQ abap_false.
      ls_doc-invoice_period = VALUE #(
        start_date = COND #( WHEN is_out-billingdate IS NOT INITIAL AND is_out-billingdate LT is_out-creationdate
                             THEN is_out-billingdate ELSE is_out-creationdate )
        end_date   = COND #( WHEN is_out-billingdate GT is_out-creationdate
                             THEN is_out-billingdate ELSE is_out-creationdate ) ).
    ELSE.
      ls_doc-credit_note_reason-response_code = lcl_xml=>str( is_out-einvoicecreditnotereason ).
    ENDIF.

    IF is_out-salesdocument IS NOT INITIAL.
      ls_doc-order_reference = VALUE #( id             = lcl_xml=>str( is_out-customerreference )
                                        sales_order_id = lcl_xml=>str( is_out-salesdocument ) ).
    ENDIF.

    "Credit note -> preceding invoice (same value as the XML BillingReference)
    IF lv_cn EQ abap_true AND is_out-headerreference IS NOT INITIAL.
      ls_doc-billing_reference = VALUE #(
        ( id = |{ is_out-originalcompanycode }-{ is_out-originaldocument }-{ is_out-originalfiscalyear }| ) ).
    ENDIF.

    "=== Parties ===
    ls_doc-accounting_supplier_party = json_party(
      iv_vat      = is_out-suppliervatregistrationcode
      iv_name     = is_out-suppliername
      iv_street   = is_out-supplierstreetname
      iv_street2  = is_out-supplieradditionalstreetname
      iv_city     = is_out-suppliercityname
      iv_postcode = is_out-supplierpostalcode
      iv_region   = is_out-supplierregion
      iv_country  = is_out-suppliercountry
      iv_legalid  = is_out-supplierlegalregistrationid ).

    ls_doc-accounting_customer_party = json_party(
      iv_vat      = is_out-customervatregistrationcode
      iv_name     = is_out-customername
      iv_street   = is_out-customerstreetname
      iv_street2  = is_out-customeradditionalstreetname
      iv_city     = is_out-customercityname
      iv_postcode = is_out-customerpostalcode
      iv_region   = is_out-customerregion
      iv_country  = is_out-customercountry
      iv_legalid  = is_out-customerlegalregistrationid ).

    "Delivery (ship-to)
    IF is_out-shiptoname IS NOT INITIAL.
      ls_doc-delivery = VALUE #(
        actual_delivery_date = is_out-billingdate
        delivery_location    = VALUE #( id        = lcl_xml=>str( is_out-shiptovatregistrationcode )
                                        scheme_id = COND #( WHEN is_out-shiptovatregistrationcode IS NOT INITIAL
                                                            THEN gc_scheme_tin )
                                        address   = json_address( iv_street   = is_out-shiptostreetname
                                                                  iv_street2  = is_out-shiptoadditionalstreetname
                                                                  iv_city     = is_out-shiptocityname
                                                                  iv_postcode = is_out-shiptopostalcode
                                                                  iv_region   = is_out-shiptoregion
                                                                  iv_country  = is_out-shiptocountry
                                                                  iv_line     = is_out-shiptoadditionalstreetname ) )
        delivery_party       = VALUE #( party_name = VALUE #( name = lcl_xml=>str( is_out-shiptoname ) ) ) ).
    ENDIF.

    "Payment means (invoice) - same priority as the XML
    IF lv_cn EQ abap_false.
      IF is_out-einvoicepaymentmethod IS NOT INITIAL.
        lv_pmethod = lcl_xml=>str( is_out-einvoicepaymentmethod ).
        lv_pmname  = lcl_xml=>str( is_out-einvoicepaymentmethodname ).
      ELSEIF is_out-customerpaymentmethod IS NOT INITIAL.
        lv_pmethod = lcl_xml=>str( is_out-customerpaymentmethod ).
        lv_pmname  = lcl_xml=>str( is_out-customerpaymentmethodname ).
      ELSE.
        lv_pmethod = lcl_xml=>str( is_out-supplierpaymentmethod ).
        lv_pmname  = lcl_xml=>str( is_out-supplierpaymentmethodname ).
      ENDIF.
      IF is_out-iban IS NOT INITIAL.
        lv_iban  = lcl_xml=>str( is_out-iban ).
        lv_accnm = lcl_xml=>str( is_out-accountname ).
        lv_bic   = lcl_xml=>str( is_out-swiftcode ).
      ELSEIF is_out-customeriban IS NOT INITIAL.
        lv_iban  = lcl_xml=>str( is_out-customeriban ).
        lv_accnm = lcl_xml=>str( is_out-customeraccountname ).
        lv_bic   = lcl_xml=>str( is_out-customerswiftcode ).
      ELSEIF is_out-supplieriban IS NOT INITIAL.
        lv_iban  = lcl_xml=>str( is_out-supplieriban ).
        lv_accnm = lcl_xml=>str( is_out-supplieraccountname ).
        lv_bic   = lcl_xml=>str( is_out-supplierswiftcode ).
      ENDIF.
      TRY.
          lv_pmcode = lv_pmethod.                 "Postman: number (10, 30, 48, 49)
        CATCH cx_sy_conversion_error.
          CLEAR lv_pmcode.
      ENDTRY.
      ls_doc-payment_means = VALUE #(
        ( payment_means_code      = lv_pmcode
          payment_means_text      = lv_pmname
          payment_id              = lv_invno
          payee_financial_account = VALUE #( id   = lv_iban
                                             name = lv_accnm
                                             financial_institution_branch = VALUE #( id = lv_bic ) ) ) ).
    ENDIF.

    IF is_out-paymentterms IS NOT INITIAL.
      ls_doc-payment_terms = VALUE #( ( note = lcl_xml=>str( is_out-paymentterms ) ) ).
    ENDIF.

    "Document level allowances / charges -> two arrays in JSON
    LOOP AT gt_prcd INTO ls_prcd WHERE conditionno EQ is_out-conditionno AND
                                       item        IS INITIAL AND
                                       value       IS NOT INITIAL AND
                                       ( allowancetype EQ 'A' OR allowancetype EQ 'C' ).
      DATA(lv_mult) = abs( ls_prcd-amount ).
      DATA(ls_dac) = VALUE ty_j_doc_ac(
        charge_indicator             = xsdbool( ls_prcd-value GT 0 )
        allowance_charge_reason_code = lcl_xml=>str( ls_prcd-allowancecode )
        allowance_charge_reason      = lcl_xml=>str( ls_prcd-allowancename )
        multiplier_factor_numeric    = COND #( WHEN ls_prcd-calculationtype EQ 'A'
                                               THEN zcl_ei_json_builder=>format_number( lv_mult ) )
        amount                       = abs( ls_prcd-value )
        amount_currency_code         = lv_cur
        base_amount                  = COND #( WHEN ls_prcd-calculationtype EQ 'A' THEN ls_prcd-baseamount )
        base_amount_currency_code    = COND #( WHEN ls_prcd-calculationtype EQ 'A' THEN lv_cur )
        tax_category                 = json_taxcat( iv_taxcode = ls_hdrtax-einvoicetaxtype
                                                    iv_percent = ls_hdrtax-taxrate ) ).
      IF ls_dac-charge_indicator EQ abap_true.
        APPEND ls_dac TO ls_doc-document_charges.
      ELSE.
        APPEND ls_dac TO ls_doc-document_allowances.
      ENDIF.
    ENDLOOP.

    "=== Tax total ===
    ls_doc-document_tax_total = VALUE #(
      tax_amount               = lv_taxamt
      tax_amount_currency_code = lv_cur
      tax_included_indicator   = abap_false
      tax_subtotal             = VALUE #( FOR ls_tax IN lt_tax
                                          ( taxable_amount               = ls_tax-base
                                            taxable_amount_currency_code = lv_cur
                                            tax_amount                   = ls_tax-amount
                                            tax_amount_currency_code     = lv_cur
                                            tax_category                 = json_taxcat( iv_taxcode = ls_tax-eitaxtype
                                                                                        iv_percent = ls_tax-taxrate ) ) ) ).

    "=== Legal monetary total ===
    lv_value = is_out-netvalue + lv_allow - lv_charge.
    ls_doc-legal_monetary_total = VALUE #(
      line_extension_amount        = lv_value
      line_ext_amt_cur             = lv_cur
      tax_exclusive_amount         = is_out-netvalue
      tax_excl_amt_cur             = lv_cur
      tax_inclusive_amount         = is_out-totalvalue
      tax_incl_amt_cur             = lv_cur
      allowance_total_amount       = lv_allow
      allow_total_amt_cur          = lv_cur
      charge_total_amount          = lv_charge
      charge_total_amt_cur         = lv_cur
      prepaid_amount               = 0
      prepaid_amount_currency_code = lv_cur
      payable_amount               = is_out-totalvalue
      payable_amount_currency_code = lv_cur ).

    "=== Lines ===
    LOOP AT gt_items INTO DATA(ls_item)
         WHERE companycode EQ is_out-companycode AND
               sapdocument EQ is_out-sapdocument AND
               fiscalyear  EQ is_out-fiscalyear.

      CLEAR ls_itemtax.
      LOOP AT gt_prcd INTO ls_prcd WHERE conditionno    EQ is_out-conditionno AND
                                         item           EQ ls_item-sapdocitem AND
                                         accountkey     EQ 'MWS' AND
                                         conditionclass EQ 'D' AND
                                         taxcode        IS NOT INITIAL.
        ls_itemtax = ls_prcd.
        EXIT.
      ENDLOOP.
      IF ls_itemtax IS INITIAL.
        ls_itemtax = ls_hdrtax.
      ENDIF.

      "Price (gross price condition PPR0 / ZPR1) - as BUILD_XML
      CLEAR lv_value.
      DATA(lv_puom) = ls_item-einvoiceunit.
      LOOP AT gt_prcd INTO ls_prcd WHERE conditionno EQ is_out-conditionno AND
                                         item        EQ ls_item-sapdocitem AND
                                         ( conditiontype EQ 'PPR0' OR conditiontype EQ 'ZPR1' ).
        lv_value = ls_prcd-value.
        IF ls_prcd-conditionunit IS NOT INITIAL.
          lv_puom = ls_prcd-einvoiceunit.
        ENDIF.
        EXIT.
      ENDLOOP.

      DATA(ls_line) = VALUE ty_j_line(
        id                          = |{ CONV i( ls_item-sapdocitem ) }|      "000010 -> "10"
        invoiced_quantity           = ls_item-quantity
        invoiced_quantity_unit_code = lcl_xml=>str( ls_item-einvoiceunit )
        line_extension_amount       = ls_item-netvalue
        line_ext_amt_cur            = lv_cur
        line_amount_aed             = COND #( WHEN lv_cur EQ `AED` THEN ls_item-netvalue )
        vat_amount_aed              = COND #( WHEN lv_cur EQ `AED` THEN ls_item-taxvalue )
        order_line_reference        = VALUE #( line_id = COND #( WHEN ls_item-salesorderitem IS NOT INITIAL
                                                                 THEN lcl_xml=>str( ls_item-salesorderitem ) ) )
        document_reference          = VALUE #( id           = lcl_xml=>str( ls_item-salesorder )
                                               id_scheme_id = COND #( WHEN ls_item-salesorder IS NOT INITIAL THEN `AWV` ) )
        item = VALUE #(
          description                  = lcl_xml=>str( ls_item-materialdescription )
          name                         = lcl_xml=>str( ls_item-materialdescription )
          buyers_item_identification   = VALUE #( id = lcl_xml=>str( ls_item-material ) )
          sellers_item_identification  = VALUE #( id = lcl_xml=>str( ls_item-material ) )
          standard_item_identification = VALUE #( id        = lcl_xml=>str( ls_item-material )
                                                  scheme_id = COND #( WHEN ls_item-material IS NOT INITIAL THEN `0088` ) )
          origin_country               = VALUE #( identification_code = lcl_xml=>str( ls_item-origincountry ) )
          classified_tax_category      = json_taxcat( iv_taxcode = ls_itemtax-einvoicetaxtype
                                                      iv_percent = ls_itemtax-taxrate )
          price = VALUE #( amount                  = lv_value
                           amount_currency_code    = lv_cur
                           gross_price             = lv_value
                           base_quantity           = ls_item-quantity
                           base_quantity_unit_code = lcl_xml=>str( lv_puom )
                           allowance_charge        = VALUE #( charge_indicator          = abap_false
                                                              amount                    = 0
                                                              amount_currency_code      = lv_cur
                                                              base_amount               = lv_value
                                                              base_amount_currency_code = lv_cur ) )
          "UAE extension: line amount incl. VAT and line VAT (as the XML)
          item_price_extension = VALUE #( amount               = ls_item-totalvalue
                                          amount_currency_code = lv_cur
                                          tax_total            = VALUE #( tax_amount               = ls_item-taxvalue
                                                                          tax_amount_currency_code = lv_cur ) ) ) ).

      "Line level allowances / charges
      LOOP AT gt_prcd INTO ls_prcd WHERE conditionno EQ is_out-conditionno AND
                                         item        EQ ls_item-sapdocitem AND
                                         value       IS NOT INITIAL AND
                                         ( allowancetype EQ 'A' OR allowancetype EQ 'C' ).
        IF ls_prcd-value GT 0.
          add_line_ac( EXPORTING is_prcd = ls_prcd iv_cur = lv_cur CHANGING cs_ac = ls_line-charges ).
        ELSE.
          add_line_ac( EXPORTING is_prcd = ls_prcd iv_cur = lv_cur CHANGING cs_ac = ls_line-allowances ).
        ENDIF.
      ENDLOOP.

      APPEND ls_line TO ls_doc-invoice_line.
    ENDLOOP.

    "Postman body shape 2: { "documents": [ { ...invoice } ] }
    rv_json = json_builder( )->serialize( VALUE ty_j_request( documents = VALUE #( ( ls_doc ) ) ) ).

  ENDMETHOD.

*----------------------------------------------------------------------*
* TaxLab responses -> SAME corner statuses / logs as today
*----------------------------------------------------------------------*
  METHOD post_result_json.

    "POST /api/invoice-endpoints/documents?country=UAE
    " 201 success=true, documents[0].status = accepted -> C2 Accepted
    " 400/422 schema validation (errors[].errors[])    -> C2 Rejected
    " 401/403 token                                    -> technical, token reset
    " 0 / 429 / 5xx / other                            -> technical, retry
    DATA: ls_resp TYPE ty_j_submit_resp,
          lv_jerr TYPE string.

    cs_out-responsepayload = iv_body.

    IF iv_code EQ 0.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |POST outbound: no response / timeout - { iv_reason } - status unchanged, retry possible| ).
      RETURN.
    ENDIF.

    IF iv_body IS NOT INITIAL.
      TRY.
          json_parser( )->deserialize( EXPORTING iv_json = iv_body CHANGING ca_data = ls_resp ).
        CATCH zcx_ei_json INTO DATA(lx_json).
          lv_jerr = lx_json->get_text( ).
      ENDTRY.
    ENDIF.

    IF iv_code EQ 401 OR iv_code EQ 403.
      drop_token( cs_out-companycode ).
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |POST outbound technical error: HTTP { iv_code } { iv_reason } { ls_resp-message } - token reset, status unchanged, retry possible| ).
      RETURN.
    ENDIF.

    READ TABLE ls_resp-documents INTO DATA(ls_doc) INDEX 1.
    DATA(lv_dstat) = to_upper( condense( ls_doc-status ) ).
    DATA(lv_bad)   = xsdbool( lv_dstat EQ 'REJECTED' OR lv_dstat EQ 'FAILED' OR
                              lv_dstat EQ 'ERROR'    OR lv_dstat EQ 'VALIDATION_ERROR' ).

    "SUCCESS -> Accepted by Supplier's ASP (Corner 2)
    IF iv_code BETWEEN 200 AND 299 AND ls_resp-success EQ abap_true AND
       ls_doc-uuid IS NOT INITIAL AND lv_bad EQ abap_false.
      cs_out-referenceid = ls_doc-uuid.                "-> {ID} of the GET URLs
      set_corner( EXPORTING is_out   = cs_out
                            iv_new   = gc_cs-accepted
                            iv_code  = 'C2'
                            iv_text  = gc_txt-c2_acc
                            iv_info  = |ASP uuid { ls_doc-uuid }, status { ls_doc-status }, batchId { ls_resp-batch_id }, queueJobId { ls_resp-queue_job_id }|
                  CHANGING  cv_field = cs_out-zzc2_status ).
      derive_overall( CHANGING cs_out = cs_out ).      "-> IN PROGRESS
      RETURN.
    ENDIF.

    "VALIDATION ERROR -> Rejected by Supplier's ASP (Corner 2) -> FAILED
    IF iv_code EQ 400 OR iv_code EQ 422 OR lv_bad EQ abap_true OR
       ( iv_code BETWEEN 200 AND 299 AND ls_resp-errors IS NOT INITIAL ).
      cs_out-referenceid = ls_doc-uuid.
      set_corner( EXPORTING is_out   = cs_out
                            iv_new   = gc_cs-rejected
                            iv_code  = 'C2'
                            iv_text  = gc_txt-c2_rej
                            iv_info  = |HTTP { iv_code } { ls_resp-message }|
                  CHANGING  cv_field = cs_out-zzc2_status ).
      log_asp_errors( is_out    = cs_out
                      iv_prefix = gc_txt-c2_rej
                      it_err    = taxlab_errors( iv_body ) ).
      derive_overall( CHANGING cs_out = cs_out ).      "-> FAILED
      RETURN.
    ENDIF.

    "Anything else -> technical error (NOT rejected), retry possible
    add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
             iv_text = |POST outbound technical error: HTTP { iv_code } { iv_reason } { ls_resp-message }| &&
                       |{ COND string( WHEN lv_jerr IS NOT INITIAL THEN | - { lv_jerr }| ) } - status unchanged, retry possible| ).

  ENDMETHOD.


  METHOD poll_result_json.

    "GET .../documents/{ID}/mls-messages  (ZEINVOICE_APIURL O / GET)
    "  transactionType SEND                       -> C3 sent
    "  receive from buyer AP  (responseCode AP/AB) -> C3 sent + C3 ack + C4
    "                         (responseCode RE)    -> C3 ack Failed
    "  receive from FTA 0242: (responseCode AP/AB) -> C5 ack
    "                         (responseCode RE)    -> C5 ack Failed
    "GET .../documents/{ID}/tdd-report    (ZEINVOICE_APIURL O / GET_ACK)
    "  -> C5 reported (see TDD_STATUS)
    "Acknowledgement legs (C3 ack, C4, C5 ack) only in background - as today
    DATA: ls_mls  TYPE ty_j_mls_resp,
          lv_tdd  TYPE string.

    IF iv_code EQ 0.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: no response / timeout - { iv_reason } - statuses unchanged, retry later| ).
      RETURN.
    ELSEIF iv_code EQ 401 OR iv_code EQ 403.
      drop_token( cs_out-companycode ).
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: HTTP { iv_code } { iv_reason } - token reset, statuses unchanged, retry later| ).
      RETURN.
    ELSEIF iv_code EQ 404.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: document { cs_out-referenceid } not found yet (HTTP 404) - statuses unchanged, re-check later| ).
      RETURN.
    ELSEIF iv_code LT 200 OR iv_code GT 299.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |Status (GET) API: HTTP { iv_code } { iv_reason } - statuses unchanged, retry later| ).
      RETURN.
    ENDIF.

    TRY.
        json_parser( )->deserialize( EXPORTING iv_json = iv_body CHANGING ca_data = ls_mls ).
      CATCH zcx_ei_json INTO DATA(lx_json).
        add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
                 iv_text = |Status (GET) API: { lx_json->get_text( ) } - statuses unchanged, retry later| ).
        RETURN.
    ENDTRY.

    IF ls_mls-messages IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'C2P'
               iv_text = |{ gc_txt-c2_pend } { sy-datum DATE = ISO } { sy-uzeit TIME = ISO }| ).
    ENDIF.

    LOOP AT ls_mls-messages INTO DATA(ls_msg).
      DATA(lv_ttype) = to_upper( condense( ls_msg-transaction_type ) ).
      DATA(lv_mls)   = to_upper( condense( ls_msg-mls_status ) ).
      DATA(lv_rc)    = to_upper( condense( ls_msg-response_code ) ).
      DATA(lv_fta)   = xsdbool( ls_msg-mls_from_party CP '0242:*' OR ls_msg-response_description CS 'C5' ).
      DATA(lv_info)  = |MLS { ls_msg-mls_id } { lv_ttype }/{ lv_mls } code { lv_rc } { ls_msg-response_description }|.

      IF lv_ttype EQ 'SEND'.
        "Our AP -> buyer's AP
        IF lv_mls EQ 'SENT' OR lv_mls EQ 'DELIVERED' OR lv_mls EQ 'ACKNOWLEDGED' OR lv_mls EQ 'RECEIVED'.
          set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C3S'
                                iv_text = gc_txt-c3_sent iv_info = lv_info
                      CHANGING  cv_field = cs_out-zzc3_sent_status ).
        ELSEIF lv_mls EQ 'FAILED' OR lv_mls EQ 'ERROR' OR lv_mls EQ 'REJECTED'.
          set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-failed iv_code = 'C3S'
                                iv_text = gc_txt-c3_sent iv_info = lv_info
                      CHANGING  cv_field = cs_out-zzc3_sent_status ).
        ELSE.
          add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'S'
                   iv_text = |{ lv_info } - not final yet, re-check later| ).
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_fta EQ abap_false.
        "MLS from the buyer's AP proves the delivery to C3
        set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C3S'
                              iv_text = gc_txt-c3_sent iv_info = lv_info
                    CHANGING  cv_field = cs_out-zzc3_sent_status ).
      ENDIF.

      CHECK sy-batch EQ abap_true.          "acknowledgement legs: background only

      CASE lv_rc.
        WHEN 'AP' OR 'AB'.
          IF lv_fta EQ abap_true.
            set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C5A'
                                  iv_text = gc_txt-c5_ack iv_info = |Document Response Code { lv_rc }|
                        CHANGING  cv_field = cs_out-zzc5_ack_status ).
          ELSE.
            set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C3A'
                                  iv_text = gc_txt-c3_ack iv_info = |Document Response Code { lv_rc }|
                        CHANGING  cv_field = cs_out-zzc3_ack_status ).
            set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C4'
                                  iv_text = gc_txt-c4 iv_info = |Document Response Code { lv_rc }|
                        CHANGING  cv_field = cs_out-zzc4_status ).
          ENDIF.
        WHEN 'RE'.
          IF lv_fta EQ abap_true.
            set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-failed iv_code = 'C5A'
                                  iv_text = gc_txt-c5_ack iv_info = lv_info
                        CHANGING  cv_field = cs_out-zzc5_ack_status ).
          ELSE.
            set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-failed iv_code = 'C3A'
                                  iv_text = gc_txt-c3_ack iv_info = lv_info
                        CHANGING  cv_field = cs_out-zzc3_ack_status ).
          ENDIF.
        WHEN OTHERS.
          add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'S'
                   iv_text = |{ lv_info } - not final yet, re-check later| ).
      ENDCASE.
    ENDLOOP.

    "C5 reported - TDD / FTA report
    tdd_status( EXPORTING iv_token = iv_token
                IMPORTING ev_body  = lv_tdd
                CHANGING  cs_out   = cs_out ).

    "Both answers kept for 'Display Response' (valid JSON)
    cs_out-responsepayload = |\{"mlsMessages":{ iv_body },"tddReport":| &&
                             |{ COND string( WHEN lv_tdd IS INITIAL THEN `null` ELSE lv_tdd ) }\}|.

    derive_overall( CHANGING cs_out = cs_out ).

  ENDMETHOD.


  METHOD tdd_status.

    DATA: ls_tdd    TYPE ty_j_tdd_resp,
          lv_code   TYPE i,
          lv_reason TYPE string.

    CLEAR ev_body.

    READ TABLE gt_apiurl INTO DATA(ls_api) WITH KEY direction = 'O' method = gc_api_get_ack.
    IF sy-subrc NE 0 OR ls_api-apiurl IS INITIAL.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |No GET_ACK (TDD report) API maintained in ZEINVOICE_APIURL for direction O - { gc_txt-c5_rep } unchanged| ).
      RETURN.
    ENDIF.

    "e.g. <base>/api/invoice-endpoints/documents/{ID}/tdd-report?country=UAE
    DATA(lv_ref) = escape( val = lcl_xml=>str( cs_out-referenceid ) format = cl_abap_format=>e_url_full ).
    DATA(lv_url) = lcl_xml=>str( ls_api-apiurl ).
    REPLACE ALL OCCURRENCES OF '{ID}'          IN lv_url WITH lv_ref.
    REPLACE ALL OCCURRENCES OF '{REFERENCEID}' IN lv_url WITH lv_ref.

    http_call( EXPORTING iv_url    = lv_url
                         iv_method = 'GET'
                         is_api    = ls_api
                         iv_token  = iv_token
                         iv_ctype  = `application/json`
               IMPORTING ev_code   = lv_code
                         ev_reason = lv_reason
                         ev_body   = ev_body ).

    IF lv_code NE 200.
      add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
               iv_text = |TDD report: HTTP { lv_code } { lv_reason } - { gc_txt-c5_rep } unchanged, re-check later| ).
      IF lv_code EQ 401 OR lv_code EQ 403.
        drop_token( cs_out-companycode ).
      ENDIF.
      CLEAR ev_body.
      RETURN.
    ENDIF.

    TRY.
        json_parser( )->deserialize( EXPORTING iv_json = ev_body CHANGING ca_data = ls_tdd ).
      CATCH zcx_ei_json INTO DATA(lx_json).
        add_log( is_out = cs_out iv_msgty = 'W' iv_code = 'W'
                 iv_text = |TDD report: { lx_json->get_text( ) } - { gc_txt-c5_rep } unchanged| ).
        RETURN.
    ENDTRY.

    LOOP AT ls_tdd-submissions INTO DATA(ls_sub).
      DATA(lv_st)   = to_upper( condense( ls_sub-submission_status ) ).
      DATA(lv_rep)  = to_upper( condense( ls_sub-reporting_status ) ).
      DATA(lv_info) = |submission { ls_sub-submission_uuid } { lv_st }, reporting { lv_rep }, | &&
                      |clearance { ls_sub-clearance_status }, hash { ls_sub-fta_invoice_hash }|.

      IF ls_sub-error_code IS NOT INITIAL OR
         lv_st EQ 'REJECTED' OR lv_st EQ 'FAILED' OR lv_st EQ 'ERROR'.
        set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-failed iv_code = 'C5R'
                              iv_text = gc_txt-c5_rep
                              iv_info = |{ lv_info } { ls_sub-error_code } { ls_sub-error_message }|
                    CHANGING  cv_field = cs_out-zzc5_rep_status ).
      ELSEIF lv_st EQ 'ACCEPTED' OR lv_st EQ 'SUBMITTED' OR lv_st EQ 'REPORTED' OR lv_st EQ 'CLEARED' OR
             lv_rep EQ 'REPORTED' OR lv_rep EQ 'ACCEPTED'.
        set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C5R'
                              iv_text = gc_txt-c5_rep iv_info = lv_info
                    CHANGING  cv_field = cs_out-zzc5_rep_status ).
        "FTA accepted the TDD -> C5 acknowledged (background only, as today)
        IF lv_st EQ 'ACCEPTED' AND sy-batch EQ abap_true.
          set_corner( EXPORTING is_out = cs_out iv_new = gc_cs-successful iv_code = 'C5A'
                                iv_text = gc_txt-c5_ack iv_info = lv_info
                      CHANGING  cv_field = cs_out-zzc5_ack_status ).
        ENDIF.
      ELSE.
        add_log( is_out = cs_out iv_msgty = 'S' iv_code = 'S'
                 iv_text = |TDD { lv_info } - not final yet, re-check later| ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD taxlab_errors.
    "errors[].errors[] -> one readable line per error (+ what to do)
    DATA ls_resp TYPE ty_j_submit_resp.

    TRY.
        json_parser( )->deserialize( EXPORTING iv_json = iv_json CHANGING ca_data = ls_resp ).
      CATCH zcx_ei_json.
        RETURN.
    ENDTRY.

    LOOP AT ls_resp-errors INTO DATA(ls_docerr).
      LOOP AT ls_docerr-errors INTO DATA(ls_err).
        DATA(ls_f) = VALUE ty_ferr(
          text = |{ ls_err-error_code }: { ls_err-error_description }| &&
                 COND string( WHEN ls_err-column_name IS NOT INITIAL THEN | (field { ls_err-column_name })| )
          fix  = COND #( WHEN ls_err-column_name IS NOT INITIAL
                         THEN |Correct the SAP data that fills JSON field { ls_err-column_name }, then press Submit again.|
                         ELSE `Correct the data in SAP and press Submit again.` ) ).
        IF NOT line_exists( rt[ text = ls_f-text ] ).
          APPEND ls_f TO rt.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    "No document errors: message (string or raw JSON array of strings)
    IF rt IS INITIAL AND ls_resp-message IS NOT INITIAL.
      DATA(lv_msg) = ls_resp-message.
      REPLACE ALL OCCURRENCES OF PCRE '^\s*\[\s*"|"\s*\]\s*$' IN lv_msg WITH ``.
      REPLACE ALL OCCURRENCES OF PCRE '"\s*,\s*"' IN lv_msg WITH `; `.
      APPEND VALUE #( text = lv_msg
                      fix  = `Correct the data in SAP and press Submit again. If the message is unclear, contact the ASP support.` ) TO rt.
    ENDIF.
  ENDMETHOD.


  METHOD drop_token.
    "Token rejected (HTTP 401/403): next call requests a new one
    DELETE gt_tokens WHERE bukrs EQ iv_bukrs.
    DATA(lv_buf_id) = CONV indx_srtfd( |ZEINVTOK{ iv_bukrs }| ).
    DELETE FROM SHARED BUFFER indx(zt) ID lv_buf_id.
  ENDMETHOD.

  METHOD x_name.
    rv = to_upper( iv_name ).
    IF rv CS ':'.
      rv = substring_after( val = rv sub = ':' ).
    ENDIF.
  ENDMETHOD.

  METHOD x_child.
    CHECK io_node IS BOUND.
    DATA(lv_name) = x_name( iv_name ).
    DATA(lo_node) = io_node->get_first_child( ).
    WHILE lo_node IS BOUND.
      IF lo_node->get_type( ) EQ if_ixml_node=>co_node_element AND
         x_name( lo_node->get_name( ) ) EQ lv_name.
        ro = lo_node.
        RETURN.
      ENDIF.
      lo_node = lo_node->get_next( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD x_list.
    CHECK io_node IS BOUND.
    DATA(lv_name) = x_name( iv_name ).
    DATA(lo_node) = io_node->get_first_child( ).
    WHILE lo_node IS BOUND.
      IF lo_node->get_type( ) EQ if_ixml_node=>co_node_element AND
         x_name( lo_node->get_name( ) ) EQ lv_name.
        APPEND lo_node TO rt.
      ENDIF.
      lo_node = lo_node->get_next( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD x_path.
    DATA lt_part TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_path AT '/' INTO TABLE lt_part.
    ro = io_node.
    LOOP AT lt_part INTO DATA(lv_part).
      ro = x_child( io_node = ro iv_name = lv_part ).
      IF ro IS NOT BOUND.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD x_val.
    DATA(lo_node) = x_path( io_node = io_node iv_path = iv_path ).
    IF lo_node IS BOUND.
      rv = lo_node->get_value( ).
      CONDENSE rv.
    ENDIF.
  ENDMETHOD.

  METHOD x_attr.
    DATA(lo_node) = x_path( io_node = io_node iv_path = iv_path ).
    CHECK lo_node IS BOUND.
    DATA(lo_attrs) = lo_node->get_attributes( ).
    CHECK lo_attrs IS BOUND.
    DATA(lo_attr) = lo_attrs->get_named_item( name = iv_attr ).
    IF lo_attr IS BOUND.
      rv = lo_attr->get_value( ).
    ENDIF.
  ENDMETHOD.

  METHOD h.
    rv = escape( val = lcl_xml=>str( iv ) format = cl_abap_format=>e_html_text ).
  ENDMETHOD.

  METHOD html_party.
    DATA(lo_p) = x_path( io_node = io_party iv_path = 'cac:Party' ).
    DATA(lv_addr) = |{ h( x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cbc:StreetName' ) ) }|.
    DATA(lv_add2) = x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cbc:AdditionalStreetName' ).
    IF lv_add2 IS NOT INITIAL.
      lv_addr = |{ lv_addr }, { h( lv_add2 ) }|.
    ENDIF.
    lv_addr = |{ lv_addr }<br>| &&
              |{ h( x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cbc:CityName' ) ) } | &&
              |{ h( x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cbc:PostalZone' ) ) } | &&
              |{ h( x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cbc:CountrySubentity' ) ) } | &&
              |{ h( x_val( io_node = lo_p iv_path = 'cac:PostalAddress/cac:Country/cbc:IdentificationCode' ) ) }|.
    DATA(lv_legal) = x_val( io_node = lo_p iv_path = 'cac:PartyLegalEntity/cbc:CompanyID' ).
    IF lv_legal IS NOT INITIAL.
      lv_legal = |{ x_attr( io_node = lo_p iv_path = 'cac:PartyLegalEntity/cbc:CompanyID' iv_attr = 'schemeAgencyID' ) } { lv_legal }|.
    ENDIF.
    rv = |<div class="party"><div class="lbl">{ h( iv_title ) }</div>| &&
         |<div class="pn">{ h( x_val( io_node = lo_p iv_path = 'cac:PartyName/cbc:Name' ) ) }</div>| &&
         |<div class="ad">{ lv_addr }</div>| &&
         |<table class="kv">| &&
         |<tr><td>TRN</td><td>{ h( x_val( io_node = lo_p iv_path = 'cac:PartyTaxScheme/cbc:CompanyID' ) ) }</td></tr>| &&
         |<tr><td>Legal registration</td><td>{ h( lv_legal ) }</td></tr>| &&
         |<tr><td>Peppol ID</td><td>{ h( iv_pid ) }</td></tr>| &&
         |</table></div>|.
  ENDMETHOD.

  METHOD build_html.

    DATA: lv_xml   TYPE string,
          lv_lines TYPE string,
          lv_tax   TYPE string,
          lv_corn  TYPE string,
          lv_level TYPE i,
          lv_fail  TYPE i,
          lv_src   TYPE string.

    lv_xml = is_out-requestpayload.
    lv_src = 'Submitted XML'.
    IF lv_xml IS INITIAL.
      lv_xml = preview_xml( is_out ).
      lv_src = 'Preview (not yet submitted)'.
    ELSEIF find( val = lv_xml pcre = '^\s*[\{\[]' ) EQ 0.
      lv_xml = preview_xml( is_out ).
      lv_src = 'Current SAP data (submitted as JSON)'.
    ENDIF.
    IF lv_xml IS INITIAL.
      RETURN.
    ENDIF.

    "Parse the PINT AE XML
    DATA(lo_ixml)   = cl_ixml=>create( ).
    DATA(lo_sf)     = lo_ixml->create_stream_factory( ).
    DATA(lo_doc)    = lo_ixml->create_document( ).
    DATA(lo_parser) = lo_ixml->create_parser( stream_factory = lo_sf
                                              istream        = lo_sf->create_istream_string( lv_xml )
                                              document       = lo_doc ).
    IF lo_parser->parse( ) NE 0.
      rv_html = |<html><body><h3>XML could not be parsed</h3><pre>{ h( lv_xml ) }</pre></body></html>|.
      RETURN.
    ENDIF.

    DATA(lo_root) = CAST if_ixml_node( lo_doc->get_root_element( ) ).
    DATA(lo_inv)  = x_child( io_node = lo_root iv_name = 'Invoice' ).
    DATA(lo_hdr)  = x_child( io_node = lo_root iv_name = 'StandardBusinessDocumentHeader' ).
    DATA(lv_cn)   = abap_false.
    IF lo_inv IS NOT BOUND.
      lo_inv = x_child( io_node = lo_root iv_name = 'CreditNote' ).
      lv_cn  = abap_true.
    ENDIF.
    IF lo_inv IS NOT BOUND.
      rv_html = |<html><body><h3>No Invoice / CreditNote element found</h3></body></html>|.
      RETURN.
    ENDIF.

    DATA(lv_cur)   = x_val( io_node = lo_inv iv_path = 'cbc:DocumentCurrencyCode' ).
    DATA(lv_title) = COND string( WHEN lv_cn EQ abap_true THEN 'CUSTOMER TAX CREDIT NOTE' ELSE 'CUSTOMER TAX INVOICE' ).
    DATA(lv_tcode) = COND string( WHEN lv_cn EQ abap_true
                                  THEN x_val( io_node = lo_inv iv_path = 'cbc:CreditNoteTypeCode' )
                                  ELSE x_val( io_node = lo_inv iv_path = 'cbc:InvoiceTypeCode' ) ).

    "Corner status strip - one box per stored corner status
    lv_corn = corner_strip_html( is_out ).

    "Lines
    DATA(lt_lines) = x_list( io_node = lo_inv
                             iv_name = COND string( WHEN lv_cn EQ abap_true THEN 'CreditNoteLine' ELSE 'InvoiceLine' ) ).
    DATA(lv_qtyp) = COND string( WHEN lv_cn EQ abap_true THEN 'cbc:CreditedQuantity' ELSE 'cbc:InvoicedQuantity' ).
    LOOP AT lt_lines INTO DATA(lo_line).
      lv_lines = lv_lines &&
        |<tr><td>{ h( x_val( io_node = lo_line iv_path = 'cbc:ID' ) ) }</td>| &&
        |<td>{ h( x_val( io_node = lo_line iv_path = 'cac:Item/cbc:Name' ) ) }| &&
        |<div class="sm">{ h( x_val( io_node = lo_line iv_path = 'cac:Item/cac:SellersItemIdentification/cbc:ID' ) ) }</div></td>| &&
        |<td class="r">{ h( x_val( io_node = lo_line iv_path = lv_qtyp ) ) } | &&
        |{ h( sap_uom( x_attr( io_node = lo_line iv_path = lv_qtyp iv_attr = 'unitCode' ) ) ) }</td>| &&
        |<td class="r">{ h( x_val( io_node = lo_line iv_path = 'cac:Price/cbc:PriceAmount' ) ) }</td>| &&
        |<td class="r">{ h( x_val( io_node = lo_line iv_path = 'cbc:LineExtensionAmount' ) ) }</td>| &&
        |<td class="c2">{ h( x_val( io_node = lo_line iv_path = 'cac:Item/cac:ClassifiedTaxCategory/cbc:ID' ) ) } | &&
        |{ h( x_val( io_node = lo_line iv_path = 'cac:Item/cac:ClassifiedTaxCategory/cbc:Percent' ) ) }%</td>| &&
        |<td class="r">{ h( x_val( io_node = lo_line iv_path = 'cac:ItemPriceExtension/cac:TaxTotal/cbc:TaxAmount' ) ) }</td>| &&
        |<td class="r">{ h( x_val( io_node = lo_line iv_path = 'cac:ItemPriceExtension/cbc:Amount' ) ) }</td></tr>|.
    ENDLOOP.

    "VAT breakdown
    DATA(lo_taxtot) = x_child( io_node = lo_inv iv_name = 'TaxTotal' ).
    LOOP AT x_list( io_node = lo_taxtot iv_name = 'TaxSubtotal' ) INTO DATA(lo_sub).
      lv_tax = lv_tax &&
        |<tr><td>VAT { h( x_val( io_node = lo_sub iv_path = 'cac:TaxCategory/cbc:ID' ) ) } | &&
        |{ h( x_val( io_node = lo_sub iv_path = 'cac:TaxCategory/cbc:Percent' ) ) }% on | &&
        |{ h( x_val( io_node = lo_sub iv_path = 'cbc:TaxableAmount' ) ) }</td>| &&
        |<td class="r">{ h( x_val( io_node = lo_sub iv_path = 'cbc:TaxAmount' ) ) }</td></tr>|.
    ENDLOOP.

    DATA(lo_lmt) = x_child( io_node = lo_inv iv_name = 'LegalMonetaryTotal' ).

    "Billing reference (credit note)
    DATA(lv_bref) = x_val( io_node = lo_inv iv_path = 'cac:BillingReference/cac:InvoiceDocumentReference/cbc:ID' ).
    DATA(lv_brefrow) = COND string( WHEN lv_bref IS NOT INITIAL
      THEN |<tr><td>Original invoice</td><td>{ h( lv_bref ) } / | &&
           |{ h( x_val( io_node = lo_inv iv_path = 'cac:BillingReference/cac:InvoiceDocumentReference/cbc:IssueDate' ) ) }</td></tr>| ).

    "Stylesheet (plain literals - no braces in string templates)
    DATA(lv_css) =
      'body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;line-height:1.4;color:#1d2d3e;background:#f5f6f7;margin:0}' &&
      'table{font-size:inherit;color:inherit}' &&
      '*{box-sizing:border-box}.doc{min-width:820px;max-width:1100px;background:#fff;margin:8px auto;padding:18px 22px;border:1px solid #d9d9d9;border-radius:6px}' &&
      '.hdr{display:flex;justify-content:space-between;border-bottom:3px solid #0a6ed1;padding-bottom:10px}' &&
      '.ttl{font-size:22px;font-weight:700;color:#0a6ed1;letter-spacing:1px}.sub{color:#6a6d70;font-size:12px}' &&
      '.kv td{padding:2px 10px 2px 0;vertical-align:top}.kv td:first-child{color:#6a6d70;white-space:nowrap}' &&
      '.cs{display:flex;gap:6px;margin:12px 0}.c{flex:1;border-radius:4px;padding:6px;font-size:11px;line-height:1.3;border:1px solid #d9d9d9}' &&
      '.c b{display:block;font-size:13px}.c.ok{background:#e8f5e9;border-color:#2b7d2b}.c.ko{background:#fdecea;border-color:#bb0000}' &&
      '.c.wt{background:#fff8e1;border-color:#e9730c}.c.na{background:#fafafa;color:#8c8c8c}' &&
      '.parties{display:flex;gap:16px;margin:10px 0}.party{flex:1;border:1px solid #e5e5e5;border-radius:4px;padding:10px}' &&
      '.lbl{font-size:11px;text-transform:uppercase;color:#6a6d70;letter-spacing:1px}.pn{font-size:15px;font-weight:600;margin:3px 0}' &&
      '.ad{margin-bottom:6px}table.ln{width:100%;border-collapse:collapse;margin-top:8px}' &&
      'table.ln th{background:#0a6ed1;color:#fff;text-align:left;padding:5px;font-weight:600}' &&
      'table.ln td{border-bottom:1px solid #e5e5e5;padding:5px;vertical-align:top}.r{text-align:right;white-space:nowrap}' &&
      '.c2{text-align:center}.sm{color:#6a6d70;font-size:11px}' &&
      '.bot{display:flex;gap:16px;margin-top:12px}.bot>div{flex:1}' &&
      'table.tot{width:100%;border-collapse:collapse}table.tot td{padding:4px 6px;border-bottom:1px solid #eee}' &&
      'table.tot tr.g td{font-weight:700;font-size:15px;border-top:2px solid #0a6ed1;background:#f0f6fd}' &&
      '.ft{margin-top:14px;color:#8c8c8c;font-size:11px}' &&
      '.pbar{min-width:820px;max-width:1100px;margin:8px auto 0;padding:0 8px;text-align:right}' &&
      '.lnw{overflow-x:auto}' &&
      '.pbtn{background:#0a6ed1;color:#fff;border:0;border-radius:4px;padding:6px 16px;font-size:12px;cursor:pointer}' &&
      '@media print{.pbar{display:none}body{background:#fff;font-size:10pt}.doc{border:0;margin:0;padding:0;max-width:none}' &&
      '.ttl{font-size:18pt}.pn,table.tot tr.g td{font-size:11pt}.c,.sm,.lbl,.ft{font-size:8pt}' &&
      '*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}'.

    rv_html =
      |{ gc_html_head }{ gc_scroll_css }{ lv_css }</style></head><body><div id="scr">| &&
      |<div class="pbar"><button class="pbtn" onclick="window.print()">Print</button></div>| &&
      |<div class="doc">| &&
      |<div class="hdr"><div><div class="ttl">{ lv_title }</div>| &&
      |<div class="sub">{ h( x_val( io_node = lo_inv iv_path = 'cbc:CustomizationID' ) ) } - type { h( lv_tcode ) }</div></div>| &&
      |<table class="kv">| &&
      |<tr><td>Number</td><td><b>{ h( x_val( io_node = lo_inv iv_path = 'cbc:ID' ) ) }</b></td></tr>| &&
      |<tr><td>Issue date</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cbc:IssueDate' ) ) }</td></tr>| &&
      |<tr><td>Due date</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cbc:DueDate' ) ) }</td></tr>| &&
      |<tr><td>Currency</td><td>{ h( lv_cur ) }</td></tr>| &&
      |<tr><td>Sales order</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cac:OrderReference/cbc:ID' ) ) }</td></tr>| &&
      lv_brefrow &&
      |<tr><td>UUID</td><td class="sm">{ h( x_val( io_node = lo_inv iv_path = 'cbc:UUID' ) ) }</td></tr>| &&
      |</table></div>| &&
      |<div class="cs">{ lv_corn }</div>| &&
      |<table class="kv"><tr><td>Overall status</td><td><b>{ h( COND string( WHEN is_out-zzoverall_status IS NOT INITIAL THEN is_out-zzoverall_status ELSE `Not yet submitted` ) ) }</b></td></tr>| &&
      |<tr><td>E-Invoice status</td><td><b>{ h( COND string( WHEN is_out-stattext IS NOT INITIAL THEN is_out-stattext ELSE is_out-einvoicestatus ) ) }</b></td></tr></table>| &&
      |<div class="parties">| &&
      html_party( io_party = x_child( io_node = lo_inv iv_name = 'AccountingSupplierParty' ) iv_title = 'Our company (Seller)'
                  iv_pid   = x_val( io_node = lo_hdr iv_path = 'Sender/Identifier' ) ) &&
      html_party( io_party = x_child( io_node = lo_inv iv_name = 'AccountingCustomerParty' ) iv_title = 'Customer'
                  iv_pid   = x_val( io_node = lo_hdr iv_path = 'Receiver/Identifier' ) ) &&
      |</div>| &&
      |<div class="lnw"><table class="ln"><tr><th>#</th><th>Description</th><th class="r">Quantity</th><th class="r">Price</th>| &&
      |<th class="r">Net amount</th><th class="c2">VAT</th><th class="r">VAT amount</th><th class="r">Total</th></tr>| &&
      lv_lines && |</table></div>| &&
      |<div class="bot"><div><div class="lbl">Payment</div><table class="kv">| &&
      |<tr><td>Means</td><td>{ h( x_attr( io_node = lo_inv iv_path = 'cac:PaymentMeans/cbc:PaymentMeansCode' iv_attr = 'name' ) ) } | &&
      |({ h( x_val( io_node = lo_inv iv_path = 'cac:PaymentMeans/cbc:PaymentMeansCode' ) ) })</td></tr>| &&
      |<tr><td>IBAN</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cac:PaymentMeans/cac:PayeeFinancialAccount/cbc:ID' ) ) }</td></tr>| &&
      |<tr><td>BIC</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cac:PaymentMeans/cac:PayeeFinancialAccount/cac:FinancialInstitutionBranch/cbc:ID' ) ) }</td></tr>| &&
      |<tr><td>Terms</td><td>{ h( x_val( io_node = lo_inv iv_path = 'cac:PaymentTerms/cbc:Note' ) ) }</td></tr>| &&
      |</table></div><div><table class="tot">| &&
      |<tr><td>Sum of line net amounts</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:LineExtensionAmount' ) ) }</td></tr>| &&
      |<tr><td>Allowances</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:AllowanceTotalAmount' ) ) }</td></tr>| &&
      |<tr><td>Charges</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:ChargeTotalAmount' ) ) }</td></tr>| &&
      |<tr><td>Total without VAT</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:TaxExclusiveAmount' ) ) }</td></tr>| &&
      lv_tax &&
      |<tr><td>Total VAT</td><td class="r">{ h( x_val( io_node = lo_taxtot iv_path = 'cbc:TaxAmount' ) ) }</td></tr>| &&
      |<tr><td>Total with VAT</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:TaxInclusiveAmount' ) ) }</td></tr>| &&
      |<tr><td>Prepaid</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:PrepaidAmount' ) ) }</td></tr>| &&
      |<tr class="g"><td>Amount due ({ h( lv_cur ) })</td><td class="r">{ h( x_val( io_node = lo_lmt iv_path = 'cbc:PayableAmount' ) ) }</td></tr>| &&
      |</table></div></div>| &&
      |<div class="ft">Rendered from the PINT AE XML - { lv_src } - { sy-datum DATE = ISO } { sy-uzeit TIME = ISO }</div>| &&
      |</div></div></body></html>|.

  ENDMETHOD.


*----------------------------------------------------------------------*
* ASP response in a user-friendly (HTML) format
*----------------------------------------------------------------------*
  METHOD sap_uom.
    "UN/ECE unit code from the XML (e.g. C62) -> SAP unit of measure as
    "shown in SAP (e.g. PC), via value mapping UNIT_OF_MEASURE_CODE
    DATA: lv_msehi TYPE msehi,
          lv_out   TYPE c LENGTH 10.
    rv = iv_code.
    LOOP AT gt_mapping INTO DATA(ls_map) WHERE vmapname EQ 'UNIT_OF_MEASURE_CODE'.
      IF lcl_xml=>str( ls_map-ext_value1 ) EQ iv_code.
        lv_msehi = ls_map-int_value.
        EXIT.
      ENDIF.
    ENDLOOP.
    CHECK lv_msehi IS NOT INITIAL.
    CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
      EXPORTING
        input          = lv_msehi
        language       = sy-langu
      IMPORTING
        output         = lv_out
      EXCEPTIONS
        unit_not_found = 1
        OTHERS         = 2.
    rv = COND #( WHEN sy-subrc EQ 0 AND lv_out IS NOT INITIAL
                 THEN lcl_xml=>str( lv_out ) ELSE lcl_xml=>str( lv_msehi ) ).
  ENDMETHOD.

  METHOD fit_script.
    "Fit the HTML frame to the visible popup area (SAP GUI for HTML renders
    "the browser control with a fixed size); no effect in SAP GUI desktop
    rv = '<script>(function(){try{var f=window.frameElement;if(!f)return;' &&
         'var s=f.parentElement;while(s){var o=getComputedStyle(s).overflowY;' &&
         'if(o=="auto"||o=="scroll")break;s=s.parentElement;}if(!s)return;' &&
         'function fit(){var w=s.clientWidth-6,h=s.clientHeight-6;if(w<200)return;' &&
         'var q=f;while(q&&q!==s){q.style.width=w+"px";q.style.height=h+"px";' &&
         'q.style.minWidth="0";q=q.parentElement;}}' &&
         'fit();setTimeout(fit,300);window.parent.addEventListener("resize",fit);' &&
         '}catch(e){}})();</script>'.
  ENDMETHOD.

  METHOD resp_label.
    DATA(lv_key) = to_upper( iv_key ).
    rv = SWITCH #( lv_key
           WHEN 'ID'                    THEN 'ASP transaction ID'
           WHEN 'REFERENCEID'           THEN 'ASP reference'
           WHEN 'MESSAGEID'             THEN 'Peppol message ID'
           WHEN 'INSTANCEIDENTIFIER'    THEN 'Document instance'
           WHEN 'SENDERPARTICIPANTID'   THEN 'Sender - our company (Peppol ID)'
           WHEN 'RECEIVERPARTICIPANTID' THEN 'Receiver - customer (Peppol ID)'
           WHEN 'DOCUMENTTYPEID'        THEN 'Document type'
           WHEN 'PROCESSID'             THEN 'Process'
           WHEN 'TRANSMISSIONTYPE'      THEN 'Direction'
           WHEN 'STATUS'                THEN 'ASP status'
           WHEN 'SERVICEPROVIDERID'     THEN 'Service provider ID'
           WHEN 'CREATEDDATE'           THEN 'Processed on (ASP)'
           WHEN 'ERRORDETAILS'          THEN 'Error details'
           WHEN 'MESSAGE'               THEN 'Message'
           WHEN 'CODE'                  THEN 'Code'
           WHEN 'TYPE'                  THEN 'Type'
           WHEN 'PROPERTYNAME'          THEN 'Field'
           ELSE '' ).
    IF rv IS INITIAL.
      "camelCase / snake_case -> Title Case
      rv = replace( val = iv_key pcre = '([a-z0-9])([A-Z])' with = '$1 $2' occ = 0 ).
      REPLACE ALL OCCURRENCES OF '_' IN rv WITH | |.
      CONDENSE rv.
      IF rv IS NOT INITIAL.
        rv = |{ to_upper( substring( val = rv len = 1 ) ) }{ substring( val = rv off = 1 ) }|.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD resp_value.
    DATA(lv_key) = to_upper( iv_key ).
    rv = iv_val.
    "Peppol participant IDs: drop the scheme prefix
    IF lv_key CS 'PARTICIPANTID' AND rv CS '::'.
      rv = substring_after( val = rv sub = '::' ).
    ENDIF.
    IF lv_key EQ 'DOCUMENTTYPEID'.
      rv = COND #( WHEN rv CS 'CreditNote' THEN |Credit Note (PINT AE)|
                   WHEN rv CS 'Invoice'    THEN |Invoice (PINT AE)|
                   ELSE rv ).
    ENDIF.
    IF lv_key EQ 'PROCESSID' AND rv CS 'peppol:bis:billing'.
      rv = |Peppol BIS Billing|.
    ENDIF.
    IF lv_key EQ 'TRANSMISSIONTYPE'.
      rv = to_mixed( val = rv ).
    ENDIF.
    "ISO timestamps -> dd.mm.yyyy hh:mm:ss
    FIND PCRE '^(\d{4})-(\d{2})-(\d{2})T(\d{2}:\d{2}:\d{2})' IN rv
         SUBMATCHES DATA(lv_y) DATA(lv_m) DATA(lv_d) DATA(lv_t).
    IF sy-subrc EQ 0.
      rv = |{ lv_d }.{ lv_m }.{ lv_y } { lv_t } (UTC)|.
    ENDIF.
  ENDMETHOD.

  METHOD pint_term.
    "PINT AE business term id -> term name (docs.peppol.eu/poac/ae/pint-ae)
    DATA(lv_t)   = to_upper( iv_term ).
    DATA(lv_sfx) = ``.
    FIND PCRE '^((?:IBT|IBG|BTAE)-\d+)-\d+$' IN lv_t SUBMATCHES DATA(lv_base).
    IF sy-subrc = 0.
      lv_t   = lv_base.
      lv_sfx = ` - scheme identifier`.
    ENDIF.
    rv = SWITCH string( lv_t
           WHEN 'IBT-001' THEN `Invoice number`
           WHEN 'IBT-002' THEN `Invoice issue date`
           WHEN 'IBT-003' THEN `Invoice type code`
           WHEN 'IBT-005' THEN `Invoice currency code`
           WHEN 'IBT-006' THEN `Tax currency code`
           WHEN 'IBT-007' THEN `Tax point date`
           WHEN 'IBT-009' THEN `Payment due date`
           WHEN 'IBT-010' THEN `Buyer reference`
           WHEN 'IBT-013' THEN `Purchase order reference`
           WHEN 'IBT-018' THEN `Invoiced object identifier`
           WHEN 'IBT-023' THEN `Business process type`
           WHEN 'IBT-024' THEN `Specification identifier`
           WHEN 'IBT-025' THEN `Preceding invoice reference`
           WHEN 'IBT-027' THEN `Seller name`
           WHEN 'IBT-030' THEN `Seller legal registration identifier`
           WHEN 'IBT-031' THEN `Seller tax identifier`
           WHEN 'IBT-032' THEN `Seller tax registration identifier`
           WHEN 'IBT-034' THEN `Seller electronic address`
           WHEN 'IBT-040' THEN `Seller country code`
           WHEN 'IBT-044' THEN `Buyer name`
           WHEN 'IBT-046' THEN `Buyer identifier`
           WHEN 'IBT-047' THEN `Buyer legal registration identifier`
           WHEN 'IBT-048' THEN `Buyer tax identifier`
           WHEN 'IBT-049' THEN `Buyer electronic address`
           WHEN 'IBT-055' THEN `Buyer country code`
           WHEN 'IBT-060' THEN `Payee identifier`
           WHEN 'IBT-061' THEN `Payee legal registration identifier`
           WHEN 'IBT-069' THEN `Tax representative country code`
           WHEN 'IBT-071' THEN `Deliver to location identifier`
           WHEN 'IBT-080' THEN `Deliver to country code`
           WHEN 'IBT-081' THEN `Payment means type code`
           WHEN 'IBT-098' THEN `Document level allowance reason code`
           WHEN 'IBT-105' THEN `Document level charge reason code`
           WHEN 'IBT-106' THEN `Sum of invoice line net amount`
           WHEN 'IBT-109' THEN `Invoice total amount without tax`
           WHEN 'IBT-110' THEN `Invoice total tax amount`
           WHEN 'IBT-112' THEN `Invoice total amount with tax`
           WHEN 'IBT-115' THEN `Amount due for payment`
           WHEN 'IBT-116' THEN `Tax category taxable amount`
           WHEN 'IBT-117' THEN `Tax category tax amount`
           WHEN 'IBT-118' THEN `Tax category code`
           WHEN 'IBT-119' THEN `Tax category rate`
           WHEN 'IBT-120' THEN `Tax exemption reason text`
           WHEN 'IBT-121' THEN `Tax exemption reason code`
           WHEN 'IBT-125' THEN `Attached document`
           WHEN 'IBT-126' THEN `Invoice line identifier`
           WHEN 'IBT-128' THEN `Invoice line object identifier`
           WHEN 'IBT-129' THEN `Invoiced quantity`
           WHEN 'IBT-130' THEN `Invoiced quantity unit of measure code`
           WHEN 'IBT-131' THEN `Invoice line net amount`
           WHEN 'IBT-140' THEN `Invoice line allowance reason code`
           WHEN 'IBT-145' THEN `Invoice line charge reason code`
           WHEN 'IBT-146' THEN `Item net price`
           WHEN 'IBT-148' THEN `Item gross price`
           WHEN 'IBT-149' THEN `Item price base quantity`
           WHEN 'IBT-150' THEN `Item price base quantity unit of measure code`
           WHEN 'IBT-151' THEN `Invoiced item tax category code`
           WHEN 'IBT-152' THEN `Invoiced item tax rate`
           WHEN 'IBT-153' THEN `Item name`
           WHEN 'IBT-157' THEN `Item standard identifier`
           WHEN 'IBT-158' THEN `Item classification identifier`
           WHEN 'IBT-159' THEN `Item country of origin`
           WHEN 'IBG-03'  THEN `Preceding invoice reference`
           WHEN 'IBG-25'  THEN `Invoice line`
           WHEN 'BTAE-03' THEN `Credit note reason code`
           WHEN 'BTAE-16' THEN `Buyer legal registration identifier type`
           WHEN 'BTAE-19' THEN `Passport issuing country code`
           ELSE `` ).
    IF rv IS NOT INITIAL.
      rv = rv && lv_sfx.
    ENDIF.
  ENDMETHOD.

  METHOD rule_hint.
    "SAP-side corrective action for a PINT AE rule
    rv = SWITCH string( iv_id
           WHEN 'IBR-CL-23' THEN
             `Maintain the ISO code of the SAP unit of measure (transaction CUNI, field ISO code / T006-ISOCODE) ` &&
             `with a UN/ECE Rec 20/21 code, e.g. H87 (piece), EA (each), KGM (kilogram), LTR (litre), MTR (metre).`
           WHEN 'IBR-CL-03' OR 'IBR-CL-04' OR 'IBR-CL-05' THEN
             `Use an ISO 4217 alpha-3 currency code (transaction OY03, ISO code / TCURC-ISOCD).`
           WHEN 'IBR-CL-14' OR 'IBR-CL-15' THEN
             `Use an ISO 3166-1 alpha-2 country code (transaction OY01, ISO code / T005-INTCA) in the address master data.`
           WHEN 'IBR-CL-25' THEN
             `Check the Peppol endpoint scheme (e.g. 0235 for UAE TIN) maintained for the seller / customer.`
           WHEN 'IBR-CL-01' THEN
             `Check the mapping of the SAP billing type to the invoice type code (380 / 381).`
           WHEN 'IBR-CL-16' THEN
             `Check the mapping of the SAP payment method to a UNCL 4461 payment means code.`
           ELSE `` ).
    CHECK rv IS INITIAL.
    rv = COND string(
           WHEN iv_id CP 'IBR-CO-*' THEN
             `Calculated amounts do not add up - check pricing conditions, rounding and tax totals of the billing document.`
           WHEN iv_id CP 'IBR-CL-*' THEN
             `The value is not in the allowed code list - correct the SAP master data / code mapping.`
           WHEN iv_id CP 'IBR-SR-*' THEN
             `An element occurs more often than allowed - check the XML mapping of the business terms listed.`
           WHEN iv_id CP 'ALIGNED-*' OR iv_id CP '*-AE' THEN
             `UAE (FTA) specific requirement - check the master data / mapping of the business terms listed.`
           ELSE
             `Correct the source data of the business terms listed and submit the document again.` ).
  ENDMETHOD.

  METHOD rule_title.
    "Simple-English meaning of a PINT AE rule
    rv = SWITCH string( iv_id
      WHEN 'IBR-CL-23' THEN `The unit of measure on the invoice lines is not a valid international unit code (UN/ECE Rec 20/21, e.g. H87, EA, KGM).` &&
                            ` The ASP only accepts these codes, not the internal SAP units such as PC or KG.`
      WHEN 'IBR-CL-03' OR 'IBR-CL-04' OR 'IBR-CL-05' THEN `The currency is not a valid international currency code (ISO 4217, e.g. AED, USD).`
      WHEN 'IBR-CL-14' OR 'IBR-CL-15' THEN `The country in an address is not a valid 2-letter country code (ISO 3166-1, e.g. AE).`
      WHEN 'IBR-CL-25' THEN `The electronic address (Peppol ID) of the seller or the customer uses a scheme that is not allowed.`
      WHEN 'IBR-CL-01' THEN `The invoice type is not allowed (only 380 = invoice and 381 = credit note).`
      WHEN 'IBR-CL-16' THEN `The payment method is not a valid payment means code.`
      ELSE `` ).
    CHECK rv IS INITIAL.
    rv = COND string(
      WHEN iv_id CP 'IBR-CO-*' THEN `Amounts or totals on the invoice do not add up correctly.`
      WHEN iv_id CP 'IBR-CL-*' THEN `A value on the invoice is not in the list of allowed codes.`
      WHEN iv_id CP 'IBR-SR-*' THEN `A field appears on the invoice more often than allowed.`
      WHEN iv_id CP 'ALIGNED-*' OR iv_id CP '*-AE' THEN `A UAE (FTA) specific rule is not met.` ).
  ENDMETHOD.

  METHOD log_html.
    "Turn a technical processing-log entry into a plain-language sentence
    "with a 'How to fix' hint (returns HTML, all values escaped)
    DATA: lv_txt  TYPE string,
          lv_fix  TYPE string,
          lv_ref  TYPE string,
          lv_ids  TYPE string,
          lv_code TYPE string,
          lv_mean TYPE string,
          lv_rest TYPE string,
          lv_list TYPE string,
          lv_rx   TYPE string,
          lv_cnt  TYPE i.

    DATA(lv_msg) = condense( iv_msg ).
    FIND PCRE 'Ref\sidentifier:\s*\[([^\]]+)\]' IN lv_msg SUBMATCHES lv_ref.
    FIND PCRE '(?:^|\s)HTTP\s+(\d{3})' IN lv_msg SUBMATCHES lv_code.

    IF lv_msg CS 'already exists'.
      lv_txt = `This document had already been submitted to our ASP, so it was not sent again.`.
      lv_fix = `Check the existing submission in the ASP portal - do not resubmit the same document.`.

    ELSEIF lv_msg CS 'VALIDATION_ERROR' OR lv_msg CS 'validation failed'.
      lv_txt = `The invoice was rejected by our e-invoicing provider (ASP) because it did not pass the UAE e-invoice checks.`.
      "Full rule details come from the stored ASP response (the log text is cut off)
      DATA(lv_all) = |{ lv_msg } { iv_full }|.
      FIND ALL OCCURRENCES OF PCRE '\[([A-Za-z]+(?:-[A-Za-z0-9]+)+)\]\s*-?\s*([^\[\]"\\]*)' IN lv_all RESULTS DATA(lt_hit).
      LOOP AT lt_hit INTO DATA(ls_hit).
        READ TABLE ls_hit-submatches INTO DATA(ls_sm) INDEX 1.
        CHECK sy-subrc EQ 0.
        DATA(lv_id) = to_upper( substring( val = lv_all off = ls_sm-offset len = ls_sm-length ) ).
        IF lv_ids CS |{ lv_id };|.
          CONTINUE.
        ENDIF.
        lv_ids = |{ lv_ids }{ lv_id };|.
        DATA(lv_title) = rule_title( lv_id ).
        IF lv_title IS INITIAL.
          "Unknown rule: use the ASP's own text
          READ TABLE ls_hit-submatches INTO DATA(ls_tx) INDEX 2.
          IF sy-subrc EQ 0 AND ls_tx-length GT 0.
            lv_title = condense( substring( val = lv_all off = ls_tx-offset len = ls_tx-length ) ).
          ENDIF.
        ENDIF.
        IF lv_title IS INITIAL.
          lv_title = `See the ASP Response for the details.`.
        ENDIF.
        lv_rx = `\[` && lv_id && `\]`.
        CLEAR lv_cnt.
        FIND ALL OCCURRENCES OF PCRE lv_rx IN iv_full IGNORING CASE MATCH COUNT lv_cnt.
        lv_rest = COND #( WHEN lv_cnt GT 1 THEN | (found { lv_cnt } times)| ELSE `` ).
        lv_list = |{ lv_list }<li><b>Problem:</b> { h( lv_title ) }{ lv_rest }| &&
                  |<span style="color:#6a6d70;font-size:11px"> - rule { lv_id }</span></li>|.
        lv_fix = |{ lv_fix } { rule_hint( lv_id ) }|.
      ENDLOOP.
      IF lv_ids IS INITIAL.
        lv_fix = `Open the ASP Response to see which checks failed, correct the data and submit the document again.`.
      ELSE.
        lv_fix = |{ lv_fix } Then submit the document again.|.
      ENDIF.

    ELSEIF lv_msg CP 'Token:*' OR lv_msg CP 'Status check - token*'.
      lv_rest = condense( substring_after( val = lv_msg sub = ':' ) ).
      lv_txt = `SAP could not log on to the ASP (the access token request failed)`.
      IF lv_rest IS NOT INITIAL.
        lv_txt = |{ lv_txt }: { lv_rest }|.
      ENDIF.
      lv_txt = |{ lv_txt }.|.
      lv_fix = `Check the ASP user / client credentials and the token URL maintained for this company code.`.

    ELSEIF lv_msg CP 'No POST API*'.
      lv_txt = `The ASP submission URL (POST) is not maintained for outbound documents.`.
      lv_fix = `Maintain the POST entry for direction O (Outbound) in table ZEINVOICE_APIURL and submit again.`.

    ELSEIF lv_msg CP 'No status (GET) API*'.
      lv_txt = `The status could not be checked because no ASP status URL (GET) is maintained.`.
      lv_fix = `Maintain the GET entry in table ZEINVOICE_APIURL - until then the document status stays unchanged.`.

    ELSEIF lv_msg CP 'PINT AE XML could not be generated*'.
      FIND PCRE 'for\s+([^\s)]+)\)' IN lv_msg SUBMATCHES lv_rest.
      lv_txt = |The invoice XML could not be created in SAP because billing type { lv_rest } is not mapped to an invoice type code.|.
      lv_fix = `Maintain mapping INVOICE_TYPE_CODE_SD for this billing type (380 = invoice, 381 = credit note) and process the document again.`.

    ELSEIF lv_code IS NOT INITIAL.
      lv_mean = SWITCH string( lv_code
        WHEN '400' THEN `the request data was rejected as invalid`
        WHEN '401' THEN `SAP is not authorised (logon / token invalid or expired)`
        WHEN '403' THEN `access is not allowed for this user`
        WHEN '404' THEN `the ASP address (URL) was not found`
        WHEN '408' OR '504' THEN `the ASP did not answer in time`
        WHEN '409' THEN `the document already exists at the ASP`
        WHEN '429' THEN `too many requests were sent in a short time`
        ELSE COND #( WHEN lv_code >= '500' THEN `the ASP service has a technical problem`
                     ELSE `the ASP returned an unexpected answer` ) ).
      IF lv_msg CP 'Status check*'.
        lv_txt = |The status check at the ASP failed (HTTP { lv_code }): { lv_mean }.|.
      ELSE.
        lv_txt = |The ASP did not accept the submission (HTTP { lv_code }): { lv_mean }.|.
      ENDIF.
      lv_fix = SWITCH string( lv_code
        WHEN '401' OR '403' THEN `Check the ASP credentials / token configuration for this company code.`
        WHEN '404' THEN `Check the URL maintained in table ZEINVOICE_APIURL.`
        WHEN '400' THEN `Open the ASP Response for the details, correct the data and submit again.`
        WHEN '409' THEN `Check the existing submission in the ASP portal - do not resubmit the same document.`
        ELSE `Try again later - if the problem continues, contact the ASP support.` ).
      IF lv_msg CP 'Status check*'.
        lv_fix = |{ lv_fix } The document status stays unchanged until the check succeeds.|.
      ENDIF.

    ELSEIF lv_msg CP 'ASP status:*' OR lv_msg CP 'ASP:*'.
      lv_rest = condense( substring_after( val = lv_msg sub = ':' ) ).
      lv_txt = |The ASP reported the status: { lv_rest }.|.

    ELSEIF lv_msg CS 'Rejected by' AND lv_msg CS 'Corner 3'.
      lv_txt = `The customer's ASP (Corner 3) rejected the invoice.`.
      lv_fix = `Open the ASP Response for the reason and agree the correction with the customer.`.

    ELSEIF lv_msg CP 'PINT AE XML generated*'.
      FIND PCRE '(\d+)\s+characters' IN lv_msg SUBMATCHES lv_rest.
      lv_txt = `The PINT AE invoice XML was created in SAP`.
      IF lv_rest IS NOT INITIAL.
        lv_txt = |{ lv_txt } ({ lv_rest } characters)|.
      ENDIF.
      lv_txt = |{ lv_txt }.|.

    ELSE.
      rv = h( lv_msg ).
      RETURN.
    ENDIF.

    rv = h( lv_txt ).
    IF lv_list IS NOT INITIAL.
      rv = |{ rv }<ul style="margin:4px 0 0 18px;padding:0">{ lv_list }</ul>|.
    ENDIF.
    IF lv_fix IS NOT INITIAL.
      lv_fix = condense( lv_fix ).
      rv = |{ rv }<div style="margin-top:4px;padding:4px 8px;background:#fff8e1;| &&
           |border-left:3px solid #e9730c;border-radius:3px"><b>How to fix:</b> { h( lv_fix ) }</div>|.
    ENDIF.
    IF lv_ref IS NOT INITIAL.
      rv = |{ rv }<div style="margin-top:3px;font-size:11px;color:#6a6d70">ASP reference: { h( lv_ref ) }</div>|.
    ENDIF.
  ENDMETHOD.

  METHOD xsd_label.
    "UBL element of an XML schema error -> business term for end users
    DATA(lv_el) = replace( val = condense( iv_el ) pcre = '^[A-Za-z0-9]+:' with = `` ).
    DATA(lv_bt) = SWITCH string( lv_el
      WHEN 'PaymentMeansCode'     THEN `IBT-081`
      WHEN 'PaymentID'            THEN `IBT-083`
      WHEN 'IssueDate'            THEN `IBT-002`
      WHEN 'InvoiceTypeCode'      THEN `IBT-003`
      WHEN 'CreditNoteTypeCode'   THEN `IBT-003`
      WHEN 'DocumentCurrencyCode' THEN `IBT-005`
      WHEN 'TaxCurrencyCode'      THEN `IBT-006`
      WHEN 'TaxPointDate'         THEN `IBT-007`
      WHEN 'DueDate'              THEN `IBT-009`
      WHEN 'BuyerReference'       THEN `IBT-010`
      WHEN 'AccountingCost'       THEN `IBT-019`
      WHEN 'Note'                 THEN `IBT-022`
      WHEN 'RegistrationName'     THEN `IBT-027`
      WHEN 'EndpointID'           THEN `IBT-034`
      WHEN 'StreetName'           THEN `IBT-035`
      WHEN 'CityName'             THEN `IBT-037`
      WHEN 'PostalZone'           THEN `IBT-038`
      WHEN 'CountrySubentity'     THEN `IBT-039`
      WHEN 'IdentificationCode'   THEN `IBT-040`
      WHEN 'PayeeFinancialAccount' THEN `IBG-17`
      WHEN 'LineExtensionAmount'  THEN `IBT-106`
      WHEN 'TaxExclusiveAmount'   THEN `IBT-109`
      WHEN 'TaxAmount'            THEN `IBT-110`
      WHEN 'TaxInclusiveAmount'   THEN `IBT-112`
      WHEN 'PayableAmount'        THEN `IBT-115`
      WHEN 'TaxableAmount'        THEN `IBT-116`
      WHEN 'Percent'              THEN `IBT-119`
      WHEN 'InvoicedQuantity'     THEN `IBT-129`
      WHEN 'CreditedQuantity'     THEN `IBT-129`
      WHEN 'PriceAmount'          THEN `IBT-146`
      WHEN 'BaseQuantity'         THEN `IBT-149`
      ELSE `` ).
    DATA(lv_name) = COND string( WHEN lv_bt IS NOT INITIAL THEN pint_term( lv_bt ) ).
    "CamelCase -> words: PaymentMeansCode -> Payment Means Code
    DATA(lv_words) = replace( val = lv_el pcre = '([a-z])([A-Z])' with = `$1 $2` occ = 0 ).
    rv = COND #( WHEN lv_name IS NOT INITIAL THEN |{ lv_name } ({ lv_bt })|
                 WHEN lv_el   EQ 'ID'          THEN `Identifier (ID)`
                 ELSE lv_words ).
  ENDMETHOD.

  METHOD xsd_hint.
    "How to fix - XML schema (UBL 2.1) errors, in end-user language
    IF iv_expected CS 'PaymentMeansCode'.
      rv = `The payment means code (IBT-081) is empty for this billing document. Maintain the e-invoice payment method `
        && `(UNCL4461 code, e.g. 30 = credit transfer, 10 = cash, 48 = card) in the billing document / payment terms mapping and submit again.`.
    ELSEIF iv_code CP 'cvc-complex-type.2.4.a*' OR iv_code CP 'cvc-complex-type.2.4.b*'.
      rv = `A mandatory field is empty in SAP, so it was not written to the e-invoice. Fill the field listed above in the `
        && `billing document or in the master data (customer, company code, material) and submit again.`.
    ELSEIF iv_code CP 'cvc-complex-type.2.4.d*'.
      rv = `The e-invoice contains a field at a position where it is not allowed. Please contact the SAP support team (e-invoice mapping).`.
    ELSEIF iv_code CP 'cvc-datatype*' OR iv_code CP 'cvc-pattern*' OR iv_code CP 'cvc-enumeration*' OR
           iv_code CP 'cvc-type*' OR iv_code CP 'cvc-*length*' OR iv_code CP 'cvc-*digits*'.
      rv = `A value has the wrong format (date, amount, code or text length). Correct the value in the billing document `
        && `or master data and submit again.`.
    ELSE.
      rv = `The e-invoice does not match the required UBL 2.1 / PINT AE structure. Please contact the SAP support team `
        && `and provide the original ASP error text shown below.`.
    ENDIF.
  ENDMETHOD.

  METHOD xsd_text.
    "XML schema error (cvc-...) -> sentence for end users
    DATA: lt_exp   TYPE string_table,
          lv_found TYPE string,
          lv_exp   TYPE string,
          lv_inc   TYPE string,
          lv_xval  TYPE string,
          lv_xel   TYPE string,
          lv_xlst  TYPE string.
    DATA(lv_stext) = iv_text.
    "Remove XML namespaces: {"urn:...":PaymentID} / {urn:...}PaymentID
    lv_stext = replace( val = lv_stext pcre = '\{urn:[^}]*\}'           with = ``   occ = 0 ).
    lv_stext = replace( val = lv_stext pcre = '"[^"]*":([A-Za-z0-9_]+)' with = `$1` occ = 0 ).
    lv_stext = replace( val = lv_stext pcre = '[{}]'                    with = ``   occ = 0 ).
    lv_stext = condense( lv_stext ).
    FIND PCRE 'starting with element ''([^'']+)'''              IN lv_stext SUBMATCHES lv_found.
    FIND PCRE 'One of ''([^'']+)'' is expected'                  IN lv_stext SUBMATCHES lv_exp.
    FIND PCRE 'content of element ''([^'']+)'' is not complete'  IN lv_stext SUBMATCHES lv_inc.
    FIND PCRE 'of element ''([^'']+)'''                         IN lv_stext SUBMATCHES lv_xel.
    FIND PCRE '''([^'']*)'''                                     IN lv_stext SUBMATCHES lv_xval.
    SPLIT lv_exp AT ',' INTO TABLE lt_exp.
    LOOP AT lt_exp INTO DATA(lv_e).
      CONDENSE lv_e.
      CHECK lv_e IS NOT INITIAL.
      lv_xlst = lv_xlst && COND string( WHEN lv_xlst IS NOT INITIAL THEN ` or ` ) && |"{ xsd_label( lv_e ) }"|.
    ENDLOOP.
    rv = COND string(
      WHEN iv_code CP 'cvc-complex-type.2.4.a*' AND lv_exp IS NOT INITIAL
        THEN |Mandatory data is missing in the e-invoice: { lv_xlst } must be provided before "{ xsd_label( lv_found ) }".|
      WHEN iv_code CP 'cvc-complex-type.2.4.b*'
        THEN |Section "{ xsd_label( lv_inc ) }" is incomplete - mandatory data missing: { lv_xlst }.|
      WHEN iv_code CP 'cvc-complex-type.2.4.d*'
        THEN |Field "{ xsd_label( lv_found ) }" is not allowed at this position of the e-invoice.|
      WHEN iv_code CP 'cvc-datatype*' OR iv_code CP 'cvc-pattern*' OR iv_code CP 'cvc-enumeration*' OR
           iv_code CP 'cvc-type*' OR iv_code CP 'cvc-*length*' OR iv_code CP 'cvc-*digits*'
        THEN |The value "{ lv_xval }"{ COND string( WHEN lv_xel IS NOT INITIAL THEN | of field "{ xsd_label( lv_xel ) }"| ) } has an invalid format.|
      ELSE lv_stext ).
  ENDMETHOD.

  METHOD friendly_errors.
    "ASP error text -> one readable line per distinct error (+ how to fix)
    DATA ls_f TYPE ty_ferr.
    DATA(lv_txt) = iv_text.
    REPLACE ALL OCCURRENCES OF '\"' IN lv_txt WITH '"'.
    REPLACE ALL OCCURRENCES OF '\/' IN lv_txt WITH '/'.

    "1. PINT AE rule violations: [ibr-cl-23]-text
    FIND ALL OCCURRENCES OF PCRE '\[([A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)+)\]\s*-\s*([^\[\]]+)'
         IN lv_txt RESULTS DATA(lt_hit).
    LOOP AT lt_hit INTO DATA(ls_hit).
      READ TABLE ls_hit-submatches INTO DATA(ls_id) INDEX 1.
      READ TABLE ls_hit-submatches INTO DATA(ls_tx) INDEX 2.
      DATA(lv_id) = to_upper( substring( val = lv_txt off = ls_id-offset len = ls_id-length ) ).
      ls_f = VALUE #( text = |{ lv_id }: { condense( substring( val = lv_txt off = ls_tx-offset len = ls_tx-length ) ) }|
                      fix  = rule_hint( lv_id ) ).
      READ TABLE rt TRANSPORTING NO FIELDS WITH KEY text = ls_f-text.
      IF sy-subrc NE 0.
        APPEND ls_f TO rt.
      ENDIF.
    ENDLOOP.

    "2. XML schema errors: [SAX] cvc-<code>: <text>
    FIND ALL OCCURRENCES OF PCRE '\[SAX\]\s*(cvc-[A-Za-z0-9.\-]+)\s*:\s*([^\]]+)'
         IN lv_txt RESULTS DATA(lt_sax).
    LOOP AT lt_sax INTO DATA(ls_sax).
      READ TABLE ls_sax-submatches INTO DATA(ls_sc) INDEX 1.
      READ TABLE ls_sax-submatches INTO DATA(ls_st) INDEX 2.
      DATA(lv_code) = substring( val = lv_txt off = ls_sc-offset len = ls_sc-length ).
      DATA(lv_part) = substring( val = lv_txt off = ls_st-offset len = ls_st-length ).
      DATA(lv_exp) = ``.
      FIND PCRE 'One of (.*) is expected' IN lv_part SUBMATCHES lv_exp.
      ls_f = VALUE #( text = xsd_text( iv_code = lv_code iv_text = lv_part )
                      fix  = xsd_hint( iv_code = lv_code iv_expected = lv_exp ) ).
      READ TABLE rt TRANSPORTING NO FIELDS WITH KEY text = ls_f-text.
      IF sy-subrc NE 0.
        APPEND ls_f TO rt.
      ENDIF.
    ENDLOOP.
    CHECK rt IS INITIAL.

    "3. Any other text: remove the technical noise
    DATA(lv_rest) = lv_txt.
    lv_rest = replace( val = lv_rest pcre = '(?i)^\s*failed to process request:\s*' with = `` ).
    lv_rest = replace( val = lv_rest pcre = '(?i)Ref\s+identifier:\s*\[?[^\]\s]*\]?\.?' with = `` occ = 0 ).
    lv_rest = replace( val = lv_rest pcre = '\{?"?urn:[^}"'']*["'']?\}?:?' with = `` occ = 0 ).
    lv_rest = condense( lv_rest ).
    CHECK lv_rest IS NOT INITIAL.
    APPEND VALUE #( text = lv_rest
                    fix  = `Correct the data in SAP and submit again. If the message is unclear, contact the SAP support team.` ) TO rt.
  ENDMETHOD.

  METHOD asp_errors.
    "TaxLab: errors[].errors[] (error_code / error_description / column_name)
    IF iv_json CS '"error_description"' OR iv_json CS '"statusCode"'.
      rt = taxlab_errors( iv_json ).
      IF rt IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.
    "Readable errors from an ASP response (errorDetails / message ...), each error once
    FIND ALL OCCURRENCES OF PCRE '(?i)"(?:errorDetails|errorMessage|message|reason|description|detail)"\s*:\s*"((?:[^"\\]|\\.)*)"'
         IN iv_json RESULTS DATA(lt_res).
    "errorDetails / errors as an array of plain strings
    FIND ALL OCCURRENCES OF PCRE '(?i)"(?:errorDetails|errors?)"\s*:\s*\[([^\]{]*)\]'
         IN iv_json RESULTS DATA(lt_arr).
    APPEND LINES OF lt_arr TO lt_res.
    LOOP AT lt_res INTO DATA(ls_res).
      READ TABLE ls_res-submatches INTO DATA(ls_sm) INDEX 1.
      CHECK sy-subrc EQ 0 AND ls_sm-length GT 0.
      LOOP AT friendly_errors( substring( val = iv_json off = ls_sm-offset len = ls_sm-length ) ) INTO DATA(ls_f).
        READ TABLE rt TRANSPORTING NO FIELDS WITH KEY text = ls_f-text.
        CHECK sy-subrc NE 0.
        APPEND ls_f TO rt.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD log_asp_errors.
    "One short, readable log line per error (ZEINVOICE_ERROR-MESSAGE = 220 characters)
    LOOP AT it_err INTO DATA(ls_err).
      DATA(lv_line) = |{ iv_prefix } - error { sy-tabix }: { ls_err-text }|.
      add_log( is_out = is_out iv_msgty = 'E' iv_code = 'E'
               iv_text = substring( val = lv_line len = nmin( val1 = strlen( lv_line ) val2 = 220 ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD rule_errors_html.
    "Structured view of PINT AE validation errors returned by the ASP,
    "e.g. [Text=[ibr-cl-23]-Unit code (ibt-130), (ibt-150) MUST be ...]
    TYPES: BEGIN OF ty_rule,
             id    TYPE string,
             text  TYPE string,
             count TYPE i,
           END OF ty_rule.
    DATA: lt_rule TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY,
          lt_gen  TYPE string_table,
          lt_seen TYPE string_table,
          lv_ref  TYPE string,
          lv_rows TYPE string,
          lv_raw  TYPE string,
          lv_no   TYPE i.

    DATA(lv_root) = `https://docs.peppol.eu/poac/ae/pint-ae/`.
    DATA(lv_base) = lv_root && COND string( WHEN iv_cn = abap_true THEN `trn-creditnote/` ELSE `trn-invoice/` ).

    "XML schema (XSD) errors, e.g. [SAX] cvc-complex-type.2.4.a: Invalid content ...
    TYPES: BEGIN OF ty_xsd,
             code  TYPE string,
             text  TYPE string,
             fix   TYPE string,
             terms TYPE string,
           END OF ty_xsd.
    DATA: lt_xsd   TYPE STANDARD TABLE OF ty_xsd WITH EMPTY KEY,
          lt_exp   TYPE string_table,
          lv_found TYPE string,
          lv_exp   TYPE string,
          lv_inc   TYPE string,
          lv_xval  TYPE string,
          lv_xel   TYPE string,
          lv_xlst  TYPE string,
          lv_xtrm  TYPE string.

    LOOP AT it_msg INTO DATA(lv_msg).
      lv_raw = lv_raw && |<li>{ h( lv_msg ) }</li>|.
      "XML schema (XSD) errors returned by the ASP: [SAX] cvc-<code>: <text>
      FIND ALL OCCURRENCES OF PCRE '\[SAX\]\s*(cvc-[A-Za-z0-9.\-]+)\s*:\s*([^\]]+)'
           IN lv_msg RESULTS DATA(lt_sax).
      LOOP AT lt_sax INTO DATA(ls_sax).
        READ TABLE ls_sax-submatches INTO DATA(ls_sc) INDEX 1.
        READ TABLE ls_sax-submatches INTO DATA(ls_st) INDEX 2.
        DATA(lv_scode) = substring( val = lv_msg off = ls_sc-offset len = ls_sc-length ).
        DATA(lv_stext) = substring( val = lv_msg off = ls_st-offset len = ls_st-length ).
        "Remove XML namespaces: {"urn:...":PaymentID} / {urn:...}PaymentID
        lv_stext = replace( val = lv_stext pcre = '\{urn:[^}]*\}'           with = ``   occ = 0 ).
        lv_stext = replace( val = lv_stext pcre = '"[^"]*":([A-Za-z0-9_]+)' with = `$1` occ = 0 ).
        lv_stext = replace( val = lv_stext pcre = '[{}]'                    with = ``   occ = 0 ).
        lv_stext = condense( lv_stext ).
        CLEAR: lv_found, lv_exp, lv_inc, lv_xval, lv_xel, lv_xlst, lv_xtrm, lt_exp.
        FIND PCRE 'starting with element ''([^'']+)'''              IN lv_stext SUBMATCHES lv_found.
        FIND PCRE 'One of ''([^'']+)'' is expected'                  IN lv_stext SUBMATCHES lv_exp.
        FIND PCRE 'content of element ''([^'']+)'' is not complete'  IN lv_stext SUBMATCHES lv_inc.
        FIND PCRE 'of element ''([^'']+)'''                         IN lv_stext SUBMATCHES lv_xel.
        FIND PCRE '''([^'']*)'''                                     IN lv_stext SUBMATCHES lv_xval.
        SPLIT lv_exp AT ',' INTO TABLE lt_exp.
        LOOP AT lt_exp INTO DATA(lv_e).
          CONDENSE lv_e.
          CHECK lv_e IS NOT INITIAL.
          lv_xlst = lv_xlst && COND string( WHEN lv_xlst IS NOT INITIAL THEN ` or ` ) && |"{ xsd_label( lv_e ) }"|.
          lv_xtrm = lv_xtrm && |<div class="chip"><b>Expected:</b> { h( xsd_label( lv_e ) ) }</div>|.
        ENDLOOP.
        IF lv_found IS NOT INITIAL.
          lv_xtrm = |<div class="chip"><b>Found:</b> { h( xsd_label( lv_found ) ) }</div>| && lv_xtrm.
        ENDIF.
        DATA(lv_xtxt) = COND string(
          WHEN lv_scode CP 'cvc-complex-type.2.4.a*' AND lv_exp IS NOT INITIAL
            THEN |Mandatory data is missing in the e-invoice: { lv_xlst } must be provided before "{ xsd_label( lv_found ) }".|
          WHEN lv_scode CP 'cvc-complex-type.2.4.b*'
            THEN |Section "{ xsd_label( lv_inc ) }" is incomplete - mandatory data missing: { lv_xlst }.|
          WHEN lv_scode CP 'cvc-complex-type.2.4.d*'
            THEN |Field "{ xsd_label( lv_found ) }" is not allowed at this position of the e-invoice.|
          WHEN lv_scode CP 'cvc-datatype*' OR lv_scode CP 'cvc-pattern*' OR lv_scode CP 'cvc-enumeration*' OR
               lv_scode CP 'cvc-type*' OR lv_scode CP 'cvc-*length*' OR lv_scode CP 'cvc-*digits*'
            THEN |The value "{ lv_xval }"{ COND string( WHEN lv_xel IS NOT INITIAL THEN | of field "{ xsd_label( lv_xel ) }"| ) } has an invalid format.|
          ELSE lv_stext ).
        READ TABLE lt_xsd TRANSPORTING NO FIELDS WITH KEY text = lv_xtxt.
        CHECK sy-subrc NE 0.                 "same error reported several times
        APPEND VALUE #( code  = lv_scode
                        text  = lv_xtxt
                        fix   = xsd_hint( iv_code = lv_scode iv_expected = lv_exp )
                        terms = lv_xtrm ) TO lt_xsd.
      ENDLOOP.
      IF lv_ref IS INITIAL.
        FIND PCRE 'Ref\sidentifier:\s*\[([^\]]+)\]' IN lv_msg SUBMATCHES lv_ref.
      ENDIF.
      "Rule violations: [rule-id]-message
      FIND ALL OCCURRENCES OF PCRE '\[([A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)+)\]\s*-\s*([^\[\]]+)'
           IN lv_msg RESULTS DATA(lt_hit).
      LOOP AT lt_hit INTO DATA(ls_hit).
        READ TABLE ls_hit-submatches INTO DATA(ls_id) INDEX 1.
        READ TABLE ls_hit-submatches INTO DATA(ls_tx) INDEX 2.
        DATA(lv_id) = to_upper( substring( val = lv_msg off = ls_id-offset len = ls_id-length ) ).
        DATA(lv_tx) = condense( substring( val = lv_msg off = ls_tx-offset len = ls_tx-length ) ).
        READ TABLE lt_rule ASSIGNING FIELD-SYMBOL(<ls_rule>) WITH KEY id = lv_id text = lv_tx.
        IF sy-subrc = 0.
          <ls_rule>-count = <ls_rule>-count + 1.
        ELSE.
          APPEND VALUE #( id = lv_id text = lv_tx count = 1 ) TO lt_rule.
        ENDIF.
      ENDLOOP.
      "General (non rule specific) part of the message
      DATA(lv_gen) = replace( val = lv_msg pcre = '\s*(?:Ref\sidentifier|Error\sdetails|\[Text=|\\r).*$' with = `` ).
      lv_gen = condense( replace( val = lv_gen pcre = '[\s.:;,-]+$' with = `` ) ).
      CHECK lv_gen IS NOT INITIAL.
      DATA(lv_dup) = abap_false.
      LOOP AT lt_gen ASSIGNING FIELD-SYMBOL(<lv_gen>).
        IF <lv_gen> CS lv_gen.
          lv_dup = abap_true.
        ELSEIF lv_gen CS <lv_gen>.
          <lv_gen> = lv_gen.
          lv_dup = abap_true.
        ENDIF.
      ENDLOOP.
      IF lv_dup = abap_false.
        APPEND lv_gen TO lt_gen.
      ENDIF.
    ENDLOOP.

    CHECK lt_rule IS NOT INITIAL OR lt_xsd IS NOT INITIAL.

    LOOP AT lt_rule INTO DATA(ls_rule).
      lv_no = lv_no + 1.
      DATA(lv_lid) = to_lower( ls_rule-id ).
      "Rule set
      DATA(lv_cat) = COND string(
                       WHEN ls_rule-id CP 'ALIGNED-*' OR ls_rule-id CP '*-AE' THEN `UAE specific PINT rule`
                       WHEN ls_rule-id CP 'IBR-CL-*' THEN `Code list rule`
                       WHEN ls_rule-id CP 'IBR-CO-*' THEN `Calculation rule`
                       WHEN ls_rule-id CP 'IBR-SR-*' THEN `Cardinality rule`
                       WHEN ls_rule-id CP 'IBR-*'    THEN `Shared PINT business rule`
                       ELSE `Peppol rule` ).
      "Severity: MUST = fatal, should = warning (as in the PINT AE schematron)
      DATA(lv_sev) = COND string(
                       WHEN find( val = ls_rule-text pcre = '\bMUST\b' ) >= 0 THEN `Fatal`
                       WHEN find( val = ls_rule-text pcre = '(?i)\bshould\b' ) >= 0 THEN `Warning`
                       ELSE `Error` ).
      DATA(lv_scl) = COND string( WHEN lv_sev = `Warning` THEN `w` ELSE `f` ).
      "Code list referenced by IBR-CL rules
      DATA(lv_cl) = SWITCH string( ls_rule-id
                      WHEN 'IBR-CL-01' THEN COND string( WHEN iv_cn = abap_true THEN `UNCL1001-cn` ELSE `UNCL1001-inv` )
                      WHEN 'IBR-CL-03' OR 'IBR-CL-04' OR 'IBR-CL-05' THEN `ISO4217`
                      WHEN 'IBR-CL-07' THEN `UNCL1153`
                      WHEN 'IBR-CL-10' OR 'IBR-CL-11' OR 'IBR-CL-21' OR 'IBR-CL-26' THEN `ICD`
                      WHEN 'IBR-CL-13' THEN `UNCL7143`
                      WHEN 'IBR-CL-14' OR 'IBR-CL-15' THEN `ISO3166`
                      WHEN 'IBR-CL-16' THEN `UNCL4461`
                      WHEN 'IBR-CL-19' THEN `UNCL5189`
                      WHEN 'IBR-CL-20' THEN `UNCL7161`
                      WHEN 'IBR-CL-23' THEN `UNECERec20`
                      WHEN 'IBR-CL-24' THEN `MimeCode`
                      WHEN 'IBR-CL-25' THEN `eas`
                      ELSE `` ).
      "Business terms mentioned in the rule text
      DATA(lv_terms) = ``.
      CLEAR lt_seen.
      FIND ALL OCCURRENCES OF PCRE '(?i)\b(?:ibt|ibg|btae)-\d+(?:-\d+)?' IN ls_rule-text RESULTS DATA(lt_term).
      LOOP AT lt_term INTO DATA(ls_term).
        DATA(lv_term) = to_upper( substring( val = ls_rule-text off = ls_term-offset len = ls_term-length ) ).
        READ TABLE lt_seen TRANSPORTING NO FIELDS WITH KEY table_line = lv_term.
        CHECK sy-subrc <> 0.
        APPEND lv_term TO lt_seen.
        DATA(lv_tname) = pint_term( lv_term ).
        lv_terms = lv_terms && |<div class="chip"><b>{ h( lv_term ) }</b>| &&
                   COND string( WHEN lv_tname IS NOT INITIAL THEN | { h( lv_tname ) }| ) && |</div>|.
      ENDLOOP.

      lv_rows = lv_rows &&
        |<tr><td class="n">{ lv_no }</td>| &&
        |<td><a href="{ lv_base }rule/{ lv_lid }/" target="_blank"><b>{ h( ls_rule-id ) }</b></a>| &&
        |<div class="cat">{ h( lv_cat ) }</div></td>| &&
        |<td><span class="sev { lv_scl }">{ lv_sev }</span></td>| &&
        |<td>{ h( ls_rule-text ) }| &&
        COND string( WHEN ls_rule-count > 1 THEN | <span class="cnt">reported { ls_rule-count }x</span>| ) &&
        |<div class="fix"><b>How to fix:</b> { h( rule_hint( ls_rule-id ) ) }</div>| &&
        COND string( WHEN lv_cl IS NOT INITIAL
                     THEN |<div class="cl">Allowed values: <a href="{ lv_base }codelist/{ lv_cl }/" target="_blank">{ lv_cl } code list</a></div>| ) &&
        |</td><td>{ COND string( WHEN lv_terms IS NOT INITIAL THEN lv_terms ELSE `-` ) }</td></tr>|.
    ENDLOOP.

    "XML schema errors - one row each, in end-user language
    LOOP AT lt_xsd INTO DATA(ls_xsd).
      lv_no = lv_no + 1.
      lv_rows = lv_rows &&
        |<tr><td class="n">{ lv_no }</td>| &&
        |<td><b>Missing / invalid data</b><div class="cat">E-invoice structure (UBL 2.1)</div></td>| &&
        |<td><span class="sev f">Fatal</span></td>| &&
        |<td>{ h( ls_xsd-text ) }| &&
        |<div class="fix"><b>How to fix:</b> { h( ls_xsd-fix ) }</div>| &&
        |<div class="cnt">Technical code: { h( ls_xsd-code ) }</div>| &&
        |</td><td>{ COND string( WHEN ls_xsd-terms IS NOT INITIAL THEN ls_xsd-terms ELSE `-` ) }</td></tr>|.
    ENDLOOP.

    DATA(lv_gtxt) = ``.
    LOOP AT lt_gen INTO DATA(lv_g).
      lv_gtxt = lv_gtxt && COND string( WHEN lv_gtxt IS NOT INITIAL THEN ` / ` ) && lv_g.
    ENDLOOP.

    rv = |<h2>What went wrong</h2>| &&
         |<div class="mbox ko"><b>{ h( COND string( WHEN lv_gtxt IS NOT INITIAL THEN lv_gtxt ELSE `Invoice validation failed` ) ) }</b>| &&
         |<br>{ COND string( WHEN lt_rule IS NOT INITIAL THEN |{ lines( lt_rule ) } PINT AE validation rule(s) violated| ) }| &&
         |{ COND string( WHEN lt_rule IS NOT INITIAL AND lt_xsd IS NOT INITIAL THEN ` and ` ) }| &&
         |{ COND string( WHEN lt_xsd IS NOT INITIAL THEN |{ lines( lt_xsd ) } data error(s) in the e-invoice| ) }| &&
         COND string( WHEN lv_ref IS NOT INITIAL THEN | - ASP reference { h( lv_ref ) }| ) && |</div>| &&
         |<table class="err"><tr><th>#</th><th>Rule</th><th>Severity</th><th>Description</th><th>Business terms</th></tr>| &&
         lv_rows && |</table>| &&
         |<div class="src">Rules reference: <a href="{ lv_root }" target="_blank">PINT AE - Peppol International Invoicing UAE</a>| &&
         | ({ COND string( WHEN iv_cn = abap_true THEN `Credit Note` ELSE `Invoice` ) } rules)</div>| &&
         |<details><summary>Show original ASP error text</summary><ul class="m">{ lv_raw }</ul></details>|.
  ENDMETHOD.
  METHOD build_response_html.

    TYPES: BEGIN OF ty_kv,
             key TYPE string,
             val TYPE string,
           END OF ty_kv.
    DATA: lt_kv    TYPE STANDARD TABLE OF ty_kv WITH EMPTY KEY,
          lt_msg   TYPE string_table,
          lv_sum   TYPE string,
          lv_more  TYPE string,
          lv_msgs  TYPE string,
          lv_hist  TYPE string,
          lv_body  TYPE string,
          lv_level TYPE i,
          lv_fail  TYPE i.

    lv_body = is_out-responsepayload.

    "1. Flatten all "key": value pairs of the JSON response
    FIND ALL OCCURRENCES OF PCRE '"([A-Za-z0-9_]+)"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|(-?[0-9][0-9.eE+-]*|true|false))'
         IN lv_body RESULTS DATA(lt_res).
    LOOP AT lt_res INTO DATA(ls_res).
      READ TABLE ls_res-submatches INTO DATA(ls_k) INDEX 1.
      READ TABLE ls_res-submatches INTO DATA(ls_s) INDEX 2.
      READ TABLE ls_res-submatches INTO DATA(ls_p) INDEX 3.
      DATA(ls_kv) = VALUE ty_kv( key = substring( val = lv_body off = ls_k-offset len = ls_k-length ) ).
      IF ls_s-offset GE 0 AND ls_s-length GT 0.
        ls_kv-val = substring( val = lv_body off = ls_s-offset len = ls_s-length ).
      ELSEIF ls_p-offset GE 0 AND ls_p-length GT 0.
        ls_kv-val = substring( val = lv_body off = ls_p-offset len = ls_p-length ).
      ENDIF.
      REPLACE ALL OCCURRENCES OF '\"' IN ls_kv-val WITH '"'.
      REPLACE ALL OCCURRENCES OF '\/' IN ls_kv-val WITH '/'.
      REPLACE ALL OCCURRENCES OF '\n' IN ls_kv-val WITH cl_abap_char_utilities=>newline.
      CHECK ls_kv-val IS NOT INITIAL.
      APPEND ls_kv TO lt_kv.
    ENDLOOP.

    "2. Summary (known fields, first occurrence, fixed order)
    DATA(lt_order) = VALUE string_table( ( |status| ) ( |id| ) ( |referenceId| ) ( |messageId| )
                                         ( |instanceIdentifier| ) ( |documentTypeID| ) ( |processID| )
                                         ( |transmissionType| ) ( |senderParticipantID| )
                                         ( |receiverParticipantID| ) ( |serviceProviderId| ) ( |createdDate| ) ).
    LOOP AT lt_order INTO DATA(lv_ord).
      LOOP AT lt_kv INTO ls_kv.
        CHECK to_upper( ls_kv-key ) EQ to_upper( lv_ord ).
        lv_sum = lv_sum && |<tr><td>{ h( resp_label( ls_kv-key ) ) }</td>| &&
                           |<td>{ h( resp_value( iv_key = ls_kv-key iv_val = ls_kv-val ) ) }</td></tr>|.
        EXIT.
      ENDLOOP.
    ENDLOOP.

    "3. Messages / error details (split multi-part error texts)
    LOOP AT lt_kv INTO ls_kv.
      DATA(lv_ukey) = to_upper( ls_kv-key ).
      CHECK lv_ukey EQ 'MESSAGE'      OR lv_ukey EQ 'ERRORDETAILS'     OR lv_ukey EQ 'REASON' OR
            lv_ukey EQ 'DESCRIPTION'  OR lv_ukey EQ 'ERRORMESSAGE'     OR
            lv_ukey EQ 'ERRORDESCRIPTION' OR lv_ukey EQ 'DETAIL'.
      DATA(lv_txt) = ls_kv-val.
      REPLACE ALL OCCURRENCES OF '##' IN lv_txt WITH cl_abap_char_utilities=>newline.
      SPLIT lv_txt AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_part).
      LOOP AT lt_part INTO DATA(lv_part).
        CONDENSE lv_part.
        CHECK lv_part IS NOT INITIAL.
        READ TABLE lt_msg TRANSPORTING NO FIELDS WITH KEY table_line = lv_part.
        CHECK sy-subrc NE 0.
        APPEND lv_part TO lt_msg.
      ENDLOOP.
    ENDLOOP.
    "3a. errorDetails / errors returned as an array of plain strings
    FIND ALL OCCURRENCES OF PCRE '(?i)"(?:errorDetails|errors?|details)"\s*:\s*\[([^\]]*)\]'
         IN lv_body RESULTS DATA(lt_arr).
    LOOP AT lt_arr INTO DATA(ls_arr).
      READ TABLE ls_arr-submatches INTO DATA(ls_am) INDEX 1.
      CHECK sy-subrc EQ 0 AND ls_am-length GT 0.
      DATA(lv_arr) = substring( val = lv_body off = ls_am-offset len = ls_am-length ).
      CHECK lv_arr NS '{'.                 "array of objects: already handled above
      FIND ALL OCCURRENCES OF PCRE '"((?:[^"\\]|\\.)*)"' IN lv_arr RESULTS DATA(lt_str).
      LOOP AT lt_str INTO DATA(ls_str).
        READ TABLE ls_str-submatches INTO DATA(ls_sm) INDEX 1.
        CHECK sy-subrc EQ 0 AND ls_sm-length GT 0.
        DATA(lv_s) = substring( val = lv_arr off = ls_sm-offset len = ls_sm-length ).
        REPLACE ALL OCCURRENCES OF '\"' IN lv_s WITH '"'.
        CONDENSE lv_s.
        CHECK lv_s IS NOT INITIAL.
        READ TABLE lt_msg TRANSPORTING NO FIELDS WITH KEY table_line = lv_s.
        CHECK sy-subrc NE 0.
        APPEND lv_s TO lt_msg.
      ENDLOOP.
    ENDLOOP.
    LOOP AT lt_msg INTO DATA(lv_msg).
      lv_msgs = lv_msgs && |<li>{ h( lv_msg ) }</li>|.
    ENDLOOP.

    "3b. PINT AE rule violations -> structured error view (docs.peppol.eu/poac/ae/pint-ae)
    DATA(lv_rules) = rule_errors_html( it_msg = lt_msg
                                       iv_cn  = xsdbool( is_out-einvoicetype = '381' ) ).

    "4. Any other returned fields
    LOOP AT lt_kv INTO ls_kv.
      lv_ukey = to_upper( ls_kv-key ).
      CHECK lv_ukey NE 'MESSAGE'      AND lv_ukey NE 'ERRORDETAILS'     AND lv_ukey NE 'REASON' AND
            lv_ukey NE 'DESCRIPTION'  AND lv_ukey NE 'ERRORMESSAGE'     AND
            lv_ukey NE 'ERRORDESCRIPTION' AND lv_ukey NE 'DETAIL'.
      READ TABLE lt_order TRANSPORTING NO FIELDS WITH KEY table_line = ls_kv-key.
      CHECK sy-subrc NE 0.
      lv_more = lv_more && |<tr><td>{ h( resp_label( ls_kv-key ) ) }</td>| &&
                           |<td>{ h( resp_value( iv_key = ls_kv-key iv_val = ls_kv-val ) ) }</td></tr>|.
    ENDLOOP.

    "5. Processing history (step log)
    "Processing sequence: date / time, then C1, C2, C3 Sent, C3 Accepted,
    "C4, C5 Reported, C5 Accepted - same order as the processing log
    TYPES: BEGIN OF ty_hist,
             sortkey TYPE string,
             msgty   TYPE zeinvoice_error-msgty,
             message TYPE string,
           END OF ty_hist.
    DATA lt_hist TYPE STANDARD TABLE OF ty_hist WITH EMPTY KEY.

    LOOP AT gt_errors INTO DATA(ls_log) USING KEY doc
         WHERE bukrs = is_out-companycode AND vbeln = is_out-sapdocument AND
               gjahr = is_out-fiscalyear  AND type  = is_out-type.
      DATA(lv_hmsg) = CONV string( ls_log-message ).
      DATA(lv_rank) = `0`.
      FIND PCRE '^C([1-5]):' IN lv_hmsg SUBMATCHES DATA(lv_hc).
      IF sy-subrc EQ 0.                                "older log lines 'Cn: ...'
        lv_rank = SWITCH #( lv_hc WHEN '1' THEN `1` WHEN '2' THEN `2` WHEN '3' THEN `3`
                                  WHEN '4' THEN `5` WHEN '5' THEN `6` ELSE `0` ).
      ELSE.
        lv_rank = COND #( WHEN lv_hmsg CS 'Corner 1'              THEN `1`
                          WHEN lv_hmsg CS 'Corner 2'              THEN `2`
                          WHEN lv_hmsg CS 'Sent to Buyer'         THEN `3`
                          WHEN lv_hmsg CS 'Accepted by Buyer' THEN `4`
                          WHEN lv_hmsg CS 'Delivered to Buyer'    THEN `5`
                          WHEN lv_hmsg CS 'Reported to FTA'       THEN `6`
                          WHEN lv_hmsg CS 'Accepted by FTA'   THEN `7`
                          ELSE `0` ).
      ENDIF.
      FIND PCRE '(\d{4})-(\d{2})-(\d{2})\s+(\d{2}:\d{2}:\d{2})' IN lv_hmsg
           SUBMATCHES DATA(lv_hy) DATA(lv_hm) DATA(lv_hd) DATA(lv_ht).
      DATA(lv_hkey) = COND string( WHEN sy-subrc EQ 0 THEN |{ lv_hy }{ lv_hm }{ lv_hd }{ lv_ht }|
                                   ELSE `99999999` ).
      APPEND VALUE #( sortkey = |{ lv_hkey }{ lv_rank }{ ls_log-code }|
                      msgty   = ls_log-msgty
                      message = lv_hmsg ) TO lt_hist.
    ENDLOOP.
    SORT lt_hist BY sortkey.

    LOOP AT lt_hist INTO DATA(ls_h).
      DATA(lv_dot) = SWITCH string( ls_h-msgty WHEN 'S' THEN 'ok' WHEN 'E' THEN 'ko' WHEN 'W' THEN 'wt' ELSE 'na' ).
      DATA(lv_lbl) = SWITCH string( ls_h-msgty WHEN 'S' THEN 'Done' WHEN 'E' THEN 'Error' WHEN 'W' THEN 'Warning' ELSE 'Info' ).
      lv_hist = lv_hist && |<tr><td><span class="dot { lv_dot }"></span>{ lv_lbl }</td>| &&
                           |<td>{ h( ls_h-message ) }</td></tr>|.
    ENDLOOP.

    "6. Overall result banner - overall status + latest corner status
    DATA(lv_bcls) = SWITCH string( is_out-zzoverall_status
                      WHEN gc_ov-success     THEN 'ok'
                      WHEN gc_ov-failed      THEN 'ko'
                      WHEN gc_ov-in_progress THEN 'wt'
                      ELSE COND #( WHEN is_out-messagetype EQ 'E' THEN 'ko' ELSE 'na' ) ).
    DATA(lv_head) = SWITCH string( is_out-zzoverall_status
                      WHEN gc_ov-success     THEN |SUCCESS - { is_out-stattext }|
                      WHEN gc_ov-failed      THEN |FAILED - { is_out-stattext }|
                      WHEN gc_ov-in_progress THEN |IN PROGRESS - { is_out-stattext }|
                      ELSE COND #( WHEN is_out-messagetype EQ 'E' THEN |Not submitted - see processing history| ELSE |Not yet submitted| ) ).
    DATA(lv_next) = SWITCH string( is_out-messagetype
                      WHEN 'E' THEN |Correct the issues listed below and submit the document again.|
                      WHEN 'W' THEN |Press Submit again later to fetch the latest status from the ASP.|
                      WHEN 'S' THEN |No further action required.|
                      ELSE |Select the document and press Submit.| ).

    DATA(lv_css) =
      'body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;line-height:1.4;color:#1d2d3e;background:#f5f6f7;margin:0}' &&
      'table{font-size:inherit;color:inherit}' &&
      '*{box-sizing:border-box}.doc{min-width:720px;max-width:1000px;background:#fff;margin:8px auto;padding:16px 20px;border:1px solid #d9d9d9;border-radius:6px}' &&
      'h2{font-size:15px;margin:16px 0 6px;color:#0a6ed1}' &&
      '.ban{border-radius:6px;padding:12px 14px;border:1px solid}.ban b{font-size:16px;display:block;margin-bottom:3px}' &&
      '.ban.ok{background:#e8f5e9;border-color:#2b7d2b}.ban.ko{background:#fdecea;border-color:#bb0000}' &&
      '.ban.wt{background:#fff8e1;border-color:#e9730c}.ban.na{background:#f5f6f7;border-color:#d9d9d9}' &&
      'table{width:100%;border-collapse:collapse}td{padding:5px 6px;border-bottom:1px solid #eee;vertical-align:top}' &&
      'td:first-child{color:#6a6d70;width:200px}' &&
      'ul.m{margin:4px 0;padding-left:18px}ul.m li{margin:3px 0}' &&
      '.mbox{border-radius:4px;padding:6px 10px;background:#f0f6fd;border-left:4px solid #0a6ed1}' &&
      '.mbox.ko{background:#fdecea;border-left-color:#bb0000}' &&
      '.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}' &&
      '.dot.ok{background:#2b7d2b}.dot.ko{background:#bb0000}.dot.wt{background:#e9730c}.dot.na{background:#8c8c8c}' &&
      'pre{white-space:pre-wrap;word-break:break-all;background:#f5f6f7;padding:8px;border-radius:4px;font-size:11px}' &&
      'table.err{margin-top:8px;border:1px solid #e5e5e5}table.err th{background:#f5f6f7;text-align:left;padding:6px;font-weight:600;border-bottom:1px solid #d9d9d9}' &&
      'table.err td:first-child{width:28px;color:#6a6d70}table.err td:nth-child(2){width:170px}table.err td:nth-child(3){width:80px}table.err td:nth-child(5){width:250px}' &&
      '.cat{font-size:11px;color:#6a6d70}.cnt{font-size:11px;color:#6a6d70}a{color:#0a6ed1}' &&
      '.sev{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:600;color:#fff}.sev.f{background:#bb0000}.sev.w{background:#e9730c}' &&
      '.fix{margin-top:6px;padding:5px 8px;background:#fff8e1;border-left:3px solid #e9730c;border-radius:3px}.cl{margin-top:4px;font-size:12px}' &&
      '.chip{margin:0 0 3px;padding:2px 6px;background:#f0f6fd;border-radius:3px;font-size:12px}.src{margin-top:6px;font-size:11px;color:#6a6d70}' &&
      'summary{cursor:pointer;color:#0a6ed1;margin-top:14px}'.

    rv_html =
      |{ gc_html_head }{ gc_scroll_css }{ lv_css }</style></head><body><div id="scr"><div class="doc">| &&
      |<div class="ban { lv_bcls }"><b>{ h( lv_head ) }</b>| &&
      |Document { h( |{ is_out-sapdocument ALPHA = OUT }| ) } / { is_out-fiscalyear } - | &&
      |Overall status { h( COND string( WHEN is_out-zzoverall_status IS NOT INITIAL THEN is_out-zzoverall_status ELSE `-` ) ) }<br>{ h( lv_next ) }</div>| &&
      `<style>.cs{display:flex;gap:6px;margin:8px 0 4px}.cs .c{flex:1;min-width:0;border:1px solid #d9d9d9;border-radius:4px;padding:6px 7px;font-size:11px;background:#f5f6f7}` &&
      `.cs .c b{display:block;margin-bottom:2px}.cs .c.ok{background:#e8f5e9;border-color:#2b7d2b}.cs .c.ko{background:#fdecea;border-color:#bb0000}` &&
      `.cs .c.wt{background:#fff8e1;border-color:#e9730c}td.sm{font-size:11px;word-break:break-all}table.legs td:first-child{width:auto}</style>` &&
      |<h2>5-Corner status</h2><div class="cs">{ corner_strip_html( is_out ) }</div>| &&
      COND string( WHEN lv_rules IS NOT INITIAL THEN lv_rules
                   WHEN lv_msgs IS NOT INITIAL
                   THEN |<h2>{ COND string( WHEN is_out-messagetype EQ 'E' THEN 'What went wrong' ELSE 'ASP message' ) }</h2>| &&
                        |<div class="mbox { COND string( WHEN is_out-messagetype EQ 'E' THEN 'ko' ) }"><ul class="m">{ lv_msgs }</ul></div>| ) &&
      `<style>table.seq th{background:#f5f6f7;text-align:left;padding:6px;font-weight:600;border-bottom:1px solid #d9d9d9}table.seq td.nw{white-space:nowrap}</style>` &&
      `<style>table.seq td:first-child{width:24px;color:#6a6d70}table.seq td:nth-child(2){width:36px}table.seq td:nth-child(3){width:40%}</style>` &&
      |<h2>Corner responses (processing sequence)</h2>{ corner_responses_html( is_out ) }| &&
                "Processing history is not shown to end users (log: ZEINVOICE_ERROR)
      COND string( WHEN lv_body IS NOT INITIAL
                   THEN |<details><summary>Show technical response (raw)</summary><pre>{ h( lv_body ) }</pre></details>| ) &&
      |</div></div></body></html>|.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* LCL_POPUP : resizable popup (dialog box container) for the HTML pages
*----------------------------------------------------------------------*
CLASS lcl_popup DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA go_box TYPE REF TO cl_gui_dialogbox_container.
    CLASS-METHODS:
      show     IMPORTING iv_html  TYPE string
                         iv_title TYPE csequence,
      on_close FOR EVENT close OF cl_gui_dialogbox_container
        IMPORTING sender.
ENDCLASS.

CLASS lcl_popup IMPLEMENTATION.

  METHOD show.
    "Only one popup at a time
    IF go_box IS BOUND.
      go_box->free( ).
      CLEAR go_box.
    ENDIF.

    DATA lv_cap TYPE text100.
    lv_cap = iv_title.

    "Popup sized to fit standard screens; the user can move / resize it and
    "the HTML page always fills the popup (scrollbars inside the page)
    go_box = NEW cl_gui_dialogbox_container( width   = 1000
                                             height  = 600
                                             top     = 20
                                             left    = 40
                                             caption = lv_cap ).
    SET HANDLER on_close FOR go_box.

    DATA lv_title TYPE cl_abap_browser=>title.
    lv_title = iv_title.
    cl_abap_browser=>show_html( html_string = iv_html
                                title       = lv_title
                                container   = go_box ).
  ENDMETHOD.

  METHOD on_close.
    sender->free( ).
    CLEAR go_box.
  ENDMETHOD.

ENDCLASS.
