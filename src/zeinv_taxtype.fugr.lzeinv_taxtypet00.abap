*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_TAXTYPE...................................*
DATA:  BEGIN OF STATUS_ZEINV_TAXTYPE                 .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_TAXTYPE                 .
CONTROLS: TCTRL_ZEINV_TAXTYPE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_TAXTYPE                 .
TABLES: ZEINV_TAXTYPE                  .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
