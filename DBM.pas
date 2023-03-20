unit DBM;

{*
   Класс TDBM

   Предназначен для управления базой данных, представляющей собой структуру каталогов.
   Класс поддерживает правильную структуру, нумерацию, чтение и обновление
   информации на диске при обновлении информации в визуальном представлении и т.п.

   То есть класс TDBM "прячет" детали
   реализации работы с базой данных от приложения.


   19.03.2023
   Т.Олесницкий
*}

interface

uses
  Winapi.Windows, System.Classes, System.UITypes,
  RegularExpressions,
  Dialogs;

const
  // Версия базы данных "по умолчанию", если явно не указано
  UNKNOWN_DBM_DB_VERSION = 1;
  // Текущая версия базы данных
  CURRENT_DBM_DB_VERSION = 2;

type
  TDBM = class(TObject)
  private
    FBaseDir: String;
    FCurrentDBVersion: Integer;
    FDBList: TStringList;
    FCurrentDBDir: String;
    FCurrentDBName: String;
    FCurrentDBIndex: Integer;
    // ... ЧАСТЬ КОДА СКРЫТА
    FCurrentDBLabel: String;
    FDBItems: TList;
    function FGetIsDBSelected: Boolean;
    procedure FGetDBItems;
    procedure FGetDBList;
    function ConstructDirName(N: Integer; Text: String; StrictTemplate: Boolean = False): String;
    procedure ReadDBIni;
    procedure WriteDBIni;
  public
    constructor Create(BaseDir: String);
    // Список доступных баз данных
    property DBList: TStringList read FDBList;
    // Версия текущей базы данных
    property DBersion: Integer read FCurrentDBVersion;
    // Список элементов текущей базы данных
    property DBItems: TList read FDBItems;
    // Текущий каталог базы данных
    property CurrentDBDir: String read FCurrentDBDir;
    // Название текущей базы данных
    property CurrentDBName: String read FCurrentDBName;
    // ... ЧАСТЬ КОДА СКРЫТА
    //
    // ... ЧАСТЬ КОДА СКРЫТА
    //
    property CurrentDBLabel: String read FCurrentDBLabel;
    // Признак, выбрана ли база данных в настоящий момент
    property IsDBSelected: Boolean read FGetIsDBSelected;
    // Создать БД
    procedure AddDB(DBName: String);
    // Выбрать БД
    procedure SelectDB(DBName: String);
    // Добавить элемент БД
    procedure AddDBItem(var Item: TDBItem; Before: Integer = -1);
    // Обновить элемент БД номер ItemIndex согласно его представлению в DBItems[ItemIndex]
    procedure UpdateDBItem(ItemIndex: Integer; TestOnly: Boolean = False);
    // Удалить элемент БД
    procedure DeleteDBItem(ItemIndex: Integer);
    // Объединить элемент с предыдущим
    procedure JoinWithPrevious(ItemIndex: Integer);
    // ... ЧАСТЬ КОДА СКРЫТА
    // Проверка целостности базы данных
    function CheckDBIntegrity(var Msg: String; FullCheck: Boolean = False): Boolean;
    //
    procedure V1ToV2;
  end;


implementation

uses
  SysUtils;

{ DBM }

// Функция сравнения, необходимая для сортировки (пока не используется)
function compareByName(Item1 : Pointer; Item2 : Pointer) : Integer;
var
  DBItem1, DBItem2 : TDBItem;
begin
  DBItem1 := TDBItem(Item1);
  DBItem2 := TDBItem(Item2);

  // Теперь сравнение строк
  if DBItem1.N > DBItem2.N
  then Result := 1
  else Result := -1;
end;

procedure TDBM.AddDB(DBName: String);
begin
  try
    MkDir(FBaseDir + DBName);
    FGetDBList;
  except
    on E:Exception do
    begin
      raise Exception.Create(
        Format('Не удалось добавить базу данных %s. %s', [DBName, E.Message])
      );
    end;
  end;
end;

procedure TDBM.AddDBItem(var Item: TDBItem; Before: Integer = -1);
var
  i: Integer;
  index: Integer;
  citem: TDBItem;
  newdirname, newdirname2: String;
