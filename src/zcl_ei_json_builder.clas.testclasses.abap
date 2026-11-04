*"* ============================================================
*"* Test classes (ADT: tab "Test Classes" / SE24: Goto > Local
*"* Definitions/Implementations > Local Test Classes)
*"* ============================================================
CLASS ltc_builder DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_tax,
        id      TYPE string,
        percent TYPE string,
      END OF ty_tax,
      BEGIN OF ty_sub,
        taxable_amount TYPE p LENGTH 16 DECIMALS 2,
        tax_category   TYPE ty_tax,
      END OF ty_sub,
      tt_sub TYPE STANDARD TABLE OF ty_sub WITH EMPTY KEY,
      BEGIN OF ty_total,
        tax_amount             TYPE p LENGTH 16 DECIMALS 2,
        tax_included_indicator TYPE abap_bool,
        tax_subtotal           TYPE tt_sub,
      END OF ty_total,
      BEGIN OF ty_doc,
        invoice_number     TYPE c LENGTH 20,
        issue_date         TYPE d,
        issue_time         TYPE t,
        due_date           TYPE d,
        note               TYPE string,
        document_tax_total TYPE ty_total,
        tags               TYPE string_table,
      END OF ty_doc.

    METHODS nested_struct_and_tables FOR TESTING.
    METHODS numbers_incl_negative    FOR TESTING.
    METHODS dates_and_times          FOR TESTING.
    METHODS empty_fields_skip_force  FOR TESTING.
    METHODS empty_fields_no_skip     FOR TESTING.
    METHODS escaping                 FOR TESTING.
    METHODS name_map_and_camel_case  FOR TESTING.
    METHODS booleans                 FOR TESTING.
    METHODS pretty_print             FOR TESTING.
    METHODS data_reference           FOR TESTING.
ENDCLASS.


