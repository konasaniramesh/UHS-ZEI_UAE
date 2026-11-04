"! <p class="shorttext synchronized">E-Invoice: dynamic JSON -> ABAP deserializer (RTTI)</p>
"!
"! Recursive-descent JSON parser that fills ANY ABAP data object, driven by
"! the RTTI description of the target. No CALL TRANSFORMATION, no /UI2/CL_JSON.
"!
"!  JSON object  -> structure  (keys matched to components, see below)
"!  JSON array   -> internal table (any kind; line parsed into a work area,
"!                  then INSERTed - also works for sorted / hashed tables)
"!  string       -> C/N/STRING; D ("YYYY-MM-DD[...]"); T ("HH:MM:SS" or ISO
"!                  date-time); numeric targets accept numeric strings
"!  number       -> P/I/INT8/F/DECFLOAT (via DECFLOAT34) or text target
"!  true/false   -> 'X'/' ' (C1/ABAP_BOOL), 'true'/'false' (text), 1/0 (number)
"!  null         -> target left initial
"!  object/array into an elementary text target or an unbound REF TO data
"!               -> raw JSON text is stored (e.g. "message": [ ... ])
"!
"! Key matching (per structure level):
"!  1. explicit name map (same table type as ZCL_EI_JSON_BUILDER, by
"!     component path or name)
"!  2. automatic: JSON key and ABAP name are compared case-insensitively
"!     without '_' -> "invoiceNumber", "invoice_number" and "INVOICENUMBER"
"!     all match component INVOICE_NUMBER (camelCase and snake_case)
"! Unknown keys are skipped; missing keys leave the component initial.
CLASS zcl_ei_json_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        it_name_map TYPE zcl_ei_json_builder=>tt_name_map OPTIONAL.

    "! @parameter iv_json | JSON text
    "! @parameter ca_data | Target data object (cleared first)
    "! @raising zcx_ei_json | Syntax error / unexpected end of input
    METHODS deserialize
      IMPORTING
        iv_json TYPE string
      CHANGING
        ca_data TYPE any
      RAISING
        zcx_ei_json.

    "! Values that could not be converted to the target type (left initial)
    METHODS get_warnings
      RETURNING
        VALUE(rt_warnings) TYPE string_table.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        key  TYPE string,
        name TYPE string,
        path TYPE string,
      END OF ty_key,
      tt_key TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY key,
      BEGIN OF ty_cache,
        type TYPE REF TO cl_abap_structdescr,
        path TYPE string,
        keys TYPE tt_key,
      END OF ty_cache.

    DATA mt_name_map TYPE zcl_ei_json_builder=>tt_name_map.
    DATA mt_cache    TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY type path.
    DATA mt_warnings TYPE string_table.
    DATA mv_json     TYPE string.
    DATA mv_len      TYPE i.
    DATA mv_pos      TYPE i.

    METHODS parse_value
      IMPORTING
        iv_path TYPE string
      CHANGING
        ca_data TYPE any
      RAISING
        zcx_ei_json.

    METHODS parse_object
      IMPORTING
        io_type TYPE REF TO cl_abap_structdescr
        iv_path TYPE string
      CHANGING
        ca_data TYPE any
      RAISING
        zcx_ei_json.

    METHODS parse_array
      IMPORTING
        iv_path TYPE string
      CHANGING
        ca_data TYPE any
      RAISING
        zcx_ei_json.

    METHODS assign_scalar
      IMPORTING
        iv_value  TYPE string
        iv_quoted TYPE abap_bool
        iv_path   TYPE string
      CHANGING
        ca_data   TYPE any.

    METHODS assign_bool
      IMPORTING
        iv_value TYPE abap_bool
      CHANGING
        ca_data  TYPE any.

    METHODS get_keys
      IMPORTING
        io_type       TYPE REF TO cl_abap_structdescr
        iv_path       TYPE string
      RETURNING
        VALUE(rr_keys) TYPE REF TO tt_key.

    METHODS read_string
      RETURNING
        VALUE(rv_value) TYPE string
      RAISING
        zcx_ei_json.

    METHODS read_token
      RETURNING
        VALUE(rv_token) TYPE string
      RAISING
        zcx_ei_json.

    METHODS skip_value
      RAISING
        zcx_ei_json.

    METHODS skip_ws.

    METHODS peek
      RETURNING
        VALUE(rv_char) TYPE string
      RAISING
        zcx_ei_json.

    METHODS expect
      IMPORTING
        iv_char TYPE string
      RAISING
        zcx_ei_json.

    METHODS throw
      IMPORTING
        iv_text TYPE string
      RAISING
        zcx_ei_json.

    CLASS-METHODS normalize
      IMPORTING
        iv_name       TYPE string
      RETURNING
        VALUE(rv_key) TYPE string.
