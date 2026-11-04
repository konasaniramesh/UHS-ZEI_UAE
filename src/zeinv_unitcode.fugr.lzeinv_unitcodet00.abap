*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_UNITCODE..................................*
DATA:  BEGIN OF STATUS_ZEINV_UNITCODE                .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_UNITCODE                .
CONTROLS: TCTRL_ZEINV_UNITCODE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_UNITCODE                .
TABLES: ZEINV_UNITCODE                 .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
