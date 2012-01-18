PKLEInstance.i18n_ru = new function()
{
  var language_pack_ =
  {
    '<CN>' : '<hr><span style="\
        -webkit-border-radius: 0.3em;\
        -moz-border-radius: 0.3em;\
        border-radius: 0.3em;\
        border: 2px solid #9D9 !important;\
        background-color: #CFC;\
        font-family:Arial;\
        font-size:12px;\
        font-weight:bold;\
      ">\
      &copy; 2010&ndash;2012 <a href="http://logiceditor.com">LogicEditor.com</a> \
      </span>',

    //----- Common UI -----

    'Failure' : 'Неудача',
    'Error' : 'Ошибка',

    'Value is invalid: ' : 'Неправильное значение: ',

    'Use cases' : 'Сценарии',
    'Use case' : 'Сценарий',
    'Administration' : 'Администрирование',

    'Cancel' : 'отмена',

    'Log' : 'Лог',
    'View log' : 'Лог',
    'Script data loading' : 'Загрузка скрипта',
    'Load script data' : 'Загрузить скрипт',

    'Prototype' : 'Прототип',

    //----- Index, title and controls -----

    'Page title prefix' : 'Редактор запросов Т.: Отзывы',

    'Welcome to the project' : 'Добро пожаловать в редактор',

    'Legend': 'Легенда',
    '(untitled)': '(без имени)',
    'Last copied use case' : 'Новый',

    //----- Use cases -----

    'Current script' : 'Сценарий',
    'Simple case' : 'Простейший скрипт',

    //----- PKLE control -----

    'Undo' : 'Отменить',
    'Redo' : 'Повторить',
    'Clear script' : 'Очистить скрипт',
    'Send to server' : 'Данные --> сервер',
    'Options' : 'Настройки',
    'Put data to log' : 'Данные --> лог',
    'View log' : 'View log',

    '<fake>' : '<fake>'
  }

  this.init = function()
  {
    PKLE.i18n_ru.init()
    PK.i18n.extend_language_pack("Russian", language_pack_)
    PK.i18n.set_current_language(PK.i18n.language.Russian)
  }
}
