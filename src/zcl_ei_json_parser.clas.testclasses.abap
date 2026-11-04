*"* ============================================================
*"* Test classes
*"* ============================================================
CLASS ltc_parser DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_err,
        error_code        TYPE string,
        error_description TYPE string,
        column_name       TYPE string,
      END OF ty_err,
      tt_err TYPE STANDARD TABLE OF ty_err WITH EMPTY KEY,
      BEGIN OF ty_doc_err,
        document_index TYPE i,
        invoice_number TYPE string,
        errors         TYPE tt_err,
      END OF ty_doc_err,
      tt_doc_err TYPE STANDARD TABLE OF ty_doc_err WITH EMPTY KEY,
      BEGIN OF ty_doc,
        uuid           TYPE string,
        status         TYPE string,
        invoice_number TYPE string,
      END OF ty_doc,
      tt_doc TYPE SORTED TABLE OF ty_doc WITH UNIQUE KEY uuid,
      BEGIN OF ty_resp,
        success           TYPE abap_bool,
        status_code       TYPE i,
        message           TYPE string,
        document_count    TYPE i,
        import_history_id TYPE string,
        amount            TYPE p LENGTH 10 DECIMALS 2,
        created           TYPE d,
        created_time      TYPE t,
        documents         TYPE tt_doc,
        errors            TYPE tt_doc_err,
        details           TYPE REF TO data,
      END OF ty_resp.

    METHODS camel_case_response     FOR TESTING RAISING zcx_ei_json.
    METHODS snake_case_nested_error FOR TESTING RAISING zcx_ei_json.
    METHODS unknown_and_missing     FOR TESTING RAISING zcx_ei_json.
    METHODS raw_json_into_text      FOR TESTING RAISING zcx_ei_json.
    METHODS escapes_and_unicode     FOR TESTING RAISING zcx_ei_json.
    METHODS name_map                FOR TESTING RAISING zcx_ei_json.
    METHODS round_trip              FOR TESTING RAISING zcx_ei_json.
    METHODS syntax_error            FOR TESTING.
ENDCLASS.


