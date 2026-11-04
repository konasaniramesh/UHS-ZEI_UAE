*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_ALLOWANCE.................................*
DATA:  BEGIN OF STATUS_ZEINV_ALLOWANCE               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_ALLOWANCE               .
CONTROLS: TCTRL_ZEINV_ALLOWANCE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_ALLOWANCE               .
TABLES: ZEINV_ALLOWANCE                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
