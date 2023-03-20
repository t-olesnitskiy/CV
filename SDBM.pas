unit SDBM;

{*
   Класс TSDBM

   Предназначен для управления базой данных, представляющей собой классическую БД.
   Класс в том числе "прячет" детали реализации работы с базой данных,
   за счёт чего переход между хранением в различных СУБД
   (например, SQLite и Postgres) может быть незаметным для приложений.

   19.03.2023
   Т.Олесницкий
*}

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.VCLUI.Wait,
  FireDAC.Comp.Client, Data.DB, DataModuleUnit, SParamLines, FireDAC.Phys.PGWrapper,
  FireDAC.Stan.Param, RegularExpressions, MWinExec, Windows;

const
  // Название файл с параметрами подключения к БД
  DEFAULT_SDB_CONNECTION_INI = 'connection.ini';
  // Название тестовой коллекции по умолчанию
  DEFAULT_TEXT_NAME = 'TEST';

  SQL = [
    '1',
    '2'
  ];

  // Названия файлов по умолчанию для приложения визуализации фонем
  FO1_DEFAULT_FILENAME = 'fo1.txt';
  FO2_DEFAULT_FILENAME = 'fo2.txt';
  VISUAL_FO = 'VisualFo.exe';


type
  TElWavType = (ewtElement, ewtAddonNac, ewtAddonKon, ewtElementAndAddons);
  TFoWavType = (fwtElement, fwtBody, fwtExtBody, fwtSchema1, fwtSchema2, fwtElementPlusPrev, fwtElementPlusNext);

  TDictor = class(TObject)
    Id: Integer;    // Поле игнорируется при вставке записи
    Name: String;
  public
    constructor Create(NewId: Integer; NewName: String);
  end;
  TDictors = TList;

  // ... ЧАСТЬ КОДА СКРЫТА

  // Основной класс - для работы с базой данных
  TSDBM = class(TObject)
  private
    FConnectionInfo: String;
    FConnectionIni: String;
    FBaseDir: String;
    function GetElCount: Integer;
  public
    DB: TFDConnection;
    DM: TDM;

    constructor Create(AOwner: TComponent; BaseDir: String; ConnectionIni: String = DEFAULT_SDB_CONNECTION_INI);
    destructor Destroy; override;

    procedure DBDisconnect;

    property ConnectionInfo: String read FConnectionInfo;
    property ElCount: Integer read GetElCount;

    procedure BeginTrans;
    procedure CommitTrans;

    function CreateTables(Recreate: Boolean = False): Boolean;

    // Функции работы с таблицей дикторов
    function GetDictorId(DictorName: String): Integer;
    function GetDictorName(DictorId: Integer): String;
    function GetDictors: TList;
    function InsertDictor(Dictor: TDictor): Integer;

    // Функции для работы с таблицей текстов
    function GetTextId(TextName: String): Integer;
    function GetTexts: TList;
    function InsertText(TextName: String): Integer;

    // Функции для работы с таблицей предложений
    function GetPres: TList;

    // Функции работы с синтезированными элементами
    // TODO

    // Функция удаления фонем предложения (будут добавлены заново)
    procedure DeleteFoPre(dictor_id: Integer;
      text_id: Integer;
      pre_id: Integer);


    // Функции записи элементов
    // Описание параметров - ниже
    function InsertEl(
      // ... ЧАСТЬ КОДА СКРЫТА
      // Переменная, через которую возвращается статус вставки (обновления)
      var Status: Integer
    ): Integer;

    procedure InsertElWav(ElIndex: Integer; WAV: TStream; FieldName: String = 'el');
    function InsertElWavFromFile(ElIndex: Integer; WAVFilename: String; FieldName: String = 'el'): Boolean;

    procedure InsertElRSL(ElIndex: Integer; RSL: TStream);
    function InsertElRSLFromFile(ElIndex: Integer; RSLFilename: String): Boolean;

    //
    procedure UpdateElFo(el_id: Integer; L_sl: Integer; ElFoA: TElFoArray);

    // Функции чтения элементов
    function SelectEl(
      // ... ЧАСТЬ КОДА СКРЫТА
    ): Integer;

    // Функция для получения звука из базы данных
    function GetElWav(el_id: Integer; var WAV: TMemoryStream; ElWavType: TElWavType = ewtElement): Boolean;
    function GetElWavToFile(el_id: Integer; WAVFilename: String; ElWavType: TElWavType = ewtElement): Boolean;
    // И функция для получения звука отдельной фонемы, а не всего элемента
    // Поскольку при этом получаем сначала элемент, а затем из него вырезаем фонему, то в качестве аргументов
    // функции нужно передавать как fo_id, так и el_id (т.к. мы их всё равно оба знаем, чтобы не выполнять лишних запросов)
    function GetFoWav(fo_id: Integer; el_id: Integer; var WAV: TMemoryStream; FoWavType: TFoWavType = fwtElement): Boolean;
    function GetFoWavToFile(fo_id: Integer; el_id: Integer; WAVFilename: String; FoWavType: TFoWavType = fwtElement): Boolean;

    // Отладочные функции (нужны для сравнения производительности в разных сценарях
    procedure DropElIndex;
    // При этом функция CreateElIndex выполняет важнейшую задачу - обеспечение БЫСТРОГО поиска
    // по критериям (всем или части), входящим в индекс
    procedure CreateElIndex;

    // ... ЧАСТЬ КОДА СКРЫТА

  end;

