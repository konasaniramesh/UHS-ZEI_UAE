FUNCTION zbpcvi_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"----------------------------------------------------------------------

  DATA: lt_knb1 TYPE TABLE OF knb1.
  FIELD-SYMBOLS: <ls_knb1> LIKE LINE OF lt_knb1.

  CHECK cvi_bdt_adapter=>is_direct_input_active( ) EQ abap_false.
  CHECK cvi_bdt_adapter=>get_current_company_code( ) IS NOT INITIAL.
  CHECK cvi_bdt_adapter=>get_current_customer( ) IS NOT INITIAL.  "customer role only

* E-Invoice moved to Customer Company Code level (KNB1)
* Step 1: read current company code data from CVI memory (XO)
  cvi_bdt_adapter=>get_current_bp_cc_data(
    EXPORTING
      i_table_name = 'KNB1'
    IMPORTING
      e_data_table = lt_knb1[] ).

* Step 2: transfer E-Invoice fields from dynpro structure
  IF gs_knb1 IS NOT INITIAL.
    IF lt_knb1[] IS INITIAL.
      gs_knb1-kunnr = cvi_bdt_adapter=>get_current_customer( ).
      gs_knb1-bukrs = cvi_bdt_adapter=>get_current_company_code( ).
      APPEND gs_knb1 TO lt_knb1.
    ELSE.
      READ TABLE lt_knb1 ASSIGNING <ls_knb1> INDEX 1.
      <ls_knb1>-zzbusinesstype = gs_knb1-zzbusinesstype.
      <ls_knb1>-zzeinvoice     = gs_knb1-zzeinvoice.
      <ls_knb1>-zzzonetype     = gs_knb1-zzzonetype.
    ENDIF.
  ENDIF.

* Step 3: update XO memory
  cvi_bdt_adapter=>data_pai_with_company_code(
    i_table_name = 'KNB1'
    i_data_new   = lt_knb1[]
    i_validate   = abap_false ).

ENDFUNCTION.
