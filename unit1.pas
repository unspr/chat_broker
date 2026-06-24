unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus, Unit2,
  Unit3, IniFiles;

type

  { TForm1 }

  TForm1 = class(TForm)
    Memo1: TMemo;
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FGeminiAPI: TGeminiAPI;
    FAIResponseLine: Integer;
    procedure AppendToMemo(const AText: string);
    function LoadConfig: TStringList;
    procedure OnSSEStart(Sender: TObject);
    procedure OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
    procedure OnSSEError(Sender: TObject; const AError: string);
  public

  end;
const
  EM_SCROLLCARET = $00B7;
var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.AppendToMemo(const AText: string);
begin
  Memo1.Lines.Add(AText);
  Memo1.Lines.Add('');
  Memo1.SelStart := Length(Memo1.Text);
  Memo1.Perform(EM_SCROLLCARET, 0, 0);
end;

function TForm1.LoadConfig: TStringList;
var
  Ini: TIniFile;
  IniFileName: string;
begin
  Result := TStringList.Create;
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);
  try
    Result.Add(Ini.ReadString('AIConfig', 'URL', ''));
    Result.Add(Ini.ReadString('AIConfig', 'Token', ''));
  finally
    Ini.Free;
  end;
end;

procedure TForm1.OnSSEStart(Sender: TObject);
begin
  FAIResponseLine := Memo1.Lines.Add('AI: ');
end;

procedure TForm1.OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
begin
  if AText <> '' then
  begin
    if FAIResponseLine >= 0 then
      Memo1.Lines[FAIResponseLine] := Memo1.Lines[FAIResponseLine] + AText
    else
      Memo1.Lines.Add(AText);
    Memo1.SelStart := Length(Memo1.Text);
    Memo1.Perform(EM_SCROLLCARET, 0, 0);
  end;
  if IsDone then
  begin
    Memo1.Lines.Add('');
    FAIResponseLine := -1;
  end;
end;

procedure TForm1.OnSSEError(Sender: TObject; const AError: string);
begin
  AppendToMemo('Error: ' + AError);
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  Config: TStringList;
  URL, Token: string;
  Prompt: string;
begin
  if Trim(Edit1.Text) = '' then Exit;

  Prompt := Edit1.Text;
  AppendToMemo('me: ' + Prompt);
  Edit1.Clear;

  Config := LoadConfig;
  try
    if Config.Count >= 2 then
    begin
      URL := Config[0];
      Token := Config[1];

      if Trim(URL) = '' then
      begin
        AppendToMemo('Error: URL 未配置');
        Exit;
      end;

      if Trim(Token) = '' then
      begin
        AppendToMemo('Error: Token 未配置');
        Exit;
      end;

      FGeminiAPI.Free;
      FGeminiAPI := TGeminiAPI.Create(URL, Token);
      FGeminiAPI.OnStart := @OnSSEStart;
      FGeminiAPI.OnData := @OnSSEData;
      FGeminiAPI.OnError := @OnSSEError;

      if FGeminiAPI.IsBusy then
      begin
        AppendToMemo('Error: 正在等待上一个请求仍在进行中');
        Exit;
      end;

      FAIResponseLine := -1;
      FGeminiAPI.SendPrompt(Prompt);
    end
    else
    begin
      AppendToMemo('Error: 配置未正确加载');
    end;
  finally
    Config.Free;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if Form2 = nil then
    Form2 := TForm2.Create(Application);
  try
    Form2.ShowModal;
  finally
    Form2.Free;
    Form2 := nil;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Memo1.Clear;
  FAIResponseLine := -1;
  FGeminiAPI := nil;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FGeminiAPI.Free;
end;

end.