implementation

{ TDictor }

constructor TDictor.Create(NewId: Integer; NewName: String);
begin
  Id := NewId;
  Name := NewName;
end;

{ TSDBM }

procedure TSDBM.BeginTrans;
begin
  DB.StartTransaction;
end;

procedure TSDBM.CommitTrans;
begin
  DB.Commit;
end;

constructor TSDBM.Create(AOwner: TComponent; BaseDir: String; ConnectionIni: String = DEFAULT_SDB_CONNECTION_INI);
const
  PG_LIB_DIR_32 = 'pg_libs';
  PG_LIB_DIR_64 = 'pg_libs_64';
  LIBPQ_DLL = 'libpq.dll';
var
  PgLibDir: String;
  SServer, SPort, SDatabase, SUsername: String;
  index: Integer;
begin

  inherited Create;

  FConnectionIni := ConnectionIni;

  DM := TDM.Create(AOwner);
  DB := DM.SDB;
  // Сейчас фактически не используется
  FBaseDir := BaseDir;

  {*
  Postgres
  см.  http://docwiki.embarcadero.com/RADStudio/Sydney/en/Connect_to_PostgreSQL_(FireDAC)
  см.  http://docwiki.embarcadero.com/RADStudio/Sydney/en/OpenSSL

  FireDAC requires the LIBPQ.DLL x86 or x64 client library for connecting to the PostgreSQL server. Using libpq.dll also requires the "Microsoft Visual C++ 2010 Redistributable Package" installed. You can get this package from http://www.microsoft.com/en-us/download/details.aspx?id=8328. Ideally, the libpq.dll version should be equal to the server version. The full set of the v 9.0 client files:
  libpq.dll
  ssleay32.dll
  libeay32.dll
  libintl-8.dll
  libiconv-2.dll
  оказывается, нужны ещё dll, смотри каталог lib
  *}

  with DB do begin
    if Connected then Close;
    with Params do begin
      Clear;
      try
        DB.Params.LoadFromFile(FConnectionIni, TEncoding.UTF8);
      except
        on E:Exception do
        begin
          FConnectionInfo := 'ошибка загрузки параметров подключения';
          raise Exception.Create('Пожалуйста, проверьте наличие файла параметров подключения к базе данных ' +
            FConnectionIni + '. Ошибка: ' + E.Message);
          Exit;
        end;
      end;
    end;
  end;

  // В процессе открытия соединения может происходить масса ошибок.
  // Мы здесь не будем их разбирать, а просто возвращаем пользователю
  try
    if DB.Params.DriverID = 'PG' then
    begin
      if sizeof(Pointer) = 8 then
        PgLibDir := PG_LIB_DIR_64
      else
        PgLibDir := PG_LIB_DIR_32;
      // А вот если каталогов не существует - не беда, пользователь увидит ошибку при подключении к БД
      if DirectoryExists(PgLibDir) then
      begin
        DM.FDPhysPgDriverLink1.Release;
        DM.FDPhysPgDriverLink1.VendorLib := BaseDir + PgLibDir + '\' + LIBPQ_DLL;
      end;
    end;
    DB.Open;
  except
    on E: Exception do
    begin
      FConnectionInfo := 'ошибка подключения к базе данных';
      raise Exception.Create('Подключение к базе данных не удалось. Проверьте доступность сервера или файла базы данных. Ошибка: ' + E.Message);
      Exit;
    end;
  end;

  if DB.Params.DriverID = 'PG' then
  begin
    try
      index := DB.Params.IndexOfName('Server');
      if index = -1 then SServer := '' else SServer := DB.Params.ValueFromIndex[index];
      index := DB.Params.IndexOfName('Database');
      if index = -1 then SDatabase := '' else SDatabase := DB.Params.ValueFromIndex[index];
      index := DB.Params.IndexOfName('User_Name');
      if index = -1 then SUsername := '' else SUsername := DB.Params.ValueFromIndex[index];
      index := DB.Params.IndexOfName('Port');
      if index = -1 then SPort := '' else SPort := DB.Params.ValueFromIndex[index];

      FConnectionInfo := Format(
        '%s %s %s@%s:%s',
        [DB.Params.DriverID, SDatabase, SUsername, SServer, SPort]
      );
    except
      on E:Exception do FConnectionInfo := '';
    end;
  end;
  if DB.Params.DriverID = 'SQLite' then
  begin
    try
      index := DB.Params.IndexOfName('Database');
      if index = -1 then SDatabase := '' else SDatabase := DB.Params.ValueFromIndex[index];

      FConnectionInfo := Format(
        '%s %s',
        [DB.Params.DriverID, SDatabase]
      );
    except
      on E:Exception do FConnectionInfo := '';
    end;
  end;
  // Если третий параметр

  // Эта замечательная процедура может создавать таблицы и индексы, если база вдруг пустая
  // При этом, конечно, тоже могут происходить ошибки
  try
    CreateTables;
  except
    on E: Exception do
    begin
      raise Exception.Create('Создание (проверка существования) таблиц и индексов не удались. Ошибка: ' + E.Message);
    end;
  end;
