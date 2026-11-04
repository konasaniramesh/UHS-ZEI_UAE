*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_DCHANNEL..................................*
DATA:  BEGIN OF STATUS_ZEINV_DCHANNEL                .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_DCHANNEL                .
CONTROLS: TCTRL_ZEINV_DCHANNEL
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_DCHANNEL                .
TABLES: ZEINV_DCHANNEL                 .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
