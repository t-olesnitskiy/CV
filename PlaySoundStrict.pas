unit PlaySoundStrict;

{*
   ������ PlaySoundStrict

   �������� �������-������ ��� PlaySound, ������� ���������� ������,
   ����� ���� �� ��������������� �� ������� ������������ ����������� ��������� � ����������� ������

   19.03.2022
   �.����������
*}

interface

// ������� ������� � ���, ��� ������ ���������� ���������� (raise)
// � ������ ���������� ���������� � ���� ���������� ����
procedure MPlaySound(SoundFilename: String; CheckStrict: Boolean = True);
procedure MPlaySoundDialogs(SoundFilename: String; CheckStrict: Boolean = True);

implementation

uses
  SysUtils, Classes, Dialogs,
  MMSystem;

// ������� ���������� ��� ������������ ��������� ��������������� ������� PlaySound
// MPlaySound ����� (��� CheckStrict = True) ������������� ��������� � ���, �����
// �� ��������� "������" ������ �������� �� �� ������ ���������� ������ (�������� �� ����)
procedure MPlaySound(SoundFilename: String; CheckStrict: Boolean = True);
var
  F: TFileStream;
  SampleCount, SamplesPerSec: Integer;
  BitsPerSample, Channels: Smallint;
  HeaderSize: Int64;
  FileSizeExpected: Int64;
begin
  // �������� ������������� �����
  if not FileExists(SoundFilename) then
  begin
    raise Exception.Create(Format(
      'MPlaySound: ���� "%s" �� ������.', [SoundFilename]));
  end;

  // �������� ��������� �����
  if CheckStrict then
  begin
    F := TFileStream.Create(SoundFilename, fmOpenRead);
    try
      ReadWaveHeader(F, SampleCount, SamplesPerSec, BitsPerSample, Channels);
      HeaderSize := F.Position;
      FileSizeExpected := (SampleCount * BitsPerSample * Channels) div 8 + HeaderSize;
      if FileSizeExpected <> F.Size then
        raise Exception.Create(Format(
          'MPlaySound: ���������� � ��������� ����� "%s" � ����������� �� ���������. ������� %d, ��� �� ����� %d, ������� %d. ��������� %d ����. ����� ��������� %d ����, ���������� %d ����.',
          [SoundFilename, SampleCount, BitsPerSample, Channels, HeaderSize, FileSizeExpected, F.Size])
        );
    finally
      if Assigned(F) then F.Free;
    end;
  end;

  // ���������� ������������ ����
  // TODO ����� ����� ���� ���������� Win32API, ������� ���� ������������ ���� �����
  // (������ ����)

//  SetLastError(ERROR_INVALID_PARAMETER);
//  {$WARN SYMBOL_PLATFORM OFF}
//  // � ������ ������ ������ CreateProcess ����� ������������� ���������� Delphi
//  Win32Check(
//    CreateProcess(nil, PWideChar(CmdLine), nil, nil, False,
//      CREATE_DEFAULT_ERROR_MODE {$IFDEF UNICODE}or CREATE_UNICODE_ENVIRONMENT{$ENDIF},
//      nil, nil, SI, PI)
//  );
//  {$WARN SYMBOL_PLATFORM ON}

  PlaySound(PWideChar(SoundFilename), 0, SND_ASYNC);
end;

// ��� ������������� �������
// ������ �� �� �� �����, �� �� ����������� �������� ����� ���������� ����
procedure MPlaySoundDialogs(SoundFilename: String; CheckStrict: Boolean = True);
begin
  try
    MPlaySound(SoundFilename, CheckStrict);
  except
    on E:Exception do
    begin
      MessageDlg(
        Format('������ ��� ������� ��������������� ��������� ����� "%s": %s',
          [SoundFilename, E.Message]),
        mtWarning, [mbOk], 0);
    end;
  end;

end;

end.
