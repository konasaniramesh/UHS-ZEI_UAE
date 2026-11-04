*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZEINV_COMPANYGRP................................*
DATA:  BEGIN OF STATUS_ZEINV_COMPANYGRP              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZEINV_COMPANYGRP              .
CONTROLS: TCTRL_ZEINV_COMPANYGRP
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZEINV_COMPANYGRP              .
TABLES: ZEINV_COMPANYGRP               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