begin
  if ((Before < 0) or (Before > FDBItems.Count - 1)) then
  begin
    // Вставка в конец набора данных
    Item.N := FDBItems.Count + 1;
    FDBItems.Add(Item);
    index := FDBItems.Count - 1;
  end
  else
  begin
    index := Before;
    FDBItems.Insert(index, Item);

    // Сначала производим действия для всех элементов, которые передвинуты вправо
    // Причём в обратном порядке (чтобы не было накладок с названиями папок)
    for i := FDBItems.Count - 1 downto index + 1 do
    begin
      citem := TDBItem(FDBItems[i]);
      citem.N := i + 1;
      UpdateDBItem(i);
    end;
  end;

  Item.N := index + 1;
  newdirname := ConstructDirName(Item.N, Item.Text, False);
  // Каталога в этот момент быть ещё не должно
  if DirectoryExists(FCurrentDBDir + newdirname) then
  begin
    raise Exception.Create(Format(
      'Ошибка при попытке создания каталога "%s": каталог уже существует. Проверьте целостность базы данных.',
      [FCurrentDBDir + newdirname]));
  end
  else
  begin
    if not SysUtils.ForceDirectories(FCurrentDBDir + newdirname) then
    begin
      // Пытались создать каталог, но не смогли. Возможно, дело в символах, попробуем другие
      newdirname2 := ConstructDirName(Item.N, Item.Text, True);
      // Каталога в этот момент быть ещё не должно
      if DirectoryExists(FCurrentDBDir + newdirname2) then
      begin
        raise Exception.Create(Format(
          'Ошибка при попытке создания каталога "%s": каталог уже существует. Проверьте целостность базы данных.',
          [FCurrentDBDir + newdirname2]));
      end
      else
        if not SysUtils.ForceDirectories(FCurrentDBDir + newdirname2) then
        begin
          // Не смогли создать каталог и со второй попытки!
          raise Exception.Create(Format(
            'Ошибка при попытках создания каталогов "%s" ("%s") для нового элемента базы данных. Проверьте доступность каталога для записи.',
            [FCurrentDBDir + newdirname, FCurrentDBDir + newdirname2]));
        end
        else
          newdirname := newdirname2;
     end;
  end;

  Item.DirName := newdirname;
  Item.HasSoundRec := False;
  Item.RSL := '';
  // Собственно вставка элемента и запись информации о нём на диск
  FDBItems[index] := Item;
  UpdateDBItem(index);

end;

procedure TDBM.DeleteDBItem(ItemIndex: Integer);
var
  item: TDBItem;
  i: Integer;
  sr: TSearchRec;
