*----------------------------------------------------------------------*
***INCLUDE LZEINV_COMPANYF01.
*----------------------------------------------------------------------*

FORM new_entry.

  IF zeinv_company-bukrs IS NOT INITIAL.

    SELECT SINGLE b~name1 && @space && b~name2
                  FROM t001 AS a LEFT OUTER JOIN adrc AS b ON b~addrnumber EQ a~adrnr
                  INTO @zeinv_company-butxt
                  WHERE a~bukrs EQ @zeinv_company-bukrs.

  ENDIF.

ENDFORM.

FORM before_save.

  IF zeinv_company-bukrs IS NOT INITIAL.

    SELECT SINGLE b~name1 && @space && b~name2
                  FROM t001 AS a LEFT OUTER JOIN adrc AS b ON b~addrnumber EQ a~adrnr
                  INTO @zeinv_company-butxt
                  WHERE a~bukrs EQ @zeinv_company-bukrs.

  ENDIF.

ENDFORM.

FORM hidden.

  IF zeinv_company-bukrs IS NOT INITIAL.

    SELECT SINGLE a~land1,
                  b~landx50
                  FROM t001 AS a LEFT OUTER JOIN t005t AS b ON b~spras EQ @sy-langu AND
                                                               b~land1 EQ a~land1
                  INTO ( @zeinv_company-land1, @zeinv_company-landx50 )
                  WHERE a~bukrs EQ @zeinv_company-bukrs.

  ENDIF.

ENDFORM.
