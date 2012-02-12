// TODO: Replace this with YOUR server URL.
var SERVER_URL = "http://omsk.tulp.dev/dbstats/reviews"

//------------------------------------------------------------------------------

PKLEInstance.init_logic_editor = function()
{
  var do_before_logic_editor_object_data_change = function(skip_undo_redo)
  {
    // TODO: Write code here to prepare for data change

    return true
  }

  var refresh_after_logic_editor_object_data_change = function(
      tree_operation, parent_node, child_node, child_index, other_child_index
    )
  {
    var object_data = logic_editor.get_object_data()

    var serialized_object_data = logic_editor.serialize_object_data_to_json(object_data)

    PKLEInstance.init_pkle_control(serialized_object_data)
  }

  logic_editor.init(
      SERVER_URL,
      do_before_logic_editor_object_data_change,
      refresh_after_logic_editor_object_data_change
    )
}

//------------------------------------------------------------------------------

PKLEInstance.init_pkle_control = function(serialized_object_data)
{
  var object_data = logic_editor.unserialize_object_data_from_json(serialized_object_data)

  logic_editor.set_object_data(object_data, false, false)

  var gui_object_data = {
    use_std_html_styling: undefined,
    raw_html : undefined,
    items : undefined,
    tooltips: undefined,
    handlers: undefined
  }

  logic_editor.render(gui_object_data)
  PK.data_tree_rendering.set_handlers(gui_object_data.handlers)

  var el = assert(PK.browser_dom.get_object_by_id("pk-le-ctrl-impl"))

  el.innerHTML = gui_object_data.raw_html
}
