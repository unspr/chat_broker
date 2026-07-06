unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus, Unit2,
  Unit3, IniFiles, HtmlView;

type

  { TForm1 }

  TForm1 = class(TForm)
    HtmlViewer1: THtmlViewer;
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FGeminiAPI: TGeminiAPI;
    FAIResponseHTML: TStringList;
    FIsReceivingAI: Boolean;
    procedure AppendToHTML(const AText: string);
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

function EscapeHTML(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

procedure TForm1.AppendToHTML(const AText: string);
var
  UserMessage, AIMessage: string;
begin
  // 将文本转换为简单的 HTML 格式
  UserMessage := '<div style="margin: 10px 0; padding: 5px; background-color: #e3f2fd; border-radius: 5px;">' + 
                 '<strong>me:</strong> ' + EscapeHTML(AText) + '</div>';
  
  if not FIsReceivingAI then
  begin
    FAIResponseHTML.Clear;
    FAIResponseHTML.Add('<!DOCTYPE html><html><head>');
    FAIResponseHTML.Add('<meta charset="UTF-8">');
    FAIResponseHTML.Add('<style>');
    FAIResponseHTML.Add('body { font-family: Arial, sans-serif; margin: 0; padding: 10px; }');
    FAIResponseHTML.Add('.user-msg { margin: 10px 0; padding: 5px; background-color: #e3f2fd; border-radius: 5px; }');
    FAIResponseHTML.Add('.ai-msg { margin: 10px 0; padding: 5px; background-color: #f5f5f5; border-radius: 5px; }');
    FAIResponseHTML.Add('</style>');
    FAIResponseHTML.Add('</head><body>');
    FIsReceivingAI := True;
  end;
  
  // 追加 AI 回复内容
  FAIResponseHTML.Add(AText);
  
  // 更新显示
  HtmlViewer1.LoadFromString(FAIResponseHTML.Text);
  // 滚动到底部 - 使用一个较大的值确保滚到底
  HtmlViewer1.ScrollBy(0, 10000);
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
    Result.Add(Ini.ReadString('Proxy', 'Host', ''));
    Result.Add(Ini.ReadString('Proxy', 'Port', '0'));
  finally
    Ini.Free;
  end;
end;

procedure TForm1.OnSSEStart(Sender: TObject);
begin
  // 开始接收 AI 回复
  FIsReceivingAI := False;
  Button1.Enabled := False; // Disable Button1 when SSE starts
end;

procedure TForm1.OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
begin
  if AText <> '' then
  begin
    // 直接将文本添加到 HTML（后续可以支持 Markdown）
    AppendToHTML(AText);
  end;
  
  if IsDone then
  begin
    // 结束 AI 回复，关闭 HTML 标签
    if FIsReceivingAI then
    begin
      FAIResponseHTML.Add('</body></html>');
      HtmlViewer1.LoadFromString(FAIResponseHTML.Text);
      FIsReceivingAI := False;
    end;
    Button1.Enabled := True; // Enable Button1 when SSE is done
  end;
end;

procedure TForm1.OnSSEError(Sender: TObject; const AError: string);
begin
  AppendToHTML('Error: ' + AError);
  FIsReceivingAI := False;
  Button1.Enabled := True; // Enable Button1 on error
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  Config: TStringList;
  URL, Token: string;
  Prompt: string;
  ProxyHost: string;
  ProxyPort: Word;
begin
  if Trim(Edit1.Text) = '' then Exit;

  Prompt := Edit1.Text;
  
  // 添加用户消息到 HTML
  if not FIsReceivingAI then
  begin
    FAIResponseHTML.Add('<div class="user-msg"><strong>me:</strong> ' + EscapeHTML(Prompt) + '</div>');
    HtmlViewer1.LoadFromString(FAIResponseHTML.Text);
  end;
  
  Edit1.Clear;

  Config := LoadConfig;
  try
    if Config.Count >= 2 then
    begin
      URL := Config[0];
      Token := Config[1];
      ProxyHost := Config[2];
      if Config[3] <> '' then
      begin
         ProxyPort := StrToInt(Config[3]);
      end;

      if Trim(URL) = '' then
      begin
        AppendToHTML('Error: URL 未配置');
        Exit;
      end;

      if Trim(Token) = '' then
      begin
        AppendToHTML('Error: Token 未配置');
        Exit;
      end;

      FGeminiAPI.Free;
      FGeminiAPI := TGeminiAPI.Create(URL, Token, ProxyHost, ProxyPort);
      FGeminiAPI.OnStart := @OnSSEStart;
      FGeminiAPI.OnData := @OnSSEData;
      FGeminiAPI.OnError := @OnSSEError;

      if FGeminiAPI.IsBusy then
      begin
        AppendToHTML('Error: 正在等待上一个请求仍在进行中');
        Exit;
      end;

      FGeminiAPI.SendPrompt(Prompt);
    end
    else
    begin
      AppendToHTML('Error: 配置未正确加载');
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
  FAIResponseHTML := TStringList.Create;
  FIsReceivingAI := False;
  FGeminiAPI := nil;
  
  // 初始化 HTML 文档
  FAIResponseHTML.Add('<!DOCTYPE html><html><head>');
  FAIResponseHTML.Add('<meta charset="UTF-8">');
  FAIResponseHTML.Add('<style>');
  FAIResponseHTML.Add('body { font-family: Arial, sans-serif; margin: 0; padding: 10px; }');
  FAIResponseHTML.Add('.user-msg { margin: 10px 0; padding: 5px; background-color: #e3f2fd; border-radius: 5px; }');
  FAIResponseHTML.Add('.ai-msg { margin: 10px 0; padding: 5px; background-color: #f5f5f5; border-radius: 5px; }');
  FAIResponseHTML.Add('</style>');
  FAIResponseHTML.Add('</head><body>');
  FAIResponseHTML.Add('</body></html>');
  HtmlViewer1.LoadFromString(FAIResponseHTML.Text);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FGeminiAPI.Free;
  FAIResponseHTML.Free;
end;

end.