ENDCLASS.



CLASS zcl_ei_json_parser IMPLEMENTATION.

  METHOD constructor.
    LOOP AT it_name_map INTO DATA(ls_map).
      INSERT VALUE #( abap = to_upper( ls_map-abap ) json = ls_map-json ) INTO TABLE mt_name_map.
    ENDLOOP.
  ENDMETHOD.


  METHOD deserialize.
    CLEAR: ca_data, mt_warnings.
    mv_json = iv_json.
    mv_len  = strlen( mv_json ).
    mv_pos  = 0.

    "UTF-8 byte order mark (U+FEFF) at the beginning
    IF mv_len GT 0 AND
       cl_abap_codepage=>convert_to( source = substring( val = mv_json len = 1 ) codepage = `UTF-16BE` ) EQ 'FEFF'.
      mv_pos = 1.
    ENDIF.

    skip_ws( ).
    IF mv_pos GE mv_len.
      throw( `empty document` ).
    ENDIF.

    parse_value( EXPORTING iv_path = `` CHANGING ca_data = ca_data ).
    CLEAR mv_json.
  ENDMETHOD.


  METHOD get_warnings.
    rt_warnings = mt_warnings.
  ENDMETHOD.


  METHOD parse_value.
    FIELD-SYMBOLS <lr_data> TYPE REF TO data.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( ca_data ).
    DATA(lv_char) = peek( ).

    "REF TO data: bound -> parse into the target, unbound -> raw JSON text
    IF lo_type->kind EQ cl_abap_typedescr=>kind_ref.
      IF lo_type->type_kind EQ cl_abap_typedescr=>typekind_dref.
        ASSIGN ca_data TO <lr_data>.
        IF <lr_data> IS BOUND.
          ASSIGN <lr_data>->* TO FIELD-SYMBOL(<la_target>).
          parse_value( EXPORTING iv_path = iv_path CHANGING ca_data = <la_target> ).
        ELSE.
          DATA(lv_start) = mv_pos.
          skip_value( ).
          DATA(lv_raw) = substring( val = mv_json off = lv_start len = mv_pos - lv_start ).
          IF lv_raw NE `null`.
            <lr_data> = NEW string( lv_raw ).
          ENDIF.
        ENDIF.
      ELSE.
        skip_value( ).
      ENDIF.
      RETURN.
    ENDIF.

    CASE lv_char.

      WHEN `{` OR `[`.
        IF lv_char EQ `{` AND lo_type->kind EQ cl_abap_typedescr=>kind_struct.
          parse_object( EXPORTING io_type = CAST #( lo_type ) iv_path = iv_path
                        CHANGING  ca_data = ca_data ).
        ELSEIF lv_char EQ `[` AND lo_type->kind EQ cl_abap_typedescr=>kind_table.
          parse_array( EXPORTING iv_path = iv_path CHANGING ca_data = ca_data ).
        ELSEIF lo_type->kind EQ cl_abap_typedescr=>kind_elem AND
               ( lo_type->type_kind EQ cl_abap_typedescr=>typekind_string OR
                 lo_type->type_kind EQ cl_abap_typedescr=>typekind_char ).
          "Object / array into a text field: keep the raw JSON
          lv_start = mv_pos.
          skip_value( ).
          ca_data = substring( val = mv_json off = lv_start len = mv_pos - lv_start ).
        ELSE.
          skip_value( ).
        ENDIF.

      WHEN `"`.
        DATA(lv_string) = read_string( ).
        assign_scalar( EXPORTING iv_value = lv_string iv_quoted = abap_true iv_path = iv_path
                       CHANGING  ca_data  = ca_data ).

      WHEN OTHERS.
        DATA(lv_token) = read_token( ).
        CASE lv_token.
          WHEN `true`.
            assign_bool( EXPORTING iv_value = abap_true  CHANGING ca_data = ca_data ).
          WHEN `false`.
            assign_bool( EXPORTING iv_value = abap_false CHANGING ca_data = ca_data ).
          WHEN `null`.
            "missing value -> target stays initial
          WHEN OTHERS.
            IF lv_token NA '0123456789'.
              throw( |invalid token "{ lv_token }"| ).
            ENDIF.
            assign_scalar( EXPORTING iv_value = lv_token iv_quoted = abap_false iv_path = iv_path
                           CHANGING  ca_data  = ca_data ).
        ENDCASE.

    ENDCASE.
  ENDMETHOD.


  METHOD parse_object.
    DATA(lr_keys) = get_keys( io_type = io_type iv_path = iv_path ).

    expect( `{` ).
    IF peek( ) EQ `}`.
      mv_pos = mv_pos + 1.
      RETURN.
    ENDIF.

    DO.
      IF peek( ) NE `"`.
        throw( `object key expected` ).
      ENDIF.
      DATA(lv_key) = read_string( ).
      expect( `:` ).

      READ TABLE lr_keys->* INTO DATA(ls_key) WITH TABLE KEY key = normalize( lv_key ).
      IF sy-subrc EQ 0.
        ASSIGN COMPONENT ls_key-name OF STRUCTURE ca_data TO FIELD-SYMBOL(<la_comp>).
        IF sy-subrc EQ 0.
          parse_value( EXPORTING iv_path = ls_key-path CHANGING ca_data = <la_comp> ).
        ELSE.
          skip_value( ).
        ENDIF.
      ELSE.
        skip_value( ).                                "unknown key -> ignored
      ENDIF.

      CASE peek( ).
        WHEN `,`.
          mv_pos = mv_pos + 1.
        WHEN `}`.
          mv_pos = mv_pos + 1.
          EXIT.
        WHEN OTHERS.
          throw( `',' or '}' expected` ).
      ENDCASE.
    ENDDO.
  ENDMETHOD.


  METHOD parse_array.
    FIELD-SYMBOLS <lt_any> TYPE ANY TABLE.
    DATA lr_line TYPE REF TO data.

    ASSIGN ca_data TO <lt_any>.

    expect( `[` ).
    IF peek( ) EQ `]`.
      mv_pos = mv_pos + 1.
      RETURN.
    ENDIF.

    DO.
      CREATE DATA lr_line LIKE LINE OF <lt_any>.
      ASSIGN lr_line->* TO FIELD-SYMBOL(<la_line>).
      parse_value( EXPORTING iv_path = iv_path CHANGING ca_data = <la_line> ).
      INSERT <la_line> INTO TABLE <lt_any>.

      CASE peek( ).
        WHEN `,`.
          mv_pos = mv_pos + 1.
        WHEN `]`.
          mv_pos = mv_pos + 1.
          EXIT.
        WHEN OTHERS.
          throw( `',' or ']' expected` ).
      ENDCASE.
    ENDDO.
  ENDMETHOD.


  METHOD assign_scalar.
    DATA: lv_df  TYPE decfloat34,
          lv_txt TYPE string.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( ca_data ).
    CHECK lo_type->kind EQ cl_abap_typedescr=>kind_elem.  "scalar into struct/table -> ignored

    TRY.
        CASE lo_type->type_kind.

          WHEN cl_abap_typedescr=>typekind_date.
            "YYYY-MM-DD or YYYY-MM-DDThh:mm:ss... -> YYYYMMDD
            lv_txt = replace( val = substring( val = iv_value len = nmin( val1 = 10 val2 = strlen( iv_value ) ) )
                              sub = `-` with = `` occ = 0 ).
            IF lv_txt CO '0123456789' AND strlen( lv_txt ) EQ 8.
              ca_data = lv_txt.
            ELSEIF lv_txt IS NOT INITIAL.
              APPEND |{ iv_path }: "{ iv_value }" is not a date| TO mt_warnings.
            ENDIF.

          WHEN cl_abap_typedescr=>typekind_time.
            "HH:MM:SS or date-time with 'T'
            lv_txt = iv_value.
            IF lv_txt CS 'T'.
              lv_txt = substring_after( val = lv_txt sub = `T` ).
            ENDIF.
            lv_txt = replace( val = lv_txt sub = `:` with = `` occ = 0 ).
            lv_txt = substring( val = lv_txt len = nmin( val1 = 6 val2 = strlen( lv_txt ) ) ).
            IF lv_txt CO '0123456789' AND strlen( lv_txt ) EQ 6.
              ca_data = lv_txt.
            ELSEIF lv_txt IS NOT INITIAL.
              APPEND |{ iv_path }: "{ iv_value }" is not a time| TO mt_warnings.
            ENDIF.

          WHEN cl_abap_typedescr=>typekind_int     OR cl_abap_typedescr=>typekind_int1
            OR cl_abap_typedescr=>typekind_int2    OR cl_abap_typedescr=>typekind_int8
            OR cl_abap_typedescr=>typekind_packed  OR cl_abap_typedescr=>typekind_float
            OR cl_abap_typedescr=>typekind_decfloat16 OR cl_abap_typedescr=>typekind_decfloat34.
            CHECK iv_value IS NOT INITIAL.
            lv_df = iv_value.                      "also 1.5E3 / -0.25
            ca_data = lv_df.                       "rounded to the target decimals

          WHEN OTHERS.                              "C, N, STRING, ...
            ca_data = iv_value.

        ENDCASE.
      CATCH cx_sy_conversion_error cx_sy_arithmetic_error INTO DATA(lx_conv).
        CLEAR ca_data.
        APPEND |{ iv_path }: "{ iv_value }" - { lx_conv->get_text( ) }| TO mt_warnings.
    ENDTRY.
  ENDMETHOD.


  METHOD assign_bool.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( ca_data ).
    CHECK lo_type->kind EQ cl_abap_typedescr=>kind_elem.

    CASE lo_type->type_kind.
      WHEN cl_abap_typedescr=>typekind_char.
        IF lo_type->length EQ cl_abap_char_utilities=>charsize.  "C LENGTH 1 (ABAP_BOOL, XFELD)
          ca_data = COND abap_bool( WHEN iv_value EQ abap_true THEN abap_true ELSE abap_false ).
        ELSE.
          ca_data = COND string( WHEN iv_value EQ abap_true THEN `true` ELSE `false` ).
        ENDIF.
      WHEN cl_abap_typedescr=>typekind_string.
        ca_data = COND string( WHEN iv_value EQ abap_true THEN `true` ELSE `false` ).
      WHEN cl_abap_typedescr=>typekind_int  OR cl_abap_typedescr=>typekind_int1 OR
           cl_abap_typedescr=>typekind_int2 OR cl_abap_typedescr=>typekind_int8 OR
           cl_abap_typedescr=>typekind_packed.
        ca_data = COND i( WHEN iv_value EQ abap_true THEN 1 ELSE 0 ).
    ENDCASE.
  ENDMETHOD.


  METHOD get_keys.
    READ TABLE mt_cache REFERENCE INTO DATA(lr_cache)
         WITH TABLE KEY type = io_type path = iv_path.
    IF sy-subrc NE 0.
      DATA(ls_cache) = VALUE ty_cache( type = io_type path = iv_path ).
      DATA(lt_view)  = io_type->get_included_view( ).

      "1. explicit name map (path before name)
      LOOP AT lt_view INTO DATA(ls_view).
        DATA(lv_name) = CONV string( ls_view-name ).
        DATA(lv_path) = COND string( WHEN iv_path IS INITIAL THEN lv_name ELSE |{ iv_path }-{ lv_name }| ).
        READ TABLE mt_name_map INTO DATA(ls_map) WITH TABLE KEY abap = lv_path.
        IF sy-subrc NE 0.
          READ TABLE mt_name_map INTO ls_map WITH TABLE KEY abap = lv_name.
        ENDIF.
        IF sy-subrc EQ 0.
          INSERT VALUE #( key = normalize( ls_map-json ) name = lv_name path = lv_path ) INTO TABLE ls_cache-keys.
        ENDIF.
      ENDLOOP.

      "2. automatic (camelCase / snake_case insensitive) - mapped keys win
      LOOP AT lt_view INTO ls_view.
        lv_name = ls_view-name.
        lv_path = COND #( WHEN iv_path IS INITIAL THEN lv_name ELSE |{ iv_path }-{ lv_name }| ).
        INSERT VALUE #( key = normalize( lv_name ) name = lv_name path = lv_path ) INTO TABLE ls_cache-keys.
      ENDLOOP.

      INSERT ls_cache INTO TABLE mt_cache REFERENCE INTO lr_cache.
    ENDIF.
    rr_keys = REF #( lr_cache->keys ).
  ENDMETHOD.


  METHOD normalize.
    rv_key = to_lower( iv_name ).
    REPLACE ALL OCCURRENCES OF `_` IN rv_key WITH ``.
    REPLACE ALL OCCURRENCES OF `-` IN rv_key WITH ``.
  ENDMETHOD.


  METHOD read_string.
    "mv_pos is on the opening quote
    mv_pos = mv_pos + 1.

    DO.
      DATA(lv_off) = find( val = mv_json off = mv_pos pcre = '["\\]' ).
      IF lv_off LT 0.
        throw( `unterminated string` ).
      ENDIF.
      IF lv_off GT mv_pos.
        rv_value = rv_value && substring( val = mv_json off = mv_pos len = lv_off - mv_pos ).
      ENDIF.
      mv_pos = lv_off.

      IF substring( val = mv_json off = mv_pos len = 1 ) EQ `"`.
        mv_pos = mv_pos + 1.
        RETURN.
      ENDIF.

      "Escape sequence
      IF mv_pos + 1 GE mv_len.
        throw( `unterminated escape sequence` ).
      ENDIF.
      DATA(lv_esc) = substring( val = mv_json off = mv_pos + 1 len = 1 ).
      CASE lv_esc.
        WHEN `"`.  rv_value = rv_value && `"`.
        WHEN `\`.  rv_value = rv_value && `\`.
        WHEN `/`.  rv_value = rv_value && `/`.
        WHEN `n`.  rv_value = rv_value && cl_abap_char_utilities=>newline.
        WHEN `r`.  rv_value = rv_value && substring( val = cl_abap_char_utilities=>cr_lf len = 1 ).
        WHEN `t`.  rv_value = rv_value && cl_abap_char_utilities=>horizontal_tab.
        WHEN `f`.  rv_value = rv_value && cl_abap_char_utilities=>form_feed.
        WHEN `b`.  rv_value = rv_value && cl_abap_char_utilities=>backspace.
        WHEN `u`.
          IF mv_pos + 6 GT mv_len.
            throw( `invalid \u escape` ).
          ENDIF.
          DATA(lv_hex) = to_upper( substring( val = mv_json off = mv_pos + 2 len = 4 ) ).
          IF lv_hex CN '0123456789ABCDEF'.
            throw( `invalid \u escape` ).
          ENDIF.
          "Surrogate pair D83D DE00 -> one character
          IF lv_hex CP 'D8++' OR lv_hex CP 'D9++' OR lv_hex CP 'DA++' OR lv_hex CP 'DB++'.
            IF mv_pos + 12 LE mv_len AND
               substring( val = mv_json off = mv_pos + 6 len = 2 ) EQ `\u`.
              lv_hex = lv_hex && to_upper( substring( val = mv_json off = mv_pos + 8 len = 4 ) ).
              mv_pos = mv_pos + 6.
            ENDIF.
          ENDIF.
          TRY.
              rv_value = rv_value && cl_abap_codepage=>convert_from( source   = CONV xstring( lv_hex )
                                                                     codepage = `UTF-16BE` ).
            CATCH cx_root.
              rv_value = rv_value && `?`.
          ENDTRY.
          mv_pos = mv_pos + 4.
        WHEN OTHERS.
          throw( |invalid escape \\{ lv_esc }| ).
      ENDCASE.
      mv_pos = mv_pos + 2.
    ENDDO.
  ENDMETHOD.


  METHOD read_token.
    "Number or literal: up to the next delimiter
    DATA(lv_end) = find( val = mv_json off = mv_pos pcre = '[,\]\}\s]' ).
    IF lv_end LT 0.
      lv_end = mv_len.
    ENDIF.
    IF lv_end EQ mv_pos.
      throw( `value expected` ).
    ENDIF.
    rv_token = substring( val = mv_json off = mv_pos len = lv_end - mv_pos ).
    mv_pos = lv_end.
  ENDMETHOD.


  METHOD skip_value.
    DATA lv_depth TYPE i.

    CASE peek( ).
      WHEN `"`.
        read_string( ).
      WHEN `{` OR `[`.
        DO.
          DATA(lv_off) = find( val = mv_json off = mv_pos pcre = '[\[\]\{\}"]' ).
          IF lv_off LT 0.
            throw( `unbalanced brackets` ).
          ENDIF.
          mv_pos = lv_off.
          CASE substring( val = mv_json off = mv_pos len = 1 ).
            WHEN `"`.
              read_string( ).
              CONTINUE.
            WHEN `{` OR `[`.
              lv_depth = lv_depth + 1.
            WHEN OTHERS.
              lv_depth = lv_depth - 1.
          ENDCASE.
          mv_pos = mv_pos + 1.
          IF lv_depth EQ 0.
            EXIT.
          ENDIF.
        ENDDO.
      WHEN OTHERS.
        read_token( ).
    ENDCASE.
  ENDMETHOD.


  METHOD skip_ws.
    DATA(lv_off) = find( val = mv_json off = mv_pos pcre = '[^\s]' ).
    mv_pos = COND #( WHEN lv_off LT 0 THEN mv_len ELSE lv_off ).
  ENDMETHOD.


  METHOD peek.
    skip_ws( ).
    IF mv_pos GE mv_len.
      throw( `unexpected end of input` ).
    ENDIF.
    rv_char = substring( val = mv_json off = mv_pos len = 1 ).
  ENDMETHOD.


  METHOD expect.
    IF peek( ) NE iv_char.
      throw( |'{ iv_char }' expected| ).
    ENDIF.
    mv_pos = mv_pos + 1.
  ENDMETHOD.


  METHOD throw.
    RAISE EXCEPTION TYPE zcx_ei_json
      EXPORTING
        iv_text   = iv_text
        iv_offset = mv_pos.
  ENDMETHOD.

ENDCLASS.