CLASS ltc_parser IMPLEMENTATION.

  METHOD camel_case_response.
    DATA ls TYPE ty_resp.
    NEW zcl_ei_json_parser( )->deserialize(
      EXPORTING iv_json = `{"success":true,"documentCount":1,"importHistoryId":12345,"amount":-2.375,` &&
                          `"created":"2025-06-15T10:30:00Z","createdTime":"2025-06-15T10:30:05.000Z",` &&
                          `"documents":[{"uuid":"u-1","status":"accepted","invoiceNumber":"INV-1"}]}`
      CHANGING  ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-success           exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = ls-document_count    exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls-import_history_id exp = `12345` ).
    DATA lv_exp_amount TYPE p LENGTH 10 DECIMALS 2 VALUE '-2.38'.  "-2.375 rounded
    cl_abap_unit_assert=>assert_equals( act = ls-amount            exp = lv_exp_amount ).
    cl_abap_unit_assert=>assert_equals( act = ls-created           exp = CONV d( '20250615' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls-created_time      exp = CONV t( '103005' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls-documents[ 1 ]-invoice_number exp = `INV-1` ).
  ENDMETHOD.


  METHOD snake_case_nested_error.
    DATA ls TYPE ty_resp.
    NEW zcl_ei_json_parser( )->deserialize(
      EXPORTING iv_json = `{"success":false,"statusCode":400,"message":"Invoice schema validation failed",` &&
                          `"errors":[{"document_index":0,"invoice_number":"INV-2025-001","errors":[` &&
                          `{"error_code":"TL_MOF_47_ITEM_TAX_RATE","error_description":"Line 1: Invoiced item tax rate is required",` &&
                          `"column_name":"invoice_line.item.classified_tax_category.percent"},` &&
                          `{"error_code":"TL_MOF_44_ITEM_GROSS_PRICE","error_description":"Line 1: Item gross price is required",` &&
                          `"column_name":"invoice_line.item.price.gross_price"}]}]}`
      CHANGING  ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-success     exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls-status_code exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls-errors[ 1 ]-errors ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls-errors[ 1 ]-errors[ 2 ]-error_code exp = `TL_MOF_44_ITEM_GROSS_PRICE` ).
  ENDMETHOD.


  METHOD unknown_and_missing.
    DATA ls TYPE ty_resp.
    NEW zcl_ei_json_parser( )->deserialize(
      EXPORTING iv_json = `{ "links": {"self":"/x","a":[1,{"b":"]}"}]}, "statusCode" : 201 , "x":null }`
      CHANGING  ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-status_code exp = 201 ).
    cl_abap_unit_assert=>assert_initial( ls-message ).
    cl_abap_unit_assert=>assert_initial( ls-documents ).
  ENDMETHOD.


  METHOD raw_json_into_text.
    DATA ls TYPE ty_resp.
    NEW zcl_ei_json_parser( )->deserialize(
      EXPORTING iv_json = `{"message":["grant_type must be \"client_credentials\""],"details":{"a":1}}`
      CHANGING  ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-message exp = `["grant_type must be \"client_credentials\""]` ).
    ASSIGN ls-details->* TO FIELD-SYMBOL(<lv_det>).
    cl_abap_unit_assert=>assert_equals( act = <lv_det> exp = `{"a":1}` ).
  ENDMETHOD.


  METHOD escapes_and_unicode.
    DATA ls TYPE ty_resp.
    NEW zcl_ei_json_parser( )->deserialize(
      EXPORTING iv_json = `{"message":"a\"b\\c\/d\né"}`
      CHANGING  ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-message
                                        exp = `a"b\c/d` && cl_abap_char_utilities=>newline && `é` ).
  ENDMETHOD.


  METHOD name_map.
    TYPES: BEGIN OF ty_s,
             line_ext_amt_cur TYPE string,
           END OF ty_s.
    DATA ls TYPE ty_s.
    NEW zcl_ei_json_parser( it_name_map = VALUE #( ( abap = `LINE_EXT_AMT_CUR` json = `line_extension_amount_currency_code` ) )
      )->deserialize( EXPORTING iv_json = `{"line_extension_amount_currency_code":"AED"}` CHANGING ca_data = ls ).
    cl_abap_unit_assert=>assert_equals( act = ls-line_ext_amt_cur exp = `AED` ).
  ENDMETHOD.


  METHOD round_trip.
    DATA ls_in  TYPE ty_resp.
    DATA ls_out TYPE ty_resp.
    ls_in = VALUE #( success = abap_true status_code = 201 message = `ok / "done"` amount = '-12.50'
                     created = '20251231' created_time = '235959'
                     documents = VALUE #( ( uuid = `1` status = `accepted` ) ( uuid = `2` ) )
                     errors = VALUE #( ( document_index = 3 errors = VALUE #( ( error_code = `E1` ) ) ) ) ).
    DATA(lv_json) = NEW zcl_ei_json_builder(
                      is_options = VALUE #( name_case = zcl_ei_json_builder=>co_case-camel skip_initial = abap_true
                                            trim_decimals = abap_true escape_slash = abap_true ) )->serialize( ls_in ).
    NEW zcl_ei_json_parser( )->deserialize( EXPORTING iv_json = lv_json CHANGING ca_data = ls_out ).
    cl_abap_unit_assert=>assert_equals( act = ls_out exp = ls_in ).
  ENDMETHOD.


  METHOD syntax_error.
    DATA ls TYPE ty_resp.
    TRY.
        NEW zcl_ei_json_parser( )->deserialize( EXPORTING iv_json = `{"success":true,` CHANGING ca_data = ls ).
        cl_abap_unit_assert=>fail( `exception expected` ).
      CATCH zcx_ei_json INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `JSON error:*` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
