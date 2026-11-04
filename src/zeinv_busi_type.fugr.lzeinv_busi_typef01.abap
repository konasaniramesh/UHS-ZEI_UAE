*----------------------------------------------------------------------*
***INCLUDE LZEINV_BUSI_TYPEF01.
*----------------------------------------------------------------------*

FORM after_save.

  DATA: ls_data TYPE zeinv_busi_type,
        ls_knb1 TYPE knb1,
        lv_line TYPE text32.

  FIELD-SYMBOLS: <lt_total> TYPE ANY TABLE,
                 <lv_line>  TYPE text32.

  ASSIGN total_restore->* TO <lt_total>.

  CHECK <lt_total> IS ASSIGNED AND
        <lt_total>[] IS NOT INITIAL.

  SELECT *
         FROM knb1
         WHERE zzbusinesstype IS NOT INITIAL
         INTO TABLE @DATA(lt_knb1).

  LOOP AT <lt_total> ASSIGNING FIELD-SYMBOL(<ls_total>).

    ASSIGN COMPONENT 'LINE' OF STRUCTURE <ls_total> TO <lv_line>.
    IF sy-subrc EQ 0.
      DATA(lv_action) = <lv_line>+9(1).
    ENDIF.

    ls_data = <ls_total>.

    "New or Update
    IF lv_action EQ 'N' OR
       lv_action EQ 'U'.
      ls_knb1-zzeinvoice = ls_data-active.
    ENDIF.

    "Deleted
    IF lv_action EQ 'D' OR
       lv_action EQ 'Y'.
      ls_knb1-zzeinvoice = abap_false.
    ENDIF.

    MODIFY lt_knb1 FROM ls_knb1 TRANSPORTING zzeinvoice
                                WHERE zzbusinesstype EQ ls_data-businesstype.

  ENDLOOP.

  IF lt_knb1[] IS NOT INITIAL.
    MODIFY knb1 FROM TABLE lt_knb1.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' DESTINATION 'NONE'
      EXPORTING
        wait = abap_true.
  ENDIF.

ENDFORM.
