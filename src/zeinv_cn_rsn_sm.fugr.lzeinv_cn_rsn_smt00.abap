*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_CN_RSN_SM.................................*
DATA:  BEGIN OF STATUS_ZEINV_CN_RSN_SM               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_CN_RSN_SM               .
CONTROLS: TCTRL_ZEINV_CN_RSN_SM
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_CN_RSN_SM               .
TABLES: ZEINV_CN_RSN_SM                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