end;

destructor TSDBM.Destroy;
begin
  // Обязательно закрыть соединение (если не открыто - ничего не произойдёт)
  DB.Close;
  // DataModule освободить
  DM.Free;
  inherited Destroy;
end;


// Данная функция создаёт таблицы, если они ещё не созданы (пустая БД)
// Также эта процедура может предварительно удалять, т.е. пересоздавать таблицы, если Recreate = True
function TSDBM.CreateTables(Recreate: Boolean = False): Boolean;
begin
  // Если задан параметр "Пересоздать таблицы", то сначала удаляем их
  if Recreate then DM.DropTables(DB.Params.DriverID);

  // Создаём таблицы и индексы
  // Синтаксис операторов отличается в зависимости от используемой СУБД,
  // сейчас поддерживаются только PG и SQLite
  DM.CreateTables(DB.Params.DriverID);

  // TODO
  // А если ещё один движок?

  // К таблицам создаём индексы, это важно!!! (особенно индекс на таблицу el)
  DM.CreateIndexes(DB.Params.DriverID);

  // TODO Возвращаемое значение всегда True
  Result := True;
end;

procedure TSDBM.CreateElIndex;
begin
  DM.CREATE_EL_INDEX.Execute();
end;

procedure TSDBM.DBDisconnect;
begin
  // Отключение от базы данных
  // Вынужденная мера для БД с монопольным доступом, таких как SQLite
  // Происходит после каждого обращения к БД
  if DB.Params.DriverID = 'SQLite' then
    if Assigned(DB) then
      try
        DB.Close;
      except
        // TODO Поскольку при ПЕРВОМ отключении возникает какая-то проблема, она мне не важна,
        // и сложно разобраться, то сделал так.
        sleep(0);
      end;
  // Для полноценных БД, таких как PostgreSQL, отключение не выполняется
