*----------------------------------------------------------------------*
***INCLUDE LZEINV_ALLOWANCEF01.
*----------------------------------------------------------------------*

FORM before_save.

  IF zeinv_allowance-kschl IS NOT INITIAL.

    SELECT SINGLE vtext
                  FROM t685t
                  INTO @zeinv_allowance-kschl_name
                  WHERE spras EQ @sy-langu AND
                        kvewe EQ 'A'       AND
                        kschl EQ @zeinv_allowance-kschl.

  ENDIF.

ENDFORM.

FORM new_entry.

  SELECT SINGLE vtext
                FROM t685t
                INTO @zeinv_allowance-kschl_name
                WHERE spras EQ @sy-langu AND
                      kvewe EQ 'A'       AND
                      kschl EQ @zeinv_allowance-kschl.

ENDFORM.
