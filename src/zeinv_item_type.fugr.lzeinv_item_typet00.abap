*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_ITEM_TYPE.................................*
DATA:  BEGIN OF STATUS_ZEINV_ITEM_TYPE               .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_ITEM_TYPE               .
CONTROLS: TCTRL_ZEINV_ITEM_TYPE
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_ITEM_TYPE               .
TABLES: ZEINV_ITEM_TYPE                .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
