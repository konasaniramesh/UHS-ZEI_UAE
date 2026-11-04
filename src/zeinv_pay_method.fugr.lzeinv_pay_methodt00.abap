*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_PAY_METHOD................................*
DATA:  BEGIN OF STATUS_ZEINV_PAY_METHOD              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_PAY_METHOD              .
CONTROLS: TCTRL_ZEINV_PAY_METHOD
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_PAY_METHOD              .
TABLES: ZEINV_PAY_METHOD               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
