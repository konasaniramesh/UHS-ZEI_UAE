*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_COMPANY...................................*
DATA:  BEGIN OF STATUS_ZEINV_COMPANY                 .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_COMPANY                 .
CONTROLS: TCTRL_ZEINV_COMPANY
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_COMPANY                 .
TABLES: ZEINV_COMPANY                  .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
