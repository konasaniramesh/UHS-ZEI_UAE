*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_ITEM_CATEG................................*
DATA:  BEGIN OF STATUS_ZEINV_ITEM_CATEG              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_ITEM_CATEG              .
CONTROLS: TCTRL_ZEINV_ITEM_CATEG
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_ITEM_CATEG              .
TABLES: ZEINV_ITEM_CATEG               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
