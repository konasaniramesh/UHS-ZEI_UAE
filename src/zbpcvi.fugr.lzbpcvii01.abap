*----------------------------------------------------------------------*
***INCLUDE LZBPCVII01.
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_9000  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE user_command_9000 INPUT.
  CALL FUNCTION 'ZBPCVI_PAI'.
ENDMODULE.
*&---------------------------------------------------------------------*
*&      Module  MODIFY  INPUT
*&---------------------------------------------------------------------*
*       Derive E-Invoice applicability from Business Type
*       (fields moved from BUT000 to KNB1 - customer company code)
*----------------------------------------------------------------------*
MODULE modify INPUT.

  IF gs_knb1-zzbusinesstype IS NOT INITIAL.
    SELECT SINGLE active
                  FROM zeinv_busi_type
                  INTO @DATA(lv_active)
                  WHERE bukrs        EQ @gs_knb1-bukrs AND
                        businesstype EQ @gs_knb1-zzbusinesstype.
    IF sy-subrc EQ 0.
      gs_knb1-zzeinvoice = lv_active.
    ELSE.
      gs_knb1-zzeinvoice = abap_false.
    ENDIF.
  ELSE.
    gs_knb1-zzeinvoice = abap_false.
  ENDIF.

ENDMODULE.
