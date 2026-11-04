*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_DLV_PF_DET................................*
DATA:  BEGIN OF STATUS_ZEINV_DLV_PF_DET              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_DLV_PF_DET              .
CONTROLS: TCTRL_ZEINV_DLV_PF_DET
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_DLV_PF_DET              .
TABLES: ZEINV_DLV_PF_DET               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
