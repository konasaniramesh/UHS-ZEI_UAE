*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_CN_RSN_FI.................................*
DATA:  BEGIN OF STATUS_ZEINV_CN_RSN_FI               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_CN_RSN_FI               .
CONTROLS: TCTRL_ZEINV_CN_RSN_FI
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_CN_RSN_FI               .
TABLES: ZEINV_CN_RSN_FI                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
