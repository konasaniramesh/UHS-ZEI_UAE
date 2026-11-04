*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_INVTYPE_SD................................*
DATA:  BEGIN OF STATUS_ZEINV_INVTYPE_SD              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_INVTYPE_SD              .
CONTROLS: TCTRL_ZEINV_INVTYPE_SD
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_INVTYPE_SD              .
TABLES: ZEINV_INVTYPE_SD               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
