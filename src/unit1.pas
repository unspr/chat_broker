unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus, Unit2,
  Unit3, IniFiles, HtmlView, ExtCtrls;

type

  { TForm1 }

  TForm1 = class(TForm)
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FGeminiAPI: TGeminiAPI;
    FMessageContainer: TScrollBox;  // 消息容器 ScrollBox
    FCurrentAIViewer: THtmlViewer;  // 当前正在接收 AI 回复的 HtmlViewer
    FAIContentBuffer: TStringList;   // AI 回复内容缓冲区
    FIsReceivingAI: Boolean;
    FMessageCount: Integer;          // 消息计数器
    procedure CreateUserMessage(const AText: string);
    function CreateAIViewer: THtmlViewer;
    procedure AppendToAIViewer(const AText: string);
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

function GetCSSStyles: string;
begin
  Result := 
    'body { font-family: Arial, sans-serif; margin: 0; padding: 8px; }' + sLineBreak +
    '.user-msg { margin: 5px 0; padding: 8px; background-color: #e3f2fd; border-radius: 5px; }' + sLineBreak +
    '.ai-msg { margin: 5px 0; padding: 8px; background-color: #f5f5f5; border-radius: 5px; }';
end;

procedure TForm1.CreateUserMessage(const AText: string);
var
  Viewer: THtmlViewer;
  HTML: string;
begin
  // 创建 HtmlViewer
  Viewer := THtmlViewer.Create(FMessageContainer);
  Viewer.Parent := FMessageContainer;
  Viewer.Align := alTop;
  Viewer.Height := 60;
  Viewer.ComponentIndex := FMessageContainer.ControlCount - 1;

  // 生成用户消息 HTML
  HTML := '<!DOCTYPE html><html><head>' +
          '<meta charset="UTF-8">' +
          '<style>' + GetCSSStyles + '</style>' +
          '</head><body>' +
          '<div class="user-msg"><strong>me:</strong> ' + EscapeHTML(AText) + '</div>' +
          '</body></html>';
  
  Viewer.LoadFromString(HTML);
  
  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
end;

function TForm1.CreateAIViewer: THtmlViewer;
begin
  // 创建 HtmlViewer
  Result := THtmlViewer.Create(FMessageContainer);
  Result.Parent := FMessageContainer;
  Result.Align := alTop;
  Result.Height := 60;
  Result.ComponentIndex := FMessageContainer.ControlCount - 1;

  // 初始化 HTML 文档
  FAIContentBuffer.Clear;
  FAIContentBuffer.Add('<!DOCTYPE html><html><head>');
  FAIContentBuffer.Add('<meta charset="UTF-8">');
  FAIContentBuffer.Add('<style>' + GetCSSStyles + '</style>');
  FAIContentBuffer.Add('</head><body>');
  FAIContentBuffer.Add('<div class="ai-msg"><strong>AI:</strong> ');
  
  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
end;

procedure TForm1.AppendToAIViewer(const AText: string);
var
  HTML: string;
begin
  if not Assigned(FCurrentAIViewer) then Exit;
  
  // 追加内容到缓冲区
  FAIContentBuffer.Add(AText);
  
  // 临时关闭标签以更新显示
  HTML := FAIContentBuffer.Text + '</div></body></html>';
  FCurrentAIViewer.LoadFromString(HTML);
  
  // 移除临时添加的结束标签
  FAIContentBuffer.Delete(FAIContentBuffer.Count - 1);
  
  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
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
  // 开始接收 AI 回复，创建新的 AI Viewer
  FCurrentAIViewer := CreateAIViewer;
  FIsReceivingAI := True;
  Button1.Enabled := False; // Disable Button1 when SSE starts
end;

procedure TForm1.OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
begin
  if AText <> '' then
  begin
    // 直接将文本添加到当前 AI Viewer
    AppendToAIViewer(AText);
  end;
  
  if IsDone then
  begin
    // 结束 AI 回复，完成 HTML 文档
    if FIsReceivingAI and Assigned(FCurrentAIViewer) then
    begin
      FAIContentBuffer.Add('</div></body></html>');
      FCurrentAIViewer.LoadFromString(FAIContentBuffer.Text);
      FIsReceivingAI := False;
      FCurrentAIViewer := nil;
    end;
    Button1.Enabled := True; // Enable Button1 when SSE is done
  end;
end;

procedure TForm1.OnSSEError(Sender: TObject; const AError: string);
begin
  if FIsReceivingAI then
  begin
    AppendToAIViewer('Error: ' + AError);
    FIsReceivingAI := False;
    FCurrentAIViewer := nil;
  end;
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
  
  // 添加用户消息
  CreateUserMessage(Prompt);
  
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
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: URL 未配置');
        Exit;
      end;

      if Trim(Token) = '' then
      begin
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: Token 未配置');
        Exit;
      end;

      FGeminiAPI.Free;
      FGeminiAPI := TGeminiAPI.Create(URL, Token, ProxyHost, ProxyPort);
      FGeminiAPI.OnStart := @OnSSEStart;
      FGeminiAPI.OnData := @OnSSEData;
      FGeminiAPI.OnError := @OnSSEError;

      if FGeminiAPI.IsBusy then
      begin
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: 正在等待上一个请求仍在进行中');
        Exit;
      end;

      FGeminiAPI.SendPrompt(Prompt);
    end
    else
    begin
      if Assigned(FCurrentAIViewer) then
        AppendToAIViewer('Error: 配置未正确加载');
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
  FAIContentBuffer := TStringList.Create;
  FIsReceivingAI := False;
  FCurrentAIViewer := nil;
  FMessageCount := 0;
  FGeminiAPI := nil;
  
  // 创建消息容器 ScrollBox（带滚动条）
  FMessageContainer := TScrollBox.Create(Self);
  FMessageContainer.Parent := Self;
  FMessageContainer.Left := 0;
  FMessageContainer.Top := 0;
  FMessageContainer.Width := ClientWidth;
  FMessageContainer.Height := ClientHeight - 80;  // 留出底部80像素给输入框和按钮
  FMessageContainer.AutoScroll := True;
  FMessageContainer.VertScrollBar.Tracking := True;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FGeminiAPI.Free;
  FAIContentBuffer.Free;
  // FMessageContainer 会自动释放其子控件
end;

end.

