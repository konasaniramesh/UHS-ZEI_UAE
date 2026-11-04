"! <p class="shorttext synchronized">E-Invoice: dynamic ABAP -> JSON serializer (RTTI)</p>
"!
"! Serializes ANY ABAP data object to JSON by walking its RTTI description
"! recursively. No CALL TRANSFORMATION, no /UI2/CL_JSON.
"!
"!   structure            -> JSON object
"!   internal table       -> JSON array (any table kind, any line type)
"!   nested struct/table  -> nested object/array, any depth
"!   P, I, INT1/2/8, F,
"!   DECFLOAT16/34        -> JSON number ('.' decimal, no grouping, leading '-')
"!   D                    -> "YYYY-MM-DD"  (initial -> omitted or null)
"!   T                    -> "HH:MM:SS"
"!   C, N, STRING         -> JSON string (escaped, trailing blanks removed)
"!   X, XSTRING           -> JSON string, Base64
"!   ABAP_BOOL, XFELD,
"!   BOOLE_D, BOOLEAN,
"!   XSDBOOLEAN           -> true / false (always written, also when false)
"!   REF TO data          -> serialized target (unbound -> null)
"!   REF TO object        -> null
"!
"! JSON key = explicit name map (component PATH or component NAME, upper
"! case) or the automatic conversion of the component name
"! (co_case-snake: invoice_number / co_case-camel: invoiceNumber).
"!
"! Output is collected in a string table and joined once at the end
"! (no repeated string concatenation in the recursion).
"!
"! Release: SAP_BASIS 7.55 (S/4HANA 2020) - uses inline declarations,
"! constructor expressions (VALUE, COND, SWITCH, REF, CAST), string templates.
CLASS zcl_ei_json_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      "! ABAP component (path or name, upper case) -> JSON key
      BEGIN OF ty_name_map,
        abap TYPE string,
        json TYPE string,
      END OF ty_name_map,
      tt_name_map TYPE HASHED TABLE OF ty_name_map WITH UNIQUE KEY abap,
      "! Component paths / names (upper case)
      tt_names    TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
      ty_case     TYPE c LENGTH 1.

    CONSTANTS:
      BEGIN OF co_case,
        snake TYPE ty_case VALUE 'S', "INVOICE_NUMBER -> invoice_number
        camel TYPE ty_case VALUE 'C', "INVOICE_NUMBER -> invoiceNumber
        none  TYPE ty_case VALUE 'N', "INVOICE_NUMBER -> INVOICE_NUMBER
      END OF co_case.

    TYPES:
      BEGIN OF ty_options,
        "! Automatic key conversion (default snake)
        name_case         TYPE ty_case,
        "! Omit initial fields / empty tables / initial structures
        skip_initial      TYPE abap_bool,
        "! Line breaks + 2 blank indentation (logging); compact otherwise
        pretty            TYPE abap_bool,
        "! 47.50 -> 47.5, 5.00 -> 5
        trim_decimals     TYPE abap_bool,
        "! '/' -> '\/' (valid JSON either way)
        escape_slash      TYPE abap_bool,
        "! Initial date that is written (forced or skip_initial off): null
        "! (abap_true) or "" (abap_false)
        null_initial_date TYPE abap_bool,
      END OF ty_options.

    "! @parameter is_options  | Options (not supplied: snake, skip initial, compact, trim, escape '/', null date)
    "! @parameter it_name_map | Explicit ABAP -> JSON key map (overrides automatic conversion)
    "! @parameter it_always   | Component paths/names always written even if initial
    METHODS constructor
      IMPORTING
        is_options  TYPE ty_options  OPTIONAL
        it_name_map TYPE tt_name_map OPTIONAL
        it_always   TYPE tt_names    OPTIONAL.

    "! Serialize any data object
    "! @parameter ia_data   | Data object (structure, table, elementary, data ref)
    "! @parameter iv_pretty | Override option PRETTY for this call (e.g. logging)
    "! @parameter rv_json   | JSON text
    METHODS serialize
      IMPORTING
        ia_data        TYPE any
        iv_pretty      TYPE abap_bool OPTIONAL
      RETURNING
        VALUE(rv_json) TYPE string.

    "! Additional boolean data element (relative type name, e.g. 'ZDE_FLAG')
    METHODS add_bool_type
      IMPORTING
        iv_type_name TYPE csequence.

    "! ABAP name -> JSON key (automatic conversion, no name map)
    CLASS-METHODS json_name
      IMPORTING
        iv_abap_name  TYPE csequence
        iv_case       TYPE ty_case DEFAULT co_case-snake
      RETURNING
        VALUE(rv_key) TYPE string.

    "! Number (or numeric text such as '5.00-') -> JSON number text
    CLASS-METHODS format_number
      IMPORTING
        ia_value       TYPE any
        iv_trim        TYPE abap_bool DEFAULT abap_true
      RETURNING
        VALUE(rv_json) TYPE string.

    "! Escape a string for use inside a JSON string literal (no quotes added)
    CLASS-METHODS escape
      IMPORTING
        iv_value        TYPE string
        iv_escape_slash TYPE abap_bool DEFAULT abap_true
      RETURNING
        VALUE(rv_json)  TYPE string.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_comp,
        name    TYPE string,
        path    TYPE string,
        json    TYPE string,
        type    TYPE REF TO cl_abap_datadescr,
        forced  TYPE abap_bool,
        is_bool TYPE abap_bool,
      END OF ty_comp,
      tt_comp TYPE STANDARD TABLE OF ty_comp WITH EMPTY KEY,
      BEGIN OF ty_cache,
        type  TYPE REF TO cl_abap_structdescr,
        path  TYPE string,
        comps TYPE tt_comp,
      END OF ty_cache.

    DATA ms_opt        TYPE ty_options.
    DATA mt_name_map   TYPE tt_name_map.
    DATA mt_always     TYPE tt_names.
    DATA mt_bool_types TYPE tt_names.
    DATA mt_cache      TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY type path.
    DATA mt_out        TYPE string_table.
    DATA mv_pretty     TYPE abap_bool.

    METHODS write_value
      IMPORTING
        ia_data  TYPE any
        io_type  TYPE REF TO cl_abap_typedescr
        iv_path  TYPE string
        iv_bool  TYPE abap_bool DEFAULT abap_false
        iv_level TYPE i.

    METHODS write_struct
      IMPORTING
        ia_data  TYPE any
        io_type  TYPE REF TO cl_abap_structdescr
        iv_path  TYPE string
        iv_level TYPE i.

    METHODS write_table
      IMPORTING
        ia_data  TYPE any
        io_type  TYPE REF TO cl_abap_tabledescr
        iv_path  TYPE string
        iv_level TYPE i.

    METHODS elem_to_json
      IMPORTING
        ia_data        TYPE any
        io_type        TYPE REF TO cl_abap_elemdescr
        iv_bool        TYPE abap_bool
      RETURNING
        VALUE(rv_json) TYPE string.

    METHODS get_components
      IMPORTING
        io_type      TYPE REF TO cl_abap_structdescr
        iv_path      TYPE string
      RETURNING
        VALUE(rr_comps) TYPE REF TO tt_comp.

    METHODS is_bool
      IMPORTING
        io_type        TYPE REF TO cl_abap_datadescr
      RETURNING
        VALUE(rv_bool) TYPE abap_bool.

    METHODS newline
      IMPORTING
        iv_level TYPE i.
