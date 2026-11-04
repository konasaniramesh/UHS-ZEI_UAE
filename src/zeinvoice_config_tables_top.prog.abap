*&---------------------------------------------------------------------*
*& Include ZEINVOICE_CONFIG_TABLES_TOP
*&---------------------------------------------------------------------*
*& E-Invoice Configuration - HTML start page (replaces the simple tree).
*& Every entry opens the maintenance of its view exactly as before
*& (VIEW_MAINTENANCE_CALL, action 'U'). The page is built and loaded
*& once; the search filters the entries in the browser (no round trip).
*& The page uses the full screen area and adapts to the window size; it
*& is hidden while a view is maintained and shown again afterwards.
*&---------------------------------------------------------------------*

CLASS lcl_event DEFINITION DEFERRED.

TYPES: BEGIN OF ty_item,
         key  TYPE string,     "former tree node key (R1C1 ...) - unchanged
         grp  TYPE i,          "section = row number in GT_GROUPS
         text TYPE string,
         view TYPE tabname,
       END OF ty_item,
       tt_item TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY,
       BEGIN OF ty_group,      "one section of the page (display order)
         icon  TYPE string,    "symbol id in the icon sprite (i1 ...)
         color TYPE string,    "icon colour class (g1 ...)
         title TYPE string,
         descr TYPE string,
         parent TYPE string,   "main title the section is grouped under (optional)
         pdescr TYPE string,   "description of the main title (first section)
       END OF ty_group,
       tt_group TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.

DATA: go_html   TYPE REF TO cl_gui_html_viewer,
      go_event  TYPE REF TO lcl_event,
      gt_items  TYPE tt_item,
      gt_groups TYPE tt_group,
      gv_open   TYPE string.    "entry clicked on the page - opened in PAI

CONSTANTS gc_open TYPE sy-ucomm VALUE 'ZOPEN'.

CLASS lcl_event DEFINITION.
  PUBLIC SECTION.
    METHODS on_sapevent FOR EVENT sapevent OF cl_gui_html_viewer
      IMPORTING action query_table.
    CLASS-METHODS open_view IMPORTING iv_key TYPE string.
ENDCLASS.