begin
  item := TDBItem(FDBItems[ItemIndex]);
  // Удаляем каталог и все файлы в нём
  // TODO Здесь нет ни одной проверки на ошибки функций DeleteFile, RemoveDir
  // Считаем, что ошибок не будет - для случая исследовательского это почти всегда верно
  if FindFirst(FCurrentDBDir + item.DirName + '\*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      DeleteFile(FCurrentDBDir + item.DirName + '\' + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(FCurrentDBDir + item.DirName);

  // Удаляем запись из списка
  FDBItems.Delete(ItemIndex);

  // Переименовываем остальные файлы
  if ItemIndex <= FDBItems.Count - 1 then
  begin
    // Производим действия для всех элементов с текущего до предпоследнего
    for i := ItemIndex to FDBItems.Count - 1 do
    begin
      // Перенумеровываем элемент в соответствии с текущим индексом
      item := TDBItem(FDBItems[i]);
      item.N := i + 1;
      // Обновляем всю информацию об элементе на диске
      UpdateDBItem(i);
    end;
  end;
end;

// Процедура для конструирования имени каталога по номеру и тексту предложения
function TDBM.ConstructDirName(N: Integer; Text: String; StrictTemplate: Boolean = False): String;
const
  // Строгий шаблон: Все символы, кроме перечисленных, убираем
  // Первый смивол ^ как раз и означает "все, кроме далее перечисленных
  // Символ - экранирован (\-), так как он имеет специальное значение
  STRICT_TEMPLATE = '[^ \-_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZабвсгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ]';
  // Нестрогий шаблон: Убираем только перечисленные символы
  NON_STRICT_TEMPLATE = '[\\\/\:\*\.\?\"\<\>\|\#\$]';
var
  re: TRegEx;
  s: String;
  template: String;
begin
  //
  re.Create('');

  if StrictTemplate then
    template := STRICT_TEMPLATE
  else
    template := NON_STRICT_TEMPLATE;


  // ВНИМАНИЕ: При изменении кода ниже соответственно поправьте константу DB_SOUNDREC_DIRNAME_MAX_LENGTH

  // Применяем шаблон
  s := re.Replace(Copy(Text, 1, 30), template, '');
  // Пробелы меняем на подчёркивания
  s := re.Replace(s, ' ', '_');
  // Нужно ещё убрать все
  s := Format('%5.5d-%s', [N, s]);

  Result := s;
end;

constructor TDBM.Create(BaseDir: String);
begin
  FBaseDir := BaseDir;
  FCurrentDbIndex := -1;
  FDBItems := TList.Create;
  if not DirectoryExists(BaseDir) then
  begin
    raise Exception.Create(
      Format('Каталог %s недоступен.', [BaseDir])
    );
  end;
  FGetDbList;
end;

procedure TDBM.FGetDBList;
var
  sr: TSearchRec;
begin
  if FDBList = nil then
    FDBList := TStringList.Create
  else
    FDBList.Clear;

  if FindFirst(FBaseDir + '*', faDirectory, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') or
            ((faDirectory and sr.Attr) = 0) then Continue;
      FDBList.Add(sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

function TDBM.FGetIsDBSelected: Boolean;
begin
  Result := FCurrentDBIndex <> -1;
end;

procedure TDBM.JoinWithPrevious(ItemIndex: Integer);
var
  item1, item2: TDBItem;
begin
  // TODO
  // Выход без сообщения об ошибке... Нужно raise
  if ((ItemIndex < 1) or (ItemIndex > FDBItems.Count - 1)) then Exit;

  item1 := TDBItem(FDBItems[ItemIndex - 1]);
  item2 := TDBItem(FDBItems[ItemIndex]);
  item1.Text := item1.Text + ' ' + item2.Text;
  // ... ЧАСТЬ КОДА СКРЫТА
  item1.Comment := item1.Comment + ' ' + item2.Comment;

  UpdateDBItem(ItemIndex - 1);
  DeleteDBItem(ItemIndex);
end;

// ... ЧАСТЬ КОДА СКРЫТА

// Эта процедура вызывается ТОЛЬКО для преобразования версии базы данных 1 к версии 2
// После преобразования всех баз данных вызов этой процедуры надо закомментировать
procedure TDBM.V1ToV2;
var
  item: TDBItem;
  // ... ЧАСТЬ КОДА СКРЫТА
  i: Integer;
  S: String;
begin
  if FCurrentDBVersion <> 1 then Exit;

  // Предупреждение о конвертации
  if MessageDlg('База данных будет конвертирована из формата версии 1 в формат версии 2.' +
    'УБЕДИТЕСЬ В НАЛИЧИИ РЕЗЕРВНОЙ КОПИИ! Продолжить?',
    mtWarning,
    [mbCancel, mbOk],
    0) <> mrOk then
  Exit;
  //
  // ... ЧАСТЬ КОДА СКРЫТА

  // Производим РЕАЛЬНЫЕ изменения
  try
    for i := 0 to FDBItems.Count - 1 do
    begin
      // Обновляем транскрипции
      item := TDBItem(FDBItems.Items[i]);
      // ... ЧАСТЬ КОДА СКРЫТА
      UpdateDBItem(i);
      // Обновляем коды в rrsl.bin
      // ... ЧАСТЬ КОДА СКРЫТА
    end;

    // Сохраняем информацию о версии
    FCurrentDBVersion := 2;
    WriteDBIni;

    // Завершаем работу
    // ... ЧАСТЬ КОДА СКРЫТА

  except
    on E:Exception do
    begin
      MessageDlg(Format('Ошибка конвертации формата базы данных с помощью функции TDBM.V1ToV2: [%s].' +
        ' Восстановите базу из резервной копии, исправьте ошибки и попробуйте снова.',
        [E.Message]),
        mtWarning, [mbOk], 0);
      Exit;
    end;
  end;

end;

// ... ЧАСТЬ КОДА СКРЫТА

// ... ЧАСТЬ КОДА СКРЫТА

end.
