"! <p class="shorttext synchronized">E-Invoice JSON builder / parser error</p>
"! Raised by ZCL_EI_JSON_PARSER (syntax error, unexpected end of input ...)
"! Create in SE24 / ADT as exception class (superclass CX_STATIC_CHECK,
"! no message class, "With Message Class" unchecked).
CLASS zcx_ei_json DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA mv_text   TYPE string READ-ONLY.
    DATA mv_offset TYPE i      READ-ONLY.

    METHODS constructor
      IMPORTING
        textid    LIKE textid   OPTIONAL
        previous  LIKE previous OPTIONAL
        iv_text   TYPE string   OPTIONAL
        iv_offset TYPE i        OPTIONAL.

    METHODS get_text REDEFINITION.
ENDCLASS.


CLASS zcx_ei_json IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( textid = textid previous = previous ).
    mv_text   = iv_text.
    mv_offset = iv_offset.
  ENDMETHOD.

  METHOD get_text.
    result = |JSON error: { mv_text } (offset { mv_offset })|.
  ENDMETHOD.

ENDCLASS.

