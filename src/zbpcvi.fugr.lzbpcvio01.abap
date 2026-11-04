*----------------------------------------------------------------------*
***INCLUDE LZBPCVIO01.
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Module STATUS_9000 OUTPUT
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
MODULE status_9000 OUTPUT.

  DATA: lt_values TYPE vrm_values.

  CALL FUNCTION 'ZBPCVI_PBO'.
  IF cvi_bdt_adapter=>get_activity( ) EQ '03'
     OR cvi_bdt_adapter=>get_current_customer( ) IS INITIAL. "display only if no customer
    LOOP AT SCREEN.
      screen-input = 0.
      MODIFY SCREEN.
    ENDLOOP.
  ENDIF.

**  SELECT a~businesstype AS key,
**         b~ddtext       AS text
**         FROM zeinv_busi_type AS a LEFT OUTER JOIN dd07t AS b ON b~domname    EQ 'ZDO_BUSINESS_TYPE' AND
**                                                                 b~ddlanguage EQ @sy-langu           AND
**                                                                 b~as4local   EQ 'A'                 AND
**                                                                 b~domvalue_l EQ a~businesstype
**         INTO CORRESPONDING FIELDS OF TABLE @lt_values
**         WHERE a~active EQ @abap_true
**         ORDER BY a~businesstype ASCENDING.
**
***  IF lt_values[] IS NOT INITIAL.
**
**  CALL FUNCTION 'VRM_SET_VALUES'
**    EXPORTING
**      id              = 'gs_knb1-ZZBUSINESSTYPE'
**      values          = lt_values
**    EXCEPTIONS
**      id_illegal_name = 1
**      OTHERS          = 2.
**
***  ENDIF.

ENDMODULE.
