unit DBM;

{*
   ����� TDBM

   ������������ ��� ���������� ����� ������, �������������� ����� ��������� ���������.
   ����� ������������ ���������� ���������, ���������, ������ � ����������
   ���������� �� ����� ��� ���������� ���������� � ���������� ������������� � �.�.

   �� ���� ����� TDBM "������" ������
   ���������� ������ � ����� ������ �� ����������.


   19.03.2023
   �.����������
*}

interface

uses
  Winapi.Windows, System.Classes, System.UITypes,
  RegularExpressions,
  Dialogs;

const
  // ������ ���� ������ "�� ���������", ���� ���� �� �������
  UNKNOWN_DBM_DB_VERSION = 1;
  // ������� ������ ���� ������
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
    // ... ����� ���� ������
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
    // ������ ��������� ��� ������
    property DBList: TStringList read FDBList;
    // ������ ������� ���� ������
    property DBersion: Integer read FCurrentDBVersion;
    // ������ ��������� ������� ���� ������
    property DBItems: TList read FDBItems;
    // ������� ������� ���� ������
    property CurrentDBDir: String read FCurrentDBDir;
    // �������� ������� ���� ������
    property CurrentDBName: String read FCurrentDBName;
    // ... ����� ���� ������
    //
    // ... ����� ���� ������
    //
    property CurrentDBLabel: String read FCurrentDBLabel;
    // �������, ������� �� ���� ������ � ��������� ������
    property IsDBSelected: Boolean read FGetIsDBSelected;
    // ������� ��
    procedure AddDB(DBName: String);
    // ������� ��
    procedure SelectDB(DBName: String);
    // �������� ������� ��
    procedure AddDBItem(var Item: TDBItem; Before: Integer = -1);
    // �������� ������� �� ����� ItemIndex �������� ��� ������������� � DBItems[ItemIndex]
    procedure UpdateDBItem(ItemIndex: Integer; TestOnly: Boolean = False);
    // ������� ������� ��
    procedure DeleteDBItem(ItemIndex: Integer);
    // ���������� ������� � ����������
    procedure JoinWithPrevious(ItemIndex: Integer);
    // ... ����� ���� ������
    // �������� ����������� ���� ������
    function CheckDBIntegrity(var Msg: String; FullCheck: Boolean = False): Boolean;
    //
    procedure V1ToV2;
  end;


implementation

uses
  SysUtils;

{ DBM }

// ������� ���������, ����������� ��� ���������� (���� �� ������������)
function compareByName(Item1 : Pointer; Item2 : Pointer) : Integer;
var
  DBItem1, DBItem2 : TDBItem;
