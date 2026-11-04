*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_STATE.....................................*
DATA:  BEGIN OF STATUS_ZEINV_STATE                   .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_STATE                   .
CONTROLS: TCTRL_ZEINV_STATE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_STATE                   .
TABLES: ZEINV_STATE                    .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
