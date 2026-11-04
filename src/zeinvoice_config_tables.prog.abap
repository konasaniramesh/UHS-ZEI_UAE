*&---------------------------------------------------------------------*
*& Report ZEINVOICE_CONFIG_TABLES
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zeinvoice_config_tables.

INCLUDE zeinvoice_config_tables_top.
INCLUDE zeinvoice_config_tables_pbo.
INCLUDE zeinvoice_config_tables_pai.

START-OF-SELECTION.

  CALL SCREEN 9000.
