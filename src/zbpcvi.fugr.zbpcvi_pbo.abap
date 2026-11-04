FUNCTION zbpcvi_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"----------------------------------------------------------------------

  DATA: lt_knb1     TYPE TABLE OF knb1,
        lv_compcode TYPE bukrs.

* E-Invoice moved to Customer Company Code level (KNB1)
* Step 1: Receive company code data from CVI memory (XO)
  lv_compcode = cvi_bdt_adapter=>get_current_company_code( ).
  IF lv_compcode IS INITIAL.
    CLEAR gs_knb1.
  ELSE.
    cvi_bdt_adapter=>data_pbo_with_company_code(
      EXPORTING
        i_table_name = 'KNB1'
      IMPORTING
        e_data_table = lt_knb1[] ).
    READ TABLE lt_knb1 INTO gs_knb1 WITH KEY bukrs = lv_compcode.
    IF sy-subrc <> 0.
      CLEAR gs_knb1.
    ENDIF.
  ENDIF.

ENDFUNCTION.
