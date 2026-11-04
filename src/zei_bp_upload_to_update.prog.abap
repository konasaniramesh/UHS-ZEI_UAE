*&---------------------------------------------------------------------*
*& Report ZEI_BP_UPLOAD_TO_UPDATE
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zei_bp_upload_to_update.

"Upload file format (sequence of the .xlsx columns)
TYPES: BEGIN OF ty_template,
         partner     TYPE bu_partner,
         name1       TYPE text40,
         name2       TYPE text40,
         name3       TYPE text40,
         name4       TYPE text40,
         sterm1      TYPE bu_sort1,
         legal_enty  TYPE bu_legenty,
         ind_sector  TYPE bu_indsect,
         houneno     TYPE ad_hsnm1,
         street      TYPE ad_street,
         street2     TYPE ad_strspp1,
         street3     TYPE ad_strspp2,
         street4     TYPE ad_strspp3,
         pobox       TYPE ad_pobx,
         postal_code TYPE ad_pstcd1,
         city        TYPE ad_city1,
         region      TYPE regio,
         country     TYPE land1,
         trn         TYPE bptaxnum,
         tin         TYPE bptaxnum,
         legalid     TYPE bu_id_number,
         lvalidf     TYPE char10,
         lvalidt     TYPE char10,
         peppolid    TYPE bu_id_number,
         pvalidf     TYPE char10,
         pvalidt     TYPE char10,
         bukrs       TYPE bukrs,    "Company Code - E-Invoice fields (KNB1)
         btype       TYPE char5,
         zone_type   TYPE char1,
       END OF ty_template.

"Upload file format + processing status
TYPES: BEGIN OF ty_data.
         INCLUDE TYPE ty_template.
TYPES:   icon(4) TYPE c,
         message TYPE bapi_msg,
       END OF ty_data.

DATA: gt_ftable   TYPE TABLE OF file_table,
      gv_rc       TYPE i,
      gt_filedata TYPE TABLE OF ty_data,
      gs_filedata TYPE ty_data.

FIELD-SYMBOLS: <fs_value> TYPE any.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: rb_upl RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND ucom,
              rb_tmp RADIOBUTTON GROUP g1.
  PARAMETERS: p_file TYPE localfile MODIF ID upl.
SELECTION-SCREEN END OF BLOCK b1.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-group1 EQ 'UPL'.
      screen-active = COND #( WHEN rb_tmp EQ abap_true THEN 0 ELSE 1 ).
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.

  REFRESH: gt_ftable.
  CLEAR: gv_rc.

  CALL METHOD cl_gui_frontend_services=>file_open_dialog
    EXPORTING
      window_title            = 'Select File'
      file_filter             = cl_gui_frontend_services=>filetype_excel
    CHANGING
      file_table              = gt_ftable
      rc                      = gv_rc
    EXCEPTIONS
      file_open_dialog_failed = 1
      cntl_error              = 2
      error_no_gui            = 3
      not_supported_by_gui    = 4
      OTHERS                  = 5.

  IF sy-subrc EQ 0.
    p_file = VALUE #( gt_ftable[ 1 ]-filename OPTIONAL ).
  ENDIF.

START-OF-SELECTION.
  "Download the upload file format (.xlsx)
  IF rb_tmp EQ abap_true.
    PERFORM download_template.
    RETURN.
  ENDIF.


  IF p_file IS INITIAL.
    MESSAGE 'Select .xlsx file to proceed' TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  PERFORM get_data_from_file.
  PERFORM update_bp.
  PERFORM display_output.
*&---------------------------------------------------------------------*
*& Form get_data_from_file
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*& -->  p1        text
*& <--  p2        text
*&---------------------------------------------------------------------*
FORM get_data_from_file.

  DATA: lv_file       TYPE string,
        lt_records    TYPE solix_tab,
        lv_filelength TYPE i,
        lv_xstring    TYPE xstring,
        lo_excel      TYPE REF TO cl_fdt_xl_spreadsheet,
        lv_index      TYPE i.

  FIELD-SYMBOLS: <lt_data> TYPE STANDARD TABLE.

  lv_file = p_file.

  CALL FUNCTION 'GUI_UPLOAD'
    EXPORTING
      filename                = lv_file
      filetype                = 'BIN'
    IMPORTING
      filelength              = lv_filelength
