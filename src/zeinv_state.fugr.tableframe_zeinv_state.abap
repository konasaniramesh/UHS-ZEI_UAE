*---------------------------------------------------------------------*
*    program for:   TABLEFRAME_ZEINV_STATE
*---------------------------------------------------------------------*
FUNCTION TABLEFRAME_ZEINV_STATE        .

  PERFORM TABLEFRAME TABLES X_HEADER X_NAMTAB DBA_SELLIST DPL_SELLIST
                            EXCL_CUA_FUNCT
                     USING  CORR_NUMBER VIEW_ACTION VIEW_NAME.

ENDFUNCTION.