end;

procedure TSDBM.DeleteEl(el_id: Integer);
begin
  DB.StartTransaction;
  try
    // Неделимый набор действий по удалению элемента
    // TODO Если используем коллекции, то и оттуда надо удалять - со всеми вытукающими
    // или, лучше, не давать удалять элемент вообще, если он используется в коллекции
    DB.ExecSQL(
      // ... ЧАСТЬ КОДА СКРЫТА,
      [el_id]
    );
    // ... ЧАСТЬ КОДА СКРЫТА
    DB.Commit;
  except
    DM.SDB.Rollback;
    raise;
  end;
end;

procedure TSDBM.DropElIndex;
begin
  DM.DROP_EL_INDEX.Execute();
end;

function TSDBM.GetDictorId(DictorName: String): Integer;
var
  S: String;
begin
  with DM.SELECT_DICTOR do
  begin
    S := SQL.Text;
    // PG поддерживает только UPPERCASE
    if DB.Params.DriverID = 'PG' then
      S := StringReplace(S, '%UCASE%', 'UPPER', [rfReplaceAll]);
    // в SQLite корректно работает только UCASE
    if DB.Params.DriverID = 'SQLite' then
      S := StringReplace(S, '%UCASE%', 'UCASE', [rfReplaceAll]);
    // TODO Третья СУБД...
    SQL.Text := S;
    Params.ParamByName('DICTOR_NAME').Value := DictorName;
    Open;
    if not Eof then
      Result := FieldByName('dictor_id').Value
    else
      Result := -1;
    Close;
  end;
end;

function TSDBM.GetDictorName(DictorId: Integer): String;
var
  AParams: TFDParams;
  AResultSet: TDataSet;
begin
  AParams := TFDParams.Create;
  AParams.Add('dictor_id', DictorId);
  DB.ExecSQL('SELECT dictor_name FROM dictors WHERE dictor_id=:dictor_id;', AParams, AResultSet);
  AParams.Free;

  if AResultSet.Eof then
    raise Exception.Create(Format(
      'Не удалось определить имя диктора по dictor_id=%d в базе данных (%s).',
      [DictorId, Self.ConnectionInfo]));

  Result := AResultSet.FieldByName('dictor_name').AsString;
  AResultSet.Close;
  AResultSet.Free;
end;

function TSDBM.GetDictors: TList;
var
  L: TList;
  D: TDictor;
begin
  L := TList.Create;
  with DM.SELECT_DICTORS do
  begin
    Open();
    while not Eof do
    begin
      D := TDictor.Create(
        FieldByName('dictor_id').Value,
        FieldByName('dictor_name').Value
      );
      L.Add(D);
      Next;
    end;
    Close;
  end;
  Result := L;
end;

function TSDBM.InsertDictor(Dictor: TDictor): Integer;
var
  dictor_id: Integer;
begin
  // Пытаемся найти уже существующего диктора с таким именем
  dictor_id := GetDictorId(Dictor.Name);
  if dictor_id = -1 then
  begin
    // Такого диктора пока нет, добавляем
    with DM.INSERT_DICTOR do
    begin
      ParamByName('dictor_name').Value := Dictor.Name;
      ExecSQL;
    end;
    // Теперь уже должны найти...
    dictor_id := GetDictorId(Dictor.Name);
    // Проверяем, что "текст по умолчанию" существует, при необходимости добавляем
    InsertText(DEFAULT_TEXT_NAME);
  end;
  Result := dictor_id;
