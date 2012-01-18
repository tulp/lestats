Ext.onReady(function()
{
  var MAX_UNDO_DEPTH = 15

  PKLE.Settings.set("universal_C_button", false)

  if (Ext.isIE && (Ext.isIE6 || Ext.isIE7) )
  {
    PKLE.Settings.set("render_new_item_placeholders_in_list", false)
  }

  Ext.QuickTips.init();

  PK.override_menu_item_to_enable_tooltips();

  PKLEInstance.i18n_ru.init();

  PK.LEWidgets = PK.LEWidgetsImpl.html

  PK.data_tree_processor.init();

  PKLE.UndoRedo.Init(MAX_UNDO_DEPTH);

  PKLEInstance.init_logic_editor();

  PKLEInstance.init_pkle_control(EXAMPLE_OBJECT_DATA);
});