*     HEADER                  =
    TABLES
      data_tab                = lt_records
    EXCEPTIONS
      file_open_error         = 1
      file_read_error         = 2
      no_batch                = 3
      gui_refuse_filetransfer = 4
      invalid_type            = 5
      no_authority            = 6
      unknown_error           = 7
      bad_data_format         = 8
      header_not_allowed      = 9
      separator_not_allowed   = 10
      header_too_long         = 11
      unknown_dp_error        = 12
      access_denied           = 13
      dp_out_of_memory        = 14
      disk_full               = 15
      dp_timeout              = 16
      OTHERS                  = 17.

  IF lt_records[] IS NOT INITIAL.

    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING
        input_length = lv_filelength
      IMPORTING
        buffer       = lv_xstring
      TABLES
        binary_tab   = lt_records
      EXCEPTIONS
        failed       = 1
        OTHERS       = 2.

    IF lv_xstring IS NOT INITIAL.

      "Below syntax is similar to CREATE OBJECT
      TRY.
          lo_excel = NEW cl_fdt_xl_spreadsheet(
            document_name = lv_file
            xdocument     = lv_xstring
          ).
        CATCH cx_fdt_excel_core. " FDT: Export/Import to Excel core errors
      ENDTRY.

      lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
        IMPORTING
          worksheet_names = DATA(lt_wsheets) "No. of Sheets will be depend on Excel Sheets
      ).

      IF lt_wsheets[] IS NOT INITIAL.

        DATA(ls_wsheets) = lt_wsheets[ 1 ].

        lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet(
          EXPORTING
            worksheet_name  = ls_wsheets
          RECEIVING
            itab            = DATA(lt_itab)
        ).

        ASSIGN lt_itab->* TO <lt_data>.

      ENDIF.

    ENDIF.

  ENDIF.

  REFRESH: gt_filedata.

  IF <lt_data> IS ASSIGNED AND
     <lt_data>[] IS NOT INITIAL.

    CLEAR: gs_filedata, lv_index.
    LOOP AT <lt_data> ASSIGNING FIELD-SYMBOL(<ls_data>).

      IF sy-tabix EQ 1.
        CONTINUE.
      ENDIF.

      DO.
        ASSIGN COMPONENT sy-index OF STRUCTURE <ls_data> TO FIELD-SYMBOL(<fs_dvalue>).
        IF sy-subrc EQ 0.
          ASSIGN COMPONENT sy-index OF STRUCTURE gs_filedata TO FIELD-SYMBOL(<fs_tvalue>).
          <fs_tvalue> = <fs_dvalue>.
        ELSE.
          EXIT.
        ENDIF.
      ENDDO.

      gs_filedata-partner = |{ gs_filedata-partner ALPHA = IN }|.

      APPEND gs_filedata TO gt_filedata.
      CLEAR: gs_filedata.

    ENDLOOP.

  ENDIF.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form update_bp
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*& -->  p1        text
*& <--  p2        text
*&---------------------------------------------------------------------*
FORM update_bp.

  DATA: lt_data      TYPE cvis_ei_extern_t,
        ls_data      TYPE cvis_ei_extern,
        lv_fromdate  TYPE dats,
        lv_todate    TYPE dats,
        lv_sydatum_1 TYPE dats.

  IF gt_filedata[] IS NOT INITIAL.

    SELECT *
           FROM but000
           INTO TABLE @DATA(lt_but000)
           FOR ALL ENTRIES IN @gt_filedata
           WHERE partner EQ @gt_filedata-partner.

    SELECT *
           FROM knb1
           INTO TABLE @DATA(lt_knb1)
           FOR ALL ENTRIES IN @gt_filedata
           WHERE kunnr EQ @gt_filedata-partner AND
                 bukrs EQ @gt_filedata-bukrs.

    SELECT *
           FROM but020
           INTO TABLE @DATA(lt_but020)
           FOR ALL ENTRIES IN @gt_filedata
           WHERE partner EQ @gt_filedata-partner.

    SELECT *
           FROM but0id
           INTO TABLE @DATA(lt_but0id)
           FOR ALL ENTRIES IN @gt_filedata
           WHERE partner EQ @gt_filedata-partner AND
                 type    IN ('AELRID', 'PAP001').

    SELECT *
           FROM dfkkbptaxnum
           INTO TABLE @DATA(lt_taxid)
           FOR ALL ENTRIES IN @gt_filedata
           WHERE partner EQ @gt_filedata-partner AND
                 taxtype IN ('AE0', 'AE1').

    SELECT *
           FROM zeinv_busi_type
           INTO TABLE @DATA(lt_btype).

    SORT: lt_but000 BY partner    ASCENDING,
          lt_but020 BY addrnumber ASCENDING,
          lt_but0id BY partner ASCENDING type ASCENDING idnumber ASCENDING,
          lt_taxid  BY partner ASCENDING taxtype ASCENDING,
          lt_btype  BY bukrs ASCENDING businesstype ASCENDING.

  ENDIF.

  LOOP AT gt_filedata ASSIGNING FIELD-SYMBOL(<ls_filedata>).

    ls_data-partner-header-object_task                  = 'U'.
    ls_data-partner-header-object_instance-bpartner     = VALUE #( lt_but000[ partner = <ls_filedata>-partner ]-partner OPTIONAL ).
    ls_data-partner-header-object_instance-bpartnerguid = VALUE #( lt_but000[ partner = <ls_filedata>-partner ]-partner_guid OPTIONAL ).

    IF ls_data-partner-header-object_instance-bpartner IS INITIAL.
      <ls_filedata>-icon    = icon_led_red.
      <ls_filedata>-message = |Business Partner doesn't exist|.
      CLEAR: ls_data.
      CONTINUE.
    ENDIF.

    ls_data-partner-central_data-common-data-bp_centraldata-searchterm1     = <ls_filedata>-sterm1.
    ls_data-partner-central_data-common-data-bp_centraldata-partnerlanguage = sy-langu.

    ls_data-partner-central_data-common-datax-bp_centraldata-searchterm1     = SWITCH #( <ls_filedata>-sterm1
                                                                                         WHEN space THEN abap_false
                                                                                         ELSE abap_true
                                                                                        ).
    ls_data-partner-central_data-common-datax-bp_centraldata-partnerlanguage = abap_true.

    IF VALUE #( lt_but000[ partner = <ls_filedata>-partner ]-type OPTIONAL ) EQ '1'. "Person

      ls_data-partner-central_data-common-data-bp_person-firstname           = <ls_filedata>-name1.
      ls_data-partner-central_data-common-data-bp_person-middlename          = <ls_filedata>-name2.
      ls_data-partner-central_data-common-data-bp_person-lastname            = <ls_filedata>-name3.
      ls_data-partner-central_data-common-data-bp_person-correspondlanguage  = sy-langu.
      ls_data-partner-central_data-common-datax-bp_person-firstname          = SWITCH #( <ls_filedata>-name1
                                                                                         WHEN space THEN abap_false
                                                                                         ELSE abap_true
                                                                                        ).
      ls_data-partner-central_data-common-datax-bp_person-middlename         = SWITCH #( <ls_filedata>-name2
                                                                                         WHEN space THEN abap_false
                                                                                         ELSE abap_true
                                                                                        ).
      ls_data-partner-central_data-common-datax-bp_person-lastname           = SWITCH #( <ls_filedata>-name3
                                                                                         WHEN space THEN abap_false
                                                                                         ELSE abap_true
                                                                                        ).
      ls_data-partner-central_data-common-datax-bp_person-correspondlanguage = abap_true.

    ELSE. "Organization

      ls_data-partner-central_data-common-data-bp_organization-name1     = <ls_filedata>-name1.
      ls_data-partner-central_data-common-data-bp_organization-name2     = <ls_filedata>-name2.
      ls_data-partner-central_data-common-data-bp_organization-name3     = <ls_filedata>-name3.
      ls_data-partner-central_data-common-data-bp_organization-name4     = <ls_filedata>-name4.
      ls_data-partner-central_data-common-data-bp_organization-legalform = <ls_filedata>-legal_enty.

      ls_data-partner-central_data-common-datax-bp_organization-name1 = SWITCH #( <ls_filedata>-name1
                                                                                  WHEN space THEN abap_false
                                                                                  ELSE abap_true
                                                                                 ).
      ls_data-partner-central_data-common-datax-bp_organization-name2 = SWITCH #( <ls_filedata>-name2
                                                                                  WHEN space THEN abap_false
                                                                                  ELSE abap_true
                                                                                 ).
      ls_data-partner-central_data-common-datax-bp_organization-name3 = SWITCH #( <ls_filedata>-name3
                                                                                  WHEN space THEN abap_false
                                                                                  ELSE abap_true
                                                                                 ).
      ls_data-partner-central_data-common-datax-bp_organization-name4 = SWITCH #( <ls_filedata>-name4
                                                                                  WHEN space THEN abap_false
                                                                                  ELSE abap_true
                                                                                 ).
      ls_data-partner-central_data-common-datax-bp_organization-legalform = SWITCH #( <ls_filedata>-legal_enty
                                                                                      WHEN space THEN abap_false
                                                                                      ELSE abap_true
                                                                                     ).
      ls_data-partner-central_data-common-datax-bp_organization-industrysector = SWITCH #( <ls_filedata>-ind_sector
                                                                                           WHEN space THEN abap_false
                                                                                           ELSE abap_true
                                                                                          ).

    ENDIF.

    "E-Invoice fields - Customer Company Code level (KNB1), previously BUT000
    IF <ls_filedata>-btype     IS NOT INITIAL OR
       <ls_filedata>-zone_type IS NOT INITIAL.

      IF <ls_filedata>-bukrs IS INITIAL.
        <ls_filedata>-icon    = icon_led_red.
        <ls_filedata>-message = |Company Code is required for E-Invoice fields|.
        CLEAR: ls_data.
        CONTINUE.
      ENDIF.

      "Customer must exist in the Company Code
      READ TABLE lt_knb1 TRANSPORTING NO FIELDS
                         WITH KEY kunnr = <ls_filedata>-partner
                                  bukrs = <ls_filedata>-bukrs.
      IF sy-subrc NE 0.
        <ls_filedata>-icon    = icon_led_red.
        <ls_filedata>-message = |Customer { <ls_filedata>-partner ALPHA = OUT } is not extended to Company Code { <ls_filedata>-bukrs }|.
        CLEAR: ls_data.
        CONTINUE.
      ENDIF.

      ls_data-customer-header-object_instance-kunnr = <ls_filedata>-partner.
      ls_data-customer-header-object_task           = 'U'.

      APPEND VALUE #( task                 = 'U'
                      data_key-bukrs       = <ls_filedata>-bukrs
                      data-zzeinvoice      = VALUE #( lt_btype[ bukrs = <ls_filedata>-bukrs businesstype = <ls_filedata>-btype ]-active OPTIONAL )
                      data-zzbusinesstype  = <ls_filedata>-btype
                      data-zzzonetype      = <ls_filedata>-zone_type
                      datax-zzeinvoice     = SWITCH #( <ls_filedata>-btype WHEN space THEN abap_false ELSE abap_true )
                      datax-zzbusinesstype = SWITCH #( <ls_filedata>-btype WHEN space THEN abap_false ELSE abap_true )
                      datax-zzzonetype     = SWITCH #( <ls_filedata>-zone_type WHEN space THEN abap_false ELSE abap_true )
                    ) TO ls_data-customer-company_data-company.

    ENDIF.

    "Address
    REFRESH: ls_data-partner-central_data-address-addresses.
    APPEND VALUE #( task                         = 'U'
                    data_key-guid                = VALUE #( lt_but020[ partner = <ls_filedata>-partner ]-address_guid OPTIONAL )
                    data_key-operation           = 'XXDFLT' "Standard "Operations are store in table TB008S

                    data-postal-data-house_no    = <ls_filedata>-houneno
                    data-postal-data-street      = <ls_filedata>-street
                    data-postal-data-str_suppl1  = <ls_filedata>-street2
                    data-postal-data-str_suppl2  = <ls_filedata>-street3
                    data-postal-data-str_suppl3  = <ls_filedata>-street4
                    data-postal-data-po_box      = <ls_filedata>-pobox
                    data-postal-data-postl_cod1  = <ls_filedata>-postal_code
                    data-postal-data-city        = <ls_filedata>-city
                    data-postal-data-region      = <ls_filedata>-region
                    data-postal-data-country     = <ls_filedata>-country
                    data-postal-data-langu       = sy-langu

                    data-postal-datax-house_no    = SWITCH #( <ls_filedata>-houneno     WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-street      = SWITCH #( <ls_filedata>-street      WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-str_suppl1  = SWITCH #( <ls_filedata>-street2     WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-str_suppl2  = SWITCH #( <ls_filedata>-street3     WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-str_suppl3  = SWITCH #( <ls_filedata>-street4     WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-po_box      = SWITCH #( <ls_filedata>-pobox       WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-postl_cod1  = SWITCH #( <ls_filedata>-postal_code WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-city        = SWITCH #( <ls_filedata>-city        WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-region      = SWITCH #( <ls_filedata>-region      WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-country     = SWITCH #( <ls_filedata>-country     WHEN space THEN abap_false ELSE abap_true )
                    data-postal-datax-langu       = abap_true
                   ) TO ls_data-partner-central_data-address-addresses.

    "Tax Numbers
    REFRESH: ls_data-partner-central_data-taxnumber-taxnumbers.
    IF <ls_filedata>-trn IS NOT INITIAL.
      APPEND VALUE #( task               = SWITCH #( VALUE #( lt_taxid[ partner = <ls_filedata>-partner taxtype = 'AE0' ]-taxtype OPTIONAL )
                                                     WHEN 'AE0' THEN 'U'
                                                     ELSE 'I'
                                                    )
                      data_key-taxtype   = 'AE0'
                      data_key-taxnumber = <ls_filedata>-trn
                     ) TO ls_data-partner-central_data-taxnumber-taxnumbers.
    ENDIF.

    IF <ls_filedata>-tin IS NOT INITIAL.
      APPEND VALUE #( task               = SWITCH #( VALUE #( lt_taxid[ partner = <ls_filedata>-partner taxtype = 'AE1' ]-taxtype OPTIONAL )
                                                     WHEN 'AE1' THEN 'U'
                                                     ELSE 'I'
                                                    )
                      data_key-taxtype   = 'AE1'
                      data_key-taxnumber = <ls_filedata>-tin
                     ) TO ls_data-partner-central_data-taxnumber-taxnumbers.
    ENDIF.

    "Identification Numbers
    REFRESH: ls_data-partner-central_data-ident_number-ident_numbers.
    IF <ls_filedata>-legalid IS NOT INITIAL.
      LOOP AT lt_but0id INTO DATA(ls_but0id)
                        WHERE partner EQ <ls_filedata>-partner AND
                              type    EQ 'AELRID'.
        CLEAR: lv_fromdate, lv_todate, lv_sydatum_1.
        lv_sydatum_1 = sy-datum - 1.
        IF ls_but0id-idnumber EQ <ls_filedata>-legalid.
          lv_fromdate = |{ <ls_filedata>-lvalidf+6(4) }{ <ls_filedata>-lvalidf+3(2) }{ <ls_filedata>-lvalidf+0(2) }|.
          lv_todate   = |{ <ls_filedata>-lvalidt+6(4) }{ <ls_filedata>-lvalidt+3(2) }{ <ls_filedata>-lvalidt+0(2) }|.
        ELSE.
          lv_fromdate = COND #( WHEN ls_but0id-valid_date_from GT lv_sydatum_1 THEN lv_sydatum_1 ELSE ls_but0id-valid_date_from ).
          lv_fromdate = COND #( WHEN lv_fromdate EQ '00000000' THEN lv_sydatum_1 ELSE lv_fromdate ).
          lv_todate   = lv_sydatum_1.
        ENDIF.
        APPEND VALUE #( task                            = 'U'
                        data_key-identificationcategory = ls_but0id-type
                        data_key-identificationnumber   = ls_but0id-idnumber
                        data-identrydate                = COND #( WHEN ls_but0id-entry_date GT lv_fromdate
                                                                  THEN lv_fromdate
                                                                  ELSE COND #( WHEN ls_but0id-entry_date IS INITIAL
                                                                               THEN lv_fromdate
                                                                               ELSE ls_but0id-entry_date
                                                                               )
                                                                  )
                        data-idvalidfromdate            = lv_fromdate
                        data-idvalidtodate              = lv_todate
                        datax-identrydate               = abap_true
                        datax-idvalidfromdate           = abap_true
                        datax-idvalidtodate             = abap_true
                       ) TO ls_data-partner-central_data-ident_number-ident_numbers.
        CLEAR: ls_but0id.
      ENDLOOP.

      IF <ls_filedata>-legalid NE VALUE #( lt_but0id[ partner = <ls_filedata>-partner type = 'AELRID' idnumber = <ls_filedata>-legalid ]-idnumber OPTIONAL ).
        lv_fromdate = |{ <ls_filedata>-lvalidf+6(4) }{ <ls_filedata>-lvalidf+3(2) }{ <ls_filedata>-lvalidf+0(2) }|.
        lv_todate   = |{ <ls_filedata>-lvalidt+6(4) }{ <ls_filedata>-lvalidt+3(2) }{ <ls_filedata>-lvalidt+0(2) }|.
        APPEND VALUE #( task                            = 'I'
                        data_key-identificationcategory = 'AELRID'
                        data_key-identificationnumber   = <ls_filedata>-legalid
                        data-identrydate                = sy-datum
                        data-idvalidfromdate            = lv_fromdate
                        data-idvalidtodate              = lv_todate
                        datax-identrydate               = abap_true
                        datax-idvalidfromdate           = abap_true
                        datax-idvalidtodate             = abap_true
                       ) TO ls_data-partner-central_data-ident_number-ident_numbers.
      ENDIF.
    ENDIF.

    IF <ls_filedata>-peppolid IS NOT INITIAL.
      LOOP AT lt_but0id INTO ls_but0id
                        WHERE partner EQ <ls_filedata>-partner AND
                              type    EQ 'PAP001'.
        CLEAR: lv_fromdate, lv_todate, lv_sydatum_1.
        lv_sydatum_1 = sy-datum - 1.
        IF ls_but0id-idnumber EQ <ls_filedata>-peppolid.
          lv_fromdate = |{ <ls_filedata>-pvalidf+6(4) }{ <ls_filedata>-pvalidf+3(2) }{ <ls_filedata>-pvalidf+0(2) }|.
          lv_todate   = |{ <ls_filedata>-pvalidt+6(4) }{ <ls_filedata>-pvalidt+3(2) }{ <ls_filedata>-pvalidt+0(2) }|.
        ELSE.
          lv_fromdate = COND #( WHEN ls_but0id-valid_date_from GT lv_sydatum_1 THEN lv_sydatum_1 ELSE ls_but0id-valid_date_from ).
          lv_fromdate = COND #( WHEN lv_fromdate EQ '00000000' THEN lv_sydatum_1 ELSE lv_fromdate ).
          lv_todate   = lv_sydatum_1.
        ENDIF.
        APPEND VALUE #( task                            = 'U'
                        data_key-identificationcategory = ls_but0id-type
                        data_key-identificationnumber   = ls_but0id-idnumber
                        data-identrydate                = COND #( WHEN ls_but0id-entry_date GT lv_fromdate
                                                                  THEN lv_fromdate
                                                                  ELSE COND #( WHEN ls_but0id-entry_date IS INITIAL
                                                                               THEN lv_fromdate
                                                                               ELSE ls_but0id-entry_date
                                                                               )
                                                                  )
                        data-idvalidfromdate            = lv_fromdate
                        data-idvalidtodate              = lv_todate
                        datax-identrydate               = abap_true
                        datax-idvalidfromdate           = abap_true
                        datax-idvalidtodate             = abap_true
                       ) TO ls_data-partner-central_data-ident_number-ident_numbers.
        CLEAR: ls_but0id, lv_fromdate, lv_todate.
      ENDLOOP.
      IF <ls_filedata>-peppolid NE VALUE #( lt_but0id[ partner = <ls_filedata>-partner type = 'PAP001' idnumber = <ls_filedata>-peppolid ]-idnumber OPTIONAL ).
        lv_fromdate = |{ <ls_filedata>-pvalidf+6(4) }{ <ls_filedata>-pvalidf+3(2) }{ <ls_filedata>-pvalidf+0(2) }|.
        lv_todate   = |{ <ls_filedata>-pvalidt+6(4) }{ <ls_filedata>-pvalidt+3(2) }{ <ls_filedata>-pvalidt+0(2) }|.
        APPEND VALUE #( task                            = 'I'
                        data_key-identificationcategory = 'PAP001'
                        data_key-identificationnumber   = <ls_filedata>-peppolid
                        data-identrydate                = sy-datum
                        data-idvalidfromdate            = lv_fromdate
                        data-idvalidtodate              = lv_todate
                        datax-identrydate               = abap_true
                        datax-idvalidfromdate           = abap_true
                        datax-idvalidtodate             = abap_true
                       ) TO ls_data-partner-central_data-ident_number-ident_numbers.
      ENDIF.
    ENDIF.

    APPEND ls_data TO lt_data.

    IF lt_data[] IS NOT INITIAL.

      CALL METHOD cl_md_bp_maintain=>maintain
        EXPORTING
          i_data     = lt_data
          i_test_run = space
        IMPORTING
          e_return   = DATA(lt_return).

      DATA(ls_return) = VALUE #( lt_return[ 1 ] OPTIONAL ).

      LOOP AT ls_return-object_msg INTO DATA(ls_msg)
                                   WHERE type EQ 'A' OR
                                         type EQ 'E'.
        <ls_filedata>-icon    = icon_led_red.
        <ls_filedata>-message = ls_msg-message.
        CLEAR: ls_msg.
        EXIT.
      ENDLOOP.

      IF <ls_filedata>-icon NE icon_led_red.
        <ls_filedata>-icon    = icon_led_green.
        <ls_filedata>-message = |Sucessfully updated|.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = abap_true.
      ENDIF.

    ENDIF.

    REFRESH: lt_return, lt_data.
    CLEAR: ls_data.
  ENDLOOP.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_output
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*& -->  p1        text
*& <--  p2        text
*&---------------------------------------------------------------------*
FORM display_output.

  DATA: lt_fcat TYPE lvc_t_fcat,
        ls_layo TYPE lvc_s_layo.

  lt_fcat = VALUE #( ( fieldname = 'PARTNER'     scrtext_l = |Business Partner| convexit = 'ALPHA' )
                     ( fieldname = 'NAME1'       scrtext_l = |Name1/FirstName|                     )
                     ( fieldname = 'NAME2'       scrtext_l = |Name2/MiddleName|                    )
                     ( fieldname = 'NAME3'       scrtext_l = |Name3/LastName|                      )
                     ( fieldname = 'NAME4'       scrtext_l = |Name4|                               )
                     ( fieldname = 'STERM1'      scrtext_l = |Search Term1|                        )
                     ( fieldname = 'LEGAL_ENTY'  scrtext_l = |Legal Entity|                        )
                     ( fieldname = 'IND_SECTOR'  scrtext_l = |Industry Sector|                     )
                     ( fieldname = 'HOUNENO'     scrtext_l = |House No|                            )
                     ( fieldname = 'STREET'      scrtext_l = |Street|                              )
                     ( fieldname = 'STREET2'     scrtext_l = |Street2|                             )
                     ( fieldname = 'STREET3'     scrtext_l = |Street3|                             )
                     ( fieldname = 'STREET4'     scrtext_l = |Street4|                             )
                     ( fieldname = 'POBOX'       scrtext_l = |PO Box|                              )
                     ( fieldname = 'POSTAL_CODE' scrtext_l = |Postal Code|                         )
                     ( fieldname = 'CITY'        scrtext_l = |City|                                )
                     ( fieldname = 'REGION'      scrtext_l = |Region|                              )
                     ( fieldname = 'COUNTRY'     scrtext_l = |Country|                              )
                     ( fieldname = 'TRN'         scrtext_l = |TRN|                                 )
                     ( fieldname = 'TIN'         scrtext_l = |TIN|                                 )
                     ( fieldname = 'LEGALID'     scrtext_l = |Legal Registration ID|               )
                     ( fieldname = 'LVALIDF'     scrtext_l = |Legal Registration Valid From|       )
                     ( fieldname = 'LVALIDT'     scrtext_l = |Legal Registration Valid To|         )
                     ( fieldname = 'PEPPOLID'    scrtext_l = |Peppol ID|                           )
                     ( fieldname = 'PVALIDF'     scrtext_l = |Peppol ID Valid From|                )
                     ( fieldname = 'PVALIDT'     scrtext_l = |Peppol ID Valid To|                  )
                     ( fieldname = 'BUKRS'       scrtext_l = |Company Code|                        )
                     ( fieldname = 'BTYPE'       scrtext_l = |Business Type|                       )
                     ( fieldname = 'ZONE_TYPE'   scrtext_l = |Zone Type|                           )
                     ( fieldname = 'ICON'        scrtext_l = |Status|          just = 'C'          )
                     ( fieldname = 'MESSAGE'     scrtext_l = |Message|                             )
                    ).

  ls_layo-cwidth_opt = abap_true.
  ls_layo-no_rowmark = abap_true.
  ls_layo-no_toolbar = abap_true.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY_LVC'
    EXPORTING
      i_callback_program = sy-repid
      is_layout_lvc      = ls_layo
      it_fieldcat_lvc    = lt_fcat
    TABLES
      t_outtab           = gt_filedata
    EXCEPTIONS
      program_error      = 1
      OTHERS             = 2.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form download_template
