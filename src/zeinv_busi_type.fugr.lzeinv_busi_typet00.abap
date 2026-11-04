*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_BUSI_TYPE.................................*
DATA:  BEGIN OF STATUS_ZEINV_BUSI_TYPE               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_BUSI_TYPE               .
CONTROLS: TCTRL_ZEINV_BUSI_TYPE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_BUSI_TYPE               .
TABLES: ZEINV_BUSI_TYPE                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
