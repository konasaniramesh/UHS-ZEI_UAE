*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_INVTYPE...................................*
DATA:  BEGIN OF STATUS_ZEINV_INVTYPE                 .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_INVTYPE                 .
CONTROLS: TCTRL_ZEINV_INVTYPE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_INVTYPE                 .
TABLES: ZEINV_INVTYPE                  .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