end;


{*
  Функции для работы с элементами
*}

function TSDBM.InsertEl(
      // ... ЧАСТЬ КОДА СКРЫТА
      // Переменная, через которую возвращается статус вставки (обновления)
      var Status: Integer
    ): Integer;
var
  // ... ЧАСТЬ КОДА СКРЫТА
begin
  // Устанавливаем значения по умолчанию
  IsReady := False;
  Status := 0;
  Result := -1;

  try
    // ... ЧАСТЬ КОДА СКРЫТА
  
    //
    el_id := -1;

    if DB.Params.DriverID = 'PG' then
    begin
      // TODO
      // Привязка к названию таблицы, имени поля и механизму формирования имени последовательности!
      // Правильнее узнавать имя последовательности для таблицы и использовать его
      el_id := DB.GetLastAutoGenValue('el_el_id_seq');
    end;

    if DB.Params.DriverID = 'SQLite' then
    begin
      el_id := DB.GetLastAutoGenValue('');
    end;

    Result := el_id;

    // ... ЧАСТЬ КОДА СКРЫТА
    //
    DB.Commit;

  except
    DB.Rollback;
    raise;
  end;

end;

procedure TSDBM.InsertElWav(ElIndex: Integer; WAV: TStream; FieldName: String = 'el');
begin
  WAV.Seek(0, 0);

  if FieldName = 'el' then
  begin
    if DB.Params.DriverID = 'SQLite' then
      DM.UPDATE_EL_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    if DB.Params.DriverID = 'PG' then
      DM.UPDATE_EL_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    // TODO Третий тип СУБД
    DM.UPDATE_EL_WAV.ParamByName('EL_ID').AsInteger := ElIndex;
    DM.UPDATE_EL_WAV.ExecSQL;
  end
  else if FieldName = 'el_addon_nac' then
  begin
    if DB.Params.DriverID = 'SQLite' then
      DM.UPDATE_EL_ADDON_NAC_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    if DB.Params.DriverID = 'PG' then
      DM.UPDATE_EL_ADDON_NAC_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    // TODO Третий тип СУБД
    DM.UPDATE_EL_ADDON_NAC_WAV.ParamByName('EL_ID').AsInteger := ElIndex;
    DM.UPDATE_EL_ADDON_NAC_WAV.ExecSQL;
  end
  else if FieldName =  'el_addon_kon' then
  begin
    if DB.Params.DriverID = 'SQLite' then
      DM.UPDATE_EL_ADDON_KON_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    if DB.Params.DriverID = 'PG' then
      DM.UPDATE_EL_ADDON_KON_WAV.ParamByName('WAV').LoadFromStream(WAV, ftVarBytes);
    // TODO Третий тип СУБД
    DM.UPDATE_EL_ADDON_KON_WAV.ParamByName('EL_ID').AsInteger := ElIndex;
    DM.UPDATE_EL_ADDON_KON_WAV.ExecSQL;
  end
  else
  begin
    raise Exception.Create(Format(
      'Неизвестный аргумент функции TSDBM.InsertElWav: FieldName=%s, ElIndex=%d.',
      [FieldName, ElIndex]
    ));
  end;
end;

function TSDBM.InsertElWavFromFile(ElIndex: Integer;
  WAVFilename: String; FieldName: String = 'el'): Boolean;
var
  FS: TFileStream;
begin
  Result := True;
  // TODO Явно неверная конструкция, вызванная смешением разных подходов к обработке ошибок
  try
    try
      FS := TFileStream.Create(WAVFilename, fmCreate or fmOpenWrite);
      InsertElWav(ElIndex, FS, FieldName);
    except
      // TODO
      Result := False;
    end;
  finally
    FS.Free;
  end;
end;


end.