ENDCLASS.



CLASS zcl_ei_json_builder IMPLEMENTATION.

  METHOD constructor.
    IF is_options IS SUPPLIED.
      ms_opt = is_options.
    ELSE.
      ms_opt = VALUE #( name_case         = co_case-snake
                        skip_initial      = abap_true
                        pretty            = abap_false
                        trim_decimals     = abap_true
                        escape_slash      = abap_true
                        null_initial_date = abap_true ).
    ENDIF.
    IF ms_opt-name_case IS INITIAL.
      ms_opt-name_case = co_case-snake.
    ENDIF.

    "Keys are compared in upper case
    LOOP AT it_name_map INTO DATA(ls_map).
      INSERT VALUE #( abap = to_upper( ls_map-abap ) json = ls_map-json ) INTO TABLE mt_name_map.
    ENDLOOP.
    LOOP AT it_always INTO DATA(lv_always).
      INSERT to_upper( lv_always ) INTO TABLE mt_always.
    ENDLOOP.

    mt_bool_types = VALUE #( ( `ABAP_BOOL` ) ( `XFELD` ) ( `BOOLE_D` )
                             ( `BOOLEAN` ) ( `XSDBOOLEAN` ) ).
  ENDMETHOD.


  METHOD add_bool_type.
    INSERT to_upper( iv_type_name ) INTO TABLE mt_bool_types.
  ENDMETHOD.


  METHOD serialize.
    CLEAR mt_out.
    mv_pretty = COND #( WHEN iv_pretty IS SUPPLIED THEN iv_pretty ELSE ms_opt-pretty ).

    write_value( ia_data  = ia_data
                 io_type  = cl_abap_typedescr=>describe_by_data( ia_data )
                 iv_path  = ``
                 iv_level = 0 ).

    rv_json = concat_lines_of( table = mt_out ).
    CLEAR mt_out.
  ENDMETHOD.


  METHOD write_value.
    FIELD-SYMBOLS: <lr_data> TYPE REF TO data,
                   <la_ref>  TYPE any.

    CASE io_type->kind.

      WHEN cl_abap_typedescr=>kind_struct.
        write_struct( ia_data  = ia_data
                      io_type  = CAST #( io_type )
                      iv_path  = iv_path
                      iv_level = iv_level ).

      WHEN cl_abap_typedescr=>kind_table.
        write_table( ia_data  = ia_data
                     io_type  = CAST #( io_type )
                     iv_path  = iv_path
                     iv_level = iv_level ).

      WHEN cl_abap_typedescr=>kind_elem.
        APPEND elem_to_json( ia_data = ia_data
                             io_type = CAST #( io_type )
                             iv_bool = iv_bool ) TO mt_out.

      WHEN cl_abap_typedescr=>kind_ref.
        IF io_type->type_kind EQ cl_abap_typedescr=>typekind_dref.
          ASSIGN ia_data TO <lr_data>.
          IF sy-subrc EQ 0 AND <lr_data> IS BOUND.
            ASSIGN <lr_data>->* TO <la_ref>.
            write_value( ia_data  = <la_ref>
                         io_type  = cl_abap_typedescr=>describe_by_data( <la_ref> )
                         iv_path  = iv_path
                         iv_level = iv_level ).
            RETURN.
          ENDIF.
        ENDIF.
        APPEND `null` TO mt_out.

      WHEN OTHERS.
        APPEND `null` TO mt_out.

    ENDCASE.
  ENDMETHOD.


  METHOD write_struct.
    DATA lv_first TYPE abap_bool VALUE abap_true.

    DATA(lr_comps) = get_components( io_type = io_type iv_path = iv_path ).

    APPEND `{` TO mt_out.

    LOOP AT lr_comps->* REFERENCE INTO DATA(lr_comp).
      ASSIGN COMPONENT lr_comp->name OF STRUCTURE ia_data TO FIELD-SYMBOL(<la_comp>).
      CHECK sy-subrc EQ 0.

      "Skip initial values (booleans are always written: false is a value)
      IF ms_opt-skip_initial EQ abap_true AND
         lr_comp->forced     EQ abap_false AND
         lr_comp->is_bool    EQ abap_false AND
         <la_comp> IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_first EQ abap_false.
        APPEND `,` TO mt_out.
      ENDIF.
      lv_first = abap_false.

      newline( iv_level + 1 ).
      APPEND COND string( WHEN mv_pretty EQ abap_true
                          THEN |"{ lr_comp->json }": |
                          ELSE |"{ lr_comp->json }":| ) TO mt_out.

      write_value( ia_data  = <la_comp>
                   io_type  = lr_comp->type
                   iv_path  = lr_comp->path
                   iv_bool  = lr_comp->is_bool
                   iv_level = iv_level + 1 ).
    ENDLOOP.

    IF lv_first EQ abap_false.
      newline( iv_level ).
    ENDIF.
    APPEND `}` TO mt_out.
  ENDMETHOD.


  METHOD write_table.
    FIELD-SYMBOLS <lt_any> TYPE ANY TABLE.
    DATA lv_count TYPE i.

    ASSIGN ia_data TO <lt_any>.
    DATA(lo_line) = io_type->get_table_line_type( ).
    DATA(lv_bool) = is_bool( lo_line ).

    APPEND `[` TO mt_out.
    LOOP AT <lt_any> ASSIGNING FIELD-SYMBOL(<la_line>).
      lv_count = lv_count + 1.
      IF lv_count GT 1.
        APPEND `,` TO mt_out.
      ENDIF.
      newline( iv_level + 1 ).
      "Table lines keep the path of the table component (no index)
      write_value( ia_data  = <la_line>
                   io_type  = lo_line
                   iv_path  = iv_path
                   iv_bool  = lv_bool
                   iv_level = iv_level + 1 ).
    ENDLOOP.
    IF lv_count GT 0.
      newline( iv_level ).
    ENDIF.
    APPEND `]` TO mt_out.
  ENDMETHOD.


  METHOD elem_to_json.
    IF iv_bool EQ abap_true.
      rv_json = COND #( WHEN ia_data IS INITIAL THEN `false` ELSE `true` ).
      RETURN.
    ENDIF.

    CASE io_type->type_kind.

      WHEN cl_abap_typedescr=>typekind_int     OR cl_abap_typedescr=>typekind_int1
        OR cl_abap_typedescr=>typekind_int2    OR cl_abap_typedescr=>typekind_int8
        OR cl_abap_typedescr=>typekind_packed  OR cl_abap_typedescr=>typekind_float
        OR cl_abap_typedescr=>typekind_decfloat16 OR cl_abap_typedescr=>typekind_decfloat34.
        rv_json = format_number( ia_value = ia_data iv_trim = ms_opt-trim_decimals ).

      WHEN cl_abap_typedescr=>typekind_date.
        DATA(lv_date) = CONV d( ia_data ).
        IF lv_date IS INITIAL OR lv_date CO '0 '.
          rv_json = COND #( WHEN ms_opt-null_initial_date EQ abap_true THEN `null` ELSE `""` ).
        ELSE.
          rv_json = |"{ lv_date(4) }-{ lv_date+4(2) }-{ lv_date+6(2) }"|.
        ENDIF.

      WHEN cl_abap_typedescr=>typekind_time.
        DATA(lv_time) = CONV t( ia_data ).
        rv_json = |"{ lv_time(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }"|.

      WHEN cl_abap_typedescr=>typekind_hex OR cl_abap_typedescr=>typekind_xstring.
        DATA(lv_xstr) = CONV xstring( ia_data ).
        rv_json = |"{ cl_http_utility=>encode_x_base64( lv_xstr ) }"|.

      WHEN OTHERS.
        "C, N, STRING (CONV string removes trailing blanks of C)
        rv_json = |"{ escape( iv_value        = CONV string( ia_data )
                              iv_escape_slash = ms_opt-escape_slash ) }"|.

    ENDCASE.
  ENDMETHOD.


  METHOD get_components.
    READ TABLE mt_cache REFERENCE INTO DATA(lr_cache)
         WITH TABLE KEY type = io_type path = iv_path.
    IF sy-subrc NE 0.
      DATA(ls_cache) = VALUE ty_cache( type = io_type path = iv_path ).

      "Included view: .INCLUDE / INCLUDE TYPE components are flattened
      LOOP AT io_type->get_included_view( ) INTO DATA(ls_view).
        DATA(lv_name) = CONV string( ls_view-name ).
        DATA(lv_path) = COND string( WHEN iv_path IS INITIAL THEN lv_name
                                     ELSE |{ iv_path }-{ lv_name }| ).
        "Key: explicit map by path, explicit map by name, automatic
        READ TABLE mt_name_map INTO DATA(ls_map) WITH TABLE KEY abap = lv_path.
        IF sy-subrc NE 0.
          READ TABLE mt_name_map INTO ls_map WITH TABLE KEY abap = lv_name.
          IF sy-subrc NE 0.
            ls_map-json = json_name( iv_abap_name = lv_name iv_case = ms_opt-name_case ).
          ENDIF.
        ENDIF.

        APPEND VALUE #( name    = lv_name
                        path    = lv_path
                        json    = escape( iv_value = ls_map-json iv_escape_slash = abap_false )
                        type    = ls_view-type
                        forced  = xsdbool( line_exists( mt_always[ table_line = lv_path ] ) OR
                                           line_exists( mt_always[ table_line = lv_name ] ) )
                        is_bool = is_bool( ls_view-type ) ) TO ls_cache-comps.
        CLEAR ls_map.
      ENDLOOP.

      INSERT ls_cache INTO TABLE mt_cache REFERENCE INTO lr_cache.
    ENDIF.

    rr_comps = REF #( lr_cache->comps ).
  ENDMETHOD.


  METHOD is_bool.
    CHECK io_type IS BOUND AND io_type->kind EQ cl_abap_typedescr=>kind_elem.
    rv_bool = xsdbool( line_exists( mt_bool_types[ table_line = io_type->get_relative_name( ) ] ) ).
  ENDMETHOD.


  METHOD newline.
    CHECK mv_pretty EQ abap_true.
    APPEND cl_abap_char_utilities=>newline && repeat( val = `  ` occ = iv_level ) TO mt_out.
  ENDMETHOD.


  METHOD json_name.
    CASE iv_case.
      WHEN co_case-none.
        rv_key = iv_abap_name.
      WHEN co_case-camel.
        SPLIT to_lower( iv_abap_name ) AT `_` INTO TABLE DATA(lt_part).
        LOOP AT lt_part INTO DATA(lv_part).
          IF rv_key IS INITIAL OR lv_part IS INITIAL.
            rv_key = rv_key && lv_part.
          ELSE.
            rv_key = rv_key && to_upper( substring( val = lv_part len = 1 ) )
                            && substring( val = lv_part off = 1 ).
          ENDIF.
        ENDLOOP.
      WHEN OTHERS.
        rv_key = to_lower( iv_abap_name ).
    ENDCASE.
  ENDMETHOD.


  METHOD format_number.
    DATA lv_df TYPE decfloat34.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( ia_value ).

    CASE lo_type->type_kind.
      WHEN cl_abap_typedescr=>typekind_int  OR cl_abap_typedescr=>typekind_int1 OR
           cl_abap_typedescr=>typekind_int2 OR cl_abap_typedescr=>typekind_int8 OR
           cl_abap_typedescr=>typekind_packed.
        "String template: '.' as decimal sign, no grouping, sign in front
        rv_json = |{ ia_value }|.
      WHEN OTHERS.
        "F, DECFLOAT and numeric text ('5.00', '12.5-') via DECFLOAT34
        TRY.
            lv_df = condense( CONV string( ia_value ) ).
            rv_json = |{ lv_df }|.
          CATCH cx_sy_conversion_error cx_sy_arithmetic_error.
            rv_json = `0`.
        ENDTRY.
    ENDCASE.

    CONDENSE rv_json NO-GAPS.
    "Defensive: trailing minus -> leading minus
    IF rv_json CP '*-'.
      rv_json = |-{ substring( val = rv_json len = strlen( rv_json ) - 1 ) }|.
    ENDIF.
    IF rv_json IS NOT INITIAL AND substring( val = rv_json len = 1 ) EQ `+`.
      rv_json = substring( val = rv_json off = 1 ).
    ENDIF.

    "47.50 -> 47.5 / 5.00 -> 5 (not for exponent notation)
    IF iv_trim EQ abap_true AND rv_json CA '.' AND rv_json NA 'Ee'.
      rv_json = replace( val = rv_json pcre = '(\.\d*[1-9])0+$|\.0+$' with = '$1' ).
    ENDIF.
    IF rv_json IS INITIAL OR rv_json EQ `-0`.
      rv_json = `0`.
    ENDIF.
  ENDMETHOD.


  METHOD escape.
    rv_json = iv_value.
    CHECK rv_json IS NOT INITIAL.

    REPLACE ALL OCCURRENCES OF `\` IN rv_json WITH `\\`.
    REPLACE ALL OCCURRENCES OF `"` IN rv_json WITH `\"`.
    IF iv_escape_slash EQ abap_true.
      REPLACE ALL OCCURRENCES OF `/` IN rv_json WITH `\/`.
    ENDIF.

    "Control characters U+0000 .. U+001F
    CHECK find( val = rv_json pcre = '[\x00-\x1F]' ) GE 0.

    DATA(lv_cr) = substring( val = cl_abap_char_utilities=>cr_lf len = 1 ).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline        IN rv_json WITH `\n`.
    REPLACE ALL OCCURRENCES OF lv_cr                                  IN rv_json WITH `\r`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_json WITH `\t`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed      IN rv_json WITH `\f`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>backspace      IN rv_json WITH `\b`.

    "Any other control character -> \u00XX
    DATA(lv_off) = find( val = rv_json pcre = '[\x00-\x1F]' ).
    WHILE lv_off GE 0.
      DATA(lv_hex) = CONV string( cl_abap_codepage=>convert_to(
                                    source   = substring( val = rv_json off = lv_off len = 1 )
                                    codepage = `UTF-16BE` ) ).
      rv_json = substring( val = rv_json len = lv_off ) &&
                |\\u{ to_lower( lv_hex ) }| &&
                substring( val = rv_json off = lv_off + 1 ).
      lv_off = find( val = rv_json pcre = '[\x00-\x1F]' off = lv_off + 6 ).
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.