*&---------------------------------------------------------------------*
*& Download the upload file format (.xlsx) - header row only
*&---------------------------------------------------------------------*
FORM download_template.

  DATA: lt_template TYPE STANDARD TABLE OF ty_template,
        lo_salv     TYPE REF TO cl_salv_table,
        lv_xstring  TYPE xstring,
        lt_solix    TYPE solix_tab,
        lv_size     TYPE i,
        lv_filename TYPE string,
        lv_path     TYPE string,
        lv_fullpath TYPE string,
        lv_action   TYPE i.

  "Column headers - same sequence as the upload file / TY_TEMPLATE
  DATA(lt_headers) = VALUE string_table(
    ( |Business Partner| ) ( |Name1/FirstName| ) ( |Name2/MiddleName| ) ( |Name3/LastName| )
    ( |Name4| ) ( |Search Term1| ) ( |Legal Entity| ) ( |Industry Sector| ) ( |House No| )
    ( |Street| ) ( |Street2| ) ( |Street3| ) ( |Street4| ) ( |PO Box| ) ( |Postal Code| )
    ( |City| ) ( |Region| ) ( |Country| ) ( |TRN| ) ( |TIN| ) ( |Legal Registration ID| )
    ( |Legal Reg. Valid From| ) ( |Legal Reg. Valid To| ) ( |Peppol ID| ) ( |Peppol ID Valid From| )
    ( |Peppol ID Valid To| ) ( |Company Code| ) ( |Business Type| ) ( |Zone Type| ) ).

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                              CHANGING  t_table      = lt_template ).

      DATA(lt_columns) = lo_salv->get_columns( )->get( ).
      LOOP AT lt_columns ASSIGNING FIELD-SYMBOL(<ls_column>).
        DATA(lv_header) = VALUE string( lt_headers[ sy-tabix ] OPTIONAL ).
        <ls_column>-r_column->set_long_text( CONV #( lv_header ) ).
        <ls_column>-r_column->set_medium_text( CONV #( lv_header ) ).
        <ls_column>-r_column->set_short_text( CONV #( lv_header ) ).
      ENDLOOP.

      lv_xstring = lo_salv->to_xml( xml_type = if_salv_bs_xml=>c_type_xlsx ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  CHECK lv_xstring IS NOT INITIAL.

  cl_gui_frontend_services=>file_save_dialog(
    EXPORTING
      window_title      = 'Save Upload File Format'
      default_extension = 'xlsx'
      default_file_name = 'BP_EInvoice_Upload_Format.xlsx'
      file_filter       = cl_gui_frontend_services=>filetype_excel
    CHANGING
      filename          = lv_filename
      path              = lv_path
      fullpath          = lv_fullpath
      user_action       = lv_action
    EXCEPTIONS
      OTHERS            = 1 ).

  IF sy-subrc NE 0 OR lv_action EQ cl_gui_frontend_services=>action_cancel.
    RETURN.
  ENDIF.

  lt_solix = cl_bcs_convert=>xstring_to_solix( iv_xstring = lv_xstring ).
  lv_size  = xstrlen( lv_xstring ).

  cl_gui_frontend_services=>gui_download(
    EXPORTING
      bin_filesize = lv_size
      filename     = lv_fullpath
      filetype     = 'BIN'
    CHANGING
      data_tab     = lt_solix
    EXCEPTIONS
      OTHERS       = 1 ).

  IF sy-subrc EQ 0.
    MESSAGE |File format downloaded to { lv_fullpath }| TYPE 'S'.
  ELSE.
    MESSAGE 'File format download failed' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.

ENDFORM.
