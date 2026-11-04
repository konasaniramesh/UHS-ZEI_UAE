*----------------------------------------------------------------------*
***INCLUDE ZEINVOICE_CONFIG_TABLES_PAI.
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Module USER_COMMAND_9000 INPUT
*&---------------------------------------------------------------------*
* text
*----------------------------------------------------------------------*
MODULE user_command_9000 INPUT.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL'.
      LEAVE TO SCREEN 0.
    WHEN gc_open.                "entry clicked on the HTML page
      DATA(lv_open) = gv_open.
      CLEAR gv_open.
      lcl_event=>open_view( lv_open ).
  ENDCASE.
ENDMODULE.