CLASS ltc_builder IMPLEMENTATION.

  METHOD nested_struct_and_tables.
    DATA(ls_doc) = VALUE ty_doc(
      invoice_number     = 'INV-1'
      document_tax_total = VALUE #(
        tax_amount   = '2.38'
        tax_subtotal = VALUE #( ( taxable_amount = '47.50' tax_category = VALUE #( id = 'S' percent = '5' ) )
                                ( taxable_amount = '10'    tax_category = VALUE #( id = 'Z' percent = '0' ) ) ) )
      tags = VALUE #( ( `a` ) ( `b` ) ) ).

    DATA(lv_json) = NEW zcl_ei_json_builder( )->serialize( ls_doc ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_json
      exp = `{"invoice_number":"INV-1","document_tax_total":{"tax_amount":2.38,"tax_included_indicator":false,` &&
            `"tax_subtotal":[{"taxable_amount":47.5,"tax_category":{"id":"S","percent":"5"}},` &&
            `{"taxable_amount":10,"tax_category":{"id":"Z","percent":"0"}}]},"tags":["a","b"]}` ).
  ENDMETHOD.


  METHOD numbers_incl_negative.
    TYPES: BEGIN OF ty_num,
             p_neg  TYPE p LENGTH 16 DECIMALS 2,
             p_big  TYPE p LENGTH 16 DECIMALS 3,
             i_neg  TYPE i,
             int8   TYPE int8,
             df     TYPE decfloat34,
             txt    TYPE c LENGTH 10,
           END OF ty_num.
    DATA(lo) = NEW zcl_ei_json_builder( ).

    DATA(lv_json) = lo->serialize( VALUE ty_num( p_neg = '-1234567.50' p_big = '1000000.125'
                                                 i_neg = -5 int8 = 9007199254740993
                                                 df = '-0.25' txt = '12.5-' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_json
      exp = `{"p_neg":-1234567.5,"p_big":1000000.125,"i_neg":-5,"int8":9007199254740993,"df":-0.25,"txt":"12.5-"}` ).

    "Numeric text -> number, trailing minus moved to the front
    cl_abap_unit_assert=>assert_equals( act = zcl_ei_json_builder=>format_number( '12.50-' ) exp = `-12.5` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_ei_json_builder=>format_number( '5.00' )   exp = `5` ).

    "Float: value must survive the round trip (exact text depends on the kernel)
    DATA lv_f TYPE f VALUE '1.5'.
    DATA(lv_ftxt) = zcl_ei_json_builder=>format_number( lv_f ).
    cl_abap_unit_assert=>assert_equals( act = CONV decfloat34( lv_ftxt ) exp = CONV decfloat34( '1.5' ) ).
  ENDMETHOD.


  METHOD dates_and_times.
    DATA(lv_json) = NEW zcl_ei_json_builder( )->serialize(
                      VALUE ty_doc( issue_date = '20250615' issue_time = '103000' ) ).
    "due_date initial -> omitted; initial structure document_tax_total -> omitted
    cl_abap_unit_assert=>assert_equals(
      act = lv_json
      exp = `{"issue_date":"2025-06-15","issue_time":"10:30:00"}` ).
  ENDMETHOD.


  METHOD empty_fields_skip_force.
    "Forced fields are written although initial: tax amount 0, initial date -> null
    "(an initial structure is only written when the structure itself is forced)
    DATA(lo) = NEW zcl_ei_json_builder( it_always = VALUE #( ( `DOCUMENT_TAX_TOTAL` )
                                                             ( `DOCUMENT_TAX_TOTAL-TAX_AMOUNT` ) "by path
                                                             ( `DUE_DATE` ) ) ).             "by name
    DATA(lv_json) = lo->serialize( VALUE ty_doc( invoice_number = 'X' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_json
      exp = `{"invoice_number":"X","due_date":null,"document_tax_total":{"tax_amount":0,"tax_included_indicator":false}}` ).
  ENDMETHOD.


  METHOD empty_fields_no_skip.
    DATA(lo) = NEW zcl_ei_json_builder( is_options = VALUE #( skip_initial = abap_false ) ).
    DATA(lv_json) = lo->serialize( VALUE ty_doc( ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_json
      exp = `{"invoice_number":"","issue_date":"","issue_time":"00:00:00","due_date":"","note":"",` &&
            `"document_tax_total":{"tax_amount":0.00,"tax_included_indicator":false,"tax_subtotal":[]},"tags":[]}` ).
    "(options supplied without TRIM_DECIMALS -> 0.00 is kept; still a valid JSON number)
  ENDMETHOD.


  METHOD escaping.
    DATA(lv_ctrl) = cl_abap_codepage=>convert_from( source = CONV xstring( '0001' ) codepage = `UTF-16BE` ).
    DATA(lv_in) = `a"b\c/d` && cl_abap_char_utilities=>newline &&
                  cl_abap_char_utilities=>horizontal_tab && lv_ctrl && `é`.

    cl_abap_unit_assert=>assert_equals(
      act = zcl_ei_json_builder=>escape( lv_in )
      exp = `a\"b\\c\/d\n\t\u0001é` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_ei_json_builder=>escape( iv_value = `a/b` iv_escape_slash = abap_false )
      exp = `a/b` ).

    "Trailing blanks of C fields are removed, leading kept
    DATA(lv_json) = NEW zcl_ei_json_builder( )->serialize( VALUE ty_doc( invoice_number = ' A B   ' ) ).
    cl_abap_unit_assert=>assert_equals( act = lv_json exp = `{"invoice_number":" A B"}` ).
  ENDMETHOD.


  METHOD name_map_and_camel_case.
    TYPES: BEGIN OF ty_s,
             line_ext_amt_cur TYPE string,
             invoice_number   TYPE string,
           END OF ty_s.
    DATA(ls) = VALUE ty_s( line_ext_amt_cur = `AED` invoice_number = `1` ).

    DATA(lo_camel) = NEW zcl_ei_json_builder(
      is_options  = VALUE #( name_case = zcl_ei_json_builder=>co_case-camel skip_initial = abap_true )
      it_name_map = VALUE #( ( abap = `LINE_EXT_AMT_CUR` json = `line_extension_amount_currency_code` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_camel->serialize( ls )
      exp = `{"line_extension_amount_currency_code":"AED","invoiceNumber":"1"}` ).

    cl_abap_unit_assert=>assert_equals( act = zcl_ei_json_builder=>json_name( iv_abap_name = 'IMPORT_HISTORY_ID'
                                                                              iv_case = zcl_ei_json_builder=>co_case-camel )
                                        exp = `importHistoryId` ).
  ENDMETHOD.


  METHOD booleans.
    TYPES: BEGIN OF ty_b,
             flag_bool  TYPE abap_bool,
             flag_xfeld TYPE xfeld,
             char1      TYPE c LENGTH 1,
           END OF ty_b.
    cl_abap_unit_assert=>assert_equals(
      act = NEW zcl_ei_json_builder( )->serialize( VALUE ty_b( flag_bool = abap_true char1 = 'X' ) )
      exp = `{"flag_bool":true,"flag_xfeld":false,"char1":"X"}` ).
  ENDMETHOD.


  METHOD pretty_print.
    TYPES: BEGIN OF ty_p,
             a TYPE string,
             b TYPE string_table,
           END OF ty_p.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    cl_abap_unit_assert=>assert_equals(
      act = NEW zcl_ei_json_builder( )->serialize( ia_data = VALUE ty_p( a = `1` b = VALUE #( ( `x` ) ) ) iv_pretty = abap_true )
      exp = |\{{ lv_nl }  "a": "1",{ lv_nl }  "b": [{ lv_nl }    "x"{ lv_nl }  ]{ lv_nl }\}| ).
  ENDMETHOD.


  METHOD data_reference.
    TYPES: BEGIN OF ty_r,
             det TYPE REF TO data,
           END OF ty_r.
    DATA ls TYPE ty_r.
    ls-det = NEW string( `x` ).
    cl_abap_unit_assert=>assert_equals( act = NEW zcl_ei_json_builder( )->serialize( ls )
                                        exp = `{"det":"x"}` ).
  ENDMETHOD.

ENDCLASS.
