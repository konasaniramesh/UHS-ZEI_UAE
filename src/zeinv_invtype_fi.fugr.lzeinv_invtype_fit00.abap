*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_INVTYPE_FI................................*
DATA:  BEGIN OF STATUS_ZEINV_INVTYPE_FI              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_INVTYPE_FI              .
CONTROLS: TCTRL_ZEINV_INVTYPE_FI
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_INVTYPE_FI              .
TABLES: ZEINV_INVTYPE_FI               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
