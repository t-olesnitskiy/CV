unit PlaySoundStrict;

{*
   Модуль PlaySoundStrict

   Содержит функцию-обёртку для PlaySound, которая нивелизует эффект,
   когда звук не воспроизводится по причине минимального расхождения заголовка и фактических данных

   19.03.2022
   Т.Олесницкий
*}

interface

// Отличия функций в том, что первая генерирует исключения (raise)
// а вторая отображает исключения в виде диалоговых окон
procedure MPlaySound(SoundFilename: String; CheckStrict: Boolean = True);
procedure MPlaySoundDialogs(SoundFilename: String; CheckStrict: Boolean = True);

implementation

uses
  SysUtils, Classes, Dialogs,
  MMSystem;

// Функция исправляет ряд особенностей поведения неинтерактивной функции PlaySound
// MPlaySound умеет (при CheckStrict = True) анализировать заголовок с тем, чтобы
// не допустить "тишины" вместо звучания на не совсем правильных файлах (сообщить об этом)
procedure MPlaySound(SoundFilename: String; CheckStrict: Boolean = True);
var
  F: TFileStream;
  SampleCount, SamplesPerSec: Integer;
  BitsPerSample, Channels: Smallint;
  HeaderSize: Int64;
  FileSizeExpected: Int64;
begin
  // Проверим существование файла
  if not FileExists(SoundFilename) then
  begin
    raise Exception.Create(Format(
      'MPlaySound: Файл "%s" не найден.', [SoundFilename]));
  end;

  // Проверим заголовок файла
  if CheckStrict then
  begin
    F := TFileStream.Create(SoundFilename, fmOpenRead);
    try
      ReadWaveHeader(F, SampleCount, SamplesPerSec, BitsPerSample, Channels);
      HeaderSize := F.Position;
      FileSizeExpected := (SampleCount * BitsPerSample * Channels) div 8 + HeaderSize;
      if FileSizeExpected <> F.Size then
        raise Exception.Create(Format(
          'MPlaySound: Информация в заголовке файла "%s" и фактическая не совпадает. Сэмплов %d, бит на сэмпл %d, каналов %d. Заголовок %d байт. Итого ожидалось %d байт, фактически %d байт.',
          [SoundFilename, SampleCount, BitsPerSample, Channels, HeaderSize, FileSizeExpected, F.Size])
        );
    finally
      if Assigned(F) then F.Free;
    end;
  end;

  // Собственно воспроизведём файл
  // TODO Здесь могут быть исключения Win32API, которые надо обрабатывать чуть иначе
  // (пример ниже)

//  SetLastError(ERROR_INVALID_PARAMETER);
//  {$WARN SYMBOL_PLATFORM OFF}
//  // В случае ошибка вызова CreateProcess будет сгенерировано исключение Delphi
//  Win32Check(
//    CreateProcess(nil, PWideChar(CmdLine), nil, nil, False,
//      CREATE_DEFAULT_ERROR_MODE {$IFDEF UNICODE}or CREATE_UNICODE_ENVIRONMENT{$ENDIF},
//      nil, nil, SI, PI)
//  );
//  {$WARN SYMBOL_PLATFORM ON}

  PlaySound(PWideChar(SoundFilename), 0, SND_ASYNC);
end;

// Это интерактивный вариант
// Делает всё то же самое, но об исключениях сообщает через диалоговое окно
procedure MPlaySoundDialogs(SoundFilename: String; CheckStrict: Boolean = True);
begin
  try
    MPlaySound(SoundFilename, CheckStrict);
  except
    on E:Exception do
    begin
      MessageDlg(
        Format('Ошибка при попытке воспроизведения звукового файла "%s": %s',
          [SoundFilename, E.Message]),
        mtWarning, [mbOk], 0);
    end;
  end;

end;

end.