begin
  DBItem1 := TDBItem(Item1);
  DBItem2 := TDBItem(Item2);

  // ������ ��������� �����
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
        Format('�� ������� �������� ���� ������ %s. %s', [DBName, E.Message])
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
    // ������� � ����� ������ ������
    Item.N := FDBItems.Count + 1;
    FDBItems.Add(Item);
    index := FDBItems.Count - 1;
  end
  else
  begin
    index := Before;
    FDBItems.Insert(index, Item);

    // ������� ���������� �������� ��� ���� ���������, ������� ����������� ������
    // ������ � �������� ������� (����� �� ���� �������� � ���������� �����)
    for i := FDBItems.Count - 1 downto index + 1 do
    begin
      citem := TDBItem(FDBItems[i]);
      citem.N := i + 1;
      UpdateDBItem(i);
    end;
  end;

  Item.N := index + 1;
  newdirname := ConstructDirName(Item.N, Item.Text, False);
  // �������� � ���� ������ ���� ��� �� ������
  if DirectoryExists(FCurrentDBDir + newdirname) then
  begin
    raise Exception.Create(Format(
      '������ ��� ������� �������� �������� "%s": ������� ��� ����������. ��������� ����������� ���� ������.',
      [FCurrentDBDir + newdirname]));
  end
  else
  begin
    if not SysUtils.ForceDirectories(FCurrentDBDir + newdirname) then
    begin
      // �������� ������� �������, �� �� ������. ��������, ���� � ��������, ��������� ������
      newdirname2 := ConstructDirName(Item.N, Item.Text, True);
      // �������� � ���� ������ ���� ��� �� ������
      if DirectoryExists(FCurrentDBDir + newdirname2) then
      begin
        raise Exception.Create(Format(
          '������ ��� ������� �������� �������� "%s": ������� ��� ����������. ��������� ����������� ���� ������.',
          [FCurrentDBDir + newdirname2]));
      end
      else
        if not SysUtils.ForceDirectories(FCurrentDBDir + newdirname2) then
        begin
          // �� ������ ������� ������� � �� ������ �������!
          raise Exception.Create(Format(
            '������ ��� �������� �������� ��������� "%s" ("%s") ��� ������ �������� ���� ������. ��������� ����������� �������� ��� ������.',
            [FCurrentDBDir + newdirname, FCurrentDBDir + newdirname2]));
        end
        else
          newdirname := newdirname2;
     end;
  end;

  Item.DirName := newdirname;
  Item.HasSoundRec := False;
  Item.RSL := '';
  // ���������� ������� �������� � ������ ���������� � �� �� ����
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
  // ������� ������� � ��� ����� � ��
  // TODO ����� ��� �� ����� �������� �� ������ ������� DeleteFile, RemoveDir
  // �������, ��� ������ �� ����� - ��� ������ ������������������ ��� ����� ������ �����
  if FindFirst(FCurrentDBDir + item.DirName + '\*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      DeleteFile(FCurrentDBDir + item.DirName + '\' + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(FCurrentDBDir + item.DirName);

  // ������� ������ �� ������
  FDBItems.Delete(ItemIndex);

  // ��������������� ��������� �����
  if ItemIndex <= FDBItems.Count - 1 then
  begin
    // ���������� �������� ��� ���� ��������� � �������� �� ��������������
    for i := ItemIndex to FDBItems.Count - 1 do
    begin
      // ���������������� ������� � ������������ � ������� ��������
      item := TDBItem(FDBItems[i]);
      item.N := i + 1;
      // ��������� ��� ���������� �� �������� �� �����
      UpdateDBItem(i);
    end;
  end;
end;

// ��������� ��� ��������������� ����� �������� �� ������ � ������ �����������
function TDBM.ConstructDirName(N: Integer; Text: String; StrictTemplate: Boolean = False): String;
const
  // ������� ������: ��� �������, ����� �������������, �������
  // ������ ������ ^ ��� ��� � �������� "���, ����� ����� �������������
  // ������ - ����������� (\-), ��� ��� �� ����� ����������� ��������
  STRICT_TEMPLATE = '[^ \-_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ��������������������������������������Ũ��������������������������]';
  // ��������� ������: ������� ������ ������������� �������
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


  // ��������: ��� ��������� ���� ���� �������������� ��������� ��������� DB_SOUNDREC_DIRNAME_MAX_LENGTH

  // ��������� ������
  s := re.Replace(Copy(Text, 1, 30), template, '');
  // ������� ������ �� �������������
  s := re.Replace(s, ' ', '_');
  // ����� ��� ������ ���
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
      Format('������� %s ����������.', [BaseDir])
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
  // ����� ��� ��������� �� ������... ����� raise
  if ((ItemIndex < 1) or (ItemIndex > FDBItems.Count - 1)) then Exit;

  item1 := TDBItem(FDBItems[ItemIndex - 1]);
  item2 := TDBItem(FDBItems[ItemIndex]);
  item1.Text := item1.Text + ' ' + item2.Text;
  // ... ����� ���� ������
  item1.Comment := item1.Comment + ' ' + item2.Comment;

  UpdateDBItem(ItemIndex - 1);
  DeleteDBItem(ItemIndex);
end;

// ... ����� ���� ������

// ��� ��������� ���������� ������ ��� �������������� ������ ���� ������ 1 � ������ 2
// ����� �������������� ���� ��� ������ ����� ���� ��������� ���� ����������������
procedure TDBM.V1ToV2;
var
  item: TDBItem;
  // ... ����� ���� ������
  i: Integer;
  S: String;
begin
  if FCurrentDBVersion <> 1 then Exit;

  // �������������� � �����������
  if MessageDlg('���� ������ ����� �������������� �� ������� ������ 1 � ������ ������ 2.' +
    '��������� � ������� ��������� �����! ����������?',
    mtWarning,
    [mbCancel, mbOk],
    0) <> mrOk then
  Exit;
  //
  // ... ����� ���� ������

  // ���������� �������� ���������
  try
    for i := 0 to FDBItems.Count - 1 do
    begin
      // ��������� ������������
      item := TDBItem(FDBItems.Items[i]);
      // ... ����� ���� ������
      UpdateDBItem(i);
      // ��������� ���� � rrsl.bin
      // ... ����� ���� ������
    end;

    // ��������� ���������� � ������
    FCurrentDBVersion := 2;
    WriteDBIni;

    // ��������� ������
    // ... ����� ���� ������

  except
    on E:Exception do
    begin
      MessageDlg(Format('������ ����������� ������� ���� ������ � ������� ������� TDBM.V1ToV2: [%s].' +
        ' ������������ ���� �� ��������� �����, ��������� ������ � ���������� �����.',
        [E.Message]),
        mtWarning, [mbOk], 0);
      Exit;
    end;
  end;

end;

// ... ����� ���� ������

// ... ����� ���� ������

end.
