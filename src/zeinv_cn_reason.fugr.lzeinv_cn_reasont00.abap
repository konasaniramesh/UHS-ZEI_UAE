*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_CN_REASON.................................*
DATA:  BEGIN OF STATUS_ZEINV_CN_REASON               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_CN_REASON               .
CONTROLS: TCTRL_ZEINV_CN_REASON
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_CN_REASON               .
TABLES: ZEINV_CN_REASON                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
