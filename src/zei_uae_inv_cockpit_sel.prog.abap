*&---------------------------------------------------------------------*
*& Include          ZEI_UAE_INV_COCKPIT_SEL
*&---------------------------------------------------------------------*
TABLES: vbrk, knb1.

"Reference fields of S_TYPE / S_STATUS - same dictionary types (F1 / F4 help
"unchanged) instead of a TABLES work area of the enhanceable table ZEINVOICE_ERROR
DATA: gv_sel_type  TYPE zeinvoice_error-type,
      gv_sel_msgty TYPE zeinvoice_error-msgty.

SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE t_b01.
  SELECT-OPTIONS: s_bukrs FOR vbrk-bukrs NO-EXTENSION
                                         NO INTERVALS,
                                         "required entry - checked in LCL_SELSCREEN=>PAI (HTML selection screen)
                  s_vbeln FOR vbrk-vbeln,
                  s_erdat FOR vbrk-erdat NO-EXTENSION,
                  s_btype FOR knb1-zzbusinesstype NO-DISPLAY,
                  s_type  FOR gv_sel_type NO-DISPLAY.
  PARAMETERS: p_btype TYPE knb1-zzbusinesstype AS LISTBOX VISIBLE LENGTH 30,
              p_type  TYPE zde_ei_type AS LISTBOX VISIBLE LENGTH 20.
  SELECT-OPTIONS: s_status FOR gv_sel_msgty NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b01.


"HTML cockpit screen (replaces the ALV grid) - the HTML viewer is
"placed on the full screen area, see LCL_COCKPIT
TABLES sscrfields.
SELECTION-SCREEN BEGIN OF SCREEN 1001 TITLE t_1001.
  SELECTION-SCREEN COMMENT /1(1) t_c1001.
SELECTION-SCREEN END OF SCREEN 1001.
