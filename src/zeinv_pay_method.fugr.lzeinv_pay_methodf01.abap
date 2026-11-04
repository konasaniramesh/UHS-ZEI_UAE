*----------------------------------------------------------------------*
***INCLUDE LZEINV_PAY_METHODF01.
*----------------------------------------------------------------------*

FORM hidden.

  SELECT SINGLE ddtext
                FROM dd07t
                INTO @zeinv_pay_method-eipayment_method_name
                WHERE domname   EQ 'ZDO_V_EIPAYMENT_METHOD' AND
                      ddlanguage EQ @sy-langu               AND
                      as4local   EQ 'A'                     AND
                      domvalue_l EQ @zeinv_pay_method-eipayment_method.

ENDFORM.
