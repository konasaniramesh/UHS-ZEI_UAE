*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINVOICE_APIURL................................*
DATA:  BEGIN OF STATUS_ZEINVOICE_APIURL              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINVOICE_APIURL              .
CONTROLS: TCTRL_ZEINVOICE_APIURL
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINVOICE_APIURL              .
TABLES: ZEINVOICE_APIURL               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
