*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_CN_RSN_SD.................................*
DATA:  BEGIN OF STATUS_ZEINV_CN_RSN_SD               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_CN_RSN_SD               .
CONTROLS: TCTRL_ZEINV_CN_RSN_SD
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_CN_RSN_SD               .
TABLES: ZEINV_CN_RSN_SD                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
